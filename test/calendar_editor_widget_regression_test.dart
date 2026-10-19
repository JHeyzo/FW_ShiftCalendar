import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fwcal/calendar/month_page.dart';
import 'package:fwcal/data/app_store.dart';
import 'package:fwcal/todo/create_todo_page.dart';

class CountingAppStore extends AppStore {
  CountingAppStore({super.clock});

  int occurrenceQueries = 0;

  @override
  List<EntryOccurrence> occurrences(
    DateTime from,
    DateTime to, {
    bool visibleOnly = true,
  }) {
    occurrenceQueries++;
    return super.occurrences(from, to, visibleOnly: visibleOnly);
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  Future<AppStore> storeWithOvernightSeries() async {
    final store = AppStore(clock: () => DateTime(2026, 10, 19, 12));
    await store.load();
    await store.saveCalendar(
      const CalendarGroup(id: 'hidden', name: '隐藏日历', visible: false),
    );
    await store.saveEntry(
      CalendarEntry(
        id: 'weekly-overnight',
        title: '每周交接',
        start: DateTime(2026, 10, 1, 22, 30),
        end: DateTime(2026, 10, 2, 8),
        allDay: false,
        repeat: RepeatRule.weekly,
      ),
    );
    return store;
  }

  Widget editorHost(AppStore store, CalendarEntry entry) => MaterialApp(
    home: Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: TextButton(
            onPressed: () => openEntryEditor(
              context,
              store,
              entry: entry,
              occurrenceDate: DateTime(2026, 10, 15, 22, 30),
            ),
            child: const Text('打开编辑器'),
          ),
        ),
      ),
    ),
  );

  Widget monthHost(AppStore store) => MaterialApp(
    theme: ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff0066ff)),
    ),
    home: AnimatedBuilder(
      animation: store,
      builder: (context, _) => Scaffold(
        body: MonthPage(
          store: store,
          onCreate: (_) {},
          onEdit: (_, _) {},
          onSettings: () {},
          onManage: () {},
          onSearch: () {},
        ),
      ),
    ),
  );

  Future<void> openSeriesEditor(WidgetTester tester, AppStore store) async {
    final entry = store.entries.single;
    await tester.pumpWidget(editorHost(store, entry));
    await tester.tap(find.text('打开编辑器'));
    await tester.pumpAndSettle();
  }

  Future<void> saveSingleOccurrence(WidgetTester tester) async {
    tester.testTextInput.hide();
    await tester.pump();
    await tester.tap(find.text('保存'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('仅此项'));
    await tester.pump(const Duration(milliseconds: 500));
  }

  testWidgets(
    'weekly occurrence editor starts on instance date and keeps overnight span',
    (tester) async {
      final store = await storeWithOvernightSeries();
      await openSeriesEditor(tester, store);

      expect(find.textContaining('2026年10月15日  22:30'), findsOneWidget);
      expect(find.textContaining('2026年10月16日  08:00'), findsOneWidget);

      await tester.enterText(find.byType(TextFormField).first, '标题已更新');
      await saveSingleOccurrence(tester);

      final detached = store.entries.singleWhere(
        (entry) => entry.repeat == RepeatRule.none,
      );
      expect(detached.title, '标题已更新');
      expect(detached.start, DateTime(2026, 10, 15, 22, 30));
      expect(detached.end, DateTime(2026, 10, 16, 8));
      expect(
        store.entries
            .singleWhere((entry) => entry.repeat == RepeatRule.weekly)
            .excludedDates,
        contains('2026-10-15'),
      );
      await tester.pumpWidget(const SizedBox.shrink());
      store.dispose();
    },
  );

  testWidgets('rescheduling one occurrence moves it to the chosen exact date', (
    tester,
  ) async {
    final store = await storeWithOvernightSeries();
    await openSeriesEditor(tester, store);

    await tester.tap(
      find.ancestor(of: find.text('开始'), matching: find.byType(ListTile)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('17').last);
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    await saveSingleOccurrence(tester);

    final detached = store.entries.singleWhere(
      (entry) => entry.repeat == RepeatRule.none,
    );
    expect(detached.start, DateTime(2026, 10, 17, 22, 30));
    expect(detached.end, DateTime(2026, 10, 18, 8));
    await tester.pumpWidget(const SizedBox.shrink());
    store.dispose();
  });

  testWidgets(
    'month header back returns to year view while swipe changes month',
    (tester) async {
      final store = AppStore(clock: () => DateTime(2026, 2, 17, 12));
      await tester.pumpWidget(monthHost(store));
      await tester.tap(find.byTooltip('返回年视图'));
      await tester.pumpAndSettle();
      expect(store.view, '年');
      expect(store.selectedDate, DateTime(2026, 2, 17));

      store.setView('月');
      await tester.pumpAndSettle();
      await tester.fling(
        find.byType(AnimatedSwitcher),
        const Offset(-320, 0),
        1000,
      );
      await tester.pumpAndSettle();
      expect(store.selectedDate, DateTime(2026, 3, 17));
      await tester.pumpWidget(const SizedBox.shrink());
      store.dispose();
    },
  );

  testWidgets(
    'month grid queries once and shares visible-day occurrence snapshot',
    (tester) async {
      final store = CountingAppStore(clock: () => DateTime(2026, 2, 17, 12));
      await store.load();
      await store.saveCalendar(
        const CalendarGroup(id: 'hidden', name: '隐藏日历', visible: false),
      );
      await store.saveEntry(
        CalendarEntry(
          id: 'overnight-visible',
          title: '跨日待办',
          start: DateTime(2026, 2, 16, 22),
          end: DateTime(2026, 2, 18, 2),
          allDay: false,
          kind: EntryKind.todo,
          repeat: RepeatRule.none,
          done: true,
        ),
      );
      await store.saveEntry(
        CalendarEntry(
          id: 'hidden-event',
          title: '隐藏事项',
          start: DateTime(2026, 2, 17, 9),
          calendarId: 'hidden',
        ),
      );
      store.selectDate(DateTime(2026, 2, 17));
      store.occurrenceQueries = 0;

      await tester.pumpWidget(monthHost(store));
      expect(store.occurrenceQueries, 1);
      expect(find.text('跨日待办'), findsOneWidget);
      expect(find.text('隐藏事项'), findsNothing);
      expect(tester.widget<Checkbox>(find.byType(Checkbox)).value, isTrue);

      await tester.pumpWidget(const SizedBox.shrink());
      store.dispose();
    },
  );
}
