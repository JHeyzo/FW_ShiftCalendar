import 'package:flutter/material.dart';

import '../data/app_store.dart';
import 'lunar.dart';

DateTime dateWithClampedDay(int year, int month, int day) {
  final lastDay = DateTime(year, month + 1, 0).day;
  return DateTime(year, month, day.clamp(1, lastDay));
}

/// Responsive twelve-month overview. Selecting a month returns a date with
/// the current selected day preserved (and clamped to the month's last day).
class YearPage extends StatelessWidget {
  const YearPage({
    super.key,
    required this.store,
    required this.onPickMonth,
    required this.onChangeYear,
    required this.onToday,
  });

  final AppStore store;
  final ValueChanged<DateTime> onPickMonth;
  final ValueChanged<int> onChangeYear;
  final VoidCallback onToday;

  Color _monthColor(BuildContext context, int year, int month) {
    final scheme = Theme.of(context).colorScheme;
    if (store.selectedDate.year == year && store.selectedDate.month == month) {
      return scheme.primary;
    }
    return Theme.of(context).textTheme.bodyLarge?.color ?? scheme.onSurface;
  }

  @override
  Widget build(BuildContext context) {
    final year = store.selectedDate.year;
    final lunarYear = lunarOf(DateTime(year, 1, 1));
    final scheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 4),
          child: Row(
            children: [
              IconButton(
                tooltip: '上一年',
                onPressed: () => onChangeYear(-1),
                icon: const Icon(Icons.chevron_left),
              ),
              Expanded(
                child: Text(
                  '$year年',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: scheme.onSurface,
                  ),
                ),
              ),
              TextButton(onPressed: onToday, child: const Text('今天')),
              IconButton(
                tooltip: '下一年',
                onPressed: () => onChangeYear(1),
                icon: const Icon(Icons.chevron_right),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Row(
            children: [
              Container(
                width: 14,
                height: 3,
                decoration: BoxDecoration(
                  color: scheme.primary,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${lunarYear.yearGanZhi}${lunarYear.shengXiao}年 · 每月农历初一',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth;
              final columns = width >= 760 ? 4 : (width >= 500 ? 3 : 2);
              return GridView.builder(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 112),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: columns,
                  mainAxisExtent: width < 400 ? 185 : 205,
                  crossAxisSpacing: 8,
                  mainAxisSpacing: 4,
                ),
                itemCount: 12,
                itemBuilder: (context, index) =>
                    _miniMonth(context, year, index + 1, width / columns),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _miniMonth(
    BuildContext context,
    int year,
    int month,
    double cellWidth,
  ) {
    final first = DateTime(year, month, 1);
    final days = DateTime(year, month + 1, 0).day;
    final leading = first.weekday - DateTime.monday;
    final scheme = Theme.of(context).colorScheme;
    final textScale = MediaQuery.textScalerOf(context).scale(1);
    final dayFont = ((cellWidth / 9.2) / textScale).clamp(8.0, 11.0);
    final monthFont = ((cellWidth / 8.0) / textScale).clamp(14.0, 18.0);
    final dateCellHeight = cellWidth < 130 ? 18.0 : 20.0;
    final current = store.today.year == year && store.today.month == month;
    final selected =
        store.selectedDate.year == year && store.selectedDate.month == month;
    return Semantics(
      button: true,
      label: '$year年$month月',
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => onPickMonth(
          dateWithClampedDay(year, month, store.selectedDate.day),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(6, 5, 6, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '$month月',
                      style: TextStyle(
                        fontSize: monthFont,
                        fontWeight: FontWeight.w600,
                        color: selected
                            ? scheme.primary
                            : _monthColor(context, year, month),
                      ),
                    ),
                  ),
                  if (current)
                    Icon(Icons.circle, size: 6, color: scheme.primary),
                ],
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  for (final label in const ['一', '二', '三', '四', '五', '六', '日'])
                    Expanded(
                      child: Center(
                        child: Text(
                          label,
                          style: TextStyle(
                            fontSize: (dayFont - 1).clamp(7.0, 9.0),
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 2),
              Expanded(
                child: GridView.builder(
                  padding: EdgeInsets.zero,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 7,
                    mainAxisExtent: dateCellHeight + 2,
                  ),
                  itemCount: ((leading + days + 6) ~/ 7) * 7,
                  itemBuilder: (context, index) {
                    final day = index - leading + 1;
                    if (day < 1 || day > days) return const SizedBox.shrink();
                    final date = DateTime(year, month, day);
                    final isToday =
                        store.today.year == year &&
                        store.today.month == month &&
                        store.today.day == day;
                    final isSelectedDate =
                        store.selectedDate.year == year &&
                        store.selectedDate.month == month &&
                        store.selectedDate.day == day;
                    final lunar = lunarOf(date);
                    return Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: dateCellHeight - 1,
                          height: dateCellHeight - 1,
                          alignment: Alignment.center,
                          decoration: isToday
                              ? BoxDecoration(
                                  color: scheme.primary,
                                  shape: BoxShape.circle,
                                )
                              : (isSelectedDate
                                    ? BoxDecoration(
                                        color: scheme.primaryContainer,
                                        shape: BoxShape.circle,
                                      )
                                    : null),
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              '$day',
                              maxLines: 1,
                              style: TextStyle(
                                fontSize: dayFont,
                                color: isToday
                                    ? scheme.onPrimary
                                    : (isSelectedDate
                                          ? scheme.onPrimaryContainer
                                          : scheme.onSurface),
                              ),
                            ),
                          ),
                        ),
                        SizedBox(
                          height: 1,
                          child: Container(
                            width: 8,
                            decoration: BoxDecoration(
                              color: lunar.dayChinese == '初一'
                                  ? scheme.primary
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
