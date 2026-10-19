import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fwcal/data/app_store.dart';
import 'package:fwcal/services/reminder_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  tearDown(() => debugDefaultTargetPlatformOverride = null);

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
}
