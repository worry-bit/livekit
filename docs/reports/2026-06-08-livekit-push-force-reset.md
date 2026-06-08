# 2026-06-08 LiveKit 推流关闭强制复位报告

## 背景

上一版把“关闭直播推流”改成先恢复 UI、后台限时执行 `unpublish/disconnect`。真机验证后仍然出现按钮变灰、无法回到初始态的问题，说明旧关闭链路中的 native/WebRTC 清理仍可能影响 ArkUI 状态或主线程响应。

## 本轮策略

这次不再让关闭按钮等待或触发原来的异步信令关闭链路，而是切到同步强制复位：

- 页面立即退出推流态。
- 同步释放本地摄像头轨道、预览 renderer、PeerConnection 和音频观察器。
- 关闭旧信令 client 的本地引用。
- 立即创建新的 `LiveKitClient`，下一次点击“开始直播推流”重新走 `joinRoom()` 和 `publishVideo()`。
- 预览 XComponent 重建期间忽略 `onDestroy` 递归关闭，避免重复触发关闭链路。

如果这个方案在真机上仍不稳定，下一步只需要把 `Index1.ets` 中 `ENABLE_LIVEKIT_PUSH_STOP_BUTTON` 改为 `false`，即可临时关闭“关闭直播推流”入口，代码保留不删除。

## 改动文件

### `entry/src/main/ets/livekit/LiveKitClient.ets`

新增 `forceResetForNextPush()`：

- 调用 `stopAudioLevelObserver()`。
- 调用 `rtcEngine.close()` 释放本地媒体资源。
- 调用 `signalClient.close()` 断开本地信令引用。
- 重置连接态、参与者、音视频发布标记。

### `entry/src/main/ets/rtc/LiveKitUtil.ets`

新增 `forceResetForNextPush()`：

- 递增 client generation，让旧 client 的异步事件失效。
- 重置页面可读运行状态。
- 对旧 client 执行强制复位。
- 创建新的 `LiveKitClient` 并重新绑定事件。

### `entry/src/main/ets/pages/Index1.ets`

- `stopLiveKitPush()` 改为同步强制复位，不再 `await unpublishVideo()` 或 `await leaveRoom()`。
- 新增 `liveKitPreviewResetting`，预览 XComponent 重建导致的 `onDestroy` 不再递归调用关闭流程。
- 新增 `ENABLE_LIVEKIT_PUSH_STOP_BUTTON`，用于必要时一行配置关闭停止功能。
- `startLiveKitPush()` 的失败分支也改为强制复位，避免连接或发布失败后残留旧 client 状态。

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
- 仍存在既有 webrtc 资源名重复 warning 和 ArkTS `ESObject/getContext` warning，不影响本次改动。

## 真机验证步骤

1. 打开云机直播。
2. 点击“开始直播推流”，确认本机摄像头推流启动。
3. 点击“关闭直播推流”。
4. 预期结果：
   - 按钮立即恢复“开始直播推流”。
   - “切换摄像头”变灰。
   - 本机预览不再停留为推流态。
   - 再次点击“开始直播推流”会重新建连并重新发布。

## 安全说明

提交版本继续保留 IAM 和 LiveKit SFU 占位符。真机安装时只在本地临时注入真实参数，安装后恢复占位符，真实参数不进入 git。
