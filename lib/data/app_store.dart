import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

const int _minimumYear = 1900;
const int _maximumYear = 2100;
const String _storageKey = 'fwcal.app_store.v1';

/// Returns a date at local midnight, preserving the input's calendar date.
DateTime dateOnly(DateTime date) => DateTime(date.year, date.month, date.day);

/// A stable, locale-independent key for a calendar date.
String dayKey(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-'
    '${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';

bool sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

/// Shifts by calendar months and clamps the day to the target month's length.
DateTime shiftMonth(DateTime date, int delta) {
  final absoluteMonth = date.year * 12 + date.month - 1 + delta;
  final year = absoluteMonth ~/ 12;
  final month = absoluteMonth % 12 + 1;
  final lastDay = DateTime(year, month + 1, 0).day;
  return DateTime(year, month, date.day.clamp(1, lastDay));
}

DateTime _boundedDate(DateTime value) {
  final normalized = dateOnly(value);
  if (normalized.year < _minimumYear) return DateTime(_minimumYear);
  if (normalized.year > _maximumYear) return DateTime(_maximumYear, 12, 31);
  return normalized;
}

enum EntryKind { event, todo }

enum RepeatRule { none, daily, weekly, monthly, yearly }

enum EditScope { single, future, all }

class CalendarGroup {
  const CalendarGroup({
    required this.id,
    required this.name,
    this.colorValue = 0xff0066ff,
    this.visible = true,
  });

  final String id;
  final String name;
  final int colorValue;
  final bool visible;

  CalendarGroup copyWith({
    String? id,
    String? name,
    int? colorValue,
    bool? visible,
  }) => CalendarGroup(
    id: id ?? this.id,
    name: name ?? this.name,
    colorValue: colorValue ?? this.colorValue,
    visible: visible ?? this.visible,
  );
}

class CalendarEntry {
  CalendarEntry({
    required this.id,
    required this.title,
    required DateTime start,
    this.end,
    this.kind = EntryKind.event,
    this.allDay = true,
    this.starred = false,
    this.done = false,
    this.colorValue = 0xff0066ff,
    this.calendarId = 'personal',
    this.notes = '',
    this.repeat = RepeatRule.none,
    this.reminderMinutes,
    DateTime? repeatUntil,
    Set<String> excludedDates = const <String>{},
    Set<String> completedDates = const <String>{},
    DateTime? createdAt,
  }) : start = start,
       repeatUntil = repeatUntil == null ? null : dateOnly(repeatUntil),
       excludedDates = Set<String>.unmodifiable(excludedDates),
       completedDates = Set<String>.unmodifiable(completedDates),
       createdAt = createdAt ?? start;

  final String id;
  final String title;
  final DateTime start;
  final DateTime? end;
  final EntryKind kind;
  final bool allDay;
  final bool starred;
  final bool done;
  final int colorValue;
  final String calendarId;
  final String notes;
  final RepeatRule repeat;
  final int? reminderMinutes;
  final DateTime? repeatUntil;
  final Set<String> excludedDates;
  final Set<String> completedDates;
  final DateTime createdAt;

  CalendarEntry copyWith({
    String? id,
    String? title,
    DateTime? start,
    DateTime? end,
    bool clearEnd = false,
    EntryKind? kind,
    bool? allDay,
    bool? starred,
    bool? done,
    int? colorValue,
    String? calendarId,
    String? notes,
    RepeatRule? repeat,
    int? reminderMinutes,
    bool clearReminder = false,
    DateTime? repeatUntil,
    bool clearRepeatUntil = false,
    Set<String>? excludedDates,
    Set<String>? completedDates,
    DateTime? createdAt,
  }) => CalendarEntry(
    id: id ?? this.id,
    title: title ?? this.title,
    start: start ?? this.start,
    end: clearEnd ? null : (end ?? this.end),
    kind: kind ?? this.kind,
    allDay: allDay ?? this.allDay,
    starred: starred ?? this.starred,
    done: done ?? this.done,
    colorValue: colorValue ?? this.colorValue,
    calendarId: calendarId ?? this.calendarId,
    notes: notes ?? this.notes,
    repeat: repeat ?? this.repeat,
    reminderMinutes: clearReminder
        ? null
        : (reminderMinutes ?? this.reminderMinutes),
    repeatUntil: clearRepeatUntil ? null : (repeatUntil ?? this.repeatUntil),
    excludedDates: excludedDates ?? this.excludedDates,
    completedDates: completedDates ?? this.completedDates,
    createdAt: createdAt ?? this.createdAt,
  );
}

class EntryOccurrence {
  const EntryOccurrence({
    required this.entry,
    required this.start,
    required this.end,
    required this.done,
  });

  final CalendarEntry entry;
  final DateTime start;
  final DateTime end;
  final bool done;
}

class AppStore extends ChangeNotifier {
  AppStore({this.preferences, DateTime Function()? clock})
    : _clock = clock ?? DateTime.now {
    _today = _boundedDate(_clock());
    _selectedDate = _today;
  }

  SharedPreferences? preferences;
  final DateTime Function() _clock;
  late DateTime _today;
  late DateTime _selectedDate;
  String _view = '月';
  ThemeMode _themeMode = ThemeMode.system;
  bool _showLunar = true;
  Future<void> _commitTail = Future<void>.value();
  List<CalendarGroup> _calendars = <CalendarGroup>[
    const CalendarGroup(id: 'personal', name: '我的日历'),
  ];
  List<CalendarEntry> _entries = <CalendarEntry>[];

  DateTime get selectedDate => _selectedDate;
  DateTime get today => _today;
  String get view => _view;
  ThemeMode get themeMode => _themeMode;
  bool get showLunar => _showLunar;
  List<CalendarGroup> get calendars =>
      List<CalendarGroup>.unmodifiable(_calendars);
  List<CalendarEntry> get entries => List<CalendarEntry>.unmodifiable(_entries);

  Future<SharedPreferences> get _prefs async =>
      preferences ??= await SharedPreferences.getInstance();

  Future<void> load() async {
    final prefs = await _prefs;
    final raw = prefs.getString(_storageKey);
    if (raw == null) {
      _refreshTodayWithoutNotify();
      return;
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('根节点必须是 JSON 对象');
      }
      final loadedCalendars = _decodeCalendars(decoded['calendars']);
      final loadedEntries = _decodeEntries(decoded['entries']);
      final loadedTheme = _enumValue(
        ThemeMode.values,
        decoded['themeMode'],
        ThemeMode.system,
        'themeMode',
      );
      final loadedShowLunar = decoded['showLunar'] is bool
          ? decoded['showLunar'] as bool
          : true;
      _calendars = loadedCalendars.isEmpty
          ? <CalendarGroup>[const CalendarGroup(id: 'personal', name: '我的日历')]
          : loadedCalendars;
      _entries = loadedEntries;
      _themeMode = loadedTheme;
      _showLunar = loadedShowLunar;
      _refreshTodayWithoutNotify();
    } on FormatException catch (error) {
      throw FormatException('无法读取已保存的日历数据：${error.message}');
    } catch (error) {
      throw FormatException('无法读取已保存的日历数据：$error');
    }
    notifyListeners();
  }

  void selectDate(DateTime date) {
    _selectedDate = _boundedDate(date);
    notifyListeners();
  }

  void moveMonth(int amount) {
    final moved = shiftMonth(_selectedDate, amount);
    _selectedDate = _boundedDate(moved);
    notifyListeners();
  }

  void goToday() {
    _today = _boundedDate(_clock());
    _selectedDate = _today;
    notifyListeners();
  }

  void refreshToday() {
    _refreshTodayWithoutNotify();
    notifyListeners();
  }

  void _refreshTodayWithoutNotify() {
    final followedToday = sameDay(_selectedDate, _today);
    _today = _boundedDate(_clock());
    if (followedToday) _selectedDate = _today;
  }

  void setView(String value) {
    _view = value;
    notifyListeners();
  }

  Future<void> setSettings({ThemeMode? themeMode, bool? showLunar}) async {
    await _commit(() {
      if (themeMode != null) _themeMode = themeMode;
      if (showLunar != null) _showLunar = showLunar;
    });
  }

  Future<void> saveEntry(CalendarEntry entry) async {
    if (!_calendars.any((calendar) => calendar.id == entry.calendarId)) {
      throw ArgumentError.value(entry.calendarId, 'entry.calendarId', '日历不存在');
    }
    await _commit(() {
      if (!_calendars.any((calendar) => calendar.id == entry.calendarId)) {
        throw ArgumentError.value(
          entry.calendarId,
          'entry.calendarId',
          '日历不存在',
        );
      }
      final index = _entries.indexWhere((existing) => existing.id == entry.id);
      if (index == -1) {
        _entries = <CalendarEntry>[..._entries, entry];
      } else {
        _entries = List<CalendarEntry>.of(_entries)..[index] = entry;
      }
    });
  }

  Future<void> saveEntries(Iterable<CalendarEntry> entries) async {
    final batch = entries.toList(growable: false);
    final calendarIds = _calendars.map((calendar) => calendar.id).toSet();
    for (final entry in batch) {
      if (!calendarIds.contains(entry.calendarId)) {
        throw ArgumentError.value(
          entry.calendarId,
          'entry.calendarId',
          '日历不存在',
        );
      }
    }
    if (batch.isEmpty) return;
    await _commit(() {
      final currentCalendarIds = _calendars
          .map((calendar) => calendar.id)
          .toSet();
      for (final entry in batch) {
        if (!currentCalendarIds.contains(entry.calendarId)) {
          throw ArgumentError.value(
            entry.calendarId,
            'entry.calendarId',
            '日历不存在',
          );
        }
      }
      final updated = List<CalendarEntry>.of(_entries);
      for (final entry in batch) {
        final index = updated.indexWhere((existing) => existing.id == entry.id);
        if (index == -1) {
          updated.add(entry);
        } else {
          updated[index] = entry;
        }
      }
      _entries = updated;
    });
  }

  Future<void> deleteEntry(
    CalendarEntry entry, {
    DateTime? occurrenceDate,
    EditScope scope = EditScope.all,
  }) async {
    final existing = _findEntry(entry.id);
    if (existing == null) return;
    await _commit(() {
      if (existing.repeat == RepeatRule.none || scope == EditScope.all) {
        _entries = _entries.where((item) => item.id != existing.id).toList();
      } else {
        final target = dateOnly(occurrenceDate ?? existing.start);
        if (scope == EditScope.single) {
          _replaceEntry(
            existing.copyWith(
              excludedDates: <String>{
                ...existing.excludedDates,
                dayKey(target),
              },
            ),
          );
        } else if (!target.isAfter(dateOnly(existing.start))) {
          _entries = _entries.where((item) => item.id != existing.id).toList();
        } else {
          _replaceEntry(
            existing.copyWith(
              repeatUntil: DateTime(target.year, target.month, target.day - 1),
            ),
          );
        }
      }
    });
  }

  Future<void> toggleDone(
    CalendarEntry entry, {
    DateTime? occurrenceDate,
  }) async {
    await _commit(() {
      final existing = _findEntry(entry.id);
      if (existing == null) return;
      if (existing.repeat == RepeatRule.none) {
        _replaceEntry(existing.copyWith(done: !existing.done));
      } else {
        final key = dayKey(occurrenceDate ?? existing.start);
        final completed = <String>{...existing.completedDates};
        if (!completed.add(key)) completed.remove(key);
        _replaceEntry(existing.copyWith(completedDates: completed));
      }
    });
  }

  Future<void> saveCalendar(CalendarGroup calendar) async {
    await _commit(() {
      final index = _calendars.indexWhere((item) => item.id == calendar.id);
      if (index == -1) {
        _calendars = <CalendarGroup>[..._calendars, calendar];
      } else {
        _calendars = List<CalendarGroup>.of(_calendars)..[index] = calendar;
      }
    });
  }

  Future<void> deleteCalendar(String id) async {
    await _commit(() {
      if (!_calendars.any((calendar) => calendar.id == id)) return;
      if (_calendars.length == 1) {
        throw StateError('至少需要保留一个日历');
      }
      _calendars = _calendars.where((calendar) => calendar.id != id).toList();
      _entries = _entries.where((entry) => entry.calendarId != id).toList();
    });
  }

  Future<void> updateEntry(
    CalendarEntry original,
    CalendarEntry replacement, {
    DateTime? occurrenceDate,
    EditScope scope = EditScope.all,
  }) async {
    final existing = _findEntry(original.id);
    if (existing == null) throw StateError('找不到要修改的日程：${original.id}');
    if (!_calendars.any((calendar) => calendar.id == replacement.calendarId)) {
      throw ArgumentError.value(
        replacement.calendarId,
        'replacement.calendarId',
        '日历不存在',
      );
    }
    await _commit(() {
      final startShift = _calendarDayDelta(existing.start, replacement.start);
      final repeatUntilWasEdited =
          replacement.repeatUntil != existing.repeatUntil;
      if (existing.repeat == RepeatRule.none || scope == EditScope.all) {
        _replaceEntry(
          replacement.copyWith(
            id: existing.id,
            repeatUntil:
                !repeatUntilWasEdited && replacement.repeatUntil != null
                ? _shiftCalendarDate(replacement.repeatUntil!, startShift)
                : replacement.repeatUntil,
            excludedDates: _shiftDateKeys(
              replacement.excludedDates,
              startShift,
            ),
            completedDates: _shiftDateKeys(
              replacement.completedDates,
              startShift,
            ),
          ),
        );
      } else {
        final target = dateOnly(occurrenceDate ?? existing.start);
        if (scope == EditScope.single) {
          final detachedId =
              replacement.id == existing.id ||
                  _entries.any((item) => item.id == replacement.id)
              ? _newEntryId(
                  existing.id,
                  target,
                  _entries.map((item) => item.id).toSet(),
                )
              : replacement.id;
          _replaceEntry(
            existing.copyWith(
              excludedDates: <String>{
                ...existing.excludedDates,
                dayKey(target),
              },
            ),
          );
          _entries = <CalendarEntry>[
            ..._entries,
            replacement.copyWith(
              id: detachedId,
              start: _rebaseEntryStart(
                replacement.start,
                existing.start,
                target,
              ),
              end: _rebaseEntryEnd(replacement, existing.start, target),
              repeat: RepeatRule.none,
              clearRepeatUntil: true,
              excludedDates: const <String>{},
              completedDates: const <String>{},
              done: existing.completedDates.contains(dayKey(target)),
            ),
          ];
        } else if (!target.isAfter(dateOnly(existing.start))) {
          _replaceEntry(replacement.copyWith(id: existing.id));
        } else {
          final priorEnd = DateTime(target.year, target.month, target.day - 1);
          _replaceEntry(existing.copyWith(repeatUntil: priorEnd));
          final futureId =
              replacement.id == existing.id ||
                  _entries.any((item) => item.id == replacement.id)
              ? _newEntryId(
                  existing.id,
                  target,
                  _entries.map((item) => item.id).toSet(),
                )
              : replacement.id;
          final shiftedRepeatUntil =
              !repeatUntilWasEdited && replacement.repeatUntil != null
              ? _shiftCalendarDate(replacement.repeatUntil!, startShift)
              : replacement.repeatUntil;
          _entries = <CalendarEntry>[
            ..._entries,
            replacement.copyWith(
              id: futureId,
              start: _rebaseEntryStart(
                replacement.start,
                existing.start,
                target,
              ),
              end: _rebaseEntryEnd(replacement, existing.start, target),
              repeatUntil: shiftedRepeatUntil,
              excludedDates: _shiftFutureDateKeys(
                replacement.excludedDates,
                startShift,
                from: target,
              ),
              completedDates: <String>{
                ..._shiftFutureDateKeys(
                  replacement.completedDates,
                  startShift,
                  from: target,
                ),
              },
            ),
          ];
        }
      }
    });
  }

  List<EntryOccurrence> occurrences(
    DateTime from,
    DateTime to, {
    bool visibleOnly = true,
  }) {
    if (!to.isAfter(from)) return <EntryOccurrence>[];
    final visibleIds = _calendars
        .where((calendar) => !visibleOnly || calendar.visible)
        .map((calendar) => calendar.id)
        .toSet();
    final result = <EntryOccurrence>[];
    for (final entry in _entries) {
      if (!visibleIds.contains(entry.calendarId)) continue;
      final rawDuration = entry.end == null
          ? (entry.allDay ? const Duration(days: 1) : Duration.zero)
          : entry.end!.difference(entry.start);
      final duration = rawDuration.isNegative ? Duration.zero : rawDuration;
      final daySpan = entry.end == null
          ? 1
          : _calendarDayDelta(entry.start, entry.end!);
      final allDaySpan = daySpan < 1 ? 1 : daySpan;
      final lastDay = dateOnly(to.subtract(const Duration(microseconds: 1)));
      final overlapStart = entry.allDay
          ? DateTime(from.year, from.month, from.day - allDaySpan)
          : duration > Duration.zero
          ? dateOnly(from.subtract(duration))
          : dateOnly(from);
      var candidate = dateOnly(entry.start);
      if (entry.repeat != RepeatRule.none && candidate.isBefore(overlapStart)) {
        candidate = overlapStart;
      }
      while (!candidate.isAfter(lastDay)) {
        if (candidate.isBefore(dateOnly(entry.start)) ||
            (entry.repeatUntil != null &&
                candidate.isAfter(entry.repeatUntil!))) {
          candidate = _nextCalendarDate(candidate);
          continue;
        }
        final occurrenceDate = _recurrenceDate(entry, candidate);
        if (occurrenceDate != null) {
          final key = dayKey(occurrenceDate);
          if (!entry.excludedDates.contains(key)) {
            final occurrenceStart = DateTime(
              occurrenceDate.year,
              occurrenceDate.month,
              occurrenceDate.day,
              entry.allDay ? 0 : entry.start.hour,
              entry.allDay ? 0 : entry.start.minute,
              entry.allDay ? 0 : entry.start.second,
              entry.allDay ? 0 : entry.start.millisecond,
              entry.allDay ? 0 : entry.start.microsecond,
            );
            final occurrenceEnd = entry.allDay
                ? DateTime(
                    occurrenceStart.year,
                    occurrenceStart.month,
                    occurrenceStart.day + allDaySpan,
                  )
                : occurrenceStart.add(duration);
            final overlaps = !entry.allDay && duration == Duration.zero
                ? !occurrenceStart.isBefore(from) &&
                      occurrenceStart.isBefore(to)
                : occurrenceEnd.isAfter(from) && occurrenceStart.isBefore(to);
            if (overlaps) {
              result.add(
                EntryOccurrence(
                  entry: entry,
                  start: occurrenceStart,
                  end: occurrenceEnd,
                  done: entry.repeat == RepeatRule.none
                      ? entry.done
                      : entry.completedDates.contains(key),
                ),
              );
            }
          }
        }
        if (entry.repeat == RepeatRule.none) break;
        candidate = _nextCalendarDate(candidate);
      }
    }
    result.sort((a, b) {
      final byStart = a.start.compareTo(b.start);
      return byStart != 0 ? byStart : a.entry.title.compareTo(b.entry.title);
    });
    return result;
  }

  DateTime _nextCalendarDate(DateTime date) =>
      DateTime(date.year, date.month, date.day + 1);

  void _replaceEntry(CalendarEntry replacement) {
    final index = _entries.indexWhere((entry) => entry.id == replacement.id);
    if (index < 0) {
      _entries = <CalendarEntry>[..._entries, replacement];
    } else {
      _entries = List<CalendarEntry>.of(_entries)..[index] = replacement;
    }
  }

  Future<void> _persist() async {
    final prefs = await _prefs;
    final value = jsonEncode(<String, Object?>{
      'version': 1,
      'themeMode': _themeMode.name,
      'showLunar': _showLunar,
      'calendars': _calendars.map(_encodeCalendar).toList(),
      'entries': _entries.map(_encodeEntry).toList(),
    });
    final saved = await prefs.setString(_storageKey, value);
    if (!saved) throw StateError('保存日历数据失败（SharedPreferences 拒绝写入）');
  }

  CalendarEntry? _findEntry(String id) {
    for (final entry in _entries) {
      if (entry.id == id) return entry;
    }
    return null;
  }

  Future<void> _commit(void Function() mutation) {
    final operation = _commitTail.catchError((Object _) {}).then((_) async {
      final oldCalendars = _calendars;
      final oldEntries = _entries;
      final oldThemeMode = _themeMode;
      final oldShowLunar = _showLunar;
      try {
        mutation();
        await _persist();
      } catch (_) {
        _calendars = oldCalendars;
        _entries = oldEntries;
        _themeMode = oldThemeMode;
        _showLunar = oldShowLunar;
        rethrow;
      }
      notifyListeners();
    });
    _commitTail = operation;
    return operation;
  }

  Map<String, Object?> _encodeCalendar(CalendarGroup calendar) =>
      <String, Object?>{
        'id': calendar.id,
        'name': calendar.name,
        'colorValue': calendar.colorValue,
        'visible': calendar.visible,
      };

  Map<String, Object?> _encodeEntry(CalendarEntry entry) => <String, Object?>{
    'id': entry.id,
    'title': entry.title,
    'start': entry.start.toIso8601String(),
    'end': entry.end?.toIso8601String(),
    'kind': entry.kind.name,
    'allDay': entry.allDay,
    'starred': entry.starred,
    'done': entry.done,
    'colorValue': entry.colorValue,
    'calendarId': entry.calendarId,
    'notes': entry.notes,
    'repeat': entry.repeat.name,
    'reminderMinutes': entry.reminderMinutes,
    'repeatUntil': entry.repeatUntil?.toIso8601String(),
    'excludedDates': entry.excludedDates.toList()..sort(),
    'completedDates': entry.completedDates.toList()..sort(),
    'createdAt': entry.createdAt.toIso8601String(),
  };

  List<CalendarGroup> _decodeCalendars(Object? value) {
    if (value == null) return <CalendarGroup>[];
    if (value is! List) throw const FormatException('calendars 必须是数组');
    return value.map((item) {
      final map = _map(item, 'calendar');
      return CalendarGroup(
        id: _requiredString(map['id'], 'calendar.id'),
        name: _requiredString(map['name'], 'calendar.name'),
        colorValue: _int(map['colorValue'], 0xff0066ff, 'calendar.colorValue'),
        visible: _bool(map['visible'], true, 'calendar.visible'),
      );
    }).toList();
  }

  List<CalendarEntry> _decodeEntries(Object? value) {
    if (value == null) return <CalendarEntry>[];
    if (value is! List) throw const FormatException('entries 必须是数组');
    return value.map((item) {
      final map = _map(item, 'entry');
      return CalendarEntry(
        id: _requiredString(map['id'], 'entry.id'),
        title: _requiredString(map['title'], 'entry.title'),
        start: _parseDateTime(map['start'], 'entry.start'),
        end: map['end'] == null
            ? null
            : _parseDateTime(map['end'], 'entry.end'),
        kind: _enumValue(
          EntryKind.values,
          map['kind'],
          EntryKind.event,
          'entry.kind',
        ),
        allDay: _bool(map['allDay'], true, 'entry.allDay'),
        starred: _bool(map['starred'], false, 'entry.starred'),
        done: _bool(map['done'], false, 'entry.done'),
        colorValue: _int(map['colorValue'], 0xff0066ff, 'entry.colorValue'),
        calendarId: _string(map['calendarId'], 'personal'),
        notes: _string(map['notes'], ''),
        repeat: _enumValue(
          RepeatRule.values,
          map['repeat'],
          RepeatRule.none,
          'entry.repeat',
        ),
        reminderMinutes: map['reminderMinutes'] == null
            ? null
            : _int(map['reminderMinutes'], 0, 'entry.reminderMinutes'),
        repeatUntil: map['repeatUntil'] == null
            ? null
            : _parseDateTime(map['repeatUntil'], 'entry.repeatUntil'),
        excludedDates: _stringSet(map['excludedDates'], 'entry.excludedDates'),
        completedDates: _stringSet(
          map['completedDates'],
          'entry.completedDates',
        ),
        createdAt: map['createdAt'] == null
            ? _parseDateTime(map['start'], 'entry.start')
            : _parseDateTime(map['createdAt'], 'entry.createdAt'),
      );
    }).toList();
  }
}

