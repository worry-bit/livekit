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
  VideoCaptureOptions,
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

// KooPhone 云手机串流客户端
export { createKooPhonePlayer, KooPhonePlayer } from './src/main/ets/koophone/KooPhonePlayer'

export {
  KooPhoneState,
  KooPhoneError
} from './src/main/ets/koophone/KooPhoneTypes'

export type {
  KooPhoneParams,
  KooIceServer,
  KooSignalMessage,
  KooAuthorizePayload,
  KooStartPayload,
  OnStateChange,
  OnTrack,
  OnError
} from './src/main/ets/koophone/KooPhoneTypes'

export {
  KooInputController,
  TouchAction,
  KeyAction,
  createKooInputController
} from './src/main/ets/koophone/KooInputController'

export type { TouchPoint, SendDataFn } from './src/main/ets/koophone/KooInputController'

export { KooUserMedia, createKooUserMedia } from './src/main/ets/koophone/KooUserMedia'

export type {
  CameraStateEvent,
  UserMediaSuccessCallback,
  UserMediaErrorCallback
} from './src/main/ets/koophone/KooUserMedia'
