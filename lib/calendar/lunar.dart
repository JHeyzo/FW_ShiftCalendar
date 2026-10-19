import 'package:characters/characters.dart';
import 'package:flutter/foundation.dart';
import 'package:lunar_plus/lunar.dart';

/// 自 epoch（1970-01-01）的天数。
int dayNumber(DateTime date) {
  final d = DateTime.utc(date.year, date.month, date.day);
  return d.difference(DateTime.utc(1970, 1, 1)).inDays;
}

/// 法定节假日名称（用于高亮）。清明节通过节气「清明」判断。
const _legalHolidays = {'元旦节', '春节', '劳动节', '端午节', '中秋节', '国庆节'};

/// 一条法定节假日区间（含首尾两天，国务院官方放假安排）。
class _HolidaySpan {
  const _HolidaySpan(this.name, this.startDay, this.endDay);

  final String name;
  final int startDay;
  final int endDay;
}

/// 国务院官方「法定节假日」整段区间（2025 / 2026）。
final List<_HolidaySpan> _holidaySpans = [
  // 2026
  _HolidaySpan(
    '元旦节',
    dayNumber(DateTime(2026, 1, 1)),
    dayNumber(DateTime(2026, 1, 3)),
  ),
  _HolidaySpan(
    '春节',
    dayNumber(DateTime(2026, 2, 15)),
    dayNumber(DateTime(2026, 2, 23)),
  ),
  _HolidaySpan(
    '清明节',
    dayNumber(DateTime(2026, 4, 4)),
    dayNumber(DateTime(2026, 4, 6)),
  ),
  _HolidaySpan(
    '劳动节',
    dayNumber(DateTime(2026, 5, 1)),
    dayNumber(DateTime(2026, 5, 5)),
  ),
  _HolidaySpan(
    '端午节',
    dayNumber(DateTime(2026, 6, 19)),
    dayNumber(DateTime(2026, 6, 21)),
  ),
  _HolidaySpan(
    '中秋节',
    dayNumber(DateTime(2026, 9, 25)),
    dayNumber(DateTime(2026, 9, 27)),
  ),
  _HolidaySpan(
    '国庆节',
    dayNumber(DateTime(2026, 10, 1)),
    dayNumber(DateTime(2026, 10, 7)),
  ),
  // 2025
  _HolidaySpan(
    '元旦节',
    dayNumber(DateTime(2025, 1, 1)),
    dayNumber(DateTime(2025, 1, 1)),
  ),
  _HolidaySpan(
    '春节',
    dayNumber(DateTime(2025, 1, 28)),
    dayNumber(DateTime(2025, 2, 4)),
  ),
  _HolidaySpan(
    '清明节',
    dayNumber(DateTime(2025, 4, 4)),
    dayNumber(DateTime(2025, 4, 6)),
  ),
  _HolidaySpan(
    '劳动节',
    dayNumber(DateTime(2025, 5, 1)),
    dayNumber(DateTime(2025, 5, 5)),
  ),
  _HolidaySpan(
    '端午节',
    dayNumber(DateTime(2025, 5, 31)),
    dayNumber(DateTime(2025, 6, 2)),
  ),
  _HolidaySpan(
    '中秋节·国庆节',
    dayNumber(DateTime(2025, 10, 1)),
    dayNumber(DateTime(2025, 10, 8)),
  ),
];

/// 调休上班日（假期里被调成上班的周末），日历上打「班」小标记。
final Set<int> _makeupDays = {
  // 2026
  dayNumber(DateTime(2026, 1, 4)),
  dayNumber(DateTime(2026, 2, 14)),
  dayNumber(DateTime(2026, 2, 28)),
  dayNumber(DateTime(2026, 5, 9)),
  dayNumber(DateTime(2026, 9, 20)),
  dayNumber(DateTime(2026, 10, 10)),
  // 2025
  dayNumber(DateTime(2025, 1, 26)),
  dayNumber(DateTime(2025, 2, 8)),
  dayNumber(DateTime(2025, 4, 27)),
  dayNumber(DateTime(2025, 9, 28)),
  dayNumber(DateTime(2025, 10, 11)),
};

