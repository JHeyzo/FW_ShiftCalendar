import 'package:flutter/material.dart';

import '../data/app_store.dart';
import '../theme/fw_tokens.dart';

/// Opens the shared event/todo editor above the current route.
Future<void> openEntryEditor(
  BuildContext context,
  AppStore store, {
  CalendarEntry? entry,
  DateTime? occurrenceDate,
  EntryKind kind = EntryKind.event,
  DateTime? date,
}) async {
  await Navigator.of(context).push<void>(
    MaterialPageRoute<void>(
      builder: (_) => _EntryEditorPage(
        store: store,
        entry: entry,
        occurrenceDate: occurrenceDate,
        kind: entry?.kind ?? kind,
        initialDate: date,
      ),
    ),
  );
}

class _EntryEditorPage extends StatefulWidget {
  const _EntryEditorPage({
    required this.store,
    required this.kind,
    this.entry,
    this.occurrenceDate,
    this.initialDate,
  });

  final AppStore store;
  final CalendarEntry? entry;
  final DateTime? occurrenceDate;
  final EntryKind kind;
  final DateTime? initialDate;

  @override
  State<_EntryEditorPage> createState() => _EntryEditorPageState();
}

class _EntryEditorPageState extends State<_EntryEditorPage> {
  static const _palette = <int>[
    0xff0066ff,
    0xff34c759,
    0xffff9f0a,
    0xffff3b30,
    0xffaf52de,
    0xff00a7a7,
    0xff8e8e93,
    0xff795548,
  ];
  static const _reminderOptions = <int?>[null, 0, 5, 10, 15, 30, 60, 1440];
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _title;
  late final TextEditingController _notes;
  late DateTime _start;
  DateTime? _end;
  late bool _allDay;
  late bool _starred;
  late int _color;
  late String _calendarId;
  late RepeatRule _repeat;
  DateTime? _repeatUntil;
  int? _reminder;
  bool _saving = false;
  bool _changed = false;
  bool _discarding = false;
  String? _error;

  CalendarEntry? get _entry => widget.entry;
  bool get _editing => _entry != null;

  @override
  void initState() {
    super.initState();
    final old = _entry;
    final day = dateOnly(
      widget.initialDate ?? widget.occurrenceDate ?? widget.store.selectedDate,
    );
    _title = TextEditingController(text: old?.title ?? '');
    _notes = TextEditingController(text: old?.notes ?? '');
    final occurrence = widget.occurrenceDate;
    if (old != null && occurrence != null && old.repeat != RepeatRule.none) {
      // A recurring entry stores the series' first date, while the editor is
      // opened for one particular instance. Show that instance's date without
      // losing its time of day or its end-date span.
      final target = dateOnly(occurrence);
      final source = dateOnly(old.start);
      _start = DateTime(
        target.year,
        target.month,
        target.day,
        old.start.hour,
        old.start.minute,
        old.start.second,
        old.start.millisecond,
        old.start.microsecond,
      );
      final daySpan = old.end == null
          ? null
          : DateTime.utc(old.end!.year, old.end!.month, old.end!.day)
                .difference(DateTime.utc(source.year, source.month, source.day))
                .inDays;
      if (old.end != null && daySpan != null) {
        final endDay = DateTime(
          target.year,
          target.month,
          target.day + daySpan,
        );
        _end = DateTime(
          endDay.year,
          endDay.month,
          endDay.day,
          old.end!.hour,
          old.end!.minute,
          old.end!.second,
          old.end!.millisecond,
          old.end!.microsecond,
        );
      } else {
        _end = null;
      }
    } else {
      _start = old?.start ?? day;
      _end = old?.end;
    }
    _allDay = old?.allDay ?? true;
    _starred = old?.starred ?? false;
    _color = old?.colorValue ?? _palette.first;
    _calendarId =
        old?.calendarId ??
        (widget.store.calendars.isEmpty
            ? 'personal'
            : widget.store.calendars.first.id);
    _repeat = old?.repeat ?? RepeatRule.none;
    _repeatUntil = old?.repeatUntil;
    _reminder = old?.reminderMinutes;
    _title.addListener(_markChanged);
    _notes.addListener(_markChanged);
  }

  @override
  void dispose() {
    _title.dispose();
    _notes.dispose();
    super.dispose();
  }

  void _markChanged() {
    _changed = true;
    if (_error != null && mounted) setState(() => _error = null);
  }

