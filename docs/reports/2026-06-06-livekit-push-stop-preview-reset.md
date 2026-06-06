# 2026-06-06 本机直播推流关闭后预览残帧修复报告

## 问题

真机上点击“关闭直播推流”后，本机摄像头小预览会停留最后一帧。再次点击“开始直播推流”时，页面没有重新正常推流。

用户期望：

- 点击关闭后立即取消发布视频并离开 LiveKit 房间。
- 摄像头采集被释放。
- 本机预览区域回到未开启时的黑底占位状态，不保留最后一帧。
- 再次点击开始时重新走权限、SFU 建连和 `publishVideo()`。

## 根因

关闭链路只做了：

```text
stopLiveKitPush()
  -> liveKitUtil.unpublishVideo()
  -> liveKitUtil.leaveRoom()
  -> liveKitPushing = false
```

但本机预览 `XComponent` 仍然是同一个 native surface。HarmonyOS 的 native surface 在摄像头 track 解绑后可能保留最后一帧，不会因为 ArkUI 文案变化自动清屏。

另外，`LiveKitUtil` 复用同一个 `LiveKitClient` 实例。关闭后如果底层 peerConnection、renderer、信令监听或发布状态没有完全回到初始态，下一次点击开始推流可能会被旧状态挡住。

## 本轮改动

### `entry/src/main/ets/pages/Index1.ets`

新增状态：

- `liveKitPreviewRevision`

新增方法：

- `resetLiveKitPreviewSurface()`

关闭或启动失败回滚时执行：

```text
liveKitPreviewReady = false
liveKitSurfaceId = ''
liveKitXCtrl = new XComponentController()
liveKitPreviewRevision++
```

`liveKitPreviewSurface()` 的 XComponent id 改成：

```ts
buildLiveKitPreviewComponentId(LIVEKIT_PREVIEW_COMPONENT_ID, this.liveKitPreviewRevision)
```

这样每次关闭推流都会强制 ArkUI 销毁旧预览 surface 并创建新 surface，预览区不会再停留摄像头最后一帧。

### `entry/src/main/ets/rtc/LiveKitUtil.ets`

- `leaveRoom()` 在断开房间后调用 `resetRuntimeState()`。
- `leaveRoom()` 随后调用 `recreateClientForNextPush()`，重新创建 `LiveKitClient` 并绑定事件。
- `unpublishVideo()` 即使当前没有已发布视频，也会清空 `localVideoSurfaceId`。
- `disconnected` 事件同步清空 `localVideoSurfaceId`。

新的关闭后状态：

```text
roomState = 'disconnected'
isVideoPublished = false
localVideoSurfaceId = ''
remoteSpeakers = []
participantCount = 0
client = createLiveKitClient()
```

### `LiveKit/src/main/ets/koophone/LiveKitPushPolicy.ets`

新增纯函数：

```ts
buildLiveKitPreviewComponentId(baseId, revision)
```

用于生成带 revision 的本机预览 XComponent id，便于单测覆盖“关闭后 id 会变化”。

### `LiveKit/src/test/LocalUnit.test.ets`

新增测试：

- `changesPreviewComponentIdWhenRevisionIncrements`

验证 revision 递增后预览 XComponent id 发生变化，避免复用旧 native surface。

## 验证点

- `git diff --check`
- `hvigorw test --no-daemon --stacktrace -p properties.enableSignTask=false`
- `hvigorw clean assembleApp --no-daemon --stacktrace`
- 真机安装完整体 HAP 后验证：
  - 打开云机直播。
  - 点击“开始直播推流”，允许相机和麦克风权限。
  - 本机预览显示真实摄像头画面。
  - 点击“关闭直播推流”。
  - 本机预览不再停留最后一帧，回到黑底占位状态。
  - 再次点击“开始直播推流”，重新建连并正常发布视频。

## 注意

git 中仍保留 IAM 和 LiveKit SFU 占位符。真机安装完整体时临时注入真实参数，安装后必须恢复占位符再提交。
