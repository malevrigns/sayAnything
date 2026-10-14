/// Decoded server policy, used only for presentation and early input hints.
/// Go validates every write independently of these values.
class AppPolicy {
  final List<String> categories, imageExtensions, videoExtensions;
  final int postCharacters,
      messageCharacters,
      campusCharacters,
      aliasCharacters;
  final int maxAttachments, maxImageBytes, maxVideoBytes, maxTotalBytes;

  /// Discover profile hints. Older servers omit them, so every value falls
  /// back to a safe default instead of failing the whole policy.
  final int bioCharacters, maxTags, dailyLikes;
  final List<String> tags;
  final List<({String id, String label})> grades;

  AppPolicy.fromJson(Map<String, dynamic> json)
    : this._(json, _section(json['profile']), _section(json['discover']));

  AppPolicy._(
    Map<String, dynamic> json,
    Map<String, dynamic> profile,
    Map<String, dynamic> discover,
  ) : categories = _strings(json['categories']),
      imageExtensions = _strings(json['media']['imageExtensions']),
      videoExtensions = _strings(json['media']['videoExtensions']),
      postCharacters = _positive(json['limits']['postCharacters']),
      messageCharacters = _positive(json['limits']['messageCharacters']),
      campusCharacters = _positive(json['limits']['campusCharacters']),
      aliasCharacters = _positive(json['limits']['aliasCharacters']),
      maxAttachments = _positive(json['media']['maxAttachments']),
      maxImageBytes = _positive(json['media']['maxImageBytes']),
      maxVideoBytes = _positive(json['media']['maxVideoBytes']),
      maxTotalBytes = _positive(json['media']['maxTotalBytes']),
      bioCharacters = _optionalPositive(profile['bioCharacters'], 120),
      maxTags = _optionalPositive(profile['maxTags'], 5),
      tags = _optionalStrings(profile['tags']),
      grades = _grades(profile['grades']),
      dailyLikes = _optionalPositive(discover['dailyLikes'], 50);

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

  static Map<String, dynamic> _section(dynamic value) =>
      value is Map ? Map<String, dynamic>.from(value) : const {};

  static int _optionalPositive(dynamic value, int fallback) =>
      value is int && value > 0 ? value : fallback;

  static List<String> _optionalStrings(dynamic value) => value is List
      ? List<String>.unmodifiable(
          value.whereType<String>().where((v) => v.isNotEmpty),
        )
      : const [];

  static List<({String id, String label})> _grades(dynamic value) {
    if (value is! List) return const [];
    return List.unmodifiable([
      for (final entry in value)
        if (entry is Map &&
            entry['id'] is String &&
            (entry['id'] as String).isNotEmpty &&
            entry['label'] is String &&
            (entry['label'] as String).isNotEmpty)
          (id: entry['id'] as String, label: entry['label'] as String),
    ]);
  }

  /// Display label for a grade id: null when unset, the server label when
  /// known, otherwise the raw id so stale data still shows something.
  String? gradeLabel(dynamic id) {
    final key = id?.toString() ?? '';
    if (key.isEmpty) return null;
    for (final grade in grades) {
      if (grade.id == key) return grade.label;
    }
    return key;
  }

  String get formatHint =>
      '${imageExtensions.join(" / ").toUpperCase()} 图片、${videoExtensions.join(" / ").toUpperCase()} 视频';
}
