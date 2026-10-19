import 'package:flutter/material.dart';

import '../data/app_store.dart';
import '../widgets/entry_tile.dart';
import 'lunar.dart';
import 'year_page.dart';

/// Monday-first dates for every visible cell in a month grid. Nulls are the
/// leading/trailing cells outside the displayed month.
List<DateTime?> monthGridDates(DateTime month) {
  final first = DateTime(month.year, month.month, 1);
  final days = DateTime(month.year, month.month + 1, 0).day;
  final leading = first.weekday - DateTime.monday;
  final cellCount = ((leading + days + 6) ~/ 7) * 7;
  return List<DateTime?>.generate(cellCount, (index) {
    final day = index - leading + 1;
    if (day < 1 || day > days) return null;
    return DateTime(month.year, month.month, day);
  }, growable: false);
}

DateTime dateInMonthPreservingDay(int year, int month, int selectedDay) {
  final lastDay = DateTime(year, month + 1, 0).day;
  return DateTime(year, month, selectedDay.clamp(1, lastDay));
}

DateTime _dateOnly(DateTime date) => DateTime(date.year, date.month, date.day);
bool _sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;
DateTime _mondayOf(DateTime date) =>
    DateTime(date.year, date.month, date.day - date.weekday + DateTime.monday);
String _dateLabel(DateTime date) => '${date.month}月${date.day}日';

/// Main calendar surface. The AppStore is the sole owner of selected date and
/// view state so changing modes or rebuilding the page cannot reset selection.
class MonthPage extends StatefulWidget {
  const MonthPage({
    super.key,
    required this.store,
    required this.onCreate,
    required this.onEdit,
    required this.onSettings,
    required this.onManage,
    required this.onSearch,
  });

  final AppStore store;
  final void Function(DateTime date) onCreate;
  final void Function(CalendarEntry entry, DateTime occurrenceDate) onEdit;
  final VoidCallback onSettings;
  final VoidCallback onManage;
  final VoidCallback onSearch;

  @override
  State<MonthPage> createState() => _MonthPageState();
}

class _MonthPageState extends State<MonthPage> {
  bool _collapsed = false;
  int _dragAccumulator = 0;
  int _slideDirection = 1;

  AppStore get store => widget.store;
  DateTime get selected => _dateOnly(store.selectedDate);
  DateTime get month => DateTime(selected.year, selected.month, 1);
  ColorScheme get colors => Theme.of(context).colorScheme;

  void _moveMonth(int amount) {
    _slideDirection = amount >= 0 ? 1 : -1;
    store.moveMonth(amount);
  }

