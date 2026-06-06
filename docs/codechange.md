# 代码改动汇总

本文档汇总从上游 `SpikeX-21/livekit` 的 `upstream/main` 到个人仓库 `worry-bit/livekit` 当前功能代码之间的增量改动。

统计基准：

```bash
git diff upstream/main..a093c4e --stat
git diff upstream/main..a093c4e --name-status
```

说明：`a093c4e` 是本轮功能代码提交点；本文档本身不计入下面的功能代码统计。git 中仍保持 IAM 与 LiveKit SFU 占位符，真机安装完整体时才临时注入真实参数。

## 总体结论

这几轮改动不只是 `entry` 模块。

- `entry` 是主要业务页面承载模块，负责 Mate X7 折叠屏 UI、淘宝/抖音选择、开始/停止直播、外屏/内屏布局、本机 LiveKit 推流按钮和页面状态机。
- `LiveKit` 也有修改，原因是现有 KooPhone/LiveKit 封装原本还不具备动态 IAM + KooPhone 实例鉴权、短效 token 开流、折叠屏 surface 重绑、信令错误上抛、策略单测等能力。
- 如果后续目标是“尽量只改 entry”，可以把一部分纯策略和鉴权 service 从 `LiveKit/src/main/ets/koophone` 迁到 `entry`；但 `KooPhonePlayer / KooRTCSource / KooSignalClient / KooPhoneTypes` 这类底层串流能力仍建议留在 `LiveKit`，否则 `entry` 会直接侵入 SDK 内部实现。

按模块统计：

| 模块 | 文件数 | 主要内容 |
| --- | ---: | --- |
| `entry` | 3 | 主入口切到 `Index1`，Mate X7 折叠屏直播页，本机 LiveKit 摄像头推流适配 |
| `LiveKit` | 25 | KooPhone 鉴权、动态开流参数、surface 重建、信令/RTC 修复、导出 API、纯函数策略与单测 |
| `docs` | 15 | 每轮增量报告、调试指南、端到端路径说明 |

## entry 模块改动

### `entry/src/main/ets/entryability/EntryAbility.ets`

改动内容：

- 应用主入口从旧示例页 `pages/Index` 切到新的业务页 `pages/Index1`。

代码对比：

```diff
- windowStage.loadContent('pages/Index', (err) => {
+ windowStage.loadContent('pages/Index1', (err) => {
```

为什么改：

- `Index1.ets` 是 Mate X7 折叠屏直播业务页，后续所有淘宝/抖音 KooPhone 串流、本机摄像头推流和折叠屏布局都从这里进入。

### `entry/src/main/ets/pages/Index1.ets`

这是本次最大改动文件。

主要新增能力：

- Mate X7 折叠屏直播选择页：
  - 淘宝直播、抖音直播支持单选和双选。
  - 未选择时开始按钮置灰；选择后按钮变红并可点击。
  - 展开屏双栏显示：淘宝固定左侧，抖音固定右侧。
  - 单路直播时另一半可显示补开选择面板。
  - 外屏只显示当前主直播槽位。
- KooPhone 串流启动链路：
  - `startSelectedStreams()` 读取用户选择并启动对应平台。
  - `startPlatformIfReady(platform)` 等待 surface 准备好后执行 IAM + KooPhone auth，再调用 `KooPhonePlayer.open()`。
  - 每路直播独立维护 `shouldStart / isStarting / retryCount / lastError / surfaceId / surfaceRevision`。
- IAM + KooPhone 实例鉴权：
  - git 中保留 `__IAM_DOMAIN_NAME__ / __IAM_USER_NAME__ / __IAM_PASSWORD__` 占位符。
  - 真机完整体安装时临时注入真实 IAM 参数。
  - KooPhone auth URL 按实例 ID 动态拼接。
- 双实例与实例池容灾：
  - 淘宝优先使用一个实例，抖音优先使用另一个实例。
  - 每个实例失败后同实例最多重试 3 次。
  - 重试耗尽后从共享实例池选择未被另一直播占用的实例。
