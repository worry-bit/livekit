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

// 云手机串流播放器（折叠屏直播页使用）
export { KooPhonePlayer, createKooPhonePlayer } from './src/main/ets/koophone/KooPhonePlayer'
export {
  KooPhoneState,
  KooPhoneError,
  KooPhoneParams
} from './src/main/ets/koophone/KooPhoneTypes'
export type {
  IamPasswordConfig,
  KooAuthConfig,
  KooAuthTokenResult,
  LivePlatformConfig
} from './src/main/ets/koophone/KooPhoneTypes'
export { KooAuthService, createKooAuthService } from './src/main/ets/koophone/KooAuthService'
export { parseKooInstanceAuthResponse } from './src/main/ets/koophone/KooAuthParser'
export {
  includesKooInstanceId,
  selectNextAvailableKooInstance
} from './src/main/ets/koophone/KooInstancePool'
export type {
  KooInstancePoolEntry,
  KooInstanceSelectionInput
} from './src/main/ets/koophone/KooInstancePool'
export {
  canStartKooLiveAddSelection,
  getKooLiveAddOptionTitle,
  isKooLiveAddOptionDisabled,
  resolveKooFoldedVisibleSlot,
  shouldShowKooFoldedSwitch,
  shouldShowKooLiveAddPanel
} from './src/main/ets/koophone/KooLiveSlotPolicy'
export type { KooLiveAddSlotState } from './src/main/ets/koophone/KooLiveSlotPolicy'
export {
  KooInputController,
  TouchAction
} from './src/main/ets/koophone/KooInputController'
export type { TouchPoint } from './src/main/ets/koophone/KooInputController'
