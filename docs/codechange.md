# 代码改动汇总

本文档说明当前 `worry-bit/livekit` 相对最初 `SpikeX-21/livekit` 的最终改动状态，重点区分 `entry` 应用模块与 `LiveKit` SDK 模块。

## 总体结论

当前最终边界如下：

- `entry` 是 App，承载 Mate X7 折叠屏 UI、KooPhone 双路串流、本机摄像头 LiveKit 推流、鉴权、实例池、状态策略和单测。
- `LiveKit` 是 SDK，由其他项目人员继续维护；本轮已把之前误放进 `LiveKit` 的新增代码迁回 `entry`，并将 `LiveKit` 文件恢复到最开始拉取的 `upstream/main` 状态。
- `git diff --name-status upstream/main -- LiveKit` 当前应为空。`git status` 中看到的 `LiveKit` 改动，是相对个人仓库上一轮提交的“撤回 SDK 改动”，不是新的 SDK 功能改动。
- 项目构建目标现在只构建 `entry`。`entry` 不再依赖本地 HAR `livekit-harmony: file:../LiveKit`，改为在应用模块内持有本次业务需要的适配实现。

## 非 entry 配置改动

### `build-profile.json5`

改动：

```diff
-    {
-      "name": "LiveKit",
-      "srcPath": "./LiveKit",
-      "targets": [...]
-    }
```

原因：

- `entry` 已经不再依赖 `LiveKit` HAR。
- 保持 SDK 源码不动时，继续把 `LiveKit` 放进 App 的根构建目标会让 App 构建被 SDK 内部实现影响。
- 这个仓库当前的 App 交付目标是 `entry` HAP；SDK 侧后续由 SDK 负责人单独维护。

### `entry/oh-package.json5`

改动：

```diff
- "livekit-harmony": "file:../LiveKit"
+ "@ohos/webrtc": "^1.0.0"
```

原因：

- `entry/src/main/ets/livekit/**` 和 `entry/src/main/ets/koophone/**` 直接使用 HarmonyOS WebRTC 能力。
- 移除对 `LiveKit` HAR 的依赖，避免 App 为了业务页面改动而修改 SDK 模块。

## entry 模块改动

### `entry/src/main/ets/entryability/EntryAbility.ets`

主入口加载业务页：

```text
EntryAbility.onWindowStageCreate()
  -> windowStage.loadContent('pages/Index1')
```

`Index1` 是当前 Mate X7 折叠屏直播主页面。

### `entry/src/main/ets/pages/Index1.ets`

主要能力：

- 初始选择页：淘宝直播、抖音直播支持单选和双选。
- 展开屏：淘宝固定左槽，抖音固定右槽；单路直播时另一半显示补开选择面板。
- 外屏：显示当前折叠态槽位；当前版本隐藏“切换直播”按钮，但保留开关和切换逻辑。
- 开始直播：每个平台独立走 IAM token -> KooPhone 实例鉴权 -> `KooPhonePlayer.open()`。
- 停止直播：`stopPlatformStream(platform)` 只停止单个平台，另一平台不受影响。
- 重试容灾：单实例最多重试 3 次，失败后从共享实例池选择未被占用实例重新鉴权开流。
- Surface 修复：停止后补开会清理旧 surface、递增 revision、重建当前槽位 XComponent，避免画面跑到外屏旧 surface。
- 本机摄像头推流：全局按钮执行 `requestPermissions()` -> `joinRoom()` -> `publishVideo()`；关闭时执行 `unpublishVideo()` -> `leaveRoom()` 并重置本机预览 surface。

关键链路：

```text
platformOption()
  -> togglePlatform()
  -> startSelectedStreams()
  -> startPlatformIfReady(platform)
  -> KooAuthService.requestSdkToken()
  -> KooPhonePlayer.open(params, surfaceId)
```

本机推流链路：

```text
liveKitPushButton()
  -> toggleLiveKitPush()
  -> startLiveKitPush()
  -> liveKitUtil.requestPermissions()
  -> liveKitUtil.joinRoom(LIVEKIT_SFU_URL, LIVEKIT_SFU_TOKEN)
  -> liveKitUtil.publishVideo(liveKitSurfaceId)
```

### `entry/src/main/ets/koophone/**`

这些文件是原本误放在 SDK 侧的 KooPhone 业务运行时和策略，现在全部归入 App：

| 文件 | 作用 |
| --- | --- |
| `KooAuthTypes.ets` | IAM、KooPhone auth、直播平台配置和 SDK token 结果类型 |
| `KooAuthService.ets` | 调 IAM `POST /v3/auth/tokens`，读取响应头 `X-Subject-Token`，再调用 KooPhone auth |
| `KooAuthParser.ets` | 解析 KooPhone auth 返回的 `signaling_url / device_token / device_id / streamingId` |
| `KooInstancePool.ets` | 共享实例池选择策略，跳过当前实例、已尝试实例和被另一路占用实例 |
| `KooLiveSlotPolicy.ets` | 内屏补开面板、外屏默认槽位、外屏切换开关、surface component id 策略 |
| `KooPhonePlayer.ets` | App 内部 KooPhone 播放器封装，负责信令、WebRTC、输入控制串联 |
| `KooRTCSource.ets` | App 内部 KooPhone WebRTC PeerConnection 和 NativeVideoRenderer 管理 |
| `KooSignalClient.ets` | KooPhone Socket.IO v2 over WebSocket 信令客户端 |
| `KooInputController.ets` | 云机触摸、按键 DataChannel 输入转发 |
| `KooPhoneTypes.ets` | KooPhone 开流、信令、错误和输入相关类型 |

