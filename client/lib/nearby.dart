import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'api.dart';
import 'chat.dart';
import 'design.dart';
import 'device_location.dart';
import 'profile_fields.dart';
import 'page_activity.dart';

class NearbyPage extends StatefulWidget {
  final Api api;
  final bool embedded;
  final bool settingsOnly;
  final Future<DeviceLocation> Function() locate;
  const NearbyPage({
    super.key,
    required this.api,
    this.embedded = false,
    this.settingsOnly = false,
    this.locate = requestDeviceLocation,
  });
  @override
  State<NearbyPage> createState() => _NearbyPageState();
}

class _NearbyPageState extends State<NearbyPage> with WidgetsBindingObserver {
  static const previewAvailable =
      kIsWeb && bool.fromEnvironment('PREVIEW_NEARBY');
  bool showMock = previewAvailable;
  bool pageActive = true;
  bool appActive = true;
  bool get active => pageActive && appActive;
  Data? status;
  Object? error;
  bool loading = true, locating = false, hiding = false;
  String? greeting;
  int revision = 0;
  bool get enabled => status?['enabled'] == true;
  List<Data> get people =>
      (status?['items'] as List? ?? []).map((v) => Data.from(v)).toList();
  static const mockPeople = <Data>[
    {'alias': '晚风同学', 'gender': 'female', 'distanceLabel': '约 500 米以内'},
    {'alias': '图书馆的猫', 'gender': 'male', 'distanceLabel': '约 500 米以内'},
    {'alias': '橘子汽水', 'gender': 'female', 'distanceLabel': '约 1 公里以内'},
    {'alias': '路过的星星', 'gender': 'undisclosed', 'distanceLabel': '约 1 公里以内'},
    {'alias': '操场散步中', 'gender': 'male', 'distanceLabel': '约 2 公里以内'},
    {'alias': '今天也早八', 'gender': 'undisclosed', 'distanceLabel': '约 3 公里以内'},
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    load();
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

  void updateActivity(bool wasActive) {
    if (active == wasActive) return;
    if (!active) {
      revision++;
      setState(() {
        loading = locating = hiding = false;
        greeting = null;
      });
    } else {
      load(silent: true);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    revision++;
    super.dispose();
  }

  Future<void> load({bool silent = false}) async {
    if (!active) return;
    final current = ++revision;
    setState(() {
      loading = !silent;
      error = null;
    });
    try {
      final result = Data.from(await widget.api.call('GET', '/nearby'));
      if (mounted && current == revision) {
        setState(() {
          status = result;
          loading = false;
        });
      }
    } catch (e) {
      if (mounted && current == revision) {
        setState(() {
          error = e;
          loading = false;
        });
      }
    }
  }

  Future<void> enable() async {
    if (!active || locating || hiding) return;
    final stateRevision = status?['revision'];
    if (stateRevision is! int) {
      toast(context, '请先刷新附近状态，再选择是否展示');
      await load();
      return;
    }
    if (widget.api.user?['allowDM'] != true) {
      toast(context, '请先在设置中开启“接收匿名私聊”');
      return;
    }
    final current = ++revision;
    setState(() {
      locating = true;
      error = null;
    });
    try {
      final location = await widget.locate();
      // Navigating away or cancelling before positioning finishes never publishes.
      if (!mounted || !active || current != revision) return;
      final result = Data.from(
        await widget.api.nearbyLocation('PUT', {
          'latitude': location.latitude,
          'longitude': location.longitude,
          'revision': stateRevision,
        }),
      );
      if (mounted && current == revision) {
        setState(() {
          status = result;
        });
      }
    } catch (e) {
      if (mounted && current == revision) {
        setState(() {
          error = e;
          locating = false;
        });
        if (e is ApiError && e.status == 409) {
          await load();
          if (mounted) toast(context, e);
        }
      }
    } finally {
      if (mounted && current == revision) {
        setState(() {
          locating = false;
        });
      }
    }
  }

  Future<void> hide() async {
    if (!active || hiding) return;
    final current = ++revision;
    setState(() {
      hiding = true;
      error = null;
      locating = false;
    });
    try {
      await widget.api.nearbyLocation('DELETE');
      if (mounted && current == revision) {
        setState(() {
          status = {...?status, 'enabled': false, 'items': <Data>[]}
            ..remove('revision');
        });
        toast(context, '已关闭附近展示');
        final fresh = Data.from(await widget.api.call('GET', '/nearby'));
        if (mounted && current == revision) {
          setState(() {
            status = fresh;
          });
        }
      }
    } catch (e) {
      if (mounted && current == revision) {
        setState(() {
          error = e;
        });
      }
    } finally {
      if (mounted && current == revision) {
        setState(() {
          hiding = false;
        });
      }
    }
  }

  Future<void> greet(Data person) async {
    if (!active || greeting != null) return;
    final current = revision;
    setState(() {
      greeting = person['id'];
    });
    try {
      final conversation = Data.from(
        await widget.api.call('POST', '/nearby/${person['id']}/greet', {}),
      );
      if (!mounted || !active || current != revision) return;
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ChatPage(
            api: widget.api,
            id: conversation['id'],
            title: conversation['alias'] ?? person['alias'],
            room: false,
          ),
        ),
      );
    } catch (e) {
      if (mounted && active && current == revision) toast(context, e);
    } finally {
      if (mounted && current == revision) {
        setState(() {
          greeting = null;
        });
      }
    }
  }

