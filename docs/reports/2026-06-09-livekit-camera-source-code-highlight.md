# 2026-06-09 摄像头闪退修复代码改动高亮报告

本报告对应提交：`212f2f0 fix: avoid Mate X7 camera source crash`。

说明：

- `+` 高亮行：本次新增或修改后的代码。
- `-` 高亮行：本次替换前删除的旧代码。
- 行号以当前提交后的文件为准。

## 1. `LiveKit/oh-package.json5`

### 第 20 行：回退 `@ohos/webrtc` 版本

```diff
-    "@ohos/webrtc": "^1.0.1",
+    "@ohos/webrtc": "^1.0.0",
```

作用：避开 `@ohos/webrtc@1.0.1` 在 Mate X7 上创建本机摄像头 `VideoSource` 时触发 native crash 的路径。

## 2. `LiveKit/oh-package-lock.json5`

### 第 9、22、27-34、129-132 行：锁定 `@ohos/webrtc@1.0.0`

```diff
-    "@ohos/webrtc@^1.0.1": "@ohos/webrtc@1.0.1",
-    "libohos_webrtc.so@../oh_modules/.ohpm/@ohos+webrtc@1.0.1/oh_modules/@ohos/webrtc/src/main/libohos_webrtc": "libohos_webrtc.so@../oh_modules/.ohpm/@ohos+webrtc@1.0.1/oh_modules/@ohos/webrtc/src/main/libohos_webrtc",
+    "@ohos/webrtc@^1.0.0": "@ohos/webrtc@1.0.0",
+    "libohos_webrtc.so@../oh_modules/.ohpm/@ohos+webrtc@1.0.0/oh_modules/@ohos/webrtc/src/main/libohos_webrtc": "libohos_webrtc.so@../oh_modules/.ohpm/@ohos+webrtc@1.0.0/oh_modules/@ohos/webrtc/src/main/libohos_webrtc",

-    "@ohos/webrtc@1.0.1": {
+    "@ohos/webrtc@1.0.0": {
       "name": "@ohos/webrtc",
-      "version": "1.0.1",
-      "resolved": "https://ohpm.openharmony.cn/ohpm/@ohos/webrtc/-/webrtc-1.0.1.har",
+      "version": "1.0.0",
+      "resolved": "https://ohpm.openharmony.cn/ohpm/@ohos/webrtc/-/webrtc-1.0.0.har",
```

作用：确保 `LiveKit` 模块构建时实际使用 `1.0.0` 的 HAR 和 native so。

## 3. `entry/oh-package-lock.json5`

### 第 9、22、28-35、130-133 行：同步锁定入口模块依赖解析

```diff
-    "@ohos/webrtc@^1.0.1": "@ohos/webrtc@1.0.1",
-    "libohos_webrtc.so@../oh_modules/.ohpm/@ohos+webrtc@1.0.1/oh_modules/@ohos/webrtc/src/main/libohos_webrtc": "libohos_webrtc.so@../oh_modules/.ohpm/@ohos+webrtc@1.0.1/oh_modules/@ohos/webrtc/src/main/libohos_webrtc",
+    "@ohos/webrtc@^1.0.0": "@ohos/webrtc@1.0.0",
+    "libohos_webrtc.so@../oh_modules/.ohpm/@ohos+webrtc@1.0.0/oh_modules/@ohos/webrtc/src/main/libohos_webrtc": "libohos_webrtc.so@../oh_modules/.ohpm/@ohos+webrtc@1.0.0/oh_modules/@ohos/webrtc/src/main/libohos_webrtc",

-    "@ohos/webrtc@1.0.1": {
+    "@ohos/webrtc@1.0.0": {
       "name": "@ohos/webrtc",
-      "version": "1.0.1",
-      "resolved": "https://ohpm.openharmony.cn/ohpm/@ohos/webrtc/-/webrtc-1.0.1.har",
+      "version": "1.0.0",
+      "resolved": "https://ohpm.openharmony.cn/ohpm/@ohos/webrtc/-/webrtc-1.0.0.har",
```

