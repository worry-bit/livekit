# 视频推送功能实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在现有音频推送基础上，新增摄像头视频采集、本地预览、前/后摄像头切换、开启/关闭视频推送功能，全部通过 `@ohos/webrtc` 原生管道实现。

**Architecture:** `VideoCapture` 采集摄像头帧注入 `VideoSource`，`VideoTrack` 通过 `publisherPC.addTrack()` 发布到 LiveKit 服务器；`NativeVideoRenderer` 作为 VideoSink 将同一帧渲染到 UI 层的 `XComponent`（surfaceId）实现本地预览。所有视频逻辑与现有音频逻辑并列在 `RTCEngine` 中，公共 API 由 `LiveKitClient` 暴露，UI 通过 `LiveKitUtil` 调用。

**Tech Stack:** HarmonyOS ArkTS、`@ohos/webrtc`（VideoCapture / VideoSource / VideoTrack / NativeVideoRenderer）、ArkUI XComponent

---

## 文件变更地图

| 文件 | 操作 | 职责 |
|---|---|---|
| `LiveKit/src/main/ets/util/types.ets` | 扩展 | 新增 `VideoCaptureOptions` 接口 |
| `LiveKit/src/main/ets/util/RTCEngine.ets` | 扩展 | 新增视频属性 + `publishVideo` / `unpublishVideo` / `switchCamera` + `close()` 补充清理 |
| `LiveKit/src/main/ets/util/LiveKitClient.ets` | 扩展 | 新增 `isVideoPublished` 状态 + `publishVideo` / `unpublishVideo` / `switchCamera` 公共 API |
| `LiveKit/Index.ets` | 扩展 | 导出 `VideoCaptureOptions` |
| `entry/src/main/resources/base/element/string.json` | 扩展 | 新增 `permission_camera_reason` 字符串资源 |
| `entry/src/main/module.json5` | 扩展 | 新增 `ohos.permission.CAMERA` 权限声明 |
| `entry/src/main/ets/rtc/LiveKitUtil.ets` | 扩展 | 新增 `publishVideo` / `unpublishVideo` / `switchCamera` + CAMERA 权限请求 |
| `entry/src/main/ets/pages/Index.ets` | 重写 | 新增 XComponent 本地预览 + 视频控制按钮 |

---

## Task 1：新增 VideoCaptureOptions 类型并导出

**Files:**
- Modify: `LiveKit/src/main/ets/util/types.ets`
- Modify: `LiveKit/Index.ets`

- [ ] **Step 1：在 types.ets 末尾追加 VideoCaptureOptions 接口**

在文件末尾 `AudioFrame` 接口之后追加：

```typescript
// ==================== 视频采集选项 ====================

export interface VideoCaptureOptions {
  width?: number      // 采集宽度，默认 1280
  height?: number     // 采集高度，默认 720
  frameRate?: number  // 帧率，默认 30
  facingMode?: 'user' | 'environment'  // 前置/后置，默认 'environment'
}
```

- [ ] **Step 2：在 LiveKit/Index.ets 导出新类型**

在现有 `ConnectOptions, AudioCaptureOptions` 导出行后追加 `VideoCaptureOptions`，完整导出块变为：

```typescript
export {
  RoomState,
  ParticipantInfo,
  ParticipantState,
  TrackInfo,
  TrackType,
  TrackSource,
  RoomInfo,
  ConnectOptions,
  AudioCaptureOptions,
  VideoCaptureOptions,
  ConnectionQuality,
  DisconnectReason,
  SpeakerInfo
} from './src/main/ets/util/types'
```

- [ ] **Step 3：提交**

```bash
git add LiveKit/src/main/ets/util/types.ets LiveKit/Index.ets
git commit -m "feat: add VideoCaptureOptions type and export"
```

---

## Task 2：RTCEngine 新增视频属性与 publishVideo 方法

**Files:**
- Modify: `LiveKit/src/main/ets/util/RTCEngine.ets`

> 背景：`@ohos/webrtc` 的 `PeerConnectionFactory` 提供 `createVideoSource(isScreenCast: boolean): VideoSource`、`createVideoTrack(id: string, source: VideoSource): VideoTrack`。`VideoCapture` 负责摄像头采集，`NativeVideoRenderer` 负责将视频帧渲染到指定 surfaceId。

- [ ] **Step 1：在 RTCEngine 类的 import 区新增 VideoCaptureOptions 导入**

