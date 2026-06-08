/**
 * LiveKit WebRTC 引擎
 * 基于 @ohos/webrtc 官方 ArkTS API
 * 
 * API 文档: src/ohos_webrtc/sdk/ohos/api/libwebrtc.md
 */

import {
  SessionDescription,
  TrickleRequest,
  ICEServer,
  SignalTarget,
  AudioCaptureOptions,
  VideoCaptureOptions
} from './types'
import { SignalClient } from './SignalClient'

// @ohos/webrtc 官方库 - ArkTS API
import webrtc from '@ohos/webrtc'

// 音频路由控制
import audio from '@ohos.multimedia.audio'

/**
 * RTCEngine 事件委托
 */
export interface RTCEngineDelegate {
  onTrackAdded(track: webrtc.MediaStreamTrack, streams: webrtc.MediaStream[]): void
  onTrackRemoved(track: webrtc.MediaStreamTrack): void
  onConnectionStateChanged(state: webrtc.RTCPeerConnectionState): void
}

/**
 * RTCEngine - WebRTC 引擎
 * 管理 PeerConnection 和媒体轨道
 */
export class RTCEngine {
  private signalClient: SignalClient
  private delegate: RTCEngineDelegate | null = null
  
  // WebRTC 工厂
  private peerConnectionFactory: webrtc.PeerConnectionFactory | null = null
  
  // 两个 PeerConnection：发布者和订阅者
  private publisherPC: webrtc.RTCPeerConnection | null = null
  private subscriberPC: webrtc.RTCPeerConnection | null = null
  
  // ICE 配置
  private iceServers: ICEServer[] = []
  private subscriberPrimary: boolean = true
  
  // 本地音频
  private audioSource: webrtc.AudioSource | null = null
  private audioTrack: webrtc.AudioTrack | null = null

  // ICE Candidate 缓存（用于处理时序问题）
  private pendingPublisherCandidates: webrtc.RTCIceCandidateInit[] = []
  private pendingSubscriberCandidates: webrtc.RTCIceCandidateInit[] = []
  private publisherRemoteDescSet: boolean = false
  private subscriberRemoteDescSet: boolean = false

  // 协商锁，防止并发协商
  private isNegotiating: boolean = false
  private negotiationPending: boolean = false

  // 缓存在 subscriberPC 就绪前收到的 offer
  private pendingOffer: SessionDescription | null = null

  // 音频路由
  private audioRoutingManager: audio.AudioRoutingManager | null = null

  // 本地视频
  private videoSource: webrtc.VideoSource | null = null
  private videoTrack: webrtc.VideoTrack | null = null
  private localRenderer: webrtc.NativeVideoRenderer | null = null
  private currentFacingMode: string = 'environment'

  constructor(signalClient: SignalClient) {
    this.signalClient = signalClient
    this.setupSignalHandlers()
  }

  /**
   * 设置事件委托
   */
  setDelegate(delegate: RTCEngineDelegate): void {
    this.delegate = delegate
  }

  /**
   * 配置 ICE 服务器
   */
  configure(iceServers: ICEServer[], subscriberPrimary: boolean): void {
    this.iceServers = iceServers
    this.subscriberPrimary = subscriberPrimary
  }