- 单路停止：
  - `stopPlatformStream(platform)` 只关闭对应平台，不影响另一平台。
  - 停止后保留选择状态，但补开面板中“已停止平台”可重新选择，“正在直播平台”置灰并显示“正在直播中”。
- 折叠态和 surface 修复：
  - `liveSurfaceLayer(platform)` 让直播 native surface 层常驻，只改变位置、尺寸、透明度和 zIndex。
  - `invalidatePlatformSurface()` / `refreshPlatformSurfaceId()` / `syncPlatformSurfaceAndStart()` 修复外屏停止后内屏补开仍显示“暂无直播内容”的问题。
  - `ENABLE_FOLDED_LIVE_SWITCH = false` 暂时隐藏外屏切换直播按钮，但保留切换逻辑。
- 本机 LiveKit 摄像头推流：
  - 新增 `开始直播推流 / 关闭直播推流` 全局按钮。
  - 点击开始时执行 `requestPermissions()` -> `joinRoom()` -> `publishVideo()`。
  - 点击关闭时执行 `unpublishVideo()` -> `leaveRoom()`。
  - 新增独立本机摄像头预览 XComponent，不能复用 KooPhone 云机画面 surface。
  - 新增切换摄像头按钮，调用 `liveKitUtil.switchCamera()`。

关键调用链：

```text
EntryAbility.onWindowStageCreate()
  -> windowStage.loadContent('pages/Index1')
  -> Index1.build()
  -> platformOption() / togglePlatform()
  -> startSelectedStreams()
  -> startPlatformIfReady(platform)
  -> KooAuthService.requestSdkToken()
  -> KooPhonePlayer.open()
  -> KooSignalClient + KooRTCSource
```

本机摄像头推流链路：

```text
liveKitPushButton()
  -> toggleLiveKitPush()
  -> startLiveKitPush()
  -> liveKitUtil.requestPermissions()
  -> liveKitUtil.joinRoom(LIVEKIT_SFU_URL, LIVEKIT_SFU_TOKEN)
  -> liveKitUtil.publishVideo(liveKitSurfaceId)
```

### `entry/src/main/ets/rtc/LiveKitUtil.ets`

改动内容：

- 把原来的示例式 void 方法改成可被页面可靠判断的 boolean 返回值。
- 增加 `hasMediaPermission / isVideoPublished / localVideoSurfaceId / errorMessage` 状态维护。
- `joinRoom(url, token)` 增加占位符检查、重复连接检查和连接结果判断。
- `publishVideo(surfaceId)` 增加 surface 非空检查、房间连接检查和 publish 结果判断。
- `unpublishVideo()` 和 `leaveRoom()` 清理推流状态。
- `switchCamera()` 只允许在视频已发布后调用。
- `requestPermissions()` 明确请求麦克风和摄像头权限，并返回是否授权成功。

代码对比：

```diff
- async joinRoom(url: string, token: string): Promise<void> {
+ async joinRoom(url: string, token: string): Promise<boolean> {
+   if (!this.isValidSfuParam(url) || !this.isValidSfuParam(token)) {
+     this.errorMessage = 'LiveKit SFU url/token 仍是占位符，请先替换为真实参数'
+     return false
+   }
```

```diff
- async publishVideo(surfaceId: string): Promise<void> {
+ async publishVideo(surfaceId: string): Promise<boolean> {
+   if (surfaceId.length === 0) {
+     this.errorMessage = '本机摄像头预览 surface 未准备好'
+     return false
+   }
+   if (!this.client.isConnected) {
+     this.errorMessage = 'LiveKit 房间未连接，无法发布视频'
+     return false
+   }
```

为什么改：

- 页面需要根据权限、连接、推流成功/失败准确更新按钮颜色、文案和错误提示。
- 本机摄像头推流必须能在失败时回滚到可重试状态，不能只在 console 中打印错误。

## LiveKit 模块改动

### 必须留在 LiveKit 的底层串流改动

这些文件直接改变 KooPhone/RTC/信令 SDK 的行为，属于底层能力。

#### `LiveKit/Index.ets`

改动内容：

