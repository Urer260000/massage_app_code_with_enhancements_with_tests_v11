require('dotenv').config();
const crypto = require('crypto');
const bcrypt = require('bcryptjs');
const pino = require('pino');
const { createApp } = require('./app');
const { createMemoryStore, createMongoStore } = require('./store');
const { loadSpaConfig, list } = require('./config');
const { createMailer } = require('./mailer');
const { sendReminders } = require('./reminders');

const env = process.env;
const production = env.NODE_ENV === 'production';
const port = Number(env.PORT) || 3000;
// JSON logs in production (for log tools); readable, coloured lines locally.
const logger = pino({
  level: env.LOG_LEVEL || 'info',
  ...(production ? {} : { transport: { target: 'pino-pretty', options: { ignore: 'pid,hostname', translateTime: 'HH:MM:ss' } } }),
});

/** In local (in-memory) mode, create a staff account so the Staff screen can be tried. */
async function seedDemoAdmin(store) {
  const email = (env.ADMIN_EMAIL || 'admin@the20sspa.com').toLowerCase();
  const password = env.ADMIN_PASSWORD || 'gatsby-staff-1920';
  if (await store.findUserByEmail(email)) return;
  await store.createUser({
    username: 'Spa Staff',
    email,
    password: await bcrypt.hash(password, 10),
    role: 'admin',
    emailVerified: true,
    tokenVersion: 0,
    createdAt: new Date().toISOString(),
    updatedAt: new Date().toISOString(),
  });
  logger.info(`Staff login for testing: ${email} / ${password}`);
}

async function start() {
  let jwtSecret = env.JWT_SECRET;
  if (!jwtSecret) {
    if (production) throw new Error('JWT_SECRET must be set in production (python generateSecretKey.py prints one).');
    jwtSecret = crypto.randomBytes(32).toString('hex');
    logger.warn('JWT_SECRET not set - using a random secret for this run (logins reset on restart).');
  }

  let store;
  if (env.MONGO_DB_URL) {
    store = await createMongoStore(env.MONGO_DB_URL);
    logger.info('Connected to MongoDB.');
  } else {
    if (production) throw new Error('MONGO_DB_URL must be set in production.');
    store = createMemoryStore();
    logger.warn('MONGO_DB_URL not set - using in-memory storage (data resets on restart).');
  }

  const adminEmails = list(env.ADMIN_EMAILS);
  if (!env.MONGO_DB_URL || env.ADMIN_PASSWORD) await seedDemoAdmin(store);

  const spa = loadSpaConfig(env);
  const mailer = createMailer({ smtpUrl: env.SMTP_URL, from: env.MAIL_FROM || `${spa.name} <${spa.email}>`, logger });
  const app = createApp({
    store,
    jwtSecret,
    spa,
    mailer,
    logger,
    corsOrigins: list(env.CORS_ORIGINS),
    trustProxy: env.TRUST_PROXY ? Number(env.TRUST_PROXY) || env.TRUST_PROXY : false,
    // Without real email, show one-time codes in the app so sign-up and resets can be tested.
    exposeDevCodes: !production,
    adminEmails,
  });

  // Listen on all interfaces so the Android emulator (10.0.2.2) can reach it.
  const server = app.listen(port, '0.0.0.0', () => {
    logger.info(`Server running on http://localhost:${port} (spa time zone ${spa.timezone})`);
  });

  const reminderTimer = setInterval(() => {
    sendReminders({ store, mailer, spa, logger }).catch((err) => logger.error({ err }, 'Reminder run failed'));
  }, 60 * 1000);

  const shutdown = (signal) => {
    logger.info(`${signal} received, shutting down.`);
    clearInterval(reminderTimer);
    server.close(async () => {
      await store.close();
      process.exit(0);
    });
    setTimeout(() => process.exit(1), 10000).unref();
  };
  process.on('SIGTERM', () => shutdown('SIGTERM'));
  process.on('SIGINT', () => shutdown('SIGINT'));
}

if (require.main === module) {
  start().catch((err) => {
    logger.error({ err }, 'Failed to start server');
    process.exit(1);
  });
}

module.exports = { start };
