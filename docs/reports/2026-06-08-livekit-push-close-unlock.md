# 2026-06-08 LiveKit 推流关闭卡死修复报告

## 背景

真机 Mate X7 上点击“关闭直播推流”后，页面会停在关闭态：开始直播推流按钮和切换摄像头按钮都变灰，无法回到初始可操作状态。现象说明 UI 状态被底层关闭链路阻塞，或者预览 surface 重建后没有及时恢复可点击策略。

## 根因判断

- 原关闭链路在页面层等待 `unpublishVideo()` 和 `leaveRoom()` 完成后才重置 `liveKitBusy`。
- 如果 native 摄像头释放、WebRTC peerConnection 断开或 SFU 信令断开耗时过长，`liveKitBusy` 会保持 `true`，按钮一直置灰。
- 关闭后为了清掉摄像头最后一帧会重建本机预览 XComponent，但按钮可点击策略仍依赖 `preview surface ready`，当 `onLoad` 没有立即回调时，开始按钮会继续显示为不可点击。
- 旧 LiveKit client 的异步事件可能在新一轮推流准备期间回调，覆盖当前页面可读状态。

## 本轮改动

### `entry/src/main/ets/pages/Index1.ets`

- `stopLiveKitPush()` 改为先调用 `liveKitUtil.closeAndResetForNextPush()` 分离旧 client，再立即把页面状态恢复为：
  - `liveKitPushing = false`
  - `liveKitBusy = false`
  - 重建预览 XComponent
- 旧 client 的 `unpublish/disconnect` 在后台限时执行，超时只展示错误提示，不再阻塞按钮恢复。
- `startLiveKitPush()` 开始前新增 `refreshLiveKitPreviewSurfaceId()`，主动读取当前预览 surface，减少重建后等待 `onLoad` 的窗口。
- 推流按钮透明度和点击入口改为只受 `liveKitBusy` 影响；真正开始推流时仍会再次校验 surface 是否有效。

### `entry/src/main/ets/rtc/LiveKitUtil.ets`

- 新增 `closeAndResetForNextPush(timeoutMs)`：
  - 先把当前 client 标记为旧 client。
  - 立即重置页面可读运行态。
  - 立即创建新的 LiveKit client，保证下一次点击“开始直播推流”会重新走 `joinRoom()` 和 `publishVideo()`。
  - 后台限时关闭旧 client，避免关闭流程卡住 UI。
- 新增 client generation 保护，旧 client 的 `connected/disconnected/reconnecting` 等事件不会覆盖新 client 状态。

### `entry/src/main/ets/push/LiveKitPushPolicy.ets`

- 新增 `canClickLiveKitPushButton(isBusy)`。
- 保留 `canToggleLiveKitPush(isSurfaceReady, isBusy)` 作为纯策略函数，但页面点击不再强依赖 preview surface，避免关闭后 XComponent 重建期间按钮永久变灰。

### `entry/src/test/LocalUnit.test.ets`

- 新增 `keepsPushButtonClickableAfterPreviewReset`，验证非 busy 状态下推流按钮必须可点击，busy 状态下才禁用。

## 验证

已执行：

```bash
git diff --check
DEVECO_SDK_HOME=/Users/wangrui/Downloads/command-line-tools/sdk /Users/wangrui/Downloads/command-line-tools/hvigor/bin/hvigorw test --no-daemon --stacktrace -p properties.enableSignTask=false
DEVECO_SDK_HOME=/Users/wangrui/Downloads/command-line-tools/sdk /Users/wangrui/Downloads/command-line-tools/hvigor/bin/hvigorw clean assembleApp --no-daemon --stacktrace -p properties.enableSignTask=false
```

结果：

- 单测通过。
- 占位符版本构建通过。
- 仍有既有 webrtc 资源名冲突 warning 和 `getContext` deprecated warning，不影响本轮修复。

## 真机验证建议

安装完整体 HAP 后按下面路径验证：

1. 打开一个云机直播。
2. 点击“开始直播推流”，确认本机摄像头预览和 SFU 推流正常。
3. 点击“关闭直播推流”，确认预览回到“本机预览/等待预览”初始态，不停留最后一帧。
4. 再次点击“开始直播推流”，确认会重新建连并重新发布视频。
5. 如果底层关闭超时，页面仍应可重新点击开始按钮，错误只作为提示显示。

## 安全说明

git 中继续只保留 IAM 和 LiveKit SFU 占位符。真机安装完整体 HAP 时在本地临时注入真实参数，安装完成后恢复占位符，真实账号、密码、token 不进入提交。
