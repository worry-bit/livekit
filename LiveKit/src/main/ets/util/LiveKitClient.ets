/**
 * LiveKit 鸿蒙客户端
 * 基于 @ohos/webrtc 官方 ArkTS API
 * 
 * 使用方法:
 *   import { LiveKitClient } from '@aspect/harmony-livekit'
 *   const client = new LiveKitClient()
 *   await client.connect('wss://server.com', 'token')
 *   await client.publishAudio()
 */

import webrtc from '@ohos/webrtc'
import {
  RoomState,
  RoomInfo,
  ParticipantInfo,
  ConnectOptions,
  AudioCaptureOptions,
  RoomEventType,
  AudioLevelInfo,
  AudioLevelCallback,
  AudioLevelObserverOptions
} from './types'
import { SignalClient } from './SignalClient'
import { RTCEngine, RTCEngineDelegate } from './RTCEngine'

export type RoomEventHandler = (event: ESObject) => void

/**
 * LiveKit 客户端
 */
export class LiveKitClient implements RTCEngineDelegate {
  // 状态
  private _state: RoomState = RoomState.DISCONNECTED
  private _roomInfo: RoomInfo | null = null
  private _localParticipant: ParticipantInfo | null = null
  private _remoteParticipants: Map<string, ParticipantInfo> = new Map()
  
  // 组件
  private signalClient: SignalClient
  private rtcEngine: RTCEngine
  
  // 事件处理
  private eventHandlers: Map<RoomEventType, RoomEventHandler[]> = new Map()
  
  // 音频状态
  private isAudioPublished: boolean = false
  private isMuted: boolean = false

  // 音频电平观察
  private audioLevelTimer: number | null = null
  private audioLevelCallback: AudioLevelCallback | null = null
  private audioLevelInterval: number = 100
  private speakingThreshold: number = 0.05

  constructor() {
    this.signalClient = new SignalClient()
    this.rtcEngine = new RTCEngine(this.signalClient)
    this.rtcEngine.setDelegate(this)
    
    this.setupSignalEventHandlers()
  }

  // ==================== Getters ====================

  get state(): RoomState {
    return this._state
  }

  get roomInfo(): RoomInfo | null {
    return this._roomInfo
  }

  get localParticipant(): ParticipantInfo | null {
    return this._localParticipant
  }

  get remoteParticipants(): ParticipantInfo[] {
    const result: ParticipantInfo[] = []
    this._remoteParticipants.forEach((value: ParticipantInfo) => {
      result.push(value)
    })
    return result
  }

  get isConnected(): boolean {
    return this._state === RoomState.CONNECTED
  }

  // ==================== 公共 API ====================

  /**
   * 连接到 LiveKit 房间
   * 
   * @param url LiveKit 服务器地址，如 wss://server.com
   * @param token JWT 令牌
   * @param options 连接选项
   */
  async connect(
    url: string,
    token: string,
    options: ConnectOptions = {}
  ): Promise<void> {
    if (this._state !== RoomState.DISCONNECTED) {
      throw new Error('Already connected or connecting')
    }

    try {
      this._state = RoomState.CONNECTING
      this.emit('reconnecting', { type: 'reconnecting' })
      
      console.info(`[LiveKitClient] Connecting to ${url}`)
      
      // 1. 建立 WebSocket 信令连接
      const joinResponse = await this.signalClient.connect(url, token)
      
      console.info('[LiveKitClient] Signal connected, room:', joinResponse.room.name)
      
      // 2. 保存房间和参与者信息
      this._roomInfo = joinResponse.room
      this._localParticipant = joinResponse.participant
      
      const otherParticipants = joinResponse.otherParticipants
      for (let i = 0; i < otherParticipants.length; i++) {
        this._remoteParticipants.set(otherParticipants[i].sid, otherParticipants[i])
      }
      
      // 3. 配置并创建 RTC 引擎
      this.rtcEngine.configure(
        joinResponse.iceServers,
        joinResponse.subscriberPrimary
      )
      await this.rtcEngine.createPeerConnections()
      
      // 3.5 智能音频路由：有耳机走耳机，无耳机走扬声器，并监听插拔自动切换
      await this.rtcEngine.setupSmartAudioRouting()

      // 4. 先标记为已连接，再发布音轨（publishAudio 内部会检查 isConnected）
      this._state = RoomState.CONNECTED
      this.emit('connected', { room: this._roomInfo })

      // 5. 自动发布音频（如果指定）
      if (options.publishAudio) {
        await this.publishAudio(options.audioOptions)
      }

      console.info('[LiveKitClient] Connected successfully')
      
    } catch (error) {
      console.error('[LiveKitClient] Connect failed:', error)
      this._state = RoomState.DISCONNECTED
      this.emit('disconnected', { error })
      // throw error
    }
  }

