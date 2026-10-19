import 'package:flutter/material.dart';

import '../data/app_store.dart';
import '../services/reminder_service.dart';
import 'shift_templates_page.dart';
import 'system_calendar_page.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key, required this.store, required this.reminders});
  final AppStore store;
  final ReminderService reminders;
  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool _busy = false;
  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('操作失败：$error')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.store,
    builder: (context, _) => Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('外观', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          DropdownButtonFormField<ThemeMode>(
            initialValue: widget.store.themeMode,
            decoration: const InputDecoration(labelText: '主题'),
            isExpanded: true,
            items: const [
              DropdownMenuItem(value: ThemeMode.system, child: Text('跟随系统')),
              DropdownMenuItem(value: ThemeMode.light, child: Text('浅色')),
              DropdownMenuItem(value: ThemeMode.dark, child: Text('深色')),
            ],
            onChanged: _busy
                ? null
                : (value) =>
                      _run(() => widget.store.setSettings(themeMode: value)),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('显示农历与节日'),
            value: widget.store.showLunar,
            onChanged: _busy
                ? null
                : (value) =>
                      _run(() => widget.store.setSettings(showLunar: value)),
          ),
          const Divider(height: 32),
          Text('提醒', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          const Text(
            '在日程或待办中设置提前提醒。Android 使用系统非精确通知，可能受省电策略影响而延迟。隐藏日历不会关闭提醒。',
          ),
          const SizedBox(height: 8),
          Text(widget.reminders.statusMessage ?? '系统提醒状态尚未检查。'),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _busy
                ? null
                : () => _run(() async {
                    final allowed = await widget.reminders.requestPermission();
                    await widget.reminders.synchronize(widget.store);
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            allowed
                                ? '通知权限已开启，已重新检查提醒安排。'
                                : widget.reminders.statusMessage ??
                                      '通知权限未开启，请在系统设置中允许通知。',
                          ),
                        ),
                      );
                    }
                  }),
            icon: const Icon(Icons.notifications_outlined),
            label: const Text('开启通知并刷新提醒'),
          ),
          const SizedBox(height: 8),
          const Text(
            '重复提醒按未来 30 天安排，最多保留最近 64 条；打开应用、保存修改或跨日时会补排。长期不打开应用可能缺少后续提醒。',
          ),
          const Divider(height: 32),
          Text('数据', style: Theme.of(context).textTheme.titleMedium),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.repeat),
            title: const Text('循环班次模板'),
            subtitle: const Text('编辑轮班周期，预览并批量生成排班'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => ShiftTemplatesPage(store: widget.store),
              ),
            ),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.sync),
            title: const Text('系统日历导入／导出'),
            subtitle: const Text('Android 手动同步，授权后选择日历与范围'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => SystemCalendarPage(store: widget.store),
              ),
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            '日程、待办、日历和外观设置保存在本机。不提供账号云同步；系统日历只在你授权并点击导入／导出时读写，不在后台实时同步。卸载应用或清除数据会删除本地记录。',
          ),
          const SizedBox(height: 12),
          const Text(
            '字体大小跟随系统，页面支持滚动和窗口尺寸变化。循环模板生成的排班可像普通日程一样手动调班；修改模板不会自动改动已生成的排班。提醒是通知，不是系统闹钟。',
          ),
          if (_busy)
            const Padding(
              padding: EdgeInsets.all(16),
              child: LinearProgressIndicator(),
            ),
        ],
      ),
    ),
  );
}
