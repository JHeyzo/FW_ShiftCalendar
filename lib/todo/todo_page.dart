import 'package:flutter/material.dart';

import '../theme/fw_tokens.dart';

/// 待办页：对齐 ColorOS 系统日历（filter chips + 卡片列表 + 空态）。
/// 空壳阶段：无数据层，展示空态；卡片组件已按原版数值备好。
class TodoPage extends StatefulWidget {
  const TodoPage({super.key});

  @override
  State<TodoPage> createState() => _TodoPageState();
}

class _TodoPageState extends State<TodoPage> {
  // 原版 TaskFilter：全部/进行中/已过期/今天/最近7天（+隐藏的高优先级）
  final _filters = const ['全部', '进行中', '已过期', '今天', '最近7天'];
  int _selected = 0;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _chips(),
        Expanded(child: _empty()),
      ],
    );
  }

  Widget _chips() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      child: Row(
        children: [
          for (var i = 0; i < _filters.length; i++)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text(_filters[i]),
                selected: _selected == i,
                onSelected: (_) =>
                    setState(() => _selected = i),
                selectedColor: FwTokens.brandBg,
                backgroundColor: FwTokens.cardBg,
                labelStyle: TextStyle(
                  fontSize: 14,
                  color: _selected == i
                      ? FwTokens.brand
                      : FwTokens.ink,
                ),
                shape: const StadiumBorder(
                  side: BorderSide(color: Color(0x1F000000)),
                ),
                showCheckmark: false,
              ),
            ),
        ],
      ),
    );
  }

  /// 空态：14sp/55%黑/左右64dp/纵向偏上（原版 empty_layout）。
  Widget _empty() {
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(
                minHeight: constraints.maxHeight),
            child: Column(
              children: [
                SizedBox(
                    height:
                        constraints.maxHeight * 0.4 -
                            60),
                const Icon(
                  Icons.inbox_outlined,
                  size: 72,
                  color: FwTokens.ink30,
                ),
                const SizedBox(height: 16),
                const Padding(
                  padding: EdgeInsets.symmetric(
                      horizontal: 64),
                  child: Text(
                    '暂无待办，去创建',
                    textAlign: TextAlign.center,
                    style: FwTokens.sectionHead,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// 待办卡片：对齐原版 item_todo_layout。
/// 圆角 16dp，间距 8dp，勾选热区 64×56dp，
/// 标题 16sp/w700/最多3行，时间 12sp/w500/55%黑。
class TodoCard extends StatelessWidget {
  const TodoCard({
    super.key,
    required this.title,
    this.time,
    this.overdue = false,
    this.done = false,
    this.onToggle,
    this.onTap,
  });

  final String title;
  final String? time;
  final bool overdue;
  final bool done;
  final VoidCallback? onToggle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(
          vertical: FwTokens.gapCardV),
      decoration: BoxDecoration(
        color: FwTokens.cardBg,
        borderRadius:
            BorderRadius.circular(FwTokens.radiusCard),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(
            FwTokens.radiusCard),
        child: Row(
          crossAxisAlignment:
              CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: FwTokens.todoCheckHitW,
              height: FwTokens.todoCheckHitH,
              child: Center(
                child: InkWell(
                  onTap: onToggle,
                  customBorder:
                      const CircleBorder(),
                  child: Padding(
                    padding:
                        const EdgeInsets.all(8),
                    child: Icon(
                      done
                          ? Icons.check_circle
                          : Icons
                              .radio_button_unchecked,
                      size: 24,
                      color: done
                          ? FwTokens.brand
                          : FwTokens.ink30,
                    ),
                  ),
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  0,
                  FwTokens.padCardV,
                  FwTokens.padCardR,
                  FwTokens.padCardV,
                ),
                child: Column(
                  crossAxisAlignment:
                      CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 3,
                      overflow:
                          TextOverflow.ellipsis,
                      style: FwTokens.todoTitle
                          .copyWith(
                        decoration: done
                            ? TextDecoration
                                .lineThrough
                            : null,
                      ),
                    ),
                    if (time != null) ...[
                      const SizedBox(height: 3),
                      Text(time!,
                          style:
                              FwTokens.todoTime),
                    ],
                    if (overdue) ...[
                      const SizedBox(height: 3),
                      const Text('已过期',
                          style:
                              FwTokens.todoTime),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
