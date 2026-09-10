import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'api.dart';

const atmosphereVideo =
    'https://d8j0ntlcm91z4.cloudfront.net/user_38xzZboKViGWJOttwIXH07lWA1P/hf_20260315_073750_51473149-4350-4920-ae24-c8214286f323.mp4';

class AppBackdrop extends StatefulWidget {
  final Api api;
  final Widget child;
  final bool allowVideo;
  const AppBackdrop({
    super.key,
    required this.api,
    required this.child,
    this.allowVideo = true,
  });
  @override
  State<AppBackdrop> createState() => _AppBackdropState();
}

class _AppBackdropState extends State<AppBackdrop> with WidgetsBindingObserver {
  VideoPlayerController? controller;
  bool ready = false, attempted = false, active = true;
  bool get enabled =>
      widget.allowVideo &&
      widget.api.dynamicBackground &&
      !widget.api.reduceMotion &&
      !MediaQuery.disableAnimationsOf(context) &&
      active;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    sync();
  }

  @override
  void didUpdateWidget(AppBackdrop old) {
    super.didUpdateWidget(old);
    sync();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    active = state == AppLifecycleState.resumed;
    if (mounted) sync();
  }

  Future<void> initializeVideo() async {
    attempted = true;
    if (!kIsWeb &&
        defaultTargetPlatform != TargetPlatform.android &&
        defaultTargetPlatform != TargetPlatform.iOS &&
        defaultTargetPlatform != TargetPlatform.macOS) {
      return;
    }
    final player = VideoPlayerController.networkUrl(
      Uri.parse(atmosphereVideo),
      videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
    );
    controller = player;
    try {
      await player.setVolume(0);
      await player.setLooping(true);
      await player.initialize().timeout(const Duration(seconds: 12));
      if (!mounted || controller != player) return;
      setState(() => ready = true);
      if (enabled) await player.play();
    } catch (_) {
      if (mounted) setState(() => ready = false);
    }
  }

  void sync() {
    if (enabled && !attempted) {
      initializeVideo();
      return;
    }
    final player = controller;
    if (player != null && ready) {
      if (enabled) {
        player.play().catchError((_) {});
      } else {
        player.pause().catchError((_) {});
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      const DecoratedBox(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(-.8, -.8),
            radius: 1.7,
            colors: [Color(0xFF303030), Color(0xFF161616), Color(0xFF080808)],
            stops: [0, .48, 1],
          ),
        ),
      ),
      if (ready && enabled && controller != null)
        Positioned.fill(
          child: ColorFiltered(
            colorFilter: const ColorFilter.matrix([
              .2126,
              .7152,
              .0722,
              0,
              0,
              .2126,
              .7152,
              .0722,
              0,
              0,
              .2126,
              .7152,
              .0722,
              0,
              0,
              0,
              0,
              0,
              1,
              0,
            ]),
            child: Opacity(
              opacity: .45,
              child: FittedBox(
                fit: BoxFit.cover,
                clipBehavior: Clip.hardEdge,
                child: SizedBox(
                  width: controller!.value.size.width,
                  height: controller!.value.size.height,
                  child: VideoPlayer(controller!),
                ),
              ),
            ),
          ),
        ),
      const DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0x50101010), Color(0xA6080808), Color(0xE6050505)],
            stops: [0, .45, 1],
          ),
        ),
      ),
      widget.child,
    ],
  );
}
