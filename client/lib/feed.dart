import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'api.dart';
import 'design.dart';
import 'chat.dart';
import 'media_draft.dart';
import 'media_viewer.dart';

class FeedPage extends StatefulWidget {
  final Api api;
  final VoidCallback? onCompose;
  final String? filter, title;
  const FeedPage({
    super.key,
    required this.api,
    this.onCompose,
    this.filter,
    this.title,
  });
  @override
  State<FeedPage> createState() => _FeedPageState();
}

class _FeedPageState extends State<FeedPage> {
  List<String> get categories => ['全部', ...widget.api.policy.categories];
  late Future<List<Data>> future;
  String category = '全部', query = '';
  bool search = false;
  @override
  void initState() {
    super.initState();
    future = fetch();
  }

  Future<List<Data>> fetch() => widget.api.list(
    '/posts?${Uri(queryParameters: {if (category != '全部') 'category': category, if (query.isNotEmpty) 'q': query, if (widget.filter != null) widget.filter!: '1'}).query}',
  );
  Future<void> reload() async {
    setState(() {
      future = fetch();
    });
    try {
      await future;
    } catch (_) {
      /* FutureBuilder renders recovery. */
    }
  }

  Future<void> prompt(String text) async {
    final sent = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => ComposePage(api: widget.api, initialText: text),
      ),
    );
    if (sent == true && mounted) reload();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      toolbarHeight: 74,
      leading: widget.filter != null ? backButton(context) : null,
      title: widget.title != null
          ? Text(widget.title!)
          : const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                BrandMark(size: 28),
                SizedBox(width: 8),
                Text(
                  'sayAnything',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -.8,
                  ),
                ),
              ],
            ),
      actions: [
        IconButton(
          tooltip: '搜索帖子',
          onPressed: () => setState(() => search = !search),
          icon: const Icon(LucideIcons.search, size: 20),
        ),
        IconButton(
          tooltip: '刷新广场',
          onPressed: reload,
          icon: const Icon(LucideIcons.refreshCw, size: 19),
        ),
        const SizedBox(width: 8),
      ],
    ),
    body: RefreshIndicator(
      color: Colors.white70,
      backgroundColor: forest,
      onRefresh: reload,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          if (search)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                child: Glass(
                  strong: true,
                  radius: 22,
                  child: TextField(
                    autofocus: true,
                    decoration: const InputDecoration(
                      hintText: '搜索校园里的声音',
                      prefixIcon: Icon(LucideIcons.search, size: 18),
                      filled: false,
                    ),
                    textInputAction: TextInputAction.search,
                    onSubmitted: (v) {
                      query = v.trim();
                      reload();
                    },
                  ),
                ),
              ),
            ),
          if (widget.filter == null)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(
                          LucideIcons.school,
                          size: 13,
                          color: Colors.white38,
                        ),
                        const SizedBox(width: 7),
                        Expanded(
                          child: Text(
                            '${widget.api.user!['campus']} · 自选校园',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.white38,
                            ),
                          ),
                        ),
                        const Text(
                          '匿名交流',
                          style: TextStyle(fontSize: 12, color: Colors.white38),
                        ),
                      ],
                    ),
                    const SizedBox(height: 26),
                    const Text(
                      '不用想好怎么说。\n从一句话开始就好。',
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w500,
                        height: 1.55,
                        letterSpacing: -.5,
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      '心事、困惑，或者只是今天发生的小事。',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.white54,
                        height: 1.8,
                      ),
                    ),
                    const SizedBox(height: 23),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final text in [
                          '今天有点累',
                          '想找个自习搭子',
                          '有件事不知跟谁说',
                          '只是想随便聊聊',
                        ])
                          Glass(
                            radius: 22,
                            child: InkWell(
                              onTap: () => prompt(text),
                              borderRadius: BorderRadius.circular(22),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 15,
                                  vertical: 12,
                                ),
                                child: Text(
                                  text,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: Colors.white60,
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 22),
                    Glass(
                      strong: true,
                      radius: 27,
                      child: InkWell(
                        onTap: widget.onCompose,
                        borderRadius: BorderRadius.circular(27),
                        child: const Padding(
                          padding: EdgeInsets.symmetric(
                            horizontal: 18,
                            vertical: 17,
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  '想到哪里，说到哪里…',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: Colors.white38,
                                  ),
                                ),
                              ),
                              Icon(
                                LucideIcons.pencil,
                                size: 18,
                                color: Colors.white60,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton.icon(
                        onPressed: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => RoomsPage(api: widget.api),
                          ),
                        ),
                        icon: const Icon(LucideIcons.messagesSquare, size: 16),
                        label: const Text(
                          '话题房间',
                          style: TextStyle(fontSize: 12),
                        ),
                      ),
                    ),
                    const SectionTitle('校园里的声音', subtitle: '一些日常，一点心事。'),
                  ],
                ),
              ),
            ),
          SliverToBoxAdapter(
            child: SizedBox(
              height: 45,
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                scrollDirection: Axis.horizontal,
                itemCount: categories.length,
                separatorBuilder: (_, i) => const SizedBox(width: 7),
                itemBuilder: (_, i) => ChoiceChip(
                  label: Text(
                    categories[i],
                    style: TextStyle(
                      fontSize: 12,
                      color: category == categories[i]
                          ? Colors.white
                          : Colors.white38,
                    ),
                  ),
                  selected: category == categories[i],
                  showCheckmark: false,
                  onSelected: (_) {
                    category = categories[i];
                    reload();
                  },
                ),
              ),
            ),
          ),
          FutureBuilder<List<Data>>(
            future: future,
            builder: (context, s) {
              if (s.connectionState == ConnectionState.waiting) {
                return const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.all(50),
                    child: Center(
                      child: CircularProgressIndicator(strokeWidth: 1.5),
                    ),
                  ),
                );
              }
              if (s.hasError) {
                return SliverToBoxAdapter(
                  child: EmptyState(
                    '连接暂时中断',
                    s.error.toString(),
                    icon: LucideIcons.wifiOff,
                    action: TextButton(
                      onPressed: reload,
                      child: const Text('重新连接'),
                    ),
                  ),
                );
              }
              final items = s.data ?? [];
              if (items.isEmpty) {
                return SliverToBoxAdapter(
                  child: EmptyState(
                    query.isNotEmpty
                        ? '没找到相关内容。'
                        : widget.filter == 'saved'
                        ? '这里还没有收藏。'
                        : widget.filter == 'mine'
                        ? '这里还没有你的声音。'
                        : '这里，还在等第一句话。',
                    query.isNotEmpty ? '换个词试试看。' : '从一句话开始，也很好。',
                    action: widget.onCompose == null
                        ? null
                        : TextButton(
                            onPressed: widget.onCompose,
                            child: const Text('写下第一条心情'),
                          ),
                  ),
                );
              }
              return SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 80),
                sliver: SliverList.builder(
                  itemCount: items.length,
                  itemBuilder: (context, i) => PostCard(
                    api: widget.api,
                    post: items[i],
                    onChanged: reload,
                  ),
                ),
              );
            },
          ),
        ],
      ),
    ),
  );
}

