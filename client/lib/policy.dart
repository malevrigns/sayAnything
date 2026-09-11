/// Decoded server policy, used only for presentation and early input hints.
/// Go validates every write independently of these values.
class AppPolicy {
  final List<String> categories, imageExtensions, videoExtensions;
  final int postCharacters,
      messageCharacters,
      campusCharacters,
      aliasCharacters;
  final int maxAttachments, maxImageBytes, maxVideoBytes, maxTotalBytes;

  AppPolicy.fromJson(Map<String, dynamic> json)
    : categories = _strings(json['categories']),
      imageExtensions = _strings(json['media']['imageExtensions']),
      videoExtensions = _strings(json['media']['videoExtensions']),
      postCharacters = _positive(json['limits']['postCharacters']),
      messageCharacters = _positive(json['limits']['messageCharacters']),
      campusCharacters = _positive(json['limits']['campusCharacters']),
      aliasCharacters = _positive(json['limits']['aliasCharacters']),
      maxAttachments = _positive(json['media']['maxAttachments']),
      maxImageBytes = _positive(json['media']['maxImageBytes']),
      maxVideoBytes = _positive(json['media']['maxVideoBytes']),
      maxTotalBytes = _positive(json['media']['maxTotalBytes']);

  static int _positive(dynamic value) {
    if (value is! int || value <= 0) {
      throw const FormatException('Invalid limit');
    }
    return value;
  }

  static List<String> _strings(dynamic value) {
    if (value is! List ||
        value.isEmpty ||
        value.any((v) => v is! String || v.isEmpty)) {
      throw const FormatException('Invalid policy list');
    }
    return List<String>.unmodifiable(value);
  }

  String get formatHint =>
      '${imageExtensions.join(" / ").toUpperCase()} 图片、${videoExtensions.join(" / ").toUpperCase()} 视频';
}
