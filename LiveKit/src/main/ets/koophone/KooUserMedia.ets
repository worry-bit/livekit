/**
 * KooUserMedia — 鸿蒙相机采集模块
 *
 * 对应 H5 UserMedia.js：管理本地摄像头开启/关闭，成功后回调 MediaStreamTrack
 * 供 KooRTCSource 通过 addTrack() 发送给云端。
 *
 * 实现方式：
 *   使用 @ohos/webrtc 的 PeerConnectionFactory API：
 *     pcf.createVideoSource(constraints) → VideoSource
 *     pcf.createVideoTrack(id, source)   → VideoTrack（MediaStreamTrack 子类）
 *
 *   facingMode 约束：'user'=前摄, 'environment'=后摄（与 H5 facingMode 一致）
 *   @ohos/webrtc 内部负责相机采集，无需手动操作 Camera Kit。
 */

import webrtc from '@ohos/webrtc'
import { common } from '@kit.AbilityKit'

export type UserMediaSuccessCallback = (action: string, type: string, track: webrtc.MediaStreamTrack | null) => void
export type UserMediaErrorCallback = (action: string, type: string, err: string) => void

export interface CameraStateEvent {
  camera_id: number
  width: number
  height: number
  fps?: number
}

interface SharedCameraCapture {
  track: webrtc.VideoTrack
  source: webrtc.VideoSource | null
  users: number
}

export class KooUserMedia {
  private static sharedCameraCapture: SharedCameraCapture | null = null

  // PeerConnectionFactory 由外部注入（与 KooRTCSource 共用同一个 pcf）
  private pcf: webrtc.PeerConnectionFactory | null = null

  private videoSource: webrtc.VideoSource | null = null
  private videoTrack: webrtc.VideoTrack | null = null
  private retainedSharedTrack: webrtc.VideoTrack | null = null

  private cameraId: number = -1
  private cameraOn: boolean = false
  private cameraOpening: boolean = false

  onSuccess: UserMediaSuccessCallback | null = null
  onError: UserMediaErrorCallback | null = null

  /**
   * 设置共用的 PeerConnectionFactory（必须在 openCamera 之前调用）
   */
  setPeerConnectionFactory(pcf: webrtc.PeerConnectionFactory): void {
    this.pcf = pcf
  }

  /**
   * 返回当前已经打开的本地摄像头轨道。
   * KooPhone 和 LiveKit 推流共用这一条 track，避免 @ohos/webrtc 同时打开两路摄像头采集。
   */
  static getSharedVideoTrack(): webrtc.VideoTrack | null {
    const capture = KooUserMedia.sharedCameraCapture
    if (!capture) {
      return null
    }
    if (capture.track.readyState === 'ended') {
      KooUserMedia.sharedCameraCapture = null
      return null
    }
    return capture.track
  }

  /**
   * 将新创建的摄像头轨道注册为全局共享轨道。
   */
  static registerSharedVideoTrack(track: webrtc.VideoTrack, source: webrtc.VideoSource | null): void {
    KooUserMedia.sharedCameraCapture = {
      track,
      source,
      users: 0
    }
  }

  /**
   * 增加共享摄像头轨道使用计数。
   */
  static retainSharedVideoTrack(track: webrtc.VideoTrack): boolean {
    const capture = KooUserMedia.sharedCameraCapture
    if (!capture || capture.track !== track || track.readyState === 'ended') {
      return false
    }
    capture.users += 1
    return true
  }

  /**
   * 减少共享摄像头轨道使用计数。最后一个使用方释放时才真正关闭摄像头。
   */
  static releaseSharedVideoTrack(track: webrtc.VideoTrack): void {
    const capture = KooUserMedia.sharedCameraCapture
    if (!capture || capture.track !== track) {
      return
    }
    capture.users = Math.max(0, capture.users - 1)
    if (capture.users > 0) {
      return
    }

    try {
      capture.track.stop()
      console.info('[KooUserMedia] Shared camera released')
    } catch (error) {
      console.error('[KooUserMedia] release shared camera failed:', String(error))
    } finally {
      KooUserMedia.sharedCameraCapture = null
    }
  }

