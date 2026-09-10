# 部署与接口

## 运行 Go 服务

从 `server/` 目录启动：

```powershell
$env:PORT = '8080'
$env:DB_PATH = '../sayanything.db'
$env:WEB_DIR = 'web'
$env:DOWNLOAD_DIR = '../dist'
go run .
```

生产环境在反向代理后监听，配置 HTTPS。`server/Caddyfile.example` 给出了单域名 Caddy 配置，使用时将示例域名改为自己控制的实际域名。Docker 配置提供持久卷，仅把端口映射到宿主机回环地址，供 HTTPS 代理使用：

```sh
docker compose up --build -d
```

Docker 配置已提供，但本次本机交付不意味着已部署公网服务。SQLite 使用 WAL，当前适用于单实例。停止服务后备份数据库及其仍存在的 `-wal`、`-shm` 文件；运行期间请使用 SQLite 在线备份工具，避免仅复制主文件丢失未 checkpoint 的写入。

| 环境变量 | 默认值 | 用途 |
| --- | --- | --- |
| PORT | 8080 | HTTP 监听端口 |
| DB_PATH | sayanything.db | SQLite 文件，父目录需存在且可写 |
| MEDIA_DIR | 数据库同目录的 media/ | 附件存储目录；Docker 使用 /data/media |
| WEB_DIR | web | 官网静态资源 |
| DOWNLOAD_DIR | ../dist | 真实安装包存放目录 |
| ALLOWED_ORIGIN | 空 | 允许的单个浏览器 Origin；原生客户端不依赖 CORS |
| ADMIN_TOKEN | 空 | 独立运营密钥；为空时管理接口不可用 |

公网部署不需要开放 Flutter Web 预览。`scripts/preview.cjs` 与 `client/build/web` 仅用于内部 UI 检查；官网没有聊天入口。

## 管理举报

服务启动前设置随机管理密钥。示例在当前 PowerShell 会话内生成，不打印密钥：

```powershell
$randomBytes = New-Object byte[] 32
$rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
$rng.GetBytes($randomBytes)
$rng.Dispose()
$env:ADMIN_TOKEN = [Convert]::ToBase64String($randomBytes)
powershell -ExecutionPolicy Bypass -File .\scripts\start.ps1
```

管理员密钥与用户令牌独立。通过安全的部署配置保存密钥，客户端中不包含它。在相同环境变量可用的终端查看举报：

```powershell
$headers = @{ Authorization = "Bearer $env:ADMIN_TOKEN" }
$reports = Invoke-RestMethod -Uri 'http://localhost:8080/api/v1/admin/reports' -Headers $headers
$reports | Select-Object id,targetType,targetId,reason,resolved

# 将选中的帖子举报标记为已处理，并隐藏该帖子
$report = $reports | Where-Object { -not $_.resolved -and $_.targetType -eq 'post' } | Select-Object -First 1
if ($report) {
  Invoke-RestMethod -Method Patch -Uri "http://localhost:8080/api/v1/admin/reports/$($report.id)" -Headers $headers -ContentType 'application/json' -Body '{"resolved":true,"hidePost":true}'
}
```

当前运营接口支持举报状态和帖子隐藏；消息与用户举报可登记及标记处理，没有独立网页后台，也不自动删除被举报内容。

## API 约定

业务接口前缀 `/api/v1`，JSON 请求与响应，错误为 `{"error":"中文提示"}`。除了创建会话与公共资源，都要求 `Authorization: Bearer <token>`。正文按 Unicode 字符验证：帖子最多 1000 字，评论及消息 2000 字，学校 80 字。昵称 API 上限 40 字，客户端输入上限 24 字。请求体大小上限由服务端统一限制。成功删除返回 204。

