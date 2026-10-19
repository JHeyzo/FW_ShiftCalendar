import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fwcal/data/app_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'zero-duration events at the left range boundary are included only once',
    () async {
      final store = AppStore();
      await store.load();
      final date = DateTime(2026, 10, 19);
      await store.saveEntry(
        CalendarEntry(id: 'point', title: '交接点', start: date, allDay: false),
      );
      expect(store.occurrences(date, DateTime(2026, 10, 20)), hasLength(1));
      expect(store.occurrences(DateTime(2026, 10, 18), date), isEmpty);
      store.dispose();
    },
  );

  test(
    'concurrent completion toggles read the latest committed state',
    () async {
      final store = AppStore();
      await store.load();
      final entry = CalendarEntry(
        id: 'task',
        title: '交接',
        start: DateTime(2026, 10, 19),
        kind: EntryKind.todo,
      );
      await store.saveEntry(entry);
      await Future.wait([store.toggleDone(entry), store.toggleDone(entry)]);
      expect(store.entries.single.done, isFalse);
      final restored = AppStore();
      await restored.load();
      expect(restored.entries.single.done, isFalse);
      store.dispose();
      restored.dispose();
    },
  );

  test(
    'concurrent calendar deletes cannot remove the last remaining calendar',
    () async {
      final store = AppStore();
      await store.load();
      await store.saveCalendar(const CalendarGroup(id: 'work', name: '工作'));
      final outcomes = await Future.wait([
        store
            .deleteCalendar('personal')
            .then((_) => true, onError: (_) => false),
        store.deleteCalendar('work').then((_) => true, onError: (_) => false),
      ]);
      expect(outcomes.where((value) => value), hasLength(1));
      expect(store.calendars, hasLength(1));
      store.dispose();
    },
  );

  test('a queued batch cannot create entries in a calendar deleted before it commits', () async {
    final store = AppStore();
    await store.load();
    await store.saveCalendar(const CalendarGroup(id: 'work', name: '工作'));
    final deletion = store.deleteCalendar('work');
    final write = store.saveEntries([
      CalendarEntry(
        id: 'orphan',
        title: '不应成为孤立记录',
        start: DateTime(2026, 10, 19),
        calendarId: 'work',
      ),
    ]);
    await expectLater(write, throwsArgumentError);
    await deletion;
    expect(store.entries, isEmpty);
    store.dispose();
  });
}
