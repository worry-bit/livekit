# 视频推送功能设计文档

**日期：** 2026-05-25  
**项目：** LiveKitDemo-main（HarmonyOS 鸿蒙）  
**范围：** 在现有音频推送基础上，新增摄像头视频推送 + 本地预览功能

---

## 1. 目标与约束

### 目标
- 采集本地摄像头画面，通过 `@ohos/webrtc` 发布到 LiveKit 服务器
- 在 UI 上实时显示本地摄像头预览画面
- 支持前/后摄像头切换
- 支持开启/关闭视频推送

### 不在本期范围内
- 渲染远端视频（本项目仅作推送端）
- 分辨率/帧率配置（后续可扩展）
- 视频静音（track enabled 控制，后续可扩展）
- Camera Kit 直接接入（本期全部走 `@ohos/webrtc` 内部管道）

---

## 2. 技术选型

使用 **`@ohos/webrtc` 原生视频管道**，与现有音频实现保持同一架构层：

| 音频（已有） | 视频（新增） |
|---|---|
| `AudioSource` | `VideoSource` |
| `AudioTrack` | `VideoTrack` |
| `peerConnectionFactory.createAudioSource()` | `peerConnectionFactory.createVideoSource()` |
| `peerConnectionFactory.createAudioTrack()` | `peerConnectionFactory.createVideoTrack()` |
| 麦克风由 webrtc 内部采集 | `VideoCapture` 采集摄像头，绑定到 `VideoSource` |
| — | `NativeVideoRenderer` 作为 VideoSink 渲染到 XComponent |

不引入 Camera Kit，原因：
- `@ohos/webrtc` 已封装摄像头采集和前/后切换能力（`VideoCapture.switchCamera()`）
- 与现有音频代码风格一致，降低维护负担
- 满足本期"基础控制"需求，无需 Camera Kit 的高级能力

---

## 3. 架构

### 数据流

```
摄像头硬件
  │
  ▼
VideoCapture（@ohos/webrtc）
  │
  ├──► VideoSource ──► VideoTrack ──► publisherPC.addTrack()
  │                                          │
  │                                          ▼
  │                                   LiveKit 服务器（转发给订阅端）
  │
  └──► NativeVideoRenderer（VideoSink）
              │
              ▼
        XComponent（surfaceId）──► 屏幕本地预览
```

### 组件职责

```
UI 层 (entry/pages/Index.ets)
├── XComponent — 提供 surfaceId 给本地预览渲染
├── Button "开启/关闭视频" — 调用 liveKitUtil.publishVideo / unpublishVideo
└── Button "切换摄像头"   — 调用 liveKitUtil.switchCamera

LiveKitUtil.ets（业务层）
├── publishVideo(surfaceId)  — 转发到 client.publishVideo
├── unpublishVideo()         — 转发到 client.unpublishVideo
└── switchCamera()           — 转发到 client.switchCamera

LiveKitClient.ets（SDK 公共 API）
├── publishVideo(surfaceId, options?)
├── unpublishVideo()
└── switchCamera()

RTCEngine.ets（WebRTC 核心，新增视频部分）
├── videoSource: webrtc.VideoSource
├── videoTrack: webrtc.VideoTrack
├── videoCapture: webrtc.VideoCapture
├── localRenderer: webrtc.NativeVideoRenderer
├── publishVideo(surfaceId, options)
│   ├── 1. sendAddTrack(cid, 'video', TrackType.VIDEO, TrackSource.CAMERA)
│   ├── 2. createVideoSource → createVideoTrack
│   ├── 3. VideoCapture.startCapture(videoSource)
│   ├── 4. NativeVideoRenderer.init(surfaceId) — 本地预览
│   └── 5. publisherPC.addTrack(videoTrack) — 触发 negotiation
├── unpublishVideo()
│   ├── 1. VideoCapture.stopCapture
│   ├── 2. NativeVideoRenderer.release
│   └── 3. publisherPC.removeTrack(sender)
└── switchCamera()
    └── videoCapture.switchCamera()
```

---

## 4. 接口设计

### 4.1 新增类型（types.ets）

