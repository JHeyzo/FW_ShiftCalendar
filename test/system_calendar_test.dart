import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fwcal/data/app_store.dart';
import 'package:fwcal/pages/system_calendar_page.dart';
import 'package:fwcal/services/system_calendar_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.jheyzo.fwcal/system_calendar');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
  });
  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
    debugDefaultTargetPlatformOverride = null;
  });

  test(
    'unsupported platform and permission denial never become empty success',
    () async {
      final service = SystemCalendarService();
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      expect(service.isSupported, isFalse);
      await expectLater(service.listCalendars(), throwsUnsupportedError);
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      messenger.setMockMethodCallHandler(channel, (call) async {
        throw PlatformException(code: 'PERMISSION_DENIED', message: '日历权限未允许');
      });
      await expectLater(
        service.listCalendars(),
        throwsA(isA<PlatformException>()),
      );
    },
  );

  testWidgets(
    'confirmed import is idempotent and export excludes imported entries',
    (tester) async {
      final today = dateOnly(DateTime.now());
      final tomorrow = DateTime(today.year, today.month, today.day + 1);
      final utc = DateTime.utc(tomorrow.year, tomorrow.month, tomorrow.day);
      final exports = <List<Object?>>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        switch (call.method) {
          case 'listCalendars':
            return [
              {
                'id': 42,
                'name': '系统日历',
                'accountName': 'test@example.invalid',
                'canWrite': true,
                'color': 0xff0066ff,
              },
            ];
          case 'readInstances':
            return {
              'instances': [
                {
                  'eventId': 7,
                  'begin': utc.millisecondsSinceEpoch,
                  'end': utc
                      .add(const Duration(days: 1))
                      .millisecondsSinceEpoch,
                  'title': '系统全天事件',
                  'allDay': true,
                  'notes': '原备注',
                  'timeZone': 'UTC',
                },
              ],
              'truncated': false,
            };
          case 'upsertEvents':
            final args = call.arguments as Map<Object?, Object?>;
            exports.add(List<Object?>.of(args['events'] as List));
            return {'total': exports.last.length};
        }
        throw MissingPluginException();
      });
      final store = AppStore();
      await store.load();
      final local = CalendarEntry(
        id: 'local-event',
        title: '本地早班',
        start: DateTime(tomorrow.year, tomorrow.month, tomorrow.day, 9),
        end: DateTime(tomorrow.year, tomorrow.month, tomorrow.day, 17),
        allDay: false,
      );
      await store.saveEntry(local);
      await tester.pumpWidget(
        MaterialApp(home: SystemCalendarPage(store: store)),
      );
      await tester.pumpAndSettle();

      Future<void> confirmAction(String label) async {
        final button = find.text(label);
        await tester.ensureVisible(button);
        await tester.pumpAndSettle();
        await tester.tap(button);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 350));
        expect(find.text('继续'), findsOneWidget);
        await tester.tap(find.text('继续'));
        await tester.pumpAndSettle();
      }

      await confirmAction('从系统日历导入');
      expect(store.entries, hasLength(2));
      final imported = store.entries.singleWhere(
        (entry) => entry.id.startsWith('system:'),
      );
      expect(imported.start, tomorrow);
      expect(imported.notes, '原备注');
      await confirmAction('从系统日历导入');
      expect(store.entries, hasLength(2));
      await confirmAction('导出到系统日历');
      expect(exports.single, hasLength(1));
      final firstExport = exports.single.single as Map<Object?, Object?>;
      expect(firstExport['key'], 'local-event');
      await store.saveEntry(
        local.copyWith(
          start: local.start.add(const Duration(hours: 1)),
          end: local.end!.add(const Duration(hours: 1)),
        ),
      );
      await confirmAction('导出到系统日历');
      final secondExport = exports.last.single as Map<Object?, Object?>;
      expect(secondExport['key'], firstExport['key']);
      expect(secondExport['start'], isNot(firstExport['start']));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      store.dispose();
      debugDefaultTargetPlatformOverride = null;
    },
  );
}
