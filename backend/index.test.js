const request = require('supertest');
const jwt = require('jsonwebtoken');
const { createApp } = require('./app');
const { createMemoryStore } = require('./store');
const { loadSpaConfig } = require('./config');
const { sendReminders } = require('./reminders');
const schedule = require('./schedule');

// Monday 7 January 2030, 10:00 in New York (15:00 UTC).
const NOW = new Date('2030-01-07T15:00:00Z');
const spa = loadSpaConfig({ SPA_TIMEZONE: 'America/New_York' });
const SECRET = 'test-secret';

function makeApp(options = {}) {
  const store = options.store || createMemoryStore();
  const outbox = [];
  const mailer = { console: true, outbox, send: async (m) => { outbox.push(m); } };
  let clock = options.now || NOW;
  const app = createApp({
    store,
    jwtSecret: SECRET,
    spa,
    mailer,
    exposeDevCodes: true,
    authRateLimitMax: options.authRateLimitMax || 1000,
    adminEmails: ['boss@the20sspa.com'],
    now: () => clock,
  });
  app.store = store;
  app.outbox = outbox;
  app.setNow = (d) => { clock = d; };
  return app;
}

const register = (app, overrides = {}) =>
  request(app)
    .post('/register')
    .send({ username: 'testuser', email: 'test@email.com', password: 'testpassword', ...overrides });

async function signedIn(app, overrides) {
  const res = await register(app, overrides);
  return { auth: `Bearer ${res.body.token}`, body: res.body };
}

/** New York wall-clock time -> UTC ISO string. */
const ny = (date, time) =>
  require('luxon').DateTime.fromISO(`${date}T${time}`, { zone: 'America/New_York' }).toUTC().toISO();

const book = (app, auth, body) => request(app).post('/appointments').set('Authorization', auth).send(body);

describe('POST /register', () => {
  it('creates a user and returns tokens', async () => {
    const res = await register(makeApp());
    expect(res.statusCode).toBe(201);
    expect(res.body).toHaveProperty('token');
    expect(res.body).toHaveProperty('refreshToken');
    expect(res.body.user).toMatchObject({ username: 'testuser', email: 'test@email.com', role: 'guest', emailVerified: false });
    expect(res.body.user).not.toHaveProperty('password');
  });

  it('rejects missing fields', async () => {
    const res = await request(makeApp()).post('/register').send({ email: 'a@b.com' });
    expect(res.statusCode).toBe(400);
  });

  it('rejects an invalid email', async () => {
    const res = await register(makeApp(), { email: 'not-an-email' });
    expect(res.statusCode).toBe(400);
  });

  it('rejects short and common passwords', async () => {
    expect((await register(makeApp(), { password: 'short1' })).statusCode).toBe(400);
    const common = await register(makeApp(), { password: 'password123' });
    expect(common.statusCode).toBe(400);
    expect(common.body.message).toMatch(/too common/);
  });

  it('rejects wrong types instead of crashing', async () => {
    const res = await request(makeApp()).post('/register').send({ username: 'x', email: 42, password: { a: 1 } });
    expect(res.statusCode).toBe(400);
  });

  it('rejects a duplicate email, even sent at the same time', async () => {
    const app = makeApp();
    const [a, b] = await Promise.all([register(app), register(app, { email: 'TEST@email.com' })]);
    expect([a.statusCode, b.statusCode].sort()).toEqual([201, 409]);
  });

  it('gives staff emails the admin role', async () => {
    const res = await register(makeApp(), { email: 'boss@the20sspa.com' });
    expect(res.body.user.role).toBe('admin');
  });

  it('answers bad JSON with 400', async () => {
    const res = await request(makeApp()).post('/register').set('Content-Type', 'application/json').send('{bad');
    expect(res.statusCode).toBe(400);
  });
});

