# 2026-06-04 编译运行与直播选择页补强增量报告

## 本次目标

在 Mate X7 折叠屏模拟器上完成当前代码的编译、安装和运行，并修复运行验证中发现的 UI 状态问题；同时补齐 ArkTS 严格类型编译问题，让工程可以通过 HarmonyOS 6.1.1 CLI 构建。

## 修改文件与增量说明

### `entry/src/main/ets/pages/Index1.ets`

修改导入方式：
- 从包名 `livekit-harmony` 导入 `createKooPhonePlayer`、`KooPhonePlayer`、`KooInputController`、`KooPhoneState`、`KooPhoneError`、`KooPhoneParams`、`TouchAction`、`TouchPoint`。
- 避免 entry 模块通过深层相对路径依赖 HAR 内部源码路径，保持模块边界清晰。

新增方法：
- `isPlatformSelected(platform: LivePlatform): boolean`
  - 直接根据 `LivePlatform.TAOBAO / LivePlatform.DOUYIN` 读取 `selectedTaobao / selectedDouyin`。
  - 用于选择圆点渲染，避免 ArkUI `@Builder` 参数缓存导致选中圆点不刷新的问题。

修改方法/Builder：
- `handleSurfaceTouch(platform, event)`
  - 为 `player` 和 `ctrl` 增加明确类型 `KooPhonePlayer`、`KooInputController`，满足 ArkTS 严格类型检查。
- `selectIndicator(platform)`
  - 从传入 `selected: boolean` 改为传入 `platform` 并直接读取组件状态。
  - 修复“按钮已变红但圆点未填充”的运行时 UI 状态不同步问题。
- `platformOption(platform, title)`
  - 移除 selected 参数，内部调用 `selectIndicator(platform)`。
- `selectionPage()`
  - 将系统 `Button` 改为自绘胶囊 `Row + Text`。
  - 通过 `hasSelection()` 同时控制背景色和点击保护。
  - 修复 Mate X7 模拟器上未选择平台时系统 Button 默认样式覆盖灰态的问题。

实现能力：
- 未选择平台时，“开始直播”按钮稳定显示灰色，点击直接 return。
- 选择任意平台后，选择圆点与按钮同步变红。
- 单选平台后点击开始直播，展开屏进入左右分栏：左侧串流面板，右侧“暂无直播内容”。

### `LiveKit/Index.ets`

新增导出：
- `KooPhonePlayer`
- `createKooPhonePlayer`
- `KooPhoneState`
- `KooPhoneError`
- `KooPhoneParams`
- `KooInputController`
- `TouchAction`
- `TouchPoint`

实现能力：
- entry 模块可以通过 HAR 包入口 `livekit-harmony` 使用云手机串流播放器能力。
- 不再依赖 HAR 模块内部文件路径，后续迁移、打包和复用更稳定。

### `LiveKit/src/main/ets/koophone/KooInputController.ets`

修改类型：
- `TouchAction` 从对象常量改为 `enum TouchAction`。
- `KeyAction` 从对象常量改为 `enum KeyAction`。

实现能力：
- 消除 ArkTS 对对象字面量枚举值推断不稳定的问题。
- 让 `sendTouchEvent()` 等输入控制调用具备明确枚举类型。

### `LiveKit/src/main/ets/koophone/KooPhoneTypes.ets`

新增接口：
- `KooSignalPayload`
  - 字段：`type?`、`sdp?`、`label?`、`id?`、`candidate?`。

修改接口：
- `KooSignalMessage.payload?: KooSignalPayload`

实现能力：
- 替换 `Record<string, Object>` 动态 payload，减少 ArkTS 严格模式下的动态索引访问。
- 为 offer、answer、candidate 三类 WebRTC 信令提供统一结构。

### `LiveKit/src/main/ets/koophone/KooSignalClient.ets`

新增接口：
- `SocketPayload`
- `StartFramePayload`
- `DataFramePayload`
- `MessageFramePayload`

修改方法：
- `emitStart(boxId, times)`
  - 使用 `StartFramePayload` 构造 start 帧。
- `emitData(type, to, data)`
  - 使用 `DataFramePayload` 构造 init/data 帧。
- `emitMessage(type, to, payload)`
  - payload 类型改为 `KooSignalPayload`。
- `handleEventFrame(frameText)`
  - 使用结构化属性读取 `authorized`、`code`、`streamId`、`vcodec`、`type`、`from`、`payload`、`data`。

实现能力：
- 消除 `payload['xxx']` 动态索引写法。
- 提高 Socket.IO 信令解析在 ArkTS 严格模式下的可编译性和可维护性。

### `LiveKit/src/main/ets/koophone/KooPhonePlayer.ets`

修改方法：
- `setupRTCHandlers()`
  - `onDescription` 参数类型改为 `webrtc.RTCSessionDescriptionInit`。
  - answer/candidate 发送 payload 类型改为 `KooSignalPayload`。
- `handleRemoteMessage(message)`
  - offer/answer/candidate payload 读取改为结构化字段读取。
  - 远端 SDP 类型使用 `webrtc.RTCSdpType`。
- `resolvePayload(message)`
  - 返回类型改为 `KooSignalPayload | null`。
- `generateUuid()`
  - 使用 `hex.charAt(...)` 替代字符串下标访问，规避 ArkTS 字符串索引兼容问题。

实现能力：
- WebRTC SDP 与 ICE candidate 信令处理通过 HarmonyOS 6.1.1 ArkTS 编译。
- 减少动态类型和动态索引，降低运行时类型错误风险。

### `LiveKit/src/main/ets/koophone/KooRTCSource.ets`

