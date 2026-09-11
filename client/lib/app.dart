import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'api.dart';
import 'background.dart';
import 'design.dart';
import 'feed.dart';
import 'chat.dart';
import 'profile.dart';
import 'nearby.dart';

class SayAnythingApp extends StatefulWidget {
  final Api api;
  final bool restore;
  const SayAnythingApp({super.key, required this.api, this.restore = true});
  @override
  State<SayAnythingApp> createState() => _SayAnythingAppState();
}

class _SayAnythingAppState extends State<SayAnythingApp> {
  bool loading = true;
  String? error;
  @override
  void initState() {
    super.initState();
    if (widget.restore) {
      restore();
    } else {
      loading = false;
    }
  }

  Future<void> restore() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      await widget.api.restore();
    } catch (e) {
      error = e.toString();
    }
    if (mounted) setState(() => loading = false);
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.api,
    builder: (context, _) => MaterialApp(
      title: 'sayAnything',
      debugShowCheckedModeBanner: false,
      theme: appTheme(true),
      darkTheme: appTheme(true),
      themeMode: ThemeMode.dark,
      builder: (context, child) => ColoredBox(
        color: const Color(0xFF080808),
        child: LayoutBuilder(
          builder: (context, constraints) => Center(
            child: SizedBox(
              width: constraints.maxWidth.clamp(0, 480),
              height: constraints.maxHeight,
              child: MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  size: Size(
                    constraints.maxWidth.clamp(0, 480),
                    constraints.maxHeight,
                  ),
                  textScaler: TextScaler.linear(
                    widget.api.textScale *
                        MediaQuery.textScalerOf(context).scale(1),
                  ),
                  disableAnimations:
                      widget.api.reduceMotion ||
                      MediaQuery.disableAnimationsOf(context),
                ),
                child: ClipRect(
                  child: AppBackdrop(
                    api: widget.api,
                    allowVideo: widget.restore,
                    child: child ?? const SizedBox(),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
      home: loading
          ? const Scaffold(
              body: Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    BrandMark(size: 34),
                    SizedBox(width: 12),
                    Text(
                      'sayAnything',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 24,
                        letterSpacing: -.8,
                      ),
                    ),
                  ],
                ),
              ),
            )
          : error != null
          ? Scaffold(
              body: SafeArea(
                child: Center(
                  child: EmptyState(
                    '连接暂时中断',
                    error!,
                    icon: LucideIcons.wifiOff,
                    action: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        FilledButton(
                          onPressed: restore,
                          child: const Text('重新连接'),
                        ),
                        TextButton(
                          onPressed: () => setState(() => error = null),
                          child: const Text('检查服务地址'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            )
          : widget.api.user == null
          ? Welcome(api: widget.api)
          : HomeShell(api: widget.api),
    ),
  );
}

class Welcome extends StatefulWidget {
  final Api api;
  const Welcome({super.key, required this.api});
  @override
  State<Welcome> createState() => _WelcomeState();
}

class _WelcomeState extends State<Welcome> {
  final campus = TextEditingController();
  late final server = TextEditingController(text: widget.api.origin);
  bool busy = false, agree = false, showServer = false;
  @override
  void dispose() {
    campus.dispose();
    server.dispose();
    super.dispose();
  }

  Future<void> join() async {
    if (busy) return;
    if (campus.text.trim().isEmpty) {
      toast(context, '请先填写你的学校');
      return;
    }
    if (!agree) {
      toast(context, '请先阅读并同意社区约定与隐私说明');
      return;
    }
    setState(() => busy = true);
    try {
      await widget.api.connect(server.text, campus.text);
    } catch (e) {
      if (mounted) toast(context, e);
    }
    if (mounted) setState(() => busy = false);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
        children: [
          Row(
            children: [
              const BrandMark(size: 30),
              const SizedBox(width: 9),
              const Text(
                'sayAnything',
                style: TextStyle(
                  fontSize: 21,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -.8,
                ),
              ),
              const Spacer(),
              IconButton(
                tooltip: '匿名与隐私',
                onPressed: () => showPolicy(context),
                icon: const Icon(LucideIcons.shield, size: 20),
              ),
            ],
          ),
          const SizedBox(height: 39),
          const Center(child: BrandMark(size: 54)),
          const SizedBox(height: 24),
          const Text(
            '有些话，\n在这里慢慢说。',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 30,
              height: 1.55,
              fontWeight: FontWeight.w500,
              letterSpacing: -.5,
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            '校园匿名交流 · 无需公开身份',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: Colors.white54),
          ),
          const SizedBox(height: 39),
          Glass(
            strong: true,
            radius: 30,
            padding: const EdgeInsets.fromLTRB(22, 25, 22, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '在这里，不必介绍自己。',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 11),
                const Text(
                  '选择你的学校，与同校的人匿名聊聊。\n无需真实姓名，也不必准备一段完美的开场白。',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.white60,
                    height: 1.9,
                  ),
                ),
                const SizedBox(height: 22),
                TextField(
                  controller: campus,
                  enabled: !busy,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => join(),
                  decoration: const InputDecoration(
                    labelText: '你在哪所学校？',
                    hintText: '输入学校全称',
                    counterText: '',
                    prefixIcon: Icon(LucideIcons.school, size: 20),
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  '学校为自行选择，暂未验证学生身份。',
                  style: TextStyle(fontSize: 12, color: Colors.white38),
                ),
                const SizedBox(height: 21),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: busy ? null : join,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (busy) ...[
                          const SizedBox(
                            width: 15,
                            height: 15,
                            child: CircularProgressIndicator(strokeWidth: 1.5),
                          ),
                          const SizedBox(width: 10),
                        ],
                        const Text('进入校园'),
                        const SizedBox(width: 12),
                        const Icon(LucideIcons.arrowRight, size: 17),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 7),
                Row(
                  children: [
                    SizedBox(
                      width: 38,
                      child: Checkbox(
                        value: agree,
                        onChanged: busy
                            ? null
                            : (v) => setState(() => agree = v!),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(5),
                        ),
                      ),
                    ),
                    Expanded(
                      child: Wrap(
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          const Text(
                            '我已阅读并同意 ',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.white38,
                            ),
                          ),
                          InkWell(
                            onTap: () => showPolicy(context),
                            child: const Padding(
                              padding: EdgeInsets.symmetric(vertical: 12),
                              child: Text(
                                '社区约定与隐私说明',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.white60,
                                  decoration: TextDecoration.underline,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 5),
          Center(
            child: TextButton(
              onPressed: () => setState(() => showServer = !showServer),
              child: const Text(
                '连接设置',
                style: TextStyle(fontSize: 12, color: Colors.white38),
              ),
            ),
          ),
          if (showServer) ...[
            const SizedBox(height: 8),
            TextField(
              controller: server,
              keyboardType: TextInputType.url,
              autocorrect: false,
              decoration: const InputDecoration(
                labelText: '服务地址',
                hintText: 'https://chat.example.com',
              ),
            ),
            const SizedBox(height: 9),
            const Text(
              '真机请连接可信的 HTTPS 服务；USB 联调可使用本机转发地址。',
              style: TextStyle(
                fontSize: 12,
                color: Colors.white54,
                height: 1.8,
              ),
            ),
          ],
        ],
      ),
    ),
  );
}

class HomeShell extends StatefulWidget {
  final Api api;
  const HomeShell({super.key, required this.api});
  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  static const labels = ['动态', '聊天', '附近', '我'];
  int tab = 0, revision = 0;
  Future<void> compose() async {
    final sent = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => ComposePage(api: widget.api)),
    );
    if (sent == true && mounted) {
      setState(() {
        tab = 0;
        revision++;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final keyboard = MediaQuery.viewInsetsOf(context).bottom > 0;
    final pages = [
      FeedPage(
        key: ValueKey('feed$revision'),
        api: widget.api,
        onCompose: compose,
        onSettings: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ProfilePage(api: widget.api, settings: true),
          ),
        ),
      ),
      InboxPage(api: widget.api, onNew: () => setState(() => tab = 0)),
      NearbyPage(api: widget.api, embedded: true),
      ProfilePage(api: widget.api),
    ];
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: KeyedSubtree(key: ValueKey('$tab-$revision'), child: pages[tab]),
      ),
      floatingActionButton: tab == 0 && !keyboard
          ? Padding(
              padding: const EdgeInsets.only(bottom: 2, right: 4),
              child: Glass(
                strong: true,
                radius: 28,
                child: IconButton(
                  tooltip: '说点什么',
                  onPressed: compose,
                  padding: const EdgeInsets.all(16),
                  icon: const Icon(
                    LucideIcons.plus,
                    color: Colors.white,
                    size: 23,
                  ),
                ),
              ),
            )
          : null,
      bottomNavigationBar: keyboard
          ? null
          : SafeArea(
              top: false,
              minimum: const EdgeInsets.fromLTRB(20, 8, 20, 12),
              child: Glass(
                strong: true,
                radius: 30,
                padding: const EdgeInsets.all(7),
                child: Row(
                  children: [
                    for (var i = 0; i < labels.length; i++)
                      Expanded(
                        child: Semantics(
                          selected: tab == i,
                          button: true,
                          label: labels[i],
                          child: InkWell(
                            onTap: () => setState(() => tab = i),
                            borderRadius: BorderRadius.circular(24),
                            child: AnimatedContainer(
                              duration: widget.api.reduceMotion
                                  ? Duration.zero
                                  : const Duration(milliseconds: 200),
                              padding: const EdgeInsets.symmetric(vertical: 9),
                              decoration: BoxDecoration(
                                color: tab == i
                                    ? Colors.white.withValues(alpha: .095)
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(24),
                              ),
                              child: ExcludeSemantics(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      [
                                        LucideIcons.newspaper,
                                        LucideIcons.messageCircle,
                                        LucideIcons.mapPin,
                                        LucideIcons.userRound,
                                      ][i],
                                      color: tab == i
                                          ? Colors.white
                                          : Colors.white38,
                                      size: 20,
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      labels[i],
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: tab == i
                                            ? Colors.white
                                            : Colors.white38,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
    );
  }
}

void showPolicy(BuildContext context) => Navigator.push(
  context,
  MaterialPageRoute(builder: (_) => const PrivacyPage()),
);
