import 'dart:async';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sayanything/api.dart';
import 'package:sayanything/media_draft.dart';
import 'package:sayanything/media_viewer.dart';
import 'package:video_player/video_player.dart';
// The existing video_player dependency supplies the platform test boundary.
// ignore: depend_on_referenced_packages
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

import 'policy_fixture.dart';

class TicketApi extends Api {
  TicketApi() : super(serverPolicy: testPolicy());
  int tickets = 0;
  bool reject = false;

  @override
  Future<dynamic> call(String method, String path, [Data? data]) async {
    if (reject) throw ApiError('暂时无法获取封面', 403);
    tickets++;
    return {
      'url': '/api/v1/media/old-video?ticket=signed%2Bvalue$tickets',
      'expiresAt': DateTime.now()
          .add(const Duration(minutes: 10))
          .toIso8601String(),
    };
  }
}

class FramePlatform extends VideoPlayerPlatform {
  final streams = <int, StreamController<VideoEvent>>{};
  final disposed = <int>[];
  final firstDisposal = Completer<void>();
  final volumes = <double>[];
  final seeks = <Duration>[];
  int created = 0, plays = 0;
  bool initializeAutomatically = true;

  @override
  Future<void> init() async {}
  @override
  Future<int?> createWithOptions(VideoCreationOptions options) async {
    final id = ++created;
    streams[id] = StreamController<VideoEvent>();
    if (initializeAutomatically) initialized(id);
    return id;
  }

  void initialized(int id) => streams[id]!.add(
    VideoEvent(
      eventType: VideoEventType.initialized,
      duration: const Duration(seconds: 5),
      size: const Size(640, 360),
    ),
  );

  @override
  Stream<VideoEvent> videoEventsFor(int playerId) => streams[playerId]!.stream;
  @override
  Future<void> dispose(int playerId) async {
    disposed.add(playerId);
    if (!firstDisposal.isCompleted) firstDisposal.complete();
    await streams[playerId]!.close();
  }

  @override
  Future<void> setLooping(int playerId, bool looping) async {}
  @override
  Future<void> pause(int playerId) async {}
  @override
  Future<void> play(int playerId) async {
    plays++;
  }

  @override
  Future<void> setVolume(int playerId, double volume) async {
    volumes.add(volume);
  }

  @override
  Future<void> seekTo(int playerId, Duration position) async {
    seeks.add(position);
  }

  @override
  Widget buildViewWithOptions(VideoViewOptions options) =>
      const ColoredBox(color: Colors.blue);
}

class DelayedPlaybackApi extends Api {
  final playback = Completer<String>();
  @override
  Future<String> posterUrl(String id, {bool refresh = false}) async =>
      throw ApiError('无封面');
  @override
  Future<String> mediaUrl(String id, {bool refresh = false}) => playback.future;
}

Widget panel(MediaDraft draft) => MaterialApp(
  home: Scaffold(body: MediaDraftPanel(draft: draft)),
);
XFile clip(String name) =>
    XFile.fromData(Uint8List(10), name: name, path: name);