  /**
   * 创建 PeerConnections
   */
  async createPeerConnections(): Promise<void> {
    // 创建 PeerConnectionFactory
    // 注意：暂时不使用自定义 AudioDeviceModule，因为会导致崩溃
    // TODO: 后续可以尝试其他方式切换到扬声器输出
    this.peerConnectionFactory = new webrtc.PeerConnectionFactory()
    
    // RTCConfiguration
    const config: webrtc.RTCConfiguration = {

      iceServers: this.iceServers.map(server => {
        // 确保 urls 是字符串数组格式
        let urlsArray: string[]
        if (typeof server.urls === 'string') {
          urlsArray = [server.urls]
        } else if (Array.isArray(server.urls)) {
          urlsArray = server.urls
        } else {
          urlsArray = []
        }

        return {
          urls: urlsArray,
          username: server.username || '',
          credential: server.credential || ''
        } as webrtc.RTCIceServer
      }),
      iceTransportPolicy: 'all',
      bundlePolicy: 'max-bundle',
      rtcpMuxPolicy: 'require'
    }

    // 创建发布者 PeerConnection
    this.publisherPC = this.peerConnectionFactory.createPeerConnection(config)
    this.setupPeerConnection(this.publisherPC, SignalTarget.PUBLISHER)

    // 创建订阅者 PeerConnection
    this.subscriberPC = this.peerConnectionFactory.createPeerConnection(config)
    this.setupPeerConnection(this.subscriberPC, SignalTarget.SUBSCRIBER)
    
    console.info('[RTCEngine] PeerConnections created, checking for pending offer...')

    // 处理在 subscriberPC 就绪前缓存的 offer
    if (this.pendingOffer) {
      console.info('[RTCEngine] Processing cached offer, sdp length:', this.pendingOffer.sdp?.length || 0)
      const offer = this.pendingOffer
      this.pendingOffer = null
      await this.handleRemoteOffer(offer)
    } else {
      console.info('[RTCEngine] No pending offer to process')
    }
  }

  /**
   * 发布音频
   */
  async publishAudio(options?: AudioCaptureOptions): Promise<void> {
    if (!this.peerConnectionFactory || !this.publisherPC) {
      throw new Error('PeerConnectionFactory not initialized')
    }

    try {
      // 创建音频源（使用麦克风）
      const constraints: webrtc.MediaTrackConstraints = {
        echoCancellation: options?.echoCancellation ?? true,
        autoGainControl: options?.autoGainControl ?? true,
        noiseSuppression: options?.noiseSuppression ?? true
      }
      
      this.audioSource = this.peerConnectionFactory.createAudioSource(constraints)
      
      // 创建音频轨道
      const trackId = `audio_${Date.now()}`
      this.audioTrack = this.peerConnectionFactory.createAudioTrack(trackId, this.audioSource)
      
      // 1. 先发送 AddTrackRequest 通知服务器
      // LiveKit 协议要求：在添加轨道到 PeerConnection 之前，必须先通知服务器
      // TrackType: AUDIO=0, VIDEO=1
      // TrackSource: MICROPHONE=2, CAMERA=1
      this.signalClient.sendAddTrack(trackId, 'audio', 0, 2)
      console.info('[RTCEngine] Sent AddTrackRequest for:', trackId)
      
      // 2. 添加轨道到发布者 PeerConnection
      // 添加 track 会自动触发 onnegotiationneeded 事件
      this.publisherPC.addTrack(this.audioTrack)
      
      console.info('[RTCEngine] Audio track added:', trackId)

    } catch (error) {
      console.error('[RTCEngine] Publish audio failed:', error)
      // throw error
    }
  }

  /**
   * 取消发布音频
   */
  async unpublishAudio(): Promise<void> {
    if (!this.publisherPC || !this.audioTrack) {
      return
    }

    try {
      // 获取发送器并移除
      const senders = this.publisherPC.getSenders()
      for (let i = 0; i < senders.length; i++) {
        if (senders[i].track === this.audioTrack) {
          this.publisherPC.removeTrack(senders[i])
          break
        }
      }

      // 停止轨道
      this.audioTrack.enabled = false
      this.audioTrack = null
      this.audioSource = null

      // removeTrack 会自动触发 onnegotiationneeded 事件
      console.info('[RTCEngine] Audio unpublished')

    } catch (error) {
      console.error('[RTCEngine] Unpublish audio failed:', error)
      // throw error
    }
  }

  /**
   * 发布视频（摄像头采集 + 本地预览）
   * @param surfaceId 来自 XComponent.onLoad 的 surfaceId，用于本地预览渲染
   * @param options 采集参数，默认 1280x720@30fps 后置摄像头
   */
  async publishVideo(surfaceId: string, options?: VideoCaptureOptions): Promise<void> {
    if (!this.peerConnectionFactory || !this.publisherPC) {
      throw new Error('PeerConnectionFactory not initialized')
    }

    try {
      const width = options?.width ?? 1280
      const height = options?.height ?? 720
      const frameRate = options?.frameRate ?? 30
      const facingMode = options?.facingMode ?? 'environment'
      this.currentFacingMode = facingMode

      // 1. 通知服务器即将发布视频轨道（TrackType.VIDEO=1, TrackSource.CAMERA=1）
      const trackId = `video_${Date.now()}`
      this.signalClient.sendAddTrack(trackId, 'video', 1, 1)
      console.info('[RTCEngine] Sent AddTrackRequest for video:', trackId)

      // 2. 创建 VideoSource，传入采集约束（含摄像头方向），内部自动开始采集
      const constraints: webrtc.MediaTrackConstraints = {
        width: width,
        height: height,
        frameRate: frameRate,
        facingMode: facingMode
      }
      this.videoSource = this.peerConnectionFactory.createVideoSource(constraints, false)
      console.info('[RTCEngine] VideoSource created, capturing started')

      // 3. 创建 VideoTrack
      this.videoTrack = this.peerConnectionFactory.createVideoTrack(trackId, this.videoSource)

      // 4. 创建本地渲染器并绑定到 XComponent surfaceId
      this.localRenderer = new webrtc.NativeVideoRenderer()
      this.localRenderer.init(surfaceId)
      this.localRenderer.setVideoTrack(this.videoTrack)
      console.info('[RTCEngine] NativeVideoRenderer initialized for surfaceId:', surfaceId)

      // 5. 将视频轨道添加到发布者 PeerConnection，触发 onnegotiationneeded
      this.publisherPC.addTrack(this.videoTrack)
      console.info('[RTCEngine] Video track added:', trackId)

    } catch (error) {
      console.error('[RTCEngine] Publish video failed:', error)
      throw new Error(String(error))
    }
  }

  /**
   * 取消发布视频，释放摄像头和渲染器资源
   */
  async unpublishVideo(): Promise<void> {
    if (!this.publisherPC || !this.videoTrack) {
      return
    }

    try {
      // 1. 解除渲染器与视频轨道的绑定，释放渲染器（必须在 removeTrack 之前）
      if (this.localRenderer) {
        this.localRenderer.setVideoTrack(null)
        this.localRenderer.release()
        this.localRenderer = null
        console.info('[RTCEngine] NativeVideoRenderer released')
      }

      // 2. 停止视频轨道，释放摄像头采集资源
      if (this.videoTrack) {
        this.videoTrack.stop()
      }
      if (this.videoSource) {
        this.videoSource = null
        console.info('[RTCEngine] VideoSource cleared')
      }

      // 3. 从 PeerConnection 移除视频轨道（触发重新协商）
      if (this.publisherPC && this.videoTrack) {
        const senders = this.publisherPC.getSenders()
        for (let i = 0; i < senders.length; i++) {
          if (senders[i].track === this.videoTrack) {
            this.publisherPC.removeTrack(senders[i])
            break
          }
        }
      }

      this.videoTrack = null
      console.info('[RTCEngine] Video unpublished')

    } catch (error) {
      console.error('[RTCEngine] Unpublish video failed:', error)
    }
  }

