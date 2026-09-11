import 'dart:async';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:video_player/video_player.dart';

import 'api.dart';
import 'design.dart';
import 'media_video_native.dart'
    if (dart.library.html) 'media_video_web.dart'
    as local_media;

class MediaAttachmentList extends StatelessWidget {
  final Api api;
  final List<Data> attachments;
  final bool compact;

  const MediaAttachmentList({
    super.key,
    required this.api,
    required this.attachments,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    if (attachments.isEmpty) return const SizedBox.shrink();
    final extent = compact ? 104.0 : 168.0;
    return Padding(
      padding: const EdgeInsets.only(top: 9),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final attachment in attachments)
            SizedBox(
              key: ValueKey('media-${attachment['id']}'),
              width: extent,
              height: compact ? 104 : 132,
              child: attachment['kind'] == 'video'
                  ? _VideoAttachmentTile(api: api, attachment: attachment)
                  : _ImageAttachmentTile(api: api, attachment: attachment),
            ),
        ],
      ),
    );
  }
}

Future<void> openLocalMedia(
  BuildContext context,
  XFile file,
  String kind,
) async {
  if (kind == 'video') {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => _VideoViewerPage(
          title: file.name,
          loadController: ({required bool refresh}) async =>
              local_media.localVideoController(file),
        ),
      ),
    );
    return;
  }
  await Navigator.push<void>(
    context,
    MaterialPageRoute(builder: (_) => _LocalImagePage(file: file)),
  );
}

class _ImageAttachmentTile extends StatefulWidget {
  final Api api;
  final Data attachment;

  const _ImageAttachmentTile({required this.api, required this.attachment});

  @override
  State<_ImageAttachmentTile> createState() => _ImageAttachmentTileState();
}

class _ImageAttachmentTileState extends State<_ImageAttachmentTile> {
  late Future<String> url;

  String get id => '${widget.attachment['id']}';

  @override
  void initState() {
    super.initState();
    url = widget.api.mediaUrl(id);
  }

  @override
  void didUpdateWidget(_ImageAttachmentTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.attachment['id'] != widget.attachment['id']) {
      url = widget.api.mediaUrl(id);
    }
  }

  void reload() => setState(() {
    url = widget.api.mediaUrl(id, refresh: true);
  });

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: '查看图片 ${widget.attachment['name'] ?? ''}'.trim(),
    child: Material(
      color: Colors.white.withValues(alpha: .055),
      borderRadius: BorderRadius.circular(17),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.push<void>(
          context,
          MaterialPageRoute(
            builder: (_) => _RemoteImagePage(
              api: widget.api,
              attachment: widget.attachment,
            ),
          ),
        ),
        child: FutureBuilder<String>(
          future: url,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const _AttachmentLoading();
            }
            if (snapshot.hasError) return _AttachmentError(onRetry: reload);
            if (!snapshot.hasData) return _AttachmentError(onRetry: reload);
            return Image.network(
              snapshot.data!,
              key: ValueKey(snapshot.data),
              fit: BoxFit.cover,
              width: double.infinity,
              height: double.infinity,
              frameBuilder: (context, child, frame, sync) =>
                  sync || frame != null ? child : const _AttachmentLoading(),
              errorBuilder: (_, _, _) => _AttachmentError(onRetry: reload),
            );
          },
        ),
      ),
    ),
  );
}

class _VideoAttachmentTile extends StatefulWidget {
  final Api api;
  final Data attachment;

  const _VideoAttachmentTile({required this.api, required this.attachment});

  @override
  State<_VideoAttachmentTile> createState() => _VideoAttachmentTileState();
}

class _VideoAttachmentTileState extends State<_VideoAttachmentTile> {
  late Future<String> poster;

  @override
  void initState() {
    super.initState();
    poster = widget.api.posterUrl('${widget.attachment['id']}');
  }