  Future<void> openSettings() async {
    await showDialog<void>(
      context: context,
      barrierColor: Colors.black38,
      builder: (_) => Dialog(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420, maxHeight: 420),
          child: Glass(
            strong: true,
            radius: 28,
            child: NearbyPage(
              api: widget.api,
              locate: widget.locate,
              settingsOnly: true,
            ),
          ),
        ),
      ),
    );
    if (mounted && active) await load(silent: true);
  }

  String get expires {
    final time = DateTime.tryParse('${status?['expiresAt']}')?.toLocal();
    if (time == null) return '本次展示会自动到期';
    return '本次展示至 ${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}，可随时关闭';
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: widget.settingsOnly ? Colors.transparent : null,
    appBar: AppBar(
      backgroundColor: widget.settingsOnly ? Colors.transparent : null,
      leading: widget.embedded || widget.settingsOnly
          ? null
          : backButton(context),
      automaticallyImplyLeading: !widget.embedded && !widget.settingsOnly,
      title: Text(widget.settingsOnly ? '附近设置' : '附近的人'),
      actions: [
        if (widget.settingsOnly)
          IconButton(
            tooltip: '关闭附近设置',
            onPressed: () => Navigator.pop(context),
            icon: const Icon(LucideIcons.x),
          )
        else ...[
          IconButton(
            tooltip: '附近设置',
            onPressed: openSettings,
            icon: const Icon(LucideIcons.settings2),
          ),
          IconButton(
            tooltip: '刷新附近',
            onPressed: locating || hiding ? null : load,
            icon: const Icon(LucideIcons.refreshCw),
          ),
        ],
      ],
    ),
    body: ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      children: [
        if (!widget.settingsOnly) ...[
          const Text(
            '也许，刚好在附近。',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 10),
          Text(
            status == null
                ? '与同校同学，轻轻打个招呼。'
                : '同一校园 · 约 ${status!['radiusKm']} 公里内',
            style: const TextStyle(color: Colors.white60, fontSize: 13),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Icon(
                enabled ? LucideIcons.radio : LucideIcons.eyeOff,
                size: 15,
                color: Colors.white60,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  enabled ? '你正在附近展示 · 可随时关闭' : '你尚未开启附近展示',
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
          const SizedBox(height: 16),
          if (previewAvailable)
            Row(
              children: [
                Expanded(
                  child: Text(
                    showMock ? '模拟数据 · 仅供预览' : '真实附近列表',
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                ),
                TextButton(
                  onPressed: () => setState(() => showMock = !showMock),
                  child: Text(showMock ? '显示真实列表' : '查看模拟效果'),
                ),
              ],
            ),
        ],
        if (widget.settingsOnly)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  enabled ? '你正在附近展示' : '先由你决定，是否被看见。',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  enabled
                      ? expires
                      : '开启后将展示匿名昵称、性别与模糊距离。位置按网格暂存，不公开坐标，也不在后台持续定位。',
                  style: const TextStyle(
                    color: Colors.white60,
                    fontSize: 13,
                    height: 1.8,
                  ),
                ),
                const SizedBox(height: 16),
                if (loading)
                  const Center(child: CircularProgressIndicator(strokeWidth: 2))
                else if (hiding)
                  const Text('正在关闭展示…', style: TextStyle(color: Colors.white70))
                else if (locating)
                  Row(
                    children: [
                      const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      const SizedBox(width: 10),
                      const Expanded(
                        child: Text(
                          '正在获取大致位置…',
                          style: TextStyle(fontSize: 13),
                        ),
                      ),
                      TextButton(onPressed: hide, child: const Text('取消')),
                    ],
                  )
                else
                  SizedBox(
                    width: double.infinity,
                    child: enabled
                        ? OutlinedButton(
                            onPressed: hide,
                            child: const Text('关闭附近展示'),
                          )
                        : FilledButton(
                            onPressed: status == null ? load : enable,
                            child: Text(status == null ? '重新连接' : '开启附近并展示我'),
                          ),
                  ),
                if (enabled && !locating && !hiding)
                  Center(
                    child: TextButton(
                      onPressed: enable,
                      child: const Text('更新我的位置'),
                    ),
                  ),
              ],
            ),
          ),
        if (error != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  error.toString(),
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 13,
                    height: 1.7,
                  ),
                ),
                if (error is DeviceLocationError &&
                    (error as DeviceLocationError).openSettings)
                  TextButton(
                    onPressed: () async {
                      try {
                        if (!await openDeviceLocationSettings() &&
                            context.mounted) {
                          toast(context, '请在设备设置中开启定位权限');
                        }
                      } catch (_) {
                        if (context.mounted) toast(context, '请在设备设置中开启定位权限');
                      }
                    },
                    child: const Text('打开设备设置'),
                  ),
              ],
            ),
          ),
        if (!widget.settingsOnly && (showMock || (enabled && !loading))) ...[
          SectionTitle(
            '此刻可见的同学',
            subtitle: showMock ? '匿名昵称、性别与模糊距离的展示效果' : '仅展示主动开启附近的人',
          ),
          if (!showMock && people.isEmpty)
            const EmptyState(
              '附近暂时还没有同学',
              '稍后再来看看，也可以先去话题房间聊聊。',
              icon: LucideIcons.users,
            ),
          for (final person in showMock ? mockPeople : people)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Glass(
                radius: 22,
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    const BrandMark(size: 30),
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
                          const SizedBox(height: 7),
                          Text(
                            '${genderLabel(person['gender'])} · ${person['distanceLabel']}',
                            style: const TextStyle(
                              color: Colors.white60,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    TextButton(
                      onPressed: showMock
                          ? () => toast(context, '这是模拟同学，仅供预览，不会发送招呼。')
                          : greeting != null
                          ? null
                          : () => greet(person),
                      child: Text(
                        !showMock && greeting == person['id'] ? '连接中…' : '打招呼',
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
        if (!widget.settingsOnly && !showMock && !enabled && !loading)
          const EmptyState(
            '先开启附近，再遇见同校同学',
            '点击右上角附近设置，由你决定是否展示。',
            icon: LucideIcons.users,
          ),
        const SizedBox(height: 14),
        const Text(
          '位置和距离均为估算。关闭附近后，新同学将无法从这里找到你，已有对话会保留。',
          style: TextStyle(color: Colors.white38, fontSize: 12, height: 1.8),
        ),
      ],
    ),
  );
}
