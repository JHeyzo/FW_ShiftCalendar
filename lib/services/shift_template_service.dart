import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../data/app_store.dart';

const String shiftTemplateStorageKey = 'fwcal.shift_templates.v1';

/// Counts local calendar-date boundaries without assuming every day is 24 hours.
int shiftCalendarDaysBetween(DateTime first, DateTime last) => DateTime.utc(
  last.year,
  last.month,
  last.day,
).difference(DateTime.utc(first.year, first.month, first.day)).inDays;

/// A single day in a repeating shift cycle. Times are local wall-clock minutes.
class ShiftStep {
  const ShiftStep({
    required this.name,
    required this.colorValue,
    required this.isRest,
    this.startMinute = 9 * 60,
    this.endMinute = 17 * 60,
    this.overnight = false,
  });

  final String name;
  final int colorValue;
  final bool isRest;
  final int startMinute;
  final int endMinute;
  final bool overnight;

  ShiftStep copyWith({
    String? name,
    int? colorValue,
    bool? isRest,
    int? startMinute,
    int? endMinute,
    bool? overnight,
  }) => ShiftStep(
    name: name ?? this.name,
    colorValue: colorValue ?? this.colorValue,
    isRest: isRest ?? this.isRest,
    startMinute: startMinute ?? this.startMinute,
    endMinute: endMinute ?? this.endMinute,
    overnight: overnight ?? this.overnight,
  );

  Map<String, Object> toJson() => <String, Object>{
    'name': name,
    'colorValue': colorValue,
    'isRest': isRest,
    'startMinute': startMinute,
    'endMinute': endMinute,
    'overnight': overnight,
  };

  factory ShiftStep.fromJson(Object? value) {
    if (value is! Map) throw const FormatException('班次步骤格式无效');
    return ShiftStep(
      name: value['name'] is String ? value['name'] as String : '班次',
      colorValue: value['colorValue'] is int
          ? value['colorValue'] as int
          : 0xff0066ff,
      isRest: value['isRest'] == true,
      startMinute: value['startMinute'] is int
          ? value['startMinute'] as int
          : 9 * 60,
      endMinute: value['endMinute'] is int
          ? value['endMinute'] as int
          : 17 * 60,
      overnight: value['overnight'] == true,
    );
  }
}

class ShiftTemplate {
  ShiftTemplate({
    required this.id,
    required this.name,
    required List<ShiftStep> steps,
    this.isBuiltIn = false,
  }) : steps = List<ShiftStep>.unmodifiable(steps) {
    validate();
  }

  final String id;
  final String name;
  final List<ShiftStep> steps;
  final bool isBuiltIn;

  void validate() {
    if (id.trim().isEmpty) throw ArgumentError('模板 ID 不能为空');
    if (name.trim().isEmpty) throw ArgumentError('模板名称不能为空');
    if (steps.isEmpty || steps.length > 31) {
      throw ArgumentError('循环步骤必须为 1–31 天');
    }
    for (final step in steps) {
      if (step.name.trim().isEmpty) throw ArgumentError('班次名称不能为空');
      if (step.startMinute < 0 ||
          step.startMinute >= 1440 ||
          step.endMinute < 0 ||
          step.endMinute >= 1440) {
        throw ArgumentError('班次时刻必须在 00:00–23:59');
      }
    }
  }

  ShiftTemplate copyWith({String? id, String? name, List<ShiftStep>? steps}) =>
      ShiftTemplate(
        id: id ?? this.id,
        name: name ?? this.name,
        steps: steps ?? this.steps,
        isBuiltIn: isBuiltIn,
      );

  Map<String, Object> toJson() => <String, Object>{
    'id': id,
    'name': name,
    'isBuiltIn': isBuiltIn,
    'steps': steps.map((step) => step.toJson()).toList(),
  };

  factory ShiftTemplate.fromJson(Object? value) {
    if (value is! Map || value['steps'] is! List) {
      throw const FormatException('排班模板格式无效');
    }
    return ShiftTemplate(
      id: value['id'] is String ? value['id'] as String : '',
      name: value['name'] is String ? value['name'] as String : '',
      isBuiltIn: value['isBuiltIn'] == true,
      steps: (value['steps'] as List).map(ShiftStep.fromJson).toList(),
    );
  }
}

enum ShiftConflictPolicy { keep, skip }

class ShiftApplicationPreview {
  const ShiftApplicationPreview({
    required this.totalDays,
    required this.workDays,
    required this.restDays,
    required this.entriesToGenerate,
    required this.conflictCount,
  });

  final int totalDays;
  final int workDays;
  final int restDays;
  final int entriesToGenerate;
  final int conflictCount;
}

class ShiftApplicationResult {
  const ShiftApplicationResult({
    required this.createdOrUpdated,
    required this.skippedConflicts,
  });

  final int createdOrUpdated;
  final int skippedConflicts;
}