void main() {
  test(
    'poster and playback reuse the same ticket and refresh together',
    () async {
      final api = TicketApi()..token = 'session-secret';
      final original = Uri.parse(await api.mediaUrl('old-video'));
      final poster = Uri.parse(
        await (api as dynamic).posterUrl('old-video') as String,
      );
      expect(
        poster.queryParameters['ticket'],
        original.queryParameters['ticket'],
      );
      expect(poster.queryParameters['view'], 'poster');
      expect(poster.toString(), isNot(contains('session-secret')));
      expect(api.tickets, 1);
      final refreshed = Uri.parse(
        await (api as dynamic).posterUrl('old-video', refresh: true) as String,
      );
      expect(
        refreshed.queryParameters['ticket'],
        isNot(original.queryParameters['ticket']),
      );
      expect(
        Uri.parse(await api.mediaUrl('old-video')).queryParameters['ticket'],
        refreshed.queryParameters['ticket'],
      );
      expect(api.tickets, 2);
    },
  );

  testWidgets(
    'old video requests a cover even without poster metadata and remains playable on failure',
    (tester) async {
      final api = TicketApi()..reject = true;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MediaAttachmentList(
              api: api,
              attachments: const [
                {
                  'id': 'old-video',
                  'kind': 'video',
                  'name': 'bee.mp4',
                  'size': 2048,
                },
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('封面暂不可用'), findsOneWidget);
      expect(find.byTooltip('重新加载封面'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('media-old-video')));
      await tester.pumpAndSettle();
      expect(find.text('无法播放这个视频'), findsOneWidget);
    },
  );

  group('local draft frame', () {
    late FramePlatform platform;
    late VideoPlayerPlatform previous;
    setUp(() {
      previous = VideoPlayerPlatform.instance;
      platform = FramePlatform();
      VideoPlayerPlatform.instance = platform;
    });
    tearDown(() {
      VideoPlayerPlatform.instance = previous;
    });

    testWidgets(
      'closing the viewer before its ticket arrives does not create a decoder',
      (tester) async {
        final api = DelayedPlaybackApi();
        final navigator = GlobalKey<NavigatorState>();
        await tester.pumpWidget(
          MaterialApp(
            navigatorKey: navigator,
            home: Scaffold(
              body: MediaAttachmentList(
                api: api,
                attachments: const [
                  {'id': 'old-video', 'kind': 'video', 'name': 'bee.mp4'},
                ],
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('media-old-video')));
        await tester.pump();
        navigator.currentState!.pop();
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));
        api.playback.complete('https://example.test/video.mp4?ticket=delayed');
        await tester.pumpAndSettle();
        expect(platform.created, 0);
      },
    );

    testWidgets('replacing the selected file disposes the previous preview', (
      tester,
    ) async {
      Widget preview(XFile file) => MaterialApp(
        home: SizedBox(
          width: 94,
          height: 96,
          child: LocalVideoPreview(file: file),
        ),
      );
      await tester.pumpWidget(preview(clip('one.mp4')));
      await tester.pumpAndSettle();
      await tester.pumpWidget(preview(clip('two.mp4')));
      await tester.pumpAndSettle();
      await tester.runAsync(
        () => platform.firstDisposal.future.timeout(const Duration(seconds: 2)),
      );
      expect(platform.created, 2);
      expect(platform.disposed, [1]);
      expect(platform.plays, 0);
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(() async {
        await Future<void>.delayed(Duration.zero);
      });
      expect(platform.disposed, [1, 2]);
    });

    testWidgets(
      'renders an actual muted paused cropped frame and releases it on removal',
      (tester) async {
        final draft = MediaDraft(TicketApi());
        await draft.addFiles([clip('bee.mp4')]);
        await tester.pumpWidget(panel(draft));
        await tester.pumpAndSettle();
        expect(find.byType(VideoPlayer), findsOneWidget);
        expect(platform.volumes, isNotEmpty);
        expect(platform.volumes.every((volume) => volume == 0), isTrue);
        expect(platform.plays, 0);
        expect(
          tester
              .widget<FittedBox>(
                find.ancestor(
                  of: find.byType(VideoPlayer),
                  matching: find.byType(FittedBox),
                ),
              )
              .fit,
          BoxFit.cover,
        );
        await tester.tap(find.byTooltip('移除附件 1'));
        await tester.pumpAndSettle();
        await tester.runAsync(
          () =>
              platform.firstDisposal.future.timeout(const Duration(seconds: 2)),
        );
        expect(platform.disposed, [1]);
        draft.dispose();
      },
    );

    testWidgets(
      'closing a draft during initialization releases the pending decoder',
      (tester) async {
        platform.initializeAutomatically = false;
        final draft = MediaDraft(TicketApi());
        await draft.addFiles([clip('bee.mp4')]);
        await tester.pumpWidget(panel(draft));
        await tester.pump();
        expect(platform.created, 1);
        await tester.pumpWidget(const SizedBox());
        await tester.pump();
        await tester.runAsync(
          () =>
              platform.firstDisposal.future.timeout(const Duration(seconds: 2)),
        );
        expect(platform.disposed, [1]);
        expect(platform.plays, 0);
        draft.dispose();
      },
    );
  });
}
