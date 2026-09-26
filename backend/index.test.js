const request = require('supertest');
const { createApp } = require('./app');
const { createMemoryStore } = require('./store');

const makeApp = () => createApp({ store: createMemoryStore(), jwtSecret: 'test-secret' });

const register = (app, overrides = {}) =>
  request(app)
    .post('/register')
    .send({ username: 'testuser', email: 'test@email.com', password: 'testpassword', ...overrides });

describe('POST /register', () => {
  it('creates a user and returns a token', async () => {
    const res = await register(makeApp());
    expect(res.statusCode).toBe(201);
    expect(res.body).toHaveProperty('token');
    expect(res.body.user).toMatchObject({ username: 'testuser', email: 'test@email.com' });
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

  it('rejects a duplicate email', async () => {
    const app = makeApp();
    await register(app);
    const res = await register(app, { email: 'TEST@email.com' });
    expect(res.statusCode).toBe(409);
  });
});

describe('POST /login', () => {
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
});

describe('GET /services', () => {
  it('lists services without auth', async () => {
    const res = await request(makeApp()).get('/services');
    expect(res.statusCode).toBe(200);
    expect(res.body.services.length).toBeGreaterThan(0);
  });
});

describe('appointments', () => {
  it('requires auth', async () => {
    const res = await request(makeApp()).get('/appointments');
    expect(res.statusCode).toBe(401);
  });

  it('books and lists an appointment', async () => {
    const app = makeApp();
    const { body } = await register(app);
    const auth = `Bearer ${body.token}`;
    const startsAt = new Date(Date.now() + 24 * 3600 * 1000).toISOString();

    const booked = await request(app)
      .post('/appointments')
      .set('Authorization', auth)
      .send({ serviceId: 'swedish-60', startsAt });
    expect(booked.statusCode).toBe(201);
    expect(booked.body.appointment.serviceName).toBe('Swedish Massage');

    const list = await request(app).get('/appointments').set('Authorization', auth);
    expect(list.body.appointments).toHaveLength(1);
  });

  it('rejects past dates and unknown services', async () => {
    const app = makeApp();
    const { body } = await register(app);
    const auth = `Bearer ${body.token}`;
    const past = await request(app)
      .post('/appointments')
      .set('Authorization', auth)
      .send({ serviceId: 'swedish-60', startsAt: '2000-01-01T10:00:00Z' });
    expect(past.statusCode).toBe(400);
    const unknown = await request(app)
      .post('/appointments')
      .set('Authorization', auth)
      .send({ serviceId: 'nope', startsAt: new Date(Date.now() + 3600e3).toISOString() });
    expect(unknown.statusCode).toBe(404);
  });
});
