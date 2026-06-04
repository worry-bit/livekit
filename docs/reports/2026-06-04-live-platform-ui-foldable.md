# 2026-06-04 直播平台选择 UI 与 Mate X7 折叠屏适配增量修改报告

## 修改目标

复刻折叠屏展开态的“开始直播”选择页面，并支持淘宝直播、抖音直播单选/双选。进入直播后，展开屏使用左右分屏；折叠到外屏时只展示左侧主直播内容。

## 修改文件

### entry/src/main/ets/pages/Index1.ets

新增 `LivePlatform` 枚举：
- `TAOBAO`：淘宝直播平台标识。
- `DOUYIN`：抖音直播平台标识。

新增两套独立串流参数常量：
- `TAOBAO_PARAMS`：淘宝直播的 `signalingUrl / boxId / token` 参数占位。
- `DOUYIN_PARAMS`：抖音直播的 `signalingUrl / boxId / token` 参数占位。

新增和重构的状态字段：
- `selectedTaobao / selectedDouyin`：记录两个平台是否选中，支持单选和双选。
- `isLiveStarted`：记录是否已进入直播态。
- `taobaoPlayer / douyinPlayer`：两个独立 `KooPhonePlayer` 实例，用于后续两套 token 和两个实例同时串流。
- `taobaoXCtrl / douyinXCtrl`：两个独立 `XComponentController`，分别承载两路视频 surface。
- `taobaoReady / douyinReady`：记录两路 `XComponent` 是否已加载完成。
- `taobaoStarted / douyinStarted`：防止同一路直播重复调用 `open()`。
- `rootWidth / rootHeight`：记录当前窗口尺寸，用于 Mate X7 展开/折叠布局切换。
- `taobaoStateText / douyinStateText`、`taobaoErrorText / douyinErrorText`：分别展示两路串流状态和错误。

新增主要方法：
- `hasSelection()`：判断是否至少选择一个直播平台；用于控制“开始直播”按钮可点击状态。
- `isExpandedScreen()`：根据当前窗口宽度是否达到 `EXPANDED_SCREEN_MIN_WIDTH` 判断是否使用展开屏左右分屏布局。
- `getPrimaryPlatform()`：确定左侧主直播平台；规则为优先淘宝，否则抖音。单选抖音时，抖音也固定显示在左半屏。
- `togglePlatform(platform)`：切换淘宝/抖音选中状态，支持单选、双选和取消选择。
- `startSelectedStreams()`：点击“开始直播”后进入直播态，并记录需要启动的直播平台。
- `startPlatformIfReady(platform)`：等对应 `XComponent` 获取 surfaceId 后再调用 `KooPhonePlayer.open()`，避免 surface 未就绪时发起串流。
- `closeAllStreams()`：页面退出时关闭两路播放器并重置启动标记。
- `handleSurfaceTouch(platform, event)`：把直播画面触摸事件分发给对应平台的 `KooInputController`，保留云手机输入控制能力。

新增 Builder：
- `selectionPage()`：复刻选择页 UI，包含左上角“开始直播”、中部“请选择直播平台”、两行平台选择项、右下角开始按钮。
- `platformOption(...)`：平台选择行组件，支持选中态圆形指示。
- `taobaoSurface()` / `douyinSurface()`：两路独立 `XComponent` surface，负责加载、销毁、尺寸同步和触摸转发。
- `streamPanel(platform)`：直播画面容器，承载对应平台的 `XComponent` 和状态浮层。
- `emptyLivePanel()`：未选择第二路直播时的右侧占位，显示“暂无直播内容”。
- `livePage()`：直播态布局；展开屏左右分屏，折叠/窄屏只展示主直播。

实现能力：
- 未选择平台时，右下角“开始直播”按钮置灰且不可点击。
- 选择淘宝、抖音任意一个或两个后，按钮变红且可点击。
- 单选任意平台时，直播画面固定显示在左侧/外屏主区域，右侧显示“暂无直播内容”。
- 双选时，展开屏左侧显示淘宝直播，右侧显示抖音直播。
- 折叠到外屏或窄屏时，只显示左侧主直播内容。

### LiveKit/src/main/ets/koophone/KooPhonePlayer.ets

新增字段：
- `currentSurfaceId`：记录当前最新视频渲染 surfaceId。

新增方法：
- `setSurfaceId(surfaceId: string)`：对外暴露 surface 更新能力，供折叠/展开导致 `XComponent` 重建后重新绑定渲染区域。

修改方法：
- `open(params, surfaceId)`：保存初始 `surfaceId` 到 `currentSurfaceId`。
- `setupSignalHandlers()`：不再捕获旧 surfaceId，收到 start 信令后使用当前最新 `currentSurfaceId`。
- `close()`：清理 `currentSurfaceId`。

补强能力：
- 解决信令 `start` 回调晚于折叠/展开重建时可能绑定旧 surfaceId 的竞态问题。

### LiveKit/src/main/ets/koophone/KooRTCSource.ets

新增字段：
- `rendererSurfaceId`：记录当前 renderer 已绑定的 surfaceId，避免重复初始化。
- `remoteVideoTrack`：缓存远端视频 track，供新 surfaceId 出现时重新绑定。

新增方法：
- `rebuildRenderer()`：释放旧 `NativeVideoRenderer`，用当前 surfaceId 创建新 renderer，并把缓存的远端视频 track 重新绑定进去。
- `releaseRenderer()`：统一释放 renderer，包含 `setVideoTrack(null)` 和 `release()`。

修改方法：
- `setSurfaceId(surfaceId)`：支持清空 surface、缓存 surface、在 PeerConnection 已创建时重建 renderer。
- `open(iceServers)`：如果已有 surfaceId，PeerConnection 创建后初始化 renderer。
- `close()`：统一释放 renderer、清理远端视频 track、清理 surface 记录。
- `ontrack` 处理：收到远端视频 track 后缓存，并在 renderer 可用时绑定。

补强能力：
- 支持 Mate X7 折叠/展开导致 `XComponent` 重建后的远端画面恢复渲染。
- 避免播放器未 open 时提前创建 `NativeVideoRenderer`，资源边界更清晰。

### entry/src/main/ets/entryability/EntryAbility.ets

修改方法：
- `onWindowStageCreate(windowStage)`：启动页从 `pages/Index` 切换为 `pages/Index1`。

实现能力：
- 应用启动后直接进入新的“开始直播”平台选择 UI。

## 当前参数说明

`TAOBAO_PARAMS` 和 `DOUYIN_PARAMS` 目前使用占位值：
- `wss://your-taobao-signal-server`
- `your-taobao-box-id`
- `your-taobao-token`
- `wss://your-douyin-signal-server`
- `your-douyin-box-id`
- `your-douyin-token`

后续拿到两套真实参数后，只需要替换 `Index1.ets` 顶部这两组常量。

## 验证结果

已执行：
- `git diff --check`：通过，无空白错误。
- 静态检查关键符号：确认 `Index1` 入口、两套参数、双实例播放器、surface 重绑方法均存在。

未执行：
- 未执行 Hvigor/DevEco 真机构建。当前本机命令行环境缺少 `hvigor` 和 `ohpm`：
  - `hvigor --version`：command not found
  - `ohpm --version`：command not found

需要在 DevEco Studio 或已配置 HarmonyOS CLI 的环境中进行最终编译和 Mate X7 真机验证。
