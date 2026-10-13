/**
 * Spa settings. Every value can be overridden with an environment variable,
 * so the same code runs locally, in tests and in production.
 */

const int = (value, fallback) => {
  const n = Number.parseInt(value, 10);
  return Number.isFinite(n) ? n : fallback;
};

const list = (value) =>
  (value || '')
    .split(',')
    .map((s) => s.trim())
    .filter(Boolean);

function systemTimezone() {
  try {
    return Intl.DateTimeFormat().resolvedOptions().timeZone || 'UTC';
  } catch (err) {
    return 'UTC';
  }
}

function loadSpaConfig(env = process.env) {
  return {
    name: env.SPA_NAME || 'the20sspa',
    // All opening hours and slot times are in this time zone, whatever the guest's phone says.
    timezone: env.SPA_TIMEZONE || systemTimezone(),
    openHour: int(env.SPA_OPEN_HOUR, 10),
    closeHour: int(env.SPA_CLOSE_HOUR, 20),
    slotMinutes: int(env.SPA_SLOT_MINUTES, 30),
    minNoticeMinutes: int(env.SPA_MIN_NOTICE_MINUTES, 30),
    maxDaysAhead: int(env.SPA_MAX_DAYS_AHEAD, 21),
    // ISO weekdays the spa is closed: 1 = Monday ... 7 = Sunday.
    closedWeekdays: list(env.SPA_CLOSED_WEEKDAYS).map(Number).filter((d) => d >= 1 && d <= 7),
    cancelCutoffHours: int(env.CANCEL_CUTOFF_HOURS, 24),
    address: env.SPA_ADDRESS || '1920 Gatsby Lane, West Egg',
    phone: env.SPA_PHONE || '(555) 019-2020',
    email: env.SPA_EMAIL || 'hello@the20sspa.com',
    about:
      env.SPA_ABOUT ||
      'A Roaring Twenties day spa. Black-and-gold rooms, warm towels and a little jazz.',
  };
}

module.exports = { loadSpaConfig, list, int };
