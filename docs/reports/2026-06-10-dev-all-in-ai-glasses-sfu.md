# dev_all_in AI 眼镜 SFU 推流接入报告

## 结论

- 已从当前实验态切出 `dev_all_in` 分支。
- 已把 AI 眼镜从“只做本地 CameraKit 预览”接到 LiveKit SFU 推流链路：页面先解析 AI Glasses remote `cameraId`，再把它作为 `VideoCaptureOptions.deviceId` 传给 `LiveKitClient.publishVideo()`。
- 已恢复正常按钮入口：`开始直播推流` 走 `requestPermissions()` -> `joinRoom()` -> `publishVideo(surfaceId, deviceId)`。
- 已新增 `切换AI眼镜摄像头`，未推流时用于预选 AI 眼镜源，推流中用于不重连房间地替换视频源。
- 已保留并重命名手机按钮为 `切换手机摄像头`，当当前源为 AI 眼镜时自动置灰。
- 已通过 `git diff --check`、`hvigor test`、`hvigor clean assembleApp`。
- `@ohos/webrtc` 依赖声明已改成 `^1.0.1`，但 OHPM registry 当前返回 502，本机没有 1.0.1 缓存，所以实际构建日志仍显示使用 `@ohos/webrtc@1.0.0`。这一点还不能算完成 1.0.1 真机验证。

## Entry 侧改动

### `AppScope/app.json5`

- 保留当前实验态已验证可用的 `bundleName = com.samples.ndkopengl`。
- 原因：前序 AI 眼镜验证中，包名可能影响眼镜侧对第三方应用的 camera 访问策略，本轮 `dev_all_in` 基于该成功实验态继续合入 SFU。

### `entry/src/main/ets/pages/Index1.ets`

- 新增 `liveKitCameraSource` 状态，当前支持：
  - `phone`
  - `ai_glasses`
- `startLiveKitPush()` 改为：
  1. 等待 LiveKit 预览 `XComponent` surface。
  2. 请求相机和麦克风权限。
  3. 按当前 source 解析明确 `cameraId`。
  4. 调用 `liveKitUtil.joinRoom(LIVEKIT_SFU_URL, LIVEKIT_SFU_TOKEN)`。
  5. 调用 `liveKitUtil.publishVideo(surfaceId, deviceId)`。
- 新增 `switchLiveKitToAiGlassesCamera()`：
  - 先调用 `GlassesPreviewUtil.resolveAiGlassesCameraId()` 检测 AI 眼镜 remote camera。
  - 未找到时弹窗提示先连接 AI 眼镜。
  - 已在推流中时调用 `liveKitUtil.replaceVideoSource(surfaceId, deviceId)`，不重连 SFU 房间。
- 修改 `switchLiveKitCamera()`：
  - 不再调用 SDK 默认 `switchCamera()`。
  - 改为 entry 先用 CameraKit 取下一个安全本机 `cameraId`，再调用 `replaceVideoSource()`。
  - 目的是规避 Mate X7 折叠态多前摄下 native 相机选择崩溃。
- UI 改动：
  - 第一行：`开始直播推流` + `切换AI眼镜摄像头`。
  - 第二行：`切换手机摄像头` + 当前源标签。
  - AI 源启用后，手机摄像头切换按钮置灰。

### `entry/src/main/ets/rtc/GlassesPreviewUtil.ets`

- 保留原有 CameraKit 本地预览实验能力。
- 新增 `resolveAiGlassesCameraId(preferredDeviceId)`：
  - 只解析 AI Glasses remote `cameraId`，不打开预览、不占用相机。
  - 内部仍使用此前验证成功的 `getCameraDevices(BACK, WIDE_ANGLE, CAMERA_CONNECTION_REMOTE)` 和 `hostDeviceName === 'AI Glasses'` 选择逻辑。
- 新增 `resolvePreferredPhoneCameraId()`：
  - 从 `getSupportedCameras()` 中过滤本机摄像头。
  - 优先选择后置广角。
  - 过滤没有 preview profile 的设备，降低折叠屏前摄崩溃概率。
- 新增 `resolveNextPhoneCameraId(currentDeviceId)`：
  - 在安全本机 cameraId 列表内循环。
  - 用于替代 SDK 默认 `switchCamera()`。

### `entry/src/main/ets/rtc/LiveKitUtil.ets`

- `publishVideo(surfaceId, deviceId)` 记录当前 `currentVideoDeviceId`。
- 新增 `replaceVideoSource(surfaceId, deviceId)`：
  - 当前已推流：`unpublishVideo()` -> `publishVideo(surfaceId, deviceId)`。
  - 当前未推流：退化为 `publishVideo(surfaceId, deviceId)`。
  - 不调用 `leaveRoom()`，因此 SFU 房间连接保持不变。

