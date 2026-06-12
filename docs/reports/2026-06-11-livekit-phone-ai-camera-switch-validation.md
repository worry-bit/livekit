# 2026-06-11 LiveKit 手机/AI 眼镜视频源切换修复与真机验证

## 本轮目标

- 修复“推送手机视频流成功后，切换手机摄像头失败”。
- 修复“点击推送 AI 眼镜视频流时卡住或没有明确反馈”。
- 构建带本地真实配置的签名 HAP，并安装到当前连接的 Mate X7。

## 修改内容

### `entry/src/main/ets/rtc/LiveKitCameraSwitchCoordinator.ets`

- 新增切换串行队列，避免连续点击导致多个 `unpublishVideo()` / `publishVideo()` 并发。
- 手机摄像头重开等待从 240ms 提高到 800ms。
- AI 眼镜 remote camera 重开等待设置为 1200ms，给 CameraService 更多时间释放旧本机摄像头。

### `entry/src/main/ets/rtc/LiveKitUtil.ets`

- `replaceVideoSource()` 增加切换开始日志，记录目标源是 `phone` 还是 `ai_glasses`。
- 切换失败时同步清理 `isVideoPublished`、`localVideoSurfaceId`、`currentVideoDeviceId`，避免页面停在“已发布”的假状态。
- `VideoCaptureOptions` 统一使用保守的 `640x480@15fps`，降低 Mate X7 和 remote camera 在重新打开视频源时的约束风险。

### `entry/src/main/ets/rtc/GlassesPreviewUtil.ets`

- `resolveNextPhoneCameraId()` 改为只从可切换的本机主摄候选中选择。
- 过滤条件保留 `DEFAULT/WIDE_ANGLE` 以及 `BACK/FRONT/FOLD_INNER`，避免误选长焦、超广角等非前后摄切换目标。
- 只有一个候选或下一个候选仍是当前 cameraId 时直接返回错误，不再重新打开同一个摄像头。

### `entry/src/main/ets/pages/Index1.ets`

- 切换失败后调用 `resetLiveKitAfterSwitchFailure()`，释放旧 LiveKit client 并让页面回到可重新开始推流的状态。
- 保留“推送手机视频流”和“推送AI眼镜视频流”两个入口。

### `LiveKit/src/main/ets/util/RTCEngine.ets`

- `MediaTrackConstraints.frameRate` 从 `{ min, max }` 改为 number，匹配当前本地 `@ohos/webrtc@1.0.0` 的类型定义。
- remote camera 视频轨道不再注册为 `KooUserMedia` 共享轨道，避免 AI 眼镜轨道污染本机摄像头共享状态。

## 真机验证

设备：

- 设备：Mate X7，`hdc` target 为 `9CN0224808033858`
- 系统：`OpenHarmony-6.0.2.130`
- API：22
- 安装包：`entry/build/default/outputs/default/entry-default-signed.hap`
- 包名：`com.samples.ndkopengl`

验证命令：

```bash
git diff --check
hvigor test --no-daemon --stacktrace -p properties.enableSignTask=false
hvigor clean assembleApp --no-daemon --stacktrace
hdc install -r entry/build/default/outputs/default/entry-default-signed.hap
```

结果：

- `git diff --check` 通过。
- `entry:test` 通过。
- `clean assembleApp` 通过，生成 signed HAP。
- 初次安装因设备 API 22 低于 `compatibleSdkVersion=23` 失败；已把本地调试构建的 `compatibleSdkVersion` 调整为 `6.0.2(22)` 后安装成功。
- 初始“开始直播”页面不显示 LiveKit 预览黑框。
- 选择淘宝直播并开始后，KooPhone 串流进入 `playing`。
- 点击“开始直播推流”后，麦克风和相机权限弹窗正常出现并授权。
- 手机视频流发布成功，日志显示 `Video published`。
- 点击“切换手机摄像头”后，从 `device/0` 切到 `device/1`，日志显示 `Video unpublished` 后重新 `Video published`，页面仍保持推流态。

关键日志文件：

```text
logs/device/20260611-145819-livekit-new-smoke.hilog
logs/device/livekit-after-phone-switch.json
logs/device/livekit-after-ai-switch.json
```

## AI 眼镜本次结论

本次点击“推送AI眼镜视频流”没有进入 WebRTC 切源阶段，原因是 CameraKit 当前没有枚举到 remote camera。

页面和日志显示：

```text
当前系统没有通过 CAMERA_CONNECTION_REMOTE 返回眼镜摄像头
strict remote query failed: Error: cameraDeviceList is null.
all=2, remote=0
all[0] id=device/0, conn=0, type=0, pos=1, host=, hostType=0
all[1] id=device/1, conn=0, type=0, pos=2, host=, hostType=0
```

这说明当前系统只暴露了 Mate X7 本机摄像头，没有把 AI Glasses 注册成 `CAMERA_CONNECTION_REMOTE`。因此本轮无法验证 AI 眼镜真正切到 SFU 推流，但已修复原先“点击后卡住无明确反馈”的问题：现在会明确弹出“未找到 AI 眼镜摄像头”，并保留当前手机视频推流状态。

后续要继续验证 AI 眼镜推流，需要先让系统枚举返回 `hostDeviceName=AI Glasses` 的 remote camera，再点击“推送AI眼镜视频流”。
