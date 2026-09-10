import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'api.dart';
import 'design.dart';
import 'media_draft.dart';
import 'media_viewer.dart';
import 'feed.dart';

class RoomsPage extends StatefulWidget {
  final Api api;
  const RoomsPage({super.key, required this.api});
  @override
  State<RoomsPage> createState() => _RoomsPageState();
}

class _RoomsPageState extends State<RoomsPage> {
  late Future<List<Data>> future;
  @override
  void initState() {
    super.initState();
    future = widget.api.list('/rooms');
  }

  Future<void> reload() async {
    setState(() {
      future = widget.api.list('/rooms');
    });
    try {
      await future;
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('话题房间'),
      actions: [
        IconButton(
          onPressed: reload,
          tooltip: '刷新房间',
          icon: const Icon(LucideIcons.refreshCw, size: 20),
        ),
      ],
    ),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: RefreshIndicator(
          onRefresh: reload,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(18, 8, 18, 32),
            children: [
              const Glass(
                padding: EdgeInsets.all(18),
                child: Row(
                  children: [
                    Icon(LucideIcons.messagesSquare, size: 24),
                    SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '同校正在聊',
                            style: TextStyle(fontWeight: FontWeight.w500),
                          ),
                          SizedBox(height: 4),
                          Text(
                            '话题是开场白，消息对本校成员可见。',
                            style: TextStyle(color: muted, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SectionTitle('全部房间', subtitle: '选择一个话题加入对话'),
              FutureBuilder<List<Data>>(
                future: future,
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return EmptyState(
                      '暂时打不开房间',
                      snapshot.error.toString(),
                      icon: LucideIcons.circleAlert,
                      action: TextButton(
                        onPressed: reload,
                        child: const Text('重试'),
                      ),
                    );
                  }
                  if (!snapshot.hasData) {
                    return const Center(
                      child: Padding(
                        padding: EdgeInsets.all(48),
                        child: CircularProgressIndicator(),
                      ),
                    );
                  }
                  if (snapshot.data!.isEmpty) {
                    return const EmptyState(
                      '还没有开放的房间',
                      '稍后回来看看。',
                      icon: LucideIcons.messageCircle,
                    );
                  }
                  return Column(
                    children: [
                      for (var i = 0; i < snapshot.data!.length; i++)
                        _room(snapshot.data![i], i),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    ),
  );

  Widget _room(Data room, int index) {
    const icons = [
      LucideIcons.coffee,
      LucideIcons.bookOpen,
      LucideIcons.headphones,
      LucideIcons.users,
    ];
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: Colors.white.withValues(alpha: .055),
        borderRadius: BorderRadius.circular(20),
        child: ListTile(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 9,
          ),
          leading: Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: .065),
              borderRadius: BorderRadius.circular(15),
              border: Border.all(color: Colors.white12),
            ),
            child: Icon(icons[index % icons.length], size: 21),
          ),
          title: Text(
            room['name'] ?? '未命名房间',
            style: const TextStyle(fontWeight: FontWeight.w500),
          ),
          subtitle: Text(
            '${room['description'] ?? ''}\n${room['messages'] ?? 0} 条消息',
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: muted, fontSize: 12),
          ),
          trailing: const Icon(
            LucideIcons.chevronRight,
            color: muted,
            size: 18,
          ),
          onTap: () async {
            await Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => ChatPage(
                  api: widget.api,
                  id: room['id'],
                  title: room['name'],
                  room: true,
                ),
              ),
            );
            reload();
          },
        ),
      ),
    );
  }
}

class InboxPage extends StatefulWidget {
  final Api api;
  final VoidCallback? onNew;
  const InboxPage({super.key, required this.api, this.onNew});
  @override
  State<InboxPage> createState() => _InboxPageState();
}

