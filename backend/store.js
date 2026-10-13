const crypto = require('crypto');
const { ConflictError } = require('./errors');

const DEFAULT_SERVICES = [
  {
    id: 'swedish-60',
    signature: 'The Gatsby',
    name: 'Swedish Massage',
    durationMinutes: 60,
    price: 80,
    description: 'Long, flowing strokes that melt the week away. Smooth as a foxtrot and twice as relaxing.',
    active: true,
  },
  {
    id: 'deep-tissue-60',
    signature: 'The Speakeasy',
    name: 'Deep Tissue Massage',
    durationMinutes: 60,
    price: 95,
    description: 'Firm, focused pressure for the knots nobody talks about. What happens here stays here.',
    active: true,
  },
  {
    id: 'hot-stone-90',
    signature: 'The Jazz Age',
    name: 'Hot Stone Massage',
    durationMinutes: 90,
    price: 120,
    description: 'Warm basalt stones and a slow, easy rhythm for a deep and lingering calm.',
    active: true,
  },
  {
    id: 'sports-45',
    signature: 'The Charleston',
    name: 'Sports Massage',
    durationMinutes: 45,
    price: 70,
    description: 'A brisk, stretching treatment for dancers, athletes and anyone always on the move.',
    active: true,
  },
];

const DEFAULT_THERAPISTS = [
  {
    id: 'evelyn',
    name: 'Evelyn',
    bio: 'Swedish and hot stone. Twelve years of slow, unhurried calm.',
    serviceIds: ['swedish-60', 'hot-stone-90'],
  },
  {
    id: 'louis',
    name: 'Louis',
    bio: 'Deep tissue and sports. Finds the knot you forgot you had.',
    serviceIds: ['deep-tissue-60', 'sports-45'],
  },
  {
    id: 'zelda',
    name: 'Zelda',
    bio: 'Does it all, with a gramophone on low.',
    serviceIds: ['swedish-60', 'deep-tissue-60', 'hot-stone-90', 'sports-45'],
  },
];

const ACTIVE_STATUSES = ['confirmed'];

/** Shared filter logic for listAppointments. */
function matches(a, filter = {}) {
  if (filter.userId && a.userId !== filter.userId) return false;
  if (filter.kind && a.kind !== filter.kind) return false;
  if (filter.statuses && !filter.statuses.includes(a.status)) return false;
  if (filter.from && a.startsAt < filter.from) return false;
  if (filter.to && a.startsAt >= filter.to) return false;
  return true;
}

function sortAndPage(list, { order = 'asc', offset = 0, limit = 1000 } = {}) {
  const sorted = [...list].sort((x, y) =>
    order === 'desc' ? y.startsAt.localeCompare(x.startsAt) : x.startsAt.localeCompare(y.startsAt),
  );
  return sorted.slice(offset, offset + limit);
}

/**
 * In-memory store. Used automatically when MONGO_DB_URL is not set,
 * so the app can be run and tested without installing MongoDB.
 *
 * Methods that check-then-write never `await` in between, so they are atomic
 * in Node's single thread.
 */
