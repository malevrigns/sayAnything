import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'api.dart';
import 'chat.dart';
import 'design.dart';
import 'page_activity.dart';
import 'policy.dart';
import 'profile_fields.dart';

/// Swipe through same-campus profile cards; a mutual like opens a private chat.
class DiscoverPage extends StatefulWidget {
  final Api api;
  final bool embedded;
  const DiscoverPage({super.key, required this.api, this.embedded = false});
  @override
  State<DiscoverPage> createState() => _DiscoverPageState();
}

class _DiscoverPageState extends State<DiscoverPage>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  static const genderFilters = [
    (value: '', label: '全部'),
    (value: 'male', label: '男'),
    (value: 'female', label: '女'),
  ];
  bool pageActive = false, appActive = true;
  bool get active => pageActive && appActive;
  List<Data> cards = [];
  int likesMe = 0, likesLeft = 0;
  bool loaded = false, loading = false;
  Object? error;
  String gender = '';
  int revision = 0;
  final answered = <String>{};
  final shift = ValueNotifier(Offset.zero);
  Animation<Offset>? flight;
  late final AnimationController flyer;
  double deckWidth = 320;
  bool get canLike => likesLeft > 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    appActive = lifecycle == null || lifecycle == AppLifecycleState.resumed;
    flyer =
        AnimationController(
          vsync: this,
          duration: const Duration(milliseconds: 220),
        )..addListener(() {
          final current = flight;
          if (current != null) shift.value = current.value;
        });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final wasActive = active;
    pageActive = PageActivity.isActiveOf(context);
    updateActivity(wasActive);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final wasActive = active;
    appActive = state == AppLifecycleState.resumed;
    updateActivity(wasActive);
  }

  /// Hidden or covered decks drop in-flight loads and interrupted gestures;
  /// coming back refreshes once. There is no polling timer.
  void updateActivity(bool wasActive) {
    if (active == wasActive) return;
    if (active) {
      load(silent: loaded);
      return;
    }
    revision++;
    flyer.stop();
    flight = null;
    shift.value = Offset.zero;
    if (loading) setState(() => loading = false);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    revision++;
    flyer.dispose();
    shift.dispose();
    super.dispose();
  }

  String get path => gender.isEmpty
      ? '/discover'
      : '/discover?${Uri(queryParameters: {'gender': gender}).query}';

  Future<void> load({bool silent = false}) async {
    if (!active) return;
    final current = ++revision;
    setState(() {
      loading = !silent;
      error = null;
    });
    try {
      final result = Data.from(await widget.api.call('GET', path));
      if (!mounted || current != revision) return;
      setState(() {
        cards = _people(
          result['items'],
        ).where((person) => !answered.contains('${person['id']}')).toList();
        likesMe = (result['likesMe'] as num?)?.toInt() ?? 0;
        likesLeft = (result['likesLeft'] as num?)?.toInt() ?? 0;
        loaded = true;
        loading = false;
      });
    } catch (e) {
      if (mounted && current == revision) {
        setState(() {
          error = e;
          loading = false;
        });
      }
    }
  }

  Duration get motion =>
      widget.api.reduceMotion || MediaQuery.disableAnimationsOf(context)
      ? Duration.zero
      : const Duration(milliseconds: 220);

  void dragUpdate(DragUpdateDetails details) {
    if (flyer.isAnimating || cards.isEmpty) return;
    shift.value += details.delta;
  }

  void dragEnd(DragEndDetails details) {
    if (flyer.isAnimating || cards.isEmpty) return;
    final dx = shift.value.dx;
    final speed = details.velocity.pixelsPerSecond.dx;
    var direction = 0;
    if (dx.abs() > deckWidth * .3) {
      direction = dx.sign.toInt();
    } else if (speed.abs() > 800) {
      direction = speed.sign.toInt();
    }
    if (direction > 0 && !canLike) {
      toast(context, '今天的心动用完了，明天再来看看。');
      direction = 0;
    }
    settle(direction);
  }

  void press(int direction) {
    if (flyer.isAnimating || cards.isEmpty) return;
    shift.value = Offset.zero;
    settle(direction);
  }

  /// Fly the top card out (or back) with a short, reduced-motion-aware
  /// animation, then record the answer. Leaving mid-flight sends nothing.
  Future<void> settle(int direction) async {
    if (cards.isEmpty) return;
    final person = cards.first;
    final start = shift.value;
    final end = direction == 0
        ? Offset.zero
        : Offset(direction * deckWidth * 1.6, start.dy * 1.4);
    flight = Tween(
      begin: start,
      end: end,
    ).animate(CurvedAnimation(parent: flyer, curve: Curves.easeOut));
    flyer.duration = motion;
    await flyer.forward(from: 0);
    if (!mounted) return;
    flight = null;
    shift.value = Offset.zero;
    flyer.reset();
    if (direction != 0) commit(person, like: direction > 0);
  }

  void commit(Data person, {required bool like}) {
    final id = '${person['id']}';
    answered.add(id);
    setState(() {
      cards.removeWhere((card) => '${card['id']}' == id);
      if (like && likesLeft > 0) likesLeft--;
    });
    swipe(person, like: like);
  }

  Future<void> swipe(Data person, {required bool like}) async {
    final id = '${person['id']}';
    try {
      final result = Data.from(
        await widget.api.call('POST', '/discover/$id/swipe', {
          'action': like ? 'like' : 'pass',
        }),
      );
      if (!mounted) return;
      if (result['matched'] == true && active) {
        await _openMatch(
          context,
          api: widget.api,
          person: person,
          conversation: result['conversation'],
        );
      }
    } catch (e) {
      if (!mounted) return;
      // Put the card back so the answer can be retried, then resync quota.
      answered.remove(id);
      setState(() {
        if (!cards.any((card) => '${card['id']}' == id)) {
          cards.insert(0, person);
        }
        if (like) likesLeft++;
      });
      if (active) {
        toast(context, e);
        load(silent: true);
      }
    }
  }

  void open(Widget page) =>
      Navigator.push(context, MaterialPageRoute(builder: (_) => page));

  @override
  Widget build(BuildContext context) {
    final policy = widget.api.policy;
    final allowDM = widget.api.user?['allowDM'] != false;
    return Scaffold(
      appBar: AppBar(
        leading: widget.embedded ? null : backButton(context),
        automaticallyImplyLeading: !widget.embedded,
        title: const Text('心动匹配'),
        actions: [
          IconButton(
            tooltip: '喜欢我的人',
            onPressed: () => open(LikesPage(api: widget.api)),
            icon: Badge(
              isLabelVisible: likesMe > 0,
              label: Text('$likesMe'),
              child: const Icon(LucideIcons.heartPlus),
            ),
          ),
          IconButton(
            tooltip: '配对',
            onPressed: () => open(MatchesPage(api: widget.api)),
            icon: const Icon(LucideIcons.heartHandshake),
          ),
          IconButton(
            tooltip: '刷新心动',
            onPressed: loading ? null : load,
            icon: const Icon(LucideIcons.refreshCw),
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
            child: GlassChoiceBar<String>(
              value: gender,
              options: genderFilters,
              onChanged: (value) {
                if (value == gender) return;
                setState(() => gender = value);
                load();
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
            child: Row(
              children: [
                Icon(
                  loaded && !canLike ? LucideIcons.heartOff : LucideIcons.heart,
                  size: 15,
                  color: Colors.white60,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    loaded ? '今日剩余 $likesLeft 次心动' : '向右是喜欢，向左是不喜欢。',
                    style: const TextStyle(color: Colors.white60, fontSize: 12),
                  ),
                ),
                if (loading)
                  const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              ],
            ),
          ),
          if (loaded && !canLike)
            Padding(
              padding: const EdgeInsets.fromLTRB(43, 6, 20, 0),
              child: Text(
                '今天的心动用完了，明天会再有 ${policy.dailyLikes} 次。',
                style: const TextStyle(color: Colors.white38, fontSize: 12),
              ),
            ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: deck(policy),
            ),
          ),
          if (!allowDM)
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(
                '开启“接收匿名私聊”后，才能表达喜欢。',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white38, fontSize: 12),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 6, 20, 16),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: cards.isEmpty ? null : () => press(-1),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(LucideIcons.x, size: 17),
                        SizedBox(width: 8),
                        Text('不喜欢'),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: cards.isEmpty || !canLike
                        ? null
                        : () => press(1),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(LucideIcons.heart, size: 17),
                        SizedBox(width: 8),
                        Text('喜欢'),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget deck(AppPolicy policy) {
    if (cards.isEmpty) {
      if (loading || (!loaded && error == null)) {
        return const Center(child: CircularProgressIndicator(strokeWidth: 2));
      }
      return Center(
        child: SingleChildScrollView(
          child: error != null
              ? EmptyState(
                  '连接暂时中断',
                  error.toString(),
                  icon: LucideIcons.wifiOff,
                  action: TextButton(
                    onPressed: load,
                    child: const Text('重新连接'),
                  ),
                )
              : const EmptyState(
                  '这会儿没有新的同学了',
                  '晚点再来看看，也可以先去完善你的心动资料。',
                  icon: LucideIcons.heart,
                ),
        ),
      );
    }
    // Build each card face once so a drag only moves it, never rebuilds it.
    final visible = cards.take(3).toList();
    final faces = [
      for (var i = 0; i < visible.length; i++)
        card(visible[i], policy, full: i < 2),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        deckWidth = constraints.maxWidth;
        return ValueListenableBuilder<Offset>(
          valueListenable: shift,
          builder: (context, offset, _) {
            final progress = (offset.dx.abs() / (deckWidth * .3)).clamp(
              0.0,
              1.0,
            );
            return Stack(
              fit: StackFit.expand,
              children: [
                for (var i = faces.length - 1; i >= 1; i--)
                  IgnorePointer(
                    child: ExcludeSemantics(
                      child: Transform.translate(
                        offset: Offset(0, 14 * (i - progress)),
                        child: Transform.scale(
                          scale: 1 - .05 * (i - progress),
                          child: faces[i],
                        ),
                      ),
                    ),
                  ),
                Transform.translate(
                  offset: offset,
                  child: Transform.rotate(
                    angle: offset.dx / deckWidth * .3,
                    alignment: Alignment.bottomCenter,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onPanUpdate: dragUpdate,
                      onPanEnd: dragEnd,
                      onPanCancel: () {
                        if (!flyer.isAnimating) settle(0);
                      },
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          faces.first,
                          if (progress > 0)
                            Positioned(
                              top: 22,
                              left: offset.dx > 0 ? 22 : null,
                              right: offset.dx < 0 ? 22 : null,
                              child: Opacity(
                                opacity: progress,
                                child: stamp(offset.dx > 0 ? '喜欢' : '不喜欢'),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget stamp(String label) => DecoratedBox(
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: .14),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: Colors.white38, width: .8),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w500,
          letterSpacing: .5,
        ),
      ),
    ),
  );

  Widget card(Data person, AppPolicy policy, {required bool full}) {
    if (!full) return const Glass(radius: 28, child: SizedBox.expand());
    final tags = _tagsOf(person);
    final bio = '${person['bio'] ?? ''}'.trim();
    final distance = '${person['distanceLabel'] ?? ''}'.trim();
    return Glass(
      strong: true,
      radius: 28,
      padding: const EdgeInsets.all(22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Avatar(person['avatar'] ?? 0, size: 56),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      person['alias'] ?? '匿名同学',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 21,
                        fontWeight: FontWeight.w500,
                        letterSpacing: -.3,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _metaOf(policy, person),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white60,
                        fontSize: 12,
                        height: 1.5,
                      ),
                    ),
                    if (distance.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          const Icon(
                            LucideIcons.mapPin,
                            size: 12,
                            color: Colors.white38,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            distance,
                            style: const TextStyle(
                              color: Colors.white38,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Expanded(
            child: Text(
              bio.isEmpty ? '这位同学还没有写简介。' : bio,
              overflow: TextOverflow.fade,
              style: TextStyle(
                fontSize: 15,
                height: 1.75,
                color: bio.isEmpty ? Colors.white38 : Colors.white,
              ),
            ),
          ),
          if (tags.isNotEmpty) ...[const SizedBox(height: 14), _tagChips(tags)],
        ],
      ),
    );
  }
}

/// People who liked me and are still waiting for an answer.
class LikesPage extends StatefulWidget {
  final Api api;
  const LikesPage({super.key, required this.api});
  @override
  State<LikesPage> createState() => _LikesPageState();
}

class _LikesPageState extends State<LikesPage> {
  List<Data>? people;
  Object? error;
  String? answering;
  int revision = 0;

  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void dispose() {
    revision++;
    super.dispose();
  }

  Future<void> load() async {
    final current = ++revision;
    try {
      final result = await widget.api.call('GET', '/discover/likes');
      if (!mounted || current != revision) return;
      setState(() {
        people = _people(result);
        error = null;
      });
    } catch (e) {
      if (mounted && current == revision) setState(() => error = e);
    }
  }

  Future<void> answer(Data person, {required bool like}) async {
    if (answering != null) return;
    final id = '${person['id']}';
    setState(() => answering = id);
    try {
      final result = Data.from(
        await widget.api.call('POST', '/discover/$id/swipe', {
          'action': like ? 'like' : 'pass',
        }),
      );
      if (!mounted) return;
      setState(() {
        people?.removeWhere((p) => '${p['id']}' == id);
        answering = null;
      });
      if (result['matched'] == true) {
        await _openMatch(
          context,
          api: widget.api,
          person: person,
          conversation: result['conversation'],
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => answering = null);
      toast(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final policy = widget.api.policy;
    return Scaffold(
      appBar: AppBar(
        leading: backButton(context),
        title: const Text('喜欢我的人'),
        actions: [
          IconButton(
            tooltip: '刷新喜欢',
            onPressed: load,
            icon: const Icon(LucideIcons.refreshCw),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
          children: [
            const Text(
              '他们先向你心动了。回应喜欢，就能开始聊天。',
              style: TextStyle(
                color: Colors.white60,
                fontSize: 13,
                height: 1.7,
              ),
            ),
            const SizedBox(height: 16),
            if (people == null && error == null)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(48),
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            else if (people == null)
              EmptyState(
                '连接暂时中断',
                error.toString(),
                icon: LucideIcons.wifiOff,
                action: TextButton(onPressed: load, child: const Text('重新连接')),
              )
            else if (people!.isEmpty)
              const EmptyState(
                '这里还很安静',
                '喜欢你的人会出现在这里。先去完善资料，或者多看看别人。',
                icon: LucideIcons.heart,
              )
            else
              for (final person in people!) row(person, policy),
          ],
        ),
      ),
    );
  }

  Widget row(Data person, AppPolicy policy) {
    final id = '${person['id']}';
    final busy = answering != null;
    final tags = _tagsOf(person);
    final bio = '${person['bio'] ?? ''}'.trim();
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Glass(
        radius: 22,
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Avatar(person['avatar'] ?? 0, size: 42),
                const SizedBox(width: 13),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        person['alias'] ?? '匿名同学',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        _metaOf(policy, person),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white60,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (bio.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                bio,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 14, height: 1.6),
              ),
            ],
            if (tags.isNotEmpty) ...[
              const SizedBox(height: 12),
              _tagChips(tags),
            ],
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: busy ? null : () => answer(person, like: false),
                  child: const Text('忽略'),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: busy ? null : () => answer(person, like: true),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(44, 42),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 10,
                    ),
                  ),
                  child: Text(answering == id ? '连接中…' : '喜欢'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Mutual likes, each one already a private conversation.
class MatchesPage extends StatefulWidget {
  final Api api;
  const MatchesPage({super.key, required this.api});
  @override
  State<MatchesPage> createState() => _MatchesPageState();
}

class _MatchesPageState extends State<MatchesPage> {
  late Future<List<Data>> future;

  @override
  void initState() {
    super.initState();
    future = widget.api.list('/discover/matches');
  }

  Future<void> reload() async {
    setState(() {
      future = widget.api.list('/discover/matches');
    });
    try {
      await future;
    } catch (_) {
      /* FutureBuilder renders recovery. */
    }
  }

  Future<void> open(Data match) async {
    final id = match['conversationId'];
    if (id is! String || id.isEmpty) {
      toast(context, '会话还没准备好，稍后再试');
      return;
    }
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChatPage(
          api: widget.api,
          id: id,
          title: '${match['alias'] ?? '匿名同学'}',
          room: false,
        ),
      ),
    );
    if (mounted) reload();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      leading: backButton(context),
      title: const Text('配对'),
      actions: [
        IconButton(
          tooltip: '刷新配对',
          onPressed: reload,
          icon: const Icon(LucideIcons.refreshCw),
        ),
      ],
    ),
    body: RefreshIndicator(
      onRefresh: reload,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          const Text(
            '互相喜欢的人，都在这里。',
            style: TextStyle(color: Colors.white60, fontSize: 13, height: 1.7),
          ),
          const SizedBox(height: 16),
          FutureBuilder<List<Data>>(
            future: future,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return EmptyState(
                  '连接暂时中断',
                  snapshot.error.toString(),
                  icon: LucideIcons.wifiOff,
                  action: TextButton(
                    onPressed: reload,
                    child: const Text('重新连接'),
                  ),
                );
              }
              if (!snapshot.hasData) {
                return const Center(
                  child: Padding(
                    padding: EdgeInsets.all(48),
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                );
              }
              final matches = snapshot.data!;
              if (matches.isEmpty) {
                return const EmptyState(
                  '还没有配对',
                  '互相喜欢的人会出现在这里，先去心动看看。',
                  icon: LucideIcons.heartHandshake,
                );
              }
              return Column(
                children: [for (final match in matches) row(match)],
              );
            },
          ),
        ],
      ),
    ),
  );

  Widget row(Data match) {
    final when = relativeTime(match['matchedAt']);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Glass(
        radius: 22,
        // ListTile draws its ink on the nearest Material; keep it inside the glass.
        child: Material(
          type: MaterialType.transparency,
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 6,
            ),
            leading: Avatar(match['avatar'] ?? 0, size: 42),
            title: Text(
              '${match['alias'] ?? '匿名同学'}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
            ),
            subtitle: Text(
              when.isEmpty ? '互相心动' : '互相心动 · $when',
              style: const TextStyle(color: Colors.white60, fontSize: 12),
            ),
            trailing: const Icon(
              LucideIcons.chevronRight,
              size: 17,
              color: Colors.white30,
            ),
            onTap: () => open(match),
          ),
        ),
      ),
    );
  }
}

/// A mutual like: name the other person and offer to start chatting.
Future<void> _openMatch(
  BuildContext context, {
  required Api api,
  required Data person,
  required dynamic conversation,
}) async {
  final chat = conversation is Map ? Data.from(conversation) : null;
  final alias = '${chat?['alias'] ?? person['alias'] ?? '匿名同学'}';
  final id = chat?['id'];
  final go = await showDialog<bool>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: .35),
    builder: (dialog) => Dialog(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
      child: Glass(
        strong: true,
        radius: 28,
        padding: const EdgeInsets.fromLTRB(24, 26, 24, 18),
        // A bare Dialog merges plain text into the dialog node, which the
        // web engine does not voice. Keep the copy as explicit nodes, as
        // AlertDialog does for its content.
        child: Semantics(
          container: true,
          explicitChildNodes: true,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(
                LucideIcons.heartHandshake,
                size: 30,
                color: Colors.white70,
              ),
              const SizedBox(height: 16),
              const Text(
                '心动了',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 10),
              Text(
                '你和“$alias”互相喜欢，可以开始聊天了。',
                style: const TextStyle(
                  fontSize: 13,
                  color: Colors.white60,
                  height: 1.7,
                ),
              ),
              const SizedBox(height: 22),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(dialog, false),
                    child: const Text('继续看看'),
                  ),
                  if (id is String && id.isNotEmpty) ...[
                    const SizedBox(width: 6),
                    FilledButton(
                      onPressed: () => Navigator.pop(dialog, true),
                      child: const Text('去聊天'),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    ),
  );
  if (go != true || id is! String || id.isEmpty) return;
  if (!context.mounted) return;
  await Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => ChatPage(api: api, id: id, title: alias, room: false),
    ),
  );
}

List<Data> _people(dynamic value) {
  final list = value is Map ? value['items'] : value;
  return (list as List? ?? const []).map((v) => Data.from(v)).toList();
}

List<String> _tagsOf(Data person) =>
    (person['tags'] as List? ?? const []).map((tag) => '$tag').toList();

String _metaOf(AppPolicy policy, Data person) {
  final grade = policy.gradeLabel(person['grade']);
  final campus = '${person['campus'] ?? ''}'.trim();
  return [
    genderLabel(person['gender']),
    ?grade,
    if (campus.isNotEmpty) campus,
  ].join(' · ');
}

Widget _tagChips(List<String> tags) => Wrap(
  spacing: 8,
  runSpacing: 8,
  children: [
    for (final tag in tags)
      Chip(
        label: Text(tag),
        visualDensity: VisualDensity.compact,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      ),
  ],
);
