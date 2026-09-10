import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dio/dio.dart' as dio;
import 'package:file_selector/file_selector.dart';

typedef Data = Map<String, dynamic>;

class ApiError implements Exception {
  final String message;
  final int status;
  ApiError(this.message, [this.status = 0]);
  @override
  String toString() => message;
}

class Api extends ChangeNotifier {
  static const _vault = FlutterSecureStorage(
    wOptions: WindowsOptions(useBackwardCompatibility: false),
  );
  String origin = const String.fromEnvironment('API_URL', defaultValue: '');
  String? token;
  Data? user;
  bool dark = false;
  bool dynamicBackground = true;
  bool reduceMotion = false;
  double textScale = 1;
  final Map<String, ({String url, DateTime expires})> _mediaTickets = {};
  Api() {
    if (origin.isEmpty) {
      origin = !kIsWeb && defaultTargetPlatform == TargetPlatform.android
          ? 'http://10.0.2.2:8080'
          : 'http://localhost:8080';
    }
  }

  static bool validOrigin(String value) {
    final uri = Uri.tryParse(value);
    return uri != null &&
        ['http', 'https'].contains(uri.scheme) &&
        uri.host.isNotEmpty &&
        uri.userInfo.isEmpty &&
        !uri.hasQuery &&
        !uri.hasFragment &&
        (uri.path.isEmpty || uri.path == '/');
  }

  Future<void> restore() async {
    final prefs = await SharedPreferences.getInstance();
    origin = prefs.getString('origin') ?? origin;
    dark = prefs.getBool('dark') ?? false;
    dynamicBackground = prefs.getBool('visual.background') ?? true;
    reduceMotion = prefs.getBool('visual.reduce') ?? false;
    textScale = (prefs.getDouble('visual.scale') ?? 1).clamp(.93, 1.12);
    token = await _vault.read(key: 'session:$origin');
    if (token != null) {
      try {
        user = Data.from(await call('GET', '/me'));
      } on ApiError catch (e) {
        if (e.status == 401) {
          await logout();
        } else {
          rethrow;
        }
      }
    }
    notifyListeners();
  }

  Future<void> connect(String url, String campus) async {
    _mediaTickets.clear();
    url = url.trim().replaceFirst(RegExp(r'/$'), '');
    if (!validOrigin(url)) {
      throw ApiError('请输入有效的服务地址，例如 https://chat.example.com');
    }
    origin = url;
    token = await _vault.read(key: 'session:$origin');
    if (token != null) {
      try {
        final existing = Data.from(await call('GET', '/me'));
        await (await SharedPreferences.getInstance()).setString(
          'origin',
          origin,
        );
        user = existing;
        notifyListeners();
        return;
      } on ApiError catch (e) {
        if (e.status != 401) rethrow;
        await _vault.delete(key: 'session:$origin');
        token = null;
      }
    }
    final result = await call('POST', '/session', {'campus': campus.trim()});
    token = result['token'];
    user = Data.from(result['user']);
    await _vault.write(key: 'session:$origin', value: token);
    await (await SharedPreferences.getInstance()).setString('origin', origin);
    notifyListeners();
  }

  Future<dynamic> call(String method, String path, [Data? data]) async {
    final request = http.Request(method, Uri.parse('$origin/api/v1$path'));
    request.headers['Content-Type'] = 'application/json';
    if (token != null) {
      request.headers['Authorization'] = 'Bearer $token';
    }
    if (data != null) {
      request.body = jsonEncode(data);
    }
    try {
      final response = await http.Response.fromStream(
        await request.send().timeout(const Duration(seconds: 12)),
      ).timeout(const Duration(seconds: 12));
      final dynamic decoded = response.body.isEmpty
          ? <String, dynamic>{}
          : jsonDecode(utf8.decode(response.bodyBytes));
      if (response.statusCode >= 400) {
        throw ApiError(
          decoded is Map
              ? decoded['error']?.toString() ?? '请求失败，请重试'
              : '服务暂时不可用',
          response.statusCode,
        );
      }
      return decoded;
    } on ApiError {
      rethrow;
    } on TimeoutException {
      throw ApiError('连接超时，内容已保留，请稍后重试');
    } catch (_) {
      throw ApiError('暂时连接不上校园，请检查网络和服务地址');
    }
  }