class _InboxPageState extends State<InboxPage> with WidgetsBindingObserver {
  List<Data>? conversations;
  String? error;
  Timer? timer;
  bool fetching = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    load();
    timer = Timer.periodic(const Duration(seconds: 5), (_) => load());
  }

  @override
  void dispose() {
    timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      load();
      timer ??= Timer.periodic(const Duration(seconds: 5), (_) => load());
    } else {
      timer?.cancel();
      timer = null;
    }
  }

  Future<void> load() async {
    if (fetching) return;
    fetching = true;
    try {
      final list = await widget.api.list('/conversations');
      if (mounted) {
        setState(() {
          conversations = list;
          error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      fetching = false;
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('聊天记录'),
      actions: [
        IconButton(
          onPressed: conversations == null
              ? null
              : () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        _SearchPage(api: widget.api, items: conversations!),
                  ),
                ).then((_) => load()),
          tooltip: '搜索聊天记录',
          icon: const Icon(LucideIcons.search, size: 20),
        ),
        IconButton(
          onPressed: load,
          tooltip: '刷新消息',
          icon: const Icon(LucideIcons.refreshCw, size: 20),
        ),
      ],
    ),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: RefreshIndicator(
          onRefresh: load,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(18, 8, 18, 34),
            children: [
              const Glass(
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 13),
                child: Row(
                  children: [
                    Icon(LucideIcons.shield, color: muted, size: 18),
                    SizedBox(width: 11),
                    Expanded(
                      child: Text(
                        '请保护个人信息，尊重彼此的匿名边界。',
                        style: TextStyle(color: muted, fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
              if (error != null) _ErrorPane(message: error!, onRetry: load),
              if (conversations == null && error == null)
                const Padding(
                  padding: EdgeInsets.all(52),
                  child: Center(child: CircularProgressIndicator()),
                ),
              if (conversations?.isEmpty == true)
                EmptyState(
                  '还没有聊天记录',
                  '在校园广场遇到想聊的人，可以匿名打个招呼。',
                  icon: LucideIcons.messageCircle,
                  action: widget.onNew == null
                      ? null
                      : TextButton(
                          onPressed: widget.onNew,
                          child: const Text('去校园广场'),
                        ),
                ),
              ..._groups(),
            ],
          ),
        ),
      ),
    ),
  );

  List<Widget> _groups() {
    final groups = <String, List<Data>>{};
    for (final item in conversations ?? const <Data>[]) {
      (groups[_dateGroup(item['updatedAt'])] ??= []).add(item);
    }
    return [
      for (final label in ['今天', '昨天', '更早'])
        if (groups[label]?.isNotEmpty == true) ...[
          SectionTitle(label),
          ...groups[label]!.map(_tile),
        ],
    ];
  }

  Widget _tile(Data item) => Padding(
    padding: const EdgeInsets.only(bottom: 7),
    child: Material(
      color: Colors.white.withValues(alpha: .045),
      borderRadius: BorderRadius.circular(18),
      child: ListTile(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 15, vertical: 7),
        leading: _AnonymousMark(index: item['avatar'] ?? 0),
        title: Row(
          children: [
            Expanded(
              child: Text(
                item['alias'] ?? '匿名同学',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w500),
              ),
            ),
            Text(
              relativeTime(item['updatedAt']),
              style: const TextStyle(color: muted, fontSize: 12),
            ),
          ],
        ),
        subtitle: Text(
          _preview(item),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: muted, fontSize: 12),
        ),
        trailing: (item['unread'] ?? 0) > 0
            ? Semantics(
                label: '${item['unread']} 条未读消息',
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white12,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${item['unread']}',
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              )
            : null,
        onTap: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => ChatPage(
                api: widget.api,
                id: item['id'],
                title: item['alias'] ?? '匿名同学',
                room: false,
              ),
            ),
          );
          load();
        },
      ),
    ),
  );
}