| 方法与路径 | 请求/行为 |
| --- | --- |
| POST /session | `{campus}` → `{token,user}` |
| POST /media | multipart 单个 `file`；可带 `X-Upload-Id` 幂等键，返回媒体对象 |
| POST /media/{id}/ticket | 获取 15 分钟临时访问链接 `{url,expiresAt}` |
| GET /media/{id} | Bearer 或临时 ticket；支持 HEAD 和 Range 视频分段读取 |
| DELETE /media/{id} | 删除自己尚未绑定到内容的附件 |
| GET /me | 当前匿名身份 |
| PATCH /me | `{alias?,allowDM?}` |
| DELETE /me | 永久删除身份与其内容 |
| GET /posts | `category`、`q`、`saved=1`、`mine=1` 可组合 |
| POST /posts | `{body,category}` |
| GET /posts/{id} | 单条帖子 |
| DELETE /posts/{id} | 仅作者 |
| POST /posts/{id}/like | 切换点赞，返回 `{active}` |
| POST /posts/{id}/save | 切换收藏，返回 `{active}` |
| GET /posts/{id}/comments | 评论列表 |
| POST /posts/{id}/comments | `{body}` |
| GET /rooms | 当前校园的话题房间 |
| GET /rooms/{id}/messages | 最新窗口；可传 `after` 时间戳 |
| POST /rooms/{id}/messages | `{body}` |
| POST /conversations | `{postId}`，创建或打开与作者的私聊 |
| GET /conversations | 会话与未读数 |
| GET /conversations/{id}/messages | 最新窗口；可传 `after`；读取已送达消息后更新已读 |
| POST /conversations/{id}/messages | `{body}`；检查双方屏蔽和接收设置 |
| POST /reports | `{targetType,targetId,reason}` |
| GET /blocks | 屏蔽列表 |
| POST /blocks | `{userId}` |
| DELETE /blocks/{id} | 解除屏蔽 |
| GET /admin/reports | 独立管理员密钥 |
| PATCH /admin/reports/{id} | `{resolved,hidePost}` |

帖子分类为 `校园日常`、`心事树洞`、`搭子集合`、`恋爱碎碎念`、`学习交流`。房间 ID 为 `treehole`、`daily`、`study`、`music`。

上述发帖、评论、房间消息、私聊消息接口均可附带 `mediaIds: string[]`（最多 4 个）和 `clientId: string`（同一次发送重试沿用原值）。允许正文为空的纯附件内容；响应增加 `attachments` 数组。先上传再绑定，选择文件本身不会上传。上传失败后复用已成功的附件，不重复插入消息。

附件对象包含 `id`、`kind`、`mimeType`、`name`、`size` 和图片宽高。图片接受 JPEG / PNG / WebP，上限 10 MiB、2500 万像素，服务端重新编码并移除 EXIF；视频接受 MP4 / WebM，上限 50 MiB，只检查容器结构，不转码或承诺所有编码都能播放。每人未发送附件额度为 100 MiB；上传并发及内存有界，过期未绑定附件定期回收。临时播放链接包含短期访问凭证，不包含登录令牌；每次请求重新检查关联内容权限，返回 `private, no-store`。

备份和恢复必须同时覆盖数据库与 `MEDIA_DIR`；最简单的方法是停止服务后复制两者。反向代理需要允许至少 51 MiB 请求体及适当的上传超时。不要把媒体目录映射为公开静态目录。删除内容或身份会清理关联附件；文件删除失败时通过持久化回收队列重试。

公共接口没有 `/api/v1` 前缀：`GET /health`、`GET /api/downloads`。下载只允许 `sayanything-android.apk` 和 `sayanything-windows.zip` 两个文件名，不开放任意目录浏览。官网读取下载状态；文件不存在时禁用下载按钮。

## 安卓正式签名

发行包默认使用开发签名以方便本地安装。正式运营时，创建自有 keystore，并配置 `client/android/key.properties`。该文件与 `.jks` 已被 Git 忽略。字段为 `storeFile`、`storePassword`、`keyAlias`、`keyPassword`。密钥需妥善保管，后续更新必须使用同一签名。具体路径以 Gradle `file()` 解析位置为准，推荐使用绝对路径。
