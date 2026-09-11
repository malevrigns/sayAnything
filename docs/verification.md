# 交付验证记录

## 1.4 视频封面、附近与性别（2026-09-11）

- Go 完整测试、`go vet` 通过，实际调用本机 FFmpeg 9.0.1 处理引用的 bee.mp4。覆盖新视频/旧视频封面、同票据权限、删除及并发发布、损坏视频/缺少工具、解码输入限制和输出上限。
- 附近后端测试覆盖旧数据库/会话迁移、性别枚举、位置取整、超时隐藏、跨校园/距离/屏蔽/私聊开关限制、并发招呼去重、每日限额与重启持久化。复核发现的位置迟到请求和资料覆盖问题已修复，增加 revision/CAS 与旧认证快照回归。
- Flutter 静态检查无问题，21 项测试通过，包括主动开启才定位、离开页面后不发送迟到位置、关闭后重新读取版本、封面使用原票据、静音暂停真实帧及播放器释放。
- `node scripts/nearby-e2e.cjs` 通过：浏览器使用明确的合成位置和隔离账号，验证性别、附近展示、一次招呼进入私聊、本地真实像素画面、JPEG 封面读取以及关闭后旧位置版本被拒绝。没有读取连接手机的真实位置，也没有向实际用户发送测试招呼。
- 原有 `test:e2e`、`test:media` 回归通过。四个 APK 和 Windows 构建完成；APK 均为 1.4.0（5），最低 API 24、目标 API 36，签名与 16 KiB ZIP 对齐通过，仅声明大致位置权限，无精确或后台定位权限。
- ARM64 为 31.41 MiB；通用包 65.30 MiB，ARMv7 28.97 MiB，x86_64 32.80 MiB，Windows ZIP 25.89 MiB。字体与旧包相同，服务器 FFmpeg 没有打进客户端。
- 五个客户端包的完整 HTTP 下载和 SHA-256 与发行清单一致。本机 Go 已更新，数据库升级前备份保存在忽略提交的 `artifacts/pre-1.4-database/`。

USB 更新尝试被手机系统拒绝：`INSTALL_FAILED_ABORTED: User rejected permissions`。未清除应用数据，尚未把 1.4 标记为真机安装/运行验证通过；需用户确认手机安装提示后再更新。封面及附近截图为本机 `artifacts/nearby-*.png`，不上传 Git。

## 1.3 Go 业务规则与安卓包优化（2026-09-11）

- Go 新增公开配置接口，校验与配置共用分类、字符数、媒体格式和大小定义。搜索改为服务端检索昵称和全部历史消息，保留参与者、屏蔽检查及未读语义。
- `go test ./... -count=1`、`go vet ./...` 通过。新增配置/写入边界、越权搜索、Unicode 大小写、字面通配字符、旧消息、附件总量及回滚、下载白名单测试。独立源码复核未发现重要问题。
- Flutter 静态检查无问题，13 项测试通过，覆盖服务端配置驱动输入提示、切换服务时清除旧令牌、搜索旧响应不能覆盖新输入，以及既有草稿/上传回归。
- Web、Windows、四个 Android release 包构建成功。Android 均为 1.3.0（4）、最低 API 24、目标 API 36，签名和 16 KiB ZIP 对齐通过，架构内容与文件名一致。
- 旧通用 APK 为 65.54 MiB；新通用包为 64.73 MiB，ARM64 为 31.06 MiB，ARMv7 为 28.66 MiB，x86_64 为 32.45 MiB。ARM64 比旧通用包小 52.61%，主要由架构拆分带来。字体 SHA-256 与旧包相同，图标裁剪已实际启用。
- `npm run test:e2e` 通过：原有产品流程、服务端搜索历史消息、360 / 390 / 430 / 1440 布局；`npm run test:media` 通过：选文件、图片查看、真实视频播放及帖子/评论/房间/私聊附件；`npm run test:visual` 通过：官网布局及架构包下载入口。
- `npm run test:downloads` 通过：四个 APK 与 Windows 包的完整 HTTP 下载字节数和 SHA-256 均与发行清单一致。

构建尺寸记录位于本机 `artifacts/android-size-before.json` 和 `android-size-after.json`，发行清单为 `dist/release-manifest.json`。未进行 Android 真机安装或硬件解码验证；安装包沿用自签测试证书。

## 1.2 图片与视频（2026-09-10）

新增真实附件上传、预览、播放及失败重试，覆盖帖子、评论、话题房间和私聊，保持校园匿名真人聊天主题。

