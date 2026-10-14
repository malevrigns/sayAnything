# sayAnything · 校园匿名聊天

一个校园匿名交流应用。Flutter Android / Windows 客户端、Go + SQLite 后端，以及仅用于产品介绍和下载的独立官网。

**有些话，在这里慢慢说。**

1.5 在底栏中间新增「心动」页，顺序为 动态 / 心动 / 聊天 / 附近 / 我：滑动资料卡表示心动或跳过，每个身份每天有固定的心动额度，双方互相心动即配对并进入普通私聊。「我」页可编辑新的资料卡字段简介、年级和标签，「心动」页提供「喜欢我」与「配对」入口。底栏已打开的页面及滚动位置保留，隐藏页面暂停聊天轮询，附近展示开关位于「附近设置」弹窗。[前后端职责说明](docs/architecture.md)。

## 先运行起来

在项目目录打开 PowerShell：

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\start.ps1
```

保持终端运行，访问 **http://localhost:8080** 查看官网。安装包不纳入 Git 源码；本机构建后的发行物位于 `dist/`：

- `sayanything-android.apk`：安卓安装包。
- `sayanything-android-arm64.apk`：ARM64 版，官网优先提供；另有 `-armv7.apk`（32 位）及 `-x64.apk`（模拟器）。不确定架构时可用通用版。各包的实际大小与 SHA-256 由 `scripts/release-manifest.ps1` 从当次构建生成，以本机 `dist/release-manifest.json` 为准。
- `sayanything-windows.zip`：解压后运行 `sayanything.exe`，保留同目录的 DLL 和 `data` 文件夹。
- `sayanything-server.exe`：Go 服务。启动脚本自动使用它；没有此文件时使用 `go run .`。

客户端首次打开时，填写学校全称，阅读社区约定后进入。同一服务、同一学校名称的用户共享校园广场和话题房间。无需创建用户名密码，匿名登录凭据保存在设备安全存储中。

更新时请先升级 Go 后端，再安装客户端。1.5 的心动匹配与资料卡字段需要 1.5 后端，1.4 的附近、性别和视频封面同样需要同版后端；旧客户端可继续连接新版 Go。

### Android 连接本机

安卓模拟器默认使用 `http://10.0.2.2:8080`。真机可通过 USB 连接电脑并启用 USB 调试，执行：

```powershell
.\.tools\android-sdk\platform-tools\adb.exe reverse tcp:8080 tcp:8080
.\.tools\android-sdk\platform-tools\adb.exe install -r .\dist\sayanything-android.apk
```

在 App 欢迎页的「连接设置」中填写 `http://127.0.0.1:8080`。该转发仅在 USB/ADB 连接有效时工作。

日常多人使用时，部署后端并填写真实的 **HTTPS 服务地址**。Release 客户端仅允许 HTTPS 及上述本机调试地址；局域网 HTTP 联调请用 `flutter run` 的 debug 构建。Windows 本机默认连接 `http://localhost:8080`。

## 已实现的产品流程

| 页面 | 功能 |
| --- | --- |
| 欢迎页 | 学校选择、匿名身份创建、已有身份重连恢复、服务地址设置、社区与隐私说明 |
| 动态 | 校园广场、分类搜索、预填草稿话题、发帖、点赞、收藏、话题房间入口；左上角品牌进入设置 |
| 帖子详情 | 评论、匿名私聊入口、删除本人帖子、举报与屏蔽 |
| 话题房间 | 深夜树洞、课间茶水间、自习搭子、耳机分你一半；同校公共聊天 |
| 心动匹配 | 底部第二项；同校匿名资料卡堆叠，滑动表示心动或跳过，每日心动额度，互相心动即配对进入普通私聊；「喜欢我」与「配对」入口 |
| 聊天 | 按日期分组的私聊、未读数、Go 检索昵称及历史消息、每 3 秒更新当前对话 |
| 附近 | 底部第四项；主动开启大致定位，同校约 5 公里内，模糊距离、自动到期、关闭展示、一次性招呼进入私聊 |
| 我 | 匿名昵称、性别、简介、年级、标签、我的发布、我的收藏、隐私与数据 |
| 设置 | 动态页品牌入口；接收私聊开关、文字大小、动态背景、减少动态效果、隐私、关于和使用说明 |
| 官网 | 仓库内生成的首屏循环背景视频（Remotion + three.js）、引用摄影、真实 App 截图、响应式介绍、键盘可切换的界面展示、隐私问答、真实下载 |
| 运营接口 | 管理员查看举报、标记处理、隐藏被举报帖子 |