- 导出 KooPhone 播放器、鉴权 service、实例池策略、折叠屏策略、本机推流策略和输入控制器。

代码对比：

```diff
+ export { KooPhonePlayer, createKooPhonePlayer } from './src/main/ets/koophone/KooPhonePlayer'
+ export { KooAuthService, createKooAuthService } from './src/main/ets/koophone/KooAuthService'
+ export { parseKooInstanceAuthResponse } from './src/main/ets/koophone/KooAuthParser'
+ export { selectNextAvailableKooInstance } from './src/main/ets/koophone/KooInstancePool'
+ export { shouldShowKooLiveAddPanel } from './src/main/ets/koophone/KooLiveSlotPolicy'
+ export { isLiveKitPushConfigReady } from './src/main/ets/koophone/LiveKitPushPolicy'
```

为什么改：

- `entry` 通过 `livekit-harmony` 包入口消费这些能力；不导出就只能使用相对路径侵入 HAR 内部文件。

#### `LiveKit/src/main/ets/koophone/KooPhoneTypes.ets`

改动内容：

- `KooPhoneParams` 增加 `streamingId`。
- 新增 `IamPasswordConfig / KooAuthConfig / LivePlatformConfig / KooAuthTokenResult`。
- 新增 `KooSignalPayload`，替代泛化的 `Record<string, Object>`。

代码对比：

```diff
 export interface KooPhoneParams {
   signalingUrl: string
   boxId: string
   token: string
+  streamingId?: string
 }

+ export interface KooAuthTokenResult {
+   token: string
+   signalingUrl: string
+   boxId: string
+   streamingId?: string
+   iceServers?: KooIceServer[]
+   expiresAt?: string
+ }
```

为什么改：

- KooPhone 实例鉴权接口返回的 `device_token / signaling_url / device_id / streamingId` 需要映射为 SDK 开流参数。
- 短效 token 不应在页面里拼散装对象，底层类型需要明确承载。

#### `LiveKit/src/main/ets/koophone/KooAuthService.ets`

新增文件。

能力：

- 调 IAM `POST /v3/auth/tokens`，从响应头 `X-Subject-Token` 读取 IAM token。
- 用 IAM token 调 KooPhone 实例鉴权接口。
- 从 KooPhone auth 响应解析出 SDK 开流所需的 `signalingUrl / token / boxId / streamingId / iceServers`。
- 对占位符配置做前置校验。

核心代码：

```ts
async requestSdkToken(config: LivePlatformConfig): Promise<KooAuthTokenResult> {
  const iamToken = await this.requestIamToken(config.iam)
  return this.requestKooPhoneAuth(config.kooAuth, iamToken)
}
```

为什么改：

- 之前页面/SDK 只能使用固定 `signalingUrl / boxId / token`，不能满足真实环境“先 IAM，再实例鉴权，device_token 约 15 秒有效”的流程。
- 重试时必须重新拿短效 token，这个逻辑放在 service 中更稳定。

#### `LiveKit/src/main/ets/koophone/KooAuthParser.ets`

新增文件。

能力：

- 解析 KooPhone 实例鉴权响应。
- 校验 `error_code`。
- 提取：
  - `data.resource.rtc.ice_signaling.signaling_url` -> `signalingUrl`
  - `data.device_token` -> `token`
  - `data.resource.device_id` -> `boxId`
  - `data.streamingId` -> `streamingId`

核心代码：

```ts
const signalingUrl = iceSignaling?.signaling_url ?? ''
const token = data?.device_token ?? ''
const boxId = resource?.device_id ?? ''
```

为什么改：

- 用户提供的真实 KooPhone auth 返回结构与最初预留的 `body.token` 不一致，必须改成解析真实返回体。

#### `LiveKit/src/main/ets/koophone/KooPhonePlayer.ets`

改动内容：

