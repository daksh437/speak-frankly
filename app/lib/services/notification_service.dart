import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

/// Daily practice reminder via a local scheduled notification. Fires once a day
/// at a fixed local time to bring the learner back and protect their streak.
/// Best-effort: if notifications aren't permitted, everything no-ops quietly.
class NotificationService extends ChangeNotifier {
  static final NotificationService instance = NotificationService._();
  NotificationService._();

  static const _kEnabled = 'sf_reminder_enabled';
  static const int _id = 1001;
  static const int _hour = 19; // 7:00 PM local

  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;
  bool enabled = true;

  Future<void> init() async {
    final p = await SharedPreferences.getInstance();
    enabled = p.getBool(_kEnabled) ?? true;
    try {
      tzdata.initializeTimeZones();
      final name = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(name));
    } catch (_) {/* fall back to default location */}

    try {
      const android = AndroidInitializationSettings('@mipmap/ic_launcher');
      const settings = InitializationSettings(android: android);
      await _plugin.initialize(settings);
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

  Future<void> _schedule() async {
    if (!_ready) return;
    try {
      await _plugin.zonedSchedule(
        _id,
        'Time to practise English 🗣️',
        "Keep your streak alive — a few minutes goes a long way!",
        _next7pm(),
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
      );
    } catch (_) {/* best-effort */}
  }

  Future<void> _cancel() async {
    try {
      await _plugin.cancel(_id);
    } catch (_) {}
  }

  tz.TZDateTime _next7pm() {
    final now = tz.TZDateTime.now(tz.local);
    var t = tz.TZDateTime(tz.local, now.year, now.month, now.day, _hour);
    if (t.isBefore(now)) t = t.add(const Duration(days: 1));
    return t;
  }
}
