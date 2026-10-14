import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sayanything/api.dart';
import 'package:sayanything/chat.dart';
import 'package:sayanything/page_activity.dart';

import 'policy_fixture.dart';

class _PollingApi extends Api {
  _PollingApi() : super(serverPolicy: testPolicy());

  int requests = 0;
  Completer<List<Data>>? pending;
  List<Data> messages = [];

  @override
  Future<List<Data>> list(String path) async {
    requests++;
    return pending == null ? messages : pending!.future;
  }
}

void main() {
  for (final chat in [false, true]) {
    final label = chat ? 'chat' : 'inbox';
    final interval = Duration(seconds: chat ? 3 : 5);

    Widget page(Api api) => chat
        ? ChatPage(
            api: api,
            id: 'conversation',
            title: 'Conversation',
            room: false,
          )
        : InboxPage(api: api);

    testWidgets(
      '$label pauses cached tabs and resumes without duplicate loads',
      (tester) async {
        final api = _PollingApi();
        final active = ValueNotifier(true);
        addTearDown(active.dispose);
        await tester.pumpWidget(
          MaterialApp(
            home: ValueListenableBuilder<bool>(
              valueListenable: active,
              child: page(api),
              builder: (_, value, child) => PageActivity(
                active: value,
                child: Offstage(offstage: !value, child: child),
              ),
            ),
          ),
        );
        await tester.pump();
        expect(api.requests, 1);

        active.value = false;
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        expect(api.requests, 1, reason: 'hidden tabs must not poll');

        active.value = true;
        await tester.pump();
        expect(
          api.requests,
          1,
          reason: 'a fresh cache survives a quick tab switch',
        );
        await tester.pump(interval);
        expect(api.requests, 2);
        await tester.pump();
        active.value = false;
        await tester.pump();
        await tester.pump(interval * 4);
        expect(api.requests, 2, reason: 'hidden tabs must not poll');
        await tester.pumpWidget(const SizedBox());
        await tester.pump(interval * 2);
        expect(api.requests, 2, reason: 'disposing must cancel polling');
      },
    );

    testWidgets('$label defers its first load until visible', (tester) async {
      final api = _PollingApi();
      final active = ValueNotifier(false);
      addTearDown(active.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: ValueListenableBuilder<bool>(
            valueListenable: active,
            child: page(api),
            builder: (_, value, child) =>
                PageActivity(active: value, child: child!),
          ),
        ),
      );
      await tester.pump(interval * 2);
      expect(api.requests, 0);
      active.value = true;
      await tester.pump();
      await tester.pump();
      expect(api.requests, 1);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('$label refreshes an expired cache immediately on return', (
      tester,
    ) async {
      final api = _PollingApi();
      final active = ValueNotifier(true);
      addTearDown(active.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: ValueListenableBuilder<bool>(
            valueListenable: active,
            child: page(api),
            builder: (_, value, child) =>
                PageActivity(active: value, child: child!),
          ),
        ),
      );
      await tester.pump();
      active.value = false;
      await tester.pump();
      // Cache age uses wall time; fake widget time only advances polling timers.
      await tester.runAsync(
        () => Future<void>.delayed(interval + const Duration(milliseconds: 50)),
      );
      expect(api.requests, 1);
      active.value = true;
      await tester.pump();
      await tester.pump();
      expect(api.requests, 2);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('$label pauses when a dialog covers its route', (tester) async {
      final api = _PollingApi();
      final navigator = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        MaterialApp(navigatorKey: navigator, home: page(api)),
      );
      await tester.pump();
      unawaited(
        showDialog<void>(
          context: tester.element(find.byType(chat ? ChatPage : InboxPage)),
          builder: (_) => const AlertDialog(content: Text('Covered')),
        ),
      );
      await tester.pumpAndSettle();
      await tester.pump(interval * 4);
      expect(api.requests, 1);
      navigator.currentState!.pop();
      await tester.pumpAndSettle();
      await tester.pump(interval);
      expect(api.requests, 2);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('$label stays paused when the app resumes on a hidden tab', (
      tester,
    ) async {
      final api = _PollingApi();
      final active = ValueNotifier(true);
      addTearDown(active.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: ValueListenableBuilder<bool>(
            valueListenable: active,
            child: page(api),
            builder: (_, value, child) =>
                PageActivity(active: value, child: child!),
          ),
        ),
      );
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      active.value = false;
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump(interval * 3);
      expect(api.requests, 1);
      active.value = true;
      await tester.pump();
      await tester.pump(interval);
      expect(api.requests, 2);
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets(
    'inbox refreshes unread counts after a short conversation visit',
    (tester) async {
      final api = _PollingApi()
        ..messages = [
          {'id': 'conversation', 'alias': 'Peer', 'unread': 1},
        ];
      final navigator = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navigator,
          home: InboxPage(api: api),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Peer'));
      await tester.pumpAndSettle();
      expect(api.requests, 2);
      api.messages = [
        {'id': 'conversation', 'alias': 'Peer', 'unread': 0},
      ];
      navigator.currentState!.pop();
      await tester.pumpAndSettle();
      expect(api.requests, 3);
      expect(find.bySemanticsLabel('1 条未读消息'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('a chat response received while hidden never scrolls the list', (
    tester,
  ) async {
    List<Data> messages(int count) => List.generate(
      count,
      (index) => {
        'id': '$index',
        'authorId': 'peer',
        'body': 'Message $index',
        'createdAt': '2026-09-11T00:00:00Z',
      },
    );
    final api = _PollingApi()..messages = messages(20);
    final active = ValueNotifier(true);
    addTearDown(active.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: ValueListenableBuilder<bool>(
          valueListenable: active,
          child: ChatPage(
            api: api,
            id: 'conversation',
            title: 'Conversation',
            room: false,
          ),
          builder: (_, value, child) =>
              PageActivity(active: value, child: child!),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final controller = tester
        .widget<ListView>(find.byType(ListView))
        .controller!;
    controller.jumpTo(controller.position.maxScrollExtent);
    await tester.pump();
    final offset = controller.offset;
    final pending = Completer<List<Data>>();
    api.pending = pending;
    await tester.pump(const Duration(seconds: 3));
    expect(api.requests, 2);
    active.value = false;
    await tester.pump();
    pending.complete(messages(40));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(controller.offset, offset);
    expect(controller.position.maxScrollExtent, greaterThan(offset));
    await tester.pump(const Duration(seconds: 12));
    expect(api.requests, 2);
    await tester.pumpWidget(const SizedBox());
  });
}