describe('login and sessions', () => {
  it('logs in with correct credentials', async () => {
    const app = makeApp();
    await register(app);
    const res = await request(app).post('/login').send({ email: 'test@email.com', password: 'testpassword' });
    expect(res.statusCode).toBe(200);
    expect(res.body).toHaveProperty('token');
  });

  it('rejects a wrong password', async () => {
    const app = makeApp();
    await register(app);
    const res = await request(app).post('/login').send({ email: 'test@email.com', password: 'nope-nope' });
    expect(res.statusCode).toBe(401);
  });

  it('rate-limits repeated login attempts', async () => {
    const app = makeApp({ authRateLimitMax: 3 });
    const attempt = () => request(app).post('/login').send({ email: 'x@y.com', password: 'whatever1' });
    for (let i = 0; i < 3; i++) expect((await attempt()).statusCode).toBe(401);
    expect((await attempt()).statusCode).toBe(429);
  });

  it('flags expired access tokens and refreshes them', async () => {
    const app = makeApp();
    const { body } = await signedIn(app);
    const expired = jwt.sign({ sub: body.user.id, typ: 'access', ver: 0, exp: Math.floor(Date.now() / 1000) - 10 }, SECRET);
    const res = await request(app).get('/me').set('Authorization', `Bearer ${expired}`);
    expect(res.statusCode).toBe(401);
    expect(res.body.code).toBe('token_expired');

    const refreshed = await request(app).post('/auth/refresh').send({ refreshToken: body.refreshToken });
    expect(refreshed.statusCode).toBe(200);
    const me = await request(app).get('/me').set('Authorization', `Bearer ${refreshed.body.token}`);
    expect(me.body.user.email).toBe('test@email.com');
  });

  it('does not accept a refresh token as an access token', async () => {
    const app = makeApp();
    const { body } = await signedIn(app);
    const res = await request(app).get('/me').set('Authorization', `Bearer ${body.refreshToken}`);
    expect(res.statusCode).toBe(401);
  });

  it('signing out voids existing tokens', async () => {
    const app = makeApp();
    const { auth, body } = await signedIn(app);
    expect((await request(app).post('/logout').set('Authorization', auth)).statusCode).toBe(200);
    expect((await request(app).get('/me').set('Authorization', auth)).statusCode).toBe(401);
    expect((await request(app).post('/auth/refresh').send({ refreshToken: body.refreshToken })).statusCode).toBe(401);
  });

  it('serves the same API under /v1', async () => {
    const res = await request(makeApp()).get('/v1/services');
    expect(res.statusCode).toBe(200);
  });

  it('sets security headers', async () => {
    const res = await request(makeApp()).get('/health');
    expect(res.headers['x-content-type-options']).toBe('nosniff');
    expect(res.headers['x-powered-by']).toBeUndefined();
  });
});

describe('password reset and email verification', () => {
  it('resets a password with an emailed code', async () => {
    const app = makeApp();
    await register(app);
    const forgot = await request(app).post('/password/forgot').send({ email: 'test@email.com' });
    expect(forgot.statusCode).toBe(200);
    expect(app.outbox.at(-1).text).toContain(forgot.body.devCode);

    const wrong = await request(app).post('/password/reset').send({ email: 'test@email.com', code: '000000', newPassword: 'brand-new-pass' });
    expect(wrong.statusCode).toBe(400);
    const reset = await request(app).post('/password/reset').send({ email: 'test@email.com', code: forgot.body.devCode, newPassword: 'brand-new-pass' });
    expect(reset.statusCode).toBe(200);
    const login = await request(app).post('/login').send({ email: 'test@email.com', password: 'brand-new-pass' });
    expect(login.statusCode).toBe(200);
    // A code works only once.
    const again = await request(app).post('/password/reset').send({ email: 'test@email.com', code: forgot.body.devCode, newPassword: 'another-pass-1' });
    expect(again.statusCode).toBe(400);
  });

  it('gives the same answer for unknown emails', async () => {
    const res = await request(makeApp()).post('/password/forgot').send({ email: 'nobody@email.com' });
    expect(res.statusCode).toBe(200);
    expect(res.body.devCode).toBeUndefined();
  });

  it('verifies an email with the sign-up code', async () => {
    const app = makeApp();
    const { auth, body } = await signedIn(app);
    const bad = await request(app).post('/me/verify-email').set('Authorization', auth).send({ code: '123' });
    expect(bad.statusCode).toBe(400);
    const ok = await request(app).post('/me/verify-email').set('Authorization', auth).send({ code: body.devCode });
    expect(ok.body.user.emailVerified).toBe(true);
  });
});

