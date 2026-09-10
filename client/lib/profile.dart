import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'api.dart';
import 'design.dart';
import 'feed.dart';

class ProfilePage extends StatelessWidget {
  final Api api;
  const ProfilePage({super.key, required this.api});
  Future<void> preference(
    BuildContext context, {
    bool? background,
    bool? reduce,
    double? scale,
  }) async {
    try {
      await api.setVisualOptions(
        background: background,
        reduce: reduce,
        scale: scale,
      );
    } catch (_) {
      if (context.mounted) toast(context, '设置暂时无法保存，请重试');
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = api.user!;
    return Scaffold(
      appBar: AppBar(toolbarHeight: 76, title: const Text('设置')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 2, 20, 26),
        children: [
          Glass(
            padding: const EdgeInsets.all(21),
            radius: 26,
            child: Row(
              children: [
                const Icon(LucideIcons.eyeOff, color: Colors.white60, size: 23),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '当前以匿名方式使用',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 7),
                      Text(
                        '${user['campus']} · 自选校园',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.white38,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 25),
          const _GroupLabel('聊天偏好'),
          _setting(
            LucideIcons.pencil,
            '匿名昵称',
            user['alias'],
            () => _rename(context),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            secondary: const Icon(
              LucideIcons.messageCircle,
              size: 20,
              color: Colors.white60,
            ),
            title: const Text('接收匿名私聊', style: TextStyle(fontSize: 14)),
            subtitle: const Text(
              '由你决定是否开始一段对话',
              style: TextStyle(fontSize: 12, color: Colors.white38),
            ),
            value: user['allowDM'] ?? true,
            onChanged: (v) async {
              try {
                await api.updateUser({'allowDM': v});
              } catch (e) {
                if (context.mounted) toast(context, e);
              }
            },
          ),
          _setting(
            LucideIcons.type,
            '文字大小',
            api.textScale < 1
                ? '小'
                : api.textScale > 1
                ? '大'
                : '标准',
            () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => TextSizePage(api: api)),
            ),
          ),
          const SizedBox(height: 22),
          const _GroupLabel('界面体验'),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            secondary: const Icon(
              LucideIcons.play,
              size: 20,
              color: Colors.white60,
            ),
            title: const Text('动态背景', style: TextStyle(fontSize: 14)),
            subtitle: const Text(
              '弱化的动态纹理，不打扰阅读',
              style: TextStyle(fontSize: 12, color: Colors.white38),
            ),
            value: api.dynamicBackground,
            onChanged: (v) => preference(context, background: v),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            secondary: const Icon(
              LucideIcons.feather,
              size: 20,
              color: Colors.white60,
            ),
            title: const Text('减少动态效果', style: TextStyle(fontSize: 14)),
            subtitle: const Text(
              '使用静态背景，减少界面动画',
              style: TextStyle(fontSize: 12, color: Colors.white38),
            ),
            value: api.reduceMotion,
            onChanged: (v) => preference(context, reduce: v),
          ),
          const SizedBox(height: 22),
          const _GroupLabel('隐私与应用'),
          _setting(
            LucideIcons.shield,
            '隐私与数据',
            null,
            () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => PrivacyPage(api: api)),
            ),
          ),
          _setting(
            LucideIcons.fileText,
            '我的发布',
            null,
            () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) =>
                    FeedPage(api: api, filter: 'mine', title: '我的发布'),
              ),
            ),
          ),
          _setting(
            LucideIcons.bookmark,
            '我的收藏',
            null,
            () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) =>
                    FeedPage(api: api, filter: 'saved', title: '我的收藏'),
              ),
            ),
          ),
          _setting(
            LucideIcons.info,
            '关于 sayAnything',
            null,
            () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const AboutPage()),
            ),
          ),
          _setting(
            LucideIcons.circleHelp,
            '使用说明',
            null,
            () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const AboutPage(help: true)),
            ),
          ),
          const SizedBox(height: 23),
          const Center(
            child: Text(
              'sayAnything · 1.2.0',
              style: TextStyle(
                fontSize: 12,
                color: Colors.white30,
                letterSpacing: .1,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _rename(BuildContext context) async {
    final controller = TextEditingController(text: api.user!['alias']);
    final value = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('修改匿名昵称'),
        content: TextField(
          controller: controller,
          maxLength: 24,
          autofocus: true,
          decoration: const InputDecoration(hintText: '取一个只属于这里的名字'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, controller.text.trim()),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 250));
    controller.dispose();
    if (value == null) return;
    if (value.isEmpty) {
      if (context.mounted) toast(context, '昵称不能为空');
      return;
    }
    try {
      await api.updateUser({'alias': value});
      if (context.mounted) toast(context, '昵称已更新');
    } catch (e) {
      if (context.mounted) toast(context, e);
    }
  }
}

class _GroupLabel extends StatelessWidget {
  final String label;
  const _GroupLabel(this.label);
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(
      label,
      style: const TextStyle(
        color: Colors.white38,
        fontSize: 12,
        letterSpacing: .4,
      ),
    ),
  );
}