  Future<bool> _confirmDiscard() async {
    if (!_changed || _saving) return true;
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('放弃未保存的更改？'),
            content: const Text('当前修改尚未保存。'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('继续编辑'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('放弃'),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _back() async {
    if (await _confirmDiscard() && mounted) {
      setState(() => _discarding = true);
      Navigator.of(context).pop();
    }
  }

  Future<EditScope?> _chooseScope(String action) async {
    if (!_editing || _entry!.repeat == RepeatRule.none) return EditScope.all;
    return showDialog<EditScope>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('$action重复事项'),
        content: const Text('请选择应用范围'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, EditScope.single),
            child: const Text('仅此项'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, EditScope.future),
            child: const Text('此后'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, EditScope.all),
            child: const Text('全部'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
        ],
      ),
    );
  }

  Future<void> _save() async {
    if (_saving || !_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    final scope = await _chooseScope('修改');
    if (scope == null || !mounted) {
      if (mounted) setState(() => _saving = false);
      return;
    }
    try {
      final title = _title.text.trim();
      if (_editing) {
        final replacement = _entry!.copyWith(
          title: title,
          start: _start,
          end: _end,
          clearEnd: _end == null,
          kind: widget.kind,
          allDay: _allDay,
          starred: _starred,
          colorValue: _color,
          calendarId: _calendarId,
          notes: _notes.text.trim(),
          repeat: _repeat,
          repeatUntil: _repeatUntil,
          clearRepeatUntil: _repeatUntil == null,
          reminderMinutes: _reminder,
          clearReminder: _reminder == null,
        );
        await widget.store.updateEntry(
          _entry!,
          replacement,
          occurrenceDate: widget.occurrenceDate,
          scope: scope,
        );
      } else {
        await widget.store.saveEntry(
          CalendarEntry(
            id: '${DateTime.now().microsecondsSinceEpoch}',
            title: title,
            start: _start,
            end: _end,
            kind: widget.kind,
            allDay: _allDay,
            starred: _starred,
            colorValue: _color,
            calendarId: _calendarId,
            notes: _notes.text.trim(),
            repeat: _repeat,
            repeatUntil: _repeatUntil,
            reminderMinutes: _reminder,
          ),
        );
      }
      if (mounted) {
        _changed = false;
        _discarding = true;
        Navigator.of(context).pop();
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = '保存失败：$error';
        });
      }
    }
  }

