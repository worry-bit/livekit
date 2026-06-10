import { abilityAccessCtrl, common } from '@kit.AbilityKit'
import { AudioLevelInfo, createLiveKitClient, LiveKitClient, VideoCaptureOptions } from 'livekit-harmony'
import { RtcModel, SpeakerModel } from './RtcModel'

/**
 * 本机 LiveKit 推流适配层。
 * 页面通过这里完成“权限 -> SFU 建连 -> 发布摄像头 -> 取消发布 -> 离开房间”的顺序调用。
 */
class LiveKitUtil {
  roomState: string = 'disconnected'
  remoteSpeakers: string[] = []
  errorMessage: string = ''
  participantCount: number = 0
  isVideoPublished: boolean = false
  hasMediaPermission: boolean = false
  localVideoSurfaceId: string = ''
  currentVideoDeviceId: string = ''

  private client: LiveKitClient = createLiveKitClient()
  private context: common.UIAbilityContext = getContext(this) as common.UIAbilityContext
  private clientGeneration: number = 0

  constructor() {
    this.setupEventHandlers(this.client, this.clientGeneration)
  }

  /**
   * 连接到 LiveKit SFU 房间。url/token 仍由页面配置传入，仓库中只保留占位符。
   * @returns true 表示信令和 RTC 初始化已完成，可以继续 publishVideo。
   */
  async joinRoom(url: string, token: string): Promise<boolean> {
    if (!this.isValidSfuParam(url) || !this.isValidSfuParam(token)) {
      this.errorMessage = 'LiveKit SFU url/token 仍是占位符，请先替换为真实参数'
      console.warn('[LiveKitUtil] Invalid SFU params')
      return false
    }

    if (this.roomState === 'connected' && this.client.isConnected) {
      return true
    }

    if (this.roomState !== 'disconnected') {
      this.errorMessage = 'LiveKit 正在连接或重连中，请稍后再试'
      console.warn('[LiveKitUtil] Already connecting or connected, skip')
      return false
    }

    this.roomState = 'connecting'
    this.errorMessage = ''
    try {
      await this.client.connect(url, token, {
        publishAudio: true,
        audioOptions: {
          sampleRate: 48000,
          channelCount: 1,
          echoCancellation: true,
          noiseSuppression: true,
          autoGainControl: true
        }
      })

      if (!this.client.isConnected) {
        this.roomState = 'disconnected'
        this.errorMessage = this.getReadableErrorMessage(this.errorMessage, '连接 LiveKit SFU 房间失败')
        return false
      }

      this.roomState = 'connected'
      return true
    } catch (error) {
      this.roomState = 'disconnected'
      this.errorMessage = this.getReadableErrorMessage(String(error), '连接 LiveKit SFU 房间失败')
      console.error('[LiveKitUtil] joinRoom failed:', error)
      return false
    }
  }

  /**
   * 离开 LiveKit 房间并清理本地状态。关闭推流时先调用 unpublishVideo，再调用本方法。
   */
  async leaveRoom(): Promise<boolean> {
    let success = true
    try {
      await this.client.disconnect()
    } catch (error) {
      success = false
      this.errorMessage = String(error)
      console.error('[LiveKitUtil] leaveRoom failed:', error)
    } finally {
      this.resetRuntimeState()
      this.recreateClientForNextPush()
    }
    return success
  }

  /**
   * 关闭直播推流的兜底入口。先立即切换到新 client 并重置页面状态，
   * 再限时关闭旧 client，避免 native 释放或信令断开卡住 UI 按钮。
   */
  async closeAndResetForNextPush(timeoutMs: number): Promise<boolean> {
    const staleClient = this.detachCurrentClientForNextPush()
    return this.closeDetachedClientWithTimeout(staleClient, timeoutMs)
  }

