# 2026-06-11 AI 眼镜推流仍显示手机画面修复报告

## 现象

点击“推送AI眼镜视频流”后，LiveKit 推流链路能出视频，但画面仍是 Mate X7 手机摄像头，不是 AI 眼镜第一视角。

## 原因分析

之前 AI 眼镜本地预览成功走的是 CameraKit 链路：

```text
CameraManager.getCameraDevices(..., CAMERA_CONNECTION_REMOTE)
  -> 选中 hostDeviceName = AI Glasses 的 CameraDevice
  -> CameraManager.createCameraInput(cameraDevice)
  -> cameraInput.open()
  -> session.addInput(cameraInput)
  -> session.start()
```

当前 LiveKit 推流走的是另一条链路：

```text
LiveKitUtil.publishVideo(surfaceId, deviceId)
  -> LiveKitClient.publishVideo()
  -> RTCEngine.publishVideo()
  -> peerConnectionFactory.createVideoSource({ deviceId, width, height, frameRate })
```

也就是说，成功预览时传给系统的是完整 `CameraDevice`；推流时只能把 remote `cameraId` 作为 `deviceId` 字符串传给 `@ohos/webrtc`。当前 `@ohos/webrtc` 公开 API 没有直接接收 CameraKit `CameraDevice` 或外部视频帧的接口，所以推流侧必须尽量避免 WebRTC 回退到默认手机摄像头。

本次定位到两个高风险点：

1. 手机摄像头共享 track 仍处于打开状态时，AI 眼镜切源会和已有本机摄像头占用冲突，`createVideoSource()` 可能继续复用或回退到手机摄像头。
2. AI 眼镜推流之前仍使用 `640x480` 采集参数，而之前 CameraKit 成功预览选择的是接近 `1280x720` 的 profile。如果 remote camera 不支持 640x480，也可能触发系统侧兜底。

## 修改内容

### `LiveKit/src/main/ets/koophone/KooUserMedia.ets`

- 第 126 行新增 `forceReleaseSharedVideoTrack(reason)`：
  - 不等待引用计数归零，直接停止并清空当前共享摄像头 track。
  - 目的：AI 眼镜切源前彻底释放 Mate X7 本机摄像头，避免 WebRTC 继续拿手机画面。
- 第 163 行补强 `openCamera()`：
  - 如果本地状态是 `cameraOn=true` 但 track 已经 `ended`，先清理再重新打开。
  - 目的：避免强制释放后，旧 `KooUserMedia` 实例误以为摄像头仍可用。

### `LiveKit/src/main/ets/util/RTCEngine.ets`

- 第 252 行：当 `deviceId` 是 remote camera 时，调用 `KooUserMedia.forceReleaseSharedVideoTrack()`。
- 第 268 行：给 `VideoSource.oncapturerstarted` 增加日志：
  - `target=ai_glasses:<masked-deviceId>`
  - `success=true/false`
- 第 274 行：给 `VideoSource.oncapturerstopped` 增加日志。
- 第 279 行：remote camera track 仍保持不注册到共享 track，避免污染手机/KooPhone 的共享状态。

### `entry/src/main/ets/rtc/LiveKitUtil.ets`

- 第 329 行：AI 眼镜 remote camera 推流参数改为 `1280x720@15fps`。
- 手机摄像头继续使用 `640x480@15fps`。

## 后续真机验证重点

真机点击“推送AI眼镜视频流”后，重点看 hilog 中是否出现：

```text
[LiveKitUtil] publishVideo with AI glasses remote deviceId: ...
[KooUserMedia] Shared camera force released: publish remote camera ...
[RTCEngine] Using explicit video deviceId for publishVideo: ...
[RTCEngine] Video capturer started target=ai_glasses:..., success=true
```

如果日志出现 `target=ai_glasses` 且 `success=true`，但画面仍是手机摄像头，则说明 `@ohos/webrtc.createVideoSource({ deviceId })` 在当前系统/设备上虽然返回成功，但实际没有按 remote `cameraId` 选源，而是系统内部回退到了本机摄像头。那时需要 SDK 层引入 CameraKit 帧转 WebRTC track 的能力，或向 `@ohos/webrtc`/CameraKit SDK 方确认 remote camera deviceId 支持。

## 验证结果

已通过：

```bash
git diff --check
hvigorw test --no-daemon --stacktrace -p properties.enableSignTask=false
hvigorw assembleApp --no-daemon --stacktrace
```

构建产物：

```text
entry/build/default/outputs/default/entry-default-signed.hap
```