DateTime? _recurrenceDate(CalendarEntry entry, DateTime candidate) {
  final start = dateOnly(entry.start);
  if (candidate.isBefore(start)) return null;
  final days = _calendarDayDelta(start, candidate);
  switch (entry.repeat) {
    case RepeatRule.none:
      return sameDay(candidate, start) ? candidate : null;
    case RepeatRule.daily:
      return candidate;
    case RepeatRule.weekly:
      return days % 7 == 0 ? candidate : null;
    case RepeatRule.monthly:
      return candidate.day == start.day ? candidate : null;
    case RepeatRule.yearly:
      return candidate.month == start.month && candidate.day == start.day
          ? candidate
          : null;
  }
}

DateTime _dateForOccurrence(
  DateTime replacementStart,
  DateTime occurrenceDate,
) => DateTime(
  occurrenceDate.year,
  occurrenceDate.month,
  occurrenceDate.day,
  replacementStart.hour,
  replacementStart.minute,
  replacementStart.second,
  replacementStart.millisecond,
  replacementStart.microsecond,
);

DateTime _rebaseEntryStart(
  DateTime replacementStart,
  DateTime masterStart,
  DateTime occurrenceDate,
) {
  if (sameDay(replacementStart, masterStart) ||
      sameDay(replacementStart, occurrenceDate)) {
    return _dateForOccurrence(replacementStart, occurrenceDate);
  }
  final occurrenceDay = _shiftCalendarDate(
    occurrenceDate,
    _calendarDayDelta(masterStart, replacementStart),
  );
  return _dateForOccurrence(replacementStart, occurrenceDay);
}