作用：入口模块最终打包时也解析到 `@ohos/webrtc@1.0.0`，避免 `entry` 和 `LiveKit` 锁文件不一致。

## 4. `LiveKit/src/main/ets/koophone/KooUserMedia.ets`

### 第 29-43 行：新增共享摄像头轨道状态

```diff
+interface SharedCameraCapture {
+  track: webrtc.VideoTrack
+  source: webrtc.VideoSource | null
+  users: number
+}
+
 export class KooUserMedia {
+  private static sharedCameraCapture: SharedCameraCapture | null = null
+
   private videoSource: webrtc.VideoSource | null = null
   private videoTrack: webrtc.VideoTrack | null = null
+  private retainedSharedTrack: webrtc.VideoTrack | null = null
```

作用：新增一个全局共享摄像头 track 容器，让 KooPhone 摄像头上行和 LiveKit 本机推流可以共用同一个 camera track。

### 第 59-119 行：新增共享 track 获取、注册、引用计数和释放方法

```diff
+  /**
+   * 返回当前已经打开的本地摄像头轨道。
+   * KooPhone 和 LiveKit 推流共用这一条 track，避免 @ohos/webrtc 同时打开两路摄像头采集。
+   */
+  static getSharedVideoTrack(): webrtc.VideoTrack | null {
+    const capture = KooUserMedia.sharedCameraCapture
+    if (!capture) {
+      return null
+    }
+    if (capture.track.readyState === 'ended') {
+      KooUserMedia.sharedCameraCapture = null
+      return null
+    }
+    return capture.track
+  }
+
+  /**
+   * 将新创建的摄像头轨道注册为全局共享轨道。
+   */
+  static registerSharedVideoTrack(track: webrtc.VideoTrack, source: webrtc.VideoSource | null): void {
+    KooUserMedia.sharedCameraCapture = {
+      track,
+      source,
+      users: 0
+    }
+  }
+
+  /**
+   * 增加共享摄像头轨道使用计数。
+   */
+  static retainSharedVideoTrack(track: webrtc.VideoTrack): boolean {
+    const capture = KooUserMedia.sharedCameraCapture
+    if (!capture || capture.track !== track || track.readyState === 'ended') {
+      return false
+    }
+    capture.users += 1
+    return true
+  }
+
+  /**
+   * 减少共享摄像头轨道使用计数。最后一个使用方释放时才真正关闭摄像头。
+   */
+  static releaseSharedVideoTrack(track: webrtc.VideoTrack): void {
+    const capture = KooUserMedia.sharedCameraCapture
+    if (!capture || capture.track !== track) {
+      return
+    }
+    capture.users = Math.max(0, capture.users - 1)
+    if (capture.users > 0) {
+      return
+    }
+
+    try {
+      capture.track.stop()
+      console.info('[KooUserMedia] Shared camera released')
+    } catch (error) {
+      console.error('[KooUserMedia] release shared camera failed:', String(error))
+    } finally {
+      KooUserMedia.sharedCameraCapture = null
+    }
+  }
```

作用：避免重复打开摄像头；最后一个使用方退出时才真正关闭摄像头。

### 第 151-169 行：`openCamera()` 优先复用共享 track，并移除 `facingMode` 约束

```diff
+      const sharedTrack = KooUserMedia.getSharedVideoTrack()
+      if (sharedTrack && KooUserMedia.retainSharedVideoTrack(sharedTrack)) {
+        this.videoTrack = sharedTrack
+        this.videoSource = null
+        this.retainedSharedTrack = sharedTrack
+        this.cameraId = cameraId
+        this.cameraOn = true
+        this.cameraOpening = false
+        console.info('[KooUserMedia] Reusing shared camera track:', sharedTrack.id)
+        this.onSuccess?.('start', 'video', this.videoTrack)
+        return true
+      }
+
       // facingMode: 前摄='user', 后摄='environment'（对应 H5 facingMode 约束）
       const facingMode = cameraId === 1 ? 'user' : 'environment'
 
-      const constraints: webrtc.MediaTrackConstraints = {
-        width: width,
-        height: height,
-        frameRate: fps,
-        facingMode: facingMode
-      }
+      // @ohos/webrtc 1.0.1 在 Mate X7 上直接传 facingMode 容易进入 native 相机方向查询崩溃路径。
+      // 这里只传 README 示例中的基础约束，cameraId/facingMode 仅保留为业务状态。
+      const constraints: webrtc.MediaTrackConstraints = this.buildVideoConstraints(width, height, fps)
```

