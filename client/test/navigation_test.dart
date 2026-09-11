import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sayanything/api.dart';
import 'package:sayanything/app.dart';
import 'package:sayanything/design.dart';
import 'policy_fixture.dart';

class NavigationApi extends Api {
  final requests = <String>[];
  NavigationApi() : super(serverPolicy: testPolicy()) {
    user = {
      'id': 'u',
      'alias': '同学',
      'campus': '测试校园',
      'gender': 'undisclosed',
      'allowDM': true,
    };
  }
  @override
  Future<dynamic> call(String method, String path, [Data? data]) async {
    requests.add('$method $path');
    if (path == '/nearby') {
      return {'enabled': false, 'revision': 0, 'radiusKm': 5, 'items': []};
    }
    return <Data>[];
  }
}

void main() {
  testWidgets('four primary tabs and brand settings route stay connected', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final api = NavigationApi();
    await tester.pumpWidget(
      MaterialApp(
        theme: appTheme(true),
        home: HomeShell(api: api),
      ),
    );
    await tester.pumpAndSettle();
    for (final label in ['动态', '聊天', '附近', '我']) {
      expect(find.text(label), findsOneWidget);
    }
    await tester.tap(find.text('聊天'));
    await tester.pumpAndSettle();
    expect(find.text('聊天记录'), findsOneWidget);
    await tester.tap(find.text('附近'));
    await tester.pumpAndSettle();
    expect(find.text('附近的人'), findsOneWidget);
    expect(find.byTooltip('返回'), findsNothing);
    expect(api.requests.where((r) => r.startsWith('PUT')), isEmpty);
    await tester.tap(find.text('我'));
    await tester.pumpAndSettle();
    expect(find.text('性别'), findsOneWidget);
    expect(find.text('我的发布'), findsOneWidget);
    expect(find.text('文字大小'), findsNothing);
    await tester.tap(find.text('动态'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('打开设置'));
    await tester.pumpAndSettle();
    expect(find.text('设置'), findsOneWidget);
    expect(find.text('文字大小'), findsOneWidget);
    expect(find.text('动态'), findsNothing);
    await tester.tap(find.byTooltip('返回'));
    await tester.pumpAndSettle();
    expect(find.text('动态'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
