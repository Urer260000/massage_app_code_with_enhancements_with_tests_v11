const crypto = require('crypto');
const express = require('express');
const cors = require('cors');
const helmet = require('helmet');
const jwt = require('jsonwebtoken');
const bcrypt = require('bcryptjs');
const rateLimit = require('express-rate-limit');
const { z } = require('zod');
const { DateTime } = require('luxon');

const { HttpError, ConflictError } = require('./errors');
const { loadSpaConfig } = require('./config');
const schedule = require('./schedule');
const { appointmentIcs } = require('./mailer');

const ACCESS_TTL = '15m';
const REFRESH_TTL = '30d';
const CODE_TTL_MINUTES = 15;
const MAX_CODE_ATTEMPTS = 5;

// The most common leaked passwords. A real deployment could also check haveibeenpwned.com.
const COMMON_PASSWORDS = new Set([
  '12345678', '123456789', '1234567890', 'password', 'password1', 'password123', 'passw0rd',
  'qwerty123', 'qwertyuiop', '11111111', '00000000', 'iloveyou', 'abc12345', 'abcd1234',
  'letmein1', 'welcome1', 'sunshine', 'football', 'baseball', 'princess', 'trustno1',
  '1q2w3e4r', 'admin123', 'qwerty12', 'aa123456', 'monkey12', 'dragon12', 'superman',
]);

// ---------- Request validation ----------

const email = z.string().trim().toLowerCase().email('Please enter a valid email address.').max(254);
const password = z
  .string()
  .min(8, 'Password must be at least 8 characters.')
  .max(128, 'Password must be at most 128 characters.')
  .refine((p) => !COMMON_PASSWORDS.has(p.toLowerCase()), 'That password is too common. Please choose another.');
const username = z.string().trim().min(1, 'Please enter your name.').max(60, 'Name must be at most 60 characters.');
const isoDate = z.string().refine((s) => !Number.isNaN(Date.parse(s)), 'A valid startsAt date is required.');
const day = z.string().regex(/^\d{4}-\d{2}-\d{2}$/, 'date must look like YYYY-MM-DD.');
const code = z.string().trim().regex(/^\d{6}$/, 'Enter the 6-digit code.');

const schemas = {
  register: z.object({ username, email, password }),
  login: z.object({ email, password: z.string().min(1, 'Email and password are required.').max(128) }),
  refresh: z.object({ refreshToken: z.string().min(1) }),
  forgot: z.object({ email }),
  reset: z.object({ email, code, newPassword: password }),
  updateMe: z.object({ username }),
  changePassword: z.object({ currentPassword: z.string().min(1).max(128), newPassword: password }),
  deleteMe: z.object({ password: z.string().min(1, 'Enter your password to confirm.').max(128) }),
  verify: z.object({ code }),
  book: z.object({
    serviceId: z.string().min(1).max(64),
    startsAt: isoDate,
    therapistId: z.string().max(64).optional(),
    notes: z.string().trim().max(500, 'Notes must be at most 500 characters.').optional(),
    pressure: z.enum(['light', 'medium', 'firm']).optional(),
  }),
  reschedule: z.object({ startsAt: isoDate, therapistId: z.string().max(64).optional() }),
  review: z.object({
    rating: z.number().int().min(1, 'Rating must be 1 to 5.').max(5, 'Rating must be 1 to 5.'),
    comment: z.string().trim().max(1000).optional(),
  }),
  waitlist: z.object({ serviceId: z.string().min(1).max(64), date: day }),
  adminStatus: z.object({ status: z.enum(['confirmed', 'completed', 'no_show', 'cancelled']) }),
  adminBlock: z.object({
    therapistId: z.string().min(1).max(64),
    startsAt: isoDate,
    durationMinutes: z.number().int().min(15).max(12 * 60),
    reason: z.string().trim().max(120).optional(),
  }),
  adminService: z
    .object({
      name: z.string().trim().min(1).max(80),
      signature: z.string().trim().max(80),
      description: z.string().trim().max(500),
      price: z.number().min(0).max(10000),
      durationMinutes: z.number().int().min(15).max(240),
      active: z.boolean(),
    })
    .partial(),
};