在 `RTCEngine.ets` 顶部的 import 列表中，将 `VideoCaptureOptions` 加入从 `./types` 的导入：

```typescript
import {
  SessionDescription,
  TrickleRequest,
  ICEServer,
  SignalTarget,
  AudioCaptureOptions,
  VideoCaptureOptions
} from './types'
```

- [ ] **Step 2：在 RTCEngine 类中新增视频成员变量**

在现有 `// 音频路由` 属性块下方追加：

```typescript
  // 本地视频
  private videoSource: webrtc.VideoSource | null = null
  private videoTrack: webrtc.VideoTrack | null = null
  private videoCapture: webrtc.VideoCapture | null = null
  private localRenderer: webrtc.NativeVideoRenderer | null = null
```

- [ ] **Step 3：新增 publishVideo 方法**

在 `unpublishAudio()` 方法之后插入：

```typescript
  /**
   * 发布视频（摄像头采集 + 本地预览）
   * @param surfaceId 来自 XComponent.onLoad 的 surfaceId，用于本地预览渲染
   * @param options 采集参数，默认 1280x720@30fps 后置摄像头
   */
  async publishVideo(surfaceId: string, options?: VideoCaptureOptions): Promise<void> {
    if (!this.peerConnectionFactory || !this.publisherPC) {
      throw new Error('PeerConnectionFactory not initialized')
    }

    try {
      const width = options?.width ?? 1280
      const height = options?.height ?? 720
      const frameRate = options?.frameRate ?? 30
      const facingMode = options?.facingMode ?? 'environment'

      // 1. 通知服务器即将发布视频轨道（TrackType.VIDEO=1, TrackSource.CAMERA=1）
      const trackId = `video_${Date.now()}`
      this.signalClient.sendAddTrack(trackId, 'video', 1, 1)
      console.info('[RTCEngine] Sent AddTrackRequest for video:', trackId)

      // 2. 创建 VideoSource（非屏幕录制）
      this.videoSource = this.peerConnectionFactory.createVideoSource(false)

      // 3. 创建 VideoTrack
      this.videoTrack = this.peerConnectionFactory.createVideoTrack(trackId, this.videoSource)

      // 4. 创建 VideoCapture 并开始采集
      this.videoCapture = new webrtc.VideoCapture(this.videoSource)
      const constraints: webrtc.MediaTrackConstraints = {
        width: width,
        height: height,
        frameRate: frameRate,
        facingMode: facingMode
      }
      await this.videoCapture.startCapture(constraints)
      console.info('[RTCEngine] VideoCapture started')

      // 5. 创建本地渲染器，将摄像头画面渲染到 XComponent
      this.localRenderer = new webrtc.NativeVideoRenderer()
      this.localRenderer.init(surfaceId)
      this.videoSource.addSink(this.localRenderer)
      console.info('[RTCEngine] NativeVideoRenderer initialized for surfaceId:', surfaceId)

      // 6. 将视频轨道添加到发布者 PeerConnection，触发 onnegotiationneeded
      this.publisherPC.addTrack(this.videoTrack)
      console.info('[RTCEngine] Video track added:', trackId)

    } catch (error) {
      console.error('[RTCEngine] Publish video failed:', error)
    }
  }
```

- [ ] **Step 4：新增 unpublishVideo 方法**

在 `publishVideo` 方法之后插入：

```typescript
  /**
   * 取消发布视频，释放摄像头和渲染器资源
   */
  async unpublishVideo(): Promise<void> {
    if (!this.publisherPC || !this.videoTrack) {
      return
    }

    try {
      // 1. 停止摄像头采集
      if (this.videoCapture) {
        await this.videoCapture.stopCapture()
        this.videoCapture = null
        console.info('[RTCEngine] VideoCapture stopped')
      }

      // 2. 释放本地渲染器（必须在 removeTrack 之前）
      if (this.localRenderer && this.videoSource) {
        this.videoSource.removeSink(this.localRenderer)
        this.localRenderer.release()
        this.localRenderer = null
        console.info('[RTCEngine] NativeVideoRenderer released')
      }

      // 3. 从 PeerConnection 移除视频轨道（触发重新协商）
      const senders = this.publisherPC.getSenders()
      for (let i = 0; i < senders.length; i++) {
        if (senders[i].track === this.videoTrack) {
          this.publisherPC.removeTrack(senders[i])
          break
        }
      }

      this.videoTrack = null
      this.videoSource = null
      console.info('[RTCEngine] Video unpublished')

    } catch (error) {
      console.error('[RTCEngine] Unpublish video failed:', error)
    }
  }
```

