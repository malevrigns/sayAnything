import 'package:flutter_test/flutter_test.dart';
import 'package:file_selector/file_selector.dart';
import 'package:sayanything/api.dart';
import 'package:sayanything/media_draft.dart';
import 'dart:typed_data';
import 'package:flutter/material.dart';

class UploadApi extends Api {
  int uploads = 0;
  bool failSecond = true;
  @override
  Future<Data> uploadMedia(
    XFile file, {
    String? uploadId,
    void Function(int, int)? onProgress,
    dynamic cancelToken,
  }) async {
    uploads++;
    if (uploads == 2 && failSecond) throw ApiError('连接中断');
    return {
      'id': file.name,
      'kind': 'image',
      'mimeType': 'image/png',
      'size': 10,
      'name': file.name,
    };
  }
}

void main() {
  testWidgets('attachment removal stays locked during message submission', (
    tester,
  ) async {
    final draft = MediaDraft(UploadApi());
    await draft.addFiles([
      XFile.fromData(Uint8List(10), name: 'clip.mp4', path: 'clip.mp4'),
    ]);
    await draft.prepare();
    expect(draft.busy, isFalse);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: MediaDraftPanel(draft: draft, disabled: true)),
      ),
    );
    final remove = find.byTooltip('移除附件 1');
    await tester.tap(remove);
    expect(draft.items, hasLength(1));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: MediaDraftPanel(draft: draft)),
      ),
    );
    // The same control becomes available once the parent submission finishes.
    expect(
      tester.widget<IconButton>(find.byType(IconButton)).onPressed,
      isNotNull,
    );
    draft.clearSent();
    await tester.pumpWidget(const SizedBox());
    draft.dispose();
  });
  test(
    'media limits reject unsupported types and oversize files before reading',
    () {
      expect(MediaDraft.validateFile('a.svg', 100), isNotNull);
      expect(MediaDraft.validateFile('a.jpg', 11 * 1024 * 1024), isNotNull);
      expect(MediaDraft.validateFile('a.mp4', 51 * 1024 * 1024), isNotNull);
      expect(MediaDraft.validateFile('a.webp', 100), isNull);
      expect(MediaDraft.validateFile('a.webm', 100), isNull);
    },
  );
  test(
    'retry preserves successful upload ids and only uploads unfinished files',
    () async {
      final api = UploadApi();
      final draft = MediaDraft(api);
      await draft.addFiles([
        XFile.fromData(Uint8List(10), name: 'one.png', path: 'one.png'),
        XFile.fromData(Uint8List(10), name: 'two.png', path: 'two.png'),
      ]);
      await expectLater(draft.prepare(), throwsA(isA<ApiError>()));
      expect(draft.items.length, 2);
      api.failSecond = false;
      expect(await draft.prepare(), ['one.png', 'two.png']);
      expect(api.uploads, 3);
      final key = draft.requestIdFor('hello');
      expect(draft.requestIdFor('hello'), key);
      draft.clearSent();
      expect(draft.items, isEmpty);
      draft.dispose();
    },
  );
}