- 新增 `currentSurfaceId` 与 `setSurfaceId(surfaceId)`。
- `open()` 使用 auth 返回的 `streamingId`，没有则自动生成。
- `setupSignalHandlers()` 不再闭包绑定旧 surface，而是读取 `currentSurfaceId`。
- 信令关闭/错误时上抛错误，便于页面层触发重试。
- 日志中对 boxId/token/session/streamingId 做脱敏。
- 将信令 payload 类型从泛化对象改成 `KooSignalPayload`。

代码对比：

```diff
+ private currentSurfaceId: string = ''

+ setSurfaceId(surfaceId: string): void {
+   this.currentSurfaceId = surfaceId
+   this.rtcSource.setSurfaceId(surfaceId)
+ }

- this.streamingId = this.randomUuid()
+ this.streamingId = params.streamingId ?? this.randomUuid()

- this.setupSignalHandlers(surfaceId)
+ this.setupSignalHandlers()
```

为什么改：

- 折叠/展开时 ArkUI 的 XComponent surface 会变化，如果播放器一直渲染旧 surface，就会出现内屏补开显示“暂无直播内容”、画面跑到外屏的问题。
- 实例鉴权返回的 `streamingId` 需要参与 KooPhone init payload。

#### `LiveKit/src/main/ets/koophone/KooRTCSource.ets`

改动内容：

- 新增 `rendererSurfaceId` 和 `remoteVideoTrack`。
- `setSurfaceId()` 支持 surface 变化时重建 NativeVideoRenderer。
- 收到远端视频 track 后，如果 surface 后到，也能补建 renderer。
- close 时清理 renderer/surface/track 状态。

关键代码：

```ts
setSurfaceId(surfaceId: string): void {
  if (this.surfaceId === surfaceId && this.rendererSurfaceId === surfaceId) {
    return
  }
  this.surfaceId = surfaceId
  this.rebuildRenderer()
}
```

为什么改：

- 这是修复 Mate X7 折叠态/展开态 surface 竞态的底层关键点。
- 单靠 `entry` 重新渲染 UI 不能保证 WebRTC NativeVideoRenderer 自动切到新 surface。

#### `LiveKit/src/main/ets/koophone/KooSignalClient.ets`

改动内容：

- 使用 HarmonyOS `@kit.NetworkKit.webSocket` 管理 Socket.IO v2 WebSocket 帧。
- 把 `http/https` signaling URL 自动转成 `ws/wss`。
- 增加 `emitStart(boxId, times)`，AUTHORIZED 后发送 `start` 帧。
- 增加 `onError` 回调，连接错误可上抛给 `KooPhonePlayer`。
- 统一脱敏日志中的 `boxid / token / sessionid / streamingid`。

代码对比：

```diff
+ if (baseUrl.startsWith('http://')) {
+   baseUrl = 'ws://' + baseUrl.slice('http://'.length)
+ } else if (baseUrl.startsWith('https://')) {
+   baseUrl = 'wss://' + baseUrl.slice('https://'.length)
+ }

+ const frame = `42["start",${JSON.stringify({ room: boxId, times })}]`
+ this.sendFrame(frame)
```

为什么改：

- KooPhone auth 返回的是 HTTP 形式的 signaling URL，原生 WebSocket 不能像浏览器 socket.io-client 那样自动转换协议。
- 页面需要识别信令失败并做三次重试/实例切换。

#### `LiveKit/src/main/ets/koophone/KooInputController.ets`

改动内容：

- `TouchAction / KeyAction` 从对象常量改为 enum。

代码对比：

```diff
- export const TouchAction = { DOWN: 0, UP: 1, MOVE: 2 }
+ export enum TouchAction { DOWN = 0, UP = 1, MOVE = 2 }
```

为什么改：

- ArkTS 类型检查和 `entry` 侧导入使用 enum 更稳定，触摸转发给云机时也更明确。

#### `LiveKit/src/main/ets/util/LiveKitClient.ets`

改动内容：

- 新增只读 getter `videoPublished`。

代码对比：

```diff
+ get videoPublished(): boolean {
+   return this.isVideoPublished
+ }
```

为什么改：

- `entry/src/main/ets/rtc/LiveKitUtil.ets` 需要准确判断 `publishVideo / unpublishVideo` 后底层 SDK 是否真的处于发布状态。