describe('account', () => {
  it('updates the name and changes the password', async () => {
    const app = makeApp();
    const { auth } = await signedIn(app);
    const named = await request(app).patch('/me').set('Authorization', auth).send({ username: 'Daisy' });
    expect(named.body.user.username).toBe('Daisy');

    const wrong = await request(app).post('/me/password').set('Authorization', auth).send({ currentPassword: 'nope', newPassword: 'fresh-pass-99' });
    expect(wrong.statusCode).toBe(400);
    const changed = await request(app).post('/me/password').set('Authorization', auth).send({ currentPassword: 'testpassword', newPassword: 'fresh-pass-99' });
    expect(changed.statusCode).toBe(200);
    // Old tokens stop working; the response carries new ones.
    expect((await request(app).get('/me').set('Authorization', auth)).statusCode).toBe(401);
    expect((await request(app).get('/me').set('Authorization', `Bearer ${changed.body.token}`)).statusCode).toBe(200);
  });

  it('deletes the account and its reservations', async () => {
    const app = makeApp();
    const { auth } = await signedIn(app);
    await book(app, auth, { serviceId: 'swedish-60', startsAt: ny('2030-01-08', '10:00') });
    const refused = await request(app).delete('/me').set('Authorization', auth).send({ password: 'wrong' });
    expect(refused.statusCode).toBe(400);
    const res = await request(app).delete('/me').set('Authorization', auth).send({ password: 'testpassword' });
    expect(res.statusCode).toBe(200);
    expect((await request(app).post('/login').send({ email: 'test@email.com', password: 'testpassword' })).statusCode).toBe(401);
    expect(await app.store.busyBlocks('2030-01-01T00:00:00Z', '2030-02-01T00:00:00Z')).toHaveLength(0);
  });
});

describe('menu, team and availability', () => {
  it('lists services and spa info without auth', async () => {
    const app = makeApp();
    const services = await request(app).get('/services');
    expect(services.body.services.length).toBeGreaterThan(0);
    const info = await request(app).get('/spa');
    expect(info.body.spa).toMatchObject({ timezone: 'America/New_York', openHour: 10, closeHour: 20 });
  });

  it('lists therapists for a treatment', async () => {
    const res = await request(makeApp()).get('/therapists?serviceId=sports-45');
    expect(res.body.therapists.map((t) => t.id).sort()).toEqual(['louis', 'zelda']);
  });

  it('only offers times where the whole treatment fits before closing', async () => {
    const res = await request(makeApp()).get('/availability?serviceId=hot-stone-90&date=2030-01-08');
    const times = res.body.slots.map((s) => s.time);
    expect(times[0]).toBe('10:00');
    expect(times.at(-1)).toBe('18:30'); // 90 minutes from 18:30 ends at 20:00
    expect(res.body.slots.every((s) => s.available)).toBe(true);
  });

  it('marks past and too-soon slots on today as unavailable', async () => {
    const res = await request(makeApp()).get('/availability?serviceId=swedish-60&date=2030-01-07');
    const slot = (t) => res.body.slots.find((s) => s.time === t);
    expect(slot('10:00').available).toBe(false); // now
    expect(slot('10:30').available).toBe(true); // 30 minutes' notice
  });

  it('shows the booking window day by day', async () => {
    const res = await request(makeApp()).get('/availability/days?serviceId=swedish-60');
    expect(res.body.days).toHaveLength(21);
    expect(res.body.days[0].date).toBe('2030-01-07');
  });

  it('hides a slot once every suitable therapist is booked', async () => {
    const app = makeApp();
    const a = await signedIn(app, { email: 'a@email.com' });
    const b = await signedIn(app, { email: 'b@email.com' });
    const startsAt = ny('2030-01-08', '14:00');
    // Sports massage: Louis and Zelda only.
    expect((await book(app, a.auth, { serviceId: 'sports-45', startsAt })).statusCode).toBe(201);
    expect((await book(app, b.auth, { serviceId: 'sports-45', startsAt })).statusCode).toBe(201);
    const res = await request(app).get('/availability?serviceId=sports-45&date=2030-01-08');
    expect(res.body.slots.find((s) => s.time === '14:00').available).toBe(false);
    // Evelyn is still free for a Swedish massage then.
    const swedish = await request(app).get('/availability?serviceId=swedish-60&date=2030-01-08');
    expect(swedish.body.slots.find((s) => s.time === '14:00').therapistIds).toEqual(['evelyn']);
  });
});

