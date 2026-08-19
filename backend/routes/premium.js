const express = require('express');
const { activatePremium } = require('../controllers/premiumController');
const { requireVerifiedAuth } = require('../middleware/auth');

const router = express.Router();

// Called by the app after a confirmed Google Play subscription purchase.
// The purchase token is verified against the Play API (premiumController); the
// uid it's granted to comes from the verified sign-in, not from the client.
//
// This is the money path, so it ALWAYS requires a verified Firebase ID token —
// never the soft `x-user-uid` header — even while REQUIRE_AUTH_TOKEN is still
// false for the rest of the API. Any build that can make a purchase already
// signs in with Google and sends the token, so no real buyer is affected; this
// just stops a caller from claiming someone else's uid on a purchase.
router.post('/activate', requireVerifiedAuth, async (req, res) => {
  const data = await activatePremium(req.uid, req.body);
  res.json({ success: true, data });
});

module.exports = router;
