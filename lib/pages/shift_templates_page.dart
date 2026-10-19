import 'package:flutter/material.dart';

import '../data/app_store.dart';
import '../services/shift_template_service.dart';

class ShiftTemplatesPage extends StatefulWidget {
  const ShiftTemplatesPage({super.key, required this.store});

  final AppStore store;

  @override
  State<ShiftTemplatesPage> createState() => _ShiftTemplatesPageState();
}

class _ShiftTemplatesPageState extends State<ShiftTemplatesPage> {
  final ShiftTemplateService _service = ShiftTemplateService();
  List<ShiftTemplate> _templates = <ShiftTemplate>[];
  bool _loading = true;
  bool _busy = false;
  String? _error;
  String? _selectedTemplateId;
  late DateTime _firstDate;
  late DateTime _lastDate;
  String? _calendarId;
  bool _includeRest = true;
  static const _colors = <int>[
    0xff0066ff,
    0xfff08900,
    0xff5476ff,
    0xffa142f4,
    0xff34a853,
    0xffe64664,
    0xff008577,
    0xff795548,
  ];

  @override
  void initState() {
    super.initState();
    final today = dateOnly(DateTime.now());
    _firstDate = today;
    _lastDate = DateTime(today.year, today.month, today.day + 27);
    _calendarId = widget.store.calendars.firstOrNull?.id;
    _load();
  }

  Future<void> _load() async {
    try {
      final templates = await _service.loadTemplates();
      if (!mounted) return;
      setState(() {
        _templates = templates;
        _selectedTemplateId ??= templates.firstOrNull?.id;
        _loading = false;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '读取模板失败：$error';
      });
    }
  }

  ShiftTemplate? get _selected {
    for (final template in _templates) {
      if (template.id == _selectedTemplateId) return template;
    }
    return null;
  }