#### `LiveKit/src/main/ets/util/RTCEngine.ets`

改动内容：

- 调整关闭视频和切摄像头时的 `VideoSource` 释放方式：停止 track，清理引用，不再直接调用 `videoSource.release()`。

代码对比：

```diff
- this.videoSource.release()
  this.videoSource = null
- console.info('[RTCEngine] VideoSource released')
+ console.info('[RTCEngine] VideoSource cleared')
```

为什么改：

- 当前 HarmonyOS WebRTC binding 下 `VideoSource.release()` 在构建/运行链路中不稳定；页面只需要确保视频轨道停止、引用释放、后续可重新 publish/switch。

### 可迁移到 entry 的策略/辅助改动

这些文件是纯函数或业务策略，放在 `LiveKit` 里主要是为了被 HAR 单测直接覆盖。如果后续强制要求“只改 entry”，可以迁到 `entry/src/main/ets/...`。

#### `LiveKit/src/main/ets/koophone/KooInstancePool.ets`

新增文件。

能力：

- 从共享实例池中选择下一个未尝试、未被其他直播占用的实例。

为什么改：

- 实例失败三次后需要自动切换备用实例。
- 双直播不能抢占同一个实例。

#### `LiveKit/src/main/ets/koophone/KooLiveSlotPolicy.ets`

新增文件。

能力：

- 判断内屏空半屏是否展示补开面板。
- 判断外屏默认显示左侧还是右侧。
- 保留外屏切换按钮策略，但通过开关隐藏。
- 生成带 revision 的 XComponent id，强制 ArkUI 重建 surface。
- 生成补开面板“正在直播中”标注。

为什么改：

- 这些规则是 bug 修复重点，抽成纯函数后可以用单测覆盖，避免 UI 状态回归。

#### `LiveKit/src/main/ets/koophone/LiveKitPushPolicy.ets`

新增文件。

能力：

- 判断 LiveKit SFU 参数是否仍是占位符。
- 生成“开始直播推流/关闭直播推流/推流中/关闭中”文案。
- 生成绿色/红色/灰色按钮颜色。
- 判断所有 KooPhone 直播停止时是否应自动关闭本机摄像头推流。

为什么改：

- 本机摄像头推流是全局能力，需要稳定的按钮状态策略。

### 编译/旧 JS 参考文件适配

以下文件主要不是业务逻辑，而是为了让 DevEco/Hvigor 打包和单测解析旧 H5 参考文件时不再依赖浏览器/npm 模块。

新增 shim 文件：

- `LiveKit/src/main/ets/koophone/Constants.js`
- `LiveKit/src/main/ets/koophone/ErrCode.js`
- `LiveKit/src/main/ets/koophone/Version.js`
- `LiveKit/src/main/ets/koophone/lib/EventEmitter.js`
- `LiveKit/src/main/ets/koophone/lib/SocketIOClient.js`
- `LiveKit/src/main/ets/koophone/lib/WebRTCAdapter.js`
- `LiveKit/src/main/ets/koophone/util/ConsoleLog.js`
- `LiveKit/src/main/ets/koophone/util/SdpUtils.js`
- `LiveKit/src/main/ets/koophone/util/Utils.js`

同步修改：

```diff
- import SocketIO from 'socket.io-client';
+ import SocketIO from './lib/SocketIOClient';

- import 'webrtc-adapter';
+ import './lib/WebRTCAdapter';
```

为什么改：

- HarmonyOS HAR 构建环境不能直接按浏览器工程方式解析 `socket.io-client` 和 `webrtc-adapter`。
- 当前真正运行路径是 ArkTS 的 `KooSignalClient / KooRTCSource / KooPhonePlayer`，这些 JS shim 只是让历史参考文件在打包/测试解析时可闭合。

### `LiveKit/src/test/LocalUnit.test.ets`

改动内容：

- 新增 KooPhone auth response parser 测试。
- 新增共享实例池选择策略测试。
- 新增内屏补开面板、外屏默认槽位、外屏切换开关策略测试。
- 新增本机 LiveKit 推流按钮/配置策略测试。

