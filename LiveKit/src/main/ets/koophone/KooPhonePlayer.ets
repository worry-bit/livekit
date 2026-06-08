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
import { KooInputController, TouchAction, KeyAction, TouchPoint, createKooInputController } from './KooInputController'
import { KooUserMedia, CameraStateEvent, createKooUserMedia } from './KooUserMedia'

interface InitPayload {
  sole: boolean
  mode: string
  role: string
  profile_name: string
  network_type: string
  profile: number
  volume: number
  vcodec: string
  venctype: number
  frame_aspect: string
  keeping_time: number
  user_agent: string
  client_version: string
  uuid: string
  sessionid: string
  streamingid: string
  room_session: string
}

interface CandidatePayload {
  label: number | null
  id: string | null
  candidate: string
}

// offer/answer SDP payload 结构
interface SdpPayload {
  type: string
  sdp: string
}

export class KooPhonePlayer {
  private _state: KooPhoneState = KooPhoneState.NEW
  private params: KooPhoneParams | null = null
  private remoteId: string = ''
  private vcodec: string = 'H264'
  private streamingId: string = ''
  private sessionId: string = ''
  private uuid: string = ''

  private signalClient: KooSignalClient = new KooSignalClient()
  private rtcSource: KooRTCSource = new KooRTCSource()
  readonly userMedia: KooUserMedia = createKooUserMedia()
  readonly inputController: KooInputController = createKooInputController()

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
    // 生成会话标识（对应 H5 _open() 中的 streamingid/sessionid/uuid）
    this.streamingId = this.randomUuid()
    this.sessionId = params.sessionId ?? params.token
    this.uuid = params.uuid ?? this.randomUuid()

    this.setupUserMediaHandlers()
    this.setupSignalHandlers(surfaceId)
    this.setupRTCHandlers()

    this.stateChange(KooPhoneState.CONNECTING)

    // 对应 H5 _connect() opts.query 构建逻辑
    let query = `authtype=token&boxid=${params.boxId}&token=${params.token}`
    query += `&sessionid=${this.sessionId}`
    query += `&streamingid=${this.streamingId}`
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
    this.userMedia.closeCamera()

    this.remoteId = ''
    this.streamingId = ''
    this.sessionId = ''
    this.uuid = ''
    this.params = null