### `entry/src/main/ets/push/LiveKitPushPolicy.ets`

- 新增视频源常量：
  - `LIVEKIT_CAMERA_SOURCE_PHONE`
  - `LIVEKIT_CAMERA_SOURCE_AI_GLASSES`
- 新增按钮策略：
  - `canSwitchPhoneCamera()`
  - `canSwitchAiGlassesCamera()`
  - `getLiveKitCameraSourceLabel()`

### `entry/src/test/LocalUnit.test.ets`

- 增加视频源按钮策略测试：
  - AI 眼镜源启用后手机切换按钮置灰。
  - AI 眼镜按钮忙碌态不可点。
  - 当前视频源标签正确。

## LiveKit SDK 侧最小改动

### `LiveKit/oh-package.json5`

- 将 `@ohos/webrtc` 依赖声明从 `^1.0.0` 改为 `^1.0.1`。
- 原因：用户确认 1.0.0 只能上传音频，视频需要 1.0.1 以上。
- 当前状态：OHPM registry 返回 502，`ohpm install` 无法下载 1.0.1，本机实际构建仍使用缓存中的 1.0.0。

### `LiveKit/src/main/ets/util/LiveKitClient.ets`

- `publishVideo()` catch 后重新抛出错误。
- `unpublishVideo()` catch 后重新抛出错误。
- 原因：此前 SDK 只打印错误不抛出，entry 无法判断 SFU 推流接口是否真正成功，会误把失败当成功。

## SFU 推流接口状态

- 页面调用入口：`Index1.toggleLiveKitPush()`。
- SFU 建连：`LiveKitUtil.joinRoom(url, token)`。
- 视频发布：`LiveKitUtil.publishVideo(surfaceId, deviceId)` -> `LiveKitClient.publishVideo(surfaceId, options)`。
- AI 眼镜推流参数：`options.deviceId = AI Glasses remote cameraId`。
- 推流中切源：`LiveKitUtil.replaceVideoSource(surfaceId, deviceId)`，不重新 `joinRoom()`。

当前编译通过，接口链路已接通到代码层；但 1.0.1 实包未拉取成功，尚未完成“webrtc 1.0.1 + 真机 + SFU + AI 眼镜”的最终端到端验证。

## 崩溃规避说明

参考崩溃日志中的 `AlignVideoFpsProfile failed! frontVideoSize = 0`，本轮规避策略是：

- entry 先明确选择 cameraId，不让 SDK 默认推断前置摄像头。
- 手机源优先用本机后置广角。
- 手机切换不再调用 SDK 默认 `switchCamera()`，改成 entry 选下一个 cameraId 后替换视频源。
- AI 眼镜源使用 remote cameraId，切换后禁用手机摄像头切换按钮。

## 验证命令

```bash
git diff --check
PATH="/Applications/DevEco-CommandLineTools/6.1.1.280/command-line-tools/bin:/Applications/DevEco-CommandLineTools/6.1.1.280/command-line-tools/tool/node/bin:$PATH" \
DEVECO_SDK_HOME="/Applications/DevEco-CommandLineTools/6.1.1.280/command-line-tools/sdk" \
/Applications/DevEco-CommandLineTools/6.1.1.280/command-line-tools/hvigor/bin/hvigorw test --no-daemon --stacktrace -p properties.enableSignTask=false

PATH="/Applications/DevEco-CommandLineTools/6.1.1.280/command-line-tools/bin:/Applications/DevEco-CommandLineTools/6.1.1.280/command-line-tools/tool/node/bin:$PATH" \
DEVECO_SDK_HOME="/Applications/DevEco-CommandLineTools/6.1.1.280/command-line-tools/sdk" \
/Applications/DevEco-CommandLineTools/6.1.1.280/command-line-tools/hvigor/bin/hvigorw clean assembleApp --no-daemon --stacktrace -p properties.enableSignTask=false
```

构建产物：

```text
entry/build/default/outputs/default/app/entry-default.hap
entry/build/default/outputs/default/entry-default-unsigned.hap
```

## 当前阻塞

`ohpm install` 拉取 `@ohos/webrtc@^1.0.1` 失败：

```text
GET https://ohpm.openharmony.cn/ohpm/@ohos/webrtc 502 Bad Gateway
NOTFOUND package '@ohos/webrtc@^1.0.1'
```

本机当前只有：

```text
oh_modules/.ohpm/@ohos+webrtc@1.0.0
```

因此，1.0.1 的真实验证需要满足任一条件：

- OHPM registry 恢复正常后重新执行 `ohpm install`。
- SDK 同事提供 `@ohos/webrtc@1.0.1` HAR 或团队私仓地址。
- DevEco/SDK 环境里已有可被 ohpm 解析的 1.0.1 缓存。
