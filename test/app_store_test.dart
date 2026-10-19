import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fwcal/data/app_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  group('date helpers and selection', () {
    test('normalizes dates, clamps month shifts, and skips invalid recurrence dates', () async {
      expect(dateOnly(DateTime(2024, 2, 29, 18, 30)), DateTime(2024, 2, 29));
      expect(sameDay(DateTime(2024, 2, 29, 18), DateTime(2024, 2, 29)), isTrue);
      expect(shiftMonth(DateTime(2024, 1, 31), 1), DateTime(2024, 2, 29));
      expect(shiftMonth(DateTime(2023, 1, 31), 1), DateTime(2023, 2, 28));
      expect(shiftMonth(DateTime(2024, 3, 31), -1), DateTime(2024, 2, 29));

      var now = DateTime(2024, 2, 28, 12);
      final store = AppStore(clock: () => now);
      await store.load();
      store.selectDate(DateTime(1899, 4, 3, 11));
      expect(store.selectedDate, DateTime(1900));
      store.selectDate(DateTime(2101, 4, 3));
      expect(store.selectedDate, DateTime(2100, 12, 31));
      store.selectDate(DateTime(2024, 2, 28, 22));
      now = DateTime(2024, 2, 29, 9);
      store.refreshToday();
      expect(store.today, DateTime(2024, 2, 29));
      expect(
        store.selectedDate,
        store.today,
        reason: 'selection follows today',
      );
      store.selectDate(DateTime(2024, 2, 20));
      now = DateTime(2024, 3, 1);
      store.refreshToday();
      expect(
        store.selectedDate,
        DateTime(2024, 2, 20),
        reason: 'a manually selected date does not move',
      );

      final monthly = CalendarEntry(
        id: 'month-end',
        title: 'Monthly',
        start: DateTime(2024, 1, 31, 9),
        allDay: false,
        repeat: RepeatRule.monthly,
      );
      final yearly = CalendarEntry(
        id: 'leap-day',
        title: 'Leap day',
        start: DateTime(2024, 2, 29, 9),
        allDay: false,
        repeat: RepeatRule.yearly,
      );
      await store.saveEntry(monthly);
      await store.saveEntry(yearly);
      final monthOccurrences = store.occurrences(
        DateTime(2024, 1, 1),
        DateTime(2024, 6, 1),
      );
      expect(
        monthOccurrences
            .where((o) => o.entry.id == 'month-end')
            .map((o) => o.start.day),
        <int>[31, 31, 31],
      );
      final leapOccurrences = store.occurrences(
        DateTime(2024, 1, 1),
        DateTime(2029, 1, 1),
      );
      expect(
        leapOccurrences
            .where((o) => o.entry.id == 'leap-day')
            .map((o) => o.start.year),
        <int>[2024, 2028],
      );
    });
  });

  group('persistence and CRUD', () {
    test(
      'batch upserts are last-write-wins and reject invalid batches atomically',
      () async {
        final store = AppStore(clock: () => DateTime(2025, 1, 2));
        await store.load();
        CalendarEntry makeEntry(
          String id,
          String title, {
          String calendarId = 'personal',
        }) => CalendarEntry(
          id: id,
          title: title,
          start: DateTime(2025, 1, 3, 9),
          allDay: false,
          calendarId: calendarId,
        );

        await store.saveEntries(<CalendarEntry>[
          makeEntry('a', 'First'),
          makeEntry('b', 'Second'),
          makeEntry('a', 'Last'),
        ]);
        expect(store.entries.map((entry) => entry.id), <String>['a', 'b']);
        expect(store.entries.first.title, 'Last');

        await expectLater(
          store.saveEntries(<CalendarEntry>[
            makeEntry('c', 'Valid'),
            makeEntry('d', 'Invalid', calendarId: 'missing'),
          ]),
          throwsArgumentError,
        );
        expect(store.entries.map((entry) => entry.id), <String>['a', 'b']);
        expect(store.entries.first.title, 'Last');
      },
    );

    test('round-trips settings, calendars, and every entry field', () async {
      final store = AppStore(clock: () => DateTime(2025, 1, 2));
      await store.load();
      await store.setSettings(themeMode: ThemeMode.dark, showLunar: false);
      final calendar = const CalendarGroup(
        id: 'work',
        name: 'Work',
        colorValue: 0xff123456,
        visible: false,
      );
      await store.saveCalendar(calendar);
      final entry = CalendarEntry(
        id: 'entry',
        title: 'Review',
        start: DateTime(2025, 1, 3, 10),
        end: DateTime(2025, 1, 3, 11),
        kind: EntryKind.todo,
        allDay: false,
        starred: true,
        colorValue: 0xffabcdef,
        calendarId: 'work',
        notes: 'Details',
        repeat: RepeatRule.weekly,
        reminderMinutes: 15,
        repeatUntil: DateTime(2025, 3, 1),
        excludedDates: <String>{'2025-01-10'},
        completedDates: <String>{'2025-01-03'},
        createdAt: DateTime(2024, 12, 20),
      );
      await store.saveEntry(entry);

      final restored = AppStore(clock: () => DateTime(2025, 1, 2));
      await restored.load();
      expect(restored.themeMode, ThemeMode.dark);
      expect(restored.showLunar, isFalse);
      expect(restored.calendars, hasLength(2));
      expect(restored.entries, hasLength(1));
      final got = restored.entries.single;
      expect(got.id, entry.id);
      expect(got.title, entry.title);
      expect(got.start, entry.start);
      expect(got.end, entry.end);
      expect(got.kind, EntryKind.todo);
      expect(got.allDay, isFalse);
      expect(got.starred, isTrue);
      expect(got.colorValue, entry.colorValue);
      expect(got.calendarId, 'work');
      expect(got.notes, entry.notes);
      expect(got.repeat, RepeatRule.weekly);
      expect(got.reminderMinutes, 15);
      expect(got.repeatUntil, DateTime(2025, 3, 1));
      expect(got.excludedDates, contains('2025-01-10'));
      expect(got.completedDates, contains('2025-01-03'));
      expect(got.createdAt, DateTime(2024, 12, 20));
      expect(restored.view, '月', reason: 'view is in-memory only');

      await restored.saveEntry(got.copyWith(title: 'Revised'));
      expect(restored.entries.single.title, 'Revised');
      await restored.deleteEntry(restored.entries.single);
      expect(restored.entries, isEmpty);
      await restored.deleteCalendar('work');
      expect(restored.calendars, hasLength(1));
      await expectLater(restored.deleteCalendar('personal'), throwsStateError);
    });

    test(
      'filters hidden calendars and includes overnight events in overlap range',
      () async {
        final store = AppStore(clock: () => DateTime(2025, 1, 1));
        await store.load();
        await store.saveCalendar(
          const CalendarGroup(id: 'hidden', name: 'Hidden', visible: false),
        );
        await store.saveEntry(
          CalendarEntry(
            id: 'night',
            title: 'Overnight',
            start: DateTime(2025, 1, 1, 23),
            end: DateTime(2025, 1, 2, 1),
            allDay: false,
          ),
        );
        await store.saveEntry(
          CalendarEntry(
            id: 'secret',
            title: 'Hidden item',
            start: DateTime(2025, 1, 2, 0, 30),
            allDay: false,
            calendarId: 'hidden',
          ),
        );
        final visible = store.occurrences(
          DateTime(2025, 1, 2),
          DateTime(2025, 1, 2, 2),
        );
        expect(visible.map((o) => o.entry.id), <String>['night']);
        expect(visible.single.start, DateTime(2025, 1, 1, 23));
        expect(visible.single.end, DateTime(2025, 1, 2, 1));
        expect(
          store.occurrences(
            DateTime(2025, 1, 2),
            DateTime(2025, 1, 2, 2),
            visibleOnly: false,
          ),
          hasLength(2),
        );

        await store.deleteCalendar('hidden');
        expect(store.entries.map((entry) => entry.id), <String>['night']);
        await expectLater(store.deleteCalendar('personal'), throwsStateError);
      },
    );
  });

  group('recurrence scopes', () {
    test(
      'single edit and delete detach and exclude exactly one occurrence',
      () async {
        final store = AppStore(clock: () => DateTime(2025, 1, 1));
        await store.load();
        final series = CalendarEntry(
          id: 'daily',
          title: 'Daily',
          start: DateTime(2025, 1, 1, 9),
          end: DateTime(2025, 1, 1, 10),
          allDay: false,
          repeat: RepeatRule.daily,
        );
        await store.saveEntry(series);
        await store.updateEntry(
          series,
          series.copyWith(
            title: 'Special',
            start: DateTime(2025, 1, 3, 11),
            end: DateTime(2025, 1, 3, 12),
          ),
          occurrenceDate: DateTime(2025, 1, 3),
          scope: EditScope.single,
        );
        var occurrences = store.occurrences(
          DateTime(2025, 1, 1),
          DateTime(2025, 1, 6),
        );
        expect(occurrences, hasLength(5));
        expect(
          occurrences.where((o) => o.start.day == 3).single.entry.title,
          'Special',
        );
        expect(
          occurrences.where((o) => o.start.day == 3).single.start,
          DateTime(2025, 1, 3, 11),
        );

        final base = store.entries.singleWhere((entry) => entry.id == 'daily');
        await store.deleteEntry(
          base,
          occurrenceDate: DateTime(2025, 1, 4),
          scope: EditScope.single,
        );
        occurrences = store.occurrences(
          DateTime(2025, 1, 1),
          DateTime(2025, 1, 6),
        );
        expect(occurrences, hasLength(4));
        expect(occurrences.any((o) => o.start.day == 4), isFalse);
        expect(occurrences.any((o) => o.start.day == 3), isTrue);
      },
    );

    test(
      'future edit splits the series, and completion toggles/reopens one day',
      () async {
        final store = AppStore(clock: () => DateTime(2025, 1, 1));
        await store.load();
        final series = CalendarEntry(
          id: 'weekly',
          title: 'Weekly',
          start: DateTime(2025, 1, 1, 9),
          end: DateTime(2025, 1, 1, 10),
          kind: EntryKind.todo,
          allDay: false,
          repeat: RepeatRule.daily,
        );
        await store.saveEntry(series);
        await store.updateEntry(
          series,
          series.copyWith(
            title: 'From Friday',
            start: DateTime(2025, 1, 4, 11),
            end: DateTime(2025, 1, 4, 12),
          ),
          occurrenceDate: DateTime(2025, 1, 4),
          scope: EditScope.future,
        );
        var occurrences = store.occurrences(
          DateTime(2025, 1, 1),
          DateTime(2025, 1, 7),
        );
        expect(occurrences, hasLength(6));
        expect(
          occurrences.take(3).map((o) => o.entry.title),
          everyElement('Weekly'),
        );
        expect(
          occurrences.skip(3).map((o) => o.entry.title),
          everyElement('From Friday'),
        );
        expect(occurrences[3].start, DateTime(2025, 1, 4, 11));

        final futureEntry = occurrences[3].entry;
        await store.toggleDone(
          futureEntry,
          occurrenceDate: DateTime(2025, 1, 5),
        );
        var may5 = store
            .occurrences(DateTime(2025, 1, 5), DateTime(2025, 1, 6))
            .single;
        expect(may5.done, isTrue);
        await store.toggleDone(
          futureEntry,
          occurrenceDate: DateTime(2025, 1, 5),
        );
        may5 = store
            .occurrences(DateTime(2025, 1, 5), DateTime(2025, 1, 6))
            .single;
        expect(may5.done, isFalse);

        await store.deleteEntry(
          futureEntry,
          occurrenceDate: DateTime(2025, 1, 4),
          scope: EditScope.future,
        );
        occurrences = store.occurrences(
          DateTime(2025, 1, 1),
          DateTime(2025, 1, 7),
        );
        expect(occurrences, hasLength(3));
      },
    );
  });

  test('corrupt JSON is reported without replacing the stored value', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'fwcal.app_store.v1': '{not json',
    });
    final preferences = await SharedPreferences.getInstance();
    final store = AppStore(preferences: preferences);
    await expectLater(store.load(), throwsFormatException);
    expect(preferences.getString('fwcal.app_store.v1'), '{not json');
  });
}