- `flutter analyze --no-pub` 无问题，`flutter test --no-pub` 11 项通过；新增文件限制、部分上传成功后重试、消息提交期间禁止删除附件回归。
- Flutter Web release 构建成功，预览地址 `http://localhost:8090`，API 使用隔离的 `8081` 测试服务。
- 媒体 API 的 Go 测试覆盖上传、持久化、伪造文件、访问凭证、Range、校园隔离、屏蔽、绑定归属、幂等、并发额度及文件清理；`go vet ./...` 无问题。当前环境 CGO 关闭，未运行 Go race detector。
- 删除帖子、删除身份和关联附件使用同一事务；新增删除失败回滚、并发上传/评论与删除交错的回归，最终 `go test ./... -count=1` 通过。
- Android / Windows release 构建成功。APK 版本 1.2.0（3），最低 API 24、目标 API 36，v2 签名和 16 KB ZIP 对齐检查通过，沿用 Android Debug 测试证书。Windows EXE 版本 1.2.0+3，包中包含文件选择、视频播放插件及 VC 运行库。
- 官网 `npm run test:visual` 通过，验证 1440 / 390 / 360 尺寸、摄影素材加载、导航、FAQ 和下载状态。
- 两个客户端包均通过本机 HTTP 下载，字节数和 SHA-256 与 `dist/release-manifest.json` 一致。
- `npm run test:e2e` 对最终 Web 构建通过：真实广场、评论、双用户私聊、房间、搜索、设置、隐私及动态背景回退；360 / 390 / 430 / 1440 尺寸正常。自动化采用实际按键输入，并等待 Flutter 完成窗口尺寸变化后的布局。
- `npm run test:media` 对最终发行版 Go 后端通过：真实文件选择、WebP / MP4 上传、双用户附件读取、图片查看、视频播放进度及评论 / 房间 / 私聊附件。视频初始暂停，点击后播放进度实际增加。最终截图经复核，保存在本机 `artifacts/media-*.png`。
- 独立实测真实 MP4 的临时访问凭证、Range 206、未登录与跨校园拒绝访问；浏览器读到时长 4.036667 秒并实际播放。测试素材及数据均在本机隔离环境中。

本机 Flutter 3.44 的 Web 增量构建曾复用旧插件注册文件，造成文件选择一直等待。`scripts/verify-glass.ps1` 会移除 Web 入口的缓存 stamp 并重新生成注册代码；不会清理原生构建产物。

媒体 UI 自动化使用 `npm run test:media`。先按脚本提示将 Flutter 文档示例 `bee.mp4` 下载到 `artifacts/media-fixtures/`；图片默认使用仓库内已有摄影，可用 `QA_IMAGE_PATH` / `QA_VIDEO_PATH` 指定本机文件。截图及视频不上传 Git。

视频不会转码；测试中的 MP4 可播放不代表全部设备支持所有视频编码。未进行真实 Android 手机安装与硬件解码验证。

## 1.1 灰度玻璃界面更新（2026-09-10）

产品仍为校园人与人匿名聊天。Go 服务和实际会话保持，未增加 AI 回复或模拟对话服务。

- `scripts/verify-glass.ps1 -Android -Windows` 最终通过：静态检查无问题，8 项 Flutter 测试通过，Web、Android、Windows release 构建成功。
- 新增回归覆盖界面偏好持久化、消息读屏包含正文、页头标题对比度；此前草稿保留与身份恢复测试继续通过。
- `node scripts/glass-e2e.cjs` 使用真实 Go 测试服务验证发帖、评论、双用户私聊、房间、记录搜索、设置与隐私，390/360/430/1440 尺寸通过。桌面始终是居中 480px 单栏；视频加载被阻断时回退有效。
- 最终人工截图复核：标题为白色、操作图标为灰白、没有侧栏或横向溢出，设置截图无遮挡 Toast。
- 对最终聊天页、私聊页、设置页 PNG 进行像素检查，RGB 通道差大于 3 的像素数均为 0，确认截图为灰度。
- 1.1 最终 APK 验证 v2 签名和 16 KB ZIP 对齐通过，包名不变，版本 1.1.0（2），最低 Android API 24。两个客户端包均通过 HTTP 完整下载与 SHA-256 对照。
- 最终截图：进入校园（artifacts/glass-welcome.png，仅本机）、聊天页（artifacts/glass-feed.png，仅本机）、私聊（artifacts/glass-chat.png，仅本机）、房间（artifacts/glass-rooms.png，仅本机）、记录（artifacts/glass-records.png，仅本机）、设置（artifacts/glass-settings.png，仅本机）、字号（artifacts/glass-size.png，仅本机）、桌面（artifacts/glass-desktop.png，仅本机）。

视频地址按用户提供的链接接入，当前网络曾出现连接超时；已验证静态回退，不把未验证的远程播放状态报告为播放成功。原生 Windows 缺少对应视频播放平台插件，使用静态回退。真实 Android 设备安装仍未验证。

