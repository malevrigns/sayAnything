import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sayanything/device_location.dart';
import 'package:sayanything/nearby.dart';
import 'nearby_test.dart' show NearbyApi;

void main() {
  const previewBuild = kIsWeb && bool.fromEnvironment('PREVIEW_NEARBY');

  testWidgets(
    'preview build displays labelled UI data without GPS or greetings',
    (tester) async {
      var positions = 0;
      final api = NearbyApi()
        ..sharing = true
        ..items = [
          {
            'id': 'real-peer',
            'alias': '真实附近同学',
            'gender': 'male',
            'distanceLabel': '约 1 公里',
          },
        ];
      await tester.pumpWidget(
        MaterialApp(
          home: NearbyPage(
            api: api,
            locate: () async {
              positions++;
              return const DeviceLocation(31.2, 121.5);
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('模拟数据 · 仅供预览'), findsOneWidget);
      expect(find.text('晚风同学'), findsOneWidget);
      expect(find.text('真实附近同学'), findsNothing);
      await tester.tap(find.text('打招呼').first);
      await tester.pump();
      expect(find.text('这是模拟同学，仅供预览，不会发送招呼。'), findsOneWidget);
      expect(api.calls, ['GET /nearby']);
      expect(positions, 0);
      await tester.tap(find.text('显示真实列表'));
      await tester.pumpAndSettle();
      expect(find.text('晚风同学'), findsNothing);
      expect(find.text('真实附近同学'), findsOneWidget);
      expect(find.text('查看模拟效果'), findsOneWidget);
      await tester.tap(find.text('查看模拟效果'));
      await tester.pumpAndSettle();
      expect(find.text('模拟数据 · 仅供预览'), findsOneWidget);
      expect(api.calls, ['GET /nearby']);
    },
    skip: !previewBuild,
  );

  testWidgets('default and native builds omit preview controls', (
    tester,
  ) async {
    await tester.pumpWidget(MaterialApp(home: NearbyPage(api: NearbyApi())));
    await tester.pumpAndSettle();
    expect(find.text('模拟数据 · 仅供预览'), findsNothing);
    expect(find.text('显示真实列表'), findsNothing);
    expect(find.text('查看模拟效果'), findsNothing);
  }, skip: previewBuild);
}
