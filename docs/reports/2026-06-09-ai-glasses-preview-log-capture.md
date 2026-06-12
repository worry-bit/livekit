# 2026-06-09 AI Glasses 预览日志抓取报告

## 结论

本次在 Mate X7 真机上重新打开 app，点击“开始眼镜预览”，并抓取 12 秒 hilog 后确认：

1. entry 侧确实调用了 CameraKit 的 remote camera 查询，并且 `getCameraDevices(...CAMERA_CONNECTION_REMOTE)` 返回了 `hostDeviceName = AI Glasses` 的 CameraDevice。
2. entry 侧把这个 AI Glasses CameraDevice 传给了 `createCameraInput(cameraDevice)`，`cameraInput.open()`、`session.commitConfig()`、`session.start()` 都成功返回。
3. 成功启动后约 0.037 秒，系统向 app 回调 `cameraInput error code=7400201`，底层 `CameraDeviceServiceCallback::OnError()` 的 `errorType = 11`。
4. 同一时间，`dcamera_host` 关闭了 distributed camera，并出现 `result = -9`、随后 `result = -7` 的通知。
5. 眼镜服务日志显示它识别到 `com.hssw.livekit` 使用眼镜 camera 后执行了白名单/MCU 逻辑，并出现 `McuNotifyForceSwitchLocalCamera`，目标 camera 被切到 `device/0`。这能解释为什么页面最终看到的是手机摄像头，而不是眼镜第一视角。
6. 本轮没有在 app 层收到 `cameraOcclusionDetection` 的 JS 回调值；但底层 CameraDaemon 有 `Msc_Occlusion_Detect` 日志。遮挡检测结果多数为 `detect result is 0`，后续出现 `protection result: 1`。结合眼镜语音“外置隐私灯被遮挡无法使用”，目前能看到的系统侧关键返回是 `cameraInput error code=7400201`、`DCameraDevice result=-9/-7`、`McuNotifyForceSwitchLocalCamera`。

## 抓取信息

- 设备：Mate X7 真机，HUAWEI AI Glasses-7667 已连接。
- app bundle：`com.hssw.livekit`
- 操作方式：`uitest uiInput click 1258 374` 点击“开始眼镜预览”按钮。
- 原始日志目录：`/tmp/ai_glasses_log_20260609_224751_uitest_click`
- 原始文件：
  - `/tmp/ai_glasses_log_20260609_224751_uitest_click/hilog_all_after.txt`
  - `/tmp/ai_glasses_log_20260609_224751_uitest_click/hilog_key_ai_glasses.txt`
  - `/tmp/ai_glasses_log_20260609_224751_uitest_click/camera_service_after.txt`
  - `/tmp/ai_glasses_log_20260609_224751_uitest_click/livekit_layout_after.json`
  - `/tmp/ai_glasses_log_20260609_224751_uitest_click/livekit_after.jpeg`

## entry 侧 CameraKit 调用反参

关键日志：

```text
[AI_GLASS_DBG] getCameraDevices input position=BACK,type=WIDE_ANGLE,connection=REMOTE
[AI_GLASS_DBG] getCameraDevices.remoteReturn count=1
[AI_GLASS_DBG] getCameraDevices.remoteReturn[0] camera[0] id=93bf...device/0, conn=2, type=1, pos=1, host=AI Glasses, hostType=2609
[AI_GLASS_DBG] selected reason=hostDeviceName AI Glasses, camera[0] id=93bf...device/0, conn=2, type=1, pos=1, host=AI Glasses, hostType=2609
```

参数含义：

- `position=BACK`：查询后置方向摄像头。
- `type=WIDE_ANGLE`：查询广角摄像头。
- `connection=REMOTE`：只查询分布式/远端摄像头。
- `conn=2`：CameraKit 反参里的 connectionType，表示 remote。
- `type=1`：CameraKit 反参里的 cameraType，当前 AI Glasses 返回为 wide-angle。
- `pos=1`：CameraKit 反参里的 cameraPosition，表示 back。
- `host=AI Glasses`：CameraKit 反参 `hostDeviceName`，当前用它确认这是眼镜设备。
- `hostType=2609`：CameraKit 反参 `hostDeviceType`，系统为眼镜主机返回的设备类型值。

## 创建预览链路

关键日志：

```text
CreateCameraInput curFoldStatus:1, position:1
CameraInput::InitCameraInput Contructor Camera: 93bf...__Camera_device/0
[AI_GLASS_DBG] cameraInput error logger registered
[AI_GLASS_DBG] cameraOcclusionDetection logger registered
CameraInputNapi::Open check secure parameter fail, try open with CameraConcurrentType
CameraInputNapi::Open check secure parameter fail, try open without secure flag
[GlassesPreviewUtil] remote camera supported scene modes: 1,2
[GlassesPreviewUtil] selected preview profile: 1280 720
StartAsync errorCode:0
[GlassesPreviewUtil] CameraKit remote glasses preview started with NORMAL_VIDEO session
```