Widget _setting(
  IconData icon,
  String title,
  String? value,
  VoidCallback onTap,
) => ListTile(
  contentPadding: EdgeInsets.zero,
  minLeadingWidth: 23,
  leading: Icon(icon, size: 20, color: Colors.white60),
  title: Text(title, style: const TextStyle(fontSize: 14)),
  trailing: Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      if (value != null)
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 120),
          child: Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12, color: Colors.white38),
          ),
        ),
      const SizedBox(width: 5),
      const Icon(LucideIcons.chevronRight, size: 17, color: Colors.white30),
    ],
  ),
  onTap: onTap,
);

class TextSizePage extends StatelessWidget {
  final Api api;
  const TextSizePage({super.key, required this.api});
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(leading: backButton(context), title: const Text('文字大小')),
    body: ListenableBuilder(
      listenable: api,
      builder: (context, _) => ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const SizedBox(height: 20),
          const Text(
            '按你舒服的方式阅读。',
            style: TextStyle(fontSize: 15, color: Colors.white60),
          ),
          const SizedBox(height: 24),
          Glass(
            padding: const EdgeInsets.all(24),
            child: const Text(
              '不用组织好语言，也可以开始。\n有些话，在这里慢慢说。',
              style: TextStyle(fontSize: 16, height: 1.8),
            ),
          ),
          const SizedBox(height: 27),
          Glass(
            padding: const EdgeInsets.all(6),
            child: Row(
              children: [
                for (final entry in [('小', .93), ('标准', 1.0), ('大', 1.12)])
                  Expanded(
                    child: TextButton(
                      onPressed: () async {
                        try {
                          await api.setVisualOptions(scale: entry.$2);
                        } catch (_) {
                          if (context.mounted) toast(context, '设置暂时无法保存');
                        }
                      },
                      style: TextButton.styleFrom(
                        backgroundColor: api.textScale == entry.$2
                            ? Colors.white10
                            : Colors.transparent,
                      ),
                      child: Text(
                        entry.$1,
                        style: TextStyle(
                          color: api.textScale == entry.$2
                              ? Colors.white
                              : Colors.white38,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          const Text(
            '同时尊重设备的系统文字缩放设置。',
            style: TextStyle(color: Colors.white38, fontSize: 12),
          ),
        ],
      ),
    ),
  );
}

class PrivacyPage extends StatelessWidget {
  final Api? api;
  const PrivacyPage({super.key, this.api});
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(leading: backButton(context), title: const Text('隐私与数据')),
    body: ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 35),
      children: [
        const Glass(
          padding: EdgeInsets.all(22),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(LucideIcons.shield, size: 22, color: Colors.white70),
              SizedBox(width: 15),
              Expanded(
                child: Text(
                  '自由表达，也温柔相待。\n匿名，不意味着没有边界。',
                  style: TextStyle(fontSize: 15, height: 1.9),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 29),
        const _GroupLabel('你的身份与内容'),
        const _PrivacyText(
          '关于匿名',
          '无需填写真实姓名或手机号。其他用户看到的是匿名昵称和你自行选择的学校；当前尚未验证学生身份。匿名面向其他用户，并非对服务运营方不可追溯。',
        ),
        const _PrivacyText(
          '聊天记录保存在哪里',
          '帖子、评论、私聊和话题房间消息保存在你连接的校园服务端。当前设备的安全存储中保存匿名登录凭据。关闭或卸载 App，不会自动删除服务端内容。',
        ),
        const _PrivacyText(
          '数据处理范围',
          '服务运营方能够访问服务器保存的内容，私聊不是端到端加密。请连接可信的 HTTPS 服务，不要分享敏感个人信息。动态背景会从指定视频服务加载；可以在设置中关闭。',
        ),
        const _PrivacyText(
          '图片与视频',
          '附件上传到当前校园服务，与对应帖子或消息共享访问范围。图片会重新编码并移除 EXIF 信息；视频不会重新编码，可能仍含原始元数据。不要上传他人的私人影像。删除帖子或身份时，关联附件一并清理。',
        ),
        const _PrivacyText(
          '社区约定',
          '不泄露他人的姓名、联系方式或照片，不骚扰、不人身攻击、不冒充他人。遇到不舒服的交流，可以举报和屏蔽。',
        ),
        if (api != null) ...[
          const SizedBox(height: 12),
          const Divider(),
          _setting(
            LucideIcons.eyeOff,
            '屏蔽管理',
            null,
            () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => BlockedPage(api: api!)),
            ),
          ),
          _setting(
            LucideIcons.server,
            '当前校园服务',
            null,
            () => showDialog(
              context: context,
              builder: (c) => AlertDialog(
                title: const Text('当前校园服务'),
                content: Text(
                  api!.origin,
                  style: const TextStyle(fontSize: 13),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(c),
                    child: const Text('知道了'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 15),
          const Divider(),
          _setting(LucideIcons.logOut, '离开当前匿名身份', null, () async {
            if (await confirmAction(
              context,
              '离开这个匿名身份？',
              '本地登录凭据将移除，下次进入会生成新身份。已有服务端内容不会删除，此身份无法恢复。',
            )) {
              await api!.logout();
              if (context.mounted) {
                Navigator.popUntil(context, (r) => r.isFirst);
              }
            }
          }),
          _setting(LucideIcons.trash2, '删除身份与发布内容', null, () async {
            if (!await confirmAction(
              context,
              '删除当前匿名身份？',
              '将向校园服务发送删除请求，永久删除此身份及其帖子、评论和消息。此操作无法恢复。',
            )) {
              return;
            }
            try {
              await api!.call('DELETE', '/me');
              await api!.logout();
              if (context.mounted) {
                Navigator.popUntil(context, (r) => r.isFirst);
              }
            } catch (e) {
              if (context.mounted) toast(context, e);
            }
          }),
        ],
      ],
    ),
  );
}

class _PrivacyText extends StatelessWidget {
  final String title, body;
  const _PrivacyText(this.title, this.body);
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 13),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
        ),
        const SizedBox(height: 10),
        Text(
          body,
          style: const TextStyle(
            fontSize: 13,
            color: Colors.white60,
            height: 1.95,
          ),
        ),
      ],
    ),
  );
}

