import 'package:sayanything/policy.dart';

Map<String, dynamic> policyJson({int maxImageBytes = 10485760}) => {
  'categories': ['服务端分类'],
  'limits': {
    'postCharacters': 1000,
    'messageCharacters': 2000,
    'campusCharacters': 80,
    'aliasCharacters': 40,
  },
  'media': {
    'maxAttachments': 4,
    'maxImageBytes': maxImageBytes,
    'maxVideoBytes': 52428800,
    'maxTotalBytes': 52428800,
    'imageExtensions': ['jpg', 'jpeg', 'png', 'webp'],
    'videoExtensions': ['mp4', 'webm'],
  },
};
AppPolicy testPolicy() => AppPolicy.fromJson({
  ...policyJson(),
  'categories': ['校园日常', '心事树洞', '搭子集合', '恋爱碎碎念', '学习交流'],
});
