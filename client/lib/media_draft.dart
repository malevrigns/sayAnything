import 'dart:math';
import 'dart:typed_data';
import 'package:dio/dio.dart' show CancelToken;
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'api.dart';
import 'design.dart';
import 'media_viewer.dart';

String _randomKey() => List.generate(
  16,
  (_) => Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0'),
).join();

class PendingMedia {
  final XFile file;
  final String kind;
  final int size;
  final String uploadId = _randomKey();
  final Uint8List? preview;
  Data? uploaded;
  PendingMedia(this.file, this.kind, this.size, this.preview);
}

class MediaDraft extends ChangeNotifier {
  final Api api;
  final List<PendingMedia> _items = [];
  List<PendingMedia> get items => List.unmodifiable(_items);
  bool busy = false, choosing = false, _disposed = false;
  double progress = 0;
  String? error;
  String _requestKey = _randomKey(), _fingerprint = '';
  CancelToken? _cancel;
  MediaDraft(this.api);
  bool get isNotEmpty => _items.isNotEmpty;
  String? validateFile(String name, int size) {
    final policy = api.policy;
    final extension = name.toLowerCase().split('.').last;
    if (!policy.imageExtensions.contains(extension) &&
        !policy.videoExtensions.contains(extension)) {
      return '当前支持 ${policy.formatHint}';
    }
    if (size <= 0) return '不能发送空文件';
    final image = policy.imageExtensions.contains(extension);
    final limit = image ? policy.maxImageBytes : policy.maxVideoBytes;
    if (size > limit) {
      return '${image ? "单张图片" : "单个视频"}不能超过 ${formatMediaSize(limit)}';
    }
    return null;
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> choose() async {
    if (busy || choosing) return;
    choosing = true;
    error = null;
    _notify();
    try {
      final files = await openFiles(
        acceptedTypeGroups: [
          XTypeGroup(
            label: '图片与视频',
            extensions: [
              ...api.policy.imageExtensions,
              ...api.policy.videoExtensions,
            ],
            mimeTypes: const ['image/*', 'video/*'],
            uniformTypeIdentifiers: const ['public.image', 'public.movie'],
          ),
        ],
      );
      if (!_disposed) await addFiles(files);
    } catch (e) {
      if (!_disposed) error = e is ApiError ? e.message : '无法读取文件，请重新选择';
    } finally {
      choosing = false;
      _notify();
    }
  }

  Future<void> addFiles(List<XFile> files) async {
    if (busy) return;
    final errors = <String>[];
    for (final file in files) {
      if (_disposed) return;
      if (_items.length >= api.policy.maxAttachments) {
        errors.add('每条消息最多 ${api.policy.maxAttachments} 个附件');
        break;
      }
      final size = await file.length();
      final issue = validateFile(file.name, size);
      if (issue != null) {
        errors.add(issue);
        continue;
      }
      if (_items.fold<int>(0, (n, f) => n + f.size) + size >
          api.policy.maxTotalBytes) {
        errors.add('附件总大小不能超过 ${formatMediaSize(api.policy.maxTotalBytes)}');
        continue;
      }
      final image = api.policy.imageExtensions.contains(
        file.name.toLowerCase().split('.').last,
      );
      final preview = image ? await file.readAsBytes() : null;
      if (!_disposed) {
        _items.add(
          PendingMedia(file, image ? 'image' : 'video', size, preview),
        );
      }
    }
    error = errors.isEmpty ? null : errors.toSet().join('；');
    _notify();
  }

  Future<List<String>> prepare() async {
    if (busy) throw ApiError('附件正在上传，请稍候');
    busy = true;
    error = null;
    progress = 0;
    _cancel = CancelToken();
    _notify();
    try {
      final total = _items.fold<int>(0, (n, f) => n + f.size);
      var completed = 0;
      for (final item in _items) {
        if (_disposed) throw ApiError('上传已取消');
        item.uploaded ??= await api.uploadMedia(
          item.file,
          uploadId: item.uploadId,
          cancelToken: _cancel,
          onProgress: (sent, length) {
            if (!_disposed) {
              progress = total == 0
                  ? 0
                  : (completed +
                            item.size * (length == 0 ? 0 : sent / length)) /
                        total;
              _notify();
            }
          },
        );
        completed += item.size;
        progress = total == 0 ? 1 : completed / total;
        _notify();
      }
      return _items.map((i) => i.uploaded!['id'] as String).toList();
    } catch (e) {
      error = e.toString();
      rethrow;
    } finally {
      busy = false;
      _cancel = null;
      _notify();
    }
  }

  String requestIdFor(String text) {
    final fingerprint =
        '$text|${_items.map((i) => i.uploaded?['id'] ?? i.uploadId).join(',')}';
    if (_fingerprint != fingerprint) {
      _fingerprint = fingerprint;
      _requestKey = _randomKey();
    }
    return _requestKey;
  }

  void cancel() => _cancel?.cancel();
  Future<void> remove(PendingMedia media) async {
    if (busy) return;
    _items.remove(media);
    error = null;
    _notify();
    if (media.uploaded != null) {
      try {
        await api.call('DELETE', '/media/${media.uploaded!['id']}');
      } catch (_) {
        /* Server GC handles cancelled or already bound uploads. */
      }
    }
  }

  void clearSent() {
    _items.clear();
    error = null;
    _fingerprint = '';
    _requestKey = _randomKey();
    progress = 0;
    _notify();
  }

  @override
  void dispose() {
    _disposed = true;
    _cancel?.cancel();
    for (final item in _items) {
      if (item.uploaded != null) {
        api
            .call('DELETE', '/media/${item.uploaded!['id']}')
            .catchError((_) => <String, dynamic>{});
      }
    }
    super.dispose();
  }
}

class MediaDraftPanel extends StatelessWidget {
  final MediaDraft draft;
  final bool disabled;
  const MediaDraftPanel({
    super.key,
    required this.draft,
    this.disabled = false,
  });
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: draft,
    builder: (context, _) => Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (draft.items.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 9),
            child: SizedBox(
              height: 96,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: draft.items.length,
                separatorBuilder: (_, i) => const SizedBox(width: 9),
                itemBuilder: (context, i) =>
                    _thumbnail(context, draft.items[i], i),
              ),
            ),
          ),
        if (draft.busy)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Column(
              children: [
                LinearProgressIndicator(
                  value: draft.progress,
                  backgroundColor: Colors.white10,
                  color: Colors.white70,
                  minHeight: 2,
                ),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        draft.progress >= 1
                            ? '正在处理附件…'
                            : '正在上传 ${(draft.progress * 100).round()}%',
                        style: const TextStyle(
                          fontSize: 11,
                          color: Colors.white60,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: draft.cancel,
                      child: const Text('取消上传', style: TextStyle(fontSize: 11)),
                    ),
                  ],
                ),
              ],
            ),
          ),
        if (draft.error != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              draft.error!,
              style: const TextStyle(
                fontSize: 12,
                color: Colors.white70,
                height: 1.5,
              ),
            ),
          ),
      ],
    ),
  );
  Widget _thumbnail(BuildContext context, PendingMedia item, int index) {
    final Widget preview = item.preview != null
        ? Image.memory(
            item.preview!,
            fit: BoxFit.cover,
            cacheWidth: 256,
            errorBuilder: (_, _, _) => const ColoredBox(
              color: forest,
              child: Icon(LucideIcons.imageOff, color: muted),
            ),
          )
        : LocalVideoPreview(key: ValueKey(item.uploadId), file: item.file);
    return SizedBox(
      key: ValueKey(item.uploadId),
      width: 94,
      child: Stack(
        children: [
          Positioned.fill(
            child: InkWell(
              onTap: disabled || draft.busy
                  ? null
                  : () => openLocalMedia(context, item.file, item.kind),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: preview,
              ),
            ),
          ),
          if (item.kind == 'video')
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: IgnorePointer(
                child: ClipRRect(
                  borderRadius: const BorderRadius.vertical(
                    bottom: Radius.circular(16),
                  ),
                  child: ColoredBox(
                    color: Colors.black54,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 5,
                      ),
                      child: Text(
                        '${item.file.name} · ${formatMediaSize(item.size)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 9,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          Positioned(
            right: 0,
            top: 0,
            child: IconButton(
              tooltip: '移除附件 ${index + 1}',
              onPressed: disabled || draft.busy
                  ? null
                  : () => draft.remove(item),
              style: IconButton.styleFrom(
                backgroundColor: Colors.black54,
                foregroundColor: Colors.white,
                minimumSize: const Size(44, 44),
              ),
              icon: const Icon(LucideIcons.x, size: 17),
            ),
          ),
        ],
      ),
    );
  }
}

class MediaAddButton extends StatelessWidget {
  final MediaDraft draft;
  final bool disabled;
  const MediaAddButton({super.key, required this.draft, this.disabled = false});
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: draft,
    builder: (context, _) => IconButton(
      tooltip: '添加图片或视频',
      onPressed:
          disabled ||
              draft.busy ||
              draft.choosing ||
              draft.items.length >= draft.api.policy.maxAttachments
          ? null
          : draft.choose,
      icon: draft.choosing
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 1.5),
            )
          : const Icon(LucideIcons.plus, size: 21),
    ),
  );
}

String formatMediaSize(int bytes) => bytes < 1024 * 1024
    ? '${(bytes / 1024).ceil()} KB'
    : '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
List<Data> attachmentsOf(Data data) =>
    (data['attachments'] as List? ?? []).map((e) => Data.from(e)).toList();