class PostCard extends StatefulWidget {
  final Api api;
  final Data post;
  final VoidCallback? onChanged;
  final bool detail;
  const PostCard({
    super.key,
    required this.api,
    required this.post,
    this.onChanged,
    this.detail = false,
  });
  @override
  State<PostCard> createState() => _PostCardState();
}

class _PostCardState extends State<PostCard> {
  bool busy = false;
  Future<void> toggle(String action) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      final r = await widget.api.call(
        'POST',
        '/posts/${widget.post['id']}/$action',
      );
      if (mounted) {
        setState(() {
          if (action == 'like') {
            widget.post['likes'] =
                ((widget.post['likes'] ?? 0) + (r['active'] == true ? 1 : -1))
                    .clamp(0, 999999);
            widget.post['liked'] = r['active'];
          } else {
            widget.post['saved'] = r['active'];
          }
        });
      }
    } catch (e) {
      if (mounted) toast(context, e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> open() async {
    if (widget.detail) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PostDetail(api: widget.api, id: widget.post['id']),
      ),
    );
    widget.onChanged?.call();
  }

  Future<void> action(String value) async {
    final p = widget.post;
    if (value == 'report') {
      await reportContent(context, widget.api, 'post', p['id']);
      return;
    }
    if (value == 'block') {
      await blockUser(context, widget.api, p['authorId']);
      if (mounted) widget.onChanged?.call();
      return;
    }
    if (value == 'delete') {
      if (!await confirmAction(context, '删除这条声音？', '帖子和评论将永久删除。')) return;
      try {
        await widget.api.call('DELETE', '/posts/${p['id']}');
        widget.onChanged?.call();
        if (widget.detail && mounted) Navigator.pop(context);
      } catch (e) {
        if (mounted) toast(context, e);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.post;
    return Padding(
      padding: const EdgeInsets.only(bottom: 13),
      child: Glass(
        radius: 25,
        child: InkWell(
          onTap: widget.detail ? null : open,
          borderRadius: BorderRadius.circular(25),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 12, 7),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Avatar(p['avatar'] ?? 0, size: 33),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            p['alias'] ?? '匿名同学',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: Colors.white70,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${relativeTime(p['createdAt'])} · 校园匿名',
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.white30,
                            ),
                          ),
                        ],
                      ),
                    ),
                    PopupMenuButton<String>(
                      tooltip: '更多操作',
                      onSelected: action,
                      icon: const Icon(
                        LucideIcons.ellipsis,
                        size: 20,
                        color: Colors.white38,
                      ),
                      itemBuilder: (_) => [
                        if (p['authorId'] == widget.api.user!['id'])
                          const PopupMenuItem(
                            value: 'delete',
                            child: Text('删除帖子'),
                          )
                        else ...[
                          const PopupMenuItem(
                            value: 'report',
                            child: Text('举报内容'),
                          ),
                          const PopupMenuItem(
                            value: 'block',
                            child: Text('屏蔽这位同学'),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 15),
                if ('${p['body'] ?? ''}'.isNotEmpty)
                  Text(
                    p['body'] ?? '',
                    maxLines: widget.detail ? null : 7,
                    overflow: widget.detail ? null : TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 16,
                      height: 1.75,
                      color: Colors.white70,
                    ),
                  ),
                if (attachmentsOf(p).isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: MediaAttachmentList(
                      api: widget.api,
                      attachments: attachmentsOf(p),
                      compact: !widget.detail,
                    ),
                  ),
                const SizedBox(height: 14),
                Text(
                  '# ${p['category']}',
                  style: const TextStyle(fontSize: 12, color: Colors.white38),
                ),
                Row(
                  children: [
                    TextButton.icon(
                      onPressed: busy ? null : () => toggle('like'),
                      icon: Icon(
                        LucideIcons.heart,
                        size: 16,
                        color: p['liked'] == true
                            ? Colors.white
                            : Colors.white38,
                      ),
                      label: Text(
                        '${p['likes'] ?? 0}',
                        style: const TextStyle(
                          color: Colors.white38,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    TextButton.icon(
                      onPressed: widget.detail ? null : open,
                      icon: const Icon(
                        LucideIcons.messageCircle,
                        size: 16,
                        color: Colors.white38,
                      ),
                      label: Text(
                        '${p['comments'] ?? 0}',
                        style: const TextStyle(
                          color: Colors.white38,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      tooltip: p['saved'] == true ? '取消收藏' : '收藏声音',
                      onPressed: busy ? null : () => toggle('save'),
                      icon: Icon(
                        LucideIcons.bookmark,
                        size: 18,
                        color: p['saved'] == true
                            ? Colors.white
                            : Colors.white38,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class ComposePage extends StatefulWidget {
  final Api api;
  final String initialText;
  const ComposePage({super.key, required this.api, this.initialText = ''});
  @override
  State<ComposePage> createState() => _ComposePageState();
}

class _ComposePageState extends State<ComposePage> {
  late final body = TextEditingController(text: widget.initialText);
  late final media = MediaDraft(widget.api);
  late String category = widget.api.policy.categories.first;
  bool busy = false;
  @override
  void initState() {
    super.initState();
    media.addListener(_mediaChanged);
  }

  void _mediaChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    media
      ..removeListener(_mediaChanged)
      ..dispose();
    body.dispose();
    super.dispose();
  }

  Future<void> send() async {
    if (busy) return;
    if (body.text.trim().isEmpty && !media.isNotEmpty) {
      toast(context, '先写点什么，或添加图片、视频');
      return;
    }
    setState(() => busy = true);
    try {
      final ids = media.isNotEmpty ? await media.prepare() : <String>[];
      await widget.api.call('POST', '/posts', {
        'body': body.text.trim(),
        'category': category,
        if (ids.isNotEmpty) 'mediaIds': ids,
        'clientId': media.requestIdFor('${body.text.trim()}|$category'),
      });
      if (mounted) {
        media.clearSent();
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) toast(context, e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !busy,
    child: Scaffold(
      appBar: AppBar(
        leading: backButton(context),
        title: const Text('说点什么'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: FilledButton(
              onPressed: busy ? null : send,
              child: Text(busy ? '发布中…' : '发布'),
            ),
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 650),
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Row(
                children: [
                  Avatar(widget.api.user!['avatar'] ?? 0),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.api.user!['alias'],
                        style: const TextStyle(fontWeight: FontWeight.w500),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        '以匿名身份发布',
                        style: TextStyle(color: muted, fontSize: 12),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 24),
              TextField(
                controller: body,
                enabled: !busy,
                autofocus: true,
                maxLines: 10,
                minLines: 6,
                maxLength: widget.api.policy.postCharacters,
                style: const TextStyle(fontSize: 16, height: 1.75),
                decoration: const InputDecoration(
                  hintText: '今天发生了什么？\n或是，有什么一直想说的话…',
                  filled: false,
                  border: InputBorder.none,
                  focusedBorder: InputBorder.none,
                ),
              ),
              const Divider(),
              Row(
                children: [
                  MediaAddButton(draft: media, disabled: busy),
                  const SizedBox(width: 6),
                  const Text(
                    '添加图片或视频',
                    style: TextStyle(fontSize: 13, color: Colors.white60),
                  ),
                  const Spacer(),
                  Text(
                    '最多 ${widget.api.policy.maxAttachments} 个',
                    style: const TextStyle(fontSize: 11, color: Colors.white38),
                  ),
                ],
              ),
              MediaDraftPanel(draft: media, disabled: busy),
              const SizedBox(height: 5),
              const SectionTitle('给心情找个角落'),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final c in widget.api.policy.categories)
                    ChoiceChip(
                      label: Text(c),
                      selected: c == category,
                      onSelected: busy
                          ? null
                          : (_) => setState(() => category = c),
                    ),
                ],
              ),
              const SizedBox(height: 28),
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: sage,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(LucideIcons.shield, color: cream, size: 18),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        '匿名不是伤害的借口。\n保护彼此的隐私，让善意在校园里发生。',
                        style: TextStyle(
                          color: cream,
                          fontSize: 12,
                          height: 1.8,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class PostDetail extends StatefulWidget {
  final Api api;
  final String id;
  const PostDetail({super.key, required this.api, required this.id});
  @override
  State<PostDetail> createState() => _PostDetailState();
}

class _PostDetailState extends State<PostDetail> {
  late Future<List<dynamic>> future;
  final body = TextEditingController();
  late final media = MediaDraft(widget.api);
  bool busy = false;
  @override
  void initState() {
    super.initState();
    media.addListener(_mediaChanged);
    future = fetch();
  }

  void _mediaChanged() {
    if (mounted) setState(() {});
  }

  Future<List<dynamic>> fetch() => Future.wait([
    widget.api.call('GET', '/posts/${widget.id}'),
    widget.api.list('/posts/${widget.id}/comments'),
  ]);
  void reload() {
    setState(() {
      future = fetch();
    });
  }

  @override
  void dispose() {
    media
      ..removeListener(_mediaChanged)
      ..dispose();
    body.dispose();
    super.dispose();
  }

  Future<void> send() async {
    if (busy || (body.text.trim().isEmpty && !media.isNotEmpty)) return;
    final draft = body.text;
    setState(() => busy = true);
    try {
      final ids = media.isNotEmpty ? await media.prepare() : <String>[];
      await widget.api.call('POST', '/posts/${widget.id}/comments', {
        'body': draft.trim(),
        if (ids.isNotEmpty) 'mediaIds': ids,
        'clientId': media.requestIdFor(draft.trim()),
      });
      if (!mounted) return;
      if (body.text == draft) body.clear();
      media.clearSent();
      reload();
    } catch (e) {
      if (mounted) toast(context, e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(leading: backButton(context), title: const Text('这一刻的声音')),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 700),
        child: Column(
          children: [
            Expanded(
              child: FutureBuilder<List<dynamic>>(
                future: future,
                builder: (context, s) {
                  if (s.hasError) {
                    return EmptyState(
                      '声音暂时无法打开',
                      s.error.toString(),
                      action: TextButton(
                        onPressed: reload,
                        child: const Text('重试'),
                      ),
                    );
                  }
                  if (!s.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final p = s.data![0] as Data;
                  final comments = s.data![1] as List<Data>;
                  return ListView(
                    padding: const EdgeInsets.all(20),
                    children: [
                      PostCard(
                        api: widget.api,
                        post: p,
                        detail: true,
                        onChanged: reload,
                      ),
                      if (p['authorId'] != widget.api.user!['id'])
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton.icon(
                            onPressed: () async {
                              try {
                                final conv = await widget.api.call(
                                  'POST',
                                  '/conversations',
                                  {'postId': widget.id},
                                );
                                if (context.mounted) {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => ChatPage(
                                        api: widget.api,
                                        id: conv['id'],
                                        title: conv['alias'] ?? p['alias'],
                                        room: false,
                                      ),
                                    ),
                                  );
                                }
                              } catch (e) {
                                if (context.mounted) toast(context, e);
                              }
                            },
                            icon: const Icon(LucideIcons.hand, size: 17),
                            label: const Text(
                              '悄悄打个招呼',
                              style: TextStyle(fontSize: 12),
                            ),
                          ),
                        ),
                      SectionTitle('回声 · ${comments.length}'),
                      if (comments.isEmpty)
                        const EmptyState(
                          '给 TA 一点回声',
                          '一句温柔的回应，也许会点亮一天。',
                          icon: LucideIcons.messageCircle,
                        ),
                      for (final c in comments)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 23),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Avatar(c['avatar'] ?? 0, size: 34),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      c['alias'] ?? '匿名同学',
                                      style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                    const SizedBox(height: 7),
                                    if ('${c['body'] ?? ''}'.isNotEmpty)
                                      Text(
                                        c['body'],
                                        style: const TextStyle(
                                          height: 1.7,
                                          fontSize: 14,
                                        ),
                                      ),
                                    if (attachmentsOf(c).isNotEmpty)
                                      Padding(
                                        padding: const EdgeInsets.only(top: 8),
                                        child: MediaAttachmentList(
                                          api: widget.api,
                                          attachments: attachmentsOf(c),
                                          compact: true,
                                        ),
                                      ),
                                    const SizedBox(height: 7),
                                    Text(
                                      relativeTime(c['createdAt']),
                                      style: const TextStyle(
                                        color: muted,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 8, 18, 12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    MediaDraftPanel(draft: media, disabled: busy),
                    Glass(
                      strong: true,
                      radius: 28,
                      padding: const EdgeInsets.fromLTRB(4, 4, 7, 4),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          MediaAddButton(draft: media, disabled: busy),
                          Expanded(
                            child: TextField(
                              controller: body,
                              minLines: 1,
                              maxLines: 5,
                              maxLength: widget.api.policy.messageCharacters,
                              decoration: const InputDecoration(
                                hintText: '让 TA 知道，你在听…',
                                counterText: '',
                                filled: false,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          ValueListenableBuilder<TextEditingValue>(
                            valueListenable: body,
                            builder: (context, value, _) => IconButton.filled(
                              onPressed:
                                  busy ||
                                      (value.text.trim().isEmpty &&
                                          !media.isNotEmpty)
                                  ? null
                                  : send,
                              tooltip: '发送评论',
                              style: IconButton.styleFrom(
                                backgroundColor: Colors.white10,
                                foregroundColor: Colors.white,
                              ),
                              icon: busy
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 1.5,
                                      ),
                                    )
                                  : const Icon(LucideIcons.arrowUp),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

Future<bool> confirmAction(
  BuildContext context,
  String title,
  String description,
) async =>
    await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(title),
        content: Text(description),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('确认'),
          ),
        ],
      ),
    ) ??
    false;

Future<void> blockUser(BuildContext context, Api api, String id) async {
  if (!await confirmAction(
    context,
    '屏蔽这位同学？',
    '彼此将无法私聊，你也不会再看到 TA 的内容。可在「我的」中解除。',
  )) {
    return;
  }
  try {
    await api.call('POST', '/blocks', {'userId': id});
    if (context.mounted) toast(context, '已屏蔽这位同学');
  } catch (e) {
    if (context.mounted) toast(context, e);
  }
}

Future<void> reportContent(
  BuildContext context,
  Api api,
  String type,
  String id,
) async {
  final reason = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    builder: (c) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              '告诉我们，发生了什么？',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w500),
            ),
          ),
          for (final r in ['泄露他人隐私', '骚扰或人身攻击', '广告或垃圾内容', '违法或危险内容'])
            ListTile(
              title: Text(r),
              trailing: const Icon(LucideIcons.chevronRight),
              onTap: () => Navigator.pop(c, r),
            ),
          const SizedBox(height: 16),
        ],
      ),
    ),
  );
  if (reason == null) return;
  try {
    await api.call('POST', '/reports', {
      'targetType': type,
      'targetId': id,
      'reason': reason,
    });
    if (context.mounted) toast(context, '已收到举报，将由服务运营方处理');
  } catch (e) {
    if (context.mounted) toast(context, e);
  }
}
