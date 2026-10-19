import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';

import 'calendar/month_page.dart';
import 'data/app_store.dart';
import 'pages/calendar_management_page.dart';
import 'pages/search_page.dart';
import 'pages/settings_page.dart';
import 'services/reminder_service.dart';
import 'theme/fw_tokens.dart';
import 'todo/create_todo_page.dart';
import 'todo/todo_page.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const FengweiApp());
}

class FengweiApp extends StatefulWidget {
  const FengweiApp({
    super.key,
    this.store,
    this.loadStore = true,
    this.enableReminders = true,
  });
  final AppStore? store;
  final bool loadStore;
  final bool enableReminders;

  @override
  State<FengweiApp> createState() => _FengweiAppState();
}

class _FengweiAppState extends State<FengweiApp> with WidgetsBindingObserver {
  late final AppStore _store = widget.store ?? AppStore();
  final _homeKey = GlobalKey<_HomeShellState>();
  late final _reminders = ReminderService(onSelectDate: _openReminderDate);
  Timer? _midnight;
  bool _ready = false;
  Object? _error;

  void _openReminderDate(DateTime date) {
    _store.selectDate(date);
    _store.setView('月');
    _homeKey.currentState?.showCalendar();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    setState(() {
      _error = null;
    });
    try {
      if (widget.loadStore) await _store.load();
      if (!mounted) return;
      if (widget.enableReminders) {
        await _reminders.initialize();
        if (!mounted) return;
        _store.addListener(_syncReminders);
        _syncReminders();
      }
      _armMidnight();
      setState(() => _ready = true);
    } catch (error) {
      if (mounted) setState(() => _error = error);
    }
  }

  void _syncReminders() {
    if (widget.enableReminders) unawaited(_reminders.synchronize(_store));
  }

  void _armMidnight() {
    _midnight?.cancel();
    final now = DateTime.now();
    final next = DateTime(now.year, now.month, now.day + 1);
    _midnight = Timer(next.difference(now) + const Duration(seconds: 1), () {
      _store.refreshToday();
      _syncReminders();
      _armMidnight();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _ready) {
      _store.refreshToday();
      _syncReminders();
      _armMidnight();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _midnight?.cancel();
    _store.removeListener(_syncReminders);
    if (widget.store == null) _store.dispose();
    super.dispose();
  }

  ThemeData _theme(Brightness brightness) {
    final scheme = ColorScheme.fromSeed(
      seedColor: FwTokens.brand,
      brightness: brightness,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: brightness == Brightness.light
          ? FwTokens.pageBg
          : const Color(0xff14151a),
      cardTheme: CardThemeData(
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      appBarTheme: const AppBarTheme(centerTitle: false, elevation: 0),
      inputDecorationTheme: const InputDecorationTheme(
        border: OutlineInputBorder(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _store,
    builder: (context, _) => MaterialApp(
      title: '风味日历',
      debugShowCheckedModeBanner: false,
      theme: _theme(Brightness.light),
      darkTheme: _theme(Brightness.dark),
      themeMode: _store.themeMode,
      home: _error != null
          ? Scaffold(
              body: SafeArea(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.error_outline, size: 48),
                        const SizedBox(height: 16),
                        const Text('无法读取本地数据，原数据未被覆盖。'),
                        const SizedBox(height: 8),
                        Text('$_error'),
                        const SizedBox(height: 16),
                        FilledButton(
                          onPressed: _bootstrap,
                          child: const Text('重试'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            )
          : !_ready
          ? const Scaffold(body: Center(child: CircularProgressIndicator()))
          : HomeShell(key: _homeKey, store: _store, reminders: _reminders),
    ),
  );
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key, required this.store, required this.reminders});
  final AppStore store;
  final ReminderService reminders;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _tab = 0;
  AppStore get store => widget.store;

  void showCalendar() {
    if (mounted) setState(() => _tab = 0);
  }

  void _edit(CalendarEntry entry, DateTime occurrenceDate) {
    openEntryEditor(
      context,
      store,
      entry: entry,
      occurrenceDate: occurrenceDate,
    );
  }

  void _push(Widget page) {
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));
  }

  Future<void> _create({DateTime? date}) async {
    final kind = await showModalBottomSheet<EntryKind>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.event_outlined),
              title: const Text('新建日程'),
              onTap: () => Navigator.pop(context, EntryKind.event),
            ),
            ListTile(
              leading: const Icon(Icons.check_box_outlined),
              title: const Text('新建待办'),
              onTap: () => Navigator.pop(context, EntryKind.todo),
            ),
          ],
        ),
      ),
    );
    if (kind != null && mounted) {
      await openEntryEditor(
        context,
        store,
        kind: kind,
        date: date ?? store.selectedDate,
      );
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: IndexedStack(
        index: _tab,
        children: [
          MonthPage(
            store: store,
            onCreate: (date) => _create(date: date),
            onEdit: _edit,
            onSettings: () =>
                _push(SettingsPage(store: store, reminders: widget.reminders)),
            onManage: () => _push(CalendarManagementPage(store: store)),
            onSearch: () => _push(SearchPage(store: store)),
          ),
          TodoPage(store: store, onEdit: _edit),
        ],
      ),
    ),
    bottomNavigationBar: SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Flexible(
              child: _frosted(
                context,
                radius: 999,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: _navTab('日历', Icons.calendar_month_outlined, 0),
                    ),
                    Flexible(child: _navTab('待办', Icons.checklist, 1)),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 12),
            _frosted(
              context,
              radius: 28,
              child: IconButton(
                tooltip: '新建',
                onPressed: _create,
                icon: const Icon(Icons.add, size: 30),
                padding: const EdgeInsets.all(14),
              ),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _frosted(
    BuildContext context, {
    required double radius,
    required Widget child,
  }) {
    final br = BorderRadius.circular(radius);
    return ClipRRect(
      borderRadius: br,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Material(
          color: Theme.of(context).colorScheme.surfaceContainerHigh
              .withValues(alpha: 0.8),
          child: child,
        ),
      ),
    );
  }

  Widget _navTab(String label, IconData icon, int index) {
    final selected = _tab == index;
    return Semantics(
      selected: selected,
      button: true,
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: () => setState(() => _tab = index),
        child: Container(
          margin: const EdgeInsets.all(4),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            color: selected
                ? Theme.of(context).colorScheme.surface
                : Colors.transparent,
          ),
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 15,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              color: selected
                  ? Theme.of(context).colorScheme.primary
                  : Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }
}
