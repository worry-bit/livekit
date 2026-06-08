# 代码改动汇总

本文档说明当前 `worry-bit/livekit` 相对最初 `SpikeX-21/livekit` 的模块边界状态，重点回答两个问题：

- `entry` 模块里现在还剩哪些业务改动。
- `entry` 是否还复制了 `LiveKit` SDK 里的实现文件。

## 总体结论

当前边界已调整为：

- `entry` 是 App，只保留 Mate X7 UI、KooPhone 鉴权、实例池、槽位策略、LiveKit 推流门面和业务单测。
- `LiveKit` 是 SDK，源码保持最初拉取状态；本轮没有修改 `LiveKit` 下任何文件。
- `entry` 不再持有 `LiveKit` SDK 的复制实现，已经删除 `entry/src/main/ets/livekit/**` 和 `entry/src/main/ets/koophone` 下的播放器/信令/RTC/输入控制复制文件。
- `entry` 通过 `livekit-harmony: file:../LiveKit` 依赖 SDK。KooPhone 相关能力因为 `LiveKit/Index.ets` 当前没有顶层导出，只能暂时使用 `livekit-harmony/src/main/ets/koophone/...` 深路径导入。

验证命令：

```bash
git diff --name-status e5fb1b5 -- LiveKit
comm -12 <(find entry/src/main/ets -type f -name '*.ets' -exec basename {} \; | sort) <(find LiveKit/src/main/ets -type f -name '*.ets' -exec basename {} \; | sort)
```

当前结果：

- `LiveKit` diff 为空。
- `entry/src/main/ets` 与 `LiveKit/src/main/ets` 下同名 `.ets` 文件扫描为空。

## entry 模块保留内容

### `entry/src/main/ets/pages/Index1.ets`

主业务页，负责：

- Mate X7 内屏/外屏选择和串流布局。
- 淘宝、抖音单选/双选开播。
- 单路停止直播、补开第二路直播。
- KooPhone 实例三次重试和实例池切换。
- 本机摄像头 LiveKit 推流按钮入口。

SDK 依赖方式已改为：

```ts
import { createKooPhonePlayer, KooPhonePlayer } from 'livekit-harmony/src/main/ets/koophone/KooPhonePlayer'
import { KooPhoneError, KooPhoneParams, KooPhoneState } from 'livekit-harmony/src/main/ets/koophone/KooPhoneTypes'
import { KooInputController, TouchAction, TouchPoint } from 'livekit-harmony/src/main/ets/koophone/KooInputController'
```

### `entry/src/main/ets/koophone/**`

当前只保留 App 业务文件：

| 文件 | 作用 |
| --- | --- |
| `KooAuthTypes.ets` | IAM、KooPhone auth、直播平台配置和 SDK token 结果类型；`KooIceServer` 从 SDK 类型导入 |
| `KooAuthService.ets` | 调 IAM `POST /v3/auth/tokens`，读取响应头 `X-Subject-Token`，再调用 KooPhone auth |
| `KooAuthParser.ets` | 解析 KooPhone auth 返回的 `signaling_url / device_token / device_id / streamingId` |
| `KooInstancePool.ets` | 共享实例池选择策略，跳过当前实例、已尝试实例和被另一路占用实例 |
| `KooLiveSlotPolicy.ets` | 内屏补开面板、外屏默认槽位、外屏切换开关、surface component id 策略 |

已删除的 SDK 复制文件：

| 删除文件 | SDK 对应文件 | 删除原因 |
| --- | --- | --- |
| `entry/src/main/ets/koophone/KooPhonePlayer.ets` | `LiveKit/src/main/ets/koophone/KooPhonePlayer.ets` | 播放器属于 SDK 原子能力，`entry` 改为从 SDK 导入 |
| `entry/src/main/ets/koophone/KooPhoneTypes.ets` | `LiveKit/src/main/ets/koophone/KooPhoneTypes.ets` | SDK 类型不在 App 内重复维护 |
| `entry/src/main/ets/koophone/KooRTCSource.ets` | `LiveKit/src/main/ets/koophone/KooRTCSource.ets` | WebRTC PeerConnection 和渲染器管理属于 SDK |
| `entry/src/main/ets/koophone/KooSignalClient.ets` | `LiveKit/src/main/ets/koophone/KooSignalClient.ets` | Socket.IO/WebSocket 信令属于 SDK |
| `entry/src/main/ets/koophone/KooInputController.ets` | `LiveKit/src/main/ets/koophone/KooInputController.ets` | 云机输入编码属于 SDK |

删除前比对结果：

| 文件 | 差异规模 |
| --- | --- |
| `KooPhonePlayer.ets` | 85 行差异，57 行新增，28 行删除 |
| `KooPhoneTypes.ets` | 50 行差异，49 行新增，1 行删除 |
| `KooRTCSource.ets` | 80 行差异，63 行新增，17 行删除 |
| `KooSignalClient.ets` | 107 行差异，88 行新增，19 行删除 |
| `KooInputController.ets` | 14 行差异，7 行新增，7 行删除 |

