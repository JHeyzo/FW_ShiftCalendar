import 'dart:ui';

import 'package:flutter/material.dart';

import 'calendar/month_page.dart';
import 'calendar/year_page.dart';
import 'theme/fw_tokens.dart';
import 'todo/todo_page.dart';

void main() => runApp(const FengweiApp());

/// 风味日历：ColorOS 风味的排班日历（空壳阶段：纯日历功能）。
class FengweiApp extends StatelessWidget {
  const FengweiApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '风味日历',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: FwTokens.pageBg,
        colorScheme: ColorScheme.fromSeed(seedColor: FwTokens.brand),
      ),
      home: const HomeShell(),
    );
  }
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _tab = 0;
  bool _showYear = false;
  DateTime _month =
      DateTime(DateTime.now().year, DateTime.now().month, 1);

  /// 日历 tab：年视图 / 月视图切换。
  Widget _calendarTab() {
    if (_showYear) {
      final now = DateTime.now();
      return YearPage(
        year: _month.year,
        today: DateTime(now.year, now.month, now.day),
        onPickMonth: (m) => setState(() {
          _month = DateTime(_month.year, m, 1);
          _showYear = false;
        }),
      );
    }
    return MonthPage(
      key: ValueKey('month-$_month'),
      initialMonth: _month,
      onOpenYear: () => setState(() => _showYear = true),
      onMonthChanged: (m) => _month = m,
    );
  }

  void _create() {
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
              leading: const Icon(Icons.check_box_outlined),
              title: const Text('新建待办'),
              subtitle: const Text('空壳：后续接待办数据层'),
              onTap: () => Navigator.pop(context),
            ),
            ListTile(
              leading: const Icon(Icons.edit_calendar_outlined),
              title: const Text('手动调班'),
              subtitle: const Text('空壳：后续接排班覆盖'),
              onTap: () => Navigator.pop(context),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: IndexedStack(
          index: _tab,
          children: [_calendarTab(), const TodoPage()],
        ),
      ),
      floatingActionButtonLocation:
          FloatingActionButtonLocation.centerFloat,
      floatingActionButton: Padding(
        padding: const EdgeInsets.only(left: 16, right: 16, bottom: 8),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _frosted(
              radius: FwTokens.radiusPill,
              child: Container(
                padding: const EdgeInsets.all(4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _navTab('日历', 0),
                    _navTab('待办', 1),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 12),
            _frosted(
              radius: 28,
              child: GestureDetector(
                onTap: _create,
                child: const SizedBox(
                  width: 56,
                  height: 56,
                  child: Icon(Icons.add,
                      size: 30, color: FwTokens.ink),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 磨砂玻璃容器：对齐系统日历底部悬浮条。
  Widget _frosted({required double radius, required Widget child}) {
    final br = BorderRadius.circular(radius);
    return Container(
      decoration: BoxDecoration(
        borderRadius: br,
        boxShadow: const [
          BoxShadow(
            color: Color(0x14000000),
            blurRadius: 16,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: br,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: Container(
            color: Colors.white.withValues(alpha: 0.65),
            child: child,
          ),
        ),
      ),
    );
  }

  Widget _navTab(String label, int index) {
    final selected = _tab == index;
    return GestureDetector(
      onTap: () => setState(() => _tab = index),
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 28, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? Colors.white : Colors.transparent,
          borderRadius:
              BorderRadius.circular(FwTokens.radiusPill),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 15,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
            color: selected ? FwTokens.ink : FwTokens.ink55,
          ),
        ),
      ),
    );
  }
}
