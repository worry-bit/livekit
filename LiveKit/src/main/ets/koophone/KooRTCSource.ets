import webrtc from '@ohos/webrtc'
import { KooIceServer } from './KooPhoneTypes'

export class KooRTCSource {
  private pcf: webrtc.PeerConnectionFactory | null = null
  private pc: webrtc.RTCPeerConnection | null = null
  private localRenderer: webrtc.NativeVideoRenderer | null = null
  private surfaceId: string = ''
  private pendingCandidates: webrtc.RTCIceCandidateInit[] = []
  private remoteDescSet: boolean = false

  // 事件回调
  onDescription: ((desc: webrtc.RTCSessionDescription) => void) | null = null
  onIceCandidate: ((candidate: webrtc.RTCIceCandidate) => void) | null = null
  onConnectionStateChange: ((state: webrtc.RTCPeerConnectionState) => void) | null = null
  onTrack: ((track: webrtc.MediaStreamTrack) => void) | null = null

  /**
   * 创建 PeerConnectionFactory 和 RTCPeerConnection
   */
  open(iceServers: KooIceServer[]): void {
    if (this.pc !== null) {
      console.warn('[KooRTCSource] Already open')
      return
    }

    this.pcf = new webrtc.PeerConnectionFactory()

    const rtcIceServers: webrtc.RTCIceServer[] = iceServers.map(s => ({
      urls: [s.uri],
      username: s.usr ?? '',
      credential: s.pwd ?? ''
    }))

    const config: webrtc.RTCConfiguration = {
      iceServers: rtcIceServers.length > 0 ? rtcIceServers : [
        { urls: ['stun:stun.l.google.com:19302'] }
      ]
    }

    this.pc = this.pcf.createPeerConnection(config)
    this.setupPcEvents()

    // 初始化本地渲染器（surfaceId 可能稍后通过 setSurfaceId 设置）
    this.localRenderer = new webrtc.NativeVideoRenderer()

    console.info('[KooRTCSource] PeerConnection created')
  }

  /**
   * 设置 XComponent surfaceId 用于远端视频渲染
   */
  setSurfaceId(surfaceId: string): void {
    this.surfaceId = surfaceId
    if (this.localRenderer && surfaceId) {
      this.localRenderer.init(surfaceId)
      console.info('[KooRTCSource] NativeVideoRenderer initialized, surfaceId:', surfaceId)
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
   * 关闭并释放所有资源
   * 顺序：renderer.setVideoTrack(null) → renderer.release() → pc.close()
   */
  close(): void {
    if (this.localRenderer) {
      this.localRenderer.setVideoTrack(null)
      this.localRenderer.release()
      this.localRenderer = null
    }

    if (this.pc) {
      this.pc.close()
      this.pc = null
    }

    this.pcf = null
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
        if (this.localRenderer && this.surfaceId) {
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

    this.pc.onsignalingstatechange = () => {
      console.debug('[KooRTCSource] Signaling state:', this.pc?.signalingState)
    }

    this.pc.oniceconnectionstatechange = () => {
      console.debug('[KooRTCSource] ICE connection state:', this.pc?.iceConnectionState)
    }
  }

  private async createAnswer(): Promise<void> {
    if (!this.pc) {
      return
    }

    try {
      const answer = await this.pc.createAnswer()
      await this.pc.setLocalDescription(answer)
      console.info('[KooRTCSource] Answer created and local description set')
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