  /**
   * 开启摄像头（对应 H5 UserMedia.openCamera）
   * @param cameraId 0=后摄, 1=前摄
   * @param width  请求宽度（像素）
   * @param height 请求高度（像素）
   * @param fps    帧率（默认 24）
   */
  async openCamera(cameraId: number, width: number, height: number, fps: number = 24): Promise<boolean> {
    if (cameraId < 0) {
      return false
    }
    if (this.cameraOpening) {
      console.warn('[KooUserMedia] Camera is opening, ignore duplicate request')
      return false
    }
    if (!this.pcf) {
      console.error('[KooUserMedia] PeerConnectionFactory not set')
      this.onError?.('start', 'video', 'PeerConnectionFactory not set')
      return false
    }
    if (this.cameraOn && this.cameraId === cameraId) {
      return true
    }

    this.cameraOpening = true
    console.info('[KooUserMedia] Opening camera id:', cameraId, width, 'x', height, 'fps:', fps)

    try {
      await this.stopCamera()

      const sharedTrack = KooUserMedia.getSharedVideoTrack()
      if (sharedTrack && KooUserMedia.retainSharedVideoTrack(sharedTrack)) {
        this.videoTrack = sharedTrack
        this.videoSource = null
        this.retainedSharedTrack = sharedTrack
        this.cameraId = cameraId
        this.cameraOn = true
        this.cameraOpening = false
        console.info('[KooUserMedia] Reusing shared camera track:', sharedTrack.id)
        this.onSuccess?.('start', 'video', this.videoTrack)
        return true
      }

      // facingMode: 前摄='user', 后摄='environment'（对应 H5 facingMode 约束）
      const facingMode = cameraId === 1 ? 'user' : 'environment'

      // @ohos/webrtc 1.0.1 在 Mate X7 上直接传 facingMode 容易进入 native 相机方向查询崩溃路径。
      // 这里只传 README 示例中的基础约束，cameraId/facingMode 仅保留为业务状态。
      const constraints: webrtc.MediaTrackConstraints = this.buildVideoConstraints(width, height, fps)

      this.videoSource = this.pcf.createVideoSource(constraints)

      // 监听采集启动结果
      this.videoSource.oncapturerstarted = (event: webrtc.VideoCapturerStartedEvent) => {
        console.info('[KooUserMedia] Capturer started:', event.success ? 'success' : 'failed')
        if (!event.success) {
          this.cameraOpening = false
          this.onError?.('start', 'video', 'Video capturer failed to start')
        }
      }

      // 创建视频轨道
      const trackId = 'camera_' + cameraId
      this.videoTrack = this.pcf.createVideoTrack(trackId, this.videoSource)
      KooUserMedia.registerSharedVideoTrack(this.videoTrack, this.videoSource)
      KooUserMedia.retainSharedVideoTrack(this.videoTrack)
      this.retainedSharedTrack = this.videoTrack

      this.cameraId = cameraId
      this.cameraOn = true
      this.cameraOpening = false

      console.info('[KooUserMedia] Camera started, facingMode:', facingMode)
      this.onSuccess?.('start', 'video', this.videoTrack)
      return true
    } catch (e) {
      this.cameraOpening = false
      const msg = e instanceof Error ? e.message : String(e)
      console.error('[KooUserMedia] openCamera failed:', msg)
      this.onError?.('start', 'video', msg)
      return false
    }
  }

  /**
   * 关闭摄像头（对应 H5 UserMedia.closeCamera）
   */
  async closeCamera(): Promise<void> {
    if (!this.cameraOn) {
      return
    }
    console.info('[KooUserMedia] Closing camera')
    await this.stopCamera()
    this.onSuccess?.('stop', 'video', null)
  }

  isCameraOn(): boolean {
    return this.cameraOn
  }

  isCameraOpening(): boolean {
    return this.cameraOpening
  }

  getCameraId(): number {
    return this.cameraId
  }

  async destroy(): Promise<void> {
    await this.stopCamera()
    this.onSuccess = null
    this.onError = null
    this.pcf = null
  }

  // ==================== 私有方法 ====================

  private async stopCamera(): Promise<void> {
    if (this.retainedSharedTrack) {
      KooUserMedia.releaseSharedVideoTrack(this.retainedSharedTrack)
    }
    this.retainedSharedTrack = null
    this.videoTrack = null
    this.videoSource = null
    this.cameraOn = false
    this.cameraId = -1
    this.cameraOpening = false
    console.info('[KooUserMedia] Camera stopped')
  }

  private buildVideoConstraints(width: number, height: number, fps: number): webrtc.MediaTrackConstraints {
    const safeFps = Math.max(1, Math.floor(fps))
    return {
      width: Math.max(1, Math.floor(width)),
      height: Math.max(1, Math.floor(height)),
      frameRate: {
        min: safeFps,
        max: Math.max(safeFps, 30)
      }
    }
  }
}

export function createKooUserMedia(): KooUserMedia {
  return new KooUserMedia()
}