  /**
   * 用户点击“关闭直播推流”时的同步兜底复位。
   * entry 不能调用 SDK 私有实现，只能废弃当前 client 并换新 client；
   * 旧 client 的公开 disconnect 走后台 fire-and-forget，避免阻塞页面按钮状态。
   */
  forceResetForNextPush(): void {
    const staleClient = this.client
    this.clientGeneration++
    this.resetRuntimeState()
    try {
      staleClient.stopAudioLevelObserver()
      staleClient.disconnect().catch((error: Error) => {
        this.errorMessage = String(error)
        console.error('[LiveKitUtil] background disconnect failed:', error)
      })
    } catch (error) {
      this.errorMessage = String(error)
      console.error('[LiveKitUtil] force reset failed:', error)
    }
    this.client = createLiveKitClient()
    this.setupEventHandlers(this.client, this.clientGeneration)
  }

  /**
   * 切换麦克风静音状态，保留给旧示例页和后续语音控制使用。
   */
  toggleMute(isMuted: boolean): void {
    this.client.setMuted(isMuted)
  }

  /**
   * 发布本机摄像头视频。surfaceId 必须来自本机预览 XComponent，不能复用云机串流 surface。
   * @returns true 表示视频轨道已发布到 SFU。
   */
  async publishVideo(surfaceId: string, deviceId: string = ''): Promise<boolean> {
    if (surfaceId.length === 0) {
      this.errorMessage = '本机摄像头预览 surface 未准备好'
      console.warn('[LiveKitUtil] publishVideo called with empty surfaceId')
      return false
    }

    if (!this.client.isConnected) {
      this.errorMessage = 'LiveKit 房间未连接，无法发布视频'
      console.warn('[LiveKitUtil] publishVideo called before room connected')
      return false
    }

    this.localVideoSurfaceId = surfaceId
    try {
      const normalizedDeviceId = deviceId.trim()
      const options = this.createVideoCaptureOptions(normalizedDeviceId)
      await this.client.publishVideo(surfaceId, options)
      this.isVideoPublished = true
      this.currentVideoDeviceId = normalizedDeviceId
      this.errorMessage = ''
      return true
    } catch (error) {
      this.isVideoPublished = false
      this.errorMessage = String(error)
      console.error('[LiveKitUtil] publishVideo failed:', error)
      return false
    }
  }

  /**
   * 取消发布本机摄像头视频，并释放 SDK 内部的视频轨道和本地渲染器。
   */
  async unpublishVideo(): Promise<boolean> {
    if (!this.isVideoPublished) {
      this.localVideoSurfaceId = ''
      this.currentVideoDeviceId = ''
      return true
    }

    try {
      await this.client.unpublishVideo()
      this.isVideoPublished = false
      this.localVideoSurfaceId = ''
      this.currentVideoDeviceId = ''
      return true
    } catch (error) {
      this.errorMessage = String(error)
      console.error('[LiveKitUtil] unpublishVideo failed:', error)
      return false
    }
  }

  /**
   * 不断开 SFU 房间，只替换本地视频采集源。
   * entry 用它在“手机摄像头 <-> AI 眼镜摄像头”之间切换；如果当前还没发布视频，则退化为首次发布。
   */
  async replaceVideoSource(surfaceId: string, deviceId: string = ''): Promise<boolean> {
    if (surfaceId.length === 0) {
      this.errorMessage = '本机摄像头预览 surface 未准备好'
      return false
    }
    if (!this.client.isConnected) {
      this.errorMessage = 'LiveKit 房间未连接，无法切换视频源'
      return false
    }
    if (!this.isVideoPublished) {
      return this.publishVideo(surfaceId, deviceId)
    }

    try {
      await this.client.unpublishVideo()
      this.isVideoPublished = false
      this.localVideoSurfaceId = ''
      this.currentVideoDeviceId = ''
      return this.publishVideo(surfaceId, deviceId)
    } catch (error) {
      this.errorMessage = String(error)
      console.error('[LiveKitUtil] replaceVideoSource failed:', error)
      return false
    }
  }

