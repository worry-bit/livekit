import webrtc from '@ohos/webrtc'

// 连接参数（与 H5 CloudPlayer._open() 参数一致）
export interface KooPhoneParams {
  signalingUrl: string        // 信令服务器地址，如 wss://host:port
  boxId: string               // 设备 ID
  token: string               // 鉴权 token
  uuid?: string               // 用户唯一标识（H5 required，不传则自动生成）
  sessionId?: string          // 会话 ID（不传则使用 token）
  streamingId?: string        // 串流 ID（KooPhone 实例鉴权返回时优先使用）
  iceServers?: KooIceServer[] // ICE 服务器（可选）
  mode?: string               // 默认 'app'
  role?: string               // 默认 'master'
  sole?: boolean              // 默认 true
  volume?: number             // 默认 100
}

// IAM 用户密码认证配置。真实账号密码只允许本地替换，不应提交到 git。
export interface IamPasswordConfig {
  authUrl: string
  domainName: string
  userName: string
  password: string
  projectName?: string
}

// KooPhone 实例鉴权接口配置。authUrl 为 /openapi/koophone/v1/instances/{kp_id}/auth 完整路径。
export interface KooAuthConfig {
  authUrl: string
  tenantId?: string
  projectId?: string
}

// 直播平台配置：IAM/KooPhone auth 每个平台独立；signalingUrl/boxId 由实例鉴权返回。
export interface LivePlatformConfig {
  signalingUrl?: string
  boxId?: string
  iam: IamPasswordConfig
  kooAuth: KooAuthConfig
  iceServers?: KooIceServer[]
  mode?: string
  role?: string
  sole?: boolean
  volume?: number
}

// KooPhone 实例鉴权返回给 SDK 的开流参数。当前 device_token 约 15 秒有效。
export interface KooAuthTokenResult {
  token: string
  signalingUrl: string
  boxId: string
  streamingId?: string
  iceServers?: KooIceServer[]
  expiresAt?: string
}

export interface KooIceServer {
  uri: string
  usr?: string
  pwd?: string
}

// 播放器状态
export enum KooPhoneState {
  NEW = 'new',
  CONNECTING = 'connecting',
  AUTHORIZED = 'authorized',
  PEER_CONNECTING = 'peer_connecting',
  PLAYING = 'playing',
  CLOSED = 'closed'
}

// 错误码
export enum KooPhoneError {
  PARAM_INVALID = 1001,
  SIGNAL_CONNECT_FAILED = 1002,
  SIGNAL_AUTH_FAILED = 1003,
  SDP_ERROR = 1004,
  ICE_ERROR = 1005,
  PEER_FAILED = 1006
}

// 信令消息结构
export interface KooSignalMessage {
  type: string       // 'offer' | 'answer' | 'candidate'
  from: string
  payload?: KooSignalPayload
  data?: string      // base64 编码（init 响应用）
}

// 授权响应结构
export interface KooAuthorizePayload {
  authorized: boolean
  code: number
}

// start 事件响应结构
export interface KooStartPayload {
  streamId: string
  vcodec?: string
}

export interface KooSignalPayload {
  type?: string
  sdp?: string
  label?: number
  id?: string
  candidate?: string
}

// 事件回调类型
export type OnStateChange = (state: KooPhoneState) => void
export type OnTrack = (track: webrtc.MediaStreamTrack) => void
export type OnError = (code: KooPhoneError, message: string) => void