- [ ] **Step 5：新增 switchCamera 方法**

在 `unpublishVideo` 方法之后插入：

```typescript
  /**
   * 切换前/后摄像头（仅在视频发布中有效）
   */
  switchCamera(): void {
    if (!this.videoCapture) {
      console.warn('[RTCEngine] switchCamera called but no active VideoCapture')
      return
    }
    this.videoCapture.switchCamera()
    console.info('[RTCEngine] Camera switched')
  }
```

- [ ] **Step 6：在 close() 方法中补充视频资源清理**

找到 `close()` 方法中 `// 停止音频` 注释块，在其上方追加视频清理代码：

```typescript
    // 停止视频
    if (this.videoCapture) {
      this.videoCapture.stopCapture()
      this.videoCapture = null
    }
    if (this.localRenderer && this.videoSource) {
      this.videoSource.removeSink(this.localRenderer)
      this.localRenderer.release()
      this.localRenderer = null
    }
    if (this.videoTrack) {
      this.videoTrack = null
    }
    this.videoSource = null
```

- [ ] **Step 7：提交**

```bash
git add LiveKit/src/main/ets/util/RTCEngine.ets
git commit -m "feat: add video publish/unpublish/switchCamera to RTCEngine"
```

---

## Task 3：LiveKitClient 新增视频公共 API

**Files:**
- Modify: `LiveKit/src/main/ets/util/LiveKitClient.ets`

- [ ] **Step 1：新增 VideoCaptureOptions import 和 isVideoPublished 状态**

在 `LiveKitClient.ets` 顶部 import 的 types 导入中加入 `VideoCaptureOptions`：

```typescript
import {
  RoomState,
  RoomInfo,
  ParticipantInfo,
  ConnectOptions,
  AudioCaptureOptions,
  VideoCaptureOptions,
  RoomEventType,
  AudioLevelInfo,
  AudioLevelCallback,
  AudioLevelObserverOptions
} from './types'
```

在 `LiveKitClient` 类的 `// 音频状态` 属性块下方追加：

```typescript
  // 视频状态
  private isVideoPublished: boolean = false
```

- [ ] **Step 2：新增 publishVideo 公共方法**

在 `unpublishAudio()` 方法之后插入：

```typescript
  /**
   * 发布本地摄像头视频
   * @param surfaceId 来自 XComponent.onLoad 的 surfaceId，用于本地预览
   * @param options 采集参数（可选）
   */
  async publishVideo(surfaceId: string, options?: VideoCaptureOptions): Promise<void> {
    if (!this.isConnected) {
      throw new Error('Not connected to room')
    }

    if (this.isVideoPublished) {
      console.warn('[LiveKitClient] Video already published')
      return
    }

    try {
      await this.rtcEngine.publishVideo(surfaceId, options)
      this.isVideoPublished = true

      console.info('[LiveKitClient] Video published')
      this.emit('trackPublished', { kind: 'video' })

    } catch (error) {
      console.error('[LiveKitClient] Publish video failed:', error)
    }
  }
```

- [ ] **Step 3：新增 unpublishVideo 公共方法**

在 `publishVideo` 方法之后插入：

```typescript
  /**
   * 取消发布本地视频
   */
  async unpublishVideo(): Promise<void> {
    if (!this.isVideoPublished) {
      return
    }

    try {
      await this.rtcEngine.unpublishVideo()
      this.isVideoPublished = false

      console.info('[LiveKitClient] Video unpublished')
      this.emit('trackUnpublished', { kind: 'video' })

    } catch (error) {
      console.error('[LiveKitClient] Unpublish video failed:', error)
    }
  }
```

- [ ] **Step 4：新增 switchCamera 公共方法**

在 `unpublishVideo` 方法之后插入：

```typescript
  /**
   * 切换前/后摄像头
   */
  switchCamera(): void {
    this.rtcEngine.switchCamera()
  }
```

- [ ] **Step 5：在 disconnect() 中补充视频取消发布**

找到 `disconnect()` 方法中 `// 1. 取消发布音频` 块，在其下方追加：

```typescript
      // 2. 取消发布视频
      if (this.isVideoPublished) {
        await this.unpublishVideo()
      }
```

注意：原有的后续注释编号相应调整（`// 2. 发送离开信令` → `// 3.`，以此类推）。

- [ ] **Step 6：提交**