  /**
   * 切换前/后摄像头。只有视频已经发布后才允许切换，避免无轨道时调用底层 SDK。
   */
  async switchCamera(): Promise<boolean> {
    if (!this.isVideoPublished) {
      this.errorMessage = '请先开始直播推流，再切换摄像头'
      return false
    }

    try {
      await this.client.switchCamera()
      return true
    } catch (error) {
      this.errorMessage = String(error)
      console.error('[LiveKitUtil] switchCamera failed:', error)
      return false
    }
  }

  /**
   * 请求本机麦克风和摄像头权限。系统弹窗由 requestPermissionsFromUser 触发。
   * @returns true 表示两个权限都已授权。
   */
  async requestPermissions(): Promise<boolean> {
    const atManager = abilityAccessCtrl.createAtManager()
    try {
      const result = await atManager.requestPermissionsFromUser(
        this.context,
        ['ohos.permission.MICROPHONE', 'ohos.permission.CAMERA']
      )
      const micGranted = result.authResults.length > 0 && result.authResults[0] === 0
      const cameraGranted = result.authResults.length > 1 && result.authResults[1] === 0
      this.hasMediaPermission = micGranted && cameraGranted
      if (!this.hasMediaPermission) {
        this.errorMessage = '需要麦克风和摄像头权限才能进行直播推流'
      } else {
        this.errorMessage = ''
      }
      return this.hasMediaPermission
    } catch (error) {
      this.hasMediaPermission = false
      this.errorMessage = String(error)
      console.error('[LiveKitUtil] requestPermissions failed:', error)
      return false
    }
  }

  /**
   * 只请求摄像头权限。眼镜本地预览实验不连接 SFU，也不采集麦克风。
   */
  async requestCameraPermission(): Promise<boolean> {
    const atManager = abilityAccessCtrl.createAtManager()
    try {
      const result = await atManager.requestPermissionsFromUser(this.context, ['ohos.permission.CAMERA'])
      const cameraGranted = result.authResults.length > 0 && result.authResults[0] === 0
      if (!cameraGranted) {
        this.errorMessage = '需要摄像头权限才能预览眼镜画面'
      } else {
        this.errorMessage = ''
      }
      return cameraGranted
    } catch (error) {
      this.errorMessage = String(error)
      console.error('[LiveKitUtil] requestCameraPermission failed:', error)
      return false
    }
  }

  private isValidSfuParam(value: string): boolean {
    const normalized = value.trim()
    return normalized.length > 0 && normalized.indexOf('__LIVEKIT_') < 0
  }

  /**
   * 重置页面可读状态。关闭推流后必须回到完整初始态，
   * 下一次点击开始推流才会重新走 joinRoom 和 publishVideo。
   */
  private resetRuntimeState(): void {
    this.roomState = 'disconnected'
    this.remoteSpeakers = []
    this.participantCount = 0
    this.isVideoPublished = false
    this.localVideoSurfaceId = ''
    this.currentVideoDeviceId = ''
  }

  private createVideoCaptureOptions(deviceId: string): VideoCaptureOptions {
    const options: VideoCaptureOptions = {
      width: deviceId.length > 0 ? 1280 : 640,
      height: 720,
      frameRate: 15
    }
    if (deviceId.length > 0) {
      options.deviceId = deviceId
      console.info('[LiveKitUtil] publishVideo with explicit deviceId:', deviceId)
    }
    return options
  }

  /**
   * 关闭房间后重新创建 LiveKitClient。旧 client 内部可能仍保留 peerConnection、
   * renderer 或信令监听状态，换新实例可以避免下一次开始推流被旧状态卡住。
   */
  private recreateClientForNextPush(): void {
    this.client.stopAudioLevelObserver()
    this.client = createLiveKitClient()
    this.clientGeneration++
    this.setupEventHandlers(this.client, this.clientGeneration)
  }

  private detachCurrentClientForNextPush(): LiveKitClient {
    const staleClient = this.client
    staleClient.stopAudioLevelObserver()
    this.resetRuntimeState()
    this.client = createLiveKitClient()
    this.clientGeneration++
    this.setupEventHandlers(this.client, this.clientGeneration)
    return staleClient
  }

