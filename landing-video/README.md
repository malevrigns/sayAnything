# landing-video · 官网首屏背景视频

用 [Remotion](https://www.remotion.dev/) + three.js（`@remotion/three`）程序化生成官网首屏的背景循环视频，不含任何第三方影像素材。

- 合成 `HeroLoop`：1920×1080，30 fps，360 帧（12 s）。画面是抽象化的校园傍晚：奶油色到浅陶土色的暖色渐变、约 30 个半透明圆角形状（卡片、胶囊、对话气泡剪影）缓慢漂移并轻微旋转、朝奶油色衰减的景深雾、几十粒上升的小光点，以及缓慢推拉并轻微摇摆的镜头。
- 所有运动都由 `useCurrentFrame()` 推导，周期等于总帧数，首尾无缝衔接；随机值使用 Remotion 的 `random()`，渲染结果可复现。
- 配色与 `server/web/styles.css` 顶部的 CSS 变量一致（cream / clay / forest / lime 等）；画面不含文字，文案由网页承载。

## 使用

```powershell
cd landing-video
npm install
npm run preview        # Remotion Studio 预览
npm run render:hero    # → out/hero-loop.mp4（H.264，crf 24）
npm run render:poster  # → out/hero-poster.jpg（第 0 帧）
```

`remotion.config.ts` 默认使用 `angle` 作为 Chromium 的 OpenGL 后端，视频帧以 JPEG 截取以加快速度。若某台机器无法渲染，可改为 `swiftshader`（或在命令行追加 `--gl swiftshader`）。如果 Remotion 无法下载自带浏览器，可追加 `--browser-executable "C:\Program Files\Google\Chrome\Application\chrome.exe"`。

渲染产物在 `out/`（已在仓库根 `.gitignore` 中忽略）。把 `out/hero-loop.mp4` 与 `out/hero-poster.jpg` 复制到 `server/web/assets/video/` 即为官网实际使用的文件；目标体积：视频 ≤ 4 MB，若超出可把 `--crf` 提高到 28 或改以 1600×900 渲染。

## 许可提示

Remotion 对个人与小团队免费，公司使用需要其商业许可，详见 [remotion.dev 的许可说明](https://www.remotion.dev/license)。three.js、React Three Fiber 为 MIT 许可。