作用：如果 LiveKit 推流已经打开摄像头，KooPhone 不再重复打开；同时不再传可能触发崩溃路径的 `facingMode`。

### 第 182-187 行：新建 track 后注册为共享 track

```diff
       // 创建视频轨道
       const trackId = 'camera_' + cameraId
       this.videoTrack = this.pcf.createVideoTrack(trackId, this.videoSource)
+      KooUserMedia.registerSharedVideoTrack(this.videoTrack, this.videoSource)
+      KooUserMedia.retainSharedVideoTrack(this.videoTrack)
+      this.retainedSharedTrack = this.videoTrack
```

作用：让后续 LiveKit 推流可以直接复用 KooPhone 已经创建好的摄像头 track。

### 第 238-260 行：`stopCamera()` 改为释放共享引用，并新增基础约束构造方法

```diff
   private async stopCamera(): Promise<void> {
-    if (this.videoTrack) {
-      this.videoTrack.stop()
-      this.videoTrack = null
-    }
-    if (this.videoSource) {
-      this.videoSource.release()
-      this.videoSource = null
+    if (this.retainedSharedTrack) {
+      KooUserMedia.releaseSharedVideoTrack(this.retainedSharedTrack)
     }
+    this.retainedSharedTrack = null
+    this.videoTrack = null
+    this.videoSource = null
     this.cameraOn = false
     this.cameraId = -1
     this.cameraOpening = false
     console.info('[KooUserMedia] Camera stopped')
   }
+
+  private buildVideoConstraints(width: number, height: number, fps: number): webrtc.MediaTrackConstraints {
+    const safeFps = Math.max(1, Math.floor(fps))
+    return {
+      width: Math.max(1, Math.floor(width)),
+      height: Math.max(1, Math.floor(height)),
+      frameRate: {
+        min: safeFps,
+        max: Math.max(safeFps, 30)
+      }
+    }
+  }
```

作用：不再调用 `VideoSource.release()`；`@ohos/webrtc@1.0.0` 类型没有该方法，释放动作交给 `track.stop()` 和引用计数处理。

## 5. `LiveKit/src/main/ets/util/RTCEngine.ets`

### 第 20 行：引入 `KooUserMedia`

```diff
 import webrtc from '@ohos/webrtc'
+import { KooUserMedia } from '../koophone/KooUserMedia'
```

作用：LiveKit 推流侧可以访问 SDK 内统一的共享摄像头 track。

### 第 73-78 行：新增当前模块持有的共享 track 引用

```diff
   private videoSource: webrtc.VideoSource | null = null
   private videoTrack: webrtc.VideoTrack | null = null
   private localRenderer: webrtc.NativeVideoRenderer | null = null
+  private retainedSharedVideoTrack: webrtc.VideoTrack | null = null
   private currentFacingMode: string = 'environment'
```

作用：记录 `RTCEngine` 是否持有共享 track，便于关闭推流时正确释放引用。

### 第 233-287 行：重写 `publishVideo()` 的摄像头创建逻辑