  @override
  void didUpdateWidget(_VideoAttachmentTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.api != widget.api ||
        oldWidget.attachment['id'] != widget.attachment['id']) {
      poster = widget.api.posterUrl('${widget.attachment['id']}');
    }
  }

  void reload() => setState(() {
    poster = widget.api.posterUrl('${widget.attachment['id']}', refresh: true);
  });

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: '播放视频 ${widget.attachment['name'] ?? ''}'.trim(),
    child: Material(
      color: Colors.white.withValues(alpha: .055),
      borderRadius: BorderRadius.circular(17),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.push<void>(
          context,
          MaterialPageRoute(
            builder: (_) => _VideoViewerPage(
              title: widget.attachment['name']?.toString() ?? '视频',
              loadController: ({required bool refresh}) async {
                final url = await widget.api.mediaUrl(
                  '${widget.attachment['id']}',
                  refresh: refresh,
                );
                return VideoPlayerController.networkUrl(Uri.parse(url));
              },
            ),
          ),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            FutureBuilder<String>(
              future: poster,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const _PosterLoading();
                }
                if (snapshot.hasError || !snapshot.hasData) {
                  return _PosterUnavailable(onRetry: reload);
                }
                return Image.network(
                  snapshot.data!,
                  key: ValueKey(snapshot.data),
                  fit: BoxFit.cover,
                  frameBuilder: (_, child, frame, sync) =>
                      sync || frame != null ? child : const _PosterLoading(),
                  errorBuilder: (_, _, _) =>
                      _PosterUnavailable(onRetry: reload),
                );
              },
            ),
            const IgnorePointer(child: _VideoPlayOverlay()),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: IgnorePointer(
                child: ColoredBox(
                  color: Colors.black54,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 5,
                    ),
                    child: Text(
                      '${widget.attachment['name'] ?? '视频'} · ${_bytes(widget.attachment['size'])}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white, fontSize: 10),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _PosterLoading extends StatelessWidget {
  const _PosterLoading();
  @override
  Widget build(BuildContext context) => const Align(
    alignment: Alignment.topLeft,
    child: Padding(
      padding: EdgeInsets.all(10),
      child: SizedBox(
        width: 13,
        height: 13,
        child: CircularProgressIndicator(strokeWidth: 1.5),
      ),
    ),
  );
}

class _PosterUnavailable extends StatelessWidget {
  final VoidCallback? onRetry;
  const _PosterUnavailable({this.onRetry});
  @override
  Widget build(BuildContext context) => Stack(
    children: [
      const Positioned(
        left: 7,
        top: 8,
        child: Text('封面暂不可用', style: TextStyle(fontSize: 9, color: muted)),
      ),
      if (onRetry != null)
        Positioned(
          right: 0,
          top: 0,
          child: IconButton(
            tooltip: '重新加载封面',
            onPressed: onRetry,
            icon: const Icon(LucideIcons.refreshCw, size: 14, color: muted),
          ),
        ),
    ],
  );
}

class _VideoPlayOverlay extends StatelessWidget {
  const _VideoPlayOverlay();
  @override
  Widget build(BuildContext context) => Center(
    child: Container(
      width: 35,
      height: 35,
      decoration: const BoxDecoration(
        color: Colors.black54,
        shape: BoxShape.circle,
      ),
      child: const Icon(LucideIcons.play, size: 18, color: Colors.white),
    ),
  );
}

/// A real, muted frame from the selected file, owned by the draft tile's lifetime.
class LocalVideoPreview extends StatefulWidget {
  final XFile file;
  const LocalVideoPreview({super.key, required this.file});

  @override
  State<LocalVideoPreview> createState() => _LocalVideoPreviewState();
}

class _LocalVideoPreviewState extends State<LocalVideoPreview> {
  VideoPlayerController? controller;
  Timer? loadingDeadline;
  bool ready = false, failed = false;

  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void didUpdateWidget(LocalVideoPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.file != widget.file) {
      release();
      ready = false;
      failed = false;
      load();
    }
  }

  bool owns(VideoPlayerController player) =>
      mounted && identical(controller, player);

  void release() {
    final previous = controller;
    loadingDeadline?.cancel();
    loadingDeadline = null;
    controller = null;
    previous?.removeListener(changed);
    if (previous != null) unawaited(previous.dispose().catchError((_) {}));
  }

  Future<void> load() async {
    VideoPlayerController? player;
    try {
      player = local_media.localVideoController(widget.file);
      controller = player;
      // Set the controller value before initialize applies volume to the platform.
      await player.setVolume(0);
      if (!owns(player)) return;
      loadingDeadline = Timer(const Duration(seconds: 15), () {
        if (!owns(player!)) return;
        release();
        setState(() => failed = true);
      });
      await player.initialize();
      if (!owns(player)) return;
      await player.pause();
      if (!owns(player)) return;
      // Seek past an opening black frame without ever starting playback/audio.
      final duration = player.value.duration.inMilliseconds;
      await player.seekTo(Duration(milliseconds: duration > 150 ? 150 : 0));
      if (!owns(player)) return;
      player.addListener(changed);
      loadingDeadline?.cancel();
      loadingDeadline = null;
      setState(() => ready = true);
    } catch (_) {
      if (player == null ? mounted : owns(player)) {
        release();
        setState(() => failed = true);
      }
    }
  }

  void changed() {
    if (mounted && controller?.value.hasError == true) {
      release();
      setState(() => failed = true);
    }
  }

  @override
  void dispose() {
    release();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final player = controller;
    return ColoredBox(
      color: forest,
      child: IgnorePointer(
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (ready && player != null)
              ClipRect(
                child: FittedBox(
                  fit: BoxFit.cover,
                  child: SizedBox(
                    width: player.value.size.width,
                    height: player.value.size.height,
                    child: VideoPlayer(player),
                  ),
                ),
              )
            else if (failed)
              const _PosterUnavailable()
            else
              const _PosterLoading(),
            const _VideoPlayOverlay(),
          ],
        ),
      ),
    );
  }
}