    this.stateChange(KooPhoneState.CLOSED)
    console.info('[KooPhonePlayer] Closed')
  }

  // ==================== 私有方法 ====================

  private setupUserMediaHandlers(): void {
    // 摄像头成功打开 → 将本地轨道添加到 PeerConnection 并重协商
    this.userMedia.onSuccess = (action: string, type: string, track: webrtc.MediaStreamTrack | null) => {
      if (action === 'start' && type === 'video' && track) {
        console.info('[KooPhonePlayer] Local camera track ready, adding to PC')
        this.rtcSource.addLocalVideoTrack(track).then(() => {
          // 对应 H5 _onCameraTrackAdded()：通知云端摄像头已就绪
          this.inputController.sendTextMessage({
            "type": 'camera_track_added',
            "camera_id": this.userMedia.getCameraId()
          } as Record<string, Object>)
        })
      } else if (action === 'stop' && type === 'video') {
        this.rtcSource.removeLocalVideoTrack()
      }
    }

    this.userMedia.onError = (action: string, type: string, err: string) => {
      console.error('[KooPhonePlayer] UserMedia error:', action, type, err)
    }
  }

  private setupSignalHandlers(surfaceId: string): void {
    this.signalClient.onAuthorize = (authorized: boolean) => {
      if (!authorized) {
        this.emitError(KooPhoneError.SIGNAL_AUTH_FAILED, 'Signal authorization failed')
        this.close()
        return
      }

      console.info('[KooPhonePlayer] Authorized')
      this.stateChange(KooPhoneState.AUTHORIZED)

      // AUTHORIZED 后客户端主动发 start 请求
      // H5: connection.start({ room: boxid, times: 0 })
      this.signalClient.emitStart(this.params?.boxId ?? '', 0)
    }

    this.signalClient.onStart = (payload: KooStartPayload) => {
      console.info('[KooPhonePlayer] Start received, streamId:', payload.streamId)
      this.remoteId = payload.streamId
      this.vcodec = payload.vcodec ?? 'H264'

      // 初始化 RTCPeerConnection
      this.stateChange(KooPhoneState.PEER_CONNECTING)
      this.rtcSource.open(this.params?.iceServers ?? [])
      this.rtcSource.setSurfaceId(surfaceId)

      // 将共用的 PeerConnectionFactory 传给 userMedia，供相机采集使用
      const pcf = this.rtcSource.getPeerConnectionFactory()
      if (pcf) {
        this.userMedia.setPeerConnectionFactory(pcf)
      }

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
      const payload: Record<string, Object> = {
        "type": desc.type,
        "sdp": desc.sdp
      }
      this.signalClient.emitMessage('answer', this.remoteId, payload)
    }

    this.rtcSource.onIceCandidate = (candidate: webrtc.RTCIceCandidate) => {
      // 发送本地 ICE candidate（与 H5 _onLocalIceCandidate 格式一致）
      const payload: Record<string, Object> = {
        "label": candidate.sdpMLineIndex ?? 0,
        "id": candidate.sdpMid ?? '',
        "candidate": candidate.candidate
      }
      this.signalClient.emitMessage('candidate', this.remoteId, payload)
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

    // DataChannel 就绪后将 sendInputData 绑定给 InputController
    // 同时注册 onDcMessage，接收云端下行控制消息（camera_state 等）
    this.rtcSource.onInputChannelOpen = () => {
      console.info('[KooPhonePlayer] Input DataChannel ready, binding InputController')
      this.inputController.setSendFunction((data: ArrayBuffer) => {
        this.rtcSource.sendInputData(data)
      })
    }

    // 对应 H5 _onInputChannelMessage → _handleExtendMessage
    // camera_state 由 DataChannel 下行，不走信令
    this.rtcSource.onDcMessage = (msgType: string, msg: Record<string, Object>) => {
      if (msgType === 'camera_state') {
        this.handleCameraState(msg)
      } else if (msgType === 'app_message') {
        // app_message 是云端 APP 层透传消息，data 字段是实际内容
        console.info('[KooPhonePlayer] app_message data:', JSON.stringify(msg['data'] ?? msg))
      } else {
        console.info('[KooPhonePlayer] Unhandled DC message type:', msgType)
      }
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
      profile: 2,
      volume: this.params.volume ?? 100,
      vcodec: this.vcodec,
      venctype: 0,
      frame_aspect: '16:9',
      keeping_time: 60,
      user_agent: 'HarmonyOS',
      client_version: 'harmony-sdk-1.0.0',
      uuid: this.uuid,
      sessionid: this.sessionId,
      streamingid: this.streamingId,
      room_session: ''
    }

    // base64 编码（与 H5 btoa(JSON.stringify(params)) 一致）
    const jsonStr = JSON.stringify(initPayload)
    console.info('[KooPhonePlayer] Init payload JSON:', jsonStr)
    const encoder = new util.TextEncoder()
    const bytes = encoder.encodeInto(jsonStr)
    const base64Helper = new util.Base64Helper()
    const encoded = base64Helper.encodeToStringSync(bytes)
    console.info('[KooPhonePlayer] Init payload base64:', encoded)

    console.info('[KooPhonePlayer] Sending init, remoteId:', this.remoteId,
      'uuid:', this.uuid, 'streamingId:', this.streamingId)
    this.signalClient.emitData('init', this.remoteId, encoded)
  }

  private handleSignalMessage(message: KooSignalMessage): void {
    const type = message.type
    console.info('[KooPhonePlayer] Signal message type:', type,
      'hasPayload:', !!message.payload, 'hasData:', !!message.data)

    // 对应 H5 CloudPlayer._onRemoteMessage()：
    // payload 优先取 message.payload，若为空则从 message.data（base64 JSON）解码
    const raw = this.resolvePayload(message)

    if (type === 'offer') {
      console.info('[KooPhonePlayer] Received offer, raw:', JSON.stringify(raw))
      if (!raw) {
        console.error('[KooPhonePlayer] offer payload is empty, drop')
        return
      }
      const sdpPayload: SdpPayload = {
        type: raw['type'] as string,
        sdp: raw['sdp'] as string
      }
      console.info('[KooPhonePlayer] offer sdp type:', sdpPayload.type,
        'sdp length:', sdpPayload.sdp?.length ?? 0)
      const sdp: webrtc.RTCSessionDescription = {
        type: sdpPayload.type as 'offer',
        sdp: sdpPayload.sdp,
        toJSON: (): webrtc.RTCSessionDescriptionInit => {
          throw new Error('Function not implemented.')
        }
      }
      this.rtcSource.setRemoteDescription(sdp)
    } else if (type === 'answer') {
      console.info('[KooPhonePlayer] Received answer')
      if (!raw) {
        return
      }
      const sdpPayload: SdpPayload = {
        type: raw['type'] as string,
        sdp: raw['sdp'] as string
      }
      const sdp: webrtc.RTCSessionDescription = {
        type: sdpPayload.type as 'answer',
        sdp: sdpPayload.sdp,
        toJSON: (): webrtc.RTCSessionDescriptionInit => {
          throw new Error('Function not implemented.')
        }
      }
      this.rtcSource.setRemoteDescription(sdp)
    } else if (type === 'candidate') {
      if (!raw) {
        return
      }
      const candidatePayload: CandidatePayload = {
        label: raw['label'] as number,
        id: raw['id'] as string,
        candidate: raw['candidate'] as string
      }
      console.info('[KooPhonePlayer] Remote candidate, id:', candidatePayload.id)
      const candidateInit: webrtc.RTCIceCandidateInit = {
        candidate: candidatePayload.candidate,
        sdpMLineIndex: candidatePayload.label ?? 0,
        sdpMid: candidatePayload.id ?? ''
      }
      this.rtcSource.addRemoteIceCandidate(candidateInit)
    } else if (type === 'init') {
      // init 回复无需处理，对应 H5 _onInitReply 只打 log
      console.info('[KooPhonePlayer] Received init reply')
    } else {
      console.info('[KooPhonePlayer] Unhandled signal message type:', type)
    }
  }

  /**
   * 处理相机状态控制消息（对应 H5 CloudPlayer._handleCameraState）
   * 通过 DataChannel 的 WebTextMessage 传来，type='camera_state'
   */
  private handleCameraState(raw: Record<string, Object>): void {
    const cameraId = raw['camera_id'] as number
    const width = (raw['width'] as number) ?? 640
    const height = (raw['height'] as number) ?? 480
    const fps = (raw['fps'] as number) ?? 24

    if (cameraId >= 0) {
      if (this.userMedia.isCameraOn() || this.userMedia.isCameraOpening()) {
        console.warn('[KooPhonePlayer] Camera already on/opening, skip open request')
        return
      }
      console.info('[KooPhonePlayer] Opening camera:', cameraId, width, 'x', height, 'fps:', fps)
      this.userMedia.openCamera(cameraId, width, height, fps)
    } else {
      console.info('[KooPhonePlayer] Closing camera')
      this.userMedia.closeCamera()
    }
  }

  /**
   * 解析信令消息 payload：
   * 对应 H5 CloudPlayer._onRemoteMessage() 第 806-808 行：
   *   if (!payload && !!message.data) payload = JSON.parse(Base64.decode(message.data))
   */
  private resolvePayload(message: KooSignalMessage): Record<string, Object> | null {
    if (message.payload) {
      return message.payload
    }
    if (message.data) {
      try {
        const base64Helper = new util.Base64Helper()
        const bytes = base64Helper.decodeSync(message.data)
        const decoder = new util.TextDecoder()
        const jsonStr = decoder.decodeToString(bytes)
        console.info('[KooPhonePlayer] Decoded data field:', jsonStr.substring(0, 100))
        return JSON.parse(jsonStr) as Record<string, Object>
      } catch (e) {
        console.error('[KooPhonePlayer] Failed to decode message.data:', String(e))
      }
    }
    return null
  }

  private randomUuid(): string {
    let timestamp = Date.now(); // 鸿蒙支持 Date.now()
    let uuid = 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx';

    return uuid.replace(/[xy]/g, (char: string) => {
      const random = (timestamp + Math.random() * 16) % 16 | 0;
      timestamp = Math.floor(timestamp / 16);
      return (char === 'x' ? random : (random & 0x3 | 0x8)).toString(16);
    });
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
