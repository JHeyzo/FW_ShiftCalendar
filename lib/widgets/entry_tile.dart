import 'package:flutter/material.dart';

import '../data/app_store.dart';

/// One concrete occurrence, shared by calendar surfaces and the todo list.
class EntryTile extends StatefulWidget {
  const EntryTile({
    super.key,
    required this.occurrence,
    required this.store,
    required this.onTap,
  });
  final EntryOccurrence occurrence;
  final AppStore store;
  final VoidCallback onTap;
  @override
  State<EntryTile> createState() => _EntryTileState();
}

class _EntryTileState extends State<EntryTile> {
  bool _updating = false;

  @override
  Widget build(BuildContext context) {
    final occurrence = widget.occurrence;
    final entry = occurrence.entry;
    final scheme = Theme.of(context).colorScheme;
    final calendars = widget.store.calendars.where(
      (group) => group.id == entry.calendarId,
    );
    final calendar = calendars.isEmpty ? null : calendars.first;
    final accent = Color(entry.colorValue);
    return Material(
      color: scheme.surface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: widget.onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 4,
                constraints: const BoxConstraints(minHeight: 44),
                decoration: BoxDecoration(
                  color: accent,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              const SizedBox(width: 10),
              if (entry.kind == EntryKind.todo)
                SizedBox(
                  width: 36,
                  height: 40,
                  child: Checkbox.adaptive(
                    value: occurrence.done,
                    activeColor: accent,
                    visualDensity: VisualDensity.compact,
                    onChanged: _updating ? null : (_) => _toggleDone(),
                  ),
                ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.title,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        decoration: occurrence.done
                            ? TextDecoration.lineThrough
                            : null,
                        color: occurrence.done
                            ? scheme.onSurfaceVariant
                            : scheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Wrap(
                      spacing: 10,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        _Meta(
                          icon: Icons.calendar_today_outlined,
                          text: calendar?.name ?? '日历',
                        ),
                        _Meta(
                          icon: entry.allDay
                              ? Icons.wb_sunny_outlined
                              : Icons.schedule,
                          text: _when(occurrence),
                        ),
                        if (entry.repeat != RepeatRule.none)
                          _Meta(
                            icon: Icons.repeat,
                            text: _repeatLabel(entry.repeat),
                          ),
                        if (entry.reminderMinutes != null)
                          _Meta(
                            icon: Icons.notifications_none,
                            text: _reminderLabel(entry.reminderMinutes!),
                          ),
                        if (entry.starred)
                          Icon(Icons.star, size: 16, color: accent),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _toggleDone() async {
    if (_updating) return;
    setState(() => _updating = true);
    try {
      await widget.store.toggleDone(
        widget.occurrence.entry,
        occurrenceDate: widget.occurrence.start,
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('更新完成状态失败：$error')));
      }
    } finally {
      if (mounted) setState(() => _updating = false);
    }
  }

  String _when(EntryOccurrence item) {
    final start = item.start;
    final end = item.end;
    if (item.entry.allDay) {
      final lastDay = end.isAfter(start)
          ? end.subtract(const Duration(microseconds: 1))
          : start;
      return sameDay(start, lastDay)
          ? '${_dateLabel(start)} 全天'
          : '${_dateLabel(start)}–${_dateLabel(lastDay)} 全天';
    }
    if (end == start) return '${_dateLabel(start)} ${_timeLabel(start)}';
    return '${_dateLabel(start)} ${_timeLabel(start)}–'
        '${sameDay(start, end) ? '' : '${_dateLabel(end)} '}${_timeLabel(end)}';
  }

  static String _dateLabel(DateTime value) =>
      '${value.year}/${value.month}/${value.day}';
  static String _timeLabel(DateTime value) =>
      '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';
  static String _repeatLabel(RepeatRule rule) => switch (rule) {
    RepeatRule.daily => '每天',
    RepeatRule.weekly => '每周',
    RepeatRule.monthly => '每月',
    RepeatRule.yearly => '每年',
    RepeatRule.none => '',
  };
  static String _reminderLabel(int minutes) => minutes == 0
      ? '开始时提醒'
      : minutes == 1440
      ? '提前1天提醒'
      : '提前$minutes分钟';
}

class _Meta extends StatelessWidget {
  const _Meta({required this.icon, required this.text});
  final IconData icon;
  final String text;
  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.onSurfaceVariant;
    return Text.rich(
      TextSpan(
        children: [
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: Icon(icon, size: 13, color: color),
          ),
          TextSpan(text: ' $text'),
        ],
      ),
      maxLines: 3,
      overflow: TextOverflow.ellipsis,
      style: Theme.of(context).textTheme.labelSmall?.copyWith(color: color),
    );
  }
}