  void _setView(String view) => store.setView(view);

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: selected,
      firstDate: DateTime(1900),
      lastDate: DateTime(2100, 12, 31),
      helpText: '选择日期',
    );
    if (picked != null) store.selectDate(_dateOnly(picked));
  }

  void _changeYear(int delta) {
    final year = selected.year + delta;
    final lastDay = DateTime(year, selected.month + 1, 0).day;
    store.selectDate(
      DateTime(year, selected.month, selected.day.clamp(1, lastDay)),
    );
  }

  void _onHeaderBack(String view) {
    if (view == '月') {
      _setView('年');
    } else if (view == '年') {
      _changeYear(-1);
    } else {
      _moveMonth(-1);
    }
  }

  void _onDateTap(DateTime date) {
    final wasSelected = _sameDay(date, selected);
    store.selectDate(date);
    if (wasSelected) _setView('列表');
  }

  Future<void> _showMenu() async {
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const ListTile(title: Text('日历视图')),
              for (final view in const ['年', '月', '周', '列表', '时间线', '概览'])
                ListTile(
                  leading: Icon(_iconForView(view)),
                  title: Text(view),
                  trailing: store.view == view
                      ? Icon(Icons.check, color: colors.primary)
                      : null,
                  onTap: () => Navigator.pop(sheetContext, 'view:$view'),
                ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.search),
                title: const Text('搜索日历'),
                onTap: () => Navigator.pop(sheetContext, 'search'),
              ),
              ListTile(
                leading: const Icon(Icons.calendar_month_outlined),
                title: const Text('日历管理'),
                onTap: () => Navigator.pop(sheetContext, 'manage'),
              ),
              ListTile(
                leading: const Icon(Icons.settings_outlined),
                title: const Text('设置'),
                onTap: () => Navigator.pop(sheetContext, 'settings'),
              ),
            ],
          ),
        ),
      ),
    );
    if (!mounted || action == null) return;
    if (action.startsWith('view:')) {
      _setView(action.substring(5));
    } else if (action == 'search') {
      widget.onSearch();
    } else if (action == 'manage') {
      widget.onManage();
    } else if (action == 'settings') {
      widget.onSettings();
    }
  }

  IconData _iconForView(String view) => switch (view) {
    '年' => Icons.calendar_view_month,
    '月' => Icons.calendar_month,
    '周' => Icons.view_week_outlined,
    '列表' => Icons.view_agenda_outlined,
    '时间线' => Icons.timeline,
    _ => Icons.dashboard_outlined,
  };

  @override
  Widget build(BuildContext context) {
    final view = store.view;
    return Column(
      children: [
        _header(view),
        Expanded(
          child: view == '年'
              ? YearPage(
                  store: store,
                  onPickMonth: (date) {
                    store.selectDate(date);
                    _setView('月');
                  },
                  onChangeYear: _changeYear,
                  onToday: store.goToday,
                )
              : _buildScrollableView(view),
        ),
      ],
    );
  }

  Widget _header(String view) {
    final title = switch (view) {
      '年' => '${selected.year}年',
      _ => '${selected.year}年${selected.month}月',
    };
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 2),
      child: Row(
        children: [
          IconButton(
            tooltip: view == '月' ? '返回年视图' : '上一${view == '年' ? '年' : '月'}',
            onPressed: () => _onHeaderBack(view),
            icon: const Icon(Icons.chevron_left),
          ),
          Expanded(
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: _pickDate,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 21,
                        fontWeight: FontWeight.w600,
                        color: colors.onSurface,
                      ),
                    ),
                    if (view != '年')
                      Text(
                        '第${isoWeekNumber(selected)}周',
                        style: TextStyle(
                          fontSize: 12,
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
          TextButton(onPressed: store.goToday, child: const Text('今天')),
          IconButton(
            tooltip: '更多日历选项',
            onPressed: _showMenu,
            icon: const Icon(Icons.more_vert),
          ),
        ],
      ),
    );
  }

  Widget _buildScrollableView(String view) {
    if (view == '周') return _weekView();
    if (view == '列表') return _agendaView();
    if (view == '时间线') return _timelineView();
    if (view == '概览') return _overviewView();
    return _monthView();
  }

  Widget _monthView() {
    final dates = monthGridDates(month);
    final weekStart = _mondayOf(selected);
    final visibleDates = _collapsed
        ? List<DateTime?>.generate(
            7,
            (i) => DateTime(weekStart.year, weekStart.month, weekStart.day + i),
          )
        : dates;
    final rowCount = visibleDates.length ~/ 7;
    final lunar = lunarOf(selected);
    final visibleStart = _collapsed ? weekStart : month;
    final visibleEnd = _collapsed
        ? DateTime(weekStart.year, weekStart.month, weekStart.day + 7)
        : DateTime(month.year, month.month + 1, 1);
    final occurrencesByDay = _indexOccurrences(
      _occurrences(visibleStart, visibleEnd),
      visibleStart,
      visibleEnd,
    );
    final dayOccurrences = occurrencesByDay[_dateOnly(selected)] ?? const [];
    return CustomScrollView(
      key: const PageStorageKey<String>('month-scroll'),
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        SliverToBoxAdapter(
          child: GestureDetector(
            onHorizontalDragEnd: (details) {
              final velocity = details.primaryVelocity ?? 0;
              if (velocity < -160) _moveMonth(1);
              if (velocity > 160) _moveMonth(-1);
            },
            child: Column(
              children: [
                _weekdayHeader(),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 180),
                  transitionBuilder: (child, animation) => SlideTransition(
                    position: Tween<Offset>(
                      begin: Offset(0.05 * _slideDirection, 0),
                      end: Offset.zero,
                    ).animate(animation),
                    child: child,
                  ),
                  child: Column(
                    key: ValueKey('${month.year}-${month.month}-$_collapsed'),
                    children: [
                      for (var row = 0; row < rowCount; row++)
                        Row(
                          children: [
                            for (var column = 0; column < 7; column++)
                              Expanded(
                                child: _dayCell(
                                  visibleDates[row * 7 + column],
                                  occurrencesByDay: occurrencesByDay,
                                ),
                              ),
                          ],
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        SliverToBoxAdapter(child: _foldHandle()),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '${_sameDay(selected, store.today) ? '今天 · ' : ''}${_dateLabel(selected)}',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: colors.onSurface,
                    ),
                  ),
                ),
                Flexible(
                  child: Text(
                    '农历${lunar.monthChinese}${lunar.dayChinese}',
                    textAlign: TextAlign.end,
                    style: TextStyle(
                      fontSize: 13,
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        SliverToBoxAdapter(child: _lunarInformation(lunar)),
        if (dayOccurrences.isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: _emptyState(
              '这一天没有日程或待办',
              icon: Icons.event_available_outlined,
            ),
          )
        else
          _occurrenceSliver(dayOccurrences),
        const SliverToBoxAdapter(child: SizedBox(height: 112)),
      ],
    );
  }

  Widget _weekdayHeader() {
    const labels = ['一', '二', '三', '四', '五', '六', '日'];
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          for (var i = 0; i < labels.length; i++)
            Expanded(
              child: Center(
                child: Text(
                  labels[i],
                  style: TextStyle(
                    fontSize: 13,
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _dayCell(
    DateTime? date, {
    Map<DateTime, List<dynamic>>? occurrencesByDay,
  }) {
    if (date == null) return const SizedBox(height: 65);
    final isToday = _sameDay(date, store.today);
    final isSelected = _sameDay(date, selected);
    final lunar = lunarOf(date);
    final hasItems = occurrencesByDay?[_dateOnly(date)]?.isNotEmpty ?? false;
    final mark = lunar.holidayName.isNotEmpty
        ? '休'
        : (lunar.isMakeupWorkday ? '班' : null);
    final cellHeight = (MediaQuery.sizeOf(context).width / 8.4).clamp(
      52.0,
      74.0,
    );
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _onDateTap(date),
      onLongPress: () {
        store.selectDate(date);
        widget.onCreate(date);
      },
      child: SizedBox(
        height: cellHeight,
        child: Stack(
          children: [
            Column(
              mainAxisAlignment: MainAxisAlignment.start,
              children: [
                const SizedBox(height: 2),
                Container(
                  width: 32,
                  height: 32,
                  decoration: isToday
                      ? BoxDecoration(
                          color: colors.primary,
                          shape: BoxShape.circle,
                        )
                      : null,
                  alignment: Alignment.center,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      '${date.day}',
                      maxLines: 1,
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: isSelected
                            ? FontWeight.w700
                            : FontWeight.w400,
                        color: isToday ? colors.onPrimary : colors.onSurface,
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 1),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        lunar.cellLabel,
                        maxLines: 1,
                        style: TextStyle(
                          fontSize: 10,
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (hasItems)
                      Container(
                        width: 4,
                        height: 4,
                        decoration: BoxDecoration(
                          color: colors.primary,
                          shape: BoxShape.circle,
                        ),
                      ),
                    if (hasItems && isSelected) const SizedBox(width: 3),
                    Container(
                      width: isSelected ? 11 : 0,
                      height: 2,
                      decoration: BoxDecoration(
                        color: isSelected ? colors.primary : Colors.transparent,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
              ],
            ),
            if (mark != null)
              Positioned(
                top: 1,
                right: 2,
                child: Text(
                  mark,
                  style: TextStyle(
                    fontSize: 9,
                    color: mark == '休'
                        ? colors.primary
                        : const Color(0xFFF08900),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _foldHandle() => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: () => setState(() => _collapsed = !_collapsed),
    onVerticalDragStart: (_) => _dragAccumulator = 0,
    onVerticalDragUpdate: (details) =>
        _dragAccumulator += details.delta.dy.round(),
    onVerticalDragEnd: (_) {
      if (_dragAccumulator.abs() > 12) {
        setState(() => _collapsed = _dragAccumulator > 0);
      }
      _dragAccumulator = 0;
    },
    child: Tooltip(
      message: _collapsed ? '展开月历' : '收起月历',
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Center(
          child: Container(
            width: 44,
            height: 4,
            decoration: BoxDecoration(
              color: colors.outlineVariant,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
        ),
      ),
    ),
  );

  Widget _lunarInformation(LunarInfo lunar) {
    final pieces = <String>[
      if (lunar.festivals.isNotEmpty) ...lunar.festivals,
      if (lunar.jieQi.isNotEmpty) lunar.jieQi,
      if (lunar.holidayName.isNotEmpty) lunar.holidayName,
      if (lunar.isMakeupWorkday) '调休上班',
    ];
    if (pieces.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: Text(
        pieces.toSet().join(' · '),
        style: TextStyle(fontSize: 12, color: colors.secondary),
      ),
    );
  }

  List<dynamic> _occurrences(DateTime from, DateTime to) =>
      store
          .occurrences(_dateOnly(from), _dateOnly(to), visibleOnly: true)
          .toList()
        ..sort((a, b) => a.start.compareTo(b.start));

  Map<DateTime, List<dynamic>> _indexOccurrences(
    List<dynamic> occurrences,
    DateTime from,
    DateTime to,
  ) {
    final result = <DateTime, List<dynamic>>{};
    for (final occurrence in occurrences) {
      final start = occurrence.start as DateTime;
      final end = occurrence.end as DateTime;
      var day = _dateOnly(start.isBefore(from) ? from : start);
      final lastCoveredDay = end.isAfter(start)
          ? _dateOnly(end.subtract(const Duration(microseconds: 1)))
          : _dateOnly(start);
      while (!day.isAfter(lastCoveredDay) && day.isBefore(to)) {
        (result[day] ??= <dynamic>[]).add(occurrence);
        day = DateTime(day.year, day.month, day.day + 1);
      }
    }
    return result;
  }

  Widget _weekView() {
    final start = _mondayOf(selected);
    final end = DateTime(start.year, start.month, start.day + 7);
    final items = _occurrences(start, end);
    final occurrencesByDay = _indexOccurrences(items, start, end);
    return ListView(
      padding: const EdgeInsets.only(bottom: 112),
      children: [
        _weekdayHeader(),
        Row(
          children: [
            for (var i = 0; i < 7; i++)
              Expanded(
                child: _dayCell(
                  DateTime(start.year, start.month, start.day + i),
                  occurrencesByDay: occurrencesByDay,
                ),
              ),
          ],
        ),
        const Divider(height: 16),
        _sectionHeading('本周日程'),
        if (items.isEmpty)
          _emptyState('本周没有日程或待办', icon: Icons.event_available_outlined)
        else
          ..._groupedOccurrenceWidgets(items),
      ],
    );
  }

  Widget _agendaView() {
    final start = month;
    final end = DateTime(month.year, month.month + 1, 1);
    final items = _occurrences(start, end);
    return ListView(
      padding: const EdgeInsets.only(bottom: 112),
      children: [
        _sectionHeading('${month.year}年${month.month}月日程'),
        if (items.isEmpty)
          _emptyState('本月没有日程或待办', icon: Icons.event_available_outlined)
        else
          ..._groupedOccurrenceWidgets(items),
      ],
    );
  }

  Widget _timelineView() {
    final items = _occurrences(
      selected,
      DateTime(selected.year, selected.month, selected.day + 1),
    );
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 112),
      children: [
        _sectionHeading('${_dateLabel(selected)} · 时间线'),
        if (items.isEmpty)
          _emptyState('这一天没有日程或待办', icon: Icons.event_available_outlined)
        else
          ...items.map(_timelineItem),
      ],
    );
  }

  Widget _overviewView() {
    final start = month;
    final end = DateTime(month.year, month.month + 1, 1);
    final items = _occurrences(start, end);
    final days = <String>{
      for (final item in items)
        '${item.start.year}-${item.start.month}-${item.start.day}',
    }.length;
    final completed = items.where((item) => item.done).length;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 112),
      children: [
        _sectionHeading('${month.year}年${month.month}月概览'),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Wrap(
              spacing: 24,
              runSpacing: 12,
              children: [
                _stat('日程与待办', '${items.length}'),
                _stat('有安排的日期', '$days'),
                _stat('已完成', '$completed'),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        _sectionHeading('按日期'),
        if (items.isEmpty)
          _emptyState('本月没有日程或待办', icon: Icons.event_available_outlined)
        else
          ..._groupedOccurrenceWidgets(items),
      ],
    );
  }

  Widget _stat(String label, String value) => SizedBox(
    width: 130,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: 23,
            fontWeight: FontWeight.w700,
            color: colors.primary,
          ),
        ),
        Text(label, style: TextStyle(color: colors.onSurfaceVariant)),
      ],
    ),
  );

  List<Widget> _groupedOccurrenceWidgets(List<dynamic> items) {
    final grouped = <DateTime, List<dynamic>>{};
    for (final item in items) {
      final date = _dateOnly(item.start);
      (grouped[date] ??= <dynamic>[]).add(item);
    }
    return [
      for (final date
          in grouped.keys.toList()..sort((a, b) => a.compareTo(b))) ...[
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Text(
            '${date.year}年${_dateLabel(date)}${_sameDay(date, store.today) ? ' · 今天' : ''}',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: colors.onSurfaceVariant,
            ),
          ),
        ),
        ...grouped[date]!.map(_entryTile),
      ],
    ];
  }

  Widget _occurrenceSliver(List<dynamic> items) => SliverList(
    delegate: SliverChildBuilderDelegate(
      (context, index) => _entryTile(items[index]),
      childCount: items.length,
    ),
  );

  Widget _entryTile(dynamic occurrence) => EntryTile(
    occurrence: occurrence,
    store: store,
    onTap: () => widget.onEdit(
      occurrence.entry as CalendarEntry,
      occurrence.start as DateTime,
    ),
  );

  Widget _timelineItem(dynamic item) {
    final time = item.start.hour == 0 && item.start.minute == 0
        ? '全天'
        : '${item.start.hour.toString().padLeft(2, '0')}:${item.start.minute.toString().padLeft(2, '0')}';
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 52,
          child: Padding(
            padding: const EdgeInsets.only(top: 16),
            child: Text(
              time,
              style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant),
            ),
          ),
        ),
        Expanded(child: _entryTile(item)),
      ],
    );
  }

  Widget _sectionHeading(String text) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
    child: Text(
      text,
      style: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        color: colors.onSurface,
      ),
    ),
  );

  Widget _emptyState(String text, {required IconData icon}) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 36),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 34, color: colors.onSurfaceVariant),
        const SizedBox(height: 8),
        Text(
          text,
          textAlign: TextAlign.center,
          style: TextStyle(color: colors.onSurfaceVariant),
        ),
      ],
    ),
  );
}