```typescript
export interface VideoCaptureOptions {
  width?: number       // 采集宽度，默认 1280
  height?: number      // 采集高度，默认 720
  frameRate?: number   // 帧率，默认 30
  facingMode?: 'user' | 'environment'  // 前置/后置，默认 'environment'
}
```

`ConnectOptions` 中已有 `publishVideo?: boolean` 字段，本期不做自动发布视频（避免增加 connect 接口复杂度），调用方在连接后手动调用 `publishVideo`。

### 4.2 RTCEngine 新增方法

```typescript
// 发布视频
async publishVideo(surfaceId: string, options?: VideoCaptureOptions): Promise<void>

// 取消发布视频
async unpublishVideo(): Promise<void>

// 切换摄像头（前/后）
switchCamera(): void
```

### 4.3 LiveKitClient 新增公共 API

```typescript
// 发布本地摄像头视频，surfaceId 来自 XComponent
async publishVideo(surfaceId: string, options?: VideoCaptureOptions): Promise<void>

// 取消发布视频
async unpublishVideo(): Promise<void>

// 切换前/后摄像头
switchCamera(): void
```

---

## 5. 权限声明

在 `entry/src/main/module.json5` 的 `requestPermissions` 中新增：

```json5
{
  "name": "ohos.permission.CAMERA",
  "reason": "$string:permission_camera_reason",
  "usedScene": {
    "abilities": ["EntryAbility"],
    "when": "inuse"
  }
}
```

在 `LiveKitUtil.requestPermissions()` 中同步增加 `ohos.permission.CAMERA` 到请求列表。

---

## 6. UI 变更（Index.ets）

- 新增 `XComponent`（type: `XComponentType.SURFACE`）占据主要屏幕区域，用于本地预览
- 新增两个按钮行：
  - "开启视频" / "关闭视频"（切换状态）
  - "切换摄像头"（仅视频推送中可用）
- XComponent 的 `onLoad` 回调中保存 `surfaceId`，供 `publishVideo` 使用

---

## 7. 涉及文件变更清单

| 文件 | 变更类型 | 说明 |
|---|---|---|
| `LiveKit/src/main/ets/util/types.ets` | 新增 | `VideoCaptureOptions` 接口 |
| `LiveKit/src/main/ets/util/RTCEngine.ets` | 扩展 | 新增视频属性和 3 个方法 |
| `LiveKit/src/main/ets/util/LiveKitClient.ets` | 扩展 | 新增 3 个公共 API + `isVideoPublished` 状态 |
| `LiveKit/Index.ets` | 扩展 | 导出 `VideoCaptureOptions` |
| `entry/src/main/ets/rtc/LiveKitUtil.ets` | 扩展 | 新增视频方法 + 权限请求 |
| `entry/src/main/ets/pages/Index.ets` | 重写 | 新增 XComponent + 视频控制按钮 |
| `entry/src/main/module.json5` | 扩展 | 新增 CAMERA 权限声明 |

---

## 8. 关键实现注意事项

1. **XComponent surfaceId 时序**：`publishVideo` 必须在 XComponent `onLoad` 回调触发后调用，否则 surfaceId 为空字符串。UI 层需保证这一顺序。

2. **NativeVideoRenderer 生命周期**：`unpublishVideo` 时必须先调用 `NativeVideoRenderer.release()`，再调用 `publisherPC.removeTrack()`，顺序不可颠倒，否则可能导致 native 层资源未释放。

3. **VideoCapture.stopCapture 异步性**：`stopCapture` 为异步操作，`unpublishVideo` 需 `await` 等待完成后再执行后续清理。

4. **摄像头权限检查**：`publishVideo` 调用前，业务层需确认已获得 `ohos.permission.CAMERA` 授权，RTCEngine 层不做权限检查（遵循"仅在系统边界校验"原则）。

5. **close() 清理**：`RTCEngine.close()` 中需补充视频资源的释放（`videoCapture`、`videoTrack`、`localRenderer`），与音频资源并列清理。

6. **sendAddTrack 参数**：视频轨道的 `TrackType = 1`（VIDEO），`TrackSource = 1`（CAMERA），与音频的 `0, 2` 区分。
