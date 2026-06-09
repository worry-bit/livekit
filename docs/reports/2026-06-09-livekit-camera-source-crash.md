# 2026-06-09 LiveKit 摄像头推流闪退排查报告

## 现象

Mate X7 真机上，先进入 KooPhone 云机串流，再点击页面上的“开始直播推流”，应用会发生 native crash。崩溃不是 ArkTS 异常，而是 `libohos_webrtc.so` 里启动本机摄像头采集时触发的 SIGSEGV。

已抓到的典型 crash 文件：

- `/data/log/faultlog/faultlogger/cppcrash-com.hssw.livekit-20020202-20260609145601938.log`
- `/data/log/faultlog/faultlogger/cppcrash-com.hssw.livekit-20020202-20260609150714009.log`
- `/data/log/faultlog/faultlogger/cppcrash-com.hssw.livekit-20020202-20260609151201960.log`
- `/data/log/faultlog/faultlogger/cppcrash-com.hssw.livekit-20020202-20260609152056561.log`

关键栈：

```text
Fault thread: v-track-source
strlen
OH_CameraDevice_GetCameraOrientation
libohos_webrtc.so
```

## 根因判断

这次问题和最新引入的 `@ohos/webrtc@1.0.1` 强相关。实测中，即使 KooPhone 侧还没有主动打开本机摄像头，只由 `RTCEngine.publishVideo()` 第一次创建 `VideoSource`，也会进入 `OH_CameraDevice_GetCameraOrientation` 的 native 崩溃路径。

因此问题不只是“两个调用方同时打开同一个摄像头”，而是两个因素叠加：

1. `@ohos/webrtc@1.0.1` 在 Mate X7 上的 `createVideoSource()` 摄像头方向查询路径不稳定，会直接 native crash。
2. KooPhone 摄像头上行和 LiveKit 本机推流如果分别创建 `VideoSource`，会增加同一时刻重复打开相机的概率，使问题更容易暴露。

## 修改内容

### `LiveKit/src/main/ets/koophone/KooUserMedia.ets`

- 新增全局共享摄像头轨道管理：
  - `KooUserMedia.getSharedVideoTrack()`
  - `KooUserMedia.registerSharedVideoTrack()`
  - `KooUserMedia.retainSharedVideoTrack()`
  - `KooUserMedia.releaseSharedVideoTrack()`
- `openCamera()` 会优先复用已存在的共享 `VideoTrack`，避免 KooPhone 和 LiveKit 推流分别打开两路本机摄像头。
- 新建摄像头时只传基础约束：`width / height / frameRate`，不再向 `createVideoSource()` 传 `facingMode`。
- `stopCamera()` 改为引用计数释放；最后一个使用方释放时才 `track.stop()`。

### `LiveKit/src/main/ets/util/RTCEngine.ets`

- `publishVideo()` 先检查 `KooUserMedia` 是否已有共享摄像头轨道：
  - 有共享轨道：直接复用并渲染本地预览。
  - 无共享轨道：创建一条本地摄像头轨道后注册为共享轨道。
- 新增重复发布保护：已有 `videoTrack` 时直接返回，避免重复 `createVideoSource()`。
- `unpublishVideo()` / `close()` 通过共享轨道引用计数释放摄像头。
- `switchCamera()` 暂时不再重建 `VideoSource`，只打印跳过日志；等 SDK 确认 Mate X7 上安全的 cameraId/deviceId 选择方式后再恢复。
- 因 `@ohos/webrtc@1.0.0` 的 `VideoSource` 类型没有 `release()`，删除 `VideoSource.release()` 调用，只保留 `VideoTrack.stop()`。

### 依赖版本

- `LiveKit/oh-package.json5`：`@ohos/webrtc` 从 `^1.0.1` 回退到 `^1.0.0`。
- `LiveKit/oh-package-lock.json5`：锁定 `@ohos/webrtc@1.0.0`。
- `entry/oh-package-lock.json5`：同步锁定 `@ohos/webrtc@1.0.0`。

`ohpm install --all` 后已确认本地生成依赖锁和构建日志都指向：

```text
oh_modules/.ohpm/@ohos+webrtc@1.0.0
```

## 验证结果

执行过的检查：

```bash
git diff --check
/Applications/DevEco-CommandLineTools/6.1.1.280/command-line-tools/bin/ohpm install --all
/Applications/DevEco-CommandLineTools/6.1.1.280/command-line-tools/bin/hvigorw test --no-daemon --stacktrace -p properties.enableSignTask=false
/Applications/DevEco-CommandLineTools/6.1.1.280/command-line-tools/bin/hvigorw clean assembleHap --no-daemon --stacktrace -p properties.enableSignTask=false
```

真机验证：

- 使用临时注入真实 IAM/SFU 参数的完整 HAP 安装到 Mate X7。
- 先点击“淘宝直播”并进入 KooPhone 云机 playing 状态。
- 再点击“开始直播推流”。
- 本机摄像头预览正常出现，应用进程未退出。
- 等待超过 12 秒后，`/data/log/faultlog/faultlogger/` 未出现新的 `cppcrash-com.hssw.livekit-*`。

截图：

- `/tmp/livekit-screen-before-push.jpeg`
- `/tmp/livekit-screen-after-push-click.jpeg`

## 给 SDK 同事的建议

1. 在 Mate X7 上暂时不要使用 `@ohos/webrtc@1.0.1` 的摄像头采集路径，建议回退到 `@ohos/webrtc@1.0.0`，直到确认 1.0.1 的 `OH_CameraDevice_GetCameraOrientation` 崩溃已修复。
2. SDK 内部应该提供“本机摄像头采集协调器”或共享 track 能力，避免 KooPhone camera upstream 和 LiveKit publish video 各自创建 `VideoSource`。
3. 切换摄像头不要通过立即销毁并重建 `VideoSource` 硬切，后续应优先验证：
   - SDK 是否支持安全的 cameraId/deviceId 约束；
   - 是否能通过 `replaceTrack` 或 SDK 原生 camera switch API 切换；
   - 是否能保证切换时不会出现两个 active camera source。
4. 如果必须支持两路本机摄像头同时采集，需要 SDK 明确给出 Mate X7 上可用的多摄能力检测和失败回退策略；当前不应默认并发打开。