describe('booking rules', () => {
  it('requires auth', async () => {
    const res = await request(makeApp()).get('/appointments');
    expect(res.statusCode).toBe(401);
  });

  it('books and lists an appointment with price, length and therapist', async () => {
    const app = makeApp();
    const { auth } = await signedIn(app);
    const booked = await book(app, auth, { serviceId: 'swedish-60', startsAt: ny('2030-01-08', '15:00'), notes: 'Sore left shoulder', pressure: 'firm' });
    expect(booked.statusCode).toBe(201);
    expect(booked.body.appointment).toMatchObject({
      serviceName: 'Swedish Massage',
      price: 80,
      durationMinutes: 60,
      localDate: '2030-01-08',
      localTime: '15:00',
      status: 'confirmed',
      notes: 'Sore left shoulder',
      pressure: 'firm',
      canChange: true,
    });
    expect(booked.body.appointment.endsAt).toBe(ny('2030-01-08', '16:00'));
    expect(app.outbox.at(-1).subject).toMatch(/confirmed/);
    expect(app.outbox.at(-1).attachments[0].content).toContain('BEGIN:VEVENT');

    const list = await request(app).get('/appointments').set('Authorization', auth);
    expect(list.body.appointments).toHaveLength(1);
  });

  it('never double-books a therapist, even when two guests confirm at once', async () => {
    const app = makeApp();
    const guests = await Promise.all(
      ['a', 'b', 'c'].map((n) => signedIn(app, { email: `${n}@email.com` })),
    );
    const startsAt = ny('2030-01-08', '11:00');
    const results = await Promise.all(
      guests.map((g) => book(app, g.auth, { serviceId: 'sports-45', startsAt })),
    );
    // Two therapists do sports massage, so exactly two bookings succeed.
    expect(results.map((r) => r.statusCode).sort()).toEqual([201, 201, 409]);
    const therapists = results.filter((r) => r.statusCode === 201).map((r) => r.body.appointment.therapistId);
    expect(new Set(therapists).size).toBe(2);
  });

  it('blocks overlapping treatments for the same therapist', async () => {
    const app = makeApp();
    const a = await signedIn(app, { email: 'a@email.com' });
    const b = await signedIn(app, { email: 'b@email.com' });
    expect((await book(app, a.auth, { serviceId: 'hot-stone-90', startsAt: ny('2030-01-08', '12:00'), therapistId: 'evelyn' })).statusCode).toBe(201);
    // 12:30 overlaps Evelyn's 12:00-13:30 hot stone.
    const clash = await book(app, b.auth, { serviceId: 'swedish-60', startsAt: ny('2030-01-08', '12:30'), therapistId: 'evelyn' });
    expect(clash.statusCode).toBe(409);
    // 13:30 is fine.
    expect((await book(app, b.auth, { serviceId: 'swedish-60', startsAt: ny('2030-01-08', '13:30'), therapistId: 'evelyn' })).statusCode).toBe(201);
  });

  it('enforces opening hours, the slot grid and the booking window', async () => {
    const app = makeApp();
    const { auth } = await signedIn(app);
    const reject = async (startsAt, serviceId = 'swedish-60') => {
      const res = await book(app, auth, { serviceId, startsAt });
      expect(res.statusCode).toBe(400);
      return res.body.message;
    };
    await reject(ny('2030-01-08', '03:00')); // before opening
    await reject(ny('2030-01-08', '19:30')); // would end after closing
    await reject(ny('2030-01-08', '18:45'), 'hot-stone-90'); // off the grid
    await reject(ny('2030-03-01', '10:00')); // too far ahead
    await reject(ny('2030-01-07', '10:15')); // less than 30 minutes' notice
    expect(await reject('2000-01-01T10:00:00Z')).toMatch(/future/);
    await reject('not-a-date');
  });

  it('rejects unknown services and therapists who do not offer the treatment', async () => {
    const app = makeApp();
    const { auth } = await signedIn(app);
    const startsAt = ny('2030-01-08', '10:00');
    expect((await book(app, auth, { serviceId: 'nope', startsAt })).statusCode).toBe(404);
    expect((await book(app, auth, { serviceId: 'sports-45', startsAt, therapistId: 'evelyn' })).statusCode).toBe(400);
  });

  it('uses the spa time zone, not the guest\'s', async () => {
    const app = makeApp();
    const { auth } = await signedIn(app);
    // 10:00 in New York is 15:00 UTC; 10:00 UTC would be 05:00 at the spa.
    expect((await book(app, auth, { serviceId: 'swedish-60', startsAt: '2030-01-08T10:00:00Z' })).statusCode).toBe(400);
    expect((await book(app, auth, { serviceId: 'swedish-60', startsAt: '2030-01-08T15:00:00Z' })).statusCode).toBe(201);
  });

  it('splits reservations into upcoming and past', async () => {
    const app = makeApp();
    const { auth } = await signedIn(app);
    await book(app, auth, { serviceId: 'swedish-60', startsAt: ny('2030-01-08', '10:00') });
    await book(app, auth, { serviceId: 'swedish-60', startsAt: ny('2030-01-09', '10:00') });
    app.setNow(new Date(ny('2030-01-08', '12:00')));
    const upcoming = await request(app).get('/appointments?scope=upcoming').set('Authorization', auth);
    const past = await request(app).get('/appointments?scope=past').set('Authorization', auth);
    expect(upcoming.body.appointments.map((a) => a.localDate)).toEqual(['2030-01-09']);
    expect(past.body.appointments.map((a) => a.localDate)).toEqual(['2030-01-08']);
  });

  it('pages long lists', async () => {
    const app = makeApp();
    const { auth } = await signedIn(app);
    for (const t of ['10:00', '11:00', '12:00']) await book(app, auth, { serviceId: 'swedish-60', startsAt: ny('2030-01-08', t) });
    const first = await request(app).get('/appointments?limit=2').set('Authorization', auth);
    expect(first.body.appointments).toHaveLength(2);
    expect(first.body.nextOffset).toBe(2);
    const second = await request(app).get('/appointments?limit=2&offset=2').set('Authorization', auth);
    expect(second.body.appointments).toHaveLength(1);
    expect(second.body.nextOffset).toBeNull();
  });
});