  /**
   * 断开连接
   */
  async disconnect(): Promise<void> {
    if (this._state === RoomState.DISCONNECTED) {
      return
    }
    
    console.info('[LiveKitClient] Disconnecting...')
    
    try {
      // 0. 停止音频电平观察
      this.stopAudioLevelObserver()

      // 1. 取消发布音频
      if (this.isAudioPublished) {
        await this.unpublishAudio()
      }
      
      // 2. 发送离开信令
      this.signalClient.sendLeave()
      
      // 3. 关闭 RTC 引擎
      await this.rtcEngine.close()
      
      // 4. 关闭信令连接
      this.signalClient.close()
      
    } catch (error) {
      console.error('[LiveKitClient] Disconnect error:', error)
    }
    
    // 清理状态
    this._state = RoomState.DISCONNECTED
    this._roomInfo = null
    this._localParticipant = null
    this._remoteParticipants.clear()
    this.isAudioPublished = false
    
    this.emit('disconnected', { type: 'disconnected' })
    console.info('[LiveKitClient] Disconnected')
  }

  /**
   * 发布本地音频
   */
  async publishAudio(options?: AudioCaptureOptions): Promise<void> {
    if (!this.isConnected) {
      throw new Error('Not connected to room')
    }

    if (this.isAudioPublished) {
      console.warn('[LiveKitClient] Audio already published')
      return
    }

    try {
      await this.rtcEngine.publishAudio(options)
      this.isAudioPublished = true
      
      console.info('[LiveKitClient] Audio published')
      this.emit('trackPublished', { kind: 'audio' })
      
    } catch (error) {
      console.error('[LiveKitClient] Publish audio failed:', error)
      // throw error
    }
  }

  /**
   * 取消发布本地音频
   */
  async unpublishAudio(): Promise<void> {
    if (!this.isAudioPublished) {
      return
    }

    try {
      await this.rtcEngine.unpublishAudio()
      this.isAudioPublished = false
      
      console.info('[LiveKitClient] Audio unpublished')
      this.emit('trackUnpublished', { kind: 'audio' })
      
    } catch (error) {
      console.error('[LiveKitClient] Unpublish audio failed:', error)
      // throw error
    }
  }

  /**
   * 设置静音状态
   */
  setMuted(muted: boolean): void {
    this.isMuted = muted
    this.rtcEngine.setAudioMuted(muted)
    
    console.info(`[LiveKitClient] Audio ${muted ? 'muted' : 'unmuted'}`)
    this.emit(muted ? 'trackMuted' : 'trackUnmuted', { kind: 'audio' })
  }

  /**
   * 获取静音状态
   */
  isMicMuted(): boolean {
    return this.isMuted
  }

  /**
   * 开始观察音频电平
   * @param callback 回调，每个周期返回所有音轨的电平信息
   * @param options intervalMs 轮询间隔（默认 100ms），speakingThreshold 说话阈值（默认 0.05）
   */
  startAudioLevelObserver(
    callback: AudioLevelCallback,
    options?: AudioLevelObserverOptions
  ): void {
    this.stopAudioLevelObserver()

    this.audioLevelCallback = callback
    this.audioLevelInterval = options?.intervalMs ?? 100
    this.speakingThreshold = options?.speakingThreshold ?? 0.05

    this.audioLevelTimer = setInterval(async () => {
      if (!this.isConnected || !this.audioLevelCallback) {
        return
      }

      const levels: AudioLevelInfo[] = []

      // 本地音频电平
      try {
        const localLevel = await this.rtcEngine.getLocalAudioLevel()
        levels.push({
          participantSid: this._localParticipant?.sid ?? 'local',
          isLocal: true,
          level: localLevel,
          isSpeaking: localLevel > this.speakingThreshold
        })
      } catch (_e) {
        // ignore
      }

      // 远端音频电平
      try {
        const remoteLevels = await this.rtcEngine.getRemoteAudioLevels()
        remoteLevels.forEach((level: number, trackId: string) => {
          levels.push({
            participantSid: trackId,
            isLocal: false,
            level: level,
            isSpeaking: level > this.speakingThreshold
          })
        })
      } catch (_e) {
        // ignore
      }

      if (levels.length > 0) {
        this.audioLevelCallback(levels)
        this.emit('audioLevelsChanged', { levels })
      }
    }, this.audioLevelInterval) as number
  }