Android 发行流程在配置生成后剔除仅用于开发的 `integration_test` 自动注册，再直接调用 Gradle；脚本会在格式异常时明确失败，不把测试插件打入安装包。见 `scripts/build-android-release.ps1`。

## 1.0 基础功能验证

环境：Windows 11，Flutter 3.44.8 / Dart 3.12.2，Go 1.25.5；Android 编译 SDK 37、目标 SDK 36、最低 SDK 24、Build Tools 36.0.0、NDK 28.2.13676358、CMake 3.22.1、JDK 21。插件额外依赖的 SDK 35/36 也已安装。

## 已执行的验证

- `go test ./... -count=1 -cover`：通过，语句覆盖率 59.2%。覆盖真实 SQLite/HTTP 的身份、资料、发帖评论、点赞收藏、校园隔离、私聊权限、屏蔽举报、删除与持久化；以及 205 条房间消息、505 条私聊消息窗口和游标、30 天会话、用户限流、孤立已读记录清理回归。
- `go vet ./...`：通过。
- `flutter analyze`：无问题。
- `flutter test`：5 项通过。包含 360px 欢迎页、地址验证、慢网发送时保留后续输入、恢复既有匿名身份、断网切换分类的错误与重试状态。
- `flutter test integration_test/storage_test.dart -d windows`：原生 Windows 集成测试通过，实际调用 DPAPI 存储读写和删除一个专用测试凭据；未修改用户实际会话。
- `node scripts/e2e.cjs`：真实 Go 后端 + Flutter 浏览器预览，验证从 UI 创建身份、发帖、评论、改昵称、房间发送，以及第二个独立用户接收私聊并回复，第一端轮询收到。数据使用独立 QA 库和专属测试校园。
- `npm run test:visual`：重做后的摄影官网 1440px / 390px / 360px 布局、图片加载、横向溢出、菜单、画廊键盘操作、FAQ、素材来源弹窗及真实下载检查通过。
- Android `assembleRelease --offline`：构建成功，258 个 Gradle 任务。APK 为 63,971,418 字节，包含 arm64-v8a / armeabi-v7a / x86_64，版本 1.0.0（1）。`apksigner verify --verbose` 验证 APK v2 签名通过，使用开发签名回退。
- 安装包、Windows 包、Go 服务的 SHA-256 清单已生成至 `dist/release-manifest.json`。
- 两个客户端发行包均通过运行中的 HTTP 下载接口完整下载，文件字节数和 SHA-256 与清单一致。APK `zipalign -c -P 16 -v 4` 通过。
- Go 发行文件已重新从最终源码编译并替换，随后双用户端到端测试再次全部通过。

## 截图

- 安卓欢迎页（artifacts/android-welcome.png，仅本机）
- 校园广场（artifacts/android-square.png，仅本机）
- 双用户私聊（artifacts/android-chat.png，仅本机）
- 话题房间（artifacts/android-rooms.png，仅本机）
- 匿名资料页（artifacts/android-profile.png，仅本机）
- 深色模式（artifacts/android-profile-dark.png，仅本机）
- 桌面布局（artifacts/desktop-app.png，仅本机）
- 官网桌面全页（artifacts/website-desktop.png，仅本机）
- 官网手机全页（artifacts/website-mobile.png，仅本机）

应用截图来自同一 Flutter 页面代码的浏览器 QA 构建，不冒充安卓真机截图。当前 ADB 没有连接的设备，因此未执行真机安装、后台保活或设备厂商兼容性测试。Windows 凭据存储测试是本机原生运行。

Go race detector 未运行：当前环境未启用 CGO。Docker/Caddy 配置作为部署文件交付，本次未执行容器或公网部署。消息为前台轮询，校园认证与离线推送未接外部服务。

## 重新运行浏览器联调

1. 在 `server/` 启动独立 QA 服务，设置 `PORT=8081`、`DB_PATH=../.tools/qa.db`、`ALLOWED_ORIGIN=http://localhost:8090`。
2. 在 `client/` 执行 `flutter build web --release --dart-define=API_URL=http://localhost:8081 --no-web-resources-cdn`。
3. 在项目根目录启动 `node scripts/preview.cjs`，运行 `npm run test:e2e`（当前指向新版 `glass-e2e.cjs`）。

官网独立视觉检查默认访问 `http://localhost:8080`，运行正常本地服务后执行 `npm run test:visual`，不依赖 Flutter 预览服务。可以用 `SITE_URL` 环境变量更换官网检查地址。

在项目根目录执行 `npm ci` 安装锁定的 Playwright，机器上需已安装 Chrome。然后使用 `npm run test:e2e` / `npm run test:visual`。公网官网不需要 Node 或这个 QA 预览。
