import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/app_store.dart';
import '../services/system_calendar_service.dart';

class SystemCalendarPage extends StatefulWidget {
  const SystemCalendarPage({super.key, required this.store});

  final AppStore store;

  @override
  State<SystemCalendarPage> createState() => _SystemCalendarPageState();
}

class _SystemCalendarPageState extends State<SystemCalendarPage> {
  final SystemCalendarService _service = SystemCalendarService();
  late DateTime _from;
  late DateTime _to;
  List<SystemCalendarInfo> _systemCalendars = const [];
  int? _systemCalendarId;
  String? _localCalendarId;
  bool _loadingCalendars = false;
  bool _busy = false;
  String? _status;
  String? _error;

  DateTime get _fromDay => DateTime(_from.year, _from.month, _from.day);
  DateTime get _toDay => DateTime(_to.year, _to.month, _to.day);
  DateTime get _today => DateUtils.dateOnly(DateTime.now());
  DateTime get _maxDay => DateTime(_today.year, _today.month, _today.day + 180);

  @override
  void initState() {
    super.initState();
    final today = DateTime.now();
    _from = DateTime(today.year, today.month, today.day);
    _to = DateTime(_from.year, _from.month, _from.day + 180);
    _localCalendarId = widget.store.calendars.firstOrNull?.id;
    _loadCalendars();
  }

  Future<void> _loadCalendars() async {
    if (!_service.isSupported) return;
    setState(() {
      _loadingCalendars = true;
      _error = null;
    });
    try {
      final calendars = await _service.listCalendars();
      if (!mounted) return;
      setState(() {
        _systemCalendars = calendars;
        if (!calendars.any((item) => item.id == _systemCalendarId)) {
          _systemCalendarId = calendars.firstOrNull?.id;
        }
        _loadingCalendars = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loadingCalendars = false;
        _error = _friendlyError(error);
      });
    }
  }

