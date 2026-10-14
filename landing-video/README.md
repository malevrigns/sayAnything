# landing-video · 官网首屏背景视频

用 [Remotion](https://www.remotion.dev/) 驱动 three.js，逐帧生成官网首屏的背景循环视频，不含任何第三方影像素材。导演流程按 frame-smith skill：先定方向和三个旋钮，只选一个主效果，再排节拍、出入场和检查清单。

## SignalLoop（官网在用）

合成 `SignalLoop`：1920×1080，30 fps，450 帧，15 秒无缝循环，静音。

方向：黑色高级调性、强科技感。匿名的信号汇聚成一句话。ENERGY 4 · SPECTACLE 9 · DENSITY 3。

主效果是粒子聚合：约 9 万颗银白粒子在黑场里绕成一个倾斜的信号星盘，一道青柠色激光从左扫到右，被扫过的粒子离开轨道，落成一个发光的立体对话气泡；气泡外有一圈 HUD 准星光环，里面三个点像对方在打字。画面主体放在右侧约六成，左侧留黑给网页文案。

| 时间 | 节拍 | 这一拍只做一件事 |
| --- | --- | --- |
| 0.0 s | HOLD | 气泡完整，光环锁定，三个点依次亮起（也是海报帧） |
| 2.6 s | RELEASE | 外壳从左往右剥离，粒子沿轨道流回星盘，光弧收回 |
| 5.6 s | ORBIT | 只剩星盘运转，十字准星在暗处搜索 |
| 8.2 s | SCAN | 激光从左扫到右，粒子落位，轮廓在光束后描出 |
| 11.0 s | LOCK | 光弧带回弹锁定，打字点逐个弹出，背景点阵荡开一圈信号波 |
| 15.0 s | — | 回到第 0 帧，首尾无缝 |

为网页背景做的取舍：

- 不放片尾字标：首屏标题就叠在视频上，循环落在「气泡锁定」这个画面上，第 0 帧即是它。
- 不配乐：网页背景视频必须静音才能自动播放，音轨不会被听到，只会增大文件。
- 不加光线拖尾和漂浮光尘：每颗粒子都参与组成气泡，背景点阵只在锁定那一下荡开一次。

## 代码结构

- `src/compositions/SignalLoop.tsx`：合成本体，导出 `SignalLoop`、`SignalLoopCover`、`SIGNAL_LOOP_FRAMES`。
- `src/signal/timeline.ts`：节拍表和全部包络（`f(秒)`、限幅插值、缓动和回弹）。
- `src/signal/particles.ts`：星盘与气泡粒子，位置由循环相位、扫描前沿和擦除前沿在着色器里算出。
- `src/signal/hud.ts`：准星光环、气泡轮廓、扫描光束、十字准星。
- `src/signal/field.ts`：黑场和远处的点阵光源（焦外成柔和圆斑，锁定时荡开信号波）。
- `src/signal/stage.ts`：相机、泛光、调色（AgX、暗角、轻微色差；纯黑处不加颗粒和抖动，网页黑底能无缝衔接）。

每帧都由帧号同步绘制，Remotion 并行渲染的每个标签页结果一致。所有运动都是同一循环周期的整数倍，或在节拍内收敛回原位。

## 使用

```powershell
cd landing-video
npm install
npm run preview        # Remotion Studio，Hero 文件夹里选 SignalLoop
npm run render:hero    # → out/hero-loop.mp4（H.264，crf 25）
npm run render:poster  # → out/hero-poster.jpg（第 0 帧，网页 <video poster>）
npm run render:cover   # → out/signal-cover.png（1920×1440 封面）
npm run typecheck
```

`remotion.config.ts` 设定 PNG 帧、H.264、x264 preset slow、`yuv420p`、bt709 色彩标记；Chromium 的 OpenGL 后端为 `angle`，需要能创建 WebGL2 的显卡。本机渲染整段约 30–50 秒。crf 25 时约 4.4 MB，放大比对与无损帧几乎无差别；crf 23 约 6.1 MB，crf 20 约 9.6 MB。

渲染产物在 `out/`，已在仓库根 `.gitignore` 中忽略。把 `out/hero-loop.mp4` 与 `out/hero-poster.jpg` 复制到 `server/web/assets/video/` 即为官网使用的文件。`qa/hero-video.cjs` 用 Playwright 检查官网上视频的播放、暂停、署名和减少动画行为。

## 存档

`Archive/HeroDusk` 是上一版暖色傍晚方向（磨砂玻璃气泡、缎带和丝绒、真实景深），保留作对比，代码在 `src/stage/` 与 `src/HeroLoop.tsx`。

## 许可提示

Remotion 对个人与小团队免费，公司使用需要其商业许可，详见 [remotion.dev 的许可说明](https://www.remotion.dev/license)。three.js 为 MIT 许可。
