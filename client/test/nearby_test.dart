import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sayanything/api.dart';
import 'package:sayanything/nearby.dart';
import 'package:sayanything/device_location.dart';

class NearbyApi extends Api {
  final calls = <String>[];
  final sentRevisions = <int>[];
  int stateRevision = 0;
  NearbyApi() {
    user = {'allowDM': true};
  }
  @override
  Future<dynamic> call(String method, String path, [Data? data]) async {
    calls.add('$method $path');
    if (method == 'PUT') {
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
    if (method == 'DELETE') stateRevision++;
    return {
      'enabled': false,
      'revision': stateRevision,
      'radiusKm': 5,
      'items': <Data>[],
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
    await tester.tap(find.text('开启附近并展示我'));
    await tester.pump();
    await tester.pumpWidget(const SizedBox());
    location.complete(const DeviceLocation(31.2, 121.5));
    await tester.pump();
    expect(api.calls.where((call) => call.startsWith('PUT')), isEmpty);
  });
}
