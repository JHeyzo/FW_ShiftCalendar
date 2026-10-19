import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fwcal/calendar/month_page.dart';
import 'package:fwcal/calendar/year_page.dart';
import 'package:fwcal/data/app_store.dart';

void main() {
  test(
    'February 2026 grid starts Monday and includes every date exactly once',
    () {
      final cells = monthGridDates(DateTime(2026, 2));
      expect(cells, hasLength(35));
      expect(cells.take(6), everyElement(isNull));
      expect(cells[6], DateTime(2026, 2, 1));
      expect(cells[33], DateTime(2026, 2, 28));
      expect(cells.last, isNull);
      expect(cells.where((date) => date?.month == 2), hasLength(28));
    },
  );

  test(
    'year and month selection preserve the selected day and clamp short months',
    () {
      expect(dateWithClampedDay(2026, 2, 31), DateTime(2026, 2, 28));
      expect(dateWithClampedDay(2026, 3, 15), DateTime(2026, 3, 15));
      expect(dateInMonthPreservingDay(2026, 2, 31), DateTime(2026, 2, 28));
      expect(dateInMonthPreservingDay(2026, 4, 30), DateTime(2026, 4, 30));
    },
  );

  AppStore newStore() => AppStore(clock: () => DateTime(2026, 2, 17, 12));

  Widget mount(AppStore store) => MaterialApp(
    theme: ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff0066ff)),
    ),
    home: AnimatedBuilder(
      animation: store,
      builder: (context, _) => Scaffold(
        body: SafeArea(
          child: MonthPage(
            store: store,
            onCreate: (_) {},
            onEdit: (_, _) {},
            onSettings: () {},
            onManage: () {},
            onSearch: () {},
          ),
        ),
      ),
    ),
  );

  testWidgets('Today control selects store today', (tester) async {
    final store = newStore();
    store.selectDate(DateTime(2026, 1, 4));
    await tester.pumpWidget(mount(store));
    await tester.tap(find.widgetWithText(TextButton, '今天'));
    await tester.pumpAndSettle();
    expect(store.selectedDate, DateTime(2026, 2, 17));
  });

  testWidgets('view menu changes views without changing the selected date', (
    tester,
  ) async {
    final store = newStore();
    final selected = DateTime(2026, 2, 12);
    store.selectDate(selected);
    await tester.pumpWidget(mount(store));
    await tester.tap(find.byTooltip('更多日历选项'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('时间线').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('时间线').last);
    await tester.pumpAndSettle();
    expect(store.view, '时间线');
    expect(store.selectedDate, selected);
    expect(find.text('2月12日 · 时间线'), findsOneWidget);
  });

  testWidgets('folding the month grid shows only the selected week', (
    tester,
  ) async {
    final store = newStore();
    store.selectDate(DateTime(2026, 2, 15));
    await tester.pumpWidget(mount(store));
    expect(find.text('1'), findsOneWidget);
    await tester.tap(find.byTooltip('收起月历'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('展开月历'), findsOneWidget);
    expect(find.text('1'), findsNothing);
    await tester.tap(find.byTooltip('展开月历'));
    await tester.pumpAndSettle();
    expect(find.text('1'), findsOneWidget);
  });

  testWidgets(
    'month detail displays actual store occurrences, not lunar text as an event',
    (tester) async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final store = newStore();
      store.selectDate(DateTime(2026, 2, 17));
      await store.saveEntry(
        CalendarEntry(
          id: 'calendar-test-entry',
          title: '真实日程',
          start: DateTime(2026, 2, 17, 9),
          allDay: false,
          calendarId: 'personal',
        ),
      );
      await tester.pumpWidget(mount(store));
      expect(find.text('真实日程'), findsOneWidget);
      expect(find.text('这一天没有日程或待办'), findsNothing);
    },
  );

  testWidgets(
    'year month selection retains the selected day, clamped to target month',
    (tester) async {
      final store = newStore();
      store.selectDate(DateTime(2026, 1, 31));
      DateTime? selected;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: YearPage(
              store: store,
              onPickMonth: (date) => selected = date,
              onChangeYear: (_) {},
              onToday: () {},
            ),
          ),
        ),
      );
      await tester.tap(find.text('2月'));
      expect(selected, DateTime(2026, 2, 28));
    },
  );

  testWidgets(
    'month page lays out on narrow portrait and landscape at 2x text',
    (tester) async {
      final store = newStore();
      for (final size in const [Size(330, 650), Size(800, 360)]) {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        await tester.pumpWidget(
          MediaQuery(
            data: MediaQueryData(
              size: size,
              textScaler: const TextScaler.linear(2),
            ),
            child: mount(store),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        // Month content remains scrollable even when the viewport is short.
        expect(find.byType(CustomScrollView), findsOneWidget);
        store.setView('年');
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.byType(GridView), findsWidgets);
        store.setView('月');
        await tester.pumpAndSettle();
      }
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    },
  );
}
