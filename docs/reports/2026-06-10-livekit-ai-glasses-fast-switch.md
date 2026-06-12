# 2026-06-10 AI 眼镜推流切换卡顿修复记录

## 修改目标

- 开始直播选择页不再显示本机/眼镜预览黑框，也不显示 LiveKit 推流控制组件；只保留淘宝/抖音选择和“开始直播”按钮。
- 进入云机直播画面后才显示 LiveKit 推流控制组件，并且只在点击“开始直播推流”或推流中切换摄像头时挂载预览 surface。
- 推流中点击“切换AI眼镜摄像头”不再走 `unpublishVideo()` + `publishVideo()`，改为在同一个 WebRTC sender 上执行 `replaceTrack()`。
- 2026-06-10 追加修复：按钮文案改为“推送AI眼镜视频流”和“推送手机视频流”；切换 AI 眼镜时先把 sender 置空并释放旧手机摄像头，再创建 AI 眼镜 track，避免同时占用两路摄像头导致卡住。
- 2026-06-10 二次修复：`RTCEngine.buildVideoConstraints()` 中的 `deviceId` 从普通字符串改为 `{ exact: cameraId }`。普通字符串只是偏好值，底层可回退到默认手机摄像头；`exact` 才能强制使用 AI Glasses remote camera。切换失败时会尝试恢复原手机视频轨道。
- 2026-06-10 三次修复：真机复现“点击开始直播推流后进程直接退出”，系统生成 `cppcrash-com.samples.ndkopengl...`。原因是手机推流也走了 `{ exact: device/0 }` 约束，`@ohos/webrtc` native 侧不稳定。修复为：手机视频流不传本机 cameraId，只传基础约束；只有 AI Glasses remote cameraId（包含 `__Camera_`）才使用 `{ exact }`。
- 2026-06-10 追加配置：实例池新增 `__TAOBAO_INSTANCE_ID__`，淘宝直播默认实例改为 `__TAOBAO_INSTANCE_ID__`，原 `__TAOBAO_INSTANCE_ID__` 保留为备用实例。

## 修改文件

### entry/src/main/ets/pages/Index1.ets

- 新增 `liveKitPreviewVisible` 状态。
- `startLiveKitPush()` 在点击开始后才设置 `liveKitPreviewVisible=true` 并等待 XComponent surface。
- `liveKitPushOverlay()` 根据 `shouldRenderLiveKitPreviewSurface()` 条件渲染预览 surface，未开始推流时只展示控制按钮。
- `switchLiveKitToAiGlassesCamera()` 在已推流状态下才显示预览并执行视频源替换；未推流状态只预选 AI 眼镜源。
- `selectionPage()` 删除 `liveKitPushOverlay()` 渲染点，初始选择页不再出现任何推流组件。
- `liveKitSwitchAiGlassesButton()` 文案改为“推送AI眼镜视频流”。
- 淘宝默认实例 `TAOBAO_INSTANCE_ID` 改为 `__TAOBAO_INSTANCE_ID__`，并将 `__TAOBAO_INSTANCE_ID__` 放入共享实例池作为备用。

### entry/src/main/ets/push/LiveKitPushPolicy.ets

- 新增 `shouldRenderLiveKitPreviewSurface()`，用于测试和页面判断预览挂载时机。

### entry/src/main/ets/rtc/LiveKitUtil.ets

- `replaceVideoSource()` 改为调用 SDK 新增的 `LiveKitClient.replaceVideoSource()`，不再先停发再重新发布。

### LiveKit/src/main/ets/util/LiveKitClient.ets

- 新增 `replaceVideoSource(surfaceId, options)`。
- 对外保持 LiveKitClient 使用方式不变，entry 只新增调用这个公开方法。

### LiveKit/src/main/ets/util/RTCEngine.ets

- 新增 `videoSender` 保存 `publisherPC.addTrack()` 返回的 `RTCRtpSender`。
- 新增 `replaceVideoSource(surfaceId, options)`，内部调用 `videoSender.replaceTrack(newTrack)`。
- 新增 `createLocalVideoTrackBundle()` 和 `releaseVideoTrack()`，确保新 track 创建成功并替换后再释放旧 track。
- 显式 `deviceId` 的 AI 眼镜 track 不注册为 `KooUserMedia` 全局共享 track，避免覆盖 KooPhone/手机摄像头的共享状态。
- 追加修复 `replaceVideoSource()` 顺序：先 `videoSender.replaceTrack(null)`，解绑本地 renderer，释放旧 track，再创建并挂载新 track。原因是先创建新 track 会同时占用手机摄像头和 AI 眼镜 remote camera，真机上容易卡住。
- `buildVideoConstraints()` 使用 `constraints.deviceId = { exact: deviceId }`，避免 `@ohos/webrtc` 把 AI 眼镜 cameraId 当作可选偏好然后回退到手机摄像头。
- `buildVideoConstraints()` 对本机 `device/0` 这类 cameraId 直接忽略，不传给 `createVideoSource()`；只对 AI Glasses remote cameraId 使用 `{ exact }`。
- `replaceVideoSource()` 记录旧 `VideoCaptureOptions`，如果 AI 眼镜 track 创建或挂载失败，会尽量恢复原来的手机视频源。

## 验证

- `git diff --check`
- `hvigorw test --no-daemon --stacktrace -p properties.enableSignTask=false`
- `hvigorw clean assembleApp --no-daemon --stacktrace`

构建通过，签名 HAP 已生成：

`entry/build/default/outputs/default/entry-default-signed.hap`

当前 `hdc list targets` 返回空，未检测到真机，因此尚未安装。设备重新连接后可直接执行：

`hdc install -r entry/build/default/outputs/default/entry-default-signed.hap`