```diff
   async publishVideo(surfaceId: string, options?: VideoCaptureOptions): Promise<void> {
     if (!this.peerConnectionFactory || !this.publisherPC) {
       throw new Error('PeerConnectionFactory not initialized')
     }
+    if (this.videoTrack) {
+      console.warn('[RTCEngine] Video already published')
+      return
+    }
 
     try {
-      const width = options?.width ?? 1280
-      const height = options?.height ?? 720
-      const frameRate = options?.frameRate ?? 30
-      const facingMode = options?.facingMode ?? 'environment'
+      const width = options?.width ?? 640
+      const height = options?.height ?? 480
+      const frameRate = options?.frameRate ?? 15
+      const facingMode = options?.facingMode ?? 'user'
       this.currentFacingMode = facingMode
 
-      const trackId = `video_${Date.now()}`
+      const sharedTrack = KooUserMedia.getSharedVideoTrack()
+      if (sharedTrack && KooUserMedia.retainSharedVideoTrack(sharedTrack)) {
+        this.videoTrack = sharedTrack
+        this.videoSource = null
+        this.retainedSharedVideoTrack = sharedTrack
+        console.info('[RTCEngine] Reusing shared camera track:', sharedTrack.id)
+      } else {
+        // 创建 VideoSource 时只传基础采集约束，避免触发 Mate X7 上的相机方向查询崩溃路径。
+        // 如果 KooPhone 已经打开摄像头，上面的 sharedTrack 分支会直接复用，避免同时打开两路相机。
+        const constraints: webrtc.MediaTrackConstraints = this.buildVideoConstraints(width, height, frameRate)
+        this.videoSource = this.peerConnectionFactory.createVideoSource(constraints)
+        const localTrackId = `video_${Date.now()}`
+        this.videoTrack = this.peerConnectionFactory.createVideoTrack(localTrackId, this.videoSource)
+        KooUserMedia.registerSharedVideoTrack(this.videoTrack, this.videoSource)
+        KooUserMedia.retainSharedVideoTrack(this.videoTrack)
+        this.retainedSharedVideoTrack = this.videoTrack
+        console.info('[RTCEngine] VideoSource created, capturing started')
+      }
+
+      const trackId = this.videoTrack.id
       this.signalClient.sendAddTrack(trackId, 'video', 1, 1)
       console.info('[RTCEngine] Sent AddTrackRequest for video:', trackId)
 
-      const constraints: webrtc.MediaTrackConstraints = {
-        width: width,
-        height: height,
-        frameRate: frameRate,
-        facingMode: facingMode
-      }
-      this.videoSource = this.peerConnectionFactory.createVideoSource(constraints, false)
-      console.info('[RTCEngine] VideoSource created, capturing started')
-
-      this.videoTrack = this.peerConnectionFactory.createVideoTrack(trackId, this.videoSource)
-
       this.localRenderer = new webrtc.NativeVideoRenderer()
       this.localRenderer.init(surfaceId)
       this.localRenderer.setVideoTrack(this.videoTrack)
       console.info('[RTCEngine] NativeVideoRenderer initialized for surfaceId:', surfaceId)
 
       this.publisherPC.addTrack(this.videoTrack)
       console.info('[RTCEngine] Video track added:', trackId)
 
     } catch (error) {
+      this.releaseRetainedVideoTrack()
       console.error('[RTCEngine] Publish video failed:', error)
       throw new Error(String(error))
     }
```

作用：

- 避免重复点击导致重复发布。
- 优先复用 KooPhone 已创建的摄像头 track。
- 不再传 `facingMode` 和第二个布尔参数给 `createVideoSource()`。
- 默认采集降到 `640x480@15fps`，降低 Mate X7 上相机初始化压力。

### 第 293-320 行：`unpublishVideo()` 改为释放共享 track 引用

```diff
-      // 2. 停止视频轨道，释放摄像头采集资源
-      if (this.videoTrack) {
-        this.videoTrack.stop()
-      }
-      if (this.videoSource) {
-        this.videoSource.release()
-        this.videoSource = null
-        console.info('[RTCEngine] VideoSource released')
-      }
-
-      // 3. 从 PeerConnection 移除视频轨道（触发重新协商）
+      // 2. 从 PeerConnection 移除视频轨道（触发重新协商）
       if (this.publisherPC && this.videoTrack) {
         const senders = this.publisherPC.getSenders()
         for (let i = 0; i < senders.length; i++) {
           if (senders[i].track === this.videoTrack) {
             this.publisherPC.removeTrack(senders[i])
             break
           }
         }
       }
 
-      this.videoTrack = null
+      // 3. 释放本模块对共享摄像头 track 的引用。最后一个使用方释放时才真正关闭摄像头。
+      this.releaseRetainedVideoTrack()
       console.info('[RTCEngine] Video unpublished')
```

