import 'package:flutter/material.dart';

import 'calendar/month_page.dart';
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
          children: const [MonthPage(), TodoPage()],
        ),
      ),
      floatingActionButtonLocation:
          FloatingActionButtonLocation.centerFloat,
      floatingActionButton: Padding(
        padding: const EdgeInsets.only(left: 16, right: 16, bottom: 8),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius:
                    BorderRadius.circular(FwTokens.radiusPill),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x14000000),
                    blurRadius: 16,
                    offset: Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _navTab('日历', 0),
                  _navTab('待办', 1),
                ],
              ),
            ),
            const SizedBox(width: 12),
            GestureDetector(
              onTap: _create,
              child: Container(
                width: 56,
                height: 56,
                decoration: const BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Color(0x14000000),
                      blurRadius: 16,
                      offset: Offset(0, 4),
                    ),
                  ],
                ),
                child: const Icon(Icons.add,
                    size: 30, color: FwTokens.ink),
              ),
            ),
          ],
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
          color: selected
              ? const Color(0xFFE9EDF3)
              : Colors.transparent,
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
