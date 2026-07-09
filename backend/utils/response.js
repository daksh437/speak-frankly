/**
 * Uniform API envelope. Mirrors InstaFlow's contract so the Flutter client can
 * reuse the same parsing logic: { success, data } on success, graceful shape on error.
 */
function apiSuccess(res, data = null, meta = {}) {
  const body = {
    success: true,
    ...(meta.message ? { message: String(meta.message) } : {}),
    ...(data !== null ? { data } : {}),
  };
  body.ok = true;
  return res.json(body);
}

function apiError(res, status, code, message, extra = {}) {
  const body = {
    success: false,
    error: String(message || 'Something went wrong'),
    code: String(code || 'INTERNAL_ERROR'),
    message: String(message || 'Something went wrong'),
    ...extra,
  };
  body.ok = false;
  return res.status(Number(status) || 500).json(body);
}

module.exports = { apiSuccess, apiError };
