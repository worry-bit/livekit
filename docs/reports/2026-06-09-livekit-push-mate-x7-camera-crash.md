# 2026-06-09 Mate X7 LiveKit 摄像头推流闪退 SDK 补丁报告

## 结论

这次闪退确认是 LiveKit SDK 侧问题，不应该在 `entry` 里关闭推流入口规避。

Mate X7 真机点击“开始直播推流”后，应用不是 ArkTS 异常，而是在 `@ohos/webrtc` 摄像头采集 native 线程崩溃：

- `Reason: Signal: SIGSEGV(SEGV_MAPERR)`
- `Fault thread: v-track-source`
- 栈顶：`strlen` -> `libohcamera.so(OH_CameraDevice_GetCameraOrientation)` -> `libohos_webrtc.so`

触发链路：

`entry LiveKitUtil.publishVideo()` -> `LiveKitClient.publishVideo()` -> `RTCEngine.publishVideo()` -> `PeerConnectionFactory.createVideoSource(...)`

## 根因判断

当前 `LiveKit/src/main/ets/util/RTCEngine.ets` 和 `LiveKit/src/main/ets/koophone/KooUserMedia.ets` 都把 `facingMode: 'user' | 'environment'` 透传给 `@ohos/webrtc` 的 `createVideoSource()`。

`@ohos/webrtc` 1.0.1 README 示例只传 `width / height / frameRate`，没有传 `facingMode`。真机 crash 栈显示 native 层进入相机方向查询 `OH_CameraDevice_GetCameraOrientation` 后崩溃。

补丁过程中做过一次中间验证：仅移除 `facingMode` 并把默认参数降到 `640x480@15` 后，真机仍在 `v-track-source` 同一线程、同一 native 栈崩溃。因此问题不能简单归结为 entry 调用错误，更接近 `@ohos/webrtc` 在 Mate X7 / HarmonyOS 6.1 上的本地摄像头 `createVideoSource()` 采集路径兼容性问题。当前提交给 SDK 的修正原则是：

- 不再向 `createVideoSource()` 传 `facingMode`；
- 默认采集参数从 `1280x720@30` 降到 `640x480@15`；
- `frameRate` 改成 `@ohos/webrtc` README 示例里的 `{ min, max }` 范围对象；
- `switchCamera()` 先做 no-op，避免再次用 `facingMode` 重建 VideoSource；
- 等 SDK 后续拿到稳定的相机选择 API 后，再恢复真实前后摄切换。

## 修改文件

### `LiveKit/src/main/ets/util/RTCEngine.ets`

- `currentFacingMode` 默认值从 `environment` 改为 `user`。
- `publishVideo()` 默认采集参数改为 `640x480@15`。
- 新增 `buildVideoConstraints()`，只构造 `width / height / frameRate`，其中 `frameRate` 使用 `{ min, max }`。
- `createVideoSource()` 改为：

```ts
const constraints: webrtc.MediaTrackConstraints = this.buildVideoConstraints(width, height, frameRate)
this.videoSource = this.peerConnectionFactory.createVideoSource(constraints)
```

- `switchCamera()` 临时禁用，仅输出 warning，避免点击切摄像头再次崩溃。

### `LiveKit/src/main/ets/koophone/KooUserMedia.ets`

- `openCamera()` 不再把 `facingMode` 放入 constraints。
- 新增 `buildVideoConstraints()`，只传基础采集参数，`frameRate` 使用 `{ min, max }`。
- `cameraId` 和 `facingMode` 仍保留为业务状态，用于后续 SDK 恢复真实相机选择。

## 撤回的 entry 规避

上一版曾在 `entry` 侧把推流按钮显示为 `推流暂不可用`，这次已撤回。现在 `entry` 继续按原链路调用 LiveKit：

`requestPermissions()` -> `joinRoom()` -> `publishVideo()`。

## SDK 同事后续需要重点确认

1. `@ohos/webrtc` 1.0.1 在 Mate X7 / HarmonyOS 6.1 上的 `createVideoSource()` 是否有已知相机 orientation 崩溃问题。
2. `@ohos/webrtc` 1.0.1 是否支持 `facingMode` 字符串约束，以及是否需要通过 CameraKit 枚举真实 cameraId。
3. 如果基础 `createVideoSource()` 仍崩，需要 SDK 改为 CameraKit 采集后通过安全的 WebRTC 外部源接入，或升级/替换 `@ohos/webrtc` native 包。
4. `switchCamera()` 要恢复时，不能再直接 `{ facingMode: newFacingMode }` 重建 VideoSource，需要使用 SDK 确认安全的相机选择方式。

## 验证

- `git diff --check`
- `hvigorw test --no-daemon --stacktrace -p properties.enableSignTask=false`
- `hvigorw clean assembleHap --no-daemon --stacktrace -p properties.enableSignTask=false`

真机安装完整体包时仍需临时注入 IAM / SFU 真实参数，提交到 git 的源码继续保持占位符。

本轮真机二次验证情况：

- `2026-06-09 11:38:39`：仅移除 `facingMode` 后仍出现同栈 `v-track-source` native crash。
- `frameRate` 范围对象补丁已通过本地编译；因设备随后进入 hdc `Offline` 状态，未完成该补丁的最终真机点击验证。
