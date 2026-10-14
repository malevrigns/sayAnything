import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sayanything/api.dart';
import 'package:sayanything/chat.dart';
import 'package:sayanything/discover.dart';
import 'package:sayanything/page_activity.dart';
import 'package:sayanything/policy.dart';
import 'package:sayanything/profile.dart';
import 'policy_fixture.dart';

Map<String, dynamic> discoverPolicyJson() => {
  ...policyJson(),
  'profile': {
    'bioCharacters': 120,
    'maxTags': 5,
    'tags': ['摄影', '夜跑', '桌游', '纪录片', '猫', '咖啡'],
    'grades': [
      {'id': 'y1', 'label': '大一'},
      {'id': 'y2', 'label': '大二'},
      {'id': 'y3', 'label': '大三'},
      {'id': 'y4', 'label': '大四'},
      {'id': 'grad', 'label': '研究生'},
    ],
  },
  'discover': {'dailyLikes': 50},
};

class DiscoverApi extends Api {
  final requests = <String>[];
  final bodies = <Data>[];
  List<Data> items = [
    {
      'id': 'p1',
      'alias': '晚风同学',
      'avatar': 1,
      'gender': 'female',
      'bio': '喜欢在傍晚的操场慢慢走。',
      'grade': 'y2',
      'tags': ['夜跑', '纪录片'],
      'campus': '测试校园',
      'distanceLabel': '1 公里内',
    },
    {
      'id': 'p2',
      'alias': '图书馆的猫',
      'avatar': 2,
      'gender': 'male',
      'bio': '三楼靠窗的位置常有我。',
      'grade': 'y3',
      'tags': ['咖啡'],
      'campus': '测试校园',
    },
    {
      'id': 'p3',
      'alias': '橘子汽水',
      'avatar': 3,
      'gender': 'female',
      'bio': '',
      'grade': '',
      'tags': <String>[],
      'campus': '测试校园',
    },
  ];
  List<Data> likes = [];
  List<Data> matches = [];
  int likesMe = 0, likesLeft = 50;
  Data swipeResult = {'matched': false};
  Object? swipeError;
  DiscoverApi()
    : super(serverPolicy: AppPolicy.fromJson(discoverPolicyJson())) {
    user = {
      'id': 'u',
      'alias': '同学',
      'campus': '测试校园',
      'gender': 'undisclosed',
      'allowDM': true,
      'avatar': 0,
    };
  }

  @override
  Future<dynamic> call(String method, String path, [Data? data]) async {
    requests.add('$method $path');
    if (data != null) bodies.add(data);
    if (method == 'GET' && path == '/discover/likes') return likes;
    if (method == 'GET' && path == '/discover/matches') return matches;
    if (method == 'GET' && path.startsWith('/discover')) {
      return {'items': items, 'likesMe': likesMe, 'likesLeft': likesLeft};
    }
    if (method == 'POST' && path.endsWith('/swipe')) {
      if (swipeError != null) throw swipeError!;
      return swipeResult;
    }
    if (method == 'PATCH' && path == '/me') return {...user!, ...?data};
    return <Data>[];
  }
}

