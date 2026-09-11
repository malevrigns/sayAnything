import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sayanything/api.dart';
import 'package:sayanything/chat.dart';
import 'package:sayanything/design.dart';
import 'policy_fixture.dart';

class ConversationApi extends Api {
  ConversationApi() : super(serverPolicy: testPolicy()) {
    user = {'id': 'self', 'alias': '我', 'campus': '测试校园', 'avatar': 0};
  }
  @override
  Future<List<Data>> list(String path) async => [
    {
      'id': 'message',
      'authorId': 'peer',
      'alias': '同学',
      'avatar': 0,
      'body': '这段正文必须能被读屏读取。',
      'createdAt': '2026-09-10T00:00:00Z',
    },
  ];
}

void main() {
  testWidgets('message announces sender and complete body together', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      MaterialApp(
        theme: appTheme(true),
        home: ChatPage(
          api: ConversationApi(),
          id: 'conversation',
          title: '匿名同学',
          room: false,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel(RegExp('对方：这段正文必须能被读屏读取。')), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    handle.dispose();
  });
}