  Future<void> _delete() async {
    if (_saving || _entry == null) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    final scope = await _chooseScope('删除');
    if (scope == null || !mounted) {
      if (mounted) setState(() => _saving = false);
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除事项？'),
        content: Text(
          scope == EditScope.single
              ? '仅删除这一次。'
              : scope == EditScope.future
              ? '删除这次及之后的重复事项。'
              : '删除整个事项及其重复安排。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) {
      if (mounted) setState(() => _saving = false);
      return;
    }
    try {
      await widget.store.deleteEntry(
        _entry!,
        occurrenceDate: widget.occurrenceDate,
        scope: scope,
      );
      if (mounted) {
        _changed = false;
        _discarding = true;
        Navigator.of(context).pop();
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = '删除失败：$error';
        });
      }
    }
  }

  Future<void> _pickDate({required bool isStart}) async {
    final initial = isStart ? _start : (_end ?? _start);
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(1900),
      lastDate: DateTime(2100, 12, 31),
    );
    if (picked == null || !mounted) return;
    setState(() {
      if (isStart) {
        final oldStart = _start;
        final oldEnd = _end;
        final calendarDaySpan = oldEnd == null
            ? null
            : DateTime.utc(oldEnd.year, oldEnd.month, oldEnd.day)
                  .difference(
                    DateTime.utc(oldStart.year, oldStart.month, oldStart.day),
                  )
                  .inDays;
        _start = DateTime(
          picked.year,
          picked.month,
          picked.day,
          _start.hour,
          _start.minute,
        );
        if (oldEnd != null && calendarDaySpan != null) {
          final endDay = DateTime(
            _start.year,
            _start.month,
            _start.day + calendarDaySpan,
          );
          _end = DateTime(
            endDay.year,
            endDay.month,
            endDay.day,
            oldEnd.hour,
            oldEnd.minute,
            oldEnd.second,
            oldEnd.millisecond,
            oldEnd.microsecond,
          );
        }
      } else {
        final time = _end ?? _start;
        _end = DateTime(
          picked.year,
          picked.month,
          picked.day,
          time.hour,
          time.minute,
        );
      }
      _changed = true;
    });
  }

  Future<void> _pickTime({required bool isStart}) async {
    final value = isStart ? _start : (_end ?? _start);
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(value),
    );
    if (picked == null || !mounted) return;
    setState(() {
      final d = isStart ? _start : (_end ?? _start);
      final result = DateTime(
        d.year,
        d.month,
        d.day,
        picked.hour,
        picked.minute,
      );
      if (isStart) {
        final oldStart = _start;
        final oldEnd = _end;
        _start = result;
        if (oldEnd != null) {
          _end = result.add(oldEnd.difference(oldStart));
        }
      } else {
        _end = result;
      }
      _changed = true;
    });
  }

  Future<void> _pickRepeatUntil() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _repeatUntil ?? _start,
      firstDate: dateOnly(_start),
      lastDate: DateTime(2100, 12, 31),
    );
    if (picked != null && mounted) {
      setState(() {
        _repeatUntil = dateOnly(picked);
        _changed = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return PopScope<void>(
      canPop: (!_changed && !_saving) || _discarding,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _back();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(_editing ? '编辑$_kindName' : '新建$_kindName'),
          leading: IconButton(
            onPressed: _saving ? null : _back,
            icon: const Icon(Icons.chevron_left),
          ),
          actions: [
            if (_editing)
              IconButton(
                tooltip: '删除',
                onPressed: _saving ? null : _delete,
                icon: const Icon(Icons.delete_outline),
              ),
          ],
        ),
        bottomNavigationBar: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: SizedBox(
              height: 52,
              child: FilledButton(
                onPressed: _saving ? null : _save,
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xff0066ff),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                ),
                child: _saving
                    ? const SizedBox.square(
                        dimension: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text(
                        '保存',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
              ),
            ),
          ),
        ),
        body: SafeArea(
          child: Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
              children: [
                _card(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextFormField(
                        controller: _title,
                        autofocus: true,
                        maxLength: 300,
                        maxLines: null,
                        style: const TextStyle(
                          fontSize: 23,
                          fontWeight: FontWeight.w600,
                        ),
                        decoration: const InputDecoration(
                          hintText: '标题（必填）',
                          border: InputBorder.none,
                          counterText: '',
                        ),
                        validator: (value) =>
                            value == null || value.trim().isEmpty
                            ? '请输入标题'
                            : null,
                      ),
                      TextFormField(
                        controller: _notes,
                        maxLines: 3,
                        minLines: 1,
                        decoration: const InputDecoration(
                          hintText: '备注',
                          border: InputBorder.none,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                _card(
                  child: Column(
                    children: [
                      SwitchListTile.adaptive(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('全天'),
                        value: _allDay,
                        onChanged: (value) => setState(() {
                          _allDay = value;
                          _changed = true;
                        }),
                      ),
                      _dateRow(
                        '开始',
                        _start,
                        () => _pickDate(isStart: true),
                        timeTap: _allDay
                            ? null
                            : () => _pickTime(isStart: true),
                      ),
                      if (_end != null)
                        _dateRow(
                          '结束',
                          _end!,
                          () => _pickDate(isStart: false),
                          timeTap: _allDay
                              ? null
                              : () => _pickTime(isStart: false),
                        ),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          onPressed: () => setState(() {
                            _end = _end == null ? _start : null;
                            _changed = true;
                          }),
                          icon: Icon(
                            _end == null
                                ? Icons.add
                                : Icons.remove_circle_outline,
                          ),
                          label: Text(
                            _end == null
                                ? (widget.kind == EntryKind.todo
                                      ? '添加截止时间（可选）'
                                      : '添加结束时间')
                                : '移除结束时间',
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                _card(
                  child: Column(
                    children: [
                      DropdownButtonFormField<String>(
                        isExpanded: true,
                        initialValue:
                            widget.store.calendars.any(
                              (c) => c.id == _calendarId,
                            )
                            ? _calendarId
                            : (widget.store.calendars.isEmpty
                                  ? null
                                  : widget.store.calendars.first.id),
                        decoration: const InputDecoration(
                          labelText: '日历',
                          border: InputBorder.none,
                        ),
                        items: [
                          for (final calendar in widget.store.calendars)
                            DropdownMenuItem(
                              value: calendar.id,
                              child: Text(
                                calendar.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                        ],
                        onChanged: widget.store.calendars.isEmpty
                            ? null
                            : (value) => setState(() {
                                if (value != null) _calendarId = value;
                                _changed = true;
                              }),
                      ),
                      const SizedBox(height: 10),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Wrap(
                          spacing: 10,
                          runSpacing: 8,
                          children: [
                            for (final value in _palette) _colorDot(value),
                          ],
                        ),
                      ),
                      SwitchListTile.adaptive(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('星标'),
                        secondary: Icon(
                          _starred ? Icons.star : Icons.star_border,
                          color: _starred ? Color(_color) : null,
                        ),
                        value: _starred,
                        onChanged: (value) => setState(() {
                          _starred = value;
                          _changed = true;
                        }),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                _card(
                  child: Column(
                    children: [
                      DropdownButtonFormField<RepeatRule>(
                        initialValue: _repeat,
                        decoration: const InputDecoration(
                          labelText: '重复',
                          border: InputBorder.none,
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: RepeatRule.none,
                            child: Text('不重复'),
                          ),
                          DropdownMenuItem(
                            value: RepeatRule.daily,
                            child: Text('每天'),
                          ),
                          DropdownMenuItem(
                            value: RepeatRule.weekly,
                            child: Text('每周'),
                          ),
                          DropdownMenuItem(
                            value: RepeatRule.monthly,
                            child: Text('每月'),
                          ),
                          DropdownMenuItem(
                            value: RepeatRule.yearly,
                            child: Text('每年'),
                          ),
                        ],
                        onChanged: (value) => setState(() {
                          _repeat = value ?? RepeatRule.none;
                          if (_repeat == RepeatRule.none) _repeatUntil = null;
                          _changed = true;
                        }),
                      ),
                      if (_repeat != RepeatRule.none)
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('重复截止'),
                          subtitle: Text(
                            _repeatUntil == null
                                ? '永不'
                                : _dateLabel(_repeatUntil!),
                          ),
                          trailing: IconButton(
                            tooltip: _repeatUntil == null ? '设置截止日期' : '清除截止日期',
                            onPressed: _repeatUntil == null
                                ? _pickRepeatUntil
                                : () => setState(() {
                                    _repeatUntil = null;
                                    _changed = true;
                                  }),
                            icon: Icon(
                              _repeatUntil == null ? Icons.event : Icons.close,
                            ),
                          ),
                          onTap: _pickRepeatUntil,
                        ),
                      DropdownButtonFormField<int?>(
                        initialValue: _reminder,
                        decoration: const InputDecoration(
                          labelText: '提前提醒',
                          helperText: '需在设置开启通知，系统可能延迟',
                          border: InputBorder.none,
                        ),
                        items: [
                          for (final value in _reminderOptions)
                            DropdownMenuItem<int?>(
                              value: value,
                              child: Text(
                                value == null
                                    ? '无'
                                    : value == 0
                                    ? '事件开始时'
                                    : value == 1440
                                    ? '提前1天'
                                    : '提前$value分钟',
                              ),
                            ),
                        ],
                        onChanged: (value) => setState(() {
                          _reminder = value;
                          _changed = true;
                        }),
                      ),
                    ],
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!, style: TextStyle(color: colors.error)),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  String get _kindName => widget.kind == EntryKind.todo ? '待办' : '日程';

  Widget _card({required Widget child}) => Material(
    color: Theme.of(context).colorScheme.surface,
    borderRadius: BorderRadius.circular(FwTokens.radiusCreateCard),
    elevation: 1,
    clipBehavior: Clip.antiAlias,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: child,
    ),
  );
  Widget _dateRow(
    String label,
    DateTime date,
    VoidCallback dateTap, {
    VoidCallback? timeTap,
  }) => ListTile(
    contentPadding: EdgeInsets.zero,
    title: Text(label),
    subtitle: Text(
      '${_dateLabel(date)}${timeTap == null ? '' : '  ${_timeLabel(date)}'}',
    ),
    trailing: const Icon(Icons.chevron_right),
    onTap: dateTap,
    onLongPress: timeTap,
    leading: timeTap == null
        ? null
        : IconButton(icon: const Icon(Icons.schedule), onPressed: timeTap),
  );

  Widget _colorDot(int value) => Semantics(
    button: true,
    label: '选择颜色',
    child: InkWell(
      customBorder: const CircleBorder(),
      onTap: () => setState(() {
        _color = value;
        _changed = true;
      }),
      child: Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          color: Color(value),
          shape: BoxShape.circle,
          border: Border.all(
            color: _color == value
                ? Theme.of(context).colorScheme.onSurface
                : Colors.transparent,
            width: 2,
          ),
        ),
        child: _color == value
            ? const Icon(Icons.check, size: 18, color: Colors.white)
            : null,
      ),
    ),
  );
}

String _dateLabel(DateTime value) =>
    '${value.year}年${value.month}月${value.day}日';
String _timeLabel(DateTime value) =>
    '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';
