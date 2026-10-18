import 'package:flutter/material.dart';

import '../theme/fw_tokens.dart';
import 'lunar.dart';

/// 月视图：对齐 ColorOS 系统日历。
/// 空壳阶段：纯日历功能（手势翻月/选日/农历/节假日标记），排班功能后续接。
class MonthPage extends StatefulWidget {
  const MonthPage({
    super.key,
    required this.initialMonth,
    required this.onOpenYear,
    required this.onMonthChanged,
  });

  /// 外部指定的月份（年视图点选回来时用）。
  final DateTime initialMonth;

  /// 点左上 "<"：进年视图。
  final VoidCallback onOpenYear;

  /// 翻月后回调用，同步外部持有的月份。
  final ValueChanged<DateTime> onMonthChanged;

  @override
  State<MonthPage> createState() => _MonthPageState();
}

class _MonthPageState extends State<MonthPage> {
  late DateTime _month; // 当月（日固定为 1）
  late DateTime _selected;
  final DateTime _today = DateTime.now();
  int _slideDir = 1; // 翻月动画方向：1 下个月，-1 上个月

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _month = DateTime(
        widget.initialMonth.year, widget.initialMonth.month, 1);
    _selected =
        (_month.year == now.year && _month.month == now.month)
            ? DateTime(now.year, now.month, now.day)
            : DateTime(_month.year, _month.month, 1);
  }

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  void _goMonth(int delta) {
    setState(() {
      _slideDir = delta >= 0 ? 1 : -1;
      _month = DateTime(_month.year, _month.month + delta, 1);
      final last = DateTime(_month.year, _month.month + 1, 0).day;
      final d = _selected.day > last ? last : _selected.day;
      _selected = DateTime(_month.year, _month.month, d);
    });
    widget.onMonthChanged(_month);
  }

  void _goToday() {
    setState(() {
      _month = DateTime(_today.year, _today.month, 1);
      _selected = DateTime(_today.year, _today.month, _today.day);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _header(),
        _weekdayRow(),
        _swipeableGrid(),
        _divider(),
        _dayDetail(),
      ],
    );
  }

  /// 月历左右滑动翻月（对齐原版手势）。
  Widget _swipeableGrid() {
    return GestureDetector(
      onHorizontalDragEnd: (details) {
        final v = details.primaryVelocity ?? 0;
        if (v < -200) {
          _goMonth(1);
        } else if (v > 200) {
          _goMonth(-1);
        }
      },
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 250),
        transitionBuilder: (child, animation) {
          final begin = Offset(0.25 * _slideDir, 0);
          return SlideTransition(
            position: Tween(begin: begin, end: Offset.zero)
                .animate(CurvedAnimation(
                    parent: animation,
                    curve: Curves.easeOut)),
            child: child,
          );
        },
        child: KeyedSubtree(
          key: ValueKey('${_month.year}-${_month.month}'),
          child: _gridColumn(),
        ),
      ),
    );
  }

  Widget _header() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 4, 4),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left, size: 28),
            onPressed: widget.onOpenYear, // 原版：< 进年视图
          ),
          GestureDetector(
            onTap: _goToday,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  '${_month.year}年${_month.month}月',
                  style: FwTokens.monthTitle,
                ),
                const SizedBox(width: 8),
                Text(
                  '第${isoWeekNumber(_selected)}周',
                  style:
                      const TextStyle(fontSize: 14, color: FwTokens.ink55),
                ),
              ],
            ),
          ),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.more_vert, size: 24),
            onPressed: () => _menu(),
          ),
        ],
      ),
    );
  }

  void _menu() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.calendar_month_outlined),
              title: const Text('排班管理'),
              subtitle: const Text('空壳：后续接排班配置'),
              onTap: () => Navigator.pop(context),
            ),
            ListTile(
              leading: const Icon(Icons.settings_outlined),
              title: const Text('设置'),
              subtitle: const Text('空壳'),
              onTap: () => Navigator.pop(context),
            ),
          ],
        ),
      ),
    );
  }

  Widget _weekdayRow() {
    const names = ['一', '二', '三', '四', '五', '六', '日'];
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          for (final n in names)
            Expanded(
              child: Center(child: Text(n, style: FwTokens.weekTitle)),
            ),
        ],
      ),
    );
  }

  Widget _gridColumn() {
    final first = _month;
    final leading = first.weekday - 1; // 周一为首
    final days = DateTime(first.year, first.month + 1, 0).day;
    final total = leading + days;
    final rows = (total / 7).ceil();
    return Column(
      children: [
        for (var r = 0; r < rows; r++)
          Row(
            children: [
              for (var c = 0; c < 7; c++)
                Expanded(child: _cell(r * 7 + c - leading)),
            ],
          ),
      ],
    );
  }

  Widget _cell(int day) {
    final days = DateTime(_month.year, _month.month + 1, 0).day;
    if (day < 1 || day > days) return const SizedBox(height: 72);
    final date = DateTime(_month.year, _month.month, day);
    final info = lunarOf(date);
    final isToday = _sameDay(date, _today);
    final isSelected = _sameDay(date, _selected);
    final mark = info.holidayName.isNotEmpty
        ? '休'
        : (info.isMakeupWorkday ? '班' : null);

    return GestureDetector(
      onTap: () => setState(() => _selected = date),
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        height: 72,
        child: Stack(
          children: [
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 6),
                Container(
                  width: 40,
                  height: 40,
                  alignment: Alignment.center,
                  decoration: isToday
                      ? const BoxDecoration(
                          color: FwTokens.brand, shape: BoxShape.circle)
                      : null,
                  child: Text(
                    '$day',
                    style: isToday
                        ? FwTokens.dayNumberToday
                        : FwTokens.dayNumber,
                  ),
                ),
                Text(info.cellLabel, style: FwTokens.lunar),
                Container(
                  margin: const EdgeInsets.only(top: 2),
                  width: 24,
                  height: 2.5,
                  decoration: BoxDecoration(
                    color: isSelected ? FwTokens.brand : Colors.transparent,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ],
            ),
            if (mark != null)
              Positioned(
                top: 2,
                right: 8,
                child: Text(
                  mark,
                  style: mark == '休'
                      ? FwTokens.markRestStyle
                      : FwTokens.markWorkStyle,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _divider() {
    return Column(
      children: [
        const Divider(height: 1, thickness: 0.5, color: Color(0xFFE5E5EA)),
        const SizedBox(height: 8),
        Container(
          width: 72,
          height: 4,
          decoration: BoxDecoration(
            color: const Color(0xFFE0E0E5),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(height: 8),
      ],
    );
  }

  Widget _dayDetail() {
    final info = lunarOf(_selected);
    final isToday = _sameDay(_selected, _today);
    final title = isToday
        ? '今天 ${_selected.month}月${_selected.day}日'
        : '${_selected.month}月${_selected.day}日';
    final lunarText = '农历${info.monthChinese}${info.dayChinese}';
    final cardTitle = info.festivals.isNotEmpty
        ? info.festivals.join('、')
        : info.shortLabel;

    return Expanded(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: FwTokens.padPage),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(title,
                    style: const TextStyle(
                        fontSize: 16, color: FwTokens.ink55)),
                const Spacer(),
                Text(lunarText,
                    style: const TextStyle(
                        fontSize: 16, color: FwTokens.ink55)),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: FwTokens.cardBg,
                borderRadius:
                    BorderRadius.circular(FwTokens.radiusCard),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x0D000000),
                    blurRadius: 12,
                    offset: Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Container(
                    width: 4,
                    height: 40,
                    decoration: BoxDecoration(
                      color: FwTokens.eventBar,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(cardTitle,
                            style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: FwTokens.ink)),
                        const SizedBox(height: 4),
                        const Text('全天',
                            style: TextStyle(
                                fontSize: 14, color: FwTokens.ink55)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            const Text('推荐', style: FwTokens.sectionHead),
            const SizedBox(height: 80),
          ],
        ),
      ),
    );
  }
}
