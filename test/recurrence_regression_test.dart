import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fwcal/data/app_store.dart';
import 'package:fwcal/todo/create_todo_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  test(
    'single edit keeps a completed todo completed and rebases its moved date',
    () async {
      final store = AppStore(clock: () => DateTime(2025, 1, 1));
      await store.load();
      final series = CalendarEntry(
        id: 'daily',
        title: 'Original',
        start: DateTime(2025, 1, 1, 9),
        kind: EntryKind.todo,
        allDay: false,
        repeat: RepeatRule.daily,
        completedDates: <String>{'2025-01-04'},
      );
      await store.saveEntry(series);

      await store.updateEntry(
        series,
        series.copyWith(title: 'Renamed', start: DateTime(2025, 1, 7, 9)),
        occurrenceDate: DateTime(2025, 1, 4),
        scope: EditScope.single,
      );

      final detached = store.entries.singleWhere(
        (entry) => entry.id != series.id,
      );
      expect(detached.start, DateTime(2025, 1, 7, 9));
      expect(detached.done, isTrue);
      expect(
        store
            .occurrences(DateTime(2025, 1, 7), DateTime(2025, 1, 8))
            .singleWhere((occurrence) => occurrence.entry.id == detached.id)
            .done,
        isTrue,
      );
      store.dispose();
    },
  );

  test('future split shifts future completion, exclusion, and implicit cutoff once', () async {
    final store = AppStore(clock: () => DateTime(2025, 1, 1));
    await store.load();
    final series = CalendarEntry(
      id: 'daily',
      title: 'Daily',
      start: DateTime(2025, 1, 1, 9),
      kind: EntryKind.todo,
      allDay: false,
      repeat: RepeatRule.daily,
      repeatUntil: DateTime(2025, 1, 31),
      completedDates: <String>{'2025-01-02', '2025-01-05'},
      excludedDates: <String>{'2025-01-03', '2025-01-06'},
    );
    await store.saveEntry(series);

    await store.updateEntry(
      series,
      series.copyWith(title: 'Moved', start: DateTime(2025, 1, 7, 9)),
      occurrenceDate: DateTime(2025, 1, 4),
      scope: EditScope.future,
    );

    final oldSegment = store.entries.singleWhere(
      (entry) => entry.id == series.id,
    );
    final newSegment = store.entries.singleWhere(
      (entry) => entry.id != series.id,
    );
    expect(newSegment.start, DateTime(2025, 1, 7, 9));
    expect(oldSegment.repeatUntil, DateTime(2025, 1, 3));
    expect(newSegment.repeatUntil, DateTime(2025, 2, 3));
    expect(newSegment.completedDates, <String>{'2025-01-08'});
    expect(newSegment.excludedDates, <String>{'2025-01-09'});
    expect(
      store.occurrences(DateTime(2025, 1, 8), DateTime(2025, 1, 9)).single.done,
      isTrue,
    );
    expect(
      store.occurrences(DateTime(2025, 1, 9), DateTime(2025, 1, 10)),
      isEmpty,
    );
    store.dispose();
  });

  test(
    'all edit with occurrence date shifts from the selected instance',
    () async {
      final store = AppStore(clock: () => DateTime(2025, 1, 1));
      await store.load();
      final series = CalendarEntry(
        id: 'all-occurrence',
        title: 'Daily',
        start: DateTime(2025, 1, 1, 9),
        kind: EntryKind.todo,
        repeat: RepeatRule.daily,
        repeatUntil: DateTime(2025, 1, 31),
        completedDates: <String>{'2025-01-06'},
        excludedDates: <String>{'2025-01-07'},
      );
      await store.saveEntry(series);

      await store.updateEntry(
        series,
        series.copyWith(start: DateTime(2025, 1, 8, 9)),
        occurrenceDate: DateTime(2025, 1, 6),
        scope: EditScope.all,
      );

      final moved = store.entries.single;
      expect(moved.start, DateTime(2025, 1, 3, 9));
      expect(moved.repeatUntil, DateTime(2025, 2, 2));
      expect(moved.completedDates, <String>{'2025-01-08'});
      expect(moved.excludedDates, <String>{'2025-01-09'});
      store.dispose();
    },
  );

  test(
    'all edit preserves the weekly series anchor and overnight span',
    () async {
      final store = AppStore();
      await store.load();
      addTearDown(store.dispose);
      final series = CalendarEntry(
        id: 'weekly-all',
        title: 'Original',
        start: DateTime(2026, 10, 1, 22, 30),
        end: DateTime(2026, 10, 2, 8),
        allDay: false,
        repeat: RepeatRule.weekly,
      );
      await store.saveEntry(series);
      await store.updateEntry(
        series,
        series.copyWith(
          title: 'Renamed',
          start: DateTime(2026, 10, 15, 22, 30),
          end: DateTime(2026, 10, 16, 8),
        ),
        occurrenceDate: DateTime(2026, 10, 15),
        scope: EditScope.all,
      );
      final renamed = store.entries.single;
      expect(renamed.start, series.start);
      expect(renamed.end, series.end);
      expect(renamed.title, 'Renamed');
      await store.updateEntry(
        renamed,
        renamed.copyWith(
          start: DateTime(2026, 10, 17, 23),
          end: DateTime(2026, 10, 18, 9),
        ),
        occurrenceDate: DateTime(2026, 10, 15),
        scope: EditScope.all,
      );
      final moved = store.entries.single;
      expect(moved.start, DateTime(2026, 10, 3, 23));
      expect(moved.end, DateTime(2026, 10, 4, 9));
      expect(
        store
            .occurrences(DateTime(2026, 10, 17), DateTime(2026, 10, 18))
            .single
            .start,
        DateTime(2026, 10, 17, 23),
      );
    },
  );

  test(
    'renaming all from a clamped February instance retains the 31st anchor',
    () async {
      final store = AppStore();
      await store.load();
      addTearDown(store.dispose);
      final series = CalendarEntry(
        id: 'monthly-anchor',
        title: 'Monthly',
        start: DateTime(2026, 1, 31),
        repeat: RepeatRule.monthly,
      );
      await store.saveEntry(series);
      await store.updateEntry(
        series,
        series.copyWith(title: 'Renamed', start: DateTime(2026, 2, 28)),
        occurrenceDate: DateTime(2026, 2, 28),
        scope: EditScope.all,
      );
      expect(store.entries.single.start, DateTime(2026, 1, 31));
      expect(
        store.occurrences(DateTime(2026, 3), DateTime(2026, 4)).single.start,
        DateTime(2026, 3, 31),
      );
    },
  );

  test(
    'future edit from first instance also moves exception keys and cutoff',
    () async {
      final store = AppStore();
      await store.load();
      addTearDown(store.dispose);
      final series = CalendarEntry(
        id: 'future-first',
        title: 'Daily',
        start: DateTime(2026, 10, 1),
        repeat: RepeatRule.daily,
        repeatUntil: DateTime(2026, 10, 31),
        excludedDates: {'2026-10-03'},
        completedDates: {'2026-10-04'},
      );
      await store.saveEntry(series);
      await store.updateEntry(
        series,
        series.copyWith(start: DateTime(2026, 10, 2)),
        occurrenceDate: DateTime(2026, 10, 1),
        scope: EditScope.future,
      );
      final moved = store.entries.single;
      expect(moved.start, DateTime(2026, 10, 2));
      expect(moved.repeatUntil, DateTime(2026, 11, 1));
      expect(moved.excludedDates, {'2026-10-04'});
      expect(moved.completedDates, {'2026-10-05'});
    },
  );

  test('all edit shifts exception keys and cutoff; an edited cutoff stays selected', () async {
    final store = AppStore(clock: () => DateTime(2025, 1, 1));
    await store.load();
    final series = CalendarEntry(
      id: 'daily',
      title: 'Daily',
      start: DateTime(2025, 1, 1, 9),
      kind: EntryKind.todo,
      repeat: RepeatRule.daily,
      repeatUntil: DateTime(2025, 1, 31),
      completedDates: <String>{'2025-01-05'},
      excludedDates: <String>{'2025-01-06'},
    );
    await store.saveEntry(series);

    await store.updateEntry(
      series,
      series.copyWith(title: 'Moved', start: DateTime(2025, 1, 7, 9)),
      scope: EditScope.all,
    );
    var moved = store.entries.single;
    expect(moved.start, DateTime(2025, 1, 7, 9));
    expect(moved.completedDates, <String>{'2025-01-11'});
    expect(moved.excludedDates, <String>{'2025-01-12'});
    expect(moved.repeatUntil, DateTime(2025, 2, 6));

    await store.updateEntry(
      moved,
      moved.copyWith(
        start: DateTime(2025, 1, 8, 9),
        repeatUntil: DateTime(2025, 2, 20),
      ),
      scope: EditScope.all,
    );
    moved = store.entries.single;
    expect(moved.repeatUntil, DateTime(2025, 2, 20));
    expect(moved.completedDates, <String>{'2025-01-12'});
    expect(moved.excludedDates, <String>{'2025-01-13'});
    store.dispose();
  });

  testWidgets(
    'moving start date preserves overnight calendar span and wall times',
    (tester) async {
      final store = AppStore(clock: () => DateTime(2025, 1, 1));
      await store.load();
      final entry = CalendarEntry(
        id: 'overnight',
        title: 'Night task',
        start: DateTime(2025, 1, 1, 22),
        end: DateTime(2025, 1, 2, 2),
        kind: EntryKind.todo,
        allDay: false,
      );
      await store.saveEntry(entry);

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => openEntryEditor(context, store, entry: entry),
                child: const Text('编辑'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('编辑'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('开始'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('3'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.schedule).first);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Switch to text input mode'));
      await tester.pumpAndSettle();
      final timeFields = find.byType(TextField);
      expect(find.byType(TextField), findsNWidgets(4));
      await tester.enterText(timeFields.at(2), '11');
      await tester.enterText(timeFields.at(3), '00');
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      tester.binding.focusManager.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();

      final saved = store.entries.single;
      expect(saved.start, DateTime(2025, 1, 3, 23));
      expect(saved.end, DateTime(2025, 1, 4, 3));
      await tester.pumpWidget(const SizedBox.shrink());
      store.dispose();
    },
  );
}