/// Owns shift-template persistence and generation; templates use an independent
/// SharedPreferences key and never mutate/remove unrelated calendar entries.
class ShiftTemplateService {
  ShiftTemplateService({this.preferences});

  SharedPreferences? preferences;
  Future<SharedPreferences> get _prefs async =>
      preferences ??= await SharedPreferences.getInstance();

  static List<ShiftTemplate> get builtIns => <ShiftTemplate>[
    ShiftTemplate(
      id: 'builtin-early-late-night-rest',
      name: '早晚夜休',
      isBuiltIn: true,
      steps: const <ShiftStep>[
        ShiftStep(
          name: '早班',
          colorValue: 0xfff08900,
          isRest: false,
          startMinute: 8 * 60,
          endMinute: 16 * 60,
        ),
        ShiftStep(
          name: '晚班',
          colorValue: 0xff5476ff,
          isRest: false,
          startMinute: 16 * 60,
          endMinute: 0,
          overnight: true,
        ),
        ShiftStep(
          name: '夜班',
          colorValue: 0xffa142f4,
          isRest: false,
          startMinute: 0,
          endMinute: 8 * 60,
        ),
        ShiftStep(name: '休息', colorValue: 0xff34a853, isRest: true),
      ],
    ),
    ShiftTemplate(
      id: 'builtin-two-on-two-off',
      name: '上二休二',
      isBuiltIn: true,
      steps: const <ShiftStep>[
        ShiftStep(
          name: '早班',
          colorValue: 0xfff08900,
          isRest: false,
          startMinute: 8 * 60,
          endMinute: 20 * 60,
        ),
        ShiftStep(
          name: '早班',
          colorValue: 0xfff08900,
          isRest: false,
          startMinute: 8 * 60,
          endMinute: 20 * 60,
        ),
        ShiftStep(name: '休息', colorValue: 0xff34a853, isRest: true),
        ShiftStep(name: '休息', colorValue: 0xff34a853, isRest: true),
      ],
    ),
  ];

  Future<List<ShiftTemplate>> loadTemplates() async {
    final prefs = await _prefs;
    final raw = prefs.getString(shiftTemplateStorageKey);
    if (raw == null) {
      final defaults = builtIns;
      await _write(defaults);
      return defaults;
    }
    try {
      final value = jsonDecode(raw);
      if (value is! List) throw const FormatException('模板列表必须是数组');
      return value.map(ShiftTemplate.fromJson).toList(growable: false);
    } catch (error) {
      throw FormatException('无法读取排班模板：$error');
    }
  }

  Future<void> saveTemplate(ShiftTemplate template) async {
    template.validate();
    final templates = await loadTemplates();
    final index = templates.indexWhere((item) => item.id == template.id);
    final updated = List<ShiftTemplate>.of(templates);
    if (index == -1) {
      updated.add(template.copyWith());
    } else {
      updated[index] = template.copyWith();
    }
    await _write(updated);
  }

  Future<void> deleteTemplate(String id) async {
    final templates = await loadTemplates();
    await _write(templates.where((item) => item.id != id).toList());
  }

  Future<void> _write(List<ShiftTemplate> templates) async {
    final prefs = await _prefs;
    final saved = await prefs.setString(
      shiftTemplateStorageKey,
      jsonEncode(templates.map((template) => template.toJson()).toList()),
    );
    if (!saved) throw StateError('保存排班模板失败（SharedPreferences 拒绝写入）');
  }

  /// Returns one entry for each working step and optionally an all-day rest
  /// entry, starting with cycle step 1 on [firstDate]. The date range is
  /// inclusive and limited to 366 calendar days.
  List<CalendarEntry> generateEntries({
    required ShiftTemplate template,
    required DateTime firstDate,
    required DateTime lastDate,
    required String calendarId,
    bool generateRestDays = true,
  }) {
    template.validate();
    final start = dateOnly(firstDate);
    final finish = dateOnly(lastDate);
    if (start.year < 1900 || finish.year > 2100) {
      throw ArgumentError('日期必须在 1900–2100 年范围内');
    }
    if (finish.isBefore(start)) throw ArgumentError('结束日期不能早于开始日期');
    final days = shiftCalendarDaysBetween(start, finish) + 1;
    if (days > 366) throw ArgumentError('日期范围最多 366 天');
    final entries = <CalendarEntry>[];
    for (var offset = 0; offset < days; offset++) {
      final date = DateTime(start.year, start.month, start.day + offset);
      final step = template.steps[offset % template.steps.length];
      if (step.isRest && !generateRestDays) continue;
      final id = 'shift:${template.id}:${dayKey(date)}';
      if (step.isRest) {
        entries.add(
          CalendarEntry(
            id: id,
            title: step.name,
            start: date,
            end: DateTime(date.year, date.month, date.day + 1),
            allDay: true,
            kind: EntryKind.event,
            colorValue: step.colorValue,
            calendarId: calendarId,
            notes: '由循环班次模板「${template.name}」生成。',
          ),
        );
      } else {
        final shiftStart = DateTime(
          date.year,
          date.month,
          date.day,
          step.startMinute ~/ 60,
          step.startMinute % 60,
        );
        var shiftEnd = DateTime(
          date.year,
          date.month,
          date.day,
          step.endMinute ~/ 60,
          step.endMinute % 60,
        );
        if (step.overnight || !shiftEnd.isAfter(shiftStart)) {
          shiftEnd = DateTime(
            date.year,
            date.month,
            date.day + 1,
            step.endMinute ~/ 60,
            step.endMinute % 60,
          );
        }
        entries.add(
          CalendarEntry(
            id: id,
            title: step.name,
            start: shiftStart,
            end: shiftEnd,
            allDay: false,
            kind: EntryKind.event,
            colorValue: step.colorValue,
            calendarId: calendarId,
            notes: '由循环班次模板「${template.name}」生成。',
          ),
        );
      }
    }
    return entries;
  }

