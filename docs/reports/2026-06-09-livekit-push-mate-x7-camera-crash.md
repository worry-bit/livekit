# 2026-06-09 LiveKit 推流点击闪退修复报告

## 背景

Mate X7 真机上，云机串流成功后点击页面中的“直播推流”会导致应用直接闪退。本轮只允许修改 `entry` 模块，不允许修改 `LiveKit` SDK 模块。

## 崩溃定位

真机 faultlog 显示崩溃不是 ArkTS 页面异常，而是进入本机摄像头采集后的 native 崩溃：

- `Reason: Signal: SIGSEGV(SEGV_MAPERR)`
- `Fault thread: v-track-source`
- 栈顶路径：`strlen` -> `libohcamera.so(OH_CameraDevice_GetCameraOrientation)` -> `libohos_webrtc.so`

这说明点击“直播推流”后，`entry` 调用 `liveKitUtil.publishVideo()`，进一步进入 `livekit-harmony` 的本机摄像头采集路径；默认采集参数会触发 Mate X7 后摄 orientation 查询路径崩溃。

## 修改内容

### `entry/src/main/ets/push/LiveKitPushPolicy.ets`

- 新增 `getSafeLiveKitVideoCaptureOptions()`：
  - 固定前摄：`facingMode: 'user'`
  - 降低采集参数：`640x360@15`
  - 避免走 SDK 默认的 `environment 1280x720@30` 后摄采集路径。
- 新增推流入口开关策略：
  - `canStart=false` 时按钮文案显示 `推流暂不可用`；
  - 按钮颜色置灰；
  - 点击策略返回 false，避免进入 SDK native 摄像头采集路径。
- 新增 `canClickLiveKitSwitchCameraButton()`：
  - 保留切换摄像头能力代码；
  - 当前通过入口开关禁用点击，避免用户切到后摄后再次触发 native 崩溃。

### `entry/src/main/ets/rtc/LiveKitUtil.ets`

- `publishVideo(surfaceId)` 改为显式传入安全采集参数：
  - `getSafeLiveKitVideoCaptureOptions()` -> `client.publishVideo(surfaceId, captureOptions)`。
- 增加日志，输出当前采集配置，方便真机 hilog 定位。

### `entry/src/main/ets/pages/Index1.ets`

- 新增 `ENABLE_LIVEKIT_PUSH_START_BUTTON = false`。
- “开始直播推流”入口改为临时关闭：
  - UI 保留推流区域和按钮位置；
  - 按钮显示 `推流暂不可用`；
  - 点击只展示错误提示，不再调用 `startLiveKitPush()`。
- 新增 `ENABLE_LIVEKIT_CAMERA_SWITCH = false`。
- “切换摄像头”按钮保留 UI 和方法，但在开关关闭时不执行 SDK 的 `switchCamera()`。
- 禁用态点击会提示：`Mate X7 后摄采集路径暂时禁用，避免点击后闪退`。

### `entry/src/test/LocalUnit.test.ets`

- 新增安全采集策略测试：
  - 确认推流默认使用前摄、低分辨率、低帧率。
- 新增推流入口禁用策略测试：
  - 确认 `canStart=false` 时文案、颜色、点击策略都进入禁用态。
- 新增摄像头切换按钮策略测试：
  - 验证功能开关关闭时按钮不可触发；
  - 验证功能开关打开且已推流、非 busy 时可触发。

## 没有修改的内容

- 没有修改 `LiveKit` 模块。
- 没有复制或改写 SDK 内部实现。
- 没有提交真实 IAM、KooPhone、SFU 密钥；真机安装时仍从本地 `local-secrets/` 临时注入。

## 验证计划

1. `git diff --check`
2. `hvigorw test --no-daemon --stacktrace -p properties.enableSignTask=false`
3. 临时注入真实参数后构建并签名 HAP。
4. 安装到 Mate X7 真机。
5. 打开应用，启动云机直播，点击推流按钮。
6. 检查：
   - 应用进程不退出；
   - 无新增 `cppcrash-com.hssw.livekit`；
   - 按钮保持禁用态，不再进入 `LiveKitClient.publishVideo()`。

## 真机复测结论

临时只改成前摄低分辨率后，真机仍出现新崩溃：

- `cppcrash-com.hssw.livekit-20020202-20260609112638625.log`
- `Fault thread: v-track-source`
- 栈仍为 `strlen` -> `OH_CameraDevice_GetCameraOrientation` -> `libohos_webrtc.so`

这说明当前问题不是单纯默认后摄参数导致，而是 SDK 最新 `@ohos/webrtc` 摄像头采集路径本身在 Mate X7 上触发 native 崩溃。用户补充的排查线索也指向最近改过的 `LiveKit/src/main/ets/util/RTCEngine.ets`、`LiveKit/src/main/ets/koophone/KooUserMedia.ets`、`LiveKit/oh-package.json5`、`LiveKit/oh-package-lock.json5`。因为本轮明确禁止修改 `LiveKit` 模块，最终采取 `entry` 侧关闭推流入口的方案，保证云机直播能力不被推流按钮拖垮。

## 后续建议

这个修复是 `entry` 侧规避方案。后续如果 LiveKit SDK 开发侧要恢复本机摄像头推流，需要在 SDK 内部继续排查：

- `RTCEngine.publishVideo()` 中 `PeerConnectionFactory.createVideoSource(constraints, false)`；
- `KooUserMedia.openCamera()` 中同类 `createVideoSource(constraints)`；
- `@ohos/webrtc` 1.0.1 的 Mate X7 摄像头 orientation 查询兼容性。