class AboutPage extends StatelessWidget {
  final bool help;
  const AboutPage({super.key, this.help = false});
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      leading: backButton(context),
      title: Text(help ? '使用说明' : '关于 sayAnything'),
    ),
    body: ListView(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
      children: [
        const Center(child: BrandMark(size: 54)),
        const SizedBox(height: 18),
        const Text(
          'sayAnything',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.w600,
            letterSpacing: -.8,
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          '1.2.0',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.white38, fontSize: 12),
        ),
        const SizedBox(height: 25),
        const Text(
          '给那些暂时不知向谁说的话，\n一个开口的地方。',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 15, height: 1.9, color: Colors.white70),
        ),
        const SizedBox(height: 32),
        for (final item in [
          (
            '怎样发送图片或视频？',
            '点击输入栏旁的加号选择附件，可预览、移除，确认发送后才上传。支持 JPG、PNG、WebP 图片（单张 10 MB）及 MP4、WebM 视频（单个 50 MB）；每条最多 4 个附件，总计不超过 50 MB。视频能否播放取决于设备支持的编码，推荐 H.264 / AAC 的 MP4。',
          ),
          ('这里的聊天对象是谁？', '同一校园中使用这项服务的匿名用户。你可以在校园广场交流，也可以进入话题房间，或从帖子详情发起私聊。'),
          (
            '不实名也可以使用吗？',
            '可以。填写学校全称、阅读社区约定后，系统会创建一个匿名身份。不需要真实姓名、手机号、性别或生日。学校目前由用户自行选择。',
          ),
          (
            '如何开始一段对话？',
            '在聊天页发布一条心情，或点击「话题房间」加入同校聊天。看到让你共鸣的帖子，可以打开详情，点击「悄悄打个招呼」。',
          ),
          (
            '聊天记录保存在哪里？',
            '内容保存在连接的校园服务端。记录页展示当前匿名身份的私聊；广场帖子可在设置里的「我的发布」和「我的收藏」中查看。',
          ),
          (
            '如何删除记录？',
            '可以删除自己的帖子，或在「隐私与数据」中删除整个匿名身份及其发布内容。离开身份只移除本机凭据，不会同步删除服务端内容。',
          ),
        ])
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            childrenPadding: const EdgeInsets.only(bottom: 18),
            shape: const Border(),
            collapsedShape: const Border(),
            title: Text(item.$1, style: const TextStyle(fontSize: 14)),
            trailing: const Icon(
              LucideIcons.chevronDown,
              size: 17,
              color: Colors.white38,
            ),
            children: [
              Text(
                item.$2,
                style: const TextStyle(
                  fontSize: 13,
                  height: 1.95,
                  color: Colors.white60,
                ),
              ),
            ],
          ),
      ],
    ),
  );
}

