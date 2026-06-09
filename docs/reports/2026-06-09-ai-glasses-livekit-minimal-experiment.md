# 2026-06-09 AI Glasses LiveKit 最小实验报告

## 目标

本轮只做最小实验，不正式改完整 UI：在不打开 KooPhone 云机串流的情况下，也允许 entry 连接 LiveKit SFU 并发布视频；SDK 临时支持把 CameraService 暴露的 remote cameraId 传给 `createVideoSource()`，用于验证 HUAWEI AI Glasses 的第一视角画面能否作为推流源。

## 设备侧依据

Mate X7 真机已能看到眼镜作为分布式摄像头注册到系统 CameraService：

- `DeviceManagerService -getTrustlist`：设备类型为 `DEVICE_TYPE_GLASSES`。
- `DistributedCameraSourceService --registered`：`CameraNumber: 1`。
- `DistributedCameraSourceService --curState`：remote camera 处于 `Registered`。
- `CameraService`：存在 `Back Wide-Angle Remote` 摄像头，cameraId 形如 `<networkId>__Camera_device/0`。

完整 cameraId 属于本机设备标识，不提交到 git；真机构建时临时注入 `__LIVEKIT_GLASSES_CAMERA_DEVICE_ID__`。

## 代码改动

### SDK 临时实验改动

这些改动位于 `LiveKit` 模块，只用于本轮验证，后续 SDK 正式提供视频源选择接口后应回退或替换：

- `LiveKit/src/main/ets/util/types.ets`
  - `VideoCaptureOptions` 新增 `deviceId?: string`。
  - 作用：让 entry 可以把系统 cameraId 传入 SDK。

- `LiveKit/src/main/ets/util/RTCEngine.ets`
  - `publishVideo()` 读取 `options.deviceId`。
  - 如果传入显式 `deviceId`，不复用 `KooUserMedia` 的共享摄像头轨道，直接创建新的 `VideoSource`。
  - `buildVideoConstraints()` 增加 `deviceId` 参数，并写入 `webrtc.MediaTrackConstraints.deviceId`。
  - 作用：让 `PeerConnectionFactory.createVideoSource(constraints)` 尝试打开眼镜 remote camera。

回退方式：

```bash
git checkout -- LiveKit/src/main/ets/util/types.ets LiveKit/src/main/ets/util/RTCEngine.ets
```

### entry 配合改动

- `entry/src/main/ets/pages/Index1.ets`
  - 新增 `LIVEKIT_EXPERIMENT_USE_GLASSES_CAMERA`。
  - 新增 `LIVEKIT_EXPERIMENT_ALLOW_STANDALONE_PUSH`。
  - 新增 `LIVEKIT_EXPERIMENT_GLASSES_CAMERA_DEVICE_ID` 占位符。
  - 删除“必须先打开淘宝/抖音云机直播才能推流”的启动限制。
  - 选择页也渲染 LiveKit 推流浮层，因此没有云机串流时也能点击“开始直播推流”。
  - `publishVideo()` 调用时传入注入后的眼镜 cameraId。
  - 预览标签在注入眼镜 cameraId 后显示“眼镜预览/等待眼镜”。

- `entry/src/main/ets/rtc/LiveKitUtil.ets`
  - `publishVideo(surfaceId, deviceId)` 增加 `deviceId` 入参。
  - 构造 `VideoCaptureOptions`，传给 `client.publishVideo(surfaceId, options)`。

- `entry/src/main/ets/push/LiveKitPushPolicy.ets`
  - 新增 `shouldAutoStopLiveKitPush()`。
  - 实验开关打开时，即使没有云机直播，也不自动关闭本机/眼镜推流。

- `entry/src/test/LocalUnit.test.ets`
  - 新增用例覆盖 `allowStandalonePush=true` 时不会因为没有 KooPhone 直播而自动停止 LiveKit 推流。

## 验证路径

1. 真机构建前临时注入：
   - IAM/SFU 真实参数。
   - `__LIVEKIT_GLASSES_CAMERA_DEVICE_ID__`，来源于真机 `CameraService` 暴露的 remote cameraId。
2. 打开应用后不选择淘宝/抖音，直接点击“开始直播推流”。
3. 预期链路：
   - `Index1.toggleLiveKitPush()`
   - `Index1.startLiveKitPush()`
   - `LiveKitUtil.requestPermissions()`
   - `LiveKitUtil.joinRoom()`
   - `LiveKitUtil.publishVideo(surfaceId, deviceId)`
   - `RTCEngine.publishVideo()`
   - `PeerConnectionFactory.createVideoSource({ deviceId })`
4. 如果预览区和 SFU 端看到眼镜第一视角，说明 remote cameraId 方案可行。

## 本轮真机结果

已安装临时注入真实 IAM/SFU 参数和 remote cameraId 的完整 HAP 到 Mate X7。

已验证通过：

- 不选择淘宝/抖音云机直播时，选择页顶部可以直接显示 LiveKit 推流浮层。
- 点击“开始直播推流”后会按顺序弹出麦克风和相机权限弹窗。
- 允许权限后应用没有闪退，也没有新增 `com.hssw.livekit` 崩溃日志。
- 页面错误文案已从 `undefined` 修正为“连接 LiveKit SFU 房间失败”。

当前阻塞：

- 日志显示失败发生在 LiveKit SFU WebSocket 建连阶段：
  - `NETSTACK: Lws client connection error conn fail: 110`
  - `[SignalClient] WebSocket error`
  - `[LiveKitClient] Connect failed`
- 这一步早于 `RTCEngine.publishVideo()`，因此还没有进入 `createVideoSource({ deviceId })`，本轮还不能判断眼镜 remote cameraId 是否能成功出画。
- Mate X7 能 ping 通 SFU 主机，但 WebSocket 端口连接失败；Mac 侧访问同一端口也超时。需要先确认当前网络到 SFU 的 7880 端口是否放通，或者换成公网可达的 SFU 测试地址。

本轮顺手修复：

- `entry/src/main/ets/rtc/LiveKitUtil.ets` 对底层 WebSocket 失败的空错误增加兜底文案，避免页面显示 `undefined`。

本地截图：

- `/tmp/livekit-glasses-final-selection.jpeg`：未选择云机直播时，选择页已显示 LiveKit 推流浮层。
- `/tmp/livekit-glasses-final-error-text.jpeg`：SFU WebSocket 失败后显示明确错误文案。

## 后续正式方案

如果本轮验证成功，正式实现不应该 hardcode cameraId，而应由 SDK 暴露以下能力：

- `listVideoSources()`：列出本机摄像头和 remote/distributed 摄像头。
- `publishVideo(surfaceId, options)`：正式保留 `deviceId`。
- `switchVideoSource(deviceId)`：推流中切换视频源。

entry 负责展示“本机摄像头/眼镜摄像头”选择 UI，并把用户选择传给 SDK；SDK 负责枚举设备、打开指定设备、处理占用和失败回退。
