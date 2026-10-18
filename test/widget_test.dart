// 风味日历空壳阶段的冒烟测试：应用能启动、日历页正常渲染。
import 'package:flutter_test/flutter_test.dart';

import 'package:fwcal/main.dart';

void main() {
  testWidgets('app boots to month page', (WidgetTester tester) async {
    await tester.pumpWidget(const FengweiApp());
    await tester.pumpAndSettle();

    // 底部导航与星期标题存在
    expect(find.text('日历'), findsOneWidget);
    expect(find.text('待办'), findsOneWidget);
    expect(find.text('一'), findsOneWidget);
    expect(find.text('日'), findsOneWidget);
  });
}