  ShiftApplicationPreview? get _preview {
    final template = _selected;
    final calendarId = _calendarId;
    if (template == null || calendarId == null) return null;
    try {
      return _service.preview(
        store: widget.store,
        template: template,
        firstDate: _firstDate,
        lastDate: _lastDate,
        calendarId: calendarId,
        generateRestDays: _includeRest,
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> _editTemplate([ShiftTemplate? original]) async {
    final changed = await showDialog<ShiftTemplate>(
      context: context,
      builder: (_) => _TemplateEditorDialog(initial: original, colors: _colors),
    );
    if (changed == null || !mounted) return;
    setState(() => _busy = true);
    try {
      await _service.saveTemplate(changed);
      final templates = await _service.loadTemplates();
      if (!mounted) return;
      setState(() {
        _templates = templates;
        _selectedTemplateId = changed.id;
        _error = null;
      });
      _message('模板已保存。不会自动修改已经生成的排班。');
    } catch (error) {
      if (mounted) _message('保存模板失败：$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _deleteTemplate(ShiftTemplate template) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('删除循环模板？'),
        content: Text('删除「${template.name}」只会删除模板，不会删除已生成的日程。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('删除模板'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await _service.deleteTemplate(template.id);
      final templates = await _service.loadTemplates();
      if (!mounted) return;
      setState(() {
        _templates = templates;
        _selectedTemplateId = templates.firstOrNull?.id;
      });
      _message('模板已删除；已有排班保留不变。');
    } catch (error) {
      if (mounted) _message('删除模板失败：$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _chooseDate({required bool first}) async {
    final current = first ? _firstDate : _lastDate;
    final value = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: DateTime(1900),
      lastDate: DateTime(2100, 12, 31),
      helpText: first ? '选择循环开始日期（首日从第 1 步开始）' : '选择循环结束日期',
    );
    if (value == null || !mounted) return;
    setState(() {
      if (first) {
        _firstDate = dateOnly(value);
        if (_lastDate.isBefore(_firstDate)) _lastDate = _firstDate;
      } else {
        _lastDate = dateOnly(value);
      }
    });
  }

  Future<void> _apply() async {
    if (_busy) return;
    final template = _selected;
    final calendarId = _calendarId;
    if (template == null || calendarId == null) {
      _message('请先选择模板和目标日历。');
      return;
    }
    ShiftApplicationPreview preview;
    try {
      preview = _service.preview(
        store: widget.store,
        template: template,
        firstDate: _firstDate,
        lastDate: _lastDate,
        calendarId: calendarId,
        generateRestDays: _includeRest,
      );
    } catch (error) {
      _message('无法生成预览：$error');
      return;
    }
    setState(() => _busy = true);
    final policy = await showDialog<ShiftConflictPolicy>(
      context: context,
      builder: (dialogContext) => _ApplyConfirmationDialog(
        template: template,
        preview: preview,
        firstDate: _firstDate,
        lastDate: _lastDate,
      ),
    );
    if (!mounted) return;
    if (policy == null) {
      setState(() => _busy = false);
      return;
    }
    try {
      final result = await _service.apply(
        store: widget.store,
        template: template,
        firstDate: _firstDate,
        lastDate: _lastDate,
        calendarId: calendarId,
        generateRestDays: _includeRest,
        conflictPolicy: policy,
      );
      if (!mounted) return;
      _message(
        '已写入 ${result.createdOrUpdated} 项排班'
        '${result.skippedConflicts > 0 ? '，跳过 ${result.skippedConflicts} 项冲突' : ''}。',
      );
    } catch (error) {
      if (mounted) _message('应用失败，日程未能保存：$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _message(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  String _dateText(DateTime date) =>
      '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('循环班次模板'),
        actions: [
          IconButton(
            tooltip: '新建循环模板',
            onPressed: _busy ? null : () => _editTemplate(),
            icon: const Icon(Icons.add),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
              children: [
                if (_error != null) ...[
                  _NoticeCard(message: _error!, isError: true),
                  const SizedBox(height: 12),
                ],
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: _busy ? null : () => _editTemplate(),
                    icon: const Icon(Icons.add),
                    label: const Text('新建模板'),
                  ),
                ),
                Text('我的模板', style: theme.textTheme.titleLarge),
                const SizedBox(height: 4),
                const Text('循环从所选开始日期的第 1 步开始，逐日循环。'),
                const SizedBox(height: 10),
                if (_templates.isEmpty)
                  const _NoticeCard(message: '还没有模板，请新建一个循环班次模板。')
                else
                  for (final template in _templates) ...[
                    _TemplateCard(
                      template: template,
                      selected: template.id == _selectedTemplateId,
                      enabled: !_busy,
                      onSelect: () =>
                          setState(() => _selectedTemplateId = template.id),
                      onEdit: () => _editTemplate(template),
                      onDelete: () => _deleteTemplate(template),
                    ),
                    const SizedBox(height: 8),
                  ],
                const SizedBox(height: 14),
                Text('批量生成排班', style: theme.textTheme.titleLarge),
                const SizedBox(height: 10),
                _Panel(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      DropdownButtonFormField<String>(
                        initialValue: _calendarId,
                        isExpanded: true,
                        decoration: const InputDecoration(labelText: '目标日历'),
                        items: [
                          for (final calendar in widget.store.calendars)
                            DropdownMenuItem(
                              value: calendar.id,
                              child: Text(
                                calendar.name,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                        ],
                        onChanged: _busy
                            ? null
                            : (value) => setState(() => _calendarId = value),
                      ),
                      const SizedBox(height: 12),
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final compact = constraints.maxWidth < 400;
                          final children = [
                            _DateButton(
                              label: '开始日期 · 从第 1 步开始',
                              value: _dateText(_firstDate),
                              onPressed: _busy
                                  ? null
                                  : () => _chooseDate(first: true),
                            ),
                            _DateButton(
                              label: '结束日期（包含当天）',
                              value: _dateText(_lastDate),
                              onPressed: _busy
                                  ? null
                                  : () => _chooseDate(first: false),
                            ),
                          ];
                          return compact
                              ? Column(
                                  children: [
                                    children[0],
                                    const SizedBox(height: 8),
                                    children[1],
                                  ],
                                )
                              : Row(
                                  children: [
                                    Expanded(child: children[0]),
                                    const SizedBox(width: 8),
                                    Expanded(child: children[1]),
                                  ],
                                );
                        },
                      ),
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('休息日也生成全天日程'),
                        subtitle: const Text('关闭后只生成工作班次。'),
                        value: _includeRest,
                        onChanged: _busy
                            ? null
                            : (value) =>
                                  setState(() => _includeRest = value ?? true),
                      ),
                      if (_lastDate.isBefore(_firstDate) ||
                          shiftCalendarDaysBetween(_firstDate, _lastDate) >=
                              366)
                        const _NoticeCard(
                          message: '日期范围须为 1–366 天；结束日期不能早于开始日期。',
                          isError: true,
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                _PreviewCard(preview: _preview),
                const SizedBox(height: 10),
                const _NoticeCard(
                  message: '重新应用会覆盖同一模板、同一日期的排班，包括对该排班做过的手工修改；其他日程不会被覆盖或自动删除。模板变更也不会自动更改已生成的排班，生成后请用通用日程编辑页手动调班。',
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed:
                      _busy ||
                          _selected == null ||
                          _calendarId == null ||
                          _preview == null
                      ? null
                      : _apply,
                  icon: _busy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.event_available_outlined),
                  label: Text(_busy ? '正在保存…' : '预览并应用排班'),
                ),
                if (_busy) ...[
                  const SizedBox(height: 10),
                  const LinearProgressIndicator(),
                ],
              ],
            ),
    );
  }
}

class _TemplateCard extends StatelessWidget {
  const _TemplateCard({
    required this.template,
    required this.selected,
    required this.enabled,
    required this.onSelect,
    required this.onEdit,
    required this.onDelete,
  });

  final ShiftTemplate template;
  final bool selected;
  final bool enabled;
  final VoidCallback onSelect;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) => Card(
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: enabled ? onSelect : null,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  selected
                      ? Icons.radio_button_checked
                      : Icons.radio_button_off,
                  color: selected
                      ? Theme.of(context).colorScheme.primary
                      : null,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    template.name,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                IconButton(
                  tooltip: '编辑模板',
                  onPressed: enabled ? onEdit : null,
                  icon: const Icon(Icons.edit_outlined),
                ),
                IconButton(
                  tooltip: '删除模板',
                  onPressed: enabled ? onDelete : null,
                  icon: const Icon(Icons.delete_outline),
                ),
              ],
            ),
            const SizedBox(height: 5),
            Wrap(
              spacing: 6,
              runSpacing: 5,
              children: [
                for (var i = 0; i < template.steps.length; i++)
                  _StepChip(step: template.steps[i], index: i),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

class _StepChip extends StatelessWidget {
  const _StepChip({required this.step, required this.index});
  final ShiftStep step;
  final int index;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
    decoration: BoxDecoration(
      color: Color(step.colorValue).withValues(alpha: .12),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: Color(step.colorValue).withValues(alpha: .45)),
    ),
    child: Text(
      '${index + 1}. ${step.name}${step.isRest ? ' · 休息' : ''}',
      style: Theme.of(context).textTheme.labelMedium,
    ),
  );
}

class _TemplateEditorDialog extends StatefulWidget {
  const _TemplateEditorDialog({required this.initial, required this.colors});
  final ShiftTemplate? initial;
  final List<int> colors;

  @override
  State<_TemplateEditorDialog> createState() => _TemplateEditorDialogState();
}

class _TemplateEditorDialogState extends State<_TemplateEditorDialog> {
  late final TextEditingController _name;
  late String _id;
  late List<ShiftStep> _steps;
  String? _error;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    _name = TextEditingController(text: initial?.name ?? '');
    _id =
        initial?.id ??
        'shift-template-${DateTime.now().microsecondsSinceEpoch}';
    _steps = initial == null
        ? <ShiftStep>[
            const ShiftStep(
              name: '早班',
              colorValue: 0xfff08900,
              isRest: false,
              startMinute: 8 * 60,
              endMinute: 16 * 60,
            ),
          ]
        : List<ShiftStep>.of(initial.steps);
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  String _clock(int minute) =>
      '${(minute ~/ 60).toString().padLeft(2, '0')}:${(minute % 60).toString().padLeft(2, '0')}';

  Future<void> _pickTime(int index, bool start) async {
    final step = _steps[index];
    final minute = start ? step.startMinute : step.endMinute;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: minute ~/ 60, minute: minute % 60),
    );
    if (time == null || !mounted) return;
    setState(() {
      _steps[index] = step.copyWith(
        startMinute: start ? time.hour * 60 + time.minute : null,
        endMinute: start ? null : time.hour * 60 + time.minute,
      );
    });
  }

  void _save() {
    final template = ShiftTemplate(
      id: _id,
      name: _name.text.trim(),
      steps: _steps,
      isBuiltIn: widget.initial?.isBuiltIn ?? false,
    );
    try {
      template.validate();
      Navigator.pop(context, template);
    } catch (error) {
      setState(() => _error = '$error');
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.initial == null ? '新建循环模板' : '编辑循环模板'),
    content: SizedBox(
      width: 520,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _name,
              maxLength: 40,
              decoration: const InputDecoration(labelText: '模板名称'),
            ),
            const SizedBox(height: 8),
            Text(
              '循环步骤 · ${_steps.length}/31 天',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 4),
            for (var index = 0; index < _steps.length; index++)
              _stepEditor(index),
            if (_steps.length < 31)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => setState(
                    () => _steps.add(
                      ShiftStep(
                        name: '新班次',
                        colorValue: widget.colors.first,
                        isRest: false,
                      ),
                    ),
                  ),
                  icon: const Icon(Icons.add),
                  label: const Text('添加一天'),
                ),
              ),
            if (_error != null)
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      FilledButton(onPressed: _save, child: const Text('保存模板')),
    ],
  );

