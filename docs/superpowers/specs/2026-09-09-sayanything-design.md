# SayAnything / 说点什么

2026-09-10 更新：用户要求提升官网质感、引用现成素材。官网已改用 Unsplash 摄影、Lucide 图标和实际 App 截图，取消原方案的手绘装饰与拼装手机模型。来源见 `docs/assets.md`；App 的原有品牌和功能保持。Android 与 Windows 自签测试发行物已生成，详见 `docs/verification.md`。

用户要求直接实现成品，安卓优先，Go 后端，官网仅介绍与下载。当前仓库为空。

## 产品与视觉
校园匿名交流：广场、话题房间、消息、我的四个导航入口，中间突出发布按钮。奶油白 #F8F7F2、森林绿 #244D3F、杏橙 #EEAA7B；大字号标题、细线边框、留白、手绘几何植物与对话气泡。名称「说点什么」，英文 SayAnything，标语「在这里，做不被定义的自己」。参考用户提供的 UI Design Guide 中的 Mobbin/移动流程方向与 MotionSites 社区分类，原创实现，不复制付费模板。

## 架构
client/: Flutter，Android/Windows 原生应用，共享适配界面；web 构建仅内部 QA。server/: Go HTTP API + SQLite，令牌仅哈希落库，持久化内容。server/web/: 独立静态介绍页，无聊天入口。发行物放 dist/，后端提供真实文件下载。

## API 契约
所有路径 /api/v1；JSON；认证 Authorization: Bearer token；错误 {error:string}。
POST /session {campus:string} -> {token:string,user:User}。GET /me -> User。PATCH /me {alias?,allowDM?} -> User。DELETE /me 注销并删除内容与令牌。
User: {id,alias,campus,avatar:int,allowDM:bool,createdAt:string}。
GET /posts?category=&q=&saved=1&mine=1 -> Post[]；POST /posts {body,category} -> Post；GET /posts/{id} -> Post；DELETE /posts/{id} 自己的帖子。
Post: {id,authorId,alias,avatar,campus,body,category,createdAt,likes:int,comments:int,liked:bool,saved:bool}。
POST /posts/{id}/like 或 /save 切换 -> {active:bool}。
GET /posts/{id}/comments -> Comment[]；POST 同路径 {body} -> Comment；Comment: {id,authorId,alias,avatar,body,createdAt}。
GET /rooms -> Room[]；Room: {id,name,description,emoji,messages:int}，预置四个校园隔离的公共话题房间。
GET /rooms/{id}/messages?after= -> Message[]；POST 同路径 {body} -> Message。
POST /conversations {postId} -> Conversation；GET /conversations -> Conversation[]；GET/POST /conversations/{id}/messages 与房间同形。
Conversation: {id,alias,avatar,lastMessage,updatedAt,unread:int}；Message: {id,authorId,alias,avatar,body,createdAt}。GET 私聊消息标记已读。
POST /reports {targetType:post|message|user,targetId,reason} -> {ok:true}；POST /blocks {userId}、GET /blocks -> User[]、DELETE /blocks/{id}。屏蔽双向限制私聊并隐藏内容。
GET /health -> {ok:true}；GET /api/downloads -> {android:bool,windows:bool}。下载对应 /downloads/sayanything-android.apk 与 /downloads/sayanything-windows.zip。

## 边界与验证
校园自选，明确未校验学生身份；匿名针对其他用户，并非对运营方不可追溯。无模拟私信与虚假在线人数。默认空数据库，仅预置话题房间；示例数据仅测试独立库。私聊需校园一致、参与者权限与接收设置。帖子正文最多1000字，消息最多2000字；空白、越权、跨校园均拒绝。单实例 SQLite WAL；API 限流、请求体上限、SQL 参数化。生产部署 HTTPS，通过环境变量配置服务端口/数据库/管理员密钥/允许的开发 Origin。离线清晰报错，发送失败保留输入，3秒轮询新消息。

验证 Go 接口集成测试（多用户、越权、校园隔离、持久化、举报屏蔽）；Flutter analyze/widget tests；浏览器预览多尺寸截图；Android APK 构建；Windows 构建条件具备则一起交付。正式域名与学生认证服务需运营方提供，成品交付本地运行和部署配置。