### `entry/src/main/ets/rtc/LiveKitUtil.ets`

页面调用的本机摄像头推流门面：

- `requestPermissions()`：申请相机和麦克风权限。
- `joinRoom(url, token)`：连接 LiveKit SFU。
- `publishVideo(surfaceId)`：开启本机摄像头并发布视频。
- `unpublishVideo()`：取消发布视频。
- `leaveRoom()`：离开房间并重建客户端。
- `switchCamera()`：切换前后摄像头。

该文件不再使用 `entry/src/main/ets/livekit/**`，改为直接从 SDK 顶层入口导入：

```ts
import { AudioLevelInfo, createLiveKitClient, LiveKitClient } from 'livekit-harmony'
```

### `entry/src/main/ets/livekit/**`

该目录已删除。删除文件如下：

- `AudioManager.ets`
- `LiveKitClient.ets`
- `ProtobufCodec.ets`
- `RTCEngine.ets`
- `SignalClient.ets`
- `types.ets`

删除原因：

- 这些文件是 `LiveKit/src/main/ets/util/**` 的 SDK 实现复制件。
- 当前 App 不应在 `entry` 内维护 SDK 底层实现。
- 业务侧只通过 `LiveKitUtil.ets` 调用 SDK 导出的能力。

### `entry/src/main/ets/push/LiveKitPushPolicy.ets`

纯业务策略文件，负责：

- 判断 `LIVEKIT_SFU_URL / LIVEKIT_SFU_TOKEN` 是否仍是占位符。
- 生成“开始直播推流 / 关闭直播推流 / 推流中... / 关闭中...”按钮文案。
- 生成绿色、红色、灰色按钮颜色。
- 判断所有 KooPhone 直播停止时是否应自动关闭本机摄像头推流。

### `entry/src/test/LocalUnit.test.ets`

业务策略测试保留在 `entry`：

- KooPhone auth 返回体解析。
- 共享实例池选择。
- 内屏补开面板与外屏槽位策略。
- 外屏切换开关关闭时不显示按钮。
- KooPhone surface component id revision。
- LiveKit 推流按钮文案、颜色、占位符判断和关闭策略。

## LiveKit 模块状态

`LiveKit` 现在保持最初拉取状态。当前工作区验证：

```bash
git diff --name-status e5fb1b5 -- LiveKit
```

无输出。

说明：

- 本轮没有把业务鉴权、实例池、折叠屏 UI、推流按钮策略写入 SDK。
- 本轮没有修改 `LiveKit/Index.ets`。
- 因为 `LiveKit/Index.ets` 当前只导出 LiveKit 音视频相关 util，不导出 KooPhone 播放器，所以 `entry` 对 KooPhone 暂时使用深路径导入。后续 SDK 负责人如果允许，可以只在 `LiveKit/Index.ets` 增加 KooPhone 导出，`entry` 再切回顶层导入。

## 当前构建状态

已通过：

```bash
/Applications/DevEco-CommandLineTools/6.1.1.280/command-line-tools/bin/ohpm install
git diff --check
/Applications/DevEco-CommandLineTools/6.1.1.280/command-line-tools/bin/hvigorw test --no-daemon --stacktrace -p properties.enableSignTask=false
```

完整 HAP 构建当前失败：

```bash
/Applications/DevEco-CommandLineTools/6.1.1.280/command-line-tools/bin/hvigorw clean assembleApp --no-daemon --stacktrace -p properties.enableSignTask=false
```

失败原因不是 `entry` 复制件残留，而是 `entry` 改为真正依赖 `LiveKit` 后，`LiveKit` 原始源码被 ArkTS 编译器检查到以下 SDK 侧错误：

- `LiveKit/src/main/ets/koophone/KooInputController.ets`：对象字面量未声明接口。
- `LiveKit/src/main/ets/koophone/KooSignalClient.ets`：对象字面量未声明接口。
- `LiveKit/src/main/ets/koophone/KooPhonePlayer.ets`：对象字面量、索引访问、`RTCSessionDescription` 类型不匹配。
- `LiveKit/src/main/ets/koophone/KooRTCSource.ets`：`RTCSessionDescription` 类型不匹配。
- `LiveKit/src/main/ets/util/RTCEngine.ets`：`VideoSource.release()` 在当前 WebRTC 类型中不存在。

这个问题的本质是：当前 `LiveKit` 初始 SDK 源码不是完整可编译的 ArkTS SDK 状态。要同时满足“`entry` 不复制 SDK 实现”和“完整 HAP 可构建”，SDK 侧需要修复这些 ArkTS 编译错误，或提供一个已经编译通过的 HAR/HSP 版本。

## 敏感信息处理

git 中继续只保留占位符：

- `__IAM_DOMAIN_NAME__`
- `__IAM_USER_NAME__`
- `__IAM_PASSWORD__`
- `__LIVEKIT_SFU_URL__`
- `__LIVEKIT_SFU_TOKEN__`

真机安装完整体时可以临时注入真实参数构建 HAP；构建安装后必须恢复占位符再提交。
