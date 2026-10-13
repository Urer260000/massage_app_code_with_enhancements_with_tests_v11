const { DateTime } = require('luxon');

/**
 * Opening-hours and slot rules. Every booking is checked here, so the API
 * enforces the same rules the app shows.
 *
 * Bookings are split into fixed-size "blocks" (30 minutes by default). Each
 * therapist can hold a block only once, which is how the stores stop double
 * bookings, even when two guests press Confirm at the same moment.
 */

/** Start of the given spa-local day (`YYYY-MM-DD`), or null if invalid. */
function parseDay(dateStr, spa) {
  if (typeof dateStr !== 'string' || !/^\d{4}-\d{2}-\d{2}$/.test(dateStr)) return null;
  const day = DateTime.fromISO(dateStr, { zone: spa.timezone }).startOf('day');
  return day.isValid ? day : null;
}

function today(spa, now = new Date()) {
  return DateTime.fromJSDate(now, { zone: spa.timezone }).startOf('day');
}

/** The spa days a guest can book, today first. */
function bookableDays(spa, now = new Date()) {
  const first = today(spa, now);
  return Array.from({ length: spa.maxDaysAhead }, (_, i) => first.plus({ days: i }));
}

/** Every start time on [day] where a treatment of [durationMinutes] fits in opening hours. */
function candidateStarts(day, durationMinutes, spa) {
  if (spa.closedWeekdays.includes(day.weekday)) return [];
  const open = day.set({ hour: spa.openHour, minute: 0, second: 0, millisecond: 0 });
  const close = day.set({ hour: spa.closeHour, minute: 0, second: 0, millisecond: 0 });
  const starts = [];
  for (let t = open; t.plus({ minutes: durationMinutes }) <= close; t = t.plus({ minutes: spa.slotMinutes })) {
    starts.push(t);
  }
  return starts;
}

/** Is [start] far enough ahead, but not too far? */
function withinWindow(start, spa, now = new Date()) {
  const earliest = DateTime.fromJSDate(now).plus({ minutes: spa.minNoticeMinutes });
  const lastDay = today(spa, now).plus({ days: spa.maxDaysAhead - 1 }).endOf('day');
  return start >= earliest && start <= lastDay;
}

/**
 * Returns a reason the guest can't start a treatment at [startsAt], or null if it is fine.
 * [startsAt] is a JS Date or ISO string.
 */
function checkStart(startsAt, durationMinutes, spa, now = new Date()) {
  const start = DateTime.fromJSDate(new Date(startsAt), { zone: spa.timezone });
  if (!start.isValid) return 'A valid startsAt date is required.';
  if (start.toMillis() < now.getTime()) return 'Appointments must be in the future.';
  if (!withinWindow(start, spa, now)) {
    return `Bookings open ${spa.minNoticeMinutes} minutes to ${spa.maxDaysAhead} days ahead.`;
  }
  if (spa.closedWeekdays.includes(start.weekday)) return 'The spa is closed that day.';
  const allowed = candidateStarts(start.startOf('day'), durationMinutes, spa);
  if (!allowed.some((t) => t.toMillis() === start.toMillis())) {
    return `Please pick one of the listed times between ${pad(spa.openHour)}:00 and ${pad(spa.closeHour)}:00.`;
  }
  return null;
}

/** The block keys (UTC ISO strings) a booking from [startsAt] lasting [durationMinutes] occupies. */
function blocksFor(startsAt, durationMinutes, spa) {
  const start = DateTime.fromJSDate(new Date(startsAt)).toUTC();
  const count = Math.ceil(durationMinutes / spa.slotMinutes);
  return Array.from({ length: count }, (_, i) => start.plus({ minutes: i * spa.slotMinutes }).toISO());
}

/** Spa-local labels for an instant, e.g. { date: '2026-10-14', time: '14:30' }. */
function localParts(iso, spa) {
  const t = DateTime.fromISO(iso, { zone: 'utc' }).setZone(spa.timezone);
  return { date: t.toISODate(), time: t.toFormat('HH:mm') };
}

function pad(n) {
  return String(n).padStart(2, '0');
}

module.exports = {
  parseDay,
  today,
  bookableDays,
  candidateStarts,
  withinWindow,
  checkStart,
  blocksFor,
  localParts,
};
