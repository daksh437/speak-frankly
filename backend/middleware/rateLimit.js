/**
 * Small in-memory rate limiter.
 *
 * The AI endpoints are already budgeted per learner (see aiAccess), but the
 * PUBLIC ones aren't: /scenarios and /dictionary/:word need no account, and the
 * dictionary proxies a free third-party API that will start refusing us if one
 * script hammers it. This caps requests per client per window so a single
 * caller can't do that — or fill the logs trying.
 *
 * In-memory on purpose: the service runs as a single Render instance, so a
 * shared store would be complexity with no benefit today. If this ever scales
 * to multiple instances the limit becomes per-instance (i.e. looser), never
 * wrong — swap in a shared store at that point.
 */

/** Best-effort client key: the proxy-forwarded IP, else the socket address. */
function clientKey(req) {
  const fwd = (req.headers['x-forwarded-for'] || '').toString().split(',')[0].trim();
  return fwd || req.ip || (req.socket && req.socket.remoteAddress) || 'unknown';
}

/**
 * @param {object} opts
 * @param {number} opts.windowMs  window length
 * @param {number} opts.max       requests allowed per key per window
 * @param {string} [opts.name]    label for logs
 */
function rateLimit({ windowMs, max, name = 'rate' }) {
  const hits = new Map(); // key -> { count, windowStart }

  // Drop stale entries so the map can't grow without bound. unref() keeps this
  // timer from holding the process (and the test runner) open.
  const sweep = setInterval(() => {
    const cutoff = Date.now() - windowMs;
    for (const [k, v] of hits) {
      if (v.windowStart < cutoff) hits.delete(k);
    }
  }, windowMs);
  if (typeof sweep.unref === 'function') sweep.unref();

  return function limiter(req, res, next) {
    const key = clientKey(req);
    const now = Date.now();
    const h = hits.get(key);

    if (!h || now - h.windowStart > windowMs) {
      hits.set(key, { count: 1, windowStart: now });
      return next();
    }

    h.count++;
    if (h.count > max) {
      const retryAfter = Math.ceil((h.windowStart + windowMs - now) / 1000);
      res.setHeader('Retry-After', String(Math.max(1, retryAfter)));
      if (h.count === max + 1) console.warn(`[${name}] rate limit hit by ${key}`);
      return res.status(429).json({
        success: false,
        error: 'TOO_MANY_REQUESTS',
        code: 'TOO_MANY_REQUESTS',
        message: 'Too many requests — please slow down.',
      });
    }
    return next();
  };
}

module.exports = { rateLimit };
