// import { createLiveKitClient, LiveKitClient } from "../../livekit/LiveKitClient"
import { AudioLevelInfo, VideoCaptureOptions, createLiveKitClient, LiveKitClient } from "livekit-harmony"
import { abilityAccessCtrl, common } from "@kit.AbilityKit"
import { AppStorageV2 } from "@kit.ArkUI"
import { RtcModel, SpeakerModel } from "./RtcModel"


class LiveKitUtil {
  // 状态
  roomState: string = 'disconnected'
  remoteSpeakers: string[] = []
  errorMessage: string = ''
  participantCount: number = 0
  isVideoPublished: boolean = false
  localVideoSurfaceId: string = ''
  // LiveKit 客户端
  private client: LiveKitClient = createLiveKitClient()
  // 上下文
  private context: common.UIAbilityContext = getContext(this) as common.UIAbilityContext

  constructor() {
    // this.requestPermissions()
    this.setupEventHandlers()
  }

  /**
   *
   * @param url  实际应用中应该从配置或 API 获取
   * @param token 实际应用中应该从配置或 API 获取
   * @returns
   */
  async joinRoom(url: string, token: string): Promise<void> {
    // 防止重复调用
    if (this.roomState !== 'disconnected') {
      console.warn('[VoiceCallPage] Already connecting or connected, skip')
      return
    }
    this.roomState = 'connecting'
    try {
      this.errorMessage = ''
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

    } catch (error) {
      console.debug('加入房间失败:', error)
      this.roomState = 'disconnected'
      this.errorMessage = (error as Error).message
    }

  }

  /**
   * 离开房间
   */
  async leaveRoom(): Promise<void> {
    await this.client.disconnect()
  }

  /**
   * 切换静音
   */
  toggleMute(isMuted: boolean): void {
    this.client.setMuted(isMuted)
  }

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
  async switchCamera(): Promise<void> {
    await this.client.switchCamera()
  }

  /**
   * 请求麦克风权限
   */
   async requestPermissions(): Promise<void> {
    const atManager = abilityAccessCtrl.createAtManager()
    try {
      const result = await atManager.requestPermissionsFromUser(
        this.context,
        ['ohos.permission.MICROPHONE', 'ohos.permission.CAMERA']
      )
      if (result.authResults[0] !== 0 || result.authResults[1] !== 0) {
        this.errorMessage = '需要麦克风和摄像头权限才能进行视频通话'
      }
    } catch (error) {
      console.error('请求权限失败:', error)
    }
  }

  /**
   * 设置事件处理器
   */
  private setupEventHandlers(): void {
    this.client.on('connected', () => {
      this.roomState = 'connected'
      console.info('已连接到房间')

      // 连接成功后启动音频电平观察（500ms 轮询，level > 0.05 视为说话）
      this.client.startAudioLevelObserver((levels: AudioLevelInfo[]) => {
        for (let i = 0; i < levels.length; i++) {
          const info = levels[i]
          if (info.isLocal) {
            // 本地麦克风电平 → 更新 UI 音量条
            if (info.isSpeaking) {
              console.debug('[VoiceCallPage] 本地正在说话')
            } else {
              console.debug('[VoiceCallPage] 本地未说话')
            }
          } else {
            // 远端音频电平 → 更新对应参与者 UI
            if (info.isSpeaking) {
              console.debug('[VoiceCallPage] 远端正在说话')
            } else {
              console.debug('[VoiceCallPage] 远端未说话')
            }
          }
        }
      }, { intervalMs: 500, speakingThreshold: 0.05 })
    })

    this.client.on('disconnected', (data: ESObject) => {
      this.roomState = 'disconnected'
      // 断开连接时停止音频电平观察，避免不可见状态下继续消耗资源
      this.client.stopAudioLevelObserver()
      if (data.error) {
        this.errorMessage = data.error.message
      }
      console.info('已断开连接')
    })

    this.client.on('reconnecting', () => {
      this.roomState = 'reconnecting'
      console.info('正在重连...')
    })

    this.client.on('participantConnected', (data: RtcModel) => {
      console.info('参与者加入:', data.participant.identity)
      this.participantCount++
    })

    this.client.on('participantDisconnected', (data: RtcModel) => {
      console.info('参与者离开:', data.participant.identity)
      this.participantCount--
    })

    this.client.on('trackSubscribed', () => {
      console.info('收到远程音频轨道')
    })

    this.client.on('activeSpeakersChanged', (data: SpeakerModel) => {
      this.remoteSpeakers = data.speakers.map(s => s.sid)
    })

  }

  /**
   * 获取状态文本
   */
  private getStateText(): string {
    switch (this.roomState) {
      case 'disconnected':
        return '未连接'
      case 'connecting':
        return '连接中...'
      case 'connected':
        return '已连接'
      case 'reconnecting':
        return '重连中...'
      default:
        return '未知'
    }
  }
}

let liveKitUtil = new LiveKitUtil()

export default liveKitUtil