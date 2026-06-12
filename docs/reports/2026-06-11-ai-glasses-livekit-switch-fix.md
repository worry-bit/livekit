# 2026-06-11 AI 眼镜 LiveKit 推流切换修复报告

## 目标

把之前已经验证成功的 AI 眼镜 CameraKit 枚举逻辑接入 LiveKit 推流：

- 手机推流时，entry 侧枚举 Mate X7 当前可用本机摄像头，并把具体 `cameraId` 传给 LiveKit SDK。
- 点击“推送AI眼镜视频流”时，entry 侧重新枚举 `CAMERA_CONNECTION_REMOTE` 摄像头，选择 `hostDeviceName = AI Glasses` 的 `cameraId`。
- 切换时不再走 `RTCRtpSender.replaceTrack()`，而是在同一个 SFU 房间内执行“停发视频 -> 释放相机 -> 用目标 cameraId 重新发布视频”，避免同时打开手机摄像头和 AI 眼镜摄像头。

## 关键调用链

### 手机视频流

```text
Index1.liveKitPushButton()
  -> toggleLiveKitPush()
  -> startLiveKitPush()
  -> resolveLiveKitDeviceIdForCurrentSource()
  -> GlassesPreviewUtil.resolvePreferredPhoneCameraId()
  -> LiveKitUtil.publishVideo(surfaceId, phoneCameraId)
  -> LiveKitClient.publishVideo(surfaceId, VideoCaptureOptions)
  -> RTCEngine.publishVideo()
  -> peerConnectionFactory.createVideoSource({ deviceId: phoneCameraId, width, height, frameRate })
```

### AI 眼镜视频流

```text
Index1.liveKitSwitchAiGlassesButton()
  -> switchLiveKitToAiGlassesCamera()
  -> GlassesPreviewUtil.resolveAiGlassesCameraId()
  -> getCameraDevices(BACK, [WIDE_ANGLE], CAMERA_CONNECTION_REMOTE)
  -> select CameraDevice where hostDeviceName == "AI Glasses"
  -> LiveKitUtil.replaceVideoSource(surfaceId, aiGlassesCameraId)
  -> LiveKitCameraSwitchCoordinator.switchPublishedVideoSource()
  -> LiveKitClient.unpublishVideo()
  -> wait 240ms
  -> LiveKitClient.publishVideo(surfaceId, { deviceId: aiGlassesCameraId, width: 1280, height: 720, frameRate: 15 })
  -> RTCEngine.publishVideo()
  -> peerConnectionFactory.createVideoSource({ deviceId: aiGlassesCameraId, width, height, frameRate })
```

### AI 眼镜切回手机

```text
Index1.liveKitPushButton()  // 当前关闭推流功能被隐藏，AI 推流中复用该按钮切回手机
  -> toggleLiveKitPush()
  -> switchLiveKitToPhoneCamera()
  -> use remembered liveKitPhoneDeviceId
  -> if empty, GlassesPreviewUtil.resolvePreferredPhoneCameraId()
  -> LiveKitUtil.replaceVideoSource(surfaceId, phoneCameraId)
  -> LiveKitCameraSwitchCoordinator.switchPublishedVideoSource()
```

## 修改文件

### `entry/src/main/ets/pages/Index1.ets`

- 新增 `liveKitPhoneDeviceId`，记录开始手机推流时实际使用的 Mate X7 本机 `cameraId`。
- `startLiveKitPush()` 在点击开始后才挂载预览 XComponent，初始“开始直播”页面不再显示黑色预览框。
- `resolveLiveKitDeviceIdForCurrentSource()` 对手机源也显式返回本机 cameraId，避免 @ohos/webrtc 在折叠屏状态下自行选择前摄。
- `switchLiveKitToAiGlassesCamera()`：
  - 未推流时只预选 AI 眼镜源。
  - 推流中重新枚举 AI Glasses remote cameraId，然后调用 `liveKitUtil.replaceVideoSource()`。
- 新增 `switchLiveKitToPhoneCamera()`，从 AI 眼镜流切回手机流时优先使用已记录的手机 cameraId，失败再重新枚举。
- 按钮文案保持：
  - `开始直播推流`
  - `推送AI眼镜视频流`
  - `切换手机摄像头`
  - AI 眼镜推流中，主按钮显示 `推送手机视频流`，用于切回手机源。

### `entry/src/main/ets/rtc/LiveKitUtil.ets`

- `publishVideo(surfaceId, deviceId)` 统一把 entry 侧枚举到的 cameraId 转成 `VideoCaptureOptions.deviceId`。
- `replaceVideoSource(surfaceId, deviceId)` 不再调用 SDK 的 replaceTrack 类能力，改为调用 entry 侧协调器。
- `createVideoCaptureOptions(deviceId)`：
  - 手机源：`640x480@15fps`。
  - AI 眼镜 remote 源：`1280x720@15fps`。
  - `deviceId` 直接传字符串，不再传 `{ exact: deviceId }`，避免 native 类型不匹配。

### `entry/src/main/ets/rtc/LiveKitCameraSwitchCoordinator.ets`

新增文件。只依赖 SDK 已公开的 `LiveKitClient.unpublishVideo()` 和 `LiveKitClient.publishVideo()`：

```text
unpublishVideo()
wait 240ms
publishVideo(surfaceId, options)
```

这条路径的目的不是断开 SFU 房间，而是释放旧摄像头后重新发布目标视频源，避免 Mate X7 + AI 眼镜场景同时占用两路摄像头。

### `entry/src/main/ets/push/LiveKitPushPolicy.ets`

- 关闭推流能力当前仍通过开关隐藏。
- `canStop=false` 时，推流中主按钮文案调整为 `推送手机视频流`。
- busy 且已推流时显示 `切换中...`。
- 新增/保留 `shouldRenderLiveKitPreviewSurface()`：只有准备推流、推流中、切换中才挂载预览 surface。

### `entry/src/test/LocalUnit.test.ets`

- 补充按钮策略测试：
  - 初始页不渲染 LiveKit preview surface。
  - 推流中切换状态显示 `切换中...`。
  - 关闭按钮隐藏时主按钮文案为 `推送手机视频流`。

### `LiveKit/src/main/ets/util/RTCEngine.ets`

这是本轮唯一 SDK 最小改动，原因是 SDK 内部会把本机视频轨道注册到 `KooUserMedia` 共享轨道。AI 眼镜 remote camera 不应该覆盖这个共享轨道，否则 KooPhone/本机摄像头可能互相影响。

改动：

- 在 `publishVideo()` 中判断 `deviceId` 是否包含 `__Camera_`。
- 如果是 AI 眼镜 remote deviceId，则创建独立 video track，不注册到 `KooUserMedia` shared track。
- 如果是手机本机 cameraId，则保留原共享逻辑。

## 验证

已通过：

```bash
git diff --check
hvigor test --no-daemon --stacktrace -p properties.enableSignTask=false
```

测试结果：

- ArkTS 单测通过。
- unsigned HAP 构建通过，产物：

```text
entry/build/default/outputs/default/entry-default-unsigned.hap
```

## 当前阻塞

完整签名安装暂时卡在签名材料口令，不是代码编译问题。

现象：

```text
00303242 Configuration Error
Signature material verification failed, as: Unsupported state or unable to authenticate data.
```

已确认：

- `default_livekit` profile 是 debug profile。
- profile bundle name 是 `com.samples.ndkopengl`。
- unsigned HAP 已生成。
- 旧 hvigor report 证明 2026-06-10 曾经用同一套 `default_livekit` p12/p7b/cer 签名成功。
- 当前可搜索到的旧加密 `keyPassword/storePassword` 已不能解当前 p12，不能继续随机猜。

下一步需要在 DevEco Studio 的 `File -> Project Structure -> Signing Configs` 里重新保存当前签名配置，让 `build-profile.json5` 写入新的可解密密文；之后重新执行 `clean assembleApp` 即可产出 signed HAP 并安装。

## @ohos/webrtc 版本风险

当前本地实际锁定仍是 `@ohos/webrtc@1.0.0`：

```text
entry/oh-package-lock.json5
LiveKit/oh-package-lock.json5
oh_modules/.ohpm/@ohos+webrtc@1.0.0
```

`LiveKit/oh-package.json5` 写了 `^1.0.1`，但本地 lock 和 oh_modules 没有拉到 1.0.1。此前用户观察到 `1.0.0` 只能推音频、视频推不上，若本轮逻辑验证仍然只有音频，需要优先解决 OHPM 拉取 `@ohos/webrtc@1.0.1+` 的问题。
