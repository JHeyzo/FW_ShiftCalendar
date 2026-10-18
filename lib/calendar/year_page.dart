import 'package:flutter/material.dart';

import '../theme/fw_tokens.dart';
import 'lunar.dart';

/// 年视图：对齐 ColorOS 系统日历（12 个迷你月历）。
class YearPage extends StatelessWidget {
  const YearPage({
    super.key,
    required this.year,
    required this.today,
    required this.onPickMonth,
  });

  final int year;
  final DateTime today;
  final ValueChanged<int> onPickMonth;

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  @override
  Widget build(BuildContext context) {
    final g = lunarOf(DateTime(year, 1, 1));
    return Column(
      children: [
        _header(g),
        Expanded(
          child: SingleChildScrollView(
            padding:
                const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              children: [
                for (var r = 0; r < 4; r++)
                  Row(
                    crossAxisAlignment:
                        CrossAxisAlignment.start,
                    children: [
                      for (var c = 0; c < 3; c++)
                        Expanded(
                            child:
                                _miniMonth(r * 3 + c + 1)),
                    ],
                  ),
                const SizedBox(height: 100),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _header(LunarInfo g) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 4, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('$year年', style: FwTokens.monthTitle),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.more_vert, size: 24),
                onPressed: () {},
              ),
            ],
          ),
          const SizedBox(height: 2),
          Row(
            children: [
              _dash(),
              Text(
                ' ${g.yearGanZhi}${g.shengXiao}年 ',
                style: const TextStyle(
                    fontSize: 14, color: FwTokens.ink55),
              ),
              _dash(),
              const Text(
                ' 每月农历初一',
                style: TextStyle(
                    fontSize: 14, color: FwTokens.ink55),
              ),
            ],
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }

  Widget _dash() => Container(
        width: 12,
        height: 3,
        decoration: BoxDecoration(
          color: FwTokens.brand,
          borderRadius: BorderRadius.circular(1.5),
        ),
      );

  Widget _miniMonth(int m) {
    final first = DateTime(year, m, 1);
    final days = DateTime(year, m + 1, 0).day;
    final leading = first.weekday - 1;
    final isThisMonth =
        today.year == year && today.month == m;
    return GestureDetector(
      onTap: () => onPickMonth(m),
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding:
            const EdgeInsets.only(bottom: 20, right: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '$m月',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w500,
                color: isThisMonth
                    ? FwTokens.brand
                    : FwTokens.ink,
              ),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                for (final n in ['一', '二', '三', '四', '五', '六', '日'])
                  Expanded(
                    child: Center(
                      child: Text(n,
                          style: const TextStyle(
                              fontSize: 9,
                              color: FwTokens.ink30)),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 2),
            GridView.builder(
              shrinkWrap: true,
              physics:
                  const NeverScrollableScrollPhysics(),
              gridDelegate:
                  const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 7,
                mainAxisExtent: 22,
              ),
              itemCount: leading + days,
              itemBuilder: (_, i) {
                if (i < leading) return const SizedBox();
                final d = i - leading + 1;
                final date = DateTime(year, m, d);
                final li = lunarOf(date);
                final isToday = _sameDay(date, today);
                final chuYi = li.dayChinese == '初一';
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 20,
                      height: 18,
                      alignment: Alignment.center,
                      decoration: isToday
                          ? const BoxDecoration(
                              color: FwTokens.brand,
                              shape: BoxShape.circle)
                          : null,
                      child: Text(
                        '$d',
                        style: TextStyle(
                          fontSize: 11,
                          color: isToday
                              ? Colors.white
                              : FwTokens.ink,
                        ),
                      ),
                    ),
                    Container(
                      width: 10,
                      height: 2,
                      decoration: BoxDecoration(
                        color: chuYi
                            ? FwTokens.brand
                            : Colors.transparent,
                        borderRadius:
                            BorderRadius.circular(1),
                      ),
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
