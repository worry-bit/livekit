/**
 * 鸿蒙音频管理器
 * 使用 @ohos.multimedia.audio 处理音频播放
 * 
 * 音频采集已集成到 RTCEngine 中（通过 @ohos/webrtc）
 * 此模块主要处理远程音频播放
 */

import audio from '@ohos.multimedia.audio'

/**
 * 音频渲染器配置
 */
export interface AudioRendererConfig {
  sampleRate?: number    // 默认 48000
  channelCount?: number  // 默认 1
}

/**
 * 远程音频播放器
 * 用于播放从 WebRTC 接收的远程音频流
 */
export class RemoteAudioPlayer {
  private renderer: audio.AudioRenderer | null = null
  private isPlaying: boolean = false
  private config: AudioRendererConfig

  constructor(config?: AudioRendererConfig) {
    this.config = {
      sampleRate: config?.sampleRate || 48000,
      channelCount: config?.channelCount || 1
    }
  }

  /**
   * 初始化音频渲染器
   */
  async initialize(): Promise<void> {
    if (this.renderer) {
      return
    }

    const rendererOptions: audio.AudioRendererOptions = {
      streamInfo: {
        samplingRate: this.config.sampleRate as audio.AudioSamplingRate,
        channels: this.config.channelCount as audio.AudioChannel,
        sampleFormat: audio.AudioSampleFormat.SAMPLE_FORMAT_S16LE,
        encodingType: audio.AudioEncodingType.ENCODING_TYPE_RAW
      },
      rendererInfo: {
        content: audio.ContentType.CONTENT_TYPE_SPEECH,
        usage: audio.StreamUsage.STREAM_USAGE_VOICE_COMMUNICATION,
        rendererFlags: 0
      }
    }

    this.renderer = await audio.createAudioRenderer(rendererOptions)
    console.info('[RemoteAudioPlayer] Initialized')
  }

  /**
   * 开始播放
   */
  async start(): Promise<void> {
    if (!this.renderer) {
      await this.initialize()
    }

    if (this.isPlaying) {
      return
    }

    await this.renderer!.start()
    this.isPlaying = true
    console.info('[RemoteAudioPlayer] Started')
  }

  /**
   * 写入音频数据
   */
  async write(data: ArrayBuffer): Promise<number> {
    if (!this.renderer || !this.isPlaying) {
      return 0
    }

    try {
      return await this.renderer.write(data)
    } catch (error) {
      console.error('[RemoteAudioPlayer] Write error:', error)
      return 0
    }
  }

  /**
   * 停止播放
   */
  async stop(): Promise<void> {
    if (!this.renderer || !this.isPlaying) {
      return
    }

    try {
      await this.renderer.stop()
      this.isPlaying = false
      console.info('[RemoteAudioPlayer] Stopped')
    } catch (error) {
      console.error('[RemoteAudioPlayer] Stop error:', error)
    }
  }

  /**
   * 释放资源
   */
  async release(): Promise<void> {
    await this.stop()
    
    if (this.renderer) {
      try {
        await this.renderer.release()
      } catch (error) {
        console.error('[RemoteAudioPlayer] Release error:', error)
      }
      this.renderer = null
    }
    
    console.info('[RemoteAudioPlayer] Released')
  }

  /**
   * 设置音量 (0.0 - 1.0)
   */
  async setVolume(volume: number): Promise<void> {
    if (this.renderer) {
      await this.renderer.setVolume(Math.max(0, Math.min(1, volume)))
    }
  }

  /**
   * 获取播放状态
   */
  isActive(): boolean {
    return this.isPlaying
  }
}

/**
 * 音频管理器
 * 管理多个远程参与者的音频播放
 */
export class AudioManager {
  private players: Map<string, RemoteAudioPlayer> = new Map()
  private defaultConfig: AudioRendererConfig

  constructor(config?: AudioRendererConfig) {
    this.defaultConfig = config || { sampleRate: 48000, channelCount: 1 }
  }

  /**
   * 为参与者创建播放器
   */
  async createPlayer(participantSid: string): Promise<RemoteAudioPlayer> {
    let player = this.players.get(participantSid)
    if (!player) {
      player = new RemoteAudioPlayer(this.defaultConfig)
      await player.initialize()
      this.players.set(participantSid, player)
      console.info(`[AudioManager] Created player for ${participantSid}`)
    }
    return player
  }

  /**
   * 获取参与者的播放器
   */
  getPlayer(participantSid: string): RemoteAudioPlayer | undefined {
    return this.players.get(participantSid)
  }

  /**
   * 移除参与者的播放器
   */
  async removePlayer(participantSid: string): Promise<void> {
    const player = this.players.get(participantSid)
    if (player) {
      await player.release()
      this.players.delete(participantSid)
      console.info(`[AudioManager] Removed player for ${participantSid}`)
    }
  }

  /**
   * 释放所有资源
   */
  async releaseAll(): Promise<void> {
    const entries: [string, RemoteAudioPlayer][] = []
    this.players.forEach((value: RemoteAudioPlayer, key: string) => {
      entries.push([key, value])
    })
    for (let i = 0; i < entries.length; i++) {
      await entries[i][1].release()
    }
    this.players.clear()
    console.info('[AudioManager] All players released')
  }

  /**
   * 设置所有播放器音量
   */
  async setGlobalVolume(volume: number): Promise<void> {
    const players: RemoteAudioPlayer[] = []
    this.players.forEach((value: RemoteAudioPlayer) => {
      players.push(value)
    })
    for (let i = 0; i < players.length; i++) {
      await players[i].setVolume(volume)
    }
  }
}

/**
 * 简单的 HarmonyAudioTrack 类
 * 用于兼容旧接口
 */
export class HarmonyAudioTrack {
  private capturer: audio.AudioCapturer | null = null
  
  constructor(capturer: audio.AudioCapturer) {
    this.capturer = capturer
  }

  getCapturer(): audio.AudioCapturer | null {
    return this.capturer
  }
}
