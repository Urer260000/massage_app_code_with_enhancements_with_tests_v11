const { createMemoryStore, createMongoStore } = require('./store');
const { ConflictError } = require('./errors');

/**
 * The same checks run against both stores. The MongoDB run needs a server:
 * set MONGO_TEST_URL (CI starts one), e.g. mongodb://localhost:27017/spa_test.
 */
const stores = [['memory', async () => createMemoryStore()]];
if (process.env.MONGO_TEST_URL) {
  stores.push([
    'mongo',
    async () => {
      const url = process.env.MONGO_TEST_URL;
      const { MongoClient } = require('mongodb');
      const client = new MongoClient(url);
      await client.connect();
      await client.db().dropDatabase();
      await client.close();
      return createMongoStore(url);
    },
  ]);
}

const user = (email) => ({ username: 'Daisy', email, password: 'hash', tokenVersion: 0 });
const appt = (fields) => ({
  kind: 'booking',
  userId: 'u1',
  serviceId: 'swedish-60',
  serviceName: 'Swedish Massage',
  therapistId: 'evelyn',
  startsAt: '2030-01-08T15:00:00.000Z',
  endsAt: '2030-01-08T16:00:00.000Z',
  status: 'confirmed',
  ...fields,
});
const B1 = '2030-01-08T15:00:00.000Z';
const B2 = '2030-01-08T15:30:00.000Z';
const B3 = '2030-01-08T16:00:00.000Z';

describe.each(stores)('%s store', (name, make) => {
  let store;
  beforeEach(async () => {
    store = await make();
  });
  afterEach(async () => {
    await store.close();
  });

  it('creates, finds and updates users; emails are unique', async () => {
    const created = await store.createUser(user('a@b.com'));
    expect(created.id).toBeTruthy();
    expect((await store.findUserByEmail('a@b.com')).id).toBe(created.id);
    expect((await store.findUserById(created.id)).email).toBe('a@b.com');
    await expect(store.createUser(user('a@b.com'))).rejects.toBeInstanceOf(ConflictError);
    expect((await store.updateUser(created.id, { username: 'Gatsby' })).username).toBe('Gatsby');
  });

  it('seeds services and therapists, and keeps edits', async () => {
    expect((await store.listServices()).length).toBe(4);
    expect((await store.listTherapists()).length).toBe(3);
    await store.updateService('sports-45', { price: 99, active: false });
    expect((await store.listServices()).map((s) => s.id)).not.toContain('sports-45');
    expect((await store.getService('sports-45')).price).toBe(99);
  });

  it('refuses a block a therapist already holds', async () => {
    await store.createAppointment(appt(), [B1, B2]);
    await expect(store.createAppointment(appt(), [B2, B3])).rejects.toBeInstanceOf(ConflictError);
    // The failed attempt must not leave B3 claimed.
    expect((await store.busyBlocks(B1, '2030-01-09T00:00:00.000Z')).map((b) => b.block).sort()).toEqual([B1, B2]);
    // Another therapist can take the same time.
    await store.createAppointment(appt({ therapistId: 'zelda' }), [B2, B3]);
  });

  it('moves a booking and restores it when the new time is taken', async () => {
    const a = await store.createAppointment(appt(), [B1, B2]);
    await store.createAppointment(appt({ therapistId: 'zelda' }), [B3]);
    await expect(store.moveAppointment(a.id, { therapistId: 'zelda' }, [B3])).rejects.toBeInstanceOf(ConflictError);
    expect((await store.busyBlocks(B1, B3)).filter((b) => b.therapistId === 'evelyn')).toHaveLength(2);
    const moved = await store.moveAppointment(a.id, { startsAt: B2 }, [B2, B3]);
    expect(moved.startsAt).toBe(B2);
  });

  it('releases blocks on cancel', async () => {
    const a = await store.createAppointment(appt(), [B1, B2]);
    const cancelled = await store.releaseAppointment(a.id, { status: 'cancelled' });
    expect(cancelled.status).toBe('cancelled');
    expect(await store.busyBlocks(B1, B3)).toHaveLength(0);
  });

  it('filters, sorts and pages appointments', async () => {
    await store.createAppointment(appt({ startsAt: B2 }), [B2]);
    await store.createAppointment(appt({ startsAt: B1, therapistId: 'zelda' }), [B1]);
    await store.createAppointment(appt({ userId: 'u2', startsAt: B3 }), [B3]);
    const mine = await store.listAppointments({ userId: 'u1' });
    expect(mine.map((a) => a.startsAt)).toEqual([B1, B2]);
    const desc = await store.listAppointments({}, { order: 'desc', limit: 2 });
    expect(desc.map((a) => a.startsAt)).toEqual([B3, B2]);
    expect(await store.listAppointments({ from: B2, to: B3 })).toHaveLength(1);
  });

  it('deletes a user with their bookings and waitlist entries', async () => {
    const u = await store.createUser(user('gone@b.com'));
    await store.createAppointment(appt({ userId: u.id }), [B1]);
    await store.addToWaitlist({ userId: u.id, email: 'gone@b.com', serviceId: 'swedish-60', date: '2030-01-08' });
    await store.deleteUser(u.id);
    expect(await store.findUserById(u.id)).toBeNull();
    expect(await store.listAppointments({ userId: u.id })).toHaveLength(0);
    expect(await store.busyBlocks(B1, B3)).toHaveLength(0);
    expect(await store.listWaitlist({ userId: u.id })).toHaveLength(0);
  });

  it('keeps one waitlist entry per guest, treatment and day', async () => {
    const entry = { userId: 'u1', email: 'a@b.com', serviceId: 'swedish-60', date: '2030-01-08' };
    const first = await store.addToWaitlist(entry);
    const second = await store.addToWaitlist(entry);
    expect(second.id).toBe(first.id);
    await store.removeFromWaitlist(first.id);
    expect(await store.listWaitlist({ date: '2030-01-08' })).toHaveLength(0);
  });
});
