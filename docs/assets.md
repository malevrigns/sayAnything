# 官网素材来源

App 1.1 界面使用 Poppins（Google Fonts/SIL OFL）、中文无衬线回退及 `lucide_icons_flutter` 的 Lucide 图标。全局视频引用用户提供的 CloudFront URL，见 `client/lib/background.dart`；没有生成背景素材。字体授权均随应用资产打包。官网里的 App 截图已更新为 1.1 实际运行界面。

2026-09-10 按用户要求重做官网，移除原版手绘气泡、CSS 插画和 HTML 拼装的手机界面。当前素材全部来自下列引用来源；产品展示使用真实 App 运行截图。

| 使用位置 | 素材与作者 | 来源 |
| --- | --- | --- |
| 首屏摄影 | 毕业生抛帽，Pang Yuhao | [Unsplash 原作](https://unsplash.com/photos/_kd5cxwZOK4)，[图片源文件](https://images.unsplash.com/photo-1541339907198-e08756dedf3f) |
| 校园庭院 | 庭院与建筑，Vadim Sherbakov | [Unsplash 原作](https://unsplash.com/photos/d6ebY-faOO0)，[图片源文件](https://images.unsplash.com/20/cambridge.JPG) |
| 界面图标 | Lucide 0.468.0 | [Lucide](https://lucide.dev/)，[图标包来源](https://unpkg.com/lucide-static@0.468.0/)，[许可](https://lucide.dev/license) |
| 中文字体 | Noto Sans SC | [Google Fonts](https://fonts.google.com/noto/specimen/Noto+Sans+SC)，SIL OFL |
| App 展示 | 私聊、房间和校园广场 | 本项目真实运行截图，测试数据；截图来源位于 `artifacts/` |

摄影素材以下载的 WebP 副本在 `server/web/assets/` 提供服务，避免依赖第三方实时加载。图片使用遵循 [Unsplash License](https://unsplash.com/license)。摄影师与来源在页面内和「素材来源」弹窗中列出，图片不表示人物或学校已使用本应用。

Lucide SVG 保留原始文件，授权说明在 `server/web/assets/lucide-LICENSE.txt`。字体授权在 `server/web/fonts/OFL.txt`，本地精简字体可用 `python scripts/subset-font.py` 重新生成。

媒体上传测试使用现有校园摄影和 [Flutter 文档示例视频 bee.mp4](https://flutter.github.io/assets-for-api-docs/assets/videos/bee.mp4)，仅保存到本机 `artifacts/media-fixtures/` 进行播放验证，不作为产品素材或源码发行。App 不预置测试聊天附件。