默认数据库没有假用户、假聊天或虚假的在线人数。Web 调试版的附近模拟列表由 `PREVIEW_NEARBY=true` 开启，明确标注预览，点击模拟招呼不会发送消息或发布位置；可切换真实列表。原生及默认构建不开启模拟列表。摄影和开源图标的 [素材来源](docs/assets.md) 已列明。自动化测试仅向独立的 `.tools/qa.db` 写入测试数据。

### 图片与视频

输入栏加号打开系统文件选择器；附件支持发送前预览、移除、真实上传进度、取消和失败重试，也可以不附带文字发送。收到图片后可放大查看，视频点击后播放、暂停和拖动进度。

支持 JPG / PNG / WebP（单张 10 MiB，解码上限 2500 万像素）和 MP4 / WebM（单个 50 MiB），每条最多 4 个附件，总计不超过 50 MiB。视频不转码，播放能力取决于设备编码支持，推荐 H.264 / AAC MP4。图片会重新编码以移除 EXIF；视频可能保留元数据。

附件并非公开静态文件：查看时检查校园、会话参与者、屏蔽状态和关联内容权限。播放链接是 15 分钟有效的临时凭证，请勿转发。媒体保存在后端 `MEDIA_DIR`，备份时必须与数据库一起保存。

视频在发送前显示本地静音暂停画面，发送后由 Go 调用 FFmpeg 生成 JPEG 封面；旧视频首次查看时自动补封面。FFmpeg 只安装在服务器，不打入客户端。Windows 可从 [FFmpeg 官方下载入口](https://ffmpeg.org/download.html) 安装并设置 `FFMPEG_PATH`；放在 `.tools/ffmpeg/<版本>/bin/ffmpeg.exe` 也会由启动脚本发现。Docker 镜像已声明 FFmpeg 依赖。缺少工具或无法解码时，界面明确提示封面不可用，原视频仍保留。

### 附近与性别

在「我」中选择「男 / 女 / 不透露」，默认不透露，不新增年龄、实名或头像资料。附近页右上角「附近设置」管理展示和更新位置。附近展示默认关闭，只有主动开启后才获取设备大致位置。Go 将位置按 0.01 度网格取整保存，约 30 分钟后自动隐藏；不返回坐标或精确距离，只显示距离范围，也不后台追踪位置。关闭展示会清除当前位置，已有私聊保留。

双方均须同校、开启附近且允许私聊，才可打招呼。首次会创建对话并发送一条固定招呼；重复操作只打开既有对话，不重复发送。每个身份每天最多建立 10 个新招呼（UTC 日期计数）。学生身份与实际位置未经认证，位置与距离均为估算。

### 心动匹配

「心动」页展示同校、允许私聊且未互相屏蔽的匿名资料卡，每次最多 20 张，已滑过的人不再出现，喜欢过我的人排在前面。每个身份每天最多心动 50 次（UTC 日期计数），心动需要本人开启接收私信，跳过不受限制。双方互相心动即配对，Go 创建一段普通私聊会话，之后与其他私聊没有区别；对同一个人重复同样的操作不会重复扣额度，跳过的人 30 天后可能再次出现。卡片不显示坐标或精确距离，只有双方都开启附近且相距不足约 5 公里时，才显示与附近相同的距离区间。

资料卡字段为一句话简介（最多 120 字）、年级（大一至大四）和最多 5 个兴趣标签（运动、音乐、阅读、摄影、美食、旅行、电影、游戏），均可留空；年级与标签列表由 Go 提供，客户端不能自定义。对应接口为 `GET /api/v1/discover`、`POST /api/v1/discover/{id}/swipe`、`GET /api/v1/discover/likes`、`GET /api/v1/discover/matches`，`GET /api/v1/config` 与 `PATCH /api/v1/me` 相应新增字段，详见 [部署与接口说明](docs/deployment.md)。

## 匿名的具体含义

无需手机号、真实姓名。学校当前为用户自选，**尚未接入学生身份认证**。匿名面向其他用户，运营方可以访问服务端内容；私聊不是端到端加密。

登录凭据在 Android 使用安全存储，在 Windows 使用 DPAPI，在服务器只保存 SHA-256 哈希，30 天后失效。当前不提供跨设备身份同步或账号找回。主动退出会删除本地凭据，重新进入会生成新身份；删除身份会同时删除其帖子、评论、消息、滑动记录和配对。

当前消息采用前台轮询，未接入离线系统推送。帖子列表显示最新 200 条；话题房间显示最新 200 条，私聊显示最新 500 条，接口支持时间游标读取后续消息。该版本适合单实例校园试运行；正式运营前需配置域名、HTTPS、管理员和备份，并按实际需求接入学校认证及推送服务。

## 构建与验证

新版 App 交互预览为 **http://localhost:8090**，使用独立的本地测试服务 `8081`；官网仍为 `8080`。预览启动和测试方法见 [验证记录](docs/verification.md)。

本项目使用 Flutter 3.44.8 / Dart 3.12.2、Go 1.25。当前环境的 Android SDK 位于 `.tools/android-sdk`；SDK 不属于需要分发的源码。

重新构建前请先停止正在运行的后端和桌面客户端，避免 Windows 锁定可执行文件。

```powershell
# 检查并构建 Android 与 Windows，默认使用本机开发服务地址
powershell -ExecutionPolicy Bypass -File .\scripts\build.ps1 -Android -Windows

# 仅验证与构建新版界面，不重建 Go 服务
powershell -ExecutionPolicy Bypass -File .\scripts\verify-glass.ps1 -Android -Windows

# 发布到自己部署的服务时，编译默认连接地址
powershell -ExecutionPolicy Bypass -File .\scripts\build.ps1 -Android -Windows -ApiUrl https://chat.example.com

# 客户端检查
cd client
flutter analyze
flutter test
flutter test integration_test/storage_test.dart -d windows

# 后端检查（从项目根目录）
cd server
go test ./... -count=1
go vet ./...
```

当前安卓包为自签测试发行版；正式分发时用自己的签名密钥。详细环境配置和 API 见 [部署与接口说明](docs/deployment.md)。本地验证截图保存在 `artifacts/`，不纳入 Git。

Android 构建脚本处理 Flutter 3.44.8 的开发测试插件注册问题，确保 `integration_test` 不进入发行包。默认使用已有 Gradle 缓存离线构建；新环境首次下载依赖可运行 `scripts/build-android-release.ps1 -Online`。完整项目仍需按 Flutter 要求安装 SDK/JDK。

## 代码位置

```text
client/lib/        Flutter 主题、页面、API 与会话
client/packages/   Windows 安全存储的 Dart FFI 集成及 MIT 许可
server/           Go API、SQLite、集成测试
server/web/       独立官网、引用摄影、Lucide 图标、真实 App 截图
scripts/          启动、构建与交互验证脚本
docs/             设计、部署与验证说明
dist/             实际发行文件
```

Windows 安全存储沿用上游 `flutter_secure_storage_windows` 4.2.2 的 Dart DPAPI 实现，移除新应用不需要的旧 C++ 凭据迁移注册，以免依赖 Visual Studio 可选 ATL 组件。变更和升级方法见 [集成说明](client/packages/flutter_secure_storage_windows/LOCAL_CHANGES.md)。中文字体为 Noto Sans SC，附带 SIL OFL 授权，界面不依赖外部图片或在线字体。

设计参考入口：[用户提供的 UI Design Guide](https://chrichuang218.github.io/awesome-ui-design/) 与 [MotionSites](https://motionsites.ai/)。官网已按后续反馈重做：采用 Unsplash 真实摄影、Lucide 图标和 App 运行截图，移除原版手绘装饰；具体来源见 [素材记录](docs/assets.md)。
