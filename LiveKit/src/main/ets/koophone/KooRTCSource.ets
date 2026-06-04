import webrtc from '@ohos/webrtc'
import { KooIceServer } from './KooPhoneTypes'

export class KooRTCSource {
  private pcf: webrtc.PeerConnectionFactory | null = null
  private pc: webrtc.RTCPeerConnection | null = null
  private localRenderer: webrtc.NativeVideoRenderer | null = null
  private surfaceId: string = ''
  private rendererSurfaceId: string = ''
  private remoteVideoTrack: webrtc.MediaStreamTrack | null = null
  private pendingCandidates: webrtc.RTCIceCandidateInit[] = []
  private remoteDescSet: boolean = false

  // DataChannel — input channel for sending control events to cloud
  private inputChannel: webrtc.RTCDataChannel | null = null

  // 事件回调
  onDescription: ((desc: webrtc.RTCSessionDescription) => void) | null = null
  onIceCandidate: ((candidate: webrtc.RTCIceCandidate) => void) | null = null
  onConnectionStateChange: ((state: webrtc.RTCPeerConnectionState) => void) | null = null
  onTrack: ((track: webrtc.MediaStreamTrack) => void) | null = null
  onInputChannelOpen: (() => void) | null = null

  /**
   * 创建 PeerConnectionFactory 和 RTCPeerConnection
   */
  open(iceServers: KooIceServer[]): void {
    if (this.pc !== null) {
      console.warn('[KooRTCSource] Already open')
      return
    }

    this.pcf = new webrtc.PeerConnectionFactory()

    // 显式构造每一个 RTCIceServer 对象，避免对象字面量类型推断错误
    const rtcIceServers: webrtc.RTCIceServer[] = []
    for (let i = 0; i < iceServers.length; i++) {
      const s = iceServers[i]
      const server: webrtc.RTCIceServer = {
        urls: [s.uri],
        username: s.usr ?? '',
        credential: s.pwd ?? ''
      }
      rtcIceServers.push(server)
    }

    const fallback: webrtc.RTCIceServer = { urls: ['stun:stun.l.google.com:19302'] }
    const servers: webrtc.RTCIceServer[] = rtcIceServers.length > 0 ? rtcIceServers : [fallback]

    const config: webrtc.RTCConfiguration = {
      iceServers: servers
    }

    this.pc = this.pcf.createPeerConnection(config)
    this.setupPcEvents()

    // 创建 input DataChannel（对应 H5 RTCSource 中的 input channel）
    this.createInputChannel()

    if (this.surfaceId.length > 0) {
      this.rebuildRenderer()
    }

    console.info('[KooRTCSource] PeerConnection created')
  }

  /**
   * 设置 XComponent surfaceId 用于远端视频渲染
   */
  setSurfaceId(surfaceId: string): void {
    if (this.surfaceId === surfaceId && this.rendererSurfaceId === surfaceId) {
      return
    }

    this.surfaceId = surfaceId
    if (surfaceId.length === 0) {
      this.releaseRenderer()
      return
    }

    if (this.pc !== null) {
      this.rebuildRenderer()
    }
  }

  /**
   * 收到服务端 offer，设置 remote description 并自动创建 answer
   */
  async setRemoteDescription(sdp: webrtc.RTCSessionDescription): Promise<void> {
    if (!this.pc) {
      console.error('[KooRTCSource] pc is null')
      return
    }

    try {
      await this.pc.setRemoteDescription(sdp)
      this.remoteDescSet = true
      console.info('[KooRTCSource] Remote description set, type:', sdp.type)

      // 批量添加缓存的 candidates
      await this.flushPendingCandidates()

      if (sdp.type === 'offer') {
        await this.createAnswer()
      }
    } catch (e) {
      console.error('[KooRTCSource] setRemoteDescription failed:', String(e))
    }
  }

  /**
   * 添加远端 ICE candidate（remoteDesc 未就绪时自动缓存）
   */
  addRemoteIceCandidate(candidate: webrtc.RTCIceCandidateInit): void {
    if (!this.remoteDescSet) {
      this.pendingCandidates.push(candidate)
      console.debug('[KooRTCSource] Candidate cached, total pending:', this.pendingCandidates.length)
      return
    }

    this.pc?.addIceCandidate(candidate).then(() => {
      console.debug('[KooRTCSource] Remote candidate added')
    }).catch((e: Error) => {
      console.error('[KooRTCSource] addIceCandidate failed:', e.message)
    })
  }

  /**
   * 通过 input DataChannel 发送二进制输入事件
   */
  sendInputData(data: ArrayBuffer): void {
    if (!this.inputChannel) {
      return
    }
    try {
      this.inputChannel.send(data)
    } catch (e) {
      console.error('[KooRTCSource] sendInputData failed:', String(e))
    }
  }

  /**
   * 关闭并释放所有资源
   * 顺序：renderer.setVideoTrack(null) → renderer.release() → pc.close()
   */
  close(): void {
    this.releaseRenderer()
    this.remoteVideoTrack = null

    if (this.inputChannel) {
      this.inputChannel.close()
      this.inputChannel = null
    }

    if (this.pc) {
      this.pc.close()
      this.pc = null
    }

    this.pcf = null
    this.surfaceId = ''
    this.rendererSurfaceId = ''
    this.remoteDescSet = false
    this.pendingCandidates = []

    console.info('[KooRTCSource] Closed')
  }

