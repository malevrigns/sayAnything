# landing-video · 官网首屏背景视频

用 [Remotion](https://www.remotion.dev/) 驱动 three.js，逐帧生成官网首屏的背景循环视频，不含任何第三方影像素材。

## 画面

合成 `HeroLoop`：1920×1080，30 fps，450 帧，15 秒无缝循环。主题是「有些话，在这里慢慢说」的一个安静傍晚：

- 两枚磨砂玻璃对话气泡悬在暖色逆光里，边缘圆润，正面有缓慢扫过的反光。前面那枚气泡里有三个暖光点依次亮起，像对方正在慢慢输入。
- 身后一条象牙色缎带和一条带青柠光泽的墨绿丝绒缓慢扭转、起伏，颜色取自站点的 cream、forest 和 lime。
- 背景为森林黑到深咖的暗场，左侧留给网页文案，右侧是一团呼吸的暖光，空气里有少量光尘和焦外光斑。

## 渲染管线

全部代码在 `src/stage/`，每帧由 `useCurrentFrame()` 同步绘制，因此 Remotion 并行渲染的每个标签页结果一致。所有运动都是同一循环周期的整数倍，最后一帧直接衔接第一帧。

1. 背景层：暗场渐变、两条丝带、后面那枚气泡，渲染到带深度纹理的半浮点缓冲。
2. 景深：对背景层做单遍黄金角散景模糊，模糊半径由深度决定，焦点在前面那枚气泡上；离焦外的样本不会糊到较近的物体上。
3. 主体层：前面那枚气泡用透射材质折射已经虚化的背景，4 倍多重采样；光尘按各自的弥散圆大小绘制成焦外光斑。
4. 后期：轻微泛光，径向色差，暗角，AgX 色调映射加轻度对比，暗部偏森林绿、高光偏暖，胶片颗粒和 8 位抖动，避免暗部渐变在 H.264 下出现色带。

材质和光照：玻璃使用 three.js 的透射、色散、清漆和轻度虹彩；缎带和丝绒使用光泽层（sheen）；环境光来自一组柔光箱烘焙出的环境贴图，并随时间缓慢转动。

## 使用

```powershell
cd landing-video
npm install
npm run preview        # Remotion Studio 预览
npm run render:hero    # → out/hero-loop.mp4
npm run render:poster  # → out/hero-poster.jpg（第 0 帧）
npm run typecheck
```

`remotion.config.ts` 设定了输出参数：PNG 帧，H.264，crf 20，x264 preset slow，`yuv420p`，bt709 色彩标记；Chromium 的 OpenGL 后端为 `angle`，需要能创建 WebGL2 的显卡。无法使用硬件加速时可追加 `--gl swiftshader`，速度会慢很多。

渲染产物在 `out/`，已在仓库根 `.gitignore` 中忽略。把 `out/hero-loop.mp4` 与 `out/hero-poster.jpg` 复制到 `server/web/assets/video/` 即为官网使用的文件。`qa/hero-video.cjs` 用 Playwright 检查官网上视频的播放、暂停与减少动画行为。

## 许可提示

Remotion 对个人与小团队免费，公司使用需要其商业许可，详见 [remotion.dev 的许可说明](https://www.remotion.dev/license)。three.js 为 MIT 许可。
