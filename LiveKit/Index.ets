/**
 * LiveKit 鸿蒙客户端
 * 导出入口
 */

// 主客户端
export { LiveKitClient, createLiveKitClient } from './src/main/ets/util/LiveKitClient'

export type { RoomEventHandler } from './src/main/ets/util/LiveKitClient'

// 类型定义
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
  ConnectionQuality,
  DisconnectReason,
  SpeakerInfo
} from './src/main/ets/util/types'

export type { RoomEventType,
  AudioLevelInfo,
  AudioLevelCallback,
  AudioLevelObserverOptions } from './src/main/ets/util/types'

// 音频管理（高级用法）
export { AudioManager, RemoteAudioPlayer } from './src/main/ets/util/AudioManager'

// 信令客户端（高级用法）
export { SignalClient } from './src/main/ets/util/SignalClient'

// RTC 引擎（高级用法）
export { RTCEngine } from './src/main/ets/util/RTCEngine'

export type { RTCEngineDelegate } from './src/main/ets/util/RTCEngine'