修改类型：
- `onDescription` 回调类型改为 `webrtc.RTCSessionDescriptionInit`。
- `setRemoteDescription(sdp)` 参数类型改为 `webrtc.RTCSessionDescriptionInit`。

修改方法：
- `createAnswer()`
  - 使用 `RTCSessionDescriptionInit` 作为 answer 结构传递给上层。

实现能力：
- 与 `@ohos/webrtc` 当前 API 返回值保持一致。
- 修复 `RTCSessionDescription` 与 `RTCSessionDescriptionInit` 类型不匹配导致的编译问题。

### `LiveKit/src/main/ets/util/RTCEngine.ets`

修改方法：
- `disableCamera()`
- `switchCamera()`
- `close()`

变更内容：
- 移除 `videoSource.release()` 调用。
- 保留 `videoTrack.stop()`，并将 `videoSource` 清空。
- 日志从 `VideoSource released` 调整为 `VideoSource cleared`。

实现能力：
- 适配当前 `@ohos/webrtc` 的 `VideoSource` 类型，避免调用不存在的 `release()` 方法导致编译失败。

## 本地环境与模拟器处理

已完成：
- DevEco Command Line Tools 可用：
  - `ohpm --version`: `6.1.2.268`
  - `hvigorw --version`: `6.24.2`
  - `hdc -v`: `3.2.0d`
- 通过断点续传补齐 SDK 镜像：
  - HarmonyOS 6.1.1 phone/foldable 通用镜像包：`2368047697` bytes
  - HarmonyOS 5.0.4 foldable 镜像包：`2349696839` bytes
- 创建 Mate X7 折叠屏模拟器：
  - 实例名：`Mate_X7_LiveKit`
  - 展开屏：`2210 x 2416`
  - 外屏：`1080 x 2444`
  - API：`24`

## 验证结果

已执行并通过：
- `hvigorw clean assembleApp --no-daemon --stacktrace -p properties.enableSignTask=false`
  - 结果：`BUILD SUCCESSFUL`
- `hdc install -r entry/build/default/outputs/default/app/entry-default.hap`
  - 结果：`install bundle successfully`
- `aa start -b com.hssw.livekit -a EntryAbility`
  - 结果：`start ability successfully`
- `ps -ef | grep com.hssw.livekit`
  - 结果：应用进程存在，说明已运行。

Mate X7 展开屏截图验证：
- 未选择平台：按钮为灰色，点击受保护。
- 选择淘宝直播：圆点和按钮同步变红。
- 点击开始直播：进入左右分栏，左侧为淘宝直播串流面板，右侧显示“暂无直播内容”。

## 当前限制

`TAOBAO_PARAMS` 和 `DOUYIN_PARAMS` 仍为占位参数，当前只能验证 UI、串流入口调用和布局状态。后续替换为两套真实 `signalingUrl / boxId / token` 后，可继续验证真实云手机画面。

当前仓库 `build-profile.json5` 仍引用同事机器的 `/Users/mac/.ohos/config/...` 签名路径。本次没有提交任何本机私钥、证书或 profile 文件；模拟器运行使用关闭签名任务后的 HAP 完成安装验证。

## 2026-06-04 追加验证目标

本轮在已跑通 Mate X7 模拟器的基础上继续增加：
- 外屏/窄屏也能选择淘宝/抖音并开始直播。
- 直播态增加停止串流入口。
- 新增 IAM token + KooPhone auth 预留接口调用链。
- 新增 SDK token 15 秒短有效期下的 3 次自动重试策略。
- 新增 `docs/koophone-live-debug-guide.md`，用于说明主入口、页面加载、点击链路、串流链路、架构图、时序图和环境问题。

真实 IAM/KooPhone 凭据仍不入库，当前占位配置会触发参数不完整错误，用于验证错误展示和重试保护。

## 2026-06-04 最终构建运行记录

已执行并通过：
- `ohpm install`
- `git diff --check`
- `hvigorw clean assembleApp --no-daemon --stacktrace -p properties.enableSignTask=false`
- `hdc -t 127.0.0.1:5555 install -r entry/build/default/outputs/default/app/entry-default.hap`
- `hdc -t 127.0.0.1:5555 shell aa start -b com.hssw.livekit -a EntryAbility`
- `hdc -t 127.0.0.1:5555 shell ps -ef | rg com.hssw.livekit`

验证截图：
- `outputs/livekit-auth-selection.jpeg`
- `outputs/livekit-douyin-selected.jpeg`
- `outputs/livekit-douyin-live-expanded.jpeg`
- `outputs/livekit-double-selected.jpeg`
- `outputs/livekit-double-live-expanded-final.jpeg`

本轮额外修复：
- `KooAuthService` 将 `http.request()` 包进 `safeRequest()`，消除新增鉴权服务中的 NetworkKit 抛异常 warning。
- `KooSignalClient` 将 open/connect/send/error 失败统一透传给 `onError`。
- `KooPhonePlayer` 将非主动信令关闭转换为 `SIGNAL_CONNECT_FAILED`，让页面层三次重试覆盖异常 close。
- 直播态停止按钮从右上角移动到右下角，避免遮挡右侧直播面板顶部状态。

本地签名处理：
- 用户已在本机完成 DevEco 自签名。
- `build-profile.json5` 中出现本机证书路径和加密口令，该文件不纳入功能提交。
- 本次 CLI 构建仍使用 `properties.enableSignTask=false` 验证，避免把签名配置作为远端仓库依赖。

仍存在的非阻塞 warning：
- `@ohos/webrtc` 与本地资源存在若干重复资源名 warning。
- `RTCEngine.ets` 仍有既有 `ESObject` 限制 warning。
- `AudioManager.ets` 和 `entry/src/main/ets/rtc/LiveKitUtil.ets` 有既有 API deprecated warning。
