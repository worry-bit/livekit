# 代码改动汇总

本文档说明当前 `worry-bit/livekit` 的最新模块边界，重点区分 `entry` App 与 `LiveKit` SDK。

## 当前结论

- `entry` 是 App，负责 Mate X7 折叠屏 UI、KooPhone IAM/实例鉴权、实例池、槽位策略、本机推流按钮策略和业务单测。
- `LiveKit` 是 SDK，当前已替换为 `SpikeX-21/livekit` 的最新 `upstream/main` 内容，并在 SDK 内补齐 KooPhone 顶层导出和 ArkTS 编译修复。
- `entry` 不再复制 `LiveKit` SDK 的底层实现，也不再使用 `livekit-harmony/src/main/ets/...` 深路径。
- `entry` 统一通过 `livekit-harmony` 顶层接口消费 SDK。

当前 upstream 基准：

```text
SpikeX-21/livekit upstream/main: bbc34ea5c09bca92ef80e94488e2655e021ae21a
```

## entry 模块

### `entry/src/main/ets/pages/Index1.ets`

主业务页，负责：

- Mate X7 内屏/外屏选择和串流布局。
- 淘宝、抖音单选/双选开播。
- 单路停止直播、补开第二路直播。
- KooPhone 实例三次重试和实例池切换。
- 本机摄像头 LiveKit 推流按钮入口。

SDK 导入方式：

```ts
import {
  KooInputController,
  TouchAction,
  TouchPoint,
  createKooPhonePlayer,
  KooPhonePlayer,
  KooPhoneError,
  KooPhoneParams,
  KooPhoneState
} from 'livekit-harmony'
```

### `entry/src/main/ets/koophone/**`

只保留 App 业务编排文件：

| 文件 | 作用 |
| --- | --- |
| `KooAuthTypes.ets` | IAM、KooPhone auth、直播平台配置和 SDK token 结果类型；`KooIceServer` 从 SDK 顶层导入 |
| `KooAuthService.ets` | 调 IAM `POST /v3/auth/tokens`，读取响应头 `X-Subject-Token`，再调用 KooPhone auth |
| `KooAuthParser.ets` | 解析 KooPhone auth 返回的 `signaling_url / device_token / device_id / streamingId` |
| `KooInstancePool.ets` | 共享实例池选择策略，跳过当前实例、已尝试实例和被另一路占用实例 |
| `KooLiveSlotPolicy.ets` | 内屏补开面板、外屏默认槽位、外屏切换开关、surface component id 策略 |

`entry/src/main/ets/koophone` 中没有播放器、信令、RTC、输入控制的 SDK 复制件。

### `entry/src/main/ets/rtc/LiveKitUtil.ets`

页面调用的本机摄像头推流门面：

- `requestPermissions()`：申请相机和麦克风权限。
- `joinRoom(url, token)`：连接 LiveKit SFU。
- `publishVideo(surfaceId)`：开启本机摄像头并发布视频。
- `unpublishVideo()`：取消发布视频。
- `leaveRoom()`：离开房间并重建客户端。
- `switchCamera()`：切换前后摄像头。

SDK 导入方式：

```ts
import { AudioLevelInfo, createLiveKitClient, LiveKitClient } from 'livekit-harmony'
```

### `entry/src/main/ets/livekit/**`

该目录已删除。`entry` 不再维护 `AudioManager / LiveKitClient / RTCEngine / SignalClient / ProtobufCodec / types` 等 SDK 复制实现。

## LiveKit SDK 模块

### 本轮替换

已从 `SpikeX-21/livekit` 拉取 `upstream/main` 并用其 `LiveKit/` 替换当前 SDK 模块。

upstream 新增的 `LiveKit/src/main/ets/koophone/KooUserMedia.ets` 已纳入当前仓库。

### 本轮 SDK 修改

按用户提供的 1-11 项修复并补充：

| 文件 | 修改内容 |
| --- | --- |
| `LiveKit/src/main/ets/koophone/KooInputController.ets` | 为 `TouchAction / KeyAction` 对象字面量补显式接口类型，满足 ArkTS 严格检查 |
| `LiveKit/src/main/ets/koophone/KooPhonePlayer.ets` | 补 `setupUserMediaHandlers()` 的 camera track 通知结构、answer/candidate payload 显式字段、`keeping_time=60`、SDP `toJSON()`、UUID 生成逻辑 |
| `LiveKit/src/main/ets/koophone/KooRTCSource.ets` | DataChannel message 类型改为 `string \| ArrayBuffer`，offer/answer 补 `toJSON()` |
| `LiveKit/src/main/ets/koophone/KooSignalClient.ets` | 增加 `StartPayload` 接口，`emitStart()` 使用显式类型 |
| `LiveKit/Index.ets` | 顶层导出 KooPhonePlayer、状态、错误、参数、输入控制和 KooUserMedia |
| `LiveKit/src/main/ets/util/RTCEngine.ets` | 去掉当前 `@ohos/webrtc` 类型不存在的 `VideoSource.release()` 调用 |
| `LiveKit/src/main/ets/koophone/KooUserMedia.ets` | 去掉当前 `@ohos/webrtc` 类型不存在的 `VideoSource.release()` 调用 |

`VideoSource.release()` 是编译时发现的额外问题。如果保留该调用，`entry:test` 和 `assembleApp` 都会失败；当前做法是停止 video track 后清空 `VideoSource` 引用。

### SDK 顶层导出

`LiveKit/Index.ets` 现在导出：

```ts
export { createKooPhonePlayer, KooPhonePlayer } from './src/main/ets/koophone/KooPhonePlayer'
export { KooPhoneState, KooPhoneError } from './src/main/ets/koophone/KooPhoneTypes'
export type { KooPhoneParams, KooIceServer } from './src/main/ets/koophone/KooPhoneTypes'
export { KooInputController, TouchAction, KeyAction, createKooInputController } from './src/main/ets/koophone/KooInputController'
export type { TouchPoint, SendDataFn } from './src/main/ets/koophone/KooInputController'
export { KooUserMedia, createKooUserMedia } from './src/main/ets/koophone/KooUserMedia'
```

## 验证结果

已通过：

```bash
/Applications/DevEco-CommandLineTools/6.1.1.280/command-line-tools/bin/ohpm install
git diff --check
/Applications/DevEco-CommandLineTools/6.1.1.280/command-line-tools/bin/hvigorw test --no-daemon --stacktrace -p properties.enableSignTask=false
/Applications/DevEco-CommandLineTools/6.1.1.280/command-line-tools/bin/hvigorw clean assembleApp --no-daemon --stacktrace -p properties.enableSignTask=false
```

HAP 输出：

```text
entry/build/default/outputs/default/app/entry-default.hap
entry/build/default/outputs/default/entry-default-unsigned.hap
```

运行检查：

```bash
/Applications/DevEco-CommandLineTools/6.1.1.280/command-line-tools/sdk/default/openharmony/toolchains/hdc list targets
```

结果为 `[Empty]`，当前没有可安装运行的真机或模拟器目标，所以本轮未能实际安装启动 App。

## 敏感信息处理

git 中继续只保留占位符：

- `__IAM_DOMAIN_NAME__`
- `__IAM_USER_NAME__`
- `__IAM_PASSWORD__`
- `__LIVEKIT_SFU_URL__`
- `__LIVEKIT_SFU_TOKEN__`

真机安装完整体时可以临时注入真实参数构建 HAP；构建安装后必须恢复占位符再提交。
