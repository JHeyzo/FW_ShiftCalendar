import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fwcal/data/app_store.dart';
import 'package:fwcal/todo/todo_page.dart';
import 'package:fwcal/widgets/entry_tile.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<AppStore> storeWithTasks() async {
    final store = AppStore(clock: () => DateTime(2026, 10, 19, 12));
    await store.load();
    await store.saveEntries([
      CalendarEntry(
        id: 'yesterday',
        title: '昨天截止',
        start: DateTime(2026, 10, 18),
        kind: EntryKind.todo,
      ),
      CalendarEntry(
        id: 'today',
        title: '今天截止',
        start: DateTime(2026, 10, 19),
        kind: EntryKind.todo,
      ),
      CalendarEntry(
        id: 'range',
        title: '多日任务今天截止',
        start: DateTime(2026, 10, 17),
        end: DateTime(2026, 10, 20),
        kind: EntryKind.todo,
      ),
    ]);
    return store;
  }

  testWidgets('all-day yesterday is overdue rather than one day late', (
    tester,
  ) async {
    final store = await storeWithTasks();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TodoPage(store: store, onEdit: (_, _) {}),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('逾期'));
    await tester.pumpAndSettle();
    expect(find.text('昨天截止'), findsOneWidget);
    expect(find.text('今天截止'), findsNothing);
    expect(find.text('多日任务今天截止'), findsNothing);
    await tester.tap(find.text('今天'));
    await tester.pumpAndSettle();
    expect(find.text('今天截止'), findsOneWidget);
    expect(find.text('多日任务今天截止'), findsOneWidget);
    expect(find.text('昨天截止'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    store.dispose();
  });

  testWidgets('completion and reopen survive storage reload', (tester) async {
    final store = AppStore(clock: () => DateTime(2026, 10, 19));
    await store.load();
    await store.saveEntry(
      CalendarEntry(
        id: 'task',
        title: '交接',
        start: store.today,
        kind: EntryKind.todo,
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TodoPage(store: store, onEdit: (_, _) {}),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byType(Checkbox));
    await tester.pumpAndSettle();
    expect(store.entries.single.done, isTrue);
    final restored = AppStore();
    await restored.load();
    expect(restored.entries.single.done, isTrue);
    await tester.tap(find.byType(Checkbox));
    await tester.pumpAndSettle();
    expect(store.entries.single.done, isFalse);
    await tester.pumpWidget(const SizedBox.shrink());
    store.dispose();
    restored.dispose();
  });

  testWidgets(
    'long names and overnight metadata wrap at 2x on a narrow dark window',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final store = AppStore();
      await store.load();
      await store.saveCalendar(
        const CalendarGroup(id: 'long', name: '这是一个很长的日历名称用于测试窄屏大字体是否正确换行显示'),
      );
      final entry = CalendarEntry(
        id: 'night',
        title: '夜班交接与值班记录',
        start: DateTime(2026, 10, 19, 22),
        end: DateTime(2026, 10, 20, 8),
        allDay: false,
        kind: EntryKind.todo,
        calendarId: 'long',
        reminderMinutes: 15,
      );
      await store.saveEntry(entry);
      final occurrence = store
          .occurrences(DateTime(2026, 10, 19), DateTime(2026, 10, 21))
          .single;
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: MediaQuery(
            data: const MediaQueryData(
              size: Size(320, 640),
              textScaler: TextScaler.linear(2),
            ),
            child: Scaffold(
              body: ListView(
                children: [
                  EntryTile(occurrence: occurrence, store: store, onTap: () {}),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.textContaining('2026/10/20'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      store.dispose();
    },
  );
}
