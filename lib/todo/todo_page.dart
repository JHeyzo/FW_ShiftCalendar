import 'package:flutter/material.dart';

import '../theme/fw_tokens.dart';

/// 待办页空壳：filter chips + 空态。数据层后续接。
class TodoPage extends StatefulWidget {
  const TodoPage({super.key});

  @override
  State<TodoPage> createState() => _TodoPageState();
}

class _TodoPageState extends State<TodoPage> {
  final _filters = ['全部', '进行中', '已逾期', '今天', '最近7天'];
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 12),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(
              horizontal: FwTokens.padPage),
          child: Row(
            children: [
              for (var i = 0; i < _filters.length; i++)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(_filters[i]),
                    selected: _index == i,
                    onSelected: (_) =>
                        setState(() => _index = i),
                    selectedColor: FwTokens.brand,
                    labelStyle: TextStyle(
                      fontSize: 14,
                      color: _index == i
                          ? Colors.white
                          : FwTokens.ink55,
                    ),
                    backgroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius:
                          BorderRadius.circular(FwTokens.radiusPill),
                      side: const BorderSide(
                          color: Color(0xFFE5E5EA)),
                    ),
                    showCheckmark: false,
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.inbox_outlined,
                    size: 72, color: FwTokens.ink30),
                const SizedBox(height: 12),
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 64),
                  child: const Text(
                    '暂无待办，去创建',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: FwTokens.spEmpty,
                        color: FwTokens.ink55),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