  /**
   * 停止观察音频电平
   */
  stopAudioLevelObserver(): void {
    if (this.audioLevelTimer !== null) {
      clearInterval(this.audioLevelTimer)
      this.audioLevelTimer = null
    }
    this.audioLevelCallback = null
  }

  /**
   * 注册事件监听
   */
  on(event: RoomEventType, handler: RoomEventHandler): void {
    if (!this.eventHandlers.has(event)) {
      this.eventHandlers.set(event, [])
    }
    this.eventHandlers.get(event)!.push(handler)
  }

  /**
   * 移除事件监听
   */
  off(event: RoomEventType, handler: RoomEventHandler): void {
    const handlers = this.eventHandlers.get(event)
    if (handlers) {
      const index = handlers.indexOf(handler)
      if (index !== -1) {
        handlers.splice(index, 1)
      }
    }
  }

  // ==================== RTCEngineDelegate ====================

  /**
   * 收到远程轨道
   */
  onTrackAdded(track: webrtc.MediaStreamTrack, streams: webrtc.MediaStream[]): void {
    console.info('[LiveKitClient] Remote track added:', track.kind)
    
    // WebRTC 会自动播放远程音频
    this.emit('trackSubscribed', { track, streams })
  }

  /**
   * 远程轨道移除
   */
  onTrackRemoved(track: webrtc.MediaStreamTrack): void {
    console.info('[LiveKitClient] Remote track removed:', track.kind)
    this.emit('trackUnsubscribed', { track })
  }

  /**
   * 连接状态变化
   */
  onConnectionStateChanged(state: webrtc.RTCPeerConnectionState): void {
    console.info('[LiveKitClient] RTC connection state:', state)
    
    if (state === 'failed') {
      this.emit('reconnecting', { type: 'reconnecting' })
      // TODO: 实现自动重连逻辑
    } else if (state === 'connected') {
      this.emit('reconnected', { type: 'reconnected' })
    }
  }

  // ==================== 私有方法 ====================

  /**
   * 设置信令事件处理
   */
  private setupSignalEventHandlers(): void {
    // 参与者更新
    this.signalClient.on('participantUpdate', (response) => {
      if (!response.update) return
      
      const participants = response.update.participants
      for (let i = 0; i < participants.length; i++) {
        const info = participants[i]
        // 本地参与者
        if (info.sid === this._localParticipant?.sid) {
          this._localParticipant = info
          continue
        }
        
        // 远程参与者离开
        if (info.state === 3) { // DISCONNECTED
          this._remoteParticipants.delete(info.sid)
          this.emit('participantDisconnected', { participant: info })
          continue
        }
        
        // 远程参与者加入或更新
        const isNew = !this._remoteParticipants.has(info.sid)
        this._remoteParticipants.set(info.sid, info)
        
        if (isNew) {
          this.emit('participantConnected', { participant: info })
        }
      }
    })

    // 轨道发布响应
    this.signalClient.on('trackPublished', (response) => {
      if (response.trackPublished) {
        console.info('[LiveKitClient] Track published:', response.trackPublished.track)
      }
    })

    // 说话者变化
    this.signalClient.on('speakersChanged', (response) => {
      if (response.speakersChanged) {
        this.emit('activeSpeakersChanged', { 
          speakers: response.speakersChanged.speakers 
        })
      }
    })

    // 房间更新
    this.signalClient.on('roomUpdate', (response) => {
      if (response.roomUpdate) {
        this._roomInfo = response.roomUpdate.room
      }
    })

    // 服务端要求断开
    this.signalClient.on('leave', () => {
      console.info('[LiveKitClient] Server requested disconnect')
      this.disconnect()
    })

    // 连接质量
    this.signalClient.on('connectionQuality', (response) => {
      if (response.connectionQuality) {
        this.emit('connectionQualityChanged', {
          updates: response.connectionQuality.updates
        })
      }
    })
  }

  /**
   * 触发事件
   */
  private emit(event: RoomEventType, data: ESObject): void {
    const handlers = this.eventHandlers.get(event)
    if (handlers) {
      for (let i = 0; i < handlers.length; i++) {
        try {
          handlers[i](data)
        } catch (error) {
          console.error(`[LiveKitClient] Event handler error (${event}):`, error)
        }
      }
    }
  }
}

/**
 * 创建 LiveKit 客户端实例
 */
export function createLiveKitClient(): LiveKitClient {
  return new LiveKitClient()
}