describe('cancel and reschedule', () => {
  async function setup() {
    const app = makeApp();
    const { auth } = await signedIn(app);
    const res = await book(app, auth, { serviceId: 'swedish-60', startsAt: ny('2030-01-09', '10:00'), therapistId: 'evelyn' });
    return { app, auth, id: res.body.appointment.id };
  }

  it('reschedules and frees the old time', async () => {
    const { app, auth, id } = await setup();
    const moved = await request(app).patch(`/appointments/${id}`).set('Authorization', auth).send({ startsAt: ny('2030-01-10', '11:00') });
    expect(moved.statusCode).toBe(200);
    expect(moved.body.appointment).toMatchObject({ localDate: '2030-01-10', localTime: '11:00' });
    const old = await request(app).get('/availability?serviceId=swedish-60&date=2030-01-09&therapistId=evelyn');
    expect(old.body.slots.find((s) => s.time === '10:00').available).toBe(true);
  });

  it('can move a booking to overlap its own old time', async () => {
    const { app, auth, id } = await setup();
    const moved = await request(app).patch(`/appointments/${id}`).set('Authorization', auth).send({ startsAt: ny('2030-01-09', '10:30'), therapistId: 'evelyn' });
    expect(moved.statusCode).toBe(200);
  });

  it('keeps the original when the new time is taken', async () => {
    const { app, auth, id } = await setup();
    const other = await signedIn(app, { email: 'other@email.com' });
    await book(app, other.auth, { serviceId: 'swedish-60', startsAt: ny('2030-01-10', '10:00'), therapistId: 'evelyn' });
    const res = await request(app).patch(`/appointments/${id}`).set('Authorization', auth).send({ startsAt: ny('2030-01-10', '10:00'), therapistId: 'evelyn' });
    expect(res.statusCode).toBe(409);
    const again = await book(app, other.auth, { serviceId: 'swedish-60', startsAt: ny('2030-01-09', '10:00'), therapistId: 'evelyn' });
    expect(again.statusCode).toBe(409); // still held by the original booking
  });

  it('cancels, frees the slot and tells the waitlist', async () => {
    const { app, auth, id } = await setup();
    const waiter = await signedIn(app, { email: 'waiter@email.com' });
    const joined = await request(app).post('/waitlist').set('Authorization', waiter.auth).send({ serviceId: 'swedish-60', date: '2030-01-09' });
    expect(joined.statusCode).toBe(201);

    const res = await request(app).delete(`/appointments/${id}`).set('Authorization', auth);
    expect(res.statusCode).toBe(200);
    expect(res.body.appointment.status).toBe('cancelled');
    expect(app.outbox.some((m) => m.to === 'waiter@email.com' && /spot opened/.test(m.subject))).toBe(true);
    const slots = await request(app).get('/availability?serviceId=swedish-60&date=2030-01-09&therapistId=evelyn');
    expect(slots.body.slots.find((s) => s.time === '10:00').available).toBe(true);
    const waitlist = await request(app).get('/waitlist').set('Authorization', waiter.auth);
    expect(waitlist.body.waitlist).toHaveLength(0);
  });

  it('refuses changes inside the cancellation window', async () => {
    const { app, auth, id } = await setup();
    app.setNow(new Date(ny('2030-01-08', '12:00'))); // 22 hours before
    const res = await request(app).delete(`/appointments/${id}`).set('Authorization', auth);
    expect(res.statusCode).toBe(400);
    expect(res.body.message).toMatch(/24 hours/);
  });

  it("can't touch someone else's reservation", async () => {
    const { app, id } = await setup();
    const other = await signedIn(app, { email: 'other@email.com' });
    expect((await request(app).delete(`/appointments/${id}`).set('Authorization', other.auth)).statusCode).toBe(404);
  });

  it('serves a calendar file', async () => {
    const { app, auth, id } = await setup();
    const res = await request(app).get(`/appointments/${id}/ics`).set('Authorization', auth);
    expect(res.headers['content-type']).toMatch(/text\/calendar/);
    expect(res.text).toContain('DTSTART:20300109T150000Z');
  });
});

