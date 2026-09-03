/**
 * The date handling every usage counter and every admin figure agrees on.
 *
 * These lived twice — once in the metering middleware, once in the admin
 * routes, as byte-identical copies. That is worse than it looks: the admin
 * dashboard reports the plan mix and today's usage by re-deriving them from the
 * same user documents the middleware meters against, so the moment the two
 * copies drifted the panel would quietly disagree with what learners were
 * actually being charged, with nothing to say which one was right.
 *
 * Days are UTC. A daily allowance has to reset at one instant for everybody, or
 * a learner could pick a timezone and get two.
 */

/**
 * Coerce whatever a Firestore field holds into a Date, or null.
 *
 * The same timestamp arrives in four shapes depending on how it was written and
 * read back: an Admin SDK Timestamp (has .toDate()), a plain Date, a
 * JSON-serialised `{_seconds}`, or an ISO string.
 */
function toDate(v) {
  if (v == null) return null;
  if (typeof v.toDate === 'function') return v.toDate();
  if (v instanceof Date) return v;
  if (typeof v._seconds === 'number') return new Date(v._seconds * 1000);
  const d = new Date(v);
  return Number.isNaN(d.getTime()) ? null : d;
}

/** YYYY-MM-DD (UTC) for a Date — the key daily counters are stamped with. */
const dayStr = (d) => d.toISOString().slice(0, 10);

/** Today's YYYY-MM-DD (UTC). */
const todayDateStr = () => dayStr(new Date());

/** The instant today's counters roll over, as an ISO string. */
function getNextMidnightUtc() {
  const now = new Date();
  return new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), now.getUTCDate() + 1)).toISOString();
}

module.exports = { toDate, dayStr, todayDateStr, getNextMidnightUtc };