这里说明 entry 的 CameraKit 链路已经走到会话启动成功：

- `createCameraInput(cameraDevice)` 使用的是 AI Glasses 的 remote CameraDevice。
- `cameraInput.open()` 没有抛异常。
- `createPreviewOutput(profile, surfaceId)` 使用了 1280x720。
- `createSession(NORMAL_VIDEO)`、`commitConfig()`、`start()` 成功。

## 失败与强制切回证据

启动成功后系统马上回调错误：

```text
CameraDeviceServiceCallback::OnError() is called!, errorType: 11, errorMsg: 0
[AI_GLASS_DBG] cameraInput error code=7400201, message=undefined, input.camera[0] id=93bf...__Camera_device/0, conn=2, type=1, pos=1, host=AI Glasses, hostType=2609
DCameraDevice::Notify for event type = 1, result = -9, content = sink stop dcamera business.
DCameraDevice::Close distributed camera: 93bf******ce/0
DCameraDevice::Notify for event type = 1, result = -7, content = .
```

眼镜服务随后把 camera 切回本机：

```text
XRGA_Camera_Control: CheckAppInWhiteList: appName :com.hssw.livekit
LiveVideoCallManager --> checkAppIsWhiteList enter
LiveVideoCallManager --> getWhiteListNames enter
LiveVideoCallManager --> sendAppIsWhiteListToMcu enter
LiveVideoCallManager --> sendAppIsWhiteListToMcu start end, sendTlvData result: 0
McuNotifyForceSwitchLocalCamera: oriCameraId  , destCameraId = dev***e/0
ConnectManager SwitchCamera
CameraPreOn CameraId is not glassCamera, PreOn CameraId : device/0
```

这段是本轮最关键的系统行为：SDK/API 层选择的是 AI Glasses remote camera，但眼镜服务收到 camera active 后执行白名单判断和 MCU 通知，随后强制切到本机 `device/0`。因此 demo 页面后续显示手机摄像头，不能简单理解为 entry 没有传入眼镜 cameraId。

## 遮挡相关日志

本轮 app 层只确认注册成功：

```text
[AI_GLASS_DBG] cameraOcclusionDetection logger registered
```

但没有收到形如 `cameraOcclusionDetection isCameraOccluded=...` 的 JS 回调。

系统底层有遮挡检测日志：

```text
Msc_Occlusion_Detect: msc occlusion detect Init
MscOcclusionDetectAlgo compareThreshold:55 zoomThreshold:1.50 delayTime:3 prevCamThreshold:30.00
Msc_Occlusion_Detect: mainLv 86.00, mscLv 0.00 zoomRatio 1.00.
Msc_Occlusion_Detect: msc occlusion detect result is 0
Msc_Occlusion_Detect: diffMean 86.04, diffvar 0.04, covariance 0.00
Msc_Occlusion_Detect: msc occlusion protection result: 1
Msc_Occlusion_Detect: msc occlusion detect result is 0
```

目前不能仅凭公开日志把 `protection result: 1` 精确翻译成“外置隐私灯被遮挡”，但它和眼镜语音报错发生在同一轮 camera 启动/关闭流程附近，是目前能从系统侧看到的遮挡/保护相关返回。

## 当前判断

当前问题更像是 AI Glasses 侧的第一视角开放策略/白名单/MCU 控制逻辑，而不是 entry 侧 CameraKit 参数传错：

- CameraKit 能枚举到 `host=AI Glasses` 的 remote camera。
- entry 能把 remote camera 打开并启动预览会话。
- 启动后被系统/眼镜服务回调错误并关闭 distributed camera。
- 眼镜服务明确执行 `CheckAppInWhiteList` 和 `McuNotifyForceSwitchLocalCamera`。

如果需要真正让 demo 使用眼镜第一视角，下一步需要华为侧或眼镜 SDK 侧确认：

1. `com.hssw.livekit` 是否需要加入 AI Glasses 第一视角直播/通话白名单。
2. `cameraInput error code=7400201`、`errorType=11` 在 AI Glasses remote camera 场景下的官方含义。
3. `DCameraDevice Notify result=-9/-7` 是否对应眼镜侧拒绝、业务停止或隐私灯保护。
4. 是否存在可授权第三方 app 保持 remote camera 而不被 `McuNotifyForceSwitchLocalCamera` 切回 `device/0` 的接口。