  ShiftApplicationPreview preview({
    required AppStore store,
    required ShiftTemplate template,
    required DateTime firstDate,
    required DateTime lastDate,
    required String calendarId,
    bool generateRestDays = true,
  }) {
    final entries = generateEntries(
      template: template,
      firstDate: firstDate,
      lastDate: lastDate,
      calendarId: calendarId,
      generateRestDays: generateRestDays,
    );
    final totalDays = shiftCalendarDaysBetween(firstDate, lastDate) + 1;
    final working = <CalendarEntry>[];
    final restDays = <CalendarEntry>[];
    for (final entry in entries) {
      (entry.allDay ? restDays : working).add(entry);
    }
    return ShiftApplicationPreview(
      totalDays: totalDays,
      workDays: working.length,
      restDays: (generateRestDays
          ? totalDays - working.length
          : _countRest(template, totalDays)),
      entriesToGenerate: entries.length,
      conflictCount: _conflictingEntries(store, entries).length,
    );
  }

  Future<ShiftApplicationResult> apply({
    required AppStore store,
    required ShiftTemplate template,
    required DateTime firstDate,
    required DateTime lastDate,
    required String calendarId,
    bool generateRestDays = true,
    ShiftConflictPolicy conflictPolicy = ShiftConflictPolicy.keep,
  }) async {
    final entries = generateEntries(
      template: template,
      firstDate: firstDate,
      lastDate: lastDate,
      calendarId: calendarId,
      generateRestDays: generateRestDays,
    );
    final conflicts = _conflictingEntries(store, entries);
    final conflictIds = conflicts.map((entry) => entry.id).toSet();
    final batch = conflictPolicy == ShiftConflictPolicy.skip
        ? entries.where((entry) => !conflictIds.contains(entry.id)).toList()
        : entries;
    await store.saveEntries(batch);
    return ShiftApplicationResult(
      createdOrUpdated: batch.length,
      skippedConflicts: entries.length - batch.length,
    );
  }

  static int _countRest(ShiftTemplate template, int days) {
    var count = 0;
    for (var i = 0; i < days; i++) {
      if (template.steps[i % template.steps.length].isRest) count++;
    }
    return count;
  }

  List<CalendarEntry> _conflictingEntries(
    AppStore store,
    List<CalendarEntry> generated,
  ) {
    if (generated.isEmpty) return <CalendarEntry>[];
    final first = dateOnly(
      generated
          .map((entry) => entry.start)
          .reduce((a, b) => a.isBefore(b) ? a : b),
    );
    final last = generated
        .map((entry) => entry.end ?? entry.start)
        .reduce((a, b) => a.isAfter(b) ? a : b);
    final occurrences = store.occurrences(
      first,
      DateTime(last.year, last.month, last.day + 2),
      visibleOnly: false,
    );
    final conflicts = <CalendarEntry>{};
    for (final target in generated) {
      for (final occurrence in occurrences) {
        if (occurrence.entry.id == target.id) continue;
        final targetEnd =
            target.end ??
            (target.allDay
                ? target.start.add(const Duration(days: 1))
                : target.start);
        final existingEnd = occurrence.end;
        final targetDuration = targetEnd.difference(target.start);
        final existingDuration = existingEnd.difference(occurrence.start);
        final overlaps =
            targetDuration == Duration.zero && existingDuration == Duration.zero
            ? target.start.isAtSameMomentAs(occurrence.start)
            : targetDuration == Duration.zero
            ? !target.start.isBefore(occurrence.start) &&
                  target.start.isBefore(existingEnd)
            : existingDuration == Duration.zero
            ? !occurrence.start.isBefore(target.start) &&
                  occurrence.start.isBefore(targetEnd)
            : target.start.isBefore(existingEnd) &&
                  targetEnd.isAfter(occurrence.start);
        if (overlaps) conflicts.add(target);
      }
    }
    return conflicts.toList(growable: false);
  }
}
