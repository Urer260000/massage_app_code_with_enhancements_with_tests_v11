require('dotenv').config();
const crypto = require('crypto');
const { createApp } = require('./app');
const { createMemoryStore, createMongoStore } = require('./store');

const port = Number(process.env.PORT) || 3000;

async function start() {
  let jwtSecret = process.env.JWT_SECRET;
  if (!jwtSecret) {
    jwtSecret = crypto.randomBytes(32).toString('hex');
    console.warn('JWT_SECRET not set - using a random secret for this run (logins reset on restart).');
  }

  let store;
  if (process.env.MONGO_DB_URL) {
    store = await createMongoStore(process.env.MONGO_DB_URL);
    console.log('Connected to MongoDB.');
  } else {
    store = createMemoryStore();
    console.log('MONGO_DB_URL not set - using in-memory storage (data resets on restart).');
  }

  const app = createApp({ store, jwtSecret });
  // Listen on all interfaces so the Android emulator (10.0.2.2) can reach it.
  app.listen(port, '0.0.0.0', () => console.log(`Server running on http://localhost:${port}`));
}

if (require.main === module) {
  start().catch((err) => {
    console.error('Failed to start server:', err);
    process.exit(1);
  });
}

module.exports = { start };
