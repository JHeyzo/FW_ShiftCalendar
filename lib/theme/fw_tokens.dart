import 'package:flutter/material.dart';

/// 设计 token：从 ColorOS 日历 16.26.20 反编译摘录（见
/// `workspace/coloros-calendar-design-tokens.md`），只取数值型 token。
abstract final class FwTokens {
  // ---------- 颜色 ----------
  static const Color pageBg = Color(0xFFF9F9FB); // base_background_color
  static const Color ink = Color(0xFF000000); // 主文字
  static const Color ink55 = Color(0x8C000000); // 次级文字 55% 黑
  static const Color ink30 = Color(0x4D000000); // 禁用/提示 30% 黑
  static const Color brand = Color(0xFF0066FF); // Blue50
  static const Color link = Color(0xFF5476FF); // 可点文字
  static const Color brandBg = Color(0x1F0066FF); // 品牌蓝 12% 底
  static const Color cardBg = Color(0xFFFFFFFF);
  static const Color markRest = Color(0xFF0066FF); // 「休」小标
  static const Color markWork = Color(0xFFF08900); // 「班」小标（调休上班）
  static const Color eventBar = Color(0xFFFF9F0A); // 日程卡左侧色条

  // ---------- 字号 ----------
  static const double spMonthTitle = 22; // 月标题
  static const double spTodoTitle = 16; // 待办标题
  static const double spTodoMeta = 12; // 待办时间/逾期
  static const double spDayNumber = 22; // 月视图日期数字（屏摄观感）
  static const double spLunar = 12; // 农历小字（屏摄观感）
  static const double spWeekday = 14; // 星期标题
  static const double spEmpty = 14; // 空态提示
  static const double spMark = 10; // 休/班小标

  // ---------- 间距圆角 ----------
  static const double radiusCard = 16; // 卡片圆角
  static const double radiusPill = 999; // 胶囊
  static const double padPage = 12; // 列表左右 padding
  static const double gapCardV = 4; // 卡片上下外边距（间距 8）
  static const double padCardV = 16; // 卡片内上下
  static const double padCardL = 48; // 卡片内左（含勾选位）
  static const double padCardR = 24; // 卡片内右
  static const double navBarH = 66; // 底部导航高

  // ---------- 文本样式 ----------
  static const TextStyle monthTitle =
      TextStyle(fontSize: spMonthTitle, color: ink, fontWeight: FontWeight.w500);
  static const TextStyle weekTitle =
      TextStyle(fontSize: spWeekday, color: ink30);
  static const TextStyle dayNumber =
      TextStyle(fontSize: spDayNumber, color: ink, fontWeight: FontWeight.w400);
  static const TextStyle dayNumberToday =
      TextStyle(fontSize: spDayNumber, color: Colors.white);
  static const TextStyle lunar =
      TextStyle(fontSize: spLunar, color: ink55);
  static const TextStyle markRestStyle =
      TextStyle(fontSize: spMark, color: markRest);
  static const TextStyle markWorkStyle =
      TextStyle(fontSize: spMark, color: markWork);
  static const TextStyle sectionHead =
      TextStyle(fontSize: spEmpty, color: ink55);
}
