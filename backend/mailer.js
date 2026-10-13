const { DateTime } = require('luxon');

/**
 * Sends email through SMTP when SMTP_URL is set (e.g. smtps://user:pass@smtp.example.com).
 * Without it, emails are written to the server log and kept in `outbox`, which is
 * enough to test sign-up codes, password resets and reminders locally.
 */
function createMailer({ smtpUrl, from, logger }) {
  const outbox = [];
  if (!smtpUrl) {
    return {
      console: true,
      outbox,
      async send(message) {
        outbox.push(message);
        logger.info({ to: message.to, subject: message.subject }, `EMAIL\n${message.text}`);
      },
    };
  }
  const nodemailer = require('nodemailer');
  const transport = nodemailer.createTransport(smtpUrl);
  return {
    console: false,
    outbox,
    async send(message) {
      await transport.sendMail({ from, ...message });
    },
  };
}

const icsDate = (iso) => DateTime.fromISO(iso, { zone: 'utc' }).toFormat("yyyyMMdd'T'HHmmss'Z'");
const icsText = (s) => String(s).replace(/[\\;,]/g, (c) => `\\${c}`).replace(/\n/g, '\\n');

/** A calendar invite (.ics) for a booking. */
function appointmentIcs(appointment, spa) {
  return [
    'BEGIN:VCALENDAR',
    'VERSION:2.0',
    'PRODID:-//the20sspa//booking//EN',
    'METHOD:PUBLISH',
    'BEGIN:VEVENT',
    `UID:${appointment.id}@the20sspa`,
    `DTSTAMP:${icsDate(new Date().toISOString())}`,
    `DTSTART:${icsDate(appointment.startsAt)}`,
    `DTEND:${icsDate(appointment.endsAt)}`,
    `SUMMARY:${icsText(`${appointment.serviceName} at ${spa.name}`)}`,
    `LOCATION:${icsText(spa.address)}`,
    `DESCRIPTION:${icsText(`With ${appointment.therapistName}. Questions? ${spa.phone}`)}`,
    appointment.status === 'cancelled' ? 'STATUS:CANCELLED' : 'STATUS:CONFIRMED',
    'END:VEVENT',
    'END:VCALENDAR',
    '',
  ].join('\r\n');
}

module.exports = { createMailer, appointmentIcs };
