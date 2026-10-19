import 'package:flutter/material.dart';

import '../theme/fw_tokens.dart';

/// 新建待办页：对齐原版 create_task_fragment。
/// 白色圆角 12dp 大卡，24sp 输入框（300字上限），
/// 时间·星标·颜色三件套，右下完成按钮。
/// 空壳阶段：保存只做占位，数据层后续接。
class CreateTodoPage extends StatefulWidget {
  const CreateTodoPage({super.key});

  @override
  State<CreateTodoPage> createState() =>
      _CreateTodoPageState();
}

class _CreateTodoPageState
    extends State<CreateTodoPage> {
  final _controller = TextEditingController();
  bool _starred = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: FwTokens.pageBg,
      appBar: AppBar(
        backgroundColor: FwTokens.pageBg,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.chevron_left,
              size: 28, color: FwTokens.ink),
          onPressed: () =>
              Navigator.of(context).pop(),
        ),
        title: const Text('新建待办',
            style: FwTokens.monthTitle),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Container(
          decoration: BoxDecoration(
            color: FwTokens.cardBg,
            borderRadius: BorderRadius.circular(
                FwTokens.radiusCreateCard),
            boxShadow: const [
              BoxShadow(
                color: Color(0x14000000),
                blurRadius: 10,
                offset: Offset(0, 2),
              ),
            ],
          ),
          padding: const EdgeInsets.fromLTRB(
              16, 16, 16, 12),
          child: Column(
            crossAxisAlignment:
                CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _controller,
                style: FwTokens.createInput,
                maxLength:
                    FwTokens.createInputMaxLength,
                maxLines: null,
                decoration: const InputDecoration(
                  hintText: '新建待办',
                  hintStyle: TextStyle(
                      color: FwTokens.ink30),
                  border: InputBorder.none,
                  counterStyle: TextStyle(
                      fontSize: 12,
                      color: FwTokens.ink30),
                ),
                onChanged: (_) =>
                    setState(() {}),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  _action(Icons.access_time,
                      () {}), // 时间：占位
                  _action(
                      _starred
                          ? Icons.star
                          : Icons.star_border,
                      () => setState(() =>
                          _starred = !_starred),
                      active: _starred),
                  _action(Icons.color_lens_outlined,
                      () {}), // 颜色：占位
                  const Spacer(),
                  _doneButton(),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _action(IconData icon, VoidCallback onTap,
      {bool active = false}) {
    return InkWell(
      onTap: onTap,
      customBorder: const CircleBorder(),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Icon(
          icon,
          size: 28,
          color:
              active ? FwTokens.brand : FwTokens.ink55,
        ),
      ),
    );
  }

  Widget _doneButton() {
    final enabled =
        _controller.text.trim().isNotEmpty;
    return GestureDetector(
      onTap: enabled
          ? () => Navigator.of(context).pop()
          : null, // 保存：数据层后续接
      child: Container(
        padding: const EdgeInsets.symmetric(
            horizontal: 20, vertical: 10),
        decoration: BoxDecoration(
          color: enabled
              ? FwTokens.brand
              : const Color(0x0A000000),
          borderRadius: BorderRadius.circular(
              FwTokens.radiusDoneBtn),
        ),
        child: Text(
          '完成',
          style: TextStyle(
            fontSize: 14,
            color: enabled
                ? Colors.white
                : FwTokens.ink55,
          ),
        ),
      ),
    );
  }
}
