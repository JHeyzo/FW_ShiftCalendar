import 'package:flutter/material.dart';

import '../data/app_store.dart';

class CalendarManagementPage extends StatelessWidget {
  const CalendarManagementPage({super.key, required this.store});
  final AppStore store;
  static const colors = [
    0xff0066ff,
    0xffff9f0a,
    0xff34a853,
    0xffa142f4,
    0xffe64664,
  ];

  Future<void> _run(
    BuildContext context,
    Future<void> Function() action,
  ) async {
    try {
      await action();
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('保存失败：$error')));
      }
    }
  }

  Future<void> _edit(BuildContext context, [CalendarGroup? group]) async {
    final controller = TextEditingController(text: group?.name ?? '');
    var color = group?.colorValue ?? colors.first;
    final result = await showDialog<CalendarGroup>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: Text(group == null ? '新建日历' : '编辑日历'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: controller,
                  autofocus: true,
                  maxLength: 40,
                  decoration: const InputDecoration(labelText: '日历名称'),
                  onChanged: (_) => update(() {}),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final value in colors)
                      ChoiceChip(
                        label: Icon(
                          Icons.circle,
                          color: Color(value),
                          size: 20,
                        ),
                        selected: value == color,
                        onSelected: (_) => update(() => color = value),
                        tooltip: '颜色 ${colors.indexOf(value) + 1}',
                      ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: controller.text.trim().isEmpty
                  ? null
                  : () => Navigator.pop(
                      context,
                      CalendarGroup(
                        id:
                            group?.id ??
                            'calendar-${DateTime.now().microsecondsSinceEpoch}',
                        name: controller.text.trim(),
                        colorValue: color,
                        visible: group?.visible ?? true,
                      ),
                    ),
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
    // The dialog's route may still be animating; its controller is released
    // after the route transition rather than while its TextField is attached.
    await Future<void>.delayed(const Duration(milliseconds: 300));
    controller.dispose();
    if (result != null && context.mounted) {
      await _run(context, () => store.saveCalendar(result));
    }
  }

  Future<void> _delete(BuildContext context, CalendarGroup group) async {
    final count = store.entries
        .where((entry) => entry.calendarId == group.id)
        .length;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除日历？'),
        content: Text('“${group.name}”及其中的 $count 条日程、待办将一并删除，无法撤销。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      await _run(context, () => store.deleteCalendar(group.id));
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: store,
    builder: (context, _) => Scaffold(
      appBar: AppBar(
        title: const Text('日历管理'),
        actions: [
          IconButton(
            tooltip: '新建日历',
            onPressed: () => _edit(context),
            icon: const Icon(Icons.add),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          const Padding(
            padding: EdgeInsets.all(12),
            child: Text('关闭可见性会隐藏日历和待办中的条目，不会删除数据，也不会关闭提醒。'),
          ),
          for (final group in store.calendars)
            Card(
              child: Column(
                children: [
                  SwitchListTile(
                    value: group.visible,
                    secondary: Icon(
                      Icons.calendar_month,
                      color: Color(group.colorValue),
                    ),
                    title: Text(group.name),
                    subtitle: Text(
                      '${store.entries.where((entry) => entry.calendarId == group.id).length} 条记录',
                    ),
                    onChanged: (value) => _run(
                      context,
                      () => store.saveCalendar(group.copyWith(visible: value)),
                    ),
                  ),
                  OverflowBar(
                    alignment: MainAxisAlignment.end,
                    children: [
                      TextButton.icon(
                        onPressed: () => _edit(context, group),
                        icon: const Icon(Icons.edit_outlined),
                        label: const Text('编辑'),
                      ),
                      TextButton.icon(
                        onPressed: store.calendars.length <= 1
                            ? null
                            : () => _delete(context, group),
                        icon: const Icon(Icons.delete_outline),
                        label: const Text('删除'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          if (store.calendars.length == 1)
            const Padding(
              padding: EdgeInsets.all(12),
              child: Text('至少保留一个日历。'),
            ),
        ],
      ),
    ),
  );
}
