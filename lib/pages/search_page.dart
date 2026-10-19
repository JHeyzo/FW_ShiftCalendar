import 'package:flutter/material.dart';

import '../data/app_store.dart';
import '../todo/create_todo_page.dart';

class SearchPage extends StatefulWidget {
  const SearchPage({super.key, required this.store});
  final AppStore store;
  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final _query = TextEditingController();
  EntryKind? _kind;
  bool _includeHidden = false;
  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.store,
    builder: (context, _) {
      final store = widget.store;
      final query = _query.text.trim().toLowerCase();
      final groups = {for (final group in store.calendars) group.id: group};
      final results =
          store.entries
              .where(
                (entry) =>
                    (_kind == null || entry.kind == _kind) &&
                    (_includeHidden ||
                        (groups[entry.calendarId]?.visible ?? false)) &&
                    '${entry.title}\n${entry.notes}\n${groups[entry.calendarId]?.name ?? ''}'
                        .toLowerCase()
                        .contains(query),
              )
              .toList()
            ..sort((a, b) => a.start.compareTo(b.start));
      return Scaffold(
        appBar: AppBar(title: const Text('搜索')),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: TextField(
                controller: _query,
                autofocus: true,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: '标题、备注或日历名称',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: IconButton(
                    tooltip: '清空搜索',
                    onPressed: () {
                      _query.clear();
                      setState(() {});
                    },
                    icon: const Icon(Icons.clear),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  ChoiceChip(
                    label: const Text('全部'),
                    selected: _kind == null,
                    onSelected: (_) => setState(() => _kind = null),
                  ),
                  ChoiceChip(
                    label: const Text('日程'),
                    selected: _kind == EntryKind.event,
                    onSelected: (_) => setState(() => _kind = EntryKind.event),
                  ),
                  ChoiceChip(
                    label: const Text('待办'),
                    selected: _kind == EntryKind.todo,
                    onSelected: (_) => setState(() => _kind = EntryKind.todo),
                  ),
                  FilterChip(
                    label: const Text('含隐藏日历'),
                    selected: _includeHidden,
                    onSelected: (value) =>
                        setState(() => _includeHidden = value),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('${results.length} 条记录 · 重复系列只显示一次'),
              ),
            ),
            Expanded(
              child: results.isEmpty
                  ? const Center(child: Text('未找到匹配的日程或待办'))
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 20),
                      itemCount: results.length,
                      itemBuilder: (context, index) {
                        final entry = results[index];
                        return Card(
                          child: ListTile(
                            leading: Icon(
                              entry.kind == EntryKind.todo
                                  ? Icons.check_box_outlined
                                  : Icons.event_outlined,
                              color: Color(entry.colorValue),
                            ),
                            title: Text(entry.title),
                            subtitle: Text(
                              '${dayKey(entry.start)} · ${groups[entry.calendarId]?.name ?? ''}'
                              '${entry.repeat != RepeatRule.none ? ' · 重复' : ''}'
                              '${entry.notes.isNotEmpty ? '\n${entry.notes}' : ''}',
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                            ),
                            onTap: () => openEntryEditor(
                              context,
                              store,
                              entry: entry,
                              occurrenceDate: entry.start,
                            ),
                            trailing: IconButton(
                              tooltip: '定位到日期',
                              icon: const Icon(Icons.my_location),
                              onPressed: () {
                                store.selectDate(entry.start);
                                store.setView('月');
                                Navigator.pop(context);
                              },
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      );
    },
  );
}
