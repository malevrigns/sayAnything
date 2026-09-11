import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sayanything/api.dart';
import 'package:sayanything/chat.dart';
import 'package:sayanything/media_draft.dart';
import 'policy_fixture.dart';

class PolicyApi extends Api {
  final calls = <String>[];
  final requestTokens = <String?>[];
  @override
  Future<dynamic> call(String method, String path, [Data? data]) async {
    calls.add(path);
    requestTokens.add(token);
    if (path == '/config') return policyJson(maxImageBytes: 50);
    if (path == '/session') {
      return {
        'token': 'test',
        'user': {'id': 'u', 'alias': '同学', 'campus': '学校'},
      };
    }
    throw ApiError('unexpected request');
  }
}

class SearchApi extends Api {
  final requests = <String, Completer<List<Data>>>{};
  @override
  Future<List<Data>> list(String path) async {
    if (path == '/conversations') return [];
    final key = Uri.parse(path).queryParameters['q']!;
    return (requests[key] = Completer<List<Data>>()).future;
  }
}

void main() {
  test(
    'connect fetches authoritative policy and media hints use server limits',
    () async {
      SharedPreferences.setMockInitialValues({});
      FlutterSecureStorage.setMockInitialValues({});
      final api = PolicyApi();
      api.token = 'previous-server-token';
      await api.connect('http://localhost:8080', '学校');
      expect(api.calls, ['/config', '/session']);
      expect(api.requestTokens.first, isNull);
      expect(api.policy.categories, ['服务端分类']);
      expect(MediaDraft(api).validateFile('photo.jpg', 51), isNotNull);
      expect(MediaDraft(api).validateFile('photo.jpg', 49), isNull);
    },
  );

  testWidgets(
    'search requests server and ignores older responses and empty input',
    (tester) async {
      final api = SearchApi();
      await tester.pumpWidget(MaterialApp(home: InboxPage(api: api)));
      await tester.pump();
      await tester.tap(find.byTooltip('搜索聊天记录'));
      await tester.pumpAndSettle();
      expect(api.requests, isEmpty);
      await tester.enterText(find.byType(TextField), '旧关键词');
      await tester.pump(const Duration(milliseconds: 300));
      await tester.enterText(find.byType(TextField), '历史消息');
      await tester.pump(const Duration(milliseconds: 300));
      api.requests['历史消息']!.complete([
        {'id': 'c', 'alias': '同学', 'matchSnippet': '服务端找到的历史消息'},
      ]);
      await tester.pump();
      api.requests['旧关键词']!.complete([
        {'id': 'old', 'alias': '旧结果'},
      ]);
      await tester.pump();
      expect(find.text('服务端找到的历史消息'), findsOneWidget);
      expect(find.text('旧结果'), findsNothing);
      await tester.enterText(find.byType(TextField), '');
      await tester.pump();
      expect(find.text('服务端找到的历史消息'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
