import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fwcal/data/app_store.dart';
import 'package:fwcal/services/reminder_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      ..setMockMethodCallHandler(_notificationsChannel, null)
      ..setMockMethodCallHandler(_timezoneChannel, null);
  });

  test(
    'unsupported platform reports unavailable instead of scheduling success',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      final service = ReminderService();
      await service.initialize();
      expect(await service.requestPermission(), isFalse);
      final store = AppStore();
      await store.load();
      await service.synchronize(store);
      expect(service.statusMessage, contains('仅支持 Android'));
      store.dispose();
    },
  );

  test(
    'missing platform implementation leaves an actionable initialization error',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final service = ReminderService();
      await service.initialize();
      expect(await service.requestPermission(), isFalse);
      expect(service.statusMessage, contains('初始化失败'));
      final store = AppStore();
      await store.load();
      await service.synchronize(store);
      expect(service.statusMessage, isNot(contains('已同步')));
      store.dispose();
    },
  );

  test('permission request permits exact mode and sync deduplicates', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final platform = _NotificationPlatform(exactAllowed: true);
    _installPlatform(platform);
    final service = ReminderService();
    final store = await _storeWithReminder();

    expect(await service.requestPermission(), isTrue);
    expect(platform.calls, contains('requestNotificationsPermission'));
    expect(platform.calls, contains('requestExactAlarmsPermission'));
    await service.synchronize(store);

    expect(platform.scheduleModes, <String>['exactAllowWhileIdle']);
    expect(service.statusMessage, contains('精准提醒'));
    final cancellations = platform.cancelAllCount;
    await service.synchronize(store);
    expect(platform.cancelAllCount, cancellations);
    expect(platform.scheduleModes, hasLength(1));
    store.dispose();
  });

  test(
    'denied exact permission schedules inexact and reports degradation',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final platform = _NotificationPlatform(exactAllowed: false);
      _installPlatform(platform);
      final service = ReminderService();
      final store = await _storeWithReminder();

      await service.synchronize(store);
      expect(platform.calls, isNot(contains('requestExactAlarmsPermission')));
      expect(platform.scheduleModes, <String>['inexactAllowWhileIdle']);
      expect(service.statusMessage, contains('非精准提醒'));
      expect(service.statusMessage, contains('权限未开启'));
      store.dispose();
    },
  );

  test(
    'exact permission change is part of signature and rebuilds schedules',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final platform = _NotificationPlatform(exactAllowed: false);
      _installPlatform(platform);
      final service = ReminderService();
      final store = await _storeWithReminder();

      await service.synchronize(store);
      expect(platform.scheduleModes, <String>['inexactAllowWhileIdle']);
      platform.exactAllowed = true;
      await service.synchronize(store);

      expect(platform.scheduleModes, <String>[
        'inexactAllowWhileIdle',
        'exactAllowWhileIdle',
      ]);
      expect(platform.cancelAllCount, 2);
      expect(service.statusMessage, contains('精准提醒'));
      store.dispose();
    },
  );

  test(
    'exact permission plugin error is explicit and subsequent sync retries',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final platform = _NotificationPlatform(exactAllowed: true)
        ..failExactPermissionCheck = true;
      _installPlatform(platform);
      final service = ReminderService();
      final store = await _storeWithReminder();

      await service.synchronize(store);
      expect(platform.scheduleModes, <String>['inexactAllowWhileIdle']);
      expect(service.statusMessage, contains('无法检查精准提醒权限'));
      expect(service.statusMessage, contains('请重试'));

      platform.failExactPermissionCheck = false;
      await service.synchronize(store);
      expect(platform.scheduleModes, <String>[
        'inexactAllowWhileIdle',
        'exactAllowWhileIdle',
      ]);
      expect(service.statusMessage, contains('精准提醒'));
      store.dispose();
    },
  );
}

const MethodChannel _notificationsChannel = MethodChannel(
  'dexterous.com/flutter/local_notifications',
);
const MethodChannel _timezoneChannel = MethodChannel('flutter_timezone');

void _installPlatform(_NotificationPlatform platform) {
  FlutterLocalNotificationsPlatform.instance =
      AndroidFlutterLocalNotificationsPlugin();
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
    ..setMockMethodCallHandler(_notificationsChannel, platform.handle)
    ..setMockMethodCallHandler(_timezoneChannel, (call) async => 'UTC');
}

Future<AppStore> _storeWithReminder() async {
  final store = AppStore();
  await store.load();
  await store.saveEntry(
    CalendarEntry(
      id: 'reminder-test',
      title: '测试提醒',
      start: DateTime.now().add(const Duration(hours: 2)),
      allDay: false,
      reminderMinutes: 10,
    ),
  );
  return store;
}

class _NotificationPlatform {
  _NotificationPlatform({required this.exactAllowed});

  bool exactAllowed;
  bool failExactPermissionCheck = false;
  final List<String> calls = <String>[];
  final List<String> scheduleModes = <String>[];
  int cancelAllCount = 0;

  Future<Object?> handle(MethodCall call) async {
    calls.add(call.method);
    switch (call.method) {
      case 'initialize':
        return true;
      case 'getNotificationAppLaunchDetails':
        return null;
      case 'requestNotificationsPermission':
        return true;
      case 'requestExactAlarmsPermission':
        return exactAllowed;
      case 'areNotificationsEnabled':
        return true;
      case 'canScheduleExactNotifications':
        if (failExactPermissionCheck) {
          throw PlatformException(code: 'permission_query_failed');
        }
        return exactAllowed;
      case 'cancelAll':
        cancelAllCount++;
        return null;
      case 'zonedSchedule':
        final arguments = call.arguments as Map<Object?, Object?>;
        final platformSpecifics =
            arguments['platformSpecifics'] as Map<Object?, Object?>;
        scheduleModes.add(platformSpecifics['scheduleMode'] as String);
        return null;
      default:
        throw MissingPluginException('Unexpected method ${call.method}');
    }
  }
}
