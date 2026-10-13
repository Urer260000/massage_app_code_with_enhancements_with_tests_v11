const { DateTime } = require('luxon');
const { localParts } = require('./schedule');

const WINDOWS = [
  { field: 'reminder24SentAt', hours: 24, label: 'tomorrow' },
  { field: 'reminder2SentAt', hours: 2, label: 'in two hours' },
];

/**
 * Emails guests whose treatment starts within 24 hours, and again within 2 hours.
 * Safe to run every minute: each reminder is sent once.
 */
async function sendReminders({ store, mailer, spa, logger, now = new Date() }) {
  const from = DateTime.fromJSDate(now).toUTC();
  const upcoming = await store.listAppointments({
    kind: 'booking',
    statuses: ['confirmed'],
    from: from.toISO(),
    to: from.plus({ hours: 24 }).toISO(),
  });
  let sent = 0;
  for (const a of upcoming) {
    const hoursAway = DateTime.fromISO(a.startsAt).diff(from, 'hours').hours;
    // Only the most urgent window applies; a booking made 1 hour ahead gets one reminder, not two.
    const due = WINDOWS.filter((w) => hoursAway <= w.hours && !a[w.field]);
    if (!due.length) continue;
    const window = due[due.length - 1];
    const user = await store.findUserById(a.userId);
    if (user) {
      const local = localParts(a.startsAt, spa);
      try {
        await mailer.send({
          to: user.email,
          subject: `Reminder: ${a.serviceName} ${window.label}`,
          text:
            `Hello ${user.username},\n\nA reminder that your ${a.serviceName} with ${a.therapistName} ` +
            `is on ${local.date} at ${local.time}.\n${spa.address}\n\nSee you soon!\n- ${spa.name}`,
        });
        sent += 1;
      } catch (err) {
        logger.error({ err }, 'Failed to send reminder');
        continue;
      }
    }
    const patch = {};
    due.forEach((w) => {
      patch[w.field] = now.toISOString();
    });
    await store.updateAppointment(a.id, patch);
  }
  return sent;
}

module.exports = { sendReminders };