  /**
   * 切换前/后摄像头：重建 VideoSource（新 facingMode）+ replaceTrack
   */
  async switchCamera(): Promise<void> {
    if (!this.publisherPC || !this.peerConnectionFactory || !this.videoTrack) {
      console.warn('[RTCEngine] switchCamera called but video not published')
      return
    }

    const newFacingMode = this.currentFacingMode === 'environment' ? 'user' : 'environment'
    const prevVideoTrack = this.videoTrack

    try {
      // 找到当前视频发送器
      const senders = this.publisherPC.getSenders()
      let videoSender: webrtc.RTCRtpSender | null = null
      for (let i = 0; i < senders.length; i++) {
        if (senders[i].track && senders[i].track!.kind === 'video') {
          videoSender = senders[i]
          break
        }
      }
      if (!videoSender) {
        console.error('[RTCEngine] switchCamera: video sender not found')
        return
      }

      // 创建新 VideoSource（新方向）
      const newVideoSource = this.peerConnectionFactory.createVideoSource(
        { facingMode: newFacingMode }, false
      )
      const newTrackId = `video_${Date.now()}`
      const newVideoTrack = this.peerConnectionFactory.createVideoTrack(newTrackId, newVideoSource)

      // 替换发送器中的轨道（不触发重新协商）
      await videoSender.replaceTrack(newVideoTrack)

      // 更新渲染器绑定
      if (this.localRenderer) {
        this.localRenderer.setVideoTrack(newVideoTrack)
      }

      // 更新成员变量
      this.videoSource = newVideoSource
      this.videoTrack = newVideoTrack
      this.currentFacingMode = newFacingMode

      // 释放旧资源
      prevVideoTrack.stop()

      console.info('[RTCEngine] Camera switched to:', newFacingMode)
    } catch (error) {
      console.error('[RTCEngine] switchCamera failed:', error)
    }
  }

  /**
   * 设置音频静音状态
   */
  setAudioMuted(muted: boolean): void {
    if (this.audioTrack) {
      this.audioTrack.enabled = !muted
      console.info(`[RTCEngine] Audio ${muted ? 'muted' : 'unmuted'}`)
    }
  }

  /**
   * 关闭引擎
   */
  async close(): Promise<void> {
    // 停止设备变化监听
    this.stopDeviceChangeListener()

    // 停止视频
    if (this.localRenderer) {
      this.localRenderer.setVideoTrack(null)
      this.localRenderer.release()
      this.localRenderer = null
    }
    if (this.videoTrack) {
      this.videoTrack.stop()
      this.videoTrack = null
    }
    if (this.videoSource) {
      this.videoSource = null
    }

    // 停止音频
    if (this.audioTrack) {
      this.audioTrack.enabled = false
      this.audioTrack = null
    }
    this.audioSource = null
    
    // 关闭 PeerConnections
    if (this.publisherPC) {
      this.publisherPC.close()
      this.publisherPC = null
    }
    
    if (this.subscriberPC) {
      this.subscriberPC.close()
      this.subscriberPC = null
    }
    
    this.peerConnectionFactory = null
    
    // 重置状态
    this.pendingPublisherCandidates = []
    this.pendingSubscriberCandidates = []
    this.publisherRemoteDescSet = false
    this.subscriberRemoteDescSet = false
    this.isNegotiating = false
    this.pendingOffer = null
    
    console.info('[RTCEngine] Closed')
  }

  // ==================== 私有方法 ====================

  /**
   * 设置信令处理器
   */
  private setupSignalHandlers(): void {
    // 处理服务端 Offer（订阅者）
    this.signalClient.on('offer', async (response) => {
      console.info('[RTCEngine] Received offer event, has offer:', !!response.offer, 
        ', subscriberPC ready:', !!this.subscriberPC)
      if (response.offer) {
        if (this.subscriberPC) {
          console.info('[RTCEngine] Processing offer immediately')
          await this.handleRemoteOffer(response.offer)
        } else {
          // subscriberPC 还未创建，先缓存 offer
          console.info('[RTCEngine] subscriberPC not ready, caching offer, sdp length:', 
            response.offer.sdp?.length || 0)
          this.pendingOffer = response.offer
        }
      }
    })

    // 处理服务端 Answer（发布者）
    this.signalClient.on('answer', async (response) => {
      if (response.answer && this.publisherPC) {
        await this.handleRemoteAnswer(response.answer)
      }
    })

    // 处理 ICE Candidate
    this.signalClient.on('trickle', async (response) => {
      if (response.trickle) {
        await this.handleRemoteCandidate(response.trickle)
      }
    })
  }

