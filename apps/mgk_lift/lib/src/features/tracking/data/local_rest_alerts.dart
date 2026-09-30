import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/timezone.dart' as tz;

import '../domain/rest_alerts.dart';

/// [RestAlerts] as a local notification, scheduled by the operating system so
/// it fires with the app suspended, locked, or killed.
///
/// ## Timing
///
/// Scheduled at an absolute instant — the rest's fixed end, see `RestTimer` —
/// in UTC. The timezone package's UTC needs no database and no device-zone
/// plugin, and an instant is all a countdown means.
///
/// On Android the alarm is **exact where the lifter's phone allows it** and
/// inexact otherwise. Android 12 and 13 grant `SCHEDULE_EXACT_ALARM` at
/// install; 14 and later deny it by default, and an inexact alarm can land
/// late. `USE_EXACT_ALARM` would avoid that, and Play restricts it to alarm
/// and calendar apps, so it is not claimed.
///
/// ## What is not here
///
/// iOS "Time Sensitive" delivery, which gets through a Focus mode. It is an
/// App ID capability, and Lift signs with a provisioning profile uploaded by
/// hand (see codemagic.yaml), so adding it means regenerating that profile.
/// Worth doing; not worth doing blind.
class LocalRestAlerts implements RestAlerts {
  LocalRestAlerts({FlutterLocalNotificationsPlugin? plugin})
    : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;

  /// One id, because there is only ever one rest.
  static const int _id = 4201;
  static const String _askedKey = 'rest_alerts.asked';

  static const AndroidNotificationDetails _android = AndroidNotificationDetails(
    'rest_timer',
    'Rest timer',
    channelDescription: 'A buzz when your rest between sets is over.',
    importance: Importance.high,
    priority: Priority.high,
    category: AndroidNotificationCategory.reminder,
    icon: 'ic_stat_rest',
  );

  static const DarwinNotificationDetails _darwin = DarwinNotificationDetails(
    presentAlert: true,
    presentSound: true,
    presentBanner: true,
    presentList: true,
    interruptionLevel: InterruptionLevel.active,
  );

  Future<bool>? _ready;

  Future<bool> _init() async {
    try {
      await _plugin.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('ic_stat_rest'),
          // Never on launch: the prompt is asked for once, at the moment it
          // means something — see [ask].
          iOS: DarwinInitializationSettings(
            requestAlertPermission: false,
            requestSoundPermission: false,
            requestBadgePermission: false,
          ),
        ),
      );
      // A rest from before the app was killed and relaunched is nobody's
      // rest now, and would buzz in the middle of whatever comes next.
      await _plugin.cancel(id: _id);
      return true;
    } on Object catch (e) {
      debugPrint('rest alerts unavailable: $e');
      return false;
    }
  }

  Future<bool> _isReady() => _ready ??= _init();

  AndroidFlutterLocalNotificationsPlugin? get _androidPlugin => _plugin
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >();

  IOSFlutterLocalNotificationsPlugin? get _iosPlugin => _plugin
      .resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin
      >();

  @override
  Future<bool> allowed() async {
    if (!await _isReady()) return false;
    try {
      if (defaultTargetPlatform == TargetPlatform.android) {
        return await _androidPlugin?.areNotificationsEnabled() ?? false;
      }
      final options = await _iosPlugin?.checkPermissions();
      return options?.isEnabled ?? false;
    } on PlatformException {
      return false;
    }
  }

  @override
  Future<bool> asked() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_askedKey) ?? false;
    } on Object {
      return true; // Unknown is treated as asked: never nag on a guess.
    }
  }

  @override
  Future<void> markAsked() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_askedKey, true);
    } on Object {
      // Remembering is a courtesy; failing to only means asking again.
    }
  }

  @override
  Future<bool> ask() async {
    await markAsked();
    if (!await _isReady()) return false;
    try {
      if (defaultTargetPlatform == TargetPlatform.android) {
        return await _androidPlugin?.requestNotificationsPermission() ?? false;
      }
      return await _iosPlugin?.requestPermissions(alert: true, sound: true) ??
          false;
    } on PlatformException {
      return false;
    }
  }

  @override
  Future<void> schedule({
    required DateTime at,
    required String title,
    required String body,
  }) async {
    if (!await _isReady()) return;
    if (!at.isAfter(DateTime.now())) return;
    try {
      final exact =
          defaultTargetPlatform != TargetPlatform.android ||
          (await _androidPlugin?.canScheduleExactNotifications() ?? false);
      await _plugin.zonedSchedule(
        id: _id,
        title: title,
        body: body,
        scheduledDate: tz.TZDateTime.from(at.toUtc(), tz.UTC),
        notificationDetails: const NotificationDetails(
          android: _android,
          iOS: _darwin,
        ),
        androidScheduleMode: exact
            ? AndroidScheduleMode.exactAllowWhileIdle
            : AndroidScheduleMode.inexactAllowWhileIdle,
      );
    } on PlatformException catch (e) {
      // A lifter with notifications off gets the timer on screen, as before.
      debugPrint('rest alert not scheduled: $e');
    }
  }

  @override
  Future<void> cancel() async {
    if (!await _isReady()) return;
    try {
      await _plugin.cancel(id: _id);
    } on PlatformException {
      // Nothing scheduled is the state this is asking for.
    }
  }
}
