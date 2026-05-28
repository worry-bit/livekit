import webrtc from '@ohos/webrtc'
import { util } from '@kit.ArkTS'
import {
  KooPhoneParams,
  KooPhoneState,
  KooPhoneError,
  KooSignalMessage,
  KooStartPayload,
  OnStateChange,
  OnTrack,
  OnError
} from './KooPhoneTypes'
import { KooSignalClient } from './KooSignalClient'
import { KooRTCSource } from './KooRTCSource'

interface InitPayload {
  sole: boolean
  mode: string
  role: string
  profile_name: string
  network_type: string
  volume: number
  vcodec: string
}

interface CandidatePayload {
  label: number | null
  id: string | null
  candidate: string
}

export class KooPhonePlayer {
  private _state: KooPhoneState = KooPhoneState.NEW
  private params: KooPhoneParams | null = null
  private remoteId: string = ''
  private vcodec: string = 'H264'

  private signalClient: KooSignalClient = new KooSignalClient()
  private rtcSource: KooRTCSource = new KooRTCSource()

  // 事件回调
  onStateChange: OnStateChange | null = null
  onTrack: OnTrack | null = null
  onError: OnError | null = null

  get state(): KooPhoneState {
    return this._state
  }

  /**
   * 开始串流
   * @param params 连接参数
   * @param surfaceId XComponent 的 surfaceId（必须已 onLoad）
   */
  open(params: KooPhoneParams, surfaceId: string): void {
    if (this._state !== KooPhoneState.NEW && this._state !== KooPhoneState.CLOSED) {
      console.warn('[KooPhonePlayer] Already open, state:', this._state)
      return
    }

    if (!params.signalingUrl || !params.boxId || !params.token) {
      this.emitError(KooPhoneError.PARAM_INVALID, 'signalingUrl, boxId and token are required')
      return
    }

    this.params = params
    this.setupSignalHandlers(surfaceId)
    this.setupRTCHandlers()

    this.stateChange(KooPhoneState.CONNECTING)

    const query = `authtype=token&boxid=${params.boxId}&token=${params.token}`
    this.signalClient.connect(params.signalingUrl, query)

    console.info('[KooPhonePlayer] Opening, boxId:', params.boxId)
  }

  /**
   * 停止串流，释放所有资源
   */
  close(): void {
    if (this._state === KooPhoneState.CLOSED) {
      return
    }

    console.info('[KooPhonePlayer] Closing...')

    this.rtcSource.close()
    this.signalClient.close()

    this.remoteId = ''
    this.params = null

    this.stateChange(KooPhoneState.CLOSED)
    console.info('[KooPhonePlayer] Closed')
  }

  // ==================== 私有方法 ====================

  private setupSignalHandlers(surfaceId: string): void {
    this.signalClient.onAuthorize = (authorized: boolean) => {
      if (!authorized) {
        this.emitError(KooPhoneError.SIGNAL_AUTH_FAILED, 'Signal authorization failed')
        this.close()
        return
      }

      console.info('[KooPhonePlayer] Authorized')
      this.stateChange(KooPhoneState.AUTHORIZED)
    }

    this.signalClient.onStart = (payload: KooStartPayload) => {
      console.info('[KooPhonePlayer] Start received, streamId:', payload.streamId)
      this.remoteId = payload.streamId
      this.vcodec = payload.vcodec ?? 'H264'

      // 初始化 RTCPeerConnection
      this.stateChange(KooPhoneState.PEER_CONNECTING)
      this.rtcSource.open(this.params?.iceServers ?? [])
      this.rtcSource.setSurfaceId(surfaceId)

      // 发送 init 请求触发 boxrtc 开始 WebRTC 协商
      this.sendInit()
    }

    this.signalClient.onMessage = (message: KooSignalMessage) => {
      this.handleSignalMessage(message)
    }

    this.signalClient.onClosed = () => {
      console.info('[KooPhonePlayer] Signal connection closed')
      if (this._state !== KooPhoneState.CLOSED) {
        this.close()
      }
    }
  }

  private setupRTCHandlers(): void {
    this.rtcSource.onDescription = (desc: webrtc.RTCSessionDescription) => {
      // answer 创建完成，通过信令发送给 boxrtc
      console.info('[KooPhonePlayer] Sending answer')
      const payload: ESObject = { type: desc.type, sdp: desc.sdp }
      this.signalClient.emitMessage('answer', this.remoteId, payload)
    }

    this.rtcSource.onIceCandidate = (candidate: webrtc.RTCIceCandidate) => {
      // 发送本地 ICE candidate（与 H5 _onLocalIceCandidate 格式一致）
      const payload: CandidatePayload = {
        label: candidate.sdpMLineIndex ?? null,
        id: candidate.sdpMid ?? null,
        candidate: candidate.candidate
      }
      this.signalClient.emitMessage('candidate', this.remoteId, payload as ESObject)
    }

    this.rtcSource.onConnectionStateChange = (state: webrtc.RTCPeerConnectionState) => {
      console.info('[KooPhonePlayer] RTC connection state:', state)
      if (state === 'connected') {
        this.stateChange(KooPhoneState.PLAYING)
      } else if (state === 'failed') {
        this.emitError(KooPhoneError.PEER_FAILED, 'WebRTC peer connection failed')
        this.close()
      }
    }

    this.rtcSource.onTrack = (track: webrtc.MediaStreamTrack) => {
      console.info('[KooPhonePlayer] Remote track received, kind:', track.kind)
      this.onTrack?.(track)
    }
  }

  private sendInit(): void {
    if (!this.params) {
      return
    }

    const initPayload: InitPayload = {
      sole: this.params.sole ?? true,
      mode: this.params.mode ?? 'app',
      role: this.params.role ?? 'master',
      profile_name: 'master',
      network_type: 'wifi',
      volume: this.params.volume ?? 100,
      vcodec: this.vcodec
    }

    // base64 编码（与 H5 btoa(JSON.stringify(params)) 一致）
    const jsonStr = JSON.stringify(initPayload)
    const encoder = new util.TextEncoder()
    const bytes = encoder.encodeInto(jsonStr)
    const base64Helper = new util.Base64Helper()
    const encoded = base64Helper.encodeToStringSync(bytes)

    console.info('[KooPhonePlayer] Sending init, remoteId:', this.remoteId)
    this.signalClient.emitData('init', this.remoteId, encoded)
  }

  private handleSignalMessage(message: KooSignalMessage): void {
    const type = message.type

    if (type === 'offer') {
      console.info('[KooPhonePlayer] Received offer')
      const payload = message.payload as ESObject
      const sdp: webrtc.RTCSessionDescription = {
        type: payload['type'] as 'offer',
        sdp: payload['sdp'] as string
      }
      this.rtcSource.setRemoteDescription(sdp)
    } else if (type === 'candidate') {
      const payload = message.payload as ESObject
      const candidateInit: webrtc.RTCIceCandidateInit = {
        candidate: payload['candidate'] as string,
        sdpMLineIndex: payload['label'] as number,
        sdpMid: payload['id'] as string
      }
      this.rtcSource.addRemoteIceCandidate(candidateInit)
    }
  }

  private stateChange(newState: KooPhoneState): void {
    this._state = newState
    console.info('[KooPhonePlayer] State:', newState)
    this.onStateChange?.(newState)
  }

  private emitError(code: KooPhoneError, message: string): void {
    console.error('[KooPhonePlayer] Error', code, ':', message)
    this.onError?.(code, message)
  }
}

/**
 * 创建 KooPhonePlayer 实例
 */
export function createKooPhonePlayer(): KooPhonePlayer {
  return new KooPhonePlayer()
}