class BlockedPage extends StatefulWidget {
  final Api api;
  const BlockedPage({super.key, required this.api});
  @override
  State<BlockedPage> createState() => _BlockedPageState();
}

class _BlockedPageState extends State<BlockedPage> {
  late Future<List<Data>> future;
  @override
  void initState() {
    super.initState();
    future = widget.api.list('/blocks');
  }

  void reload() {
    setState(() {
      future = widget.api.list('/blocks');
    });
    future.ignore();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(leading: backButton(context), title: const Text('屏蔽管理')),
    body: FutureBuilder<List<Data>>(
      future: future,
      builder: (context, s) {
        if (s.hasError) {
          return EmptyState(
            '暂时无法读取',
            s.error.toString(),
            action: TextButton(onPressed: reload, child: const Text('重试')),
          );
        }
        if (!s.hasData) {
          return const Center(child: CircularProgressIndicator(strokeWidth: 2));
        }
        if (s.data!.isEmpty) {
          return const EmptyState(
            '这里很安静',
            '你还没有屏蔽任何同学。',
            icon: LucideIcons.shield,
          );
        }
        return ListView(
          padding: const EdgeInsets.all(20),
          children: [
            for (final u in s.data!)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Avatar(u['avatar'] ?? 0, size: 36),
                title: Text(u['alias'], style: const TextStyle(fontSize: 14)),
                trailing: TextButton(
                  onPressed: () async {
                    try {
                      await widget.api.call('DELETE', '/blocks/${u['id']}');
                      reload();
                    } catch (e) {
                      if (context.mounted) toast(context, e);
                    }
                  },
                  child: const Text('解除屏蔽', style: TextStyle(fontSize: 12)),
                ),
              ),
          ],
        );
      },
    ),
  );
}
