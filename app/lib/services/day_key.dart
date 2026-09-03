/// The one definition of "which day is it" on the device.
///
/// Three copies of this used to sit in three files: the streak counter's, the
/// daily speaking-phrase cache's, and the daily picture-match cache's. They
/// happened to agree, which is the dangerous kind of duplication — the streak,
/// the phrase set and the game set all roll over together only for as long as
/// nobody edits one of them.
///
/// LOCAL time, deliberately. This is what the learner experiences as "today":
/// their streak survives if they practise before they go to bed, and they get
/// new phrases when they wake up. The SERVER's daily allowances are UTC and
/// separate on purpose — one instant has to reset everyone's quota, or a
/// timezone becomes a way to get two.
library;

/// YYYY-MM-DD for [d] in local time.
String dayKey(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// Today's YYYY-MM-DD in local time.
String todayKey() => dayKey(DateTime.now());