  /**
   * 设置 PeerConnection 事件处理
   */
  private setupPeerConnection(pc: webrtc.RTCPeerConnection, target: SignalTarget): void {
    const targetName = target === SignalTarget.PUBLISHER ? 'pub' : 'sub'
    
    // ICE Candidate
    pc.onicecandidate = (event: webrtc.RTCPeerConnectionIceEvent) => {
      console.info(`[RTCEngine] onicecandidate (${targetName}):`, event.candidate ? 'has candidate' : 'null/complete')
      if (event.candidate) {
        const candidateInit = JSON.stringify({
          candidate: event.candidate.candidate,
          sdpMLineIndex: event.candidate.sdpMLineIndex,
          sdpMid: event.candidate.sdpMid
        })
        console.info(`[RTCEngine] Sending ICE candidate (${targetName}):`, event.candidate.candidate?.substring(0, 50))
        this.signalClient.sendCandidate(candidateInit, target)
      }
    }
    
    // ICE Gathering 状态
    pc.onicegatheringstatechange = () => {
      console.info(`[RTCEngine] ICE gathering state (${targetName}): ${pc.iceGatheringState}`)
    }

    // ICE 连接状态
    pc.oniceconnectionstatechange = () => {
      const targetName = target === SignalTarget.PUBLISHER ? 'pub' : 'sub'
      console.info(`[RTCEngine] ICE state (${targetName}): ${pc.iceConnectionState}`)
    }

    // 连接状态
    pc.onconnectionstatechange = () => {
      const targetName = target === SignalTarget.PUBLISHER ? 'pub' : 'sub'
      console.info(`[RTCEngine] Connection state (${targetName}): ${pc.connectionState}`)
      this.delegate?.onConnectionStateChanged(pc.connectionState)
    }

    // 收到远程轨道（仅订阅者）
    if (target === SignalTarget.SUBSCRIBER) {
      pc.ontrack = (event: webrtc.RTCTrackEvent) => {
        console.info('[RTCEngine] Remote track received:', event.track.kind)
        // webrtc.MediaStream[]
        this.delegate?.onTrackAdded(event.track, event.streams as webrtc.MediaStream[])
      }
    }

    // 需要协商（仅发布者）
    pc.onnegotiationneeded = async () => {
      if (target === SignalTarget.PUBLISHER) {
        console.info('[RTCEngine] Negotiation needed')
        await this.negotiate()
      }
    }
  }

  /**
   * 协商 SDP（发布者）
   */
  private async negotiate(): Promise<void> {
    if (!this.publisherPC) {
      return
    }

    // 防止并发协商：记录 pending，等当前协商完成后再触发一次
    if (this.isNegotiating) {
      console.info('[RTCEngine] Negotiation already in progress, will retry after current completes')
      this.negotiationPending = true
      return
    }

    // 检查状态是否适合创建 offer（只有 stable 状态才能发起新协商）
    const state = this.publisherPC.signalingState
    if (state !== 'stable') {
      console.info('[RTCEngine] Signaling state not stable:', state, ', skipping negotiation')
      return
    }

    this.isNegotiating = true

    try {
      // 创建 Offer
      const offerOptions: webrtc.RTCOfferOptions = {
        iceRestart: false
      }
      const offer = await this.publisherPC.createOffer(offerOptions)
      
      // 设置本地描述
      await this.publisherPC.setLocalDescription(offer)
      
      // 发送到服务端
      this.signalClient.sendOffer({
        type: 'offer',
        sdp: offer.sdp ? offer.sdp : ''
      })
      
      console.info('[RTCEngine] Sent offer')
    } catch (error) {
      console.error('[RTCEngine] Negotiate error:', error)
    } finally {
      this.isNegotiating = false
      if (this.negotiationPending) {
        this.negotiationPending = false
        console.info('[RTCEngine] Retrying pending negotiation')
        await this.negotiate()
      }
    }
  }