describe('reviews', () => {
  it('accepts one review after the treatment', async () => {
    const app = makeApp();
    const { auth } = await signedIn(app);
    const booked = await book(app, auth, { serviceId: 'swedish-60', startsAt: ny('2030-01-08', '10:00') });
    const id = booked.body.appointment.id;
    const early = await request(app).post(`/appointments/${id}/review`).set('Authorization', auth).send({ rating: 5 });
    expect(early.statusCode).toBe(400);
    app.setNow(new Date(ny('2030-01-08', '12:00')));
    const res = await request(app).post(`/appointments/${id}/review`).set('Authorization', auth).send({ rating: 5, comment: 'The bee\'s knees' });
    expect(res.statusCode).toBe(201);
    expect(res.body.appointment.review.rating).toBe(5);
    const twice = await request(app).post(`/appointments/${id}/review`).set('Authorization', auth).send({ rating: 4 });
    expect(twice.statusCode).toBe(409);
    const bad = await request(app).post(`/appointments/${id}/review`).set('Authorization', auth).send({ rating: 9 });
    expect(bad.statusCode).toBe(400);
  });
});

describe('staff', () => {
  async function setup() {
    const app = makeApp();
    const staff = await signedIn(app, { email: 'boss@the20sspa.com', username: 'Boss' });
    const guest = await signedIn(app, { email: 'guest@email.com', username: 'Daisy' });
    return { app, staff, guest };
  }

  it('is closed to guests', async () => {
    const { app, guest } = await setup();
    expect((await request(app).get('/admin/appointments').set('Authorization', guest.auth)).statusCode).toBe(403);
  });

  it("lists the day's bookings with guest details and marks no-shows", async () => {
    const { app, staff, guest } = await setup();
    const booked = await book(app, guest.auth, { serviceId: 'swedish-60', startsAt: ny('2030-01-08', '10:00'), notes: 'Allergic to lavender' });
    const day = await request(app).get('/admin/appointments?date=2030-01-08').set('Authorization', staff.auth);
    expect(day.body.appointments).toHaveLength(1);
    expect(day.body.appointments[0]).toMatchObject({ guestName: 'Daisy', guestEmail: 'guest@email.com', notes: 'Allergic to lavender' });

    const res = await request(app).patch(`/admin/appointments/${booked.body.appointment.id}`).set('Authorization', staff.auth).send({ status: 'no_show' });
    expect(res.body.appointment.status).toBe('no_show');
  });

  it('blocks out time so guests cannot book it', async () => {
    const { app, staff } = await setup();
    const res = await request(app).post('/admin/blocks').set('Authorization', staff.auth).send({ therapistId: 'louis', startsAt: ny('2030-01-08', '10:00'), durationMinutes: 600, reason: 'Training' });
    expect(res.statusCode).toBe(201);
    const slots = await request(app).get('/availability?serviceId=deep-tissue-60&date=2030-01-08&therapistId=louis');
    expect(slots.body.slots.every((s) => !s.available)).toBe(true);
  });

  it('edits prices, and hidden treatments drop off the menu', async () => {
    const { app, staff } = await setup();
    const res = await request(app).patch('/admin/services/sports-45').set('Authorization', staff.auth).send({ price: 75, active: false });
    expect(res.body.service).toMatchObject({ price: 75, active: false });
    const menu = await request(app).get('/services');
    expect(menu.body.services.find((s) => s.id === 'sports-45')).toBeUndefined();
    const all = await request(app).get('/admin/services').set('Authorization', staff.auth);
    expect(all.body.services.find((s) => s.id === 'sports-45').price).toBe(75);
  });
});