DateTime? _rebaseEntryEnd(
  CalendarEntry replacement,
  DateTime masterStart,
  DateTime occurrenceDate,
) {
  if (replacement.end == null) return null;
  final shiftedStart = _rebaseEntryStart(
    replacement.start,
    masterStart,
    occurrenceDate,
  );
  final end = replacement.end!;
  return DateTime(
    shiftedStart.year,
    shiftedStart.month,
    shiftedStart.day + _calendarDayDelta(replacement.start, end),
    end.hour,
    end.minute,
    end.second,
    end.millisecond,
    end.microsecond,
  );
}

int _calendarDayDelta(DateTime from, DateTime to) => DateTime.utc(
  to.year,
  to.month,
  to.day,
).difference(DateTime.utc(from.year, from.month, from.day)).inDays;

DateTime _shiftCalendarDate(DateTime date, int dayDelta) =>
    DateTime(date.year, date.month, date.day + dayDelta);

Set<String> _shiftDateKeys(
  Iterable<String> keys,
  int dayDelta, {
  DateTime? from,
}) => keys.map((key) {
  final parsed = DateTime.tryParse(key);
  if (parsed == null ||
      (from != null && dateOnly(parsed).isBefore(dateOnly(from)))) {
    return key;
  }
  return dayKey(_shiftCalendarDate(parsed, dayDelta));
}).toSet();

