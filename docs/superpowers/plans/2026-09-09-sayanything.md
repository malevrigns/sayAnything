# SayAnything Implementation Plan

**Goal:** 可运行的校园匿名交流 Android/Windows 客户端、Go 后端和介绍下载官网。

**Architecture:** Flutter 调用 Go JSON API，SQLite 持久化；官网独立静态资源由 Go 托管。

**Tech Stack:** Flutter 3.44 / Dart 3.12 / Go 1.25 / SQLite。

用户已要求直接实现，执行方案不再要求额外审批。依据 subagent-driven-development 技能，独立委派后端与构建环境，本地实现客户端与官网并验证集成。

- [x] 后端：依设计文档契约先写真实 HTTP 测试，覆盖令牌、发帖评论、跨校园与私聊越权、屏蔽、删除、落盘重启，再实现与执行 `go test ./...`。
- [x] 客户端：先验证窄屏欢迎页、表单校验、导航与可访问按钮；实现 API/安全令牌存储/统一主题，再实现 onboarding、广场、帖子详情、发帖、房间、私聊、个人设置。
- [x] 官网：引用摄影与开源图标的响应式静态介绍页，使用真实下载可用性 API，下载不存在时展示未发布。使用 Playwright 检查 390px 与 1440px。
- [x] 发布：Android INTERNET 权限与自签测试发行包，Windows release ZIP；真实签名可由环境文件配置；启动脚本、Docker、使用文档。
- [x] 联调：`flutter analyze`、`flutter test`、`go test ./...`、双会话聊天测试、APK 构建，检查截图和交付文件，记录尚未验证的设备差异。