  Widget _stepEditor(int index) {
    final step = _steps[index];
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 5),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 13,
                  backgroundColor: Color(step.colorValue),
                  child: Text(
                    '${index + 1}',
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextFormField(
                    key: ValueKey('step-name-$index-${step.name}'),
                    initialValue: step.name,
                    maxLength: 24,
                    decoration: const InputDecoration(
                      labelText: '班次名称',
                      counterText: '',
                    ),
                    onChanged: (value) =>
                        _steps[index] = _steps[index].copyWith(name: value),
                  ),
                ),
                IconButton(
                  tooltip: '上移',
                  onPressed: index == 0
                      ? null
                      : () => setState(() {
                          final item = _steps.removeAt(index);
                          _steps.insert(index - 1, item);
                        }),
                  icon: const Icon(Icons.arrow_upward, size: 20),
                ),
                IconButton(
                  tooltip: '下移',
                  onPressed: index == _steps.length - 1
                      ? null
                      : () => setState(() {
                          final item = _steps.removeAt(index);
                          _steps.insert(index + 1, item);
                        }),
                  icon: const Icon(Icons.arrow_downward, size: 20),
                ),
                IconButton(
                  tooltip: '删除步骤',
                  onPressed: _steps.length <= 1
                      ? null
                      : () => setState(() => _steps.removeAt(index)),
                  icon: const Icon(Icons.delete_outline, size: 20),
                ),
              ],
            ),
            Wrap(
              spacing: 2,
              children: [
                for (final color in widget.colors)
                  InkWell(
                    onTap: () => setState(
                      () => _steps[index] = _steps[index].copyWith(
                        colorValue: color,
                      ),
                    ),
                    customBorder: const CircleBorder(),
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: CircleAvatar(
                        radius: 11,
                        backgroundColor: Color(color),
                        child: color == step.colorValue
                            ? const Icon(
                                Icons.check,
                                size: 13,
                                color: Colors.white,
                              )
                            : null,
                      ),
                    ),
                  ),
              ],
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('休息日'),
              value: step.isRest,
              onChanged: (value) => setState(
                () => _steps[index] = _steps[index].copyWith(isRest: value),
              ),
            ),
            if (!step.isRest) ...[
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  OutlinedButton.icon(
                    onPressed: () => _pickTime(index, true),
                    icon: const Icon(Icons.login, size: 18),
                    label: Text('开始 ${_clock(step.startMinute)}'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => _pickTime(index, false),
                    icon: const Icon(Icons.logout, size: 18),
                    label: Text('结束 ${_clock(step.endMinute)}'),
                  ),
                ],
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('跨夜结束（结束日期为次日）'),
                value: step.overnight,
                onChanged: (value) => setState(
                  () => _steps[index] = _steps[index].copyWith(
                    overnight: value ?? false,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ApplyConfirmationDialog extends StatefulWidget {
  const _ApplyConfirmationDialog({
    required this.template,
    required this.preview,
    required this.firstDate,
    required this.lastDate,
  });
  final ShiftTemplate template;
  final ShiftApplicationPreview preview;
  final DateTime firstDate;
  final DateTime lastDate;

  @override
  State<_ApplyConfirmationDialog> createState() =>
      _ApplyConfirmationDialogState();
}

class _ApplyConfirmationDialogState extends State<_ApplyConfirmationDialog> {
  ShiftConflictPolicy _policy = ShiftConflictPolicy.skip;

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('确认生成排班'),
    content: SizedBox(
      width: 460,
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '模板「${widget.template.name}」：${widget.preview.totalDays} 天，工作 ${widget.preview.workDays} 天，休息 ${widget.preview.restDays} 天，生成 ${widget.preview.entriesToGenerate} 项。',
            ),
            const SizedBox(height: 8),
            Text(
              '${_formatDate(widget.firstDate)} 至 ${_formatDate(widget.lastDate)}（首日从第 1 步开始）',
            ),
            const SizedBox(height: 12),
            if (widget.preview.conflictCount > 0) ...[
              Text('检测到与其他日程重叠的排班：${widget.preview.conflictCount} 项。选择如何处理：'),
              RadioGroup<ShiftConflictPolicy>(
                groupValue: _policy,
                onChanged: (value) {
                  if (value != null) setState(() => _policy = value);
                },
                child: Column(
                  children: [
                    RadioListTile<ShiftConflictPolicy>(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('跳过冲突项'),
                      subtitle: const Text('保留现有日程，不写入与其重叠的排班。'),
                      value: ShiftConflictPolicy.skip,
                    ),
                    RadioListTile<ShiftConflictPolicy>(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('仍然保留全部排班'),
                      subtitle: const Text('只写入 shift 模板日程，不覆盖其他日程。'),
                      value: ShiftConflictPolicy.keep,
                    ),
                  ],
                ),
              ),
            ] else
              const Text('未发现与现有日程时间重叠的班次。'),
            const SizedBox(height: 12),
            const _NoticeCard(
              isError: true,
              message: '重新应用会覆盖同模板同日期的已有排班，包括其中的手工修改。模板改动不会自动应用到已生成排班。',
            ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context, _policy),
        child: const Text('确认应用'),
      ),
    ],
  );
}

