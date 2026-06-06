/**
 * LiveKit 鸿蒙客户端类型定义
 * 基于 livekit/protocol 的 protobuf 定义简化
 */

// ==================== 房间状态 ====================
export enum RoomState {
  DISCONNECTED = 'disconnected',
  CONNECTING = 'connecting',
  CONNECTED = 'connected',
  RECONNECTING = 'reconnecting'
}

// ==================== 参与者 ====================
export interface ParticipantInfo {
  sid: string
  identity: string
  name: string
  state: ParticipantState
  metadata?: string
  joinedAt: number
  permission?: ParticipantPermission
}

export enum ParticipantState {
  JOINING = 0,
  JOINED = 1,
  ACTIVE = 2,
  DISCONNECTED = 3
}

export interface ParticipantPermission {
  canSubscribe: boolean
  canPublish: boolean
  canPublishData: boolean
}

// ==================== 轨道 ====================
export interface TrackInfo {
  sid: string
  type: TrackType
  name: string
  source: TrackSource
  muted: boolean
}

// export enum TrackType {
//   AUDIO = 0,
//   VIDEO = 1,
//   DATA = 2
// }

export enum TrackSource {
  UNKNOWN = 0,
  CAMERA = 1,
  MICROPHONE = 2,
  SCREEN_SHARE = 3,
  SCREEN_SHARE_AUDIO = 4
}

// ==================== 信令消息 ====================

// 轨道类型
export enum TrackType {
  AUDIO = 0,
  VIDEO = 1,
  DATA = 2
}

// 添加轨道请求
export interface AddTrackRequest {
  cid: string           // 客户端轨道 ID
  name?: string         // 轨道名称
  type: TrackType       // 轨道类型
  source?: TrackSource  // 轨道来源
  muted?: boolean       // 是否静音
  disableDtx?: boolean  // 是否禁用 DTX
  disableRed?: boolean  // 是否禁用 RED
  width?: number        // 视频宽度
  height?: number       // 视频高度
}

// 客户端发送的信令请求
export interface SignalRequest {
  join?: JoinRequest
  offer?: SessionDescription
  answer?: SessionDescription
  trickle?: TrickleRequest
  addTrack?: AddTrackRequest  // 添加轨道请求
  leave?: LeaveRequest
  mute?: MuteTrackRequest
  subscription?: UpdateSubscription
  trackSetting?: UpdateTrackSettings
}

// 服务端发送的信令响应
export interface SignalResponse {
  join?: JoinResponse
  offer?: SessionDescription
  answer?: SessionDescription
  trickle?: TrickleRequest
  update?: ParticipantUpdate
  trackPublished?: TrackPublishedResponse
  leave?: LeaveRequest
  speakersChanged?: SpeakersChanged
  roomUpdate?: RoomUpdate
  connectionQuality?: ConnectionQualityUpdate
}

// 加入请求
export interface JoinRequest {
  roomName: string
  identity: string
  name?: string
  metadata?: string
  autoSubscribe?: boolean
  reconnect?: boolean
  // 客户端信息
  clientInfo?: ClientInfo
}

// 加入响应
export interface JoinResponse {
  room: RoomInfo
  participant: ParticipantInfo
  otherParticipants: ParticipantInfo[]
  serverVersion: string
  iceServers: ICEServer[]
  subscriberPrimary: boolean
}

// 房间信息
export interface RoomInfo {
  sid: string
  name: string
  metadata?: string
  numParticipants: number
  maxParticipants: number
  activeRecording: boolean
}

// 客户端信息
export interface ClientInfo {
  sdk: string        // 'HARMONY'
  version: string
  protocol: number   // 目前是 16
  os?: string
  osVersion?: string
  deviceModel?: string
}

// SDP 描述
export interface SessionDescription {
  type: 'offer' | 'answer'
  sdp: string
}

// ICE Candidate
export interface TrickleRequest {
  candidateInit: string  // JSON 编码的 RTCIceCandidateInit
  target: SignalTarget
}

export enum SignalTarget {
  PUBLISHER = 0,
  SUBSCRIBER = 1
}

// ICE 服务器配置
export interface ICEServer {
  urls: string[]
  username?: string
  credential?: string
}