void usePhone(WidgetTester tester) {
  tester.view.physicalSize = const Size(360, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> pumpDeck(WidgetTester tester, DiscoverApi api) async {
  usePhone(tester);
  await tester.pumpWidget(MaterialApp(home: DiscoverPage(api: api)));
  await tester.pumpAndSettle();
}

Finder likeButton() => find.widgetWithText(FilledButton, '喜欢');
Finder passButton() => find.widgetWithText(OutlinedButton, '不喜欢');
Iterable<String> posts(DiscoverApi api) =>
    api.requests.where((request) => request.startsWith('POST'));

void main() {
  test('policy keeps older servers parsing and reads discover hints', () {
    final legacy = testPolicy();
    expect(legacy.bioCharacters, 120);
    expect(legacy.maxTags, 5);
    expect(legacy.tags, isEmpty);
    expect(legacy.grades, isEmpty);
    expect(legacy.dailyLikes, 50);
    expect(legacy.gradeLabel(''), isNull);
    expect(legacy.gradeLabel(null), isNull);
    final json = discoverPolicyJson();
    json['discover'] = {'dailyLikes': 20};
    (json['profile'] as Map)['bioCharacters'] = 80;
    (json['profile'] as Map)['maxTags'] = 3;
    final policy = AppPolicy.fromJson(json);
    expect(policy.bioCharacters, 80);
    expect(policy.maxTags, 3);
    expect(policy.dailyLikes, 20);
    expect(policy.tags, ['摄影', '夜跑', '桌游', '纪录片', '猫', '咖啡']);
    expect(policy.grades.map((grade) => grade.label), [
      '大一',
      '大二',
      '大三',
      '大四',
      '研究生',
    ]);
    expect(policy.gradeLabel('y2'), '大二');
    expect(policy.gradeLabel('unknown'), 'unknown');
  });

  testWidgets('deck renders the first card and the daily quota', (
    tester,
  ) async {
    final api = DiscoverApi();
    await pumpDeck(tester, api);
    expect(api.requests, ['GET /discover']);
    expect(find.text('晚风同学'), findsOneWidget);
    expect(find.text('喜欢在傍晚的操场慢慢走。'), findsOneWidget);
    expect(find.text('女 · 大二 · 测试校园'), findsOneWidget);
    expect(find.text('1 公里内'), findsOneWidget);
    expect(find.text('夜跑'), findsOneWidget);
    expect(find.text('纪录片'), findsOneWidget);
    expect(find.text('今日剩余 50 次心动'), findsOneWidget);
    expect(tester.widget<FilledButton>(likeButton()).onPressed, isNotNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a right swipe likes the card and reveals the next one', (
    tester,
  ) async {
    final api = DiscoverApi();
    await pumpDeck(tester, api);
    await tester.drag(find.text('晚风同学'), const Offset(280, 0));
    await tester.pumpAndSettle();
    expect(posts(api), ['POST /discover/p1/swipe']);
    expect(api.bodies.single, {'action': 'like'});
    expect(find.text('晚风同学'), findsNothing);
    expect(find.text('图书馆的猫'), findsOneWidget);
    expect(find.text('三楼靠窗的位置常有我。'), findsOneWidget);
    expect(find.text('今日剩余 49 次心动'), findsOneWidget);
    expect(find.text('心动了'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a left swipe passes without spending the quota', (tester) async {
    final api = DiscoverApi();
    await pumpDeck(tester, api);
    await tester.drag(find.text('晚风同学'), const Offset(-280, 0));
    await tester.pumpAndSettle();
    expect(posts(api), ['POST /discover/p1/swipe']);
    expect(api.bodies.single, {'action': 'pass'});
    expect(find.text('晚风同学'), findsNothing);
    expect(find.text('图书馆的猫'), findsOneWidget);
    expect(find.text('今日剩余 50 次心动'), findsOneWidget);
  });

  testWidgets('a short drag snaps back and sends nothing', (tester) async {
    final api = DiscoverApi();
    await pumpDeck(tester, api);
    await tester.drag(find.text('晚风同学'), const Offset(40, 0));
    await tester.pumpAndSettle();
    expect(posts(api), isEmpty);
    expect(find.text('晚风同学'), findsOneWidget);
  });

  testWidgets('a mutual like shows the match dialog and opens the chat', (
    tester,
  ) async {
    final api = DiscoverApi()
      ..swipeResult = {
        'matched': true,
        'conversation': {
          'id': 'c1',
          'alias': '晚风同学',
          'lastMessage': '',
          'updatedAt': '2026-10-14T00:00:00Z',
          'unread': 0,
        },
      };
    await pumpDeck(tester, api);
    await tester.tap(likeButton());
    await tester.pumpAndSettle();
    expect(posts(api), ['POST /discover/p1/swipe']);
    expect(api.bodies.single, {'action': 'like'});
    expect(find.text('心动了'), findsOneWidget);
    expect(find.text('你和“晚风同学”互相喜欢，可以开始聊天了。'), findsOneWidget);
    await tester.tap(find.text('去聊天'));
    await tester.pumpAndSettle();
    expect(find.byType(ChatPage), findsOneWidget);
    expect(find.text('心动了'), findsNothing);
    expect(api.requests, contains('GET /conversations/c1/messages'));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('continuing after a match keeps browsing the deck', (
    tester,
  ) async {
    final api = DiscoverApi()
      ..swipeResult = {
        'matched': true,
        'conversation': {'id': 'c1', 'alias': '晚风同学'},
      };
    await pumpDeck(tester, api);
    await tester.tap(likeButton());
    await tester.pumpAndSettle();
    await tester.tap(find.text('继续看看'));
    await tester.pumpAndSettle();
    expect(find.text('心动了'), findsNothing);
    expect(find.byType(ChatPage), findsNothing);
    expect(find.byType(DiscoverPage), findsOneWidget);
    expect(find.text('图书馆的猫'), findsOneWidget);
  });

  testWidgets('an exhausted quota disables liking and explains why', (
    tester,
  ) async {
    final api = DiscoverApi()..likesLeft = 0;
    await pumpDeck(tester, api);
    expect(find.text('今日剩余 0 次心动'), findsOneWidget);
    expect(find.text('今天的心动用完了，明天会再有 50 次。'), findsOneWidget);
    expect(tester.widget<FilledButton>(likeButton()).onPressed, isNull);
    expect(tester.widget<OutlinedButton>(passButton()).onPressed, isNotNull);
    await tester.drag(find.text('晚风同学'), const Offset(280, 0));
    await tester.pumpAndSettle();
    expect(posts(api), isEmpty);
    expect(find.text('晚风同学'), findsOneWidget);
    expect(find.text('今天的心动用完了，明天再来看看。'), findsOneWidget);
    await tester.drag(find.text('晚风同学'), const Offset(-280, 0));
    await tester.pumpAndSettle();
    expect(api.bodies.single, {'action': 'pass'});
    expect(find.text('图书馆的猫'), findsOneWidget);
  });

  testWidgets('a rejected like is toasted and the card comes back', (
    tester,
  ) async {
    final api = DiscoverApi()..swipeError = ApiError('请先开启接收私信', 403);
    api.user = {...api.user!, 'allowDM': false};
    await pumpDeck(tester, api);
    expect(find.text('开启“接收匿名私聊”后，才能表达喜欢。'), findsOneWidget);
    await tester.tap(likeButton());
    await tester.pumpAndSettle();
    expect(posts(api), ['POST /discover/p1/swipe']);
    expect(find.text('请先开启接收私信'), findsOneWidget);
    expect(find.text('晚风同学'), findsOneWidget);
    expect(find.text('今日剩余 50 次心动'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('an empty deck asks the user to come back later', (tester) async {
    final api = DiscoverApi()..items = [];
    await pumpDeck(tester, api);
    expect(find.text('这会儿没有新的同学了'), findsOneWidget);
    expect(tester.widget<FilledButton>(likeButton()).onPressed, isNull);
    expect(tester.widget<OutlinedButton>(passButton()).onPressed, isNull);
  });

  testWidgets('the gender filter refetches the deck', (tester) async {
    final api = DiscoverApi();
    await pumpDeck(tester, api);
    await tester.tap(find.text('男'));
    await tester.pumpAndSettle();
    expect(api.requests, ['GET /discover', 'GET /discover?gender=male']);
    await tester.tap(find.text('全部'));
    await tester.pumpAndSettle();
    expect(api.requests.last, 'GET /discover');
  });

  testWidgets(
    'the deck issues no request while inactive and refreshes on return',
    (tester) async {
      final api = DiscoverApi();
      final active = ValueNotifier(false);
      addTearDown(active.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: ValueListenableBuilder<bool>(
            valueListenable: active,
            child: DiscoverPage(api: api),
            builder: (_, value, child) => PageActivity(
              active: value,
              child: Offstage(offstage: !value, child: child),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(seconds: 10));
      expect(api.requests, isEmpty);
      active.value = true;
      await tester.pumpAndSettle();
      expect(api.requests, ['GET /discover']);
      expect(find.text('晚风同学'), findsOneWidget);
      active.value = false;
      await tester.pump();
      await tester.pump(const Duration(seconds: 30));
      expect(api.requests, [
        'GET /discover',
      ], reason: 'hidden decks never poll');
      active.value = true;
      await tester.pumpAndSettle();
      expect(api.requests, [
        'GET /discover',
        'GET /discover',
      ], reason: 'returning refreshes once');
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('likes page lists admirers and answering removes the row', (
    tester,
  ) async {
    final api = DiscoverApi();
    api.likes = [api.items[0], api.items[1]];
    usePhone(tester);
    await tester.pumpWidget(MaterialApp(home: LikesPage(api: api)));
    await tester.pumpAndSettle();
    expect(api.requests, ['GET /discover/likes']);
    expect(find.text('晚风同学'), findsOneWidget);
    expect(find.text('图书馆的猫'), findsOneWidget);
    expect(find.text('喜欢在傍晚的操场慢慢走。'), findsOneWidget);
    expect(find.text('夜跑'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, '喜欢').first);
    await tester.pumpAndSettle();
    expect(posts(api), ['POST /discover/p1/swipe']);
    expect(api.bodies.last, {'action': 'like'});
    expect(find.text('晚风同学'), findsNothing);
    expect(find.text('图书馆的猫'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, '忽略'));
    await tester.pumpAndSettle();
    expect(posts(api), ['POST /discover/p1/swipe', 'POST /discover/p2/swipe']);
    expect(api.bodies.last, {'action': 'pass'});
    expect(find.text('图书馆的猫'), findsNothing);
    expect(find.text('这里还很安静'), findsOneWidget);
  });

  testWidgets('likes page refreshes by pulling down', (tester) async {
    final api = DiscoverApi();
    usePhone(tester);
    await tester.pumpWidget(MaterialApp(home: LikesPage(api: api)));
    await tester.pumpAndSettle();
    expect(find.text('这里还很安静'), findsOneWidget);
    api.likes = [api.items[2]];
    await tester.fling(find.byType(ListView), const Offset(0, 400), 1000);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(api.requests.where((r) => r == 'GET /discover/likes').length, 2);
    expect(find.text('橘子汽水'), findsOneWidget);
    expect(find.text('这里还很安静'), findsNothing);
  });

  testWidgets('matches open their conversation', (tester) async {
    final api = DiscoverApi()
      ..matches = [
        {
          'id': 'p1',
          'alias': '晚风同学',
          'avatar': 1,
          'conversationId': 'c1',
          'matchedAt': DateTime.now()
              .subtract(const Duration(hours: 2))
              .toIso8601String(),
        },
      ];
    usePhone(tester);
    await tester.pumpWidget(MaterialApp(home: MatchesPage(api: api)));
    await tester.pumpAndSettle();
    expect(api.requests, ['GET /discover/matches']);
    expect(find.text('晚风同学'), findsOneWidget);
    expect(find.text('互相心动 · 2 小时前'), findsOneWidget);
    await tester.tap(find.text('晚风同学'));
    await tester.pumpAndSettle();
    expect(find.byType(ChatPage), findsOneWidget);
    expect(api.requests, contains('GET /conversations/c1/messages'));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('profile edits bio, grade and tags through PATCH /me', (
    tester,
  ) async {
    usePhone(tester);
    final api = DiscoverApi();
    await tester.pumpWidget(
      MaterialApp(
        home: ListenableBuilder(
          listenable: api,
          builder: (context, _) => ProfilePage(api: api),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('心动资料'), findsOneWidget);
    expect(find.text('匿名昵称'), findsOneWidget);
    expect(find.text('性别'), findsOneWidget);
    expect(find.text('未填写'), findsNWidgets(2));
    expect(find.text('未选择'), findsOneWidget);

    await tester.tap(find.text('简介'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '傍晚的操场见。');
    await tester.pump();
    expect(find.text('7/120'), findsOneWidget);
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 300));
    expect(api.requests, contains('PATCH /me'));
    expect(api.bodies.last, {'bio': '傍晚的操场见。'});
    expect(find.text('傍晚的操场见。'), findsOneWidget);
    expect(find.text('未填写'), findsOneWidget);

    await tester.tap(find.text('年级'));
    await tester.pumpAndSettle();
    expect(find.text('不填写'), findsOneWidget);
    await tester.tap(find.text('大二'));
    await tester.pumpAndSettle();
    expect(api.bodies.last, {'grade': 'y2'});
    expect(find.text('大二'), findsOneWidget);
    expect(find.text('未填写'), findsNothing);

    await tester.ensureVisible(find.text('标签'));
    await tester.tap(find.text('标签'));
    await tester.pumpAndSettle();
    for (final tag in ['摄影', '夜跑', '桌游', '纪录片', '猫']) {
      await tester.tap(find.widgetWithText(FilterChip, tag));
      await tester.pump();
    }
    expect(find.text('已选 5 / 5'), findsOneWidget);
    expect(
      tester
          .widget<FilterChip>(find.widgetWithText(FilterChip, '咖啡'))
          .onSelected,
      isNull,
    );
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(api.bodies.last, {
      'tags': ['摄影', '夜跑', '桌游', '纪录片', '猫'],
    });
    expect(find.text('摄影 · 夜跑 · 桌游 · 纪录片 · 猫'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