  private async closeDetachedClientWithTimeout(client: LiveKitClient, timeoutMs: number): Promise<boolean> {
    return new Promise<boolean>((resolve) => {
      let settled = false
      const timeout = setTimeout(() => {
        if (settled) {
          return
        }
        settled = true
        this.errorMessage = '关闭直播推流超时，已重置状态，可重新开始推流'
        console.warn('[LiveKitUtil] close detached client timed out')
        resolve(false)
      }, timeoutMs) as number

      setTimeout(() => {
        this.closeDetachedClient(client).then((success: boolean) => {
          if (settled) {
            return
          }
          settled = true
          clearTimeout(timeout)
          resolve(success)
        })
      }, 60)
    })
  }

  private async closeDetachedClient(client: LiveKitClient): Promise<boolean> {
    try {
      await client.unpublishVideo()
      await client.disconnect()
      return true
    } catch (error) {
      this.errorMessage = String(error)
      console.error('[LiveKitUtil] close detached client failed:', error)
      return false
    }
  }

  /**
   * 设置 LiveKit SDK 事件处理器，把底层连接状态同步给页面可读字段。
   */
  private setupEventHandlers(client: LiveKitClient, generation: number): void {
    client.on('connected', () => {
      if (!this.isCurrentClientGeneration(generation)) {
        return
      }
      this.roomState = 'connected'
      console.info('[LiveKitUtil] 已连接到房间')

      client.startAudioLevelObserver((levels: AudioLevelInfo[]) => {
        for (let i = 0; i < levels.length; i++) {
          const info = levels[i]
          if (info.isLocal) {
            if (info.isSpeaking) {
              console.debug('[LiveKitUtil] 本地正在说话')
            } else {
              console.debug('[LiveKitUtil] 本地未说话')
            }
          } else {
            if (info.isSpeaking) {
              console.debug('[LiveKitUtil] 远端正在说话')
            } else {
              console.debug('[LiveKitUtil] 远端未说话')
            }
          }
        }
      }, { intervalMs: 500, speakingThreshold: 0.05 })
    })

    client.on('disconnected', (data: ESObject) => {
      if (!this.isCurrentClientGeneration(generation)) {
        return
      }
      this.roomState = 'disconnected'
      this.isVideoPublished = false
      this.localVideoSurfaceId = ''
      client.stopAudioLevelObserver()
      if (data.error) {
        this.errorMessage = this.getReadableErrorMessage(String(data.error.message), '连接 LiveKit SFU 房间失败')
      }
      console.info('[LiveKitUtil] 已断开连接')
    })

    client.on('reconnecting', () => {
      if (!this.isCurrentClientGeneration(generation)) {
        return
      }
      this.roomState = 'reconnecting'
      console.info('[LiveKitUtil] 正在重连...')
    })

    client.on('participantConnected', (data: RtcModel) => {
      if (!this.isCurrentClientGeneration(generation)) {
        return
      }
      console.info('[LiveKitUtil] 参与者加入:', data.participant.identity)
      this.participantCount++
    })

    client.on('participantDisconnected', (data: RtcModel) => {
      if (!this.isCurrentClientGeneration(generation)) {
        return
      }
      console.info('[LiveKitUtil] 参与者离开:', data.participant.identity)
      this.participantCount--
    })

    client.on('trackSubscribed', () => {
      if (!this.isCurrentClientGeneration(generation)) {
        return
      }
      console.info('[LiveKitUtil] 收到远程音频轨道')
    })

    client.on('activeSpeakersChanged', (data: SpeakerModel) => {
      if (!this.isCurrentClientGeneration(generation)) {
        return
      }
      this.remoteSpeakers = data.speakers.map(s => s.sid)
    })
  }

  private isCurrentClientGeneration(generation: number): boolean {
    return generation === this.clientGeneration
  }

  private getReadableErrorMessage(message: string, fallback: string): string {
    const normalized = message.trim()
    if (normalized.length === 0 || normalized === 'undefined' || normalized === '[object Object]') {
      return fallback
    }
    return normalized
  }
}

const liveKitUtil = new LiveKitUtil()

export default liveKitUtil