/// 该日期所在法定节假日的名称（非假期返回 null）。
String? holidayNameOf(DateTime date) {
  final d = dayNumber(date);
  for (final s in _holidaySpans) {
    if (d >= s.startDay && d <= s.endDay) return s.name;
  }
  return null;
}

/// 该日期是否为调休上班日。
bool isMakeupWorkdayOf(DateTime date) => _makeupDays.contains(dayNumber(date));

/// 某天的农历/节日/节气信息（数据源 lunar_plus）。
class LunarInfo {
  const LunarInfo({
    required this.monthChinese,
    required this.dayChinese,
    required this.jieQi,
    required this.festivals,
    required this.otherFestivals,
    required this.yearGanZhi,
    required this.dayGanZhi,
    required this.shengXiao,
    required this.holidayName,
    required this.isMakeupWorkday,
  });

  final String monthChinese; // 正月
  final String dayChinese; // 初一
  final String jieQi; // 节气（无则为空串）
  final List<String> festivals; // 大节日：农历传统 + 农历其他 + 公历正式
  final List<String> otherFestivals; // 小日子：公历纪念日等
  final String yearGanZhi;
  final String dayGanZhi;
  final String shengXiao;
  final String holidayName; // 所在法定节假日名称（非假期为空串）
  final bool isMakeupWorkday; // 是否调休上班日

  bool get isLegalHoliday =>
      holidayName.isNotEmpty ||
      festivals.any(_legalHolidays.contains) ||
      jieQi == '清明';

  /// 格子里的一行小字：大节日优先 → 节气 → 农历日。
  String get shortLabel {
    if (festivals.isNotEmpty) return festivals.first;
    if (jieQi.isNotEmpty) return jieQi;
    return dayChinese;
  }

  /// 格子小字截断（3 字 + 省略号）。
  String get cellLabel {
    final s = shortLabel;
    if (s.characters.length <= 3) return s;
    return '${s.characters.take(3)}…';
  }
}

const int _lunarCacheMax = 1024;
final Map<int, LunarInfo> _lunarCache = <int, LunarInfo>{};

@visibleForTesting
void lunarCacheClear() => _lunarCache.clear();

/// 某一天的农历信息（带缓存）。
LunarInfo lunarOf(DateTime date) {
  final key = dayNumber(date);
  final hit = _lunarCache[key];
  if (hit != null) return hit;
  if (_lunarCache.length >= _lunarCacheMax) _lunarCache.clear();
  final solar = Solar.fromYmd(date.year, date.month, date.day);
  final lunar = solar.getLunar();
  final info = LunarInfo(
    monthChinese: lunar.getMonthInChinese(),
    dayChinese: lunar.getDayInChinese(),
    jieQi: lunar.getJieQi(),
    festivals: [
      ...lunar.getFestivals(),
      ...lunar.getOtherFestivals(),
      ...solar.getFestivals(),
    ],
    otherFestivals: solar.getOtherFestivals(),
    yearGanZhi: lunar.getYearInGanZhi(),
    dayGanZhi: lunar.getDayInGanZhi(),
    shengXiao: lunar.getYearShengXiao(),
    holidayName: holidayNameOf(date) ?? '',
    isMakeupWorkday: isMakeupWorkdayOf(date),
  );
  _lunarCache[key] = info;
  return info;
}

/// ISO 8601 周序号。
int isoWeekNumber(DateTime date) {
  final d = DateTime.utc(date.year, date.month, date.day);
  // 周四所在的周为该周序号
  final thursday = d.add(Duration(days: 4 - d.weekday));
  final jan1 = DateTime.utc(thursday.year, 1, 1);
  return (thursday.difference(jan1).inDays ~/ 7) + 1;
}