为什么改：

- 折叠态 UI 状态和重试/实例切换规则容易回归，纯函数单测比直接绑 UI 结构更稳定。

## docs 模块改动

新增/更新文档：

- `docs/koophone-live-debug-guide.md`
- `docs/reports/2026-06-04-live-platform-ui-foldable.md`
- `docs/reports/2026-06-04-build-run-and-ui-state-fixes.md`
- `docs/reports/2026-06-05-koophone-instance-auth.md`
- `docs/reports/2026-06-05-mate-x7-real-device-e2e.md`
- `docs/reports/2026-06-05-iam-token-real-e2e-success.md`
- `docs/reports/2026-06-05-single-stop-folded-switch-instance-pool.md`
- `docs/reports/2026-06-05-expanded-add-second-stream-panel.md`
- `docs/reports/2026-06-05-live-add-panel-reselect-and-ui-polish.md`
- `docs/reports/2026-06-05-folded-dual-switch-and-add-panel.md`
- `docs/reports/2026-06-06-folded-stable-surface-and-controls.md`
- `docs/reports/2026-06-06-folded-switch-hidden-and-reopen-surface.md`
- `docs/reports/2026-06-06-folded-stop-inner-reopen-surface.md`
- `docs/reports/2026-06-06-reopen-live-state-reactivity.md`
- `docs/reports/2026-06-06-livekit-local-camera-push.md`

文档主要覆盖：

- Mate X7 折叠屏 UI 与状态机。
- IAM + KooPhone auth + KooPhonePlayer 的端到端路径。
- 真实设备调试、签名、构建、安装和占位符恢复流程。
- 每轮 bug 修复的根因、改动和验证命令。

## 如果后续要减少 LiveKit 改动

可以拆成两类处理。

建议保留在 `LiveKit`：

- `KooPhonePlayer.ets`
- `KooRTCSource.ets`
- `KooSignalClient.ets`
- `KooPhoneTypes.ets`
- `LiveKitClient.ets`
- `RTCEngine.ets`
- `KooInputController.ets`

原因：这些文件是 SDK 内部能力，涉及信令、WebRTC、surface、输入控制和 LiveKit 客户端状态，不适合由页面层硬改。

可以迁到 `entry`：

- `KooAuthService.ets`
- `KooAuthParser.ets`
- `KooInstancePool.ets`
- `KooLiveSlotPolicy.ets`
- `LiveKitPushPolicy.ets`

迁移代价：

- 需要调整 `entry` 的 import 路径。
- 需要把相关单测从 `LiveKit/src/test` 移到 entry 可运行的测试目录，或者继续保留在 LiveKit 中测试公共策略。
- `LiveKit/Index.ets` 可以减少导出项，但 KooPhonePlayer/Types 仍需要导出。

## 敏感信息与公开仓库说明

- git 中没有提交真实 IAM 明文密码、真实 LiveKit SFU token。
- git 中保留的是占位符：
  - `__IAM_DOMAIN_NAME__`
  - `__IAM_USER_NAME__`
  - `__IAM_PASSWORD__`
  - `__LIVEKIT_SFU_URL__`
  - `__LIVEKIT_SFU_TOKEN__`
- 代码和历史文档中仍包含环境相关的 KooPhone 实例 ID、内网 KooPhone auth base URL 示例。公开给其他人使用前，应确认这些是否允许公开；如果不允许，需要再做一轮配置脱敏，把实例 ID 和内网地址也改成占位符。

## 验证命令

本轮文档提交前建议执行：

```bash
git diff --check
```

功能代码上一轮已验证过：

```bash
hvigorw test --no-daemon --stacktrace -p properties.enableSignTask=false
hvigorw clean assembleApp --no-daemon --stacktrace
hdc install -r entry/build/default/outputs/default/entry-default-signed.hap
```

完整代码对比命令：

```bash
git diff upstream/main..a093c4e -- entry
git diff upstream/main..a093c4e -- LiveKit
git diff upstream/main..a093c4e -- docs
```