class _RemoteImagePage extends StatefulWidget {
  final Api api;
  final Data attachment;

  const _RemoteImagePage({required this.api, required this.attachment});

  @override
  State<_RemoteImagePage> createState() => _RemoteImagePageState();
}

class _RemoteImagePageState extends State<_RemoteImagePage> {
  late Future<String> url;

  String get id => '${widget.attachment['id']}';

  @override
  void initState() {
    super.initState();
    url = widget.api.mediaUrl(id);
  }

  @override
  void didUpdateWidget(_RemoteImagePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.attachment['id'] != widget.attachment['id']) {
      url = widget.api.mediaUrl(id);
    }
  }

  void reload() => setState(() {
    url = widget.api.mediaUrl(id, refresh: true);
  });

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFF050505),
    appBar: AppBar(
      leading: backButton(context),
      title: Text(
        widget.attachment['name']?.toString() ?? '图片',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    ),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: FutureBuilder<String>(
          future: url,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const _AttachmentLoading();
            }
            if (snapshot.hasError) return _ViewerError(onRetry: reload);
            if (!snapshot.hasData) return _ViewerError(onRetry: reload);
            return InteractiveViewer(
              minScale: .8,
              maxScale: 5,
              child: Center(
                child: Image.network(
                  snapshot.data!,
                  key: ValueKey(snapshot.data),
                  fit: BoxFit.contain,
                  frameBuilder: (context, child, frame, sync) =>
                      sync || frame != null
                      ? child
                      : const _AttachmentLoading(),
                  errorBuilder: (_, _, _) => _ViewerError(onRetry: reload),
                ),
              ),
            );
          },
        ),
      ),
    ),
  );
}

class _LocalImagePage extends StatelessWidget {
  final XFile file;

