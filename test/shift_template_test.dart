import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fwcal/data/app_store.dart';
import 'package:fwcal/pages/shift_templates_page.dart';
import 'package:fwcal/services/shift_template_service.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  ShiftTemplate cycleTemplate() => ShiftTemplate(
    id: 'cycle-a',
    name: '兩日循環',
    steps: const <ShiftStep>[
      ShiftStep(
        name: '日班',
        colorValue: 0xff0066ff,
        isRest: false,
        startMinute: 8 * 60,
        endMinute: 16 * 60,
      ),
      ShiftStep(name: '休息', colorValue: 0xff34a853, isRest: true),
    ],
  );

  test(
    'cycle starts at step one and rolls through dates including leap day',
    () {
      final service = ShiftTemplateService();
      final entries = service.generateEntries(
        template: cycleTemplate(),
        firstDate: DateTime(2024, 2, 28),
        lastDate: DateTime(2024, 3, 2),
        calendarId: 'personal',
      );

      expect(entries.map((entry) => entry.id).toList(), <String>[
        'shift:cycle-a:2024-02-28',
        'shift:cycle-a:2024-02-29',
        'shift:cycle-a:2024-03-01',
        'shift:cycle-a:2024-03-02',
      ]);
      expect(entries.map((entry) => entry.allDay).toList(), <bool>[
        false,
        true,
        false,
        true,
      ]);
      expect(entries[2].title, '日班');
      expect(entries[2].start, DateTime(2024, 3, 1, 8));
    },
  );

  test('overnight work entry ends on the following calendar date', () {
    final entry = ShiftTemplateService()
        .generateEntries(
          template: ShiftTemplate(
            id: 'night',
            name: '夜班',
            steps: const <ShiftStep>[
              ShiftStep(
                name: '夜班',
                colorValue: 0xffa142f4,
                isRest: false,
                startMinute: 22 * 60,
                endMinute: 6 * 60,
                overnight: true,
              ),
            ],
          ),
          firstDate: DateTime(2024, 2, 29),
          lastDate: DateTime(2024, 2, 29),
          calendarId: 'personal',
        )
        .single;

    expect(entry.start, DateTime(2024, 2, 29, 22));
    expect(entry.end, DateTime(2024, 3, 1, 6));
    expect(entry.allDay, isFalse);
  });

  test(
    'reapplying same template and date uses stable id and upserts',
    () async {
      final store = AppStore();
      final service = ShiftTemplateService();
      await store.load();
      final first = service
          .generateEntries(
            template: cycleTemplate(),
            firstDate: DateTime(2025, 1, 1),
            lastDate: DateTime(2025, 1, 1),
            calendarId: 'personal',
          )
          .single;
      await store.saveEntry(first.copyWith(title: '手工修改'));
      await service.apply(
        store: store,
        template: cycleTemplate(),
        firstDate: DateTime(2025, 1, 1),
        lastDate: DateTime(2025, 1, 1),
        calendarId: 'personal',
      );

      expect(store.entries, hasLength(1));
      expect(store.entries.single.id, 'shift:cycle-a:2025-01-01');
      expect(store.entries.single.title, '日班');
    },
  );

  test(
    'conflict skip preserves unrelated entries and does not replace other IDs',
    () async {
      final store = AppStore();
      final service = ShiftTemplateService();
      await store.load();
      final unrelated = CalendarEntry(
        id: 'user-event',
        title: '私人會議',
        start: DateTime(2025, 4, 10, 9),
        end: DateTime(2025, 4, 10, 10),
        allDay: false,
        calendarId: 'personal',
      );
      await store.saveEntry(unrelated);
      final result = await service.apply(
        store: store,
        template: ShiftTemplate(
          id: 'workday',
          name: '日班模板',
          steps: const <ShiftStep>[
            ShiftStep(
              name: '早班',
              colorValue: 0xff0066ff,
              isRest: false,
              startMinute: 8 * 60,
              endMinute: 16 * 60,
            ),
          ],
        ),
        firstDate: DateTime(2025, 4, 10),
        lastDate: DateTime(2025, 4, 11),
        calendarId: 'personal',
        conflictPolicy: ShiftConflictPolicy.skip,
      );

      expect(result.skippedConflicts, 1);
      expect(store.entries.map((entry) => entry.id).toSet(), <String>{
        'user-event',
        'shift:workday:2025-04-11',
      });
      expect(
        store.entries.firstWhere((entry) => entry.id == 'user-event').title,
        '私人會議',
      );
    },
  );

  test(
    'templates persist under an independent SharedPreferences key',
    () async {
      final prefs = await SharedPreferences.getInstance();
      final service = ShiftTemplateService(preferences: prefs);
      final defaults = await service.loadTemplates();
      expect(
        defaults.map((template) => template.name),
        containsAll(<String>['早晚夜休', '上二休二']),
      );

      final custom = ShiftTemplate(
        id: 'custom-one',
        name: '自定义',
        steps: const <ShiftStep>[
          ShiftStep(
            name: '晚班',
            colorValue: 0xff5476ff,
            isRest: false,
            startMinute: 16 * 60,
            endMinute: 0,
            overnight: true,
          ),
        ],
      );
      await service.saveTemplate(custom);
      final loaded = await ShiftTemplateService(preferences: prefs)
          .loadTemplates();

      expect(loaded.any((template) => template.id == 'custom-one'), isTrue);
      expect(prefs.getString(shiftTemplateStorageKey), isNotNull);
      expect(prefs.getString('fwcal.app_store.v1'), isNull);
    },
  );

  testWidgets('large-text narrow layout can create and confirm a batch apply', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(360, 780);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final store = AppStore();
    await store.load();
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: const TextScaler.linear(1.7)),
          child: child!,
        ),
        home: ShiftTemplatesPage(store: store),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('循环班次模板'), findsOneWidget);
    expect(find.text('早晚夜休'), findsOneWidget);

    await tester.tap(find.text('新建模板'));
    await tester.pumpAndSettle();
    expect(find.text('新建循环模板'), findsOneWidget);
    await tester.enterText(find.byType(TextField).first, 'UI 烟测班表');
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('保存模板'));
    await tester.tap(find.text('保存模板'));
    await tester.pumpAndSettle();
    expect(find.text('UI 烟测班表'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();

    for (var i = 0; i < 8 && find.text('预览并应用排班').evaluate().isEmpty; i++) {
      await tester.drag(find.byType(ListView).first, const Offset(0, -550));
      await tester.pumpAndSettle();
    }
    expect(find.text('预览并应用排班'), findsOneWidget);
    await tester.ensureVisible(find.text('预览并应用排班'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('预览并应用排班'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    expect(find.text('确认生成排班'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.textContaining('重新应用会覆盖'),
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('确认应用'));
    await tester.pumpAndSettle();
    expect(store.entries, isNotEmpty);
    expect(store.entries.first.id, startsWith('shift:shift-template-'));
    await tester.pumpWidget(const SizedBox.shrink());
    store.dispose();
  });
}