```bash
git add LiveKit/src/main/ets/util/LiveKitClient.ets
git commit -m "feat: add publishVideo/unpublishVideo/switchCamera to LiveKitClient"
```

---

## Task 4：权限声明与字符串资源

**Files:**
- Modify: `entry/src/main/resources/base/element/string.json`
- Modify: `entry/src/main/module.json5`

- [ ] **Step 1：在 string.json 追加摄像头权限说明字符串**

在 `Audio_reason` 条目之后追加：

```json
{
  "name": "permission_camera_reason",
  "value": "需要使用摄像头进行视频通话"
}
```

完整文件变为：

```json
{
  "string": [
    {
      "name": "module_desc",
      "value": "module description"
    },
    {
      "name": "EntryAbility_desc",
      "value": "description"
    },
    {
      "name": "EntryAbility_label",
      "value": "label"
    },
    {
      "name": "Internet_reason",
      "value": "访问用户网络"
    },
    {
      "name": "Audio_reason",
      "value": "需要录制音频"
    },
    {
      "name": "permission_camera_reason",
      "value": "需要使用摄像头进行视频通话"
    }
  ]
}
```

- [ ] **Step 2：在 module.json5 的 requestPermissions 数组中追加 CAMERA 权限**

在 `ohos.permission.MICROPHONE` 条目之后追加（保持与现有格式一致）：

```json5
// 访问摄像头的权限
{
  "name": "ohos.permission.CAMERA",
  "reason": "$string:permission_camera_reason",
  "usedScene": {
    "abilities": [
      "EntryAbility"
    ],
    "when": "inuse"
  }
}
```

- [ ] **Step 3：提交**

```bash
git add entry/src/main/resources/base/element/string.json entry/src/main/module.json5
git commit -m "feat: add CAMERA permission declaration"
```

---

## Task 5：LiveKitUtil 新增视频业务方法

**Files:**
- Modify: `entry/src/main/ets/rtc/LiveKitUtil.ets`

- [ ] **Step 1：新增 videoCaptureOptions 导入**

在现有 `import { AudioLevelInfo, createLiveKitClient, LiveKitClient } from "livekit-harmony"` 行中加入 `VideoCaptureOptions`：

```typescript
import { AudioLevelInfo, VideoCaptureOptions, createLiveKitClient, LiveKitClient } from "livekit-harmony"
```

- [ ] **Step 2：新增视频状态属性**

在 `LiveKitUtil` 类的 `participantCount: number = 0` 之后追加：

```typescript
  isVideoPublished: boolean = false
  localVideoSurfaceId: string = ''
```

- [ ] **Step 3：新增 publishVideo 方法**

在 `toggleMute()` 方法之后插入：

```typescript
  /**
   * 发布本地摄像头视频
   * @param surfaceId 来自 XComponent.onLoad，必须非空
   */
  async publishVideo(surfaceId: string): Promise<void> {
    if (!surfaceId) {
      console.warn('[LiveKitUtil] publishVideo called with empty surfaceId')
      return
    }
    this.localVideoSurfaceId = surfaceId
    try {
      await this.client.publishVideo(surfaceId)
      this.isVideoPublished = true
    } catch (error) {
      console.error('[LiveKitUtil] publishVideo failed:', error)
    }
  }

  /**
   * 取消发布视频
   */
  async unpublishVideo(): Promise<void> {
    try {
      await this.client.unpublishVideo()
      this.isVideoPublished = false
    } catch (error) {
      console.error('[LiveKitUtil] unpublishVideo failed:', error)
    }
  }

  /**
   * 切换前/后摄像头
   */
  switchCamera(): void {
    this.client.switchCamera()
  }
```

- [ ] **Step 4：在 requestPermissions 中加入 CAMERA**

将 `requestPermissionsFromUser` 调用的权限数组由：

```typescript
['ohos.permission.MICROPHONE']
```

改为：

```typescript
['ohos.permission.MICROPHONE', 'ohos.permission.CAMERA']
```

同时将错误提示文案改为：

```typescript
this.errorMessage = '需要麦克风和摄像头权限才能进行视频通话'
```

- [ ] **Step 5：提交**

```bash
git add entry/src/main/ets/rtc/LiveKitUtil.ets
git commit -m "feat: add video methods and CAMERA permission request to LiveKitUtil"
```

---

## Task 6：UI 层新增本地预览与视频控制

**Files:**
- Modify: `entry/src/main/ets/pages/Index.ets`

