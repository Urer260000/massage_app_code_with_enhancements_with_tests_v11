const express = require('express');
const cors = require('cors');
const jwt = require('jsonwebtoken');
const bcrypt = require('bcryptjs');
const rateLimit = require('express-rate-limit');

const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

function createApp({ store, jwtSecret, rateLimitMax = 100 }) {
  if (!store) throw new Error('createApp requires a store');
  if (!jwtSecret) throw new Error('createApp requires a jwtSecret');

  const app = express();
  app.use(cors());
  app.use(express.json());
  app.use(rateLimit({ windowMs: 15 * 60 * 1000, max: rateLimitMax }));

  const signToken = (user) =>
    jwt.sign({ userId: user.id }, jwtSecret, { expiresIn: '1h' });

  const publicUser = (user) => ({ id: user.id, username: user.username, email: user.email });

  function requireAuth(req, res, next) {
    const header = req.header('Authorization') || '';
    const token = header.startsWith('Bearer ') ? header.slice(7) : header;
    if (!token) return res.status(401).json({ message: 'Unauthorized' });
    try {
      req.userId = jwt.verify(token, jwtSecret).userId;
      return next();
    } catch (err) {
      return res.status(401).json({ message: 'Unauthorized' });
    }
  }

  app.get('/health', (req, res) => res.json({ status: 'ok' }));

  app.post('/register', async (req, res) => {
    const { username, email, password } = req.body || {};
    if (!username || !email || !password) {
      return res.status(400).json({ message: 'Username, email and password are required.' });
    }
    if (!EMAIL_RE.test(email)) {
      return res.status(400).json({ message: 'Please enter a valid email address.' });
    }
    if (String(password).length < 6) {
      return res.status(400).json({ message: 'Password must be at least 6 characters.' });
    }
    try {
      const normalizedEmail = email.trim().toLowerCase();
      if (await store.findUserByEmail(normalizedEmail)) {
        return res.status(409).json({ message: 'An account with that email already exists.' });
      }
      const now = new Date();
      const user = await store.createUser({
        username: username.trim(),
        email: normalizedEmail,
        password: await bcrypt.hash(password, 10),
        createdAt: now,
        updatedAt: now,
      });
      return res.status(201).json({
        message: 'User registered successfully',
        user: publicUser(user),
        token: signToken(user),
      });
    } catch (err) {
      console.error(err);
      return res.status(500).json({ message: 'An error occurred while registering the user.' });
    }
  });

  app.post('/login', async (req, res) => {
    const { email, password } = req.body || {};
    if (!email || !password) {
      return res.status(400).json({ message: 'Email and password are required.' });
    }
    try {
      const user = await store.findUserByEmail(email.trim().toLowerCase());
      if (!user || !(await bcrypt.compare(password, user.password))) {
        return res.status(401).json({ message: 'Invalid email or password.' });
      }
      return res.json({ user: publicUser(user), token: signToken(user) });
    } catch (err) {
      console.error(err);
      return res.status(500).json({ message: 'An error occurred while logging in.' });
    }
  });

  app.get('/services', async (req, res) => {
    try {
      return res.json({ services: await store.listServices() });
    } catch (err) {
      console.error(err);
      return res.status(500).json({ message: 'An error occurred while fetching services.' });
    }
  });

  app.get('/appointments', requireAuth, async (req, res) => {
    try {
      return res.json({ appointments: await store.listAppointments(req.userId) });
    } catch (err) {
      console.error(err);
      return res.status(500).json({ message: 'An error occurred while fetching appointments.' });
    }
  });

  app.post('/appointments', requireAuth, async (req, res) => {
    const { serviceId, startsAt } = req.body || {};
    const start = new Date(startsAt);
    if (!serviceId || !startsAt || Number.isNaN(start.getTime())) {
      return res.status(400).json({ message: 'serviceId and a valid startsAt date are required.' });
    }
    if (start.getTime() < Date.now()) {
      return res.status(400).json({ message: 'Appointments must be in the future.' });
    }
    try {
      const services = await store.listServices();
      const service = services.find((s) => s.id === serviceId);
      if (!service) return res.status(404).json({ message: 'Service not found.' });
      const appointment = await store.createAppointment({
        userId: req.userId,
        serviceId,
        serviceName: service.name,
        startsAt: start.toISOString(),
        createdAt: new Date().toISOString(),
      });
      return res.status(201).json({ appointment });
    } catch (err) {
      console.error(err);
      return res.status(500).json({ message: 'An error occurred while booking.' });
    }
  });

  return app;
}

module.exports = { createApp };
