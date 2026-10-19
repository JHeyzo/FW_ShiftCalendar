import 'package:flutter/material.dart';

import '../data/app_store.dart';
import '../widgets/entry_tile.dart';
import 'create_todo_page.dart';

/// Todo list. Repeating entries are queried only for a bounded window around
/// the selected day (30 days back and 90 days forward).
class TodoPage extends StatefulWidget {
  const TodoPage({super.key, required this.store, required this.onEdit});

  final AppStore store;
  final void Function(CalendarEntry entry, DateTime occurrenceDate) onEdit;

  @override
  State<TodoPage> createState() => _TodoPageState();
}

enum _TodoFilter { all, active, done, overdue, today, nextSevenDays, starred }

enum _TodoSort { date, created, starred }

class _TodoPageState extends State<TodoPage> {
  _TodoFilter _filter = _TodoFilter.all;
  _TodoSort _sort = _TodoSort.date;

  static const _filterLabels = <_TodoFilter, String>{
    _TodoFilter.all: '全部',
    _TodoFilter.active: '进行中',
    _TodoFilter.done: '已完成',
    _TodoFilter.overdue: '逾期',
    _TodoFilter.today: '今天',
    _TodoFilter.nextSevenDays: '7天',
    _TodoFilter.starred: '星标',
  };

  List<EntryOccurrence> _items() {
    final selected = dateOnly(widget.store.selectedDate);
    final from = DateTime(selected.year, selected.month, selected.day - 30);
    final through = DateTime(selected.year, selected.month, selected.day + 90);
    final occurrences = widget.store
        .occurrences(
          from,
          DateTime(through.year, through.month, through.day + 1),
        )
        .where((item) => item.entry.kind == EntryKind.todo)
        .toList();
    // Keep one-off tasks visible even when their due date is outside the
    // recurring expansion window; only recurring instances are windowed.
    final visibleCalendars = widget.store.calendars
        .where((calendar) => calendar.visible)
        .map((calendar) => calendar.id)
        .toSet();
    final seenOneOffIds = occurrences
        .where((item) => item.entry.repeat == RepeatRule.none)
        .map((item) => item.entry.id)
        .toSet();
    for (final entry in widget.store.entries) {
      if (entry.kind == EntryKind.todo &&
          entry.repeat == RepeatRule.none &&
          !seenOneOffIds.contains(entry.id) &&
          visibleCalendars.contains(entry.calendarId)) {
        occurrences.add(
          EntryOccurrence(
            entry: entry,
            start: entry.start,
            end: entry.end ?? entry.start,
            done: entry.done,
          ),
        );
      }
    }
    final nextWeek = DateTime(
      widget.store.today.year,
      widget.store.today.month,
      widget.store.today.day + 7,
    );
    final today = dateOnly(widget.store.today);

    final filtered = occurrences.where((item) {
      final effectiveDue = item.entry.allDay
          ? (item.entry.end == null || !item.end.isAfter(item.start)
                ? item.start
                : item.end.subtract(const Duration(microseconds: 1)))
          : item.end;
      final due = dateOnly(effectiveDue);
      switch (_filter) {
        case _TodoFilter.all:
          return true;
        case _TodoFilter.active:
          return !item.done;
        case _TodoFilter.done:
          return item.done;
        case _TodoFilter.overdue:
          final overdue = item.entry.allDay
              ? due.isBefore(today)
              : item.end.isBefore(DateTime.now());
          return !item.done && overdue;
        case _TodoFilter.today:
          return sameDay(due, today);
        case _TodoFilter.nextSevenDays:
          return !due.isBefore(today) && due.isBefore(nextWeek);
        case _TodoFilter.starred:
          return item.entry.starred;
      }
    }).toList();

    switch (_sort) {
      case _TodoSort.date:
        filtered.sort((a, b) => a.start.compareTo(b.start));
      case _TodoSort.created:
        filtered.sort((a, b) => b.entry.createdAt.compareTo(a.entry.createdAt));
      case _TodoSort.starred:
        filtered.sort((a, b) {
          final priority =
              (b.entry.starred ? 1 : 0) - (a.entry.starred ? 1 : 0);
          return priority != 0 ? priority : a.start.compareTo(b.start);
        });
    }
    return filtered;
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.store,
    builder: (context, _) {
      final items = _items();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _filterChips(),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 7),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '重复待办仅显示所选日前30天至后90天',
                    maxLines: 2,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                DropdownButton<_TodoSort>(
                  value: _sort,
                  underline: const SizedBox.shrink(),
                  isDense: true,
                  onChanged: (value) {
                    if (value != null) setState(() => _sort = value);
                  },
                  items: const [
                    DropdownMenuItem(value: _TodoSort.date, child: Text('按日期')),
                    DropdownMenuItem(
                      value: _TodoSort.created,
                      child: Text('按创建'),
                    ),
                    DropdownMenuItem(
                      value: _TodoSort.starred,
                      child: Text('按星标'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Expanded(child: items.isEmpty ? _emptyState() : _list(items)),
        ],
      );
    },
  );

  Widget _filterChips() => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
    child: Row(
      children: [
        for (final filter in _TodoFilter.values)
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: Text(_filterLabels[filter]!),
              selected: _filter == filter,
              onSelected: (_) => setState(() => _filter = filter),
              selectedColor: Theme.of(context).colorScheme.primaryContainer,
              backgroundColor: Theme.of(context).colorScheme.surface,
              showCheckmark: false,
            ),
          ),
      ],
    ),
  );

  Widget _list(List<EntryOccurrence> items) => ListView.builder(
    padding: const EdgeInsets.fromLTRB(12, 4, 12, 120),
    itemCount: items.length,
    itemBuilder: (context, index) {
      final occurrence = items[index];
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: GestureDetector(
          onLongPress: () => _showActions(occurrence),
          child: EntryTile(
            occurrence: occurrence,
            store: widget.store,
            onTap: () => widget.onEdit(occurrence.entry, occurrence.start),
          ),
        ),
      );
    },
  );

  Future<void> _showActions(EntryOccurrence occurrence) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('编辑'),
              onTap: () => Navigator.pop(context, 'edit'),
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: const Text('删除'),
              onTap: () => Navigator.pop(context, 'delete'),
            ),
          ],
        ),
      ),
    );
    if (!mounted) return;
    if (action == 'edit') {
      widget.onEdit(occurrence.entry, occurrence.start);
    } else if (action == 'delete') {
      await _deleteOccurrence(occurrence);
    }
  }

  Future<void> _deleteOccurrence(EntryOccurrence occurrence) async {
    final repeated = occurrence.entry.repeat != RepeatRule.none;
    EditScope? scope = EditScope.all;
    if (repeated) {
      scope = await showDialog<EditScope>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('删除重复待办'),
          content: const Text('请选择删除范围。'),
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
      if (scope == null) return;
    }
    try {
      await widget.store.deleteEntry(
        occurrence.entry,
        occurrenceDate: occurrence.start,
        scope: scope,
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('删除失败：$error')));
      }
    }
  }

  Widget _emptyState() => Center(
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 40),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.inbox_outlined,
            size: 68,
            color: Theme.of(context).colorScheme.outline,
          ),
          const SizedBox(height: 14),
          Text(
            '此筛选下暂无待办',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: () => openEntryEditor(
              context,
              widget.store,
              kind: EntryKind.todo,
              date: widget.store.selectedDate,
            ),
            icon: const Icon(Icons.add),
            label: const Text('新建待办'),
          ),
        ],
      ),
    ),
  );
}
