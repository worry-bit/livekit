import { KooIceServer } from 'livekit-harmony'

export type { KooIceServer } from 'livekit-harmony'

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
