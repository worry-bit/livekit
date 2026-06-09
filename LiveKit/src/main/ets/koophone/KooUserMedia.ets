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
 *   @ohos/webrtc 内部负责相机采集，无需手动操作 Camera Kit。
 *
 *   注意：@ohos/webrtc 1.0.1 在 Mate X7 上透传 facingMode 会触发
 *   OH_CameraDevice_GetCameraOrientation native 崩溃，因此当前只传基础采集约束。
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

export class KooUserMedia {
  // PeerConnectionFactory 由外部注入（与 KooRTCSource 共用同一个 pcf）
  private pcf: webrtc.PeerConnectionFactory | null = null

  private videoSource: webrtc.VideoSource | null = null
  private videoTrack: webrtc.VideoTrack | null = null

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

      // facingMode 只保留为业务状态，不透传给 createVideoSource，避免 Mate X7 native 崩溃。
      const facingMode = cameraId === 1 ? 'user' : 'environment'
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

      this.cameraId = cameraId
      this.cameraOn = true
      this.cameraOpening = false

      console.info('[KooUserMedia] Camera started with safe constraints, requested facingMode:', facingMode)
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
    if (this.videoTrack) {
      this.videoTrack.stop()
      this.videoTrack = null
    }
    if (this.videoSource) {
      this.videoSource.release()
      this.videoSource = null
    }
    this.cameraOn = false
    this.cameraId = -1
    this.cameraOpening = false
    console.info('[KooUserMedia] Camera stopped')
  }

  /**
   * 构造 @ohos/webrtc 官方示例兼容的视频采集约束。
   * 不传 facingMode：Mate X7 上这一路会进入 libohcamera orientation 崩溃路径。
   * frameRate 使用范围对象，贴近 @ohos/webrtc README 中的 createVideoSource 示例。
   */
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