  /**
   * 处理远程 Offer（订阅者）
   */
  private async handleRemoteOffer(offer: SessionDescription): Promise<void> {
    if (!this.subscriberPC) {
      console.warn('[RTCEngine] handleRemoteOffer: subscriberPC is null')
      return
    }

    try {
      console.info('[RTCEngine] handleRemoteOffer: setting remote description...')
      // 设置远程描述
      const remoteDesc: webrtc.RTCSessionDescription = {
        type: offer.type,
        sdp: offer.sdp,
        toJSON: (): webrtc.RTCSessionDescriptionInit => {
          throw new Error('Function not implemented.')
        }
      }
      await this.subscriberPC.setRemoteDescription(remoteDesc)
      console.info('[RTCEngine] handleRemoteOffer: remote description set')
      
      // 标记已设置远程描述，并处理缓存的 candidates
      this.subscriberRemoteDescSet = true
      await this.flushPendingCandidates(false)
      
      // 创建 Answer
      console.info('[RTCEngine] handleRemoteOffer: creating answer...')
      const answer = await this.subscriberPC.createAnswer()
      console.info('[RTCEngine] handleRemoteOffer: answer created')
      
      // 设置本地描述 - 这会触发 ICE gathering
      console.info('[RTCEngine] handleRemoteOffer: setting local description (will trigger ICE gathering)...')
      await this.subscriberPC.setLocalDescription(answer)
      console.info('[RTCEngine] handleRemoteOffer: local description set, iceGatheringState:', this.subscriberPC.iceGatheringState)
      
      // 发送到服务端
      this.signalClient.sendAnswer({
        type: 'answer',
        sdp: answer.sdp ? answer.sdp : ''
      })
      
      console.info('[RTCEngine] Sent answer, sdp length:', answer.sdp?.length || 0)
    } catch (error) {
      console.error('[RTCEngine] Handle offer error:', error)
    }
  }

  /**
   * 处理远程 Answer（发布者）
   */
  private async handleRemoteAnswer(answer: SessionDescription): Promise<void> {
    if (!this.publisherPC) {
      return
    }

    try {
      const remoteDesc: webrtc.RTCSessionDescription = {
        type: answer.type,
        sdp: answer.sdp,
        toJSON: (): webrtc.RTCSessionDescriptionInit => {
          throw new Error('Function not implemented.')
        }
      }
      await this.publisherPC.setRemoteDescription(remoteDesc)
      
      // 标记已设置远程描述，并处理缓存的 candidates
      this.publisherRemoteDescSet = true
      await this.flushPendingCandidates(true)
      
      console.info('[RTCEngine] Remote answer set')
    } catch (error) {
      console.error('[RTCEngine] Handle answer error:', error)
    }
  }

  /**
   * 处理远程 ICE Candidate
   */
  private async handleRemoteCandidate(trickle: TrickleRequest): Promise<void> {
    const isPublisher = trickle.target === SignalTarget.PUBLISHER
    const pc = isPublisher ? this.publisherPC : this.subscriberPC
    
    if (!pc) {
      return
    }

    try {
      const candidateInit: webrtc.RTCIceCandidateInit = JSON.parse(trickle.candidateInit)
      
      // 检查 remote description 是否已设置
      const remoteDescSet = isPublisher ? this.publisherRemoteDescSet : this.subscriberRemoteDescSet
      
      if (remoteDescSet) {
        // 已设置，直接添加
        await pc.addIceCandidate(candidateInit)
        console.debug('[RTCEngine] Remote candidate added (', isPublisher ? 'pub' : 'sub', ')')
      } else {
        // 未设置，缓存起来
        if (isPublisher) {
          this.pendingPublisherCandidates.push(candidateInit)
        } else {
          this.pendingSubscriberCandidates.push(candidateInit)
        }
        console.debug('[RTCEngine] Remote candidate cached (', isPublisher ? 'pub' : 'sub', ')')
      }
    } catch (error) {
      console.error('[RTCEngine] Add candidate error:', error)
    }
  }