为什么放在 `entry`：

- IAM/KooPhone 实例鉴权、实例池、Mate X7 槽位策略都属于当前 App 的业务编排，不应污染 SDK。
- `KooPhonePlayer / KooRTCSource / KooSignalClient` 当前是为了保持已打通功能而在 App 内持有的一份适配实现；后续如果 SDK 团队提供稳定公共原子能力，`entry` 再切回 SDK 公共导出即可。

### `entry/src/main/ets/livekit/**`

这些文件是本机摄像头推流所需的 App 内部 LiveKit 适配：

| 文件 | 作用 |
| --- | --- |
| `LiveKitClient.ets` | SFU 房间连接、发布/取消发布视频、切换摄像头 |
| `RTCEngine.ets` | 本机摄像头采集、PeerConnection、媒体轨道管理 |
| `SignalClient.ets` | LiveKit 信令连接 |
| `ProtobufCodec.ets` | LiveKit 信令消息编码/解码 |
| `AudioManager.ets` | 音频采集说明与管理占位 |
| `types.ets` | LiveKit 连接、媒体、错误相关类型 |

为什么放在 `entry`：

- 本轮需求是 App 内“开始直播推流/关闭直播推流/切换摄像头”业务能力。
- SDK 模块不允许继续改动，所以页面依赖的推流适配留在 App 内部。

### `entry/src/main/ets/push/LiveKitPushPolicy.ets`

纯策略文件，负责：

- 判断 `LIVEKIT_SFU_URL / LIVEKIT_SFU_TOKEN` 是否仍是占位符。
- 生成“开始直播推流 / 关闭直播推流 / 推流中... / 关闭中...”按钮文案。
- 生成绿色、红色、灰色按钮颜色。
- 判断所有 KooPhone 直播停止时是否应自动关闭本机摄像头推流。

### `entry/src/main/ets/rtc/LiveKitUtil.ets`

页面调用的本机摄像头推流门面：

- `requestPermissions()`：申请相机和麦克风权限。
- `joinRoom(url, token)`：连接 LiveKit SFU。
- `publishVideo(surfaceId)`：开启本机摄像头并发布视频。
- `unpublishVideo()`：取消发布视频。
- `leaveRoom()`：离开房间并重建客户端，避免下一次点击被旧 PeerConnection 状态卡住。
- `switchCamera()`：切换前后摄像头。

### `entry/src/test/LocalUnit.test.ets`

之前放在 `LiveKit/src/test/LocalUnit.test.ets` 的业务策略测试已迁入 `entry`：

- KooPhone auth 返回体解析。
- 共享实例池选择。
- 内屏补开面板与外屏槽位策略。
- 外屏切换开关关闭时不显示按钮。
- KooPhone surface component id revision。
- LiveKit 推流按钮文案、颜色、占位符判断和关闭策略。

## LiveKit 模块状态

### 最终状态

`LiveKit` 当前应与最开始拉取的 `SpikeX-21/livekit` 保持一致：

```bash
git diff --name-status upstream/main -- LiveKit
```

预期没有输出。

### 本轮从 LiveKit 撤回的内容

这些内容不再留在 `LiveKit`，已迁入 `entry` 或直接撤回：

- `KooAuthService.ets`
- `KooAuthParser.ets`
- `KooInstancePool.ets`
- `KooLiveSlotPolicy.ets`
- `LiveKitPushPolicy.ets`
- KooPhone/LiveKit 相关单测
- 为旧 JS 参考文件补的 shim
- 对 `LiveKit/Index.ets` 增加的大量业务导出
- 对 SDK 内部 `KooPhonePlayer / KooRTCSource / KooSignalClient / LiveKitClient / RTCEngine` 的业务修补

原因：

- `LiveKit` 是 SDK，不属于当前 App 业务团队维护范围。
- SDK 侧后续有人会继续改，如果 App 侧也改同一批文件，会造成冲突。
- 当前 App 需要的功能先在 `entry` 中闭合，保证真机功能不丢。

## 敏感信息处理

git 中只保留占位符：

- `__IAM_DOMAIN_NAME__`
- `__IAM_USER_NAME__`
- `__IAM_PASSWORD__`
- `__LIVEKIT_SFU_URL__`
- `__LIVEKIT_SFU_TOKEN__`

真机安装完整体时可以临时注入真实参数构建 HAP；构建安装后必须恢复占位符再提交。

代码和历史文档仍包含测试环境 KooPhone auth host 与实例 ID，用于当前内网端到端调试。公开给外部使用前，如果这些也被视为敏感，需要再做一轮配置化脱敏。

## 验证命令

本轮重构已通过：

```bash
/Users/wangrui/Downloads/command-line-tools/ohpm/bin/ohpm install
DEVECO_SDK_HOME=/Users/wangrui/Downloads/command-line-tools/sdk /Users/wangrui/Downloads/command-line-tools/hvigor/bin/hvigorw test --no-daemon --stacktrace -p properties.enableSignTask=false
git diff --check
DEVECO_SDK_HOME=/Users/wangrui/Downloads/command-line-tools/sdk /Users/wangrui/Downloads/command-line-tools/hvigor/bin/hvigorw clean assembleApp --no-daemon --stacktrace -p properties.enableSignTask=false
```

验证结论：

- `entry:test` 通过。
- `clean assembleApp` 通过。
- 构建日志只出现 `entry` 任务，没有再编译 `LiveKit` 模块。
- `@ohos/webrtc` 资源名与 entry 自带资源有 warning 级重复声明，不影响测试和打包。