Set<String> _shiftFutureDateKeys(
  Iterable<String> keys,
  int dayDelta, {
  required DateTime from,
}) => keys
    .map((key) {
      final parsed = DateTime.tryParse(key);
      if (parsed == null) return key;
      if (dateOnly(parsed).isBefore(dateOnly(from))) return null;
      return dayKey(_shiftCalendarDate(parsed, dayDelta));
    })
    .whereType<String>()
    .toSet();

String _newEntryId(String base, DateTime date, Set<String> existingIds) {
  final root = '${base}_${dayKey(date)}_split';
  var candidate = root;
  var suffix = 2;
  while (existingIds.contains(candidate)) {
    candidate = '${root}_$suffix';
    suffix++;
  }
  return candidate;
}

Map<String, dynamic> _map(Object? value, String label) {
  if (value is Map<String, dynamic>) return value;
  throw FormatException('$label 必须是对象');
}

String _string(Object? value, String fallback) {
  if (value == null) return fallback;
  if (value is String) return value;
  throw const FormatException('文本字段格式无效');
}

String _requiredString(Object? value, String label) {
  if (value is String && value.isNotEmpty) return value;
  throw FormatException('$label 必须是非空字符串');
}

int _int(Object? value, int fallback, String label) {
  if (value == null) return fallback;
  if (value is int) return value;
  throw FormatException('$label 必须是整数');
}

bool _bool(Object? value, bool fallback, String label) {
  if (value == null) return fallback;
  if (value is bool) return value;
  throw FormatException('$label 必须是布尔值');
}

Set<String> _stringSet(Object? value, String label) {
  if (value == null) return <String>{};
  if (value is! List || value.any((item) => item is! String)) {
    throw FormatException('$label 必须是字符串数组');
  }
  return value.cast<String>().toSet();
}

DateTime _parseDateTime(Object? value, String label) {
  if (value is! String) throw FormatException('$label 必须是日期字符串');
  final parsed = DateTime.tryParse(value);
  if (parsed == null) throw FormatException('$label 日期无效：$value');
  return parsed;
}

T _enumValue<T extends Enum>(
  List<T> values,
  Object? name,
  T fallback,
  String label,
) {
  if (name == null) return fallback;
  for (final value in values) {
    if (value.name == name) return value;
  }
  throw FormatException('$label 未知值：$name');
}