  /**
   * 处理缓存的 ICE Candidates
   */
  private async flushPendingCandidates(isPublisher: boolean): Promise<void> {
    const pc = isPublisher ? this.publisherPC : this.subscriberPC
    const pending = isPublisher ? this.pendingPublisherCandidates : this.pendingSubscriberCandidates
    
    if (!pc || pending.length === 0) {
      return
    }

    console.info('[RTCEngine] Flushing', pending.length, 'cached candidates (', isPublisher ? 'pub' : 'sub', ')')
    
    for (let i = 0; i < pending.length; i++) {
      try {
        await pc.addIceCandidate(pending[i])
      } catch (error) {
        console.error('[RTCEngine] Add cached candidate error:', error)
      }
    }
    
    // 清空缓存
    if (isPublisher) {
      this.pendingPublisherCandidates = []
    } else {
      this.pendingSubscriberCandidates = []
    }
  }

  /**
   * 切换到扬声器输出
   * 使用 HarmonyOS 音频路由 API
   */
  async enableSpeakerphone(enable: boolean): Promise<void> {
    try {
      const audioManager = audio.getAudioManager()
      const routingManager = audioManager.getRoutingManager()

      // CommunicationDeviceType: SPEAKER = 2
      const deviceType = enable ? audio.CommunicationDeviceType.SPEAKER : 0
      await routingManager.setCommunicationDevice(deviceType, enable)
      console.info('[RTCEngine] Set communication device to:', enable ? 'SPEAKER' : 'DEFAULT')
    } catch (error) {
      console.error('[RTCEngine] enableSpeakerphone error:', error)
    }
  }

  /**
   * 检测当前是否有耳机连接（有线耳机 / 蓝牙耳机）
   */
  isHeadsetConnected(): boolean {
    try {
      const audioManager = audio.getAudioManager()
      const routingManager = audioManager.getRoutingManager()
      const devices = routingManager.getDevicesSync(audio.DeviceFlag.OUTPUT_DEVICES_FLAG)
      for (let i = 0; i < devices.length; i++) {
        const deviceType = devices[i].deviceType
        if (deviceType === audio.DeviceType.WIRED_HEADSET ||
          deviceType === audio.DeviceType.WIRED_HEADPHONES ||
          deviceType === audio.DeviceType.BLUETOOTH_A2DP ||
          deviceType === audio.DeviceType.BLUETOOTH_SCO ||
          deviceType === audio.DeviceType.USB_HEADSET) {
          console.info('[RTCEngine] Headset detected, deviceType:', deviceType)
          return true
        }
      }
    } catch (error) {
      console.error('[RTCEngine] isHeadsetConnected error:', error)
    }
    return false
  }

  /**
   * 智能音频路由：有耳机走耳机，没耳机走扬声器
   */
  async setupSmartAudioRouting(): Promise<void> {
    const hasHeadset = this.isHeadsetConnected()
    if (hasHeadset) {
      // 有耳机 → 不强制扬声器，系统默认走耳机
      await this.enableSpeakerphone(false)
      console.info('[RTCEngine] Headset connected, routing to headset')
    } else {
      // 无耳机 → 走扬声器外放
      await this.enableSpeakerphone(true)
      console.info('[RTCEngine] No headset, routing to speaker')
    }

    // 启动设备变化监听
    this.startDeviceChangeListener()
  }