  const _LocalImagePage({required this.file});

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFF050505),
    appBar: AppBar(
      leading: backButton(context),
      title: Text(file.name, maxLines: 1, overflow: TextOverflow.ellipsis),
    ),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: InteractiveViewer(
          minScale: .8,
          maxScale: 5,
          child: Center(
            child: Image(
              image: local_media.localImageProvider(file),
              fit: BoxFit.contain,
              errorBuilder: (_, _, _) => const _ViewerMessage(
                icon: LucideIcons.imageOff,
                title: '无法显示这张图片',
                detail: '文件可能已移动，或图片格式无法解码。',
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

typedef _ControllerLoader =
    Future<VideoPlayerController> Function({required bool refresh});

class _VideoViewerPage extends StatefulWidget {
  final String title;
  final _ControllerLoader loadController;

  const _VideoViewerPage({required this.title, required this.loadController});

  @override
  State<_VideoViewerPage> createState() => _VideoViewerPageState();
}

class _VideoViewerPageState extends State<_VideoViewerPage> {
  VideoPlayerController? controller;
  Object? error;
  bool loading = true;
  int loadGeneration = 0;

  @override
  void initState() {
    super.initState();
    load(refresh: false);
  }

  Future<void> load({required bool refresh}) async {
    if (!mounted) return;
    final generation = ++loadGeneration;
    final previous = controller;
    if (mounted) {
      setState(() {
        controller = null;
        error = null;
        loading = true;
      });
    }
    previous?.removeListener(changed);
    if (previous != null) unawaited(previous.dispose().catchError((_) {}));
    VideoPlayerController? next;
    try {
      next = await widget.loadController(refresh: refresh);
      if (!mounted || generation != loadGeneration) {
        await next.dispose();
        return;
      }
      // Own pending initialization too, so closing the page releases its decoder.
      controller = next;
      await next.initialize();
      if (!mounted || generation != loadGeneration) return;
      next.addListener(changed);
      setState(() {
        controller = next;
        loading = false;
      });
    } catch (exception) {
      if (mounted && generation == loadGeneration) {
        if (identical(controller, next)) controller = null;
        if (next != null) unawaited(next.dispose().catchError((_) {}));
        setState(() {
          error = exception;
          loading = false;
        });
      }
    }
  }

  void changed() {
    if (!mounted || controller == null) return;
    final value = controller!.value;
    if (value.hasError && error == null) {
      setState(() => error = value.errorDescription ?? '视频播放失败');
    } else {
      setState(() {});
    }
  }

  Future<void> toggle() async {
    final player = controller;
    if (player == null || !player.value.isInitialized) return;
    if (player.value.isPlaying) {
      await player.pause();
    } else {
      await player.play();
    }
  }

  @override
  void dispose() {
    loadGeneration++;
    final player = controller;
    player?.removeListener(changed);
    if (player != null) unawaited(player.dispose().catchError((_) {}));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final player = controller;
    return Scaffold(
      backgroundColor: const Color(0xFF050505),
      appBar: AppBar(
        leading: backButton(context),
        title: Text(widget.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: loading
              ? const _AttachmentLoading()
              : error != null || player == null
              ? _ViewerError(
                  title: '无法播放这个视频',
                  detail: '视频可能已失效，或当前设备不支持这种编码。',
                  onRetry: () => load(refresh: true),
                )
              : Column(
                  children: [
                    Expanded(
                      child: Center(
                        child: AspectRatio(
                          aspectRatio: player.value.aspectRatio > 0
                              ? player.value.aspectRatio
                              : 16 / 9,
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              VideoPlayer(player),
                              if (player.value.isBuffering)
                                const Center(child: _AttachmentLoading()),
                            ],
                          ),
                        ),
                      ),
                    ),
                    _VideoControls(controller: player, onToggle: toggle),
                  ],
                ),
        ),
      ),
    );
  }
}

class _VideoControls extends StatelessWidget {
  final VideoPlayerController controller;
  final Future<void> Function() onToggle;

  const _VideoControls({required this.controller, required this.onToggle});

  @override
  Widget build(BuildContext context) {
    final value = controller.value;
    final duration = value.duration;
    final position = value.position > duration ? duration : value.position;
    final total = duration.inMilliseconds.toDouble();
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 18),
        child: Glass(
          strong: true,
          radius: 25,
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
          child: Row(
            children: [
              IconButton(
                onPressed: onToggle,
                tooltip: value.isPlaying ? '暂停视频' : '播放视频',
                icon: Icon(
                  value.isPlaying ? LucideIcons.pause : LucideIcons.play,
                  size: 20,
                ),
              ),
              Expanded(
                child: Slider(
                  value: total <= 0
                      ? 0
                      : position.inMilliseconds.clamp(0, total).toDouble(),
                  max: total <= 0 ? 1 : total,
                  onChanged: total <= 0
                      ? null
                      : (next) => controller.seekTo(
                          Duration(milliseconds: next.round()),
                        ),
                ),
              ),
              Text(
                '${_duration(position)} / ${_duration(duration)}',
                style: const TextStyle(color: muted, fontSize: 10),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AttachmentLoading extends StatelessWidget {
  const _AttachmentLoading();
  @override
  Widget build(BuildContext context) => const Center(
    child: SizedBox(
      width: 22,
      height: 22,
      child: CircularProgressIndicator(strokeWidth: 1.5),
    ),
  );
}

class _AttachmentError extends StatelessWidget {
  final VoidCallback onRetry;
  const _AttachmentError({required this.onRetry});
  @override
  Widget build(BuildContext context) => Center(
    child: IconButton(
      onPressed: onRetry,
      tooltip: '重新加载附件',
      icon: const Icon(LucideIcons.refreshCw, color: muted, size: 20),
    ),
  );
}

class _ViewerError extends StatelessWidget {
  final String title, detail;
  final VoidCallback onRetry;
  const _ViewerError({
    this.title = '附件暂时无法打开',
    this.detail = '链接可能已过期，请重新加载。',
    required this.onRetry,
  });
  @override
  Widget build(BuildContext context) => _ViewerMessage(
    icon: LucideIcons.circleAlert,
    title: title,
    detail: detail,
    action: TextButton.icon(
      onPressed: onRetry,
      icon: const Icon(LucideIcons.refreshCw, size: 17),
      label: const Text('重新加载附件'),
    ),
  );
}

class _ViewerMessage extends StatelessWidget {
  final IconData icon;
  final String title, detail;
  final Widget? action;
  const _ViewerMessage({
    required this.icon,
    required this.title,
    required this.detail,
    this.action,
  });
  @override
  Widget build(BuildContext context) => Center(
    child: EmptyState(title, detail, icon: icon, action: action),
  );
}

String _bytes(dynamic raw) {
  final size = raw is num ? raw.toInt() : int.tryParse('$raw') ?? 0;
  if (size < 1024) return '$size B';
  if (size < 1024 * 1024) return '${(size / 1024).toStringAsFixed(1)} KB';
  return '${(size / (1024 * 1024)).toStringAsFixed(1)} MB';
}

String _duration(Duration value) {
  final minutes = value.inMinutes;
  final seconds = value.inSeconds.remainder(60).toString().padLeft(2, '0');
  return '$minutes:$seconds';
}