  Future<List<Data>> list(String path) async =>
      (await call('GET', path) as List).map((e) => Data.from(e)).toList();

  Future<Data> uploadMedia(
    XFile file, {
    String? uploadId,
    void Function(int, int)? onProgress,
    dio.CancelToken? cancelToken,
  }) async {
    final length = await file.length();
    if (length > 50 * 1024 * 1024) throw ApiError('文件不能超过 50 MB');
    final capturedToken = token;
    final client = dio.Dio(
      dio.BaseOptions(
        connectTimeout: const Duration(seconds: 15),
        sendTimeout: const Duration(minutes: 5),
        receiveTimeout: const Duration(seconds: 60),
        headers: {
          'Authorization': 'Bearer $capturedToken',
          'X-Upload-Id': ?uploadId,
        },
      ),
    );
    try {
      final form = dio.FormData.fromMap({
        'file': dio.MultipartFile.fromStream(
          file.openRead,
          length,
          filename: file.name,
        ),
      });
      final response = await client.post(
        '$origin/api/v1/media',
        data: form,
        onSendProgress: onProgress,
        cancelToken: cancelToken,
      );
      if (token != capturedToken) throw ApiError('匿名身份已变更，请重新选择附件');
      if (response.data is! Map) throw ApiError('上传结果异常，请重试');
      final media = Data.from(response.data);
      if (media['id'] is! String ||
          !['image', 'video'].contains(media['kind'])) {
        throw ApiError('上传结果异常，请重试');
      }
      return media;
    } on dio.DioException catch (e) {
      if (dio.CancelToken.isCancel(e)) throw ApiError('已取消上传，附件仍在草稿中');
      final body = e.response?.data;
      if (body is Map && body['error'] is String) {
        throw ApiError(body['error'], e.response?.statusCode ?? 0);
      }
      throw ApiError('上传暂时中断，附件和文字还在，请重试');
    } finally {
      client.close(force: true);
    }
  }

  Future<String> mediaUrl(String id, {bool refresh = false}) async {
    final key = '$origin/$id';
    final cached = _mediaTickets[key];
    if (!refresh &&
        cached != null &&
        cached.expires.isAfter(
          DateTime.now().add(const Duration(seconds: 30)),
        )) {
      return cached.url;
    }
    final capturedToken = token;
    final result = await call('POST', '/media/$id/ticket', {});
    if (token != capturedToken) throw ApiError('匿名身份已变更');
    final base = Uri.parse(origin);
    final url = base.resolve(result['url'] as String);
    if (url.origin != base.origin || !url.path.startsWith('/api/v1/media/')) {
      throw ApiError('媒体链接无效');
    }
    final expires =
        DateTime.tryParse('${result['expiresAt']}') ??
        DateTime.now().add(const Duration(minutes: 1));
    _mediaTickets[key] = (url: url.toString(), expires: expires);
    return url.toString();
  }

  Future<void> updateUser(Data data) async {
    user = Data.from(await call('PATCH', '/me', data));
    notifyListeners();
  }

  Future<void> setDark(bool value) async {
    dark = value;
    await (await SharedPreferences.getInstance()).setBool('dark', value);
    notifyListeners();
  }

  Future<void> setVisualOptions({
    bool? background,
    bool? reduce,
    double? scale,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    if (background != null) {
      dynamicBackground = background;
      await prefs.setBool('visual.background', background);
    }
    if (reduce != null) {
      reduceMotion = reduce;
      await prefs.setBool('visual.reduce', reduce);
    }
    if (scale != null) {
      textScale = scale.clamp(.93, 1.12);
      await prefs.setDouble('visual.scale', textScale);
    }
    notifyListeners();
  }

  Future<void> logout() async {
    _mediaTickets.clear();
    await _vault.delete(key: 'session:$origin');
    token = null;
    user = null;
    notifyListeners();
  }
}