// 离开请求
export interface LeaveRequest {
  canReconnect?: boolean
  reason?: DisconnectReason
}

export enum DisconnectReason {
  UNKNOWN = 0,
  CLIENT_INITIATED = 1,
  DUPLICATE_IDENTITY = 2,
  SERVER_SHUTDOWN = 3,
  PARTICIPANT_REMOVED = 4,
  ROOM_DELETED = 5,
  STATE_MISMATCH = 6,
  JOIN_FAILURE = 7
}

// 静音请求
export interface MuteTrackRequest {
  sid: string
  muted: boolean
}

// 订阅更新
export interface UpdateSubscription {
  trackSids: string[]
  subscribe: boolean
  participantTracks?: ParticipantTracks[]
}

export interface ParticipantTracks {
  participantSid: string
  trackSids: string[]
}

// 轨道设置更新
export interface UpdateTrackSettings {
  trackSids: string[]
  disabled?: boolean
  quality?: VideoQuality
  width?: number
  height?: number
  fps?: number
}

export enum VideoQuality {
  LOW = 0,
  MEDIUM = 1,
  HIGH = 2,
  OFF = 3
}

// 参与者更新
export interface ParticipantUpdate {
  participants: ParticipantInfo[]
}

// 轨道发布响应
export interface TrackPublishedResponse {
  cid: string  // client track id
  track: TrackInfo
}

// 说话者变化
export interface SpeakersChanged {
  speakers: SpeakerInfo[]
}

export interface SpeakerInfo {
  sid: string
  level: number  // 0-1
  active: boolean
}

// 房间更新
export interface RoomUpdate {
  room: RoomInfo
}

// 连接质量更新
export interface ConnectionQualityUpdate {
  updates: ConnectionQualityInfo[]
}

export interface ConnectionQualityInfo {
  participantSid: string
  quality: ConnectionQuality
  score: number
}

export enum ConnectionQuality {
  POOR = 0,
  GOOD = 1,
  EXCELLENT = 2,
  LOST = 3
}

// ==================== 事件 ====================

export type RoomEventType =
  | 'connected'
  | 'disconnected'
  | 'reconnecting'
  | 'reconnected'
  | 'participantConnected'
  | 'participantDisconnected'
  | 'trackPublished'
  | 'trackUnpublished'
  | 'trackSubscribed'
  | 'trackUnsubscribed'
  | 'trackMuted'
  | 'trackUnmuted'
  | 'activeSpeakersChanged'
  | 'connectionQualityChanged'
  | 'dataReceived'
  | 'audioLevelsChanged'

export interface RoomEvent {
  type: RoomEventType
  // 根据事件类型携带不同数据
  participant?: ParticipantInfo
  track?: TrackInfo
  data?: Uint8Array
}

// ==================== 连接选项 ====================

export interface ConnectOptions {
  autoSubscribe?: boolean  // 默认 true
  publishAudio?: boolean   // 连接后自动发布音频
  publishVideo?: boolean   // 连接后自动发布视频
  // 音频选项
  audioOptions?: AudioCaptureOptions
}

export interface AudioCaptureOptions {
  sampleRate?: number      // 默认 48000
  channelCount?: number    // 默认 1
  echoCancellation?: boolean
  noiseSuppression?: boolean
  autoGainControl?: boolean
}

// ==================== 音频电平 ====================

export interface AudioLevelInfo {
  participantSid: string  // 参与者 sid，本地为 'local'
  isLocal: boolean
  level: number           // 0.0 - 1.0
  isSpeaking: boolean     // level > threshold
}

export type AudioLevelCallback = (levels: AudioLevelInfo[]) => void

export interface AudioLevelObserverOptions {
  intervalMs?: number
  speakingThreshold?: number
}

// ==================== 音频帧 ====================

export interface AudioFrame {
  data: ArrayBuffer
  sampleRate: number
  numChannels: number
  samplesPerChannel: number
}

// ==================== 视频采集选项 ====================

export interface VideoCaptureOptions {
  width?: number      // 采集宽度，默认 1280
  height?: number     // 采集高度，默认 720
  frameRate?: number  // 帧率，默认 30
  facingMode?: 'user' | 'environment'  // 前置/后置，默认 'environment'
}
