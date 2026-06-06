# 2026-06-06 本机摄像头 LiveKit 推流接入报告

## 背景

当前应用的主链路是 Mate X7 上打开淘宝/抖音云机直播画面，并把云机画面渲染在 `Index1.ets` 的左右槽位里。本轮新增的是另一条独立链路：把真实 Mate X7 的摄像头和麦克风通过 LiveKit 推到 SFU，供云机里的直播应用使用。

这条链路不复用 KooPhone 云机串流的 `surfaceId`。KooPhone surface 用于显示云机画面和转发触摸；LiveKit 本机推流 surface 只用于本机摄像头预览和 `publishVideo(surfaceId)`。

## 本轮改动

### `entry/src/main/ets/pages/Index1.ets`

- 新增 LiveKit SFU 占位配置：
  - `LIVEKIT_SFU_URL = '__LIVEKIT_SFU_URL__'`
  - `LIVEKIT_SFU_TOKEN = '__LIVEKIT_SFU_TOKEN__'`
- 新增本机摄像头预览状态：
  - `liveKitXCtrl`
  - `liveKitSurfaceId`
  - `liveKitPreviewReady`
  - `liveKitPushing`
  - `liveKitBusy`
  - `liveKitErrorText`
- 新增本机预览浮层：
  - `liveKitPreviewSurface()`
  - `liveKitPushButton()`
  - `liveKitSwitchCameraButton()`
  - `liveKitPushOverlay()`
- 新增推流控制方法：
  - `toggleLiveKitPush()`：全局推流按钮入口。
  - `startLiveKitPush()`：按 `requestPermissions -> joinRoom -> publishVideo` 顺序启动推流。
  - `stopLiveKitPush()`：按 `unpublishVideo -> leaveRoom` 顺序关闭推流。
  - `switchLiveKitCamera()`：调用 `liveKitUtil.switchCamera()` 切换前后摄像头。
  - `stopLiveKitPushForLifecycle()`：页面退出、直播关闭时异步释放推流。
  - `stopLiveKitPushIfNoActiveKooLive()`：所有云机直播都停止或失败后释放本机摄像头。
- `liveContent()` 在最高层渲染 `liveKitPushOverlay()`，所以外屏和内屏直播态都能看到同一个全局推流控件。

### `entry/src/main/ets/rtc/LiveKitUtil.ets`

- `requestPermissions()` 改为返回 `Promise<boolean>`，同时记录 `hasMediaPermission`。
- `joinRoom(url, token)` 改为返回 `Promise<boolean>`：
  - 拒绝空值和 `__LIVEKIT_*__` 占位符。
  - 连接成功后返回 `true`。
  - 失败时写入 `errorMessage`，页面用于展示错误。
- `publishVideo(surfaceId)` 改为返回 `Promise<boolean>`：
  - 校验本机预览 surface 是否已准备好。
  - 校验 LiveKit 房间是否已连接。
  - 通过 `LiveKitClient.videoPublished` 确认底层确实发布成功。
- `unpublishVideo()`、`leaveRoom()`、`switchCamera()` 都改为返回 `Promise<boolean>`，便于页面按结果回退按钮状态。
- 断开事件里同步清理 `isVideoPublished`，避免页面误判摄像头仍在推流。

### `LiveKit/src/main/ets/util/LiveKitClient.ets`

- 新增只读 getter：
  - `videoPublished`
- `LiveKitUtil.publishVideo()` 通过这个 getter 判断 SDK 内部视频轨道是否真的发布成功。

### `LiveKit/src/main/ets/koophone/LiveKitPushPolicy.ets`

新增纯策略函数，供页面和单测复用：

- `isLiveKitPushConfigReady(url, token)`：判断 SFU 参数是否已经替换为真实值。
- `getLiveKitPushButtonText(isPublished, isBusy)`：返回“开始直播推流 / 关闭直播推流 / 推流中... / 关闭中...”。
- `getLiveKitPushButtonColor(isPublished, isBusy)`：绿色开始、红色关闭、灰色过渡态。
- `canToggleLiveKitPush(isSurfaceReady, isBusy)`：判断按钮是否可点击。
- `shouldStopLiveKitPush(hasTaobaoLiveActive, hasDouyinLiveActive)`：所有云机直播都不活跃时释放本机推流。

### `LiveKit/Index.ets`

- 导出 `LiveKitPushPolicy` 的公共策略函数和按钮颜色常量，`entry` 页面可以继续从 `livekit-harmony` 包入口导入，不跨 HAR 内部路径。

### `LiveKit/src/test/LocalUnit.test.ets`

新增单测覆盖：

- SFU 占位符配置会被判定为不可用。
- 推流按钮不同状态的文案和颜色。
- 本机预览 surface 未准备好或 busy 时不能切换推流状态。
- 所有云机直播都停止时，应关闭本机推流。

## 调用链

开始推流：

```text
liveKitPushButton()
  -> toggleLiveKitPush()
  -> startLiveKitPush()
  -> liveKitUtil.requestPermissions()
  -> liveKitUtil.joinRoom(LIVEKIT_SFU_URL, LIVEKIT_SFU_TOKEN)
  -> liveKitUtil.publishVideo(liveKitSurfaceId)
  -> liveKitPushing = true
```

关闭推流：

```text
liveKitPushButton()
  -> toggleLiveKitPush()
  -> stopLiveKitPush()
  -> liveKitUtil.unpublishVideo()
  -> liveKitUtil.leaveRoom()
  -> liveKitPushing = false
```

切换摄像头：

```text
liveKitSwitchCameraButton()
  -> switchLiveKitCamera()
  -> liveKitUtil.switchCamera()
  -> LiveKitClient.switchCamera()
  -> RTCEngine.switchCamera()
```

## 验证结果

- `git diff --check`：通过。
- `/Applications/DevEco-CommandLineTools/6.1.1.280/command-line-tools/bin/hvigorw test --no-daemon --stacktrace -p properties.enableSignTask=false`：`BUILD SUCCESSFUL`。
- `/Applications/DevEco-CommandLineTools/6.1.1.280/command-line-tools/bin/hvigorw clean assembleApp --no-daemon --stacktrace`：`BUILD SUCCESSFUL`。

构建产物：

- `entry/build/default/outputs/default/entry-default-signed.hap`

## 当前限制

- git 中不能提交真实 SFU `url/token`，当前只保留 `__LIVEKIT_SFU_URL__` 和 `__LIVEKIT_SFU_TOKEN__`。
- 真机端到端验证“云机直播应用看到真实 Mate X7 摄像头画面”前，需要在本地临时注入真实 SFU 参数后重新构建安装。
- 当前实现是一条本机摄像头采集链路、一条 LiveKit 推流链路，不做两个独立 LiveKit 客户端。