  // ==================== 私有方法 ====================

  private setupPcEvents(): void {
    if (!this.pc) {
      return
    }

    this.pc.ontrack = (event: webrtc.RTCTrackEvent) => {
      console.info('[KooRTCSource] Remote track received, kind:', event.track.kind)
      if (event.track.kind === 'video') {
        this.remoteVideoTrack = event.track
        if (!this.localRenderer && this.surfaceId.length > 0) {
          this.rebuildRenderer()
        }
        if (this.localRenderer) {
          this.localRenderer.setVideoTrack(event.track)
          console.info('[KooRTCSource] Video track set to renderer')
        }
        this.onTrack?.(event.track)
      }
    }

    this.pc.onicecandidate = (event: webrtc.RTCPeerConnectionIceEvent) => {
      if (event.candidate) {
        console.debug('[KooRTCSource] Local ICE candidate gathered')
        this.onIceCandidate?.(event.candidate)
      }
    }

    this.pc.onconnectionstatechange = () => {
      const state = this.pc?.connectionState ?? 'closed'
      console.info('[KooRTCSource] Connection state:', state)
      this.onConnectionStateChange?.(state as webrtc.RTCPeerConnectionState)
    }

    this.pc.ondatachannel = (event: webrtc.RTCDataChannelEvent) => {
      // 云端主动创建的 DataChannel（如 input channel from server side）
      console.info('[KooRTCSource] Remote datachannel:', event.channel?.label)
      if (event.channel?.label === 'input') {
        this.setupDataChannel(event.channel)
      }
    }

    this.pc.onsignalingstatechange = () => {
      console.debug('[KooRTCSource] Signaling state:', this.pc?.signalingState)
    }

    this.pc.oniceconnectionstatechange = () => {
      console.debug('[KooRTCSource] ICE connection state:', this.pc?.iceConnectionState)
    }
  }

  private createInputChannel(): void {
    if (!this.pc) {
      return
    }
    try {
      // 客户端主动创建 input channel（与 H5 RTCSource 行为一致）
      this.inputChannel = this.pc.createDataChannel('input', {
        ordered: false,     // 允许乱序，降低延迟
        maxRetransmits: 0   // 不重传，优先低延迟
      })
      this.setupDataChannel(this.inputChannel)
      console.info('[KooRTCSource] Input DataChannel created')
    } catch (e) {
      console.error('[KooRTCSource] createDataChannel failed:', String(e))
    }
  }

  private rebuildRenderer(): void {
    if (this.surfaceId.length === 0) {
      return
    }

    this.releaseRenderer()
    this.localRenderer = new webrtc.NativeVideoRenderer()
    this.localRenderer.init(this.surfaceId)
    this.rendererSurfaceId = this.surfaceId

    if (this.remoteVideoTrack) {
      this.localRenderer.setVideoTrack(this.remoteVideoTrack)
      console.info('[KooRTCSource] Video track rebound to renderer')
    }
    console.info('[KooRTCSource] NativeVideoRenderer initialized, surfaceId:', this.surfaceId)
  }

  private releaseRenderer(): void {
    if (!this.localRenderer) {
      this.rendererSurfaceId = ''
      return
    }

    try {
      this.localRenderer.setVideoTrack(null)
      this.localRenderer.release()
    } catch (e) {
      console.warn('[KooRTCSource] releaseRenderer warning:', String(e))
    }

    this.localRenderer = null
    this.rendererSurfaceId = ''
  }

  private setupDataChannel(channel: webrtc.RTCDataChannel): void {
    this.inputChannel = channel
    channel.onopen = () => {
      console.info('[KooRTCSource] Input DataChannel opened')
      this.onInputChannelOpen?.()
    }
    channel.onclose = () => {
      console.info('[KooRTCSource] Input DataChannel closed')
    }
    channel.onerror = (event: webrtc.RTCErrorEvent) => {
      console.error('[KooRTCSource] DataChannel error:', event?.error?.message ?? 'unknown')
    }
  }

  private async createAnswer(): Promise<void> {
    if (!this.pc) {
      return
    }

    try {
      // pc.createAnswer() 返回 RTCSessionDescriptionInit，需转为 RTCSessionDescription
      const answerInit = await this.pc.createAnswer()
      await this.pc.setLocalDescription(answerInit)
      console.info('[KooRTCSource] Answer created and local description set')

      // 构造完整的 RTCSessionDescription 传给回调
      const answer: webrtc.RTCSessionDescription = {
        type: answerInit.type as 'answer',
        sdp: answerInit.sdp ?? ''
      }
      this.onDescription?.(answer)
    } catch (e) {
      console.error('[KooRTCSource] createAnswer failed:', String(e))
    }
  }

  private async flushPendingCandidates(): Promise<void> {
    if (this.pendingCandidates.length === 0 || !this.pc) {
      return
    }

    console.info('[KooRTCSource] Flushing', this.pendingCandidates.length, 'pending candidates')
    for (let i = 0; i < this.pendingCandidates.length; i++) {
      try {
        await this.pc.addIceCandidate(this.pendingCandidates[i])
      } catch (e) {
        console.error('[KooRTCSource] Flush candidate failed:', String(e))
      }
    }
    this.pendingCandidates = []
  }
}