  Future<void> _pickDate({required bool start}) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: start ? _fromDay : _toDay,
      firstDate: _today,
      lastDate: _maxDay,
      helpText: start ? '选择范围开始日期' : '选择范围结束日期',
    );
    if (picked == null || !mounted) return;
    final normalized = DateTime(picked.year, picked.month, picked.day);
    setState(() {
      if (start) {
        _from = normalized;
        if (_toDay.isBefore(_fromDay)) _to = _from;
      } else {
        _to = normalized;
        if (_toDay.isBefore(_fromDay)) _from = _to;
      }
    });
  }

  Future<void> _createImportCalendar() async {
    const id = 'system_imports';
    const name = '系统日历导入';
    try {
      if (!widget.store.calendars.any((calendar) => calendar.id == id)) {
        await widget.store.saveCalendar(
          const CalendarGroup(id: id, name: name, colorValue: 0xff4285f4),
        );
      }
      if (!mounted) return;
      setState(() {
        _localCalendarId = id;
        _status = '已创建专属本地日历“$name”。';
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = _friendlyError(error));
    }
  }

  Future<void> _import() async {
    final systemId = _systemCalendarId;
    final localId = _localCalendarId;
    if (systemId == null || localId == null) {
      _showError('请先选择系统日历和本地日历。');
      return;
    }
    await _run(() async {
      final result = await _service.readInstances(
        calendarId: systemId,
        from: _fromDay,
        to: DateTime(_toDay.year, _toDay.month, _toDay.day + 1),
      );
      final source = _systemCalendars.firstWhere((item) => item.id == systemId);
      final confirmed = await _confirm(
        title: '确认导入',
        body:
            '从“${source.name}”导入 ${_formatDate(_fromDay)} 至 ${_formatDate(_toDay)} 的 ${result.instances.length} 个日历实例，保存到“${_localCalendarName(localId)}”。每个重复日程实例会成为独立本地日程。\n\n再次导入会按稳定实例 ID 更新并覆盖同一实例的本地修改；不会重复创建，也不会删除任何本地旧项。${result.truncated ? '\n\n结果已达到500项上限，列表可能被截断。' : ''}',
      );
      if (!confirmed) return;
      final entries = result.instances
          .map((item) {
            final start = item.allDay
                ? _allDayLocal(item.beginMillis)
                : DateTime.fromMillisecondsSinceEpoch(item.beginMillis);
            final end = item.allDay
                ? _allDayLocal(item.endMillis)
                : DateTime.fromMillisecondsSinceEpoch(item.endMillis);
            return CalendarEntry(
              id: 'system:$systemId:${item.eventId}:${item.beginMillis}',
              title: item.title.trim().isEmpty ? '(无标题)' : item.title,
              start: start,
              end: end,
              kind: EntryKind.event,
              allDay: item.allDay,
              calendarId: localId,
              colorValue: source.color,
              notes: item.notes,
              repeat: RepeatRule.none,
            );
          })
          .toList(growable: false);
      await widget.store.saveEntries(entries);
      if (!mounted) return;
      setState(
        () => _status =
            '导入完成：${entries.length} 项${result.truncated ? '（已达500项上限，结果可能截断）' : ''}。',
      );
    });
  }

  Future<void> _export() async {
    final systemId = _systemCalendarId;
    final localId = _localCalendarId;
    if (systemId == null || localId == null) {
      _showError('请先选择系统日历和本地日历。');
      return;
    }
    final calendar = _systemCalendars.firstWhere((item) => item.id == systemId);
    if (!calendar.canWrite) {
      _showError('所选系统日历为只读，请选择可写日历。');
      return;
    }
    final occurrences = widget.store.occurrences(
      _fromDay,
      DateTime(_toDay.year, _toDay.month, _toDay.day + 1),
      visibleOnly: false,
    );
    final events = <SystemCalendarExportItem>[];
    for (final occurrence in occurrences) {
      final entry = occurrence.entry;
      if (entry.calendarId != localId ||
          entry.kind != EntryKind.event ||
          entry.id.startsWith('system:')) {
        continue;
      }
      final start = occurrence.start;
      final end = occurrence.end.isAfter(start)
          ? occurrence.end
          : entry.allDay
          ? DateTime(start.year, start.month, start.day + 1)
          : start.add(const Duration(minutes: 1));
      final startMillis = entry.allDay
          ? DateTime.utc(
              start.year,
              start.month,
              start.day,
            ).millisecondsSinceEpoch
          : start.millisecondsSinceEpoch;
      final endMillis = entry.allDay
          ? DateTime.utc(end.year, end.month, end.day).millisecondsSinceEpoch
          : end.millisecondsSinceEpoch;
      events.add(
        SystemCalendarExportItem(
          occurrenceKey: entry.repeat == RepeatRule.none
              ? entry.id
              : '${entry.id}@${dayKey(start)}',
          title: entry.title,
          startMillis: startMillis,
          endMillis: endMillis,
          allDay: entry.allDay,
          // Native Android uses its IANA device timezone when this is empty.
          timeZone: entry.allDay ? 'UTC' : '',
          notes: entry.notes,
        ),
      );
    }
    final visibleEvents = events.take(500).toList(growable: false);
    final truncated = events.length > 500;
    await _run(() async {
      final confirmed = await _confirm(
        title: '确认导出',
        body:
            '将从本地日历“${_localCalendarName(localId)}”导出 ${_formatDate(_fromDay)} 至 ${_formatDate(_toDay)} 的 ${visibleEvents.length} 个日程实例至系统日历“${calendar.name}”。待办和 system: 开头的导入项不会导出；重复日程按范围展开为独立实例（不创建重复规则）。备注会保留，系统日历备注中会追加可见的“风味日历导出”来源标记。再次导出更新相同实例，不会自动删除系统日历中的旧项。${truncated ? '\n\n本地结果超过500项，仅导出前500项。' : ''}',
      );
      if (!confirmed) return;
      final count = await _service.upsertEvents(
        calendarId: systemId,
        events: visibleEvents,
      );
      if (!mounted) return;
      setState(
        () => _status =
            '导出完成：$count 项${truncated ? '（受500项上限截断）' : ''}。已存在的本应用导出项已更新。',
      );
    });
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _status = null;
      _error = null;
    });
    try {
      await action();
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = _friendlyError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool> _confirm({required String title, required String body}) async {
    if (!mounted) return false;
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(title),
            content: SingleChildScrollView(child: Text(body)),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('继续'),
              ),
            ],
          ),
        ) ??
        false;
  }

  void _showError(String message) {
    setState(() => _error = message);
  }

  DateTime _allDayLocal(int millis) {
    final utc = DateTime.fromMillisecondsSinceEpoch(millis, isUtc: true);
    return DateTime(utc.year, utc.month, utc.day);
  }

  String _localCalendarName(String id) =>
      widget.store.calendars
          .where((calendar) => calendar.id == id)
          .map((calendar) => calendar.name)
          .firstOrNull ??
      id;

  String _formatDate(DateTime date) =>
      '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

  String _friendlyError(Object error) {
    if (error is PlatformException) {
      return error.message ?? '系统日历操作失败（${error.code}）';
    }
    if (error is UnsupportedError) {
      return error.message ?? '此平台不支持系统日历';
    }
    return error.toString().replaceFirst('Exception: ', '');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (!_service.isSupported) {
      return Scaffold(
        appBar: AppBar(title: const Text('系统日历同步')),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              '系统日历导入/导出目前仅支持 Android。此功能为手动操作，不会后台实时双向同步。',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }
    final localCalendars = widget.store.calendars;
    final selectedSystem = _systemCalendars
        .where((item) => item.id == _systemCalendarId)
        .firstOrNull;
    return Scaffold(
      appBar: AppBar(
        title: const Text('系统日历同步'),
        actions: [
          IconButton(
            tooltip: '重新读取系统日历',
            onPressed: _busy || _loadingCalendars ? null : _loadCalendars,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('手动导入 / 导出', style: theme.textTheme.titleLarge),
          const SizedBox(height: 8),
          const Text('仅 Android 支持。不是后台实时双向同步；不会自动同步或删除日程。每次操作最多处理500个实例。'),
          const SizedBox(height: 16),
          DropdownButtonFormField<int>(
            initialValue: _systemCalendarId,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: '系统日历',
              border: OutlineInputBorder(),
            ),
            items: _systemCalendars
                .map(
                  (item) => DropdownMenuItem(
                    value: item.id,
                    child: Text(
                      '${item.name} · ${item.accountName}${item.canWrite ? '' : '（只读）'}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                )
                .toList(),
            onChanged: _busy
                ? null
                : (value) => setState(() => _systemCalendarId = value),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            isExpanded: true,
            initialValue:
                localCalendars.any((item) => item.id == _localCalendarId)
                ? _localCalendarId
                : null,
            decoration: const InputDecoration(
              labelText: '本地日历',
              border: OutlineInputBorder(),
            ),
            items: localCalendars
                .map(
                  (item) => DropdownMenuItem(
                    value: item.id,
                    child: Text(
                      item.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                )
                .toList(),
            onChanged: _busy
                ? null
                : (value) => setState(() => _localCalendarId = value),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: _busy ? null : _createImportCalendar,
              icon: const Icon(Icons.add),
              label: const Text('新建专属“系统日历导入”本地日历'),
            ),
          ),
          const SizedBox(height: 8),
          Text('日期范围（默认今天至180天后）', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _busy ? null : () => _pickDate(start: true),
                  icon: const Icon(Icons.calendar_today),
                  label: Text('从 ${_formatDate(_fromDay)}'),
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 8),
                child: Text('至'),
              ),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _busy ? null : () => _pickDate(start: false),
                  icon: const Icon(Icons.event),
                  label: Text(_formatDate(_toDay)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_loadingCalendars) const LinearProgressIndicator(),
          if (_systemCalendars.isEmpty && !_loadingCalendars)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text('未找到可读取的系统日历，或尚未授予日历权限。'),
            ),
          if (selectedSystem != null && !selectedSystem.canWrite)
            const Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: Text('当前系统日历只读：可导入，不可导出。'),
            ),
          if (_busy) const LinearProgressIndicator(),
          if (_status != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                _status!,
                style: TextStyle(color: theme.colorScheme.primary),
              ),
            ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                _error!,
                style: TextStyle(color: theme.colorScheme.error),
              ),
            ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _busy || _loadingCalendars || _systemCalendarId == null
                ? null
                : _import,
            icon: const Icon(Icons.download),
            label: const Text('从系统日历导入'),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed:
                _busy ||
                    _loadingCalendars ||
                    _systemCalendarId == null ||
                    selectedSystem?.canWrite != true
                ? null
                : _export,
            icon: const Icon(Icons.upload),
            label: const Text('导出到系统日历'),
          ),
          const SizedBox(height: 16),
          Text(
            '导入规则：重复事件展开为单独本地日程。再次导入按实例 ID 更新，覆盖该实例的本地修改，但不删除本地旧项。\n导出规则：只导出本地日程，不导出待办或已导入的 system: 项；重复事件展开为单独系统日程，更新本应用已导出项，但不会自动删除系统日历中的旧项。',
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}
