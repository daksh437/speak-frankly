import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../screens/daily_call.dart' show kDailyCallEnabled;

/// Daily practice reminder via a local scheduled notification. Fires once a day
/// at a fixed local time to bring the learner back and protect their streak.
/// Best-effort: if notifications aren't permitted, everything no-ops quietly.
class NotificationService extends ChangeNotifier {
  static final NotificationService instance = NotificationService._();
  NotificationService._();

  static const _kEnabled = 'sf_reminder_enabled';
  /// Payload on the daily notification: tapping it should open a call, not
  /// just the app.
  static const String callAction = 'daily_call';

  static const int _id = 1001;
  static const int _trialId = 1002; // one-time "trial ending" reminder
  static const _kCallHour = 'sf_call_hour';
  static const int _defaultHour = 19; // 7:00 PM local

  /// When the daily call goes out, as a local hour. Persisted, because the only
  /// time that works is the one the learner picked themselves.
  int hour = _defaultHour;

  /// Set when a notification was tapped before anything could listen for it —
  /// which is the normal case, since tapping it is usually what launches the
  /// app. Read and cleared by whoever handles routing.
  static String? pendingAction;

  /// Fired when a notification is tapped while the app is already running.
  static void Function(String action)? onAction;

  static void _deliver(String? payload) {
    final action = (payload ?? '').trim();
    if (action.isEmpty) return;
    final handler = onAction;
    if (handler != null) {
      handler(action);
    } else {
      pendingAction = action;
    }
  }

  /// Whatever a notification tap asked for while nobody was listening.
  static String? takePendingAction() {
    final a = pendingAction;
    pendingAction = null;
    return a;
  }

  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;
  bool enabled = true;

  Future<void> init() async {
    final p = await SharedPreferences.getInstance();
    enabled = p.getBool(_kEnabled) ?? true;
    hour = p.getInt(_kCallHour) ?? _defaultHour;
    try {
      tzdata.initializeTimeZones();
      final name = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(name));
    } catch (_) {/* fall back to default location */}

    try {
      const android = AndroidInitializationSettings('@mipmap/ic_launcher');
      const settings = InitializationSettings(android: android);
      await _plugin.initialize(
        settings,
        onDidReceiveNotificationResponse: (r) => _deliver(r.payload),
      );
      // A tap that LAUNCHED the app never reaches the callback above - the
      // handler is registered after the fact - so the launch details have to be
      // asked for directly. Without this, tapping the call notification from a
      // closed app just opened the home screen.
      final launch = await _plugin.getNotificationAppLaunchDetails();
      if (launch?.didNotificationLaunchApp ?? false) {
        _deliver(launch?.notificationResponse?.payload);
      }
      _ready = true;
    } catch (_) {
      _ready = false;
    }

    if (enabled) await _schedule();
    notifyListeners();
  }

  /// Ask for notification permission (Android 13+) and (re)schedule.
  Future<bool> requestAndSchedule() async {
    if (!_ready) await init();
    var granted = true;
    try {
      final android = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      granted = await android?.requestNotificationsPermission() ?? true;
    } catch (_) {}
    await setEnabled(true);
    return granted;
  }

  Future<void> setEnabled(bool value) async {
    enabled = value;
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kEnabled, value);
    if (value) {
      await _schedule();
    } else {
      await _cancel();
    }
    notifyListeners();
  }

  /// Move the daily call to a different local hour.
  Future<void> setHour(int newHour) async {
    hour = newHour.clamp(0, 23);
    final p = await SharedPreferences.getInstance();
    await p.setInt(_kCallHour, hour);
    if (enabled) await _schedule();
    notifyListeners();
  }

  Future<void> _schedule() async {
    if (!_ready) return;
    try {
      await _plugin.zonedSchedule(
        _id,
        'Time to practise English 🗣️',
        'Keep your streak alive — a few minutes goes a long way!',
        _nextCallTime(),
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'daily_reminder',
            'Daily reminder',
            channelDescription: 'A gentle daily nudge to practise.',
            importance: Importance.defaultImportance,
            priority: Priority.defaultPriority,
          ),
        ),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
        matchDateTimeComponents: DateTimeComponents.time, // repeat daily
        // Only carry the call payload while the call ships. Without this the
        // reminder would deep-link into a screen the build does not offer.
        payload: kDailyCallEnabled ? callAction : null,
      );
    } catch (_) {/* best-effort */}
  }

  Future<void> _cancel() async {
    try {
      await _plugin.cancel(_id);
    } catch (_) {}
  }

  /// One-time nudge ~24h before the free trial ends — the strongest moment to
  /// convert to Premium. Idempotent (same id just reschedules). No-ops if
  /// notifications are off or the trial ends too soon.
  Future<void> scheduleTrialEnding(DateTime trialEndsAt) async {
    if (!_ready) await init();
    if (!_ready || !enabled) return;
    final fireAt = trialEndsAt.toLocal().subtract(const Duration(hours: 24));
    if (fireAt.isBefore(DateTime.now())) return; // trial already ending — too late to nudge
    try {
      await _plugin.zonedSchedule(
        _trialId,
        'Your free trial ends tomorrow ⏳',
        'Keep unlimited conversations — go Premium so your practice never stops.',
        tz.TZDateTime.from(fireAt, tz.local),
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'trial_ending',
            'Trial ending',
            channelDescription: 'A reminder before your free trial ends.',
            importance: Importance.high,
            priority: Priority.high,
          ),
        ),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
        // one-time (no matchDateTimeComponents → does not repeat)
      );
    } catch (_) {/* best-effort */}
  }

  tz.TZDateTime _nextCallTime() {
    final now = tz.TZDateTime.now(tz.local);
    var t = tz.TZDateTime(tz.local, now.year, now.month, now.day, hour);
    if (t.isBefore(now)) t = t.add(const Duration(days: 1));
    return t;
  }
}
