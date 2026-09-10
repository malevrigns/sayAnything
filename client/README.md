# 说点什么 · Flutter 客户端

Android 和 Windows 共享一套 Flutter 页面、主题和 Go API 客户端。详细运行方式见 [项目说明](../README.md)。

```powershell
flutter pub get
flutter analyze
flutter test
flutter run -d windows
```

默认 Windows 服务地址为 `http://localhost:8080`，Android 模拟器为 `http://10.0.2.2:8080`，可在欢迎页连接设置中更改，或用 `--dart-define=API_URL=https://your-domain.example` 编译。

`web/` 仅为内部交互验证入口。对外官网位于 `../server/web/`，只提供介绍与下载。
