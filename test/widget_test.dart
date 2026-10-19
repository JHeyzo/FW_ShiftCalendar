import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fwcal/data/app_store.dart';
import 'package:fwcal/main.dart';
import 'package:fwcal/pages/calendar_management_page.dart';
import 'package:fwcal/pages/search_page.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<AppStore> boot(WidgetTester tester) async {
    final store = AppStore(clock: () => DateTime(2026, 10, 19, 10));
    await store.load();
    await tester.pumpWidget(
      FengweiApp(store: store, loadStore: false, enableReminders: false),
    );
    await tester.pumpAndSettle();
    return store;
  }

  testWidgets('app boots with unified calendar date and todo navigation', (
    tester,
  ) async {
    final store = await boot(tester);
    expect(find.text('日历'), findsOneWidget);
    expect(find.text('待办'), findsOneWidget);
    expect(store.selectedDate, DateTime(2026, 10, 19));
    await tester.tap(find.text('待办'));
    await tester.pumpAndSettle();
    expect(find.text('全部'), findsWidgets);
    await tester.tap(find.text('日历'));
    await tester.pumpAndSettle();
    expect(store.selectedDate, DateTime(2026, 10, 19));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    store.dispose();
  });

  testWidgets('creating a todo persists and returns to a real list', (
    tester,
  ) async {
    final store = await boot(tester);
    await tester.tap(find.byTooltip('新建'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('新建待办'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).first, '测试夜班交接');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    final save = find.text('保存');
    await tester.scrollUntilVisible(
      save,
      350,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(save);
    await tester.pumpAndSettle();
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(store.entries.single.title, '测试夜班交接');
    expect(store.entries.single.kind, EntryKind.todo);
    await tester.tap(find.text('待办'));
    await tester.pumpAndSettle();
    expect(find.text('测试夜班交接'), findsWidgets);
    final reloaded = AppStore();
    await reloaded.load();
    expect(reloaded.entries.single.title, '测试夜班交接');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    store.dispose();
    reloaded.dispose();
  });

  testWidgets('search respects hidden calendars and can include them', (
    tester,
  ) async {
    final store = AppStore();
    await store.load();
    await store.saveCalendar(
      const CalendarGroup(id: 'hidden', name: '隐藏排班', visible: false),
    );
    await store.saveEntry(
      CalendarEntry(
        id: 'a',
        title: '交接记录',
        start: DateTime(2026, 10, 19),
        calendarId: 'hidden',
      ),
    );
    await tester.pumpWidget(MaterialApp(home: SearchPage(store: store)));
    await tester.pumpAndSettle();
    expect(find.text('交接记录'), findsNothing);
    await tester.tap(find.text('含隐藏日历'));
    await tester.pumpAndSettle();
    expect(find.text('交接记录'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '不匹配');
    await tester.pumpAndSettle();
    expect(find.text('未找到匹配的日程或待办'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    store.dispose();
  });

  testWidgets('calendar visibility is saved without deleting its entries', (
    tester,
  ) async {
    final store = AppStore();
    await store.load();
    await store.saveEntry(
      CalendarEntry(id: 'a', title: '早班', start: DateTime(2026, 10, 19)),
    );
    await tester.pumpWidget(
      MaterialApp(home: CalendarManagementPage(store: store)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(store.calendars.single.visible, isFalse);
    expect(store.entries, hasLength(1));
    expect(
      store.occurrences(DateTime(2026, 10, 19), DateTime(2026, 10, 20)),
      isEmpty,
    );
    await tester.pumpWidget(const SizedBox.shrink());
    store.dispose();
  });
}
