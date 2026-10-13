/** An error with an HTTP status; the app's error handler turns it into `{ message }`. */
class HttpError extends Error {
  constructor(status, message, extra) {
    super(message);
    this.status = status;
    this.extra = extra;
  }
}

/** Thrown by stores when a unique rule is broken (duplicate email, slot already taken). */
class ConflictError extends Error {}

module.exports = { HttpError, ConflictError };