作用：关闭本机推流时不直接抢关摄像头，避免影响 KooPhone 侧仍在使用的共享 track。

### 第 327-339 行：暂时禁用重建 `VideoSource` 的切摄像头实现

```diff
-   * 切换前/后摄像头：重建 VideoSource（新 facingMode）+ replaceTrack
+   * 切换前/后摄像头。
+   * @ohos/webrtc 1.0.1 在 Mate X7 上重建 VideoSource 会进入 native 相机崩溃路径，
+   * 这里先不再创建第二个摄像头源，等 SDK 确认安全的 cameraId/deviceId 选择方式后再恢复。
    */
   async switchCamera(): Promise<void> {
     if (!this.publisherPC || !this.peerConnectionFactory || !this.videoTrack) {
       console.warn('[RTCEngine] switchCamera called but video not published')
       return
     }
 
-    const newFacingMode = this.currentFacingMode === 'environment' ? 'user' : 'environment'
-    ...
-    console.info('[RTCEngine] Camera switched to:', newFacingMode)
+    console.warn('[RTCEngine] switchCamera skipped: @ohos/webrtc 1.0.1 camera source is not safe to recreate on Mate X7')
   }
```

作用：当前先保住“开始直播推流不闪退”。切摄像头后续需要 SDK 确认安全的 cameraId/deviceId 或 replaceTrack 方案后再打开。

### 第 358-366 行：`close()` 释放视频时改用共享释放方法

```diff
     if (this.videoTrack) {
-      this.videoTrack.stop()
-      this.videoTrack = null
-    }
-    if (this.videoSource) {
-      this.videoSource.release()
-      this.videoSource = null
+      this.releaseRetainedVideoTrack()
     }
```

作用：关闭 RTCEngine 时统一走共享 track 引用计数释放。

### 第 877-898 行：新增视频释放和基础约束构造方法

```diff
+  private releaseRetainedVideoTrack(): void {
+    if (this.retainedSharedVideoTrack) {
+      KooUserMedia.releaseSharedVideoTrack(this.retainedSharedVideoTrack)
+    } else if (this.videoTrack) {
+      this.videoTrack.stop()
+    }
+    this.retainedSharedVideoTrack = null
+    this.videoTrack = null
+    this.videoSource = null
+  }
+
+  private buildVideoConstraints(width: number, height: number, frameRate: number): webrtc.MediaTrackConstraints {
+    const safeFrameRate = Math.max(1, Math.floor(frameRate))
+    return {
+      width: Math.max(1, Math.floor(width)),
+      height: Math.max(1, Math.floor(height)),
+      frameRate: {
+        min: safeFrameRate,
+        max: Math.max(safeFrameRate, 30)
+      }
+    }
+  }
```

作用：

- `releaseRetainedVideoTrack()`：统一释放 RTCEngine 持有的视频 track。
- `buildVideoConstraints()`：统一生成不含 `facingMode` 的基础约束。

## 6. 验证结论

本次改动验证通过：

```bash
git diff --check
ohpm install --all
hvigorw test --no-daemon --stacktrace -p properties.enableSignTask=false
hvigorw clean assembleHap --no-daemon --stacktrace -p properties.enableSignTask=false
```

真机 Mate X7 验证结果：

- 进入淘宝 KooPhone 云机直播后，点击“开始直播推流”不再闪退。
- 本机摄像头预览正常出现。
- 等待超过 12 秒后没有新增 `cppcrash-com.hssw.livekit-*`。
