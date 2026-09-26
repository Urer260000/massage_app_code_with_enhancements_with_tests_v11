const crypto = require('crypto');

const DEFAULT_SERVICES = [
  { id: 'swedish-60', name: 'Swedish Massage', durationMinutes: 60, price: 80 },
  { id: 'deep-tissue-60', name: 'Deep Tissue Massage', durationMinutes: 60, price: 95 },
  { id: 'hot-stone-90', name: 'Hot Stone Massage', durationMinutes: 90, price: 120 },
  { id: 'sports-45', name: 'Sports Massage', durationMinutes: 45, price: 70 },
];

/**
 * In-memory store. Used automatically when MONGO_DB_URL is not set,
 * so the app can be run and tested without installing MongoDB.
 */
function createMemoryStore() {
  const users = [];
  const appointments = [];

  return {
    async findUserByEmail(email) {
      return users.find((u) => u.email === email) || null;
    },
    async createUser(user) {
      const created = { ...user, id: crypto.randomUUID() };
      users.push(created);
      return created;
    },
    async listServices() {
      return DEFAULT_SERVICES;
    },
    async createAppointment(appointment) {
      const created = { ...appointment, id: crypto.randomUUID() };
      appointments.push(created);
      return created;
    },
    async listAppointments(userId) {
      return appointments.filter((a) => a.userId === userId);
    },
    async close() {},
  };
}

/** MongoDB-backed store. */
async function createMongoStore(url) {
  const { MongoClient } = require('mongodb');
  const client = new MongoClient(url);
  await client.connect();
  const db = client.db();
  const users = db.collection('users');
  const services = db.collection('services');
  const appointments = db.collection('appointments');

  await users.createIndex({ email: 1 }, { unique: true });
  if ((await services.countDocuments()) === 0) {
    await services.insertMany(DEFAULT_SERVICES.map((s) => ({ ...s })));
  }

  const clean = (doc) => {
    if (!doc) return null;
    const { _id, ...rest } = doc;
    return { id: rest.id || _id.toString(), ...rest };
  };

  return {
    async findUserByEmail(email) {
      return clean(await users.findOne({ email }));
    },
    async createUser(user) {
      const result = await users.insertOne({ ...user });
      return { ...user, id: result.insertedId.toString() };
    },
    async listServices() {
      return (await services.find({}).toArray()).map(clean);
    },
    async createAppointment(appointment) {
      const result = await appointments.insertOne({ ...appointment });
      return { ...appointment, id: result.insertedId.toString() };
    },
    async listAppointments(userId) {
      return (await appointments.find({ userId }).toArray()).map(clean);
    },
    async close() {
      await client.close();
    },
  };
}

module.exports = { createMemoryStore, createMongoStore, DEFAULT_SERVICES };
