import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sayanything/api.dart';
import 'package:sayanything/app.dart';
import 'package:sayanything/design.dart';
import 'package:sayanything/feed.dart';
import 'policy_fixture.dart';

class CachedNavigationApi extends Api {
  int feedRequests = 0;
  CachedNavigationApi() : super(serverPolicy: testPolicy()) {
    user = {
      'id': 'u',
      'alias': '原昵称',
      'campus': '测试校园',
      'gender': 'undisclosed',
      'allowDM': true,
    };
  }
  @override
  Future<List<Data>> list(String path) async {
    if (path.startsWith('/posts')) {
      feedRequests++;
      return List.generate(
        25,
        (i) => {
          'id': 'p$i',
          'authorId': 'peer',
          'alias': '同学$i',
          'body': '第$i条测试动态',
          'category': '校园日常',
          'createdAt': '2026-09-11T00:00:00Z',
          'avatar': 0,
          'likes': 0,
          'comments': 0,
        },
      );
    }
    return [];
  }
}

void main() {
  testWidgets('warm tabs retain feed state and scroll without refetching', (
    tester,
  ) async {
    final api = CachedNavigationApi();
    await tester.pumpWidget(
      MaterialApp(
        theme: appTheme(true),
        home: HomeShell(api: api),
      ),
    );
    await tester.pumpAndSettle();
    final feed = find.byType(FeedPage);
    final oldState = tester.state(feed);
    final scroll = find
        .descendant(of: feed, matching: find.byType(Scrollable))
        .first;
    await tester.drag(scroll, const Offset(0, -650));
    await tester.pumpAndSettle();
    final offset = tester.state<ScrollableState>(scroll).position.pixels;
    expect(offset, greaterThan(100));
    for (var i = 0; i < 4; i++) {
      await tester.tap(find.text('我'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('动态'));
      await tester.pumpAndSettle();
    }
    expect(identical(tester.state(feed), oldState), isTrue);
    expect(
      tester.state<ScrollableState>(scroll).position.pixels,
      closeTo(offset, 1),
    );
    expect(api.feedRequests, 1);
    await tester.tap(find.text('我'));
    await tester.pumpAndSettle();
    api.user = {...api.user!, 'alias': '更新后的昵称'};
    api.notifyListeners();
    await tester.pumpAndSettle();
    expect(find.text('更新后的昵称'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'subpages use short transitions and reduced motion has no duration',
    (tester) async {
      final nav = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: nav,
          theme: appTheme(true),
          home: const Scaffold(body: Text('first')),
        ),
      );
      final route = MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('second')),
      );
      nav.currentState!.push(route);
      await tester.pump();
      expect(
        route.transitionDuration,
        lessThan(const Duration(milliseconds: 200)),
      );
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: nav,
          theme: appTheme(true, reduceMotion: true),
          home: const Scaffold(body: Text('first')),
        ),
      );
      final quietRoute = MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('quiet')),
      );
      nav.currentState!.push(quietRoute);
      await tester.pumpAndSettle();
      expect(quietRoute.transitionDuration, Duration.zero);
      expect(quietRoute.reverseTransitionDuration, Duration.zero);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('changing identity discards cached tab state', (tester) async {
    final api = CachedNavigationApi();
    await tester.pumpWidget(
      MaterialApp(
        theme: appTheme(true),
        home: HomeShell(api: api),
      ),
    );
    await tester.pumpAndSettle();
    final oldState = tester.state(find.byType(FeedPage));
    api.user = {...api.user!, 'id': 'another-user'};
    api.notifyListeners();
    await tester.pumpAndSettle();
    expect(identical(oldState, tester.state(find.byType(FeedPage))), isFalse);
    expect(api.feedRequests, 2);
    await tester.pumpWidget(const SizedBox());
  });
}
