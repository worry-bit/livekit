import {
  KooAuthTokenResult,
  KooIceServer
} from './KooAuthTypes'

interface KooAuthIceServer {
  uri?: string
  urls?: string
  usr?: string
  username?: string
  pwd?: string
  credential?: string
}

interface KooAuthIceSignaling {
  signaling_url?: string
  expired_time?: string | number | null
  ice_servers?: KooAuthIceServer[]
}

interface KooAuthRtcResource {
  ice_signaling?: KooAuthIceSignaling
}

interface KooAuthResource {
  rtc?: KooAuthRtcResource
  device_id?: string
  kp_id?: string
}

interface KooInstanceAuthData {
  resource?: KooAuthResource
  device_token?: string
  streamingId?: string
}

interface KooInstanceAuthResponse {
  data?: KooInstanceAuthData
  error_code?: string | number
  error_msg?: string
}

/**
 * 解析 KooPhone 实例鉴权接口响应。
 * SDK 开流真正需要的 signalingUrl/token/boxId 都来自这个响应，
 * 不能再使用页面侧写死的旧占位参数。
 */
export function parseKooInstanceAuthResponse(raw: string): KooAuthTokenResult {
  const response = JSON.parse(raw) as KooInstanceAuthResponse
  if (`${response.error_code ?? ''}` !== '0') {
    throw new Error(`KooPhone auth failed: ${response.error_code ?? ''} ${response.error_msg ?? ''}`.trim())
  }

  const data = response.data
  const resource = data?.resource
  const iceSignaling = resource?.rtc?.ice_signaling
  const signalingUrl = iceSignaling?.signaling_url ?? ''
  const token = data?.device_token ?? ''
  const boxId = resource?.device_id ?? ''

  if (signalingUrl.length === 0) {
    throw new Error('KooPhone auth response missing data.resource.rtc.ice_signaling.signaling_url')
  }
  if (token.length === 0) {
    throw new Error('KooPhone auth response missing data.device_token')
  }
  if (boxId.length === 0) {
    throw new Error('KooPhone auth response missing data.resource.device_id')
  }

  const result: KooAuthTokenResult = {
    token,
    signalingUrl,
    boxId,
    streamingId: data?.streamingId,
    expiresAt: stringifyExpiresAt(iceSignaling?.expired_time)
  }
  const iceServers = convertIceServers(iceSignaling?.ice_servers)
  if (iceServers.length > 0) {
    result.iceServers = iceServers
  }
  return result
}

function stringifyExpiresAt(expiredTime?: string | number | null): string | undefined {
  if (expiredTime === undefined || expiredTime === null) {
    return undefined
  }
  return `${expiredTime}`
}

function convertIceServers(source?: KooAuthIceServer[]): KooIceServer[] {
  const result: KooIceServer[] = []
  if (!source) {
    return result
  }

  for (let i = 0; i < source.length; i++) {
    const item = source[i]
    const uri = item.uri ?? item.urls ?? ''
    if (uri.length === 0) {
      continue
    }
    result.push({
      uri,
      usr: item.usr ?? item.username,
      pwd: item.pwd ?? item.credential
    })
  }
  return result
}