function createMemoryStore() {
  const users = new Map();
  const services = new Map(DEFAULT_SERVICES.map((s) => [s.id, { ...s }]));
  const therapists = DEFAULT_THERAPISTS.map((t) => ({ ...t }));
  const appointments = new Map();
  const blocks = new Map(); // `${therapistId}|${blockIso}` -> appointmentId
  const waitlist = [];

  const key = (therapistId, block) => `${therapistId}|${block}`;

  function claim(appointmentId, therapistId, keys) {
    if (keys.some((b) => blocks.has(key(therapistId, b)))) {
      throw new ConflictError('That time has just been taken.');
    }
    keys.forEach((b) => blocks.set(key(therapistId, b), appointmentId));
  }

  function release(appointmentId) {
    for (const [k, id] of blocks) if (id === appointmentId) blocks.delete(k);
  }

  const copy = (x) => (x ? JSON.parse(JSON.stringify(x)) : null);

  return {
    // Users
    async findUserByEmail(email) {
      return copy([...users.values()].find((u) => u.email === email));
    },
    async findUserById(id) {
      return copy(users.get(id));
    },
    async createUser(user) {
      if ([...users.values()].some((u) => u.email === user.email)) {
        throw new ConflictError('An account with that email already exists.');
      }
      const created = { ...user, id: crypto.randomUUID() };
      users.set(created.id, created);
      return copy(created);
    },
    async updateUser(id, patch) {
      const user = users.get(id);
      if (!user) return null;
      Object.assign(user, patch);
      return copy(user);
    },
    async deleteUser(id) {
      users.delete(id);
      for (const [apptId, a] of appointments) {
        if (a.userId === id) {
          release(apptId);
          appointments.delete(apptId);
        }
      }
      for (let i = waitlist.length - 1; i >= 0; i--) if (waitlist[i].userId === id) waitlist.splice(i, 1);
    },

    // Services and therapists
    async listServices({ includeInactive = false } = {}) {
      return copy([...services.values()].filter((s) => includeInactive || s.active !== false));
    },
    async getService(id) {
      return copy(services.get(id));
    },
    async updateService(id, patch) {
      const service = services.get(id);
      if (!service) return null;
      Object.assign(service, patch);
      return copy(service);
    },
    async listTherapists() {
      return copy(therapists);
    },

    // Appointments
    async createAppointment(appointment, blockKeys) {
      const created = { ...appointment, id: crypto.randomUUID() };
      claim(created.id, created.therapistId, blockKeys);
      appointments.set(created.id, created);
      return copy(created);
    },
    async getAppointment(id) {
      return copy(appointments.get(id));
    },
    async listAppointments(filter = {}, page = {}) {
      return copy(sortAndPage([...appointments.values()].filter((a) => matches(a, filter)), page));
    },
    async updateAppointment(id, patch) {
      const a = appointments.get(id);
      if (!a) return null;
      Object.assign(a, patch);
      return copy(a);
    },
    /** Moves a booking to new blocks (and maybe a new therapist) atomically. */
    async moveAppointment(id, patch, blockKeys) {
      const a = appointments.get(id);
      if (!a) return null;
      const old = [...blocks].filter(([, apptId]) => apptId === id);
      release(id);
      try {
        claim(id, patch.therapistId || a.therapistId, blockKeys);
      } catch (err) {
        old.forEach(([k, apptId]) => blocks.set(k, apptId));
        throw err;
      }
      Object.assign(a, patch);
      return copy(a);
    },
    /** Frees a booking's time (cancel, no-show) and applies [patch]. */
    async releaseAppointment(id, patch) {
      const a = appointments.get(id);
      if (!a) return null;
      release(id);
      Object.assign(a, patch);
      return copy(a);
    },
    /** Taken blocks between two ISO instants: [{ therapistId, block }]. */
    async busyBlocks(fromIso, toIso) {
      const out = [];
      for (const k of blocks.keys()) {
        const [therapistId, block] = k.split('|');
        if (block >= fromIso && block < toIso) out.push({ therapistId, block });
      }
      return out;
    },

    // Waitlist
    async addToWaitlist(entry) {
      const existing = waitlist.find(
        (w) => w.userId === entry.userId && w.serviceId === entry.serviceId && w.date === entry.date,
      );
      if (existing) return copy(existing);
      const created = { ...entry, id: crypto.randomUUID() };
      waitlist.push(created);
      return copy(created);
    },
    async listWaitlist(filter = {}) {
      return copy(
        waitlist.filter(
          (w) => (!filter.date || w.date === filter.date) && (!filter.userId || w.userId === filter.userId),
        ),
      );
    },
    async removeFromWaitlist(id) {
      const i = waitlist.findIndex((w) => w.id === id);
      if (i >= 0) waitlist.splice(i, 1);
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
  const therapists = db.collection('therapists');
  const appointments = db.collection('appointments');
  const slots = db.collection('slots');
  const waitlist = db.collection('waitlist');

  // Earlier versions keyed users and appointments by Mongo's _id only. Give them an `id`.
  for (const collection of [users, appointments]) {
    const legacy = await collection.find({ id: { $exists: false } }, { projection: { _id: 1 } }).toArray();
    for (const doc of legacy) await collection.updateOne({ _id: doc._id }, { $set: { id: doc._id.toString() } });
  }
  await appointments.updateMany({ status: { $exists: false } }, { $set: { status: 'confirmed', kind: 'booking' } });

  await Promise.all([
    users.createIndex({ email: 1 }, { unique: true }),
    users.createIndex({ id: 1 }, { unique: true }),
    services.createIndex({ id: 1 }, { unique: true }),
    therapists.createIndex({ id: 1 }, { unique: true }),
    appointments.createIndex({ id: 1 }, { unique: true }),
    appointments.createIndex({ userId: 1, startsAt: 1 }),
    appointments.createIndex({ startsAt: 1, status: 1 }),
    // The double-booking guard: a therapist can hold each time block only once.
    slots.createIndex({ therapistId: 1, block: 1 }, { unique: true }),
    slots.createIndex({ appointmentId: 1 }),
    waitlist.createIndex({ date: 1 }),
  ]);
  // Seed only what's missing, so prices edited by staff survive restarts.
  for (const service of DEFAULT_SERVICES) {
    await services.updateOne({ id: service.id }, { $setOnInsert: service }, { upsert: true });
  }
  for (const therapist of DEFAULT_THERAPISTS) {
    await therapists.updateOne({ id: therapist.id }, { $setOnInsert: therapist }, { upsert: true });
  }

  const clean = (doc) => {
    if (!doc) return null;
    const { _id, ...rest } = doc;
    return rest;
  };
  const isDuplicate = (err) => err && err.code === 11000;

  async function claim(appointmentId, therapistId, blockKeys) {
    try {
      await slots.insertMany(
        blockKeys.map((block) => ({ therapistId, block, appointmentId })),
        { ordered: true },
      );
    } catch (err) {
      await slots.deleteMany({ appointmentId, therapistId, block: { $in: blockKeys } });
      if (isDuplicate(err)) throw new ConflictError('That time has just been taken.');
      throw err;
    }
  }

  return {
    async findUserByEmail(email) {
      return clean(await users.findOne({ email }));
    },
    async findUserById(id) {
      return clean(await users.findOne({ id }));
    },
    async createUser(user) {
      const created = { ...user, id: crypto.randomUUID() };
      try {
        await users.insertOne({ ...created });
      } catch (err) {
        if (isDuplicate(err)) throw new ConflictError('An account with that email already exists.');
        throw err;
      }
      return created;
    },
    async updateUser(id, patch) {
      return clean(await users.findOneAndUpdate({ id }, { $set: patch }, { returnDocument: 'after' }));
    },
    async deleteUser(id) {
      const ids = (await appointments.find({ userId: id }, { projection: { id: 1 } }).toArray()).map((a) => a.id);
      await slots.deleteMany({ appointmentId: { $in: ids } });
      await appointments.deleteMany({ userId: id });
      await waitlist.deleteMany({ userId: id });
      await users.deleteOne({ id });
    },

    async listServices({ includeInactive = false } = {}) {
      const query = includeInactive ? {} : { active: { $ne: false } };
      return (await services.find(query).toArray()).map(clean);
    },
    async getService(id) {
      return clean(await services.findOne({ id }));
    },
    async updateService(id, patch) {
      return clean(await services.findOneAndUpdate({ id }, { $set: patch }, { returnDocument: 'after' }));
    },
    async listTherapists() {
      return (await therapists.find({}).toArray()).map(clean);
    },

    async createAppointment(appointment, blockKeys) {
      const created = { ...appointment, id: crypto.randomUUID() };
      await claim(created.id, created.therapistId, blockKeys);
      await appointments.insertOne({ ...created });
      return created;
    },
    async getAppointment(id) {
      return clean(await appointments.findOne({ id }));
    },
    async listAppointments(filter = {}, { order = 'asc', offset = 0, limit = 1000 } = {}) {
      const query = {};
      if (filter.userId) query.userId = filter.userId;
      if (filter.kind) query.kind = filter.kind;
      if (filter.statuses) query.status = { $in: filter.statuses };
      if (filter.from || filter.to) {
        query.startsAt = {};
        if (filter.from) query.startsAt.$gte = filter.from;
        if (filter.to) query.startsAt.$lt = filter.to;
      }
      const docs = await appointments
        .find(query)
        .sort({ startsAt: order === 'desc' ? -1 : 1 })
        .skip(offset)
        .limit(limit)
        .toArray();
      return docs.map(clean);
    },
    async updateAppointment(id, patch) {
      return clean(await appointments.findOneAndUpdate({ id }, { $set: patch }, { returnDocument: 'after' }));
    },
    async moveAppointment(id, patch, blockKeys) {
      const current = await appointments.findOne({ id });
      if (!current) return null;
      const old = await slots.find({ appointmentId: id }).toArray();
      await slots.deleteMany({ appointmentId: id });
      try {
        await claim(id, patch.therapistId || current.therapistId, blockKeys);
      } catch (err) {
        if (old.length) await slots.insertMany(old.map(({ _id, ...s }) => s));
        throw err;
      }
      return clean(await appointments.findOneAndUpdate({ id }, { $set: patch }, { returnDocument: 'after' }));
    },
    async releaseAppointment(id, patch) {
      await slots.deleteMany({ appointmentId: id });
      return clean(await appointments.findOneAndUpdate({ id }, { $set: patch }, { returnDocument: 'after' }));
    },
    async busyBlocks(fromIso, toIso) {
      const docs = await slots.find({ block: { $gte: fromIso, $lt: toIso } }).toArray();
      return docs.map(({ therapistId, block }) => ({ therapistId, block }));
    },

    async addToWaitlist(entry) {
      const filter = { userId: entry.userId, serviceId: entry.serviceId, date: entry.date };
      await waitlist.updateOne(
        filter,
        { $setOnInsert: { ...entry, id: crypto.randomUUID() } },
        { upsert: true },
      );
      return clean(await waitlist.findOne(filter));
    },
    async listWaitlist(filter = {}) {
      const query = {};
      if (filter.date) query.date = filter.date;
      if (filter.userId) query.userId = filter.userId;
      return (await waitlist.find(query).toArray()).map(clean);
    },
    async removeFromWaitlist(id) {
      await waitlist.deleteOne({ id });
    },

    async close() {
      await client.close();
    },
  };
}

module.exports = {
  createMemoryStore,
  createMongoStore,
  DEFAULT_SERVICES,
  DEFAULT_THERAPISTS,
  ACTIVE_STATUSES,
};
