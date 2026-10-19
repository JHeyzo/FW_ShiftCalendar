import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fwcal/calendar/lunar.dart';
import 'package:fwcal/data/app_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  // Run the complete suite with TZ=America/New_York to exercise native local
  // DateTime DST arithmetic, not merely UTC or a timezone database simulation.
  test(
    'real DST transitions retain local dates and 09:00 recurring wall time',
    () async {
      final store = AppStore();
      await store.load();
      addTearDown(store.dispose);
      for (final transition in [
        (day: DateTime(2026, 3, 8), hours: 23, before: -5, after: -4),
        (day: DateTime(2026, 11, 1), hours: 25, before: -4, after: -5),
      ]) {
        final day = transition.day;
        final next = DateTime(day.year, day.month, day.day + 1);
        expect(day.timeZoneOffset, Duration(hours: transition.before));
        expect(next.timeZoneOffset, Duration(hours: transition.after));
        expect(next.difference(day).inHours, transition.hours);
        expect(dayNumber(next) - dayNumber(day), 1);
        await store.saveEntries([
          CalendarEntry(
            id: 'all-day-${day.month}',
            title: '全天跨夏令时',
            start: DateTime(day.year, day.month, day.day - 7),
            repeat: RepeatRule.weekly,
          ),
          CalendarEntry(
            id: 'timed-${day.month}',
            title: '每天九点',
            start: DateTime(day.year, day.month, day.day - 1, 9),
            end: DateTime(day.year, day.month, day.day - 1, 10),
            allDay: false,
            repeat: RepeatRule.daily,
          ),
        ]);
        final allDay = store
            .occurrences(day, next)
            .singleWhere((item) => item.entry.id == 'all-day-${day.month}');
        expect(allDay.start, day);
        expect(allDay.end, next);
        expect(allDay.end.difference(allDay.start).inHours, transition.hours);
        final timed = store
            .occurrences(
              DateTime(day.year, day.month, day.day - 1),
              DateTime(day.year, day.month, day.day + 2),
            )
            .where((item) => item.entry.id == 'timed-${day.month}')
            .toList();
        expect(timed, hasLength(3));
        expect(
          timed.map((item) => item.start.day),
          [
            day.day - 1,
            day.day,
            day.day + 1,
          ].map((d) => DateTime(day.year, day.month, d).day),
        );
        for (final item in timed) {
          expect(item.start.hour, 9);
          expect(item.end.hour, 10);
        }
      }
    },
    skip: Platform.environment['TZ'] != 'America/New_York'
        ? 'Requires TZ=America/New_York; included in the full validation command.'
        : false,
  );

  test('day keys stay consecutive across spring and autumn clock changes', () {
    for (final date in [
      DateTime(2026, 3, 7),
      DateTime(2026, 3, 8),
      DateTime(2026, 10, 31),
      DateTime(2026, 11, 1),
    ]) {
      final next = DateTime(date.year, date.month, date.day + 1);
      expect(dayNumber(next) - dayNumber(date), 1);
    }
    expect(isoWeekNumber(DateTime(2021, 1, 1)), 53);
    expect(isoWeekNumber(DateTime(2021, 1, 4)), 1);
    expect(isoWeekNumber(DateTime(2018, 12, 31)), 1);
  });

  test(
    'all-day occurrences end at the next local midnight, not after 24 hours',
    () async {
      final store = AppStore();
      await store.load();
      await store.saveEntry(
        CalendarEntry(
          id: 'all-day',
          title: '每天全天',
          start: DateTime(2026, 3, 7),
          allDay: true,
          repeat: RepeatRule.daily,
          repeatUntil: DateTime(2026, 3, 10),
        ),
      );
      final items = store.occurrences(
        DateTime(2026, 3, 9),
        DateTime(2026, 3, 10),
      );
      expect(items, hasLength(1));
      expect(items.single.start, DateTime(2026, 3, 9));
      expect(items.single.end, DateTime(2026, 3, 10));
      final spring = store
          .occurrences(DateTime(2026, 3, 8), DateTime(2026, 3, 9))
          .single;
      expect(spring.end, DateTime(2026, 3, 9));
      store.dispose();
    },
  );

  test('all-day multi-date recurrence preserves its calendar span', () async {
    final store = AppStore();
    await store.load();
    await store.saveEntry(
      CalendarEntry(
        id: 'multi',
        title: '两天',
        start: DateTime(2026, 3, 1),
        end: DateTime(2026, 3, 3),
        allDay: true,
        repeat: RepeatRule.weekly,
      ),
    );
    final items = store.occurrences(
      DateTime(2026, 3, 8),
      DateTime(2026, 3, 10),
    );
    expect(items, hasLength(1));
    expect(items.single.start, DateTime(2026, 3, 8));
    expect(items.single.end, DateTime(2026, 3, 10));
    store.dispose();
  });
}
