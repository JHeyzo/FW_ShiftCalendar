import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fwcal/calendar/lunar.dart';
import 'package:fwcal/data/app_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

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