class _SearchPage extends StatefulWidget {
  final Api api;
  final List<Data> items;
  const _SearchPage({required this.api, required this.items});
  @override
  State<_SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<_SearchPage> {
  String query = '';
  @override
  Widget build(BuildContext context) {
    final needle = query.trim().toLowerCase();
    final matches = widget.items
        .where(
          (item) =>
              needle.isEmpty ||
              '${item['alias'] ?? ''}'.toLowerCase().contains(needle) ||
              '${item['lastMessage'] ?? ''}'.toLowerCase().contains(needle),
        )
        .toList();
    return Scaffold(
      appBar: AppBar(title: const Text('搜索聊天记录')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 8, 18, 0),
            child: Column(
              children: [
                Glass(
                  strong: true,
                  radius: 18,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: TextField(
                    autofocus: true,
                    onChanged: (value) => setState(() => query = value),
                    decoration: const InputDecoration(
                      icon: Icon(LucideIcons.search, size: 19),
                      hintText: '搜索昵称或最近消息',
                      border: InputBorder.none,
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Expanded(
                  child: matches.isEmpty
                      ? const EmptyState(
                          '没有找到相关聊天',
                          '换个昵称或消息关键词试试。',
                          icon: LucideIcons.searchX,
                        )
                      : ListView.builder(
                          itemCount: matches.length,
                          itemBuilder: (context, i) {
                            final item = matches[i];
                            return ListTile(
                              leading: _AnonymousMark(
                                index: item['avatar'] ?? 0,
                              ),
                              title: Text(
                                item['alias'] ?? '匿名同学',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              subtitle: Text(
                                _preview(item),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              onTap: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => ChatPage(
                                    api: widget.api,
                                    id: item['id'],
                                    title: item['alias'] ?? '匿名同学',
                                    room: false,
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class ChatPage extends StatefulWidget {
  final Api api;
  final String id, title;
  final bool room;
  const ChatPage({
    super.key,
    required this.api,
    required this.id,
    required this.title,
    required this.room,
  });
  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> with WidgetsBindingObserver {
  List<Data>? messages;
  String? error;
  bool sending = false, fetching = false, showLatest = false;
  Timer? timer;
  final body = TextEditingController(), scroll = ScrollController();
  late final media = MediaDraft(widget.api);
  String get path =>
      '/${widget.room ? 'rooms' : 'conversations'}/${widget.id}/messages';
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    body.addListener(_draftChanged);
    media.addListener(_draftChanged);
    scroll.addListener(_scrollChanged);
    load();
    timer = Timer.periodic(const Duration(seconds: 3), (_) => load());
  }

  @override
  void dispose() {
    timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    media
      ..removeListener(_draftChanged)
      ..dispose();
    body
      ..removeListener(_draftChanged)
      ..dispose();
    scroll
      ..removeListener(_scrollChanged)
      ..dispose();
    super.dispose();
  }

  void _draftChanged() {
    if (mounted) setState(() {});
  }

  void _scrollChanged() {
    if (!scroll.hasClients) return;
    final value = scroll.position.maxScrollExtent - scroll.offset > 130;
    if (value != showLatest && mounted) setState(() => showLatest = value);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      load();
      timer ??= Timer.periodic(const Duration(seconds: 3), (_) => load());
    } else {
      timer?.cancel();
      timer = null;
    }
  }

  String? _lastId(List<Data>? list) =>
      list == null || list.isEmpty ? null : '${list.last['id']}';
  Future<void> load({bool forceScroll = false}) async {
    if (fetching) return;
    fetching = true;
    final nearBottom =
        !scroll.hasClients ||
        scroll.position.maxScrollExtent - scroll.offset < 100;
    final oldLastId = _lastId(messages);
    try {
      final list = await widget.api.list(path);
      if (!mounted) return;
      final changed = oldLastId != _lastId(list);
      setState(() {
        messages = list;
        error = null;
        if (changed && !nearBottom && !forceScroll) showLatest = true;
      });
      if (forceScroll || changed && nearBottom) _scrollToLatest();
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      fetching = false;
    }
  }

  void _scrollToLatest() => WidgetsBinding.instance.addPostFrameCallback((_) {
    if (!mounted || !scroll.hasClients) return;
    scroll.animateTo(
      scroll.position.maxScrollExtent,
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOut,
    );
    if (showLatest) setState(() => showLatest = false);
  });
  Future<void> send() async {
    if (sending || (body.text.trim().isEmpty && !media.isNotEmpty)) return;
    final draft = body.text;
    setState(() => sending = true);
    try {
      final ids = media.isNotEmpty ? await media.prepare() : <String>[];
      await widget.api.call('POST', path, {
        'body': draft.trim(),
        if (ids.isNotEmpty) 'mediaIds': ids,
        'clientId': media.requestIdFor(draft.trim()),
      });
      if (!mounted) return;
      if (body.text == draft) body.clear();
      media.clearSent();
      await load(forceScroll: true);
    } catch (e) {
      if (mounted) toast(context, e);
    } finally {
      if (mounted) setState(() => sending = false);
    }
  }

  Future<void> _actions(Data message, bool mine) async =>
      showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        builder: (sheet) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(LucideIcons.copy),
                title: const Text('复制消息'),
                onTap: () async {
                  Navigator.pop(sheet);
                  await Clipboard.setData(
                    ClipboardData(text: '${message['body']}'),
                  );
                  if (mounted) toast(context, '已复制');
                },
              ),
              if (!mine)
                ListTile(
                  leading: const Icon(LucideIcons.flag),
                  title: const Text('举报这条消息'),
                  onTap: () {
                    Navigator.pop(sheet);
                    reportContent(
                      context,
                      widget.api,
                      'message',
                      message['id'],
                    );
                  },
                ),
              if (!mine)
                ListTile(
                  leading: const Icon(LucideIcons.ban),
                  title: const Text('屏蔽这位同学'),
                  onTap: () async {
                    Navigator.pop(sheet);
                    await blockUser(context, widget.api, message['authorId']);
                    if (mounted) load();
                  },
                ),
            ],
          ),
        ),
      );

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.black.withValues(alpha: .2),
    appBar: AppBar(
      titleSpacing: 0,
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w500),
          ),
          const Text('校园匿名对话', style: TextStyle(fontSize: 12, color: muted)),
        ],
      ),
      actions: [
        IconButton(
          onPressed: load,
          tooltip: '刷新对话',
          icon: const Icon(LucideIcons.refreshCw, size: 19),
        ),
      ],
    ),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Column(
          children: [
            if (error != null) _ErrorPane(message: error!, onRetry: load),
            Expanded(
              child: Stack(
                children: [
                  Positioned.fill(child: _messageList()),
                  if (showLatest)
                    Positioned(
                      right: 18,
                      bottom: 12,
                      child: Glass(
                        radius: 22,
                        padding: EdgeInsets.zero,
                        child: IconButton(
                          onPressed: _scrollToLatest,
                          tooltip: '回到最新消息',
                          icon: const Icon(LucideIcons.arrowDown, size: 19),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            _composer(),
          ],
        ),
      ),
    ),
  );

  Widget _messageList() {
    if (messages == null) {
      return error == null
          ? const Center(child: CircularProgressIndicator())
          : const SizedBox();
    }
    if (messages!.isEmpty) {
      return const Center(
        child: EmptyState(
          '还没有消息',
          '发一句问候，让对话开始吧。',
          icon: LucideIcons.messageCircle,
        ),
      );
    }
    return ListView.builder(
      controller: scroll,
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 24),
      itemCount: messages!.length,
      itemBuilder: (context, i) {
        final message = messages![i];
        final mine = message['authorId'] == widget.api.user?['id'];
        return Align(
          alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.sizeOf(context).width.clamp(0, 480) * .82,
            ),
            margin: const EdgeInsets.only(bottom: 15),
            child: Column(
              crossAxisAlignment: mine
                  ? CrossAxisAlignment.end
                  : CrossAxisAlignment.start,
              children: [
                if (!mine && widget.room)
                  Padding(
                    padding: const EdgeInsets.only(left: 4, bottom: 5),
                    child: Text(
                      message['alias'] ?? '匿名同学',
                      style: const TextStyle(color: muted, fontSize: 12),
                    ),
                  ),
                if ('${message['body'] ?? ''}'.isNotEmpty)
                  Semantics(
                    label:
                        '${mine ? '我' : '对方'}：${message['body'] ?? ''}${attachmentsOf(message).isNotEmpty ? '，含图片或视频附件' : ''}',
                    excludeSemantics: true,
                    onLongPress: () => _actions(message, mine),
                    child: GestureDetector(
                      onLongPress: () => _actions(message, mine),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 11,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(
                            alpha: mine ? .10 : .055,
                          ),
                          borderRadius: BorderRadius.only(
                            topLeft: const Radius.circular(19),
                            topRight: const Radius.circular(19),
                            bottomLeft: Radius.circular(mine ? 19 : 5),
                            bottomRight: Radius.circular(mine ? 5 : 19),
                          ),
                          border: Border.all(
                            color: Colors.white.withValues(
                              alpha: mine ? .12 : .08,
                            ),
                          ),
                        ),
                        child: Text(
                          '${message['body'] ?? ''}',
                          style: const TextStyle(fontSize: 16, height: 1.7),
                        ),
                      ),
                    ),
                  ),
                if (attachmentsOf(message).isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 7),
                    child: MediaAttachmentList(
                      api: widget.api,
                      attachments: attachmentsOf(message),
                    ),
                  ),
                const SizedBox(height: 4),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Text(
                    relativeTime(message['createdAt']),
                    style: const TextStyle(color: muted, fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _composer() {
    final canSend =
        !sending && (body.text.trim().isNotEmpty || media.isNotEmpty);
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 7, 14, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            MediaDraftPanel(draft: media, disabled: sending),
            Glass(
              strong: true,
              radius: 24,
              padding: const EdgeInsets.fromLTRB(4, 5, 7, 5),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  MediaAddButton(draft: media, disabled: sending),
                  Expanded(
                    child: TextField(
                      controller: body,
                      minLines: 1,
                      maxLines: 5,
                      maxLength: 2000,
                      textInputAction: TextInputAction.newline,
                      decoration: const InputDecoration(
                        hintText: '输入消息…',
                        counterText: '',
                        border: InputBorder.none,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    onPressed: canSend ? send : null,
                    tooltip: '发送消息',
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.white.withValues(alpha: .14),
                      disabledBackgroundColor: Colors.white.withValues(
                        alpha: .045,
                      ),
                      minimumSize: const Size(44, 44),
                    ),
                    icon: sending
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(LucideIcons.arrowUp, size: 20),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AnonymousMark extends StatelessWidget {
  final int index;
  const _AnonymousMark({required this.index});
  @override
  Widget build(BuildContext context) => Semantics(
    label: '匿名用户',
    child: Container(
      width: 42,
      height: 42,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white.withValues(alpha: .04 + (index % 3) * .015),
        border: Border.all(color: Colors.white12),
      ),
      child: const Icon(LucideIcons.userRound, color: muted, size: 19),
    ),
  );
}

class _ErrorPane extends StatelessWidget {
  final String message;
  final Future<void> Function() onRetry;
  const _ErrorPane({required this.message, required this.onRetry});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(18, 8, 18, 4),
    child: Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .055),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white10),
      ),
      child: Row(
        children: [
          const Icon(LucideIcons.circleAlert, color: muted, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: muted, fontSize: 12),
            ),
          ),
          TextButton(onPressed: onRetry, child: const Text('重试')),
        ],
      ),
    ),
  );
}

String _preview(Data item) {
  final message = item['lastMessage'] as String?;
  return message?.isNotEmpty == true ? message! : '还没有消息';
}

String _dateGroup(dynamic value) {
  final date = DateTime.tryParse('$value')?.toLocal();
  if (date == null) return '更早';
  final now = DateTime.now();
  final difference = DateTime(
    now.year,
    now.month,
    now.day,
  ).difference(DateTime(date.year, date.month, date.day)).inDays;
  if (difference <= 0) return '今天';
  if (difference == 1) return '昨天';
  return '更早';
}