> 设计要点：
> - `XComponent` 类型为 `XComponentType.SURFACE`，`onLoad` 时保存 `surfaceId`
> - "开启视频" 按钮在 XComponent surfaceId 就绪后才有效（由 `xComponentReady` 状态控制）
> - "切换摄像头" 按钮仅在 `isVideoPublished` 为 true 时可交互

- [ ] **Step 1：重写 Index.ets**

完整替换为：

```typescript
import liveKitUtil from '../rtc/LiveKitUtil'

@Entry
@Component
struct Index {
  @State xComponentReady: boolean = false
  @State isVideoPublished: boolean = false
  private xComponentCtrl: XComponentController = new XComponentController()
  private surfaceId: string = ''

  build() {
    Column() {
      // 本地摄像头预览区域
      XComponent({
        type: XComponentType.SURFACE,
        controller: this.xComponentCtrl
      })
        .width('100%')
        .aspectRatio(9 / 16)
        .backgroundColor(Color.Black)
        .onLoad(() => {
          this.surfaceId = this.xComponentCtrl.getXComponentSurfaceId()
          this.xComponentReady = true
          console.info('[Index] XComponent loaded, surfaceId:', this.surfaceId)
        })
        .onDestroy(() => {
          this.xComponentReady = false
          this.surfaceId = ''
        })

      // 连接控制行
      Row({ space: 12 }) {
        Button('获取权限')
          .onClick(() => {
            liveKitUtil.requestPermissions()
          })
        Button('加入房间')
          .onClick(() => {
            const token = 'your-token'
            const url = 'your-wss'
            liveKitUtil.joinRoom(url, token)
          })
        Button('退出房间')
          .onClick(() => {
            liveKitUtil.leaveRoom()
            this.isVideoPublished = false
          })
      }
      .padding({ top: 12 })

      // 视频控制行
      Row({ space: 12 }) {
        Button(this.isVideoPublished ? '关闭视频' : '开启视频')
          .enabled(this.xComponentReady)
          .onClick(async () => {
            if (this.isVideoPublished) {
              await liveKitUtil.unpublishVideo()
              this.isVideoPublished = false
            } else {
              await liveKitUtil.publishVideo(this.surfaceId)
              this.isVideoPublished = liveKitUtil.isVideoPublished
            }
          })

        Button('切换摄像头')
          .enabled(this.isVideoPublished)
          .onClick(() => {
            liveKitUtil.switchCamera()
          })
      }
      .padding({ top: 12 })
    }
    .height('100%')
    .width('100%')
    .padding(16)
  }
}
```

- [ ] **Step 2：提交**

```bash
git add entry/src/main/ets/pages/Index.ets
git commit -m "feat: add XComponent preview and video control buttons to Index"
```

---

## Task 7：端到端验证

这一步在真实设备或 DevEco 模拟器上手动验证，编译工具链无法替代。

- [ ] **Step 1：编译检查**

```bash
hvigorw assembleDebug
```

预期：BUILD SUCCESSFUL，无 ArkTS 编译错误。

- [ ] **Step 2：安装并运行**

通过 DevEco Studio 安装到测试设备，或：

```bash
hdc app install entry/build/default/outputs/default/entry-default-unsigned.hap
```

- [ ] **Step 3：验证权限弹窗**

点击"获取权限"，预期弹出麦克风 + 摄像头双权限授权弹窗，授权后不再弹出。

- [ ] **Step 4：验证本地预览**

点击"加入房间"完成连接（确保 token/url 已填入），点击"开启视频"，预期：
- XComponent 区域显示摄像头画面
- 按钮文字变为"关闭视频"
- "切换摄像头"按钮变为可点击状态

- [ ] **Step 5：验证摄像头切换**

点击"切换摄像头"，预期预览画面切换为前置（或后置）摄像头。

- [ ] **Step 6：验证关闭视频**

点击"关闭视频"，预期：
- XComponent 区域变黑（停止渲染）
- 按钮文字变回"开启视频"
- "切换摄像头"按钮变为不可点击状态

- [ ] **Step 7：验证退出房间资源释放**

在视频发布状态下点击"退出房间"，预期：
- 无崩溃
- 摄像头指示灯熄灭（摄像头资源已释放）
- 再次加入并开启视频时正常工作

- [ ] **Step 8：最终提交**

```bash
git add .
git commit -m "feat: video publish complete - camera capture, local preview, switch camera"
```