class _PreviewCard extends StatelessWidget {
  const _PreviewCard({required this.preview});
  final ShiftApplicationPreview? preview;

  @override
  Widget build(BuildContext context) {
    if (preview == null) {
      return const _NoticeCard(
        isError: true,
        message: '预览不可用：请检查日期范围、模板及目标日历。',
      );
    }
    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('生成预览', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _CountBadge(label: '总天数', value: preview!.totalDays),
              _CountBadge(label: '工作班次', value: preview!.workDays),
              _CountBadge(label: '休息日', value: preview!.restDays),
              _CountBadge(
                label: '时间冲突',
                value: preview!.conflictCount,
                alert: preview!.conflictCount > 0,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CountBadge extends StatelessWidget {
  const _CountBadge({
    required this.label,
    required this.value,
    this.alert = false,
  });
  final String label;
  final int value;
  final bool alert;

  @override
  Widget build(BuildContext context) => Chip(
    avatar: Icon(
      alert ? Icons.warning_amber_rounded : Icons.check_circle_outline,
      size: 18,
      color: alert ? Theme.of(context).colorScheme.error : null,
    ),
    label: Text('$label $value'),
  );
}

class _DateButton extends StatelessWidget {
  const _DateButton({
    required this.label,
    required this.value,
    required this.onPressed,
  });
  final String label;
  final String value;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => OutlinedButton(
    onPressed: onPressed,
    style: OutlinedButton.styleFrom(
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.all(12),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelMedium),
        const SizedBox(height: 3),
        Text(value),
      ],
    ),
  );
}

class _Panel extends StatelessWidget {
  const _Panel({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(padding: const EdgeInsets.all(14), child: child),
  );
}

class _NoticeCard extends StatelessWidget {
  const _NoticeCard({required this.message, this.isError = false});
  final String message;
  final bool isError;

  @override
  Widget build(BuildContext context) => Card(
    color: isError ? Theme.of(context).colorScheme.errorContainer : null,
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Text(message, style: Theme.of(context).textTheme.bodyMedium),
    ),
  );
}

String _formatDate(DateTime date) =>
    '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
