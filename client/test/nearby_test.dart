import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sayanything/api.dart';
import 'package:sayanything/nearby.dart';
import 'package:sayanything/device_location.dart';
import 'package:sayanything/page_activity.dart';

class NearbyApi extends Api {
  final calls = <String>[];
  final sentRevisions = <int>[];
  int stateRevision = 0;
  bool sharing = false;
  List<Data> items = [];
  Completer<Data>? pendingGreeting;
  NearbyApi() {
    user = {'allowDM': true};
  }
  @override
  Future<dynamic> call(String method, String path, [Data? data]) async {
    calls.add('$method $path');
    if (method == 'POST') return pendingGreeting!.future;
    if (method == 'PUT') {
      sharing = true;
      sentRevisions.add(data!['revision']);
      stateRevision++;
      return {
        'enabled': true,
        'revision': stateRevision,
        'radiusKm': 5,
        'expiresAt': '2099-01-01T01:00:00Z',
        'items': <Data>[],
      };
    }
    if (method == 'DELETE') {
      sharing = false;
      stateRevision++;
    }
    return {
      'enabled': sharing,
      'revision': stateRevision,
      'radiusKm': 5,
      'items': items,
    };
  }
}

void main() {
  testWidgets('nearby only requests location after explicit enable', (
    tester,
  ) async {
    var requests = 0;
    final api = NearbyApi();
    await tester.pumpWidget(
      MaterialApp(
        home: NearbyPage(
          api: api,
          locate: () async {
            requests++;
            return const DeviceLocation(31.2, 121.5);
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(requests, 0);
    expect(find.text('开启附近并展示我'), findsNothing);
    expect(find.text('模拟数据 · 仅供预览'), findsNothing);
    await tester.tap(find.byTooltip('附近设置'));
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsOneWidget);
    await tester.tap(find.text('开启附近并展示我'));
    await tester.pumpAndSettle();
    expect(requests, 1);
    expect(api.calls, contains('PUT /nearby/location'));
    await tester.tap(find.text('关闭附近展示'));
    await tester.pumpAndSettle();
    expect(api.calls, contains('DELETE /nearby/location'));
    await tester.tap(find.text('开启附近并展示我'));
    await tester.pumpAndSettle();
    expect(api.sentRevisions, [0, 2]);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('leaving while locating never publishes late coordinates', (
    tester,
  ) async {
    final location = Completer<DeviceLocation>();
    final api = NearbyApi();
    await tester.pumpWidget(
      MaterialApp(
        home: NearbyPage(api: api, locate: () => location.future),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('附近设置'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('开启附近并展示我'));
    await tester.pump();
    await tester.pumpWidget(const SizedBox());
    location.complete(const DeviceLocation(31.2, 121.5));
    await tester.pump();
    expect(api.calls.where((call) => call.startsWith('PUT')), isEmpty);
  });

  testWidgets('closing settings cancels positioning and refreshes status', (
    tester,
  ) async {
    final location = Completer<DeviceLocation>();
    final api = NearbyApi();
    await tester.pumpWidget(
      MaterialApp(
        home: NearbyPage(api: api, locate: () => location.future),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('附近设置'));
    await tester.pumpAndSettle();
    expect(
      tester
          .getSize(
            find.byWidgetPredicate(
              (widget) => widget is NearbyPage && widget.settingsOnly,
            ),
          )
          .height,
      lessThanOrEqualTo(420),
    );
    await tester.tap(find.text('开启附近并展示我'));
    await tester.pump();
    final reads = api.calls.length;
    await tester.tap(find.byTooltip('关闭附近设置'));
    await tester.pumpAndSettle();
    location.complete(const DeviceLocation(31.2, 121.5));
    await tester.pumpAndSettle();
    expect(api.calls.where((call) => call.startsWith('PUT')), isEmpty);
    expect(api.calls.length, greaterThan(reads));
    expect(find.text('你尚未开启附近展示'), findsOneWidget);
  });

  testWidgets('hidden cached page discards GPS and resumes with GET only', (
    tester,
  ) async {
    final api = NearbyApi();
    final location = Completer<DeviceLocation>();
    var active = true;
    var requests = 0;
    late StateSetter updateHost;
    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, update) {
            updateHost = update;
            return PageActivity(
              active: active,
              child: NearbyPage(
                api: api,
                settingsOnly: true,
                locate: () {
                  requests++;
                  return location.future;
                },
              ),
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('开启附近并展示我'));
    await tester.pump();
    updateHost(() => active = false);
    await tester.pump();
    location.complete(const DeviceLocation(31.2, 121.5));
    await tester.pump();
    expect(api.calls.where((call) => call.startsWith('PUT')), isEmpty);
    expect(find.text('正在获取大致位置…'), findsNothing);
    final reads = api.calls.length;
    updateHost(() => active = true);
    await tester.pumpAndSettle();
    expect(api.calls.length, reads + 1);
    expect(api.calls.last, 'GET /nearby');
    expect(requests, 1);
  });

  testWidgets('backgrounding cancels pending GPS and resume does not locate', (
    tester,
  ) async {
    final api = NearbyApi();
    final location = Completer<DeviceLocation>();
    var requests = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: NearbyPage(
          api: api,
          settingsOnly: true,
          locate: () {
            requests++;
            return location.future;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('开启附近并展示我'));
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    location.complete(const DeviceLocation(31.2, 121.5));
    await tester.pump();
    expect(api.calls.where((call) => call.startsWith('PUT')), isEmpty);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(requests, 1);
    expect(api.calls.last, 'GET /nearby');
  });

  testWidgets('late greeting response cannot navigate a hidden cached page', (
    tester,
  ) async {
    final api = NearbyApi()
      ..sharing = true
      ..items = [
        {
          'id': 'peer',
          'alias': '真实同学',
          'gender': 'male',
          'distanceLabel': '约 1 公里',
        },
      ]
      ..pendingGreeting = Completer<Data>();
    var active = true;
    late StateSetter updateHost;
    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, update) {
            updateHost = update;
            return PageActivity(
              active: active,
              child: NearbyPage(api: api),
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('打招呼'));
    await tester.pump();
    expect(api.calls, contains('POST /nearby/peer/greet'));
    updateHost(() => active = false);
    await tester.pump();
    api.pendingGreeting!.complete({'id': 'conversation', 'alias': '真实同学'});
    await tester.pumpAndSettle();
    expect(find.text('附近的人'), findsOneWidget);
    expect(find.text('输入消息…'), findsNothing);
    expect(
      api.calls.where((call) => call.contains('/conversations/')),
      isEmpty,
    );
  });
}