/** Parses req.body (or req.query) with [schema]; a 400 with the first problem otherwise. */
function parse(schema, data) {
  const result = schema.safeParse(data ?? {});
  if (result.success) return result.data;
  const issue = result.error.issues[0];
  const missing = issue.code === 'invalid_type' && issue.received === 'undefined';
  throw new HttpError(400, missing ? `${issue.path.join('.') || 'body'} is required.` : issue.message);
}

const route = (fn) => (req, res, next) => Promise.resolve(fn(req, res, next)).catch(next);

const hash = (value) => crypto.createHash('sha256').update(value).digest('hex');
const newCode = () => String(crypto.randomInt(0, 1_000_000)).padStart(6, '0');

// ---------- App ----------

function createApp({
  store,
  jwtSecret,
  spa = loadSpaConfig(),
  mailer = { console: true, outbox: [], async send() {} },
  logger = { info() {}, warn() {}, error() {} },
  rateLimitMax = 300,
  authRateLimitMax = 20,
  corsOrigins = [],
  trustProxy = false,
  exposeDevCodes = false,
  adminEmails = [],
  now = () => new Date(),
}) {
  if (!store) throw new Error('createApp requires a store');
  if (!jwtSecret) throw new Error('createApp requires a jwtSecret');

  const app = express();
  if (trustProxy) app.set('trust proxy', trustProxy);
  app.disable('x-powered-by');
  app.use(helmet({ crossOriginResourcePolicy: { policy: 'cross-origin' } }));
  app.use(
    cors({
      // No list configured: allow any origin (fine for local development).
      origin: corsOrigins.length ? corsOrigins : true,
    }),
  );
  app.use(express.json({ limit: '20kb' }));
  app.use(rateLimit({ windowMs: 15 * 60 * 1000, limit: rateLimitMax, standardHeaders: 'draft-7', legacyHeaders: false }));

  // Much stricter limit for anything that checks a password or a code.
  const authLimiter = rateLimit({
    windowMs: 15 * 60 * 1000,
    limit: authRateLimitMax,
    standardHeaders: 'draft-7',
    legacyHeaders: false,
    message: { message: 'Too many attempts. Please wait a few minutes and try again.' },
  });

  const adminSet = new Set(adminEmails.map((e) => e.toLowerCase()));

  // ---------- Helpers ----------

  const signTokens = (user) => ({
    token: jwt.sign({ sub: user.id, typ: 'access', ver: user.tokenVersion || 0 }, jwtSecret, {
      expiresIn: ACCESS_TTL,
    }),
    refreshToken: jwt.sign({ sub: user.id, typ: 'refresh', ver: user.tokenVersion || 0 }, jwtSecret, {
      expiresIn: REFRESH_TTL,
    }),
  });

  const publicUser = (user) => ({
    id: user.id,
    username: user.username,
    email: user.email,
    role: user.role || 'guest',
    emailVerified: Boolean(user.emailVerified),
  });

  const authResponse = (user, extra = {}) => ({ user: publicUser(user), ...signTokens(user), ...extra });

  async function verifyToken(token, typ) {
    let payload;
    try {
      payload = jwt.verify(token, jwtSecret);
    } catch (err) {
      throw new HttpError(401, err.name === 'TokenExpiredError' ? 'Session expired.' : 'Unauthorized', {
        code: err.name === 'TokenExpiredError' ? 'token_expired' : 'unauthorized',
      });
    }
    if (payload.typ !== typ) throw new HttpError(401, 'Unauthorized', { code: 'unauthorized' });
    const user = await store.findUserById(payload.sub);
    // Signing out, changing password or deleting the account bumps tokenVersion, voiding old tokens.
    if (!user || (user.tokenVersion || 0) !== payload.ver) {
      throw new HttpError(401, 'Unauthorized', { code: 'unauthorized' });
    }
    return user;
  }

  const requireAuth = route(async (req, res, next) => {
    const header = req.header('Authorization') || '';
    const token = header.startsWith('Bearer ') ? header.slice(7) : '';
    if (!token) throw new HttpError(401, 'Unauthorized', { code: 'unauthorized' });
    req.user = await verifyToken(token, 'access');
    req.userId = req.user.id;
    next();
  });

  const requireAdmin = (req, res, next) =>
    req.user && req.user.role === 'admin' ? next() : next(new HttpError(403, 'Staff only.'));

  const nowDT = () => DateTime.fromJSDate(now());

  async function sendMail(message) {
    try {
      await mailer.send(message);
    } catch (err) {
      logger.error({ err }, 'Failed to send email');
    }
  }

  /** Sends a one-time code and remembers its hash on the user. */
  async function issueCode(user, purpose, subject, intro) {
    const value = newCode();
    await store.updateUser(user.id, {
      [`${purpose}CodeHash`]: hash(`${user.id}:${value}`),
      [`${purpose}CodeExpires`]: nowDT().plus({ minutes: CODE_TTL_MINUTES }).toISO(),
      [`${purpose}CodeAttempts`]: 0,
    });
    await sendMail({
      to: user.email,
      subject,
      text: `${intro}\n\nYour code: ${value}\n\nIt expires in ${CODE_TTL_MINUTES} minutes.\n\n- ${spa.name}`,
    });
    return exposeDevCodes && mailer.console ? { devCode: value } : {};
  }

  async function checkCode(user, purpose, value) {
    const expires = user[`${purpose}CodeExpires`];
    const attempts = user[`${purpose}CodeAttempts`] || 0;
    const valid =
      user[`${purpose}CodeHash`] &&
      expires &&
      DateTime.fromISO(expires) > nowDT() &&
      attempts < MAX_CODE_ATTEMPTS &&
      user[`${purpose}CodeHash`] === hash(`${user.id}:${value}`);
    if (!valid) {
      await store.updateUser(user.id, { [`${purpose}CodeAttempts`]: attempts + 1 });
      throw new HttpError(400, 'That code is wrong or has expired.');
    }
    await store.updateUser(user.id, { [`${purpose}CodeHash`]: null, [`${purpose}CodeExpires`]: null });
  }

  const cutoffPassed = (a) =>
    DateTime.fromISO(a.startsAt).diff(nowDT(), 'hours').hours < spa.cancelCutoffHours;

  function view(a, { withGuest } = {}) {
    const local = schedule.localParts(a.startsAt, spa);
    const isPast = DateTime.fromISO(a.endsAt || a.startsAt) <= nowDT();
    const out = {
      id: a.id,
      kind: a.kind || 'booking',
      serviceId: a.serviceId,
      serviceName: a.serviceName,
      price: a.price,
      durationMinutes: a.durationMinutes,
      therapistId: a.therapistId,
      therapistName: a.therapistName,
      startsAt: a.startsAt,
      endsAt: a.endsAt,
      localDate: local.date,
      localTime: local.time,
      status: a.status || 'confirmed',
      notes: a.notes || null,
      pressure: a.pressure || null,
      review: a.review || null,
      isPast,
      canChange: (a.status || 'confirmed') === 'confirmed' && !isPast && !cutoffPassed(a),
    };
    if (withGuest) {
      out.guestName = a.guestName || null;
      out.guestEmail = a.guestEmail || null;
    }
    return out;
  }

  async function activeService(serviceId) {
    const service = await store.getService(serviceId);
    if (!service || service.active === false) throw new HttpError(404, 'Service not found.');
    return service;
  }

  /** Therapists who can give [service]; just one when the guest picked someone. */
  async function teamFor(service, therapistId) {
    const team = (await store.listTherapists()).filter((t) => t.serviceIds.includes(service.id));
    if (!therapistId || therapistId === 'any') return team;
    const chosen = team.find((t) => t.id === therapistId);
    if (!chosen) throw new HttpError(400, 'That therapist does not offer this treatment.');
    return [chosen];
  }

  const busyKeySet = (busy) => new Set(busy.map((b) => `${b.therapistId}|${b.block}`));

  function slotsForDay(service, dayDT, team, busy) {
    return schedule.candidateStarts(dayDT, service.durationMinutes, spa).map((t) => {
      const keys = schedule.blocksFor(t.toJSDate(), service.durationMinutes, spa);
      const free = team.filter((th) => keys.every((k) => !busy.has(`${th.id}|${k}`)));
      return {
        time: t.toFormat('HH:mm'),
        startsAt: t.toUTC().toISO(),
        available: free.length > 0 && schedule.withinWindow(t, spa, now()),
        therapistIds: free.map((th) => th.id),
      };
    });
  }

  /** Tries each therapist in turn until one can take the booking. */
  async function claimWithTeam(team, attempt) {
    for (const therapist of team) {
      try {
        return await attempt(therapist);
      } catch (err) {
        if (!(err instanceof ConflictError)) throw err;
      }
    }
    throw new HttpError(409, 'Sorry, that time has just been taken. Please pick another.');
  }

  /** Lets waitlisted guests know a spot opened on [date]. */
  async function notifyWaitlist(date) {
    const entries = await store.listWaitlist({ date });
    for (const entry of entries) {
      await sendMail({
        to: entry.email,
        subject: `A spot opened up on ${date}`,
        text: `Good news: a reservation on ${date} has just become free. Open the app to grab it.\n\n- ${spa.name}`,
      });
      await store.removeFromWaitlist(entry.id);
    }
  }

  function bookingEmail(user, a, heading) {
    const local = schedule.localParts(a.startsAt, spa);
    return {
      to: user.email,
      subject: `${heading}: ${a.serviceName} on ${local.date} at ${local.time}`,
      text:
        `Hello ${user.username},\n\n${heading}.\n\n` +
        `${a.serviceName} with ${a.therapistName}\n${local.date} at ${local.time} (${spa.timezone})\n` +
        `${spa.address}\n\nNeed to change it? You can cancel or reschedule in the app up to ` +
        `${spa.cancelCutoffHours} hours before. After that, please call ${spa.phone}.\n\n- ${spa.name}`,
      attachments: [{ filename: 'reservation.ics', content: appointmentIcs(a, spa), contentType: 'text/calendar' }],
    };
  }

  async function ownAppointment(req) {
    const a = await store.getAppointment(req.params.id);
    if (!a || a.userId !== req.userId || a.kind === 'block') throw new HttpError(404, 'Reservation not found.');
    return a;
  }

  // ---------- Routes ----------

  const api = express.Router();

  api.get('/health', (req, res) => res.json({ status: 'ok' }));

  api.get('/spa', (req, res) => {
    const { name, timezone, openHour, closeHour, slotMinutes, maxDaysAhead, closedWeekdays, cancelCutoffHours, address, phone, email: spaEmail, about } = spa;
    res.json({
      spa: { name, timezone, openHour, closeHour, slotMinutes, maxDaysAhead, closedWeekdays, cancelCutoffHours, address, phone, email: spaEmail, about },
    });
  });

  // Auth

  api.post('/register', authLimiter, route(async (req, res) => {
    const input = parse(schemas.register, req.body);
    const timestamp = now().toISOString();
    const user = await store.createUser({
      username: input.username,
      email: input.email,
      password: await bcrypt.hash(input.password, 10),
      role: adminSet.has(input.email) ? 'admin' : 'guest',
      emailVerified: false,
      tokenVersion: 0,
      createdAt: timestamp,
      updatedAt: timestamp,
    });
    const extra = await issueCode(user, 'verify', `Welcome to ${spa.name}`, `Welcome, ${user.username}! Please confirm your email with the code below.`);
    res.status(201).json({ message: 'User registered successfully', ...authResponse(user), ...extra });
  }));

  api.post('/login', authLimiter, route(async (req, res) => {
    const input = parse(schemas.login, req.body);
    const user = await store.findUserByEmail(input.email);
    if (!user || !(await bcrypt.compare(input.password, user.password))) {
      throw new HttpError(401, 'Invalid email or password.');
    }
    res.json(authResponse(user));
  }));

  api.post('/auth/refresh', authLimiter, route(async (req, res) => {
    const { refreshToken } = parse(schemas.refresh, req.body);
    const user = await verifyToken(refreshToken, 'refresh');
    res.json(authResponse(user));
  }));

  api.post('/logout', requireAuth, route(async (req, res) => {
    await store.updateUser(req.userId, { tokenVersion: (req.user.tokenVersion || 0) + 1 });
    res.json({ message: 'Signed out.' });
  }));

  api.post('/password/forgot', authLimiter, route(async (req, res) => {
    const input = parse(schemas.forgot, req.body);
    const user = await store.findUserByEmail(input.email);
    let extra = {};
    if (user) {
      extra = await issueCode(user, 'reset', `Reset your ${spa.name} password`, 'Someone asked to reset your password. If it was you, use this code.');
    }
    // Same answer either way, so this can't be used to find out who has an account.
    res.json({ message: 'If that email has an account, we have sent a reset code.', ...extra });
  }));

  api.post('/password/reset', authLimiter, route(async (req, res) => {
    const input = parse(schemas.reset, req.body);
    const user = await store.findUserByEmail(input.email);
    if (!user) throw new HttpError(400, 'That code is wrong or has expired.');
    await checkCode(user, 'reset', input.code);
    const updated = await store.updateUser(user.id, {
      password: await bcrypt.hash(input.newPassword, 10),
      tokenVersion: (user.tokenVersion || 0) + 1,
      emailVerified: true, // they proved they can read the inbox
      updatedAt: now().toISOString(),
    });
    res.json({ message: 'Password updated.', ...authResponse(updated) });
  }));

  // Account

  api.get('/me', requireAuth, (req, res) => res.json({ user: publicUser(req.user) }));

  api.patch('/me', requireAuth, route(async (req, res) => {
    const input = parse(schemas.updateMe, req.body);
    const user = await store.updateUser(req.userId, { username: input.username, updatedAt: now().toISOString() });
    res.json({ user: publicUser(user) });
  }));

  api.post('/me/password', requireAuth, authLimiter, route(async (req, res) => {
    const input = parse(schemas.changePassword, req.body);
    if (!(await bcrypt.compare(input.currentPassword, req.user.password))) {
      throw new HttpError(400, 'Your current password is not right.');
    }
    const user = await store.updateUser(req.userId, {
      password: await bcrypt.hash(input.newPassword, 10),
      tokenVersion: (req.user.tokenVersion || 0) + 1,
      updatedAt: now().toISOString(),
    });
    res.json({ message: 'Password changed.', ...authResponse(user) });
  }));

  api.post('/me/verify-email', requireAuth, authLimiter, route(async (req, res) => {
    const input = parse(schemas.verify, req.body);
    if (!req.user.emailVerified) await checkCode(req.user, 'verify', input.code);
    const user = await store.updateUser(req.userId, { emailVerified: true });
    res.json({ user: publicUser(user) });
  }));

  api.post('/me/verify-email/resend', requireAuth, authLimiter, route(async (req, res) => {
    if (req.user.emailVerified) return res.json({ message: 'Your email is already confirmed.' });
    const extra = await issueCode(req.user, 'verify', `Confirm your ${spa.name} email`, 'Here is a new code to confirm your email.');
    return res.json({ message: 'We have sent a new code.', ...extra });
  }));

  api.delete('/me', requireAuth, authLimiter, route(async (req, res) => {
    const input = parse(schemas.deleteMe, req.body);
    if (!(await bcrypt.compare(input.password, req.user.password))) {
      throw new HttpError(400, 'That password is not right.');
    }
    await store.deleteUser(req.userId);
    res.json({ message: 'Your account and reservations have been deleted.' });
  }));

  // Menu, team, availability

  api.get('/services', route(async (req, res) => {
    res.json({ services: await store.listServices() });
  }));

  api.get('/therapists', route(async (req, res) => {
    const all = await store.listTherapists();
    const serviceId = typeof req.query.serviceId === 'string' ? req.query.serviceId : null;
    res.json({ therapists: serviceId ? all.filter((t) => t.serviceIds.includes(serviceId)) : all });
  }));

  api.get('/availability', route(async (req, res) => {
    const service = await activeService(String(req.query.serviceId || ''));
    const dayDT = schedule.parseDay(req.query.date, spa);
    if (!dayDT) throw new HttpError(400, 'date must look like YYYY-MM-DD.');
    const team = await teamFor(service, req.query.therapistId);
    const busy = busyKeySet(await store.busyBlocks(dayDT.toUTC().toISO(), dayDT.plus({ days: 1 }).toUTC().toISO()));
    res.json({ date: dayDT.toISODate(), timezone: spa.timezone, slots: slotsForDay(service, dayDT, team, busy) });
  }));

  api.get('/availability/days', route(async (req, res) => {
    const service = await activeService(String(req.query.serviceId || ''));
    const team = await teamFor(service, req.query.therapistId);
    const days = schedule.bookableDays(spa, now());
    const busy = busyKeySet(
      await store.busyBlocks(days[0].toUTC().toISO(), days[days.length - 1].plus({ days: 1 }).toUTC().toISO()),
    );
    res.json({
      timezone: spa.timezone,
      days: days.map((d) => {
        const slots = slotsForDay(service, d, team, busy);
        return { date: d.toISODate(), weekday: d.weekday, available: slots.some((s) => s.available), freeSlots: slots.filter((s) => s.available).length };
      }),
    });
  }));

  // Reservations

  api.get('/appointments', requireAuth, route(async (req, res) => {
    const scope = ['upcoming', 'past'].includes(req.query.scope) ? req.query.scope : 'all';
    const limit = Math.min(Math.max(Number.parseInt(req.query.limit, 10) || 50, 1), 100);
    const offset = Math.max(Number.parseInt(req.query.offset, 10) || 0, 0);
    let list = (await store.listAppointments({ userId: req.userId }, { order: scope === 'past' ? 'desc' : 'asc' }))
      .filter((a) => a.kind !== 'block')
      .map((a) => view(a));
    const upcoming = (a) => a.status === 'confirmed' && !a.isPast;
    if (scope === 'upcoming') list = list.filter(upcoming);
    if (scope === 'past') list = list.filter((a) => !upcoming(a));
    const page = list.slice(offset, offset + limit);
    res.json({ appointments: page, nextOffset: offset + limit < list.length ? offset + limit : null });
  }));

  api.post('/appointments', requireAuth, route(async (req, res) => {
    const input = parse(schemas.book, req.body);
    const service = await activeService(input.serviceId);
    const reason = schedule.checkStart(input.startsAt, service.durationMinutes, spa, now());
    if (reason) throw new HttpError(400, reason);
    const team = await teamFor(service, input.therapistId);
    const start = DateTime.fromISO(new Date(input.startsAt).toISOString(), { zone: 'utc' });
    const blocks = schedule.blocksFor(start.toJSDate(), service.durationMinutes, spa);
    const timestamp = now().toISOString();

    const appointment = await claimWithTeam(team, (therapist) =>
      store.createAppointment(
        {
          kind: 'booking',
          userId: req.userId,
          guestName: req.user.username,
          guestEmail: req.user.email,
          serviceId: service.id,
          serviceName: service.name,
          price: service.price,
          durationMinutes: service.durationMinutes,
          therapistId: therapist.id,
          therapistName: therapist.name,
          startsAt: start.toISO(),
          endsAt: start.plus({ minutes: service.durationMinutes }).toISO(),
          status: 'confirmed',
          notes: input.notes || null,
          pressure: input.pressure || null,
          createdAt: timestamp,
          updatedAt: timestamp,
        },
        blocks,
      ),
    );
    await sendMail(bookingEmail(req.user, appointment, 'Your reservation is confirmed'));
    res.status(201).json({ appointment: view(appointment) });
  }));

  api.get('/appointments/:id/ics', requireAuth, route(async (req, res) => {
    const a = await ownAppointment(req);
    res.type('text/calendar').attachment('reservation.ics').send(appointmentIcs(a, spa));
  }));

  api.patch('/appointments/:id', requireAuth, route(async (req, res) => {
    const input = parse(schemas.reschedule, req.body);
    const current = await ownAppointment(req);
    if (!view(current).canChange) {
      throw new HttpError(400, `Reservations can be changed up to ${spa.cancelCutoffHours} hours before. Please call ${spa.phone}.`);
    }
    const service = (await store.getService(current.serviceId)) || current;
    const duration = current.durationMinutes || service.durationMinutes;
    const reason = schedule.checkStart(input.startsAt, duration, spa, now());
    if (reason) throw new HttpError(400, reason);
    const team = await teamFor({ id: current.serviceId }, input.therapistId);
    const start = DateTime.fromISO(new Date(input.startsAt).toISOString(), { zone: 'utc' });
    const blocks = schedule.blocksFor(start.toJSDate(), duration, spa);

    const moved = await claimWithTeam(team, (therapist) =>
      store.moveAppointment(
        current.id,
        {
          therapistId: therapist.id,
          therapistName: therapist.name,
          startsAt: start.toISO(),
          endsAt: start.plus({ minutes: duration }).toISO(),
          reminder24SentAt: null,
          reminder2SentAt: null,
          updatedAt: now().toISOString(),
        },
        blocks,
      ),
    );
    await sendMail(bookingEmail(req.user, moved, 'Your reservation has moved'));
    await notifyWaitlist(schedule.localParts(current.startsAt, spa).date);
    res.json({ appointment: view(moved) });
  }));

  api.delete('/appointments/:id', requireAuth, route(async (req, res) => {
    const current = await ownAppointment(req);
    if (!view(current).canChange) {
      throw new HttpError(400, `Reservations can be cancelled up to ${spa.cancelCutoffHours} hours before. Please call ${spa.phone}.`);
    }
    const cancelled = await store.releaseAppointment(current.id, {
      status: 'cancelled',
      cancelledAt: now().toISOString(),
      updatedAt: now().toISOString(),
    });
    await sendMail({ ...bookingEmail(req.user, cancelled, 'Your reservation is cancelled') });
    await notifyWaitlist(schedule.localParts(current.startsAt, spa).date);
    res.json({ appointment: view(cancelled) });
  }));

  api.post('/appointments/:id/review', requireAuth, route(async (req, res) => {
    const input = parse(schemas.review, req.body);
    const current = await ownAppointment(req);
    const v = view(current);
    if (!v.isPast || !['confirmed', 'completed'].includes(v.status)) {
      throw new HttpError(400, 'You can review a treatment once it has finished.');
    }
    if (current.review) throw new HttpError(409, 'You have already reviewed this treatment.');
    const updated = await store.updateAppointment(current.id, {
      review: { rating: input.rating, comment: input.comment || null, createdAt: now().toISOString() },
    });
    res.status(201).json({ appointment: view(updated) });
  }));

  // Waitlist

  api.get('/waitlist', requireAuth, route(async (req, res) => {
    res.json({ waitlist: await store.listWaitlist({ userId: req.userId }) });
  }));

  api.post('/waitlist', requireAuth, route(async (req, res) => {
    const input = parse(schemas.waitlist, req.body);
    await activeService(input.serviceId);
    const dayDT = schedule.parseDay(input.date, spa);
    if (!dayDT || !schedule.bookableDays(spa, now()).some((d) => d.equals(dayDT))) {
      throw new HttpError(400, 'Pick a date within the booking window.');
    }
    const entry = await store.addToWaitlist({
      userId: req.userId,
      email: req.user.email,
      serviceId: input.serviceId,
      date: input.date,
      createdAt: now().toISOString(),
    });
    res.status(201).json({ entry, message: "You're on the waitlist. We'll email you if a spot opens." });
  }));

  api.delete('/waitlist/:id', requireAuth, route(async (req, res) => {
    const mine = await store.listWaitlist({ userId: req.userId });
    if (!mine.some((w) => w.id === req.params.id)) throw new HttpError(404, 'Not found.');
    await store.removeFromWaitlist(req.params.id);
    res.json({ message: 'Removed from the waitlist.' });
  }));

  // Staff

  const admin = express.Router();
  admin.use(requireAuth, requireAdmin);

  admin.get('/appointments', route(async (req, res) => {
    const dayDT = req.query.date ? schedule.parseDay(req.query.date, spa) : schedule.today(spa, now());
    if (!dayDT) throw new HttpError(400, 'date must look like YYYY-MM-DD.');
    const list = await store.listAppointments({
      from: dayDT.toUTC().toISO(),
      to: dayDT.plus({ days: 1 }).toUTC().toISO(),
    });
    res.json({
      date: dayDT.toISODate(),
      timezone: spa.timezone,
      therapists: await store.listTherapists(),
      appointments: list.map((a) => view(a, { withGuest: true })),
    });
  }));

  admin.patch('/appointments/:id', route(async (req, res) => {
    const input = parse(schemas.adminStatus, req.body);
    const current = await store.getAppointment(req.params.id);
    if (!current) throw new HttpError(404, 'Reservation not found.');
    const patch = { status: input.status, updatedAt: now().toISOString() };
    let updated;
    if (['no_show', 'cancelled'].includes(input.status)) {
      updated = await store.releaseAppointment(current.id, patch);
      if (input.status === 'cancelled') await notifyWaitlist(schedule.localParts(current.startsAt, spa).date);
    } else {
      updated = await store.updateAppointment(current.id, patch);
    }
    res.json({ appointment: view(updated, { withGuest: true }) });
  }));

  admin.post('/blocks', route(async (req, res) => {
    const input = parse(schemas.adminBlock, req.body);
    const therapist = (await store.listTherapists()).find((t) => t.id === input.therapistId);
    if (!therapist) throw new HttpError(400, 'Unknown therapist.');
    const start = DateTime.fromISO(new Date(input.startsAt).toISOString(), { zone: 'utc' });
    if (start.setZone(spa.timezone).minute % spa.slotMinutes !== 0) {
      throw new HttpError(400, `Blocks must start on a ${spa.slotMinutes}-minute boundary.`);
    }
    const blocks = schedule.blocksFor(start.toJSDate(), input.durationMinutes, spa);
    let block;
    try {
      block = await store.createAppointment(
        {
          kind: 'block',
          userId: req.userId,
          serviceId: null,
          serviceName: input.reason ? `Blocked: ${input.reason}` : 'Blocked',
          durationMinutes: input.durationMinutes,
          therapistId: therapist.id,
          therapistName: therapist.name,
          startsAt: start.toISO(),
          endsAt: start.plus({ minutes: input.durationMinutes }).toISO(),
          status: 'confirmed',
          createdAt: now().toISOString(),
          updatedAt: now().toISOString(),
        },
        blocks,
      );
    } catch (err) {
      if (err instanceof ConflictError) throw new HttpError(409, `${therapist.name} already has a booking in that time.`);
      throw err;
    }
    res.status(201).json({ appointment: view(block, { withGuest: true }) });
  }));

  admin.get('/services', route(async (req, res) => {
    res.json({ services: await store.listServices({ includeInactive: true }) });
  }));

  admin.patch('/services/:id', route(async (req, res) => {
    const input = parse(schemas.adminService, req.body);
    const updated = await store.updateService(req.params.id, input);
    if (!updated) throw new HttpError(404, 'Service not found.');
    res.json({ service: updated });
  }));

  api.use('/admin', admin);

  // Same routes with and without a version prefix; new clients should use /v1.
  app.use('/v1', api);
  app.use('/', api);

  app.use((req, res) => res.status(404).json({ message: 'Not found.' }));

  // One place that turns errors into `{ message }` responses.
  // eslint-disable-next-line no-unused-vars
  app.use((err, req, res, next) => {
    if (err instanceof HttpError) return res.status(err.status).json({ message: err.message, ...err.extra });
    if (err instanceof ConflictError) return res.status(409).json({ message: err.message });
    if (err.type === 'entity.parse.failed') return res.status(400).json({ message: 'Invalid JSON body.' });
    if (err.type === 'entity.too.large') return res.status(413).json({ message: 'Request is too large.' });
    logger.error({ err, path: req.path }, 'Unhandled error');
    return res.status(500).json({ message: 'Something went wrong. Please try again.' });
  });

  return app;
}

module.exports = { createApp, COMMON_PASSWORDS };