describe('reminders', () => {
  it('sends a 24-hour and a 2-hour reminder once each', async () => {
    const app = makeApp();
    const { auth } = await signedIn(app);
    await book(app, auth, { serviceId: 'swedish-60', startsAt: ny('2030-01-08', '10:00') });
    const outbox = [];
    const mailer = { send: async (m) => { outbox.push(m); } };
    const run = (iso) => sendReminders({ store: app.store, mailer, spa, logger: console, now: new Date(iso) });

    expect(await run(ny('2030-01-07', '09:00'))).toBe(0); // 25 hours ahead
    expect(await run(ny('2030-01-07', '10:30'))).toBe(1);
    expect(await run(ny('2030-01-07', '11:00'))).toBe(0);
    expect(await run(ny('2030-01-08', '08:30'))).toBe(1);
    expect(await run(ny('2030-01-08', '09:00'))).toBe(0);
    expect(outbox.map((m) => m.subject)).toEqual([
      'Reminder: Swedish Massage tomorrow',
      'Reminder: Swedish Massage in two hours',
    ]);
  });
});

describe('schedule', () => {
  it('handles the daylight-saving change', () => {
    // 10 March 2030: clocks go forward in New York.
    const day = schedule.parseDay('2030-03-10', spa);
    const starts = schedule.candidateStarts(day, 60, spa);
    expect(starts[0].toUTC().toISO()).toBe('2030-03-10T14:00:00.000Z');
  });

  it('honours closed weekdays', () => {
    const closed = { ...spa, closedWeekdays: [2] }; // Tuesdays
    expect(schedule.candidateStarts(schedule.parseDay('2030-01-08', closed), 60, closed)).toHaveLength(0);
  });
});
