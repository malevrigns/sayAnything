import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sayanything/main.dart';
import 'package:sayanything/api.dart';
import 'dart:async';
import 'package:sayanything/chat.dart';
import 'package:sayanything/feed.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SlowApi extends Api {
  final sent = Completer<dynamic>();
  final calls = <String>[];
  SlowApi() {
    user = {
      'id': 'u1',
      'alias': '晚风',
      'campus': '测试校园',
      'avatar': 1,
      'allowDM': true,
    };
  }
  @override
  Future<dynamic> call(String method, String path, [Data? data]) async {
    calls.add('$method $path');
    if (path == '/me') return user;
    if (method == 'POST') return sent.future;
    return <Data>[];
  }
}

class FailingFeedApi extends SlowApi {
  bool offline = false;
  @override
  Future<List<Data>> list(String path) async {
    if (offline) throw ApiError('网络已断开');
    return [];
  }
}

void main() {
  test(
    'visual preferences persist independently from anonymous identity',
    () async {
      SharedPreferences.setMockInitialValues({});
      FlutterSecureStorage.setMockInitialValues({});
      final api = Api();
      await api.setVisualOptions(background: false, reduce: true, scale: 1.12);
      final restored = Api();
      await restored.restore();
      expect(restored.dynamicBackground, false);
      expect(restored.reduceMotion, true);
      expect(restored.textScale, 1.12);
      expect(restored.user, isNull);
    },
  );
  testWidgets(
    'changing category offline displays a retry without unhandled errors',
    (tester) async {
      final api = FailingFeedApi();
      await tester.pumpWidget(MaterialApp(home: FeedPage(api: api)));
      await tester.pumpAndSettle();
      api.offline = true;
      await tester.tap(find.text('校园日常'));
      await tester.pumpAndSettle();
      expect(find.text('网络已断开'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('welcome fits narrow phone and validates campus', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(SayAnythingApp(api: Api(), restore: false));
    await tester.pumpAndSettle();
    expect(find.text('sayAnything'), findsWidgets);
    await tester.ensureVisible(find.text('进入校园'));
    await tester.tap(find.text('进入校园'));
    await tester.pumpAndSettle();
    expect(find.text('请先填写你的学校'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  test('API rejects credential-bearing and non-origin URLs', () {
    expect(Api.validOrigin('https://chat.example.com'), isTrue);
    expect(Api.validOrigin('http://192.168.1.5:8080'), isTrue);
    expect(Api.validOrigin('https://name:secret@example.com'), isFalse);
    expect(Api.validOrigin('https://example.com?token=secret'), isFalse);
    expect(Api.validOrigin('file:///tmp/db'), isFalse);
    expect(Api.validOrigin('https://example.com/api'), isFalse);
  });
  testWidgets('sending a message does not erase the next draft', (
    tester,
  ) async {
    final api = SlowApi();
    await tester.pumpWidget(
      MaterialApp(
        home: ChatPage(api: api, id: 'room', title: '茶水间', room: true),
      ),
    );
    await tester.pump();
    await tester.enterText(find.byType(TextField), '第一句');
    await tester.tap(find.byTooltip('发送消息'));
    await tester.pump();
    await tester.enterText(find.byType(TextField), '下一句还没发送');
    api.sent.complete({'id': 'm1'});
    await tester.pump();
    expect(find.text('下一句还没发送'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
  test('reconnecting preserves an existing valid anonymous identity', () async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({
      'session:http://localhost:8080': 'existing-token',
    });
    final api = SlowApi();
    api.sent.complete({'token': 'replacement', 'user': api.user});
    await api.connect('http://localhost:8080', '测试校园');
    expect(api.token, 'existing-token');
    expect(api.calls, ['GET /me']);
  });
}
