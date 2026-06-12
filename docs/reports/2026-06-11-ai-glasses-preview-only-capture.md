# AI 眼镜预览画面专用采集修复

## 问题

AI 眼镜已经可以通过 CameraKit 打开预览，但推送到 SFU 的是整个应用屏幕，而不是只推预览区域的视频内容。

## 原因

当前兜底推流链路使用 `LiveKitUtil.publishDisplayVideo()`，底层进入 `RTCEngine.publishDisplayVideo()`，通过 `@ohos/webrtc` 创建屏幕采集视频源。

当前 `@ohos/webrtc` 的屏幕采集参数只支持整屏、指定屏幕、指定窗口和窗口过滤等能力，没有提供按 XComponent 坐标裁剪的矩形参数。因此不能直接把“页面上一块预览区域”裁剪成独立视频轨道。

## 修改

文件：`entry/src/main/ets/pages/Index1.ets`

- 新增 `aiGlassesDisplayCaptureFocused` 状态，表示当前进入 AI 眼镜屏幕采集专用画布。
- 新增 `aiGlassesDisplayCapturePage()`，只渲染 AI 眼镜 CameraKit 预览 surface 和黑色背景。
- AI 眼镜推流启动或切换成功后，进入专用画布；失败、停止或切回手机视频源时退出。
- 根 `build()` 最高优先级渲染 `aiGlassesDisplayCapturePage()`，避免独立推流时仍停留在初始选择页。
- 专用画布右下角保留透明点击区，用于恢复控制面板；恢复后 AI 眼镜推流仍继续，但此时屏幕采集会重新包含应用 UI。

## 结果

AI 眼镜推流时，应用窗口会临时变成只包含预览视频的全屏黑底画布。由于屏幕采集采到的是当前应用窗口，这样 SFU 端看到的内容就是 AI 眼镜预览画面，而不是完整业务界面。

这是当前 API 条件下的兜底方案，不是 CameraKit 原始帧到 WebRTC Track 的直接桥接。如果后续 SDK 提供 CameraKit 帧桥接或外部视频 Track 注入能力，应替换为直接推视频帧的实现。

## 验证

- `git diff --check`
- `hvigorw assembleApp --no-daemon --stacktrace`
- 已安装签名包到 Mate X7：`dist/full-params/entry-dev-all-in-ai-glasses-preview-only-capture-full-params-com.samples.ndkopengl-signed.hap`