  /**
   * 监听音频设备插拔，自动切换路由
   */
  private startDeviceChangeListener(): void {
    try {
      const audioManager = audio.getAudioManager()
      this.audioRoutingManager = audioManager.getRoutingManager()
      this.audioRoutingManager.on('deviceChange', audio.DeviceFlag.OUTPUT_DEVICES_FLAG,
        (deviceChangeAction: audio.DeviceChangeAction) => {
          const devices = deviceChangeAction.deviceDescriptors
          const changeType = deviceChangeAction.type // 0=CONNECT, 1=DISCONNECT
          let isHeadset = false
          for (let i = 0; i < devices.length; i++) {
            const deviceType = devices[i].deviceType
            if (deviceType === audio.DeviceType.WIRED_HEADSET ||
              deviceType === audio.DeviceType.WIRED_HEADPHONES ||
              deviceType === audio.DeviceType.BLUETOOTH_A2DP ||
              deviceType === audio.DeviceType.BLUETOOTH_SCO ||
              deviceType === audio.DeviceType.USB_HEADSET) {
              isHeadset = true
              break
            }
          }
          if (!isHeadset) {
            return
          }

          if (changeType === audio.DeviceChangeType.CONNECT) {
            // 耳机插入 → 切到耳机
            console.info('[RTCEngine] Headset plugged in, switching to headset')
            this.enableSpeakerphone(false)
          } else if (changeType === audio.DeviceChangeType.DISCONNECT) {
            // 耳机拔出 → 切回扬声器
            console.info('[RTCEngine] Headset unplugged, switching to speaker')
            this.enableSpeakerphone(true)
          }
        })
      console.info('[RTCEngine] Device change listener started')
    } catch (error) {
      console.error('[RTCEngine] startDeviceChangeListener error:', error)
    }
  }

  /**
   * 停止设备变化监听
   */
  private stopDeviceChangeListener(): void {
    try {
      if (this.audioRoutingManager) {
        this.audioRoutingManager.off('deviceChange')
        this.audioRoutingManager = null
        console.info('[RTCEngine] Device change listener stopped')
      }
    } catch (error) {
      console.error('[RTCEngine] stopDeviceChangeListener error:', error)
    }
  }

  /**
   * 获取本地音频电平（从 publisherPC stats 读取）
   * 返回 0.0 - 1.0 的电平值
   */
  async getLocalAudioLevel(): Promise<number> {
    if (!this.publisherPC) {
      return 0
    }

    try {
      const report = await this.publisherPC.getStats()
      const statsMap = report.stats
      const entries: [string, ESObject][] = []
      statsMap.forEach((value: ESObject, key: string) => {
        entries.push([key, value])
      })
      for (let i = 0; i < entries.length; i++) {
        const stat: ESObject = entries[i][1]
        if (stat.type === 'media-source' && stat.kind === 'audio') {
          const level: number = stat.audioLevel ?? 0
          return level
        }
      }
    } catch (error) {
      console.error('[RTCEngine] getLocalAudioLevel error:', error)
    }
    return 0
  }

  /**
   * 获取远端音频电平（从 subscriberPC stats 读取）
   * 通过 getStats() 读取 inbound-rtp 的 audioLevel
   * 返回 Map<trackId, level>
   */
  async getRemoteAudioLevels(): Promise<Map<string, number>> {
    const levels: Map<string, number> = new Map()
    if (!this.subscriberPC) {
      return levels
    }

    try {
      const report = await this.subscriberPC.getStats()
      const statsMap = report.stats
      const entries: [string, ESObject][] = []
      statsMap.forEach((value: ESObject, key: string) => {
        entries.push([key, value])
      })
      for (let i = 0; i < entries.length; i++) {
        const stat: ESObject = entries[i][1]
        if (stat.type === 'inbound-rtp' && stat.kind === 'audio') {
          // 优先读 audioLevel，备选通过 totalAudioEnergy 计算
          let level: number = 0
          if (stat.audioLevel !== undefined && stat.audioLevel !== null) {
            level = stat.audioLevel as number
          } else if (stat.totalAudioEnergy !== undefined && stat.totalSamplesDuration !== undefined) {
            const energy: number = stat.totalAudioEnergy as number
            const duration: number = stat.totalSamplesDuration as number
            if (duration > 0) {
              level = Math.sqrt(energy / duration)
            }
          }
          const trackId: string = stat.trackIdentifier ?? stat.ssrc?.toString() ?? entries[i][0]
          levels.set(trackId, level)
        }
      }
    } catch (error) {
      console.error('[RTCEngine] getRemoteAudioLevels error:', error)
    }
    return levels
  }
}
