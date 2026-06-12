/**
 * LiveKit 信令客户端
 * 使用鸿蒙 @ohos.net.webSocket API
 * 使用手动实现的 Protobuf 编解码（避免鸿蒙的 new Function() 限制）
 */

import webSocket from '@ohos.net.webSocket'
import { util } from '@kit.ArkTS'
import {
  SignalRequest,
  SignalResponse,
  JoinResponse,
  SessionDescription,
  SignalTarget
} from './types'

// 手动实现的 Protobuf 编解码器（不依赖 protobufjs）
import {
  encodeSignalRequest,
  decodeSignalResponse,
  SignalRequest as CodecSignalRequest
} from './ProtobufCodec'

/**
 * 信令事件处理函数类型
 */
export type SignalEventHandler = (response: SignalResponse) => void

/**
 * LiveKit 信令客户端
 */
export class SignalClient {
  private ws: webSocket.WebSocket | null = null
  private url: string = ''
  private token: string = ''
  private reconnectAttempts: number = 0
  private maxReconnectAttempts: number = 5
  private reconnectDelay: number = 2000  // 增加重连延迟

  private eventHandlers: Map<string, SignalEventHandler[]> = new Map()

  // 使用 Protobuf 还是 JSON
  private useProtobuf: boolean = true

  // 连接状态
  private _isConnected: boolean = false
  private _isConnecting: boolean = false  // 防止重复连接
  private _shouldReconnect: boolean = true  // 控制是否应该重连
  
  get isConnected(): boolean {
    return this._isConnected
  }

  constructor(useProtobuf: boolean = true) {
    this.useProtobuf = useProtobuf
  }

  /**
   * 连接到 LiveKit 服务器
   */
  async connect(url: string, token: string): Promise<JoinResponse> {
    // 防止重复连接
    if (this._isConnecting) {
      return Promise.reject(new Error('Already connecting'))
    }
    if (this._isConnected) {
      return Promise.reject(new Error('Already connected'))
    }
    
    this._isConnecting = true
    this._shouldReconnect = true
    this.url = url
    this.token = token

    // 使用手动实现的 Protobuf 编解码，无需初始化

    return new Promise((resolve, reject) => {
      try {
        // 构建 WebSocket URL
        const wsUrl = this.buildWsUrl(url, token)
        console.info(`[SignalClient] Connecting to ${wsUrl}`)

        // 创建鸿蒙 WebSocket
        this.ws = webSocket.createWebSocket()

        // 连接事件
        this.ws.on('open', (err: Error, value: Object) => {
          if (err) {
            console.error('[SignalClient] WebSocket open error:', err)
            this._isConnecting = false
            reject(err)
            return
          }
          console.info('[SignalClient] WebSocket connected')
          this._isConnected = true
          this._isConnecting = false
          this.reconnectAttempts = 0  // 重置重连计数
        })

        // 消息事件
        this.ws.on('message', (err: Error, value: string | ArrayBuffer) => {
          if (err) {
            console.error('[SignalClient] WebSocket message error:', err)
            return
          }
          this.handleMessage(value)
        })

        // 关闭事件
        this.ws.on('close', (err: Error, value: webSocket.CloseResult) => {
          console.info(`[SignalClient] WebSocket closed: ${value.code} ${value.reason}`)
          this._isConnected = false
          this._isConnecting = false
          
          // 某些关闭码不应该重连（如 DUPLICATE_IDENTITY）
          // 4001 = DUPLICATE_IDENTITY, 4002 = SERVER_SHUTDOWN 等
          if (value.code >= 4000 && value.code < 5000) {
            console.warn('[SignalClient] Server closed connection, not reconnecting')
            this._shouldReconnect = false
            this.emit('disconnected', {} as SignalResponse)
          } else {
            this.handleDisconnect()
          }
        })

        // 错误事件
        this.ws.on('error', (err: Error) => {
          console.error('[SignalClient] WebSocket error:', err)
          this._isConnecting = false
          if (!this._isConnected) {
            reject(err)
          }
        })
        // 发起连接
        this.ws.connect(wsUrl, (err: Error, value: boolean) => {
          if (err) {
            console.error('[SignalClient] Connect error:', err)
            reject(err)
          }
        })

        // 等待 JoinResponse
        const timeout = setTimeout(() => {
          reject(new Error('Join timeout'))
        }, 10000)

        this.once('join', (response: SignalResponse) => {
          clearTimeout(timeout)
          if (response.join) {
            resolve(response.join)
          } else {
            reject(new Error('Invalid join response'))
          }
        })

      } catch (error) {
        reject(error)
      }
    })
  }

  /**
   * 发送 SDP Offer
   */
  sendOffer(offer: SessionDescription): void {
    const signalRequest: SignalRequest = {
      offer: offer
    }
    this.sendRequest(signalRequest)
  }

  /**
   * 发送 SDP Answer
   */
  sendAnswer(answer: SessionDescription): void {
    const signalRequest: SignalRequest = {
      answer: answer
    }
    this.sendRequest(signalRequest)
  }

  /**
   * 发送 ICE Candidate
   * @param candidateInit JSON 字符串格式的 ICE candidate
   * @param target 目标（发布者或订阅者）
   */
  sendCandidate(candidateInit: string, target: SignalTarget): void {
    const signalRequest: SignalRequest = {
      trickle: {
        candidateInit: candidateInit,
        target: target
      }
    }
    this.sendRequest(signalRequest)
  }

  /**
   * 发送离开请求
   */
  sendLeave(): void {
    const signalRequest: SignalRequest = {
      leave: {
        canReconnect: false
      }
    }
    this.sendRequest(signalRequest)
  }

  /**
   * 发送静音请求
   */
  sendMuteTrack(trackSid: string, muted: boolean): void {
    const signalRequest: SignalRequest = {
      mute: {
        sid: trackSid,
        muted: muted
      }
    }
    this.sendRequest(signalRequest)
  }

  /**
   * 发送添加轨道请求
   * @param cid 客户端轨道 ID
   * @param name 轨道名称
   * @param type 轨道类型: 0=AUDIO, 1=VIDEO
   * @param source 轨道来源: 2=MICROPHONE, 1=CAMERA
   */
  sendAddTrack(cid: string, name: string, type: number, source: number): void {
    const signalRequest: SignalRequest = {
      addTrack: {
        cid: cid,
        name: name,
        type: type,
        source: source,
        muted: false,
        // 视频发布端强制 VP8，不再启用 RED，避免服务端继续协商非 VP8 冗余编码。
        disableRed: type === 1
      }
    }
    this.sendRequest(signalRequest)
    console.info('[SignalClient] Sent addTrack:', cid, name, 'type:', type, 'source:', source)
  }

  /**
   * 关闭连接
   */
  close(): void {
    this._shouldReconnect = false  // 手动关闭不重连
    this._isConnecting = false
    
    if (this.ws) {
      this.ws.close((err: Error) => {
        if (err) {
          console.error('[SignalClient] Close error:', err)
        }
      })
      this.ws = null
    }
    this._isConnected = false
  }

  /**
   * 注册事件处理器
   */
  on(event: string, handler: SignalEventHandler): void {
    if (!this.eventHandlers.has(event)) {
      this.eventHandlers.set(event, [])
    }
    this.eventHandlers.get(event)!.push(handler)
  }

  /**
   * 注册一次性事件处理器
   */
  once(event: string, handler: SignalEventHandler): void {
    const wrappedHandler: SignalEventHandler = (response) => {
      this.off(event, wrappedHandler)
      handler(response)
    }
    this.on(event, wrappedHandler)
  }

  /**
   * 移除事件处理器
   */
  off(event: string, handler: SignalEventHandler): void {
    const handlers = this.eventHandlers.get(event)
    if (handlers) {
      const index = handlers.indexOf(handler)
      if (index !== -1) {
        handlers.splice(index, 1)
      }
    }
  }

  // ==================== 私有方法 ====================

  private buildWsUrl(url: string, token: string): string {
    // 将 http/https 转换为 ws/wss
    let wsUrl = url.replace(/^http/, 'ws')

    // 确保路径正确
    if (!wsUrl.endsWith('/rtc')) {
      wsUrl = wsUrl.replace(/\/$/, '') + '/rtc'
    }

    // 添加 token 参数
    wsUrl += `?access_token=${encodeURIComponent(token)}`

    // 添加协议版本
    wsUrl += '&protocol=16'

    // 添加自动订阅
    wsUrl += '&auto_subscribe=1'

    // 添加 SDK 信息 (使用 JS 类型，因为 ArkTS 类似 TypeScript)
    // LiveKit 支持: JS, SWIFT, ANDROID, FLUTTER, GO, UNITY, REACT_NATIVE, RUST, PYTHON, CPP, UNITY_WEB, NODE, UNREAL, ESP32
    wsUrl += '&sdk=js&version=1.0.0'

    return wsUrl
  }

  private sendRequest(request: SignalRequest): void {
    if (!this.ws || !this._isConnected) {
      console.error('[SignalClient] Cannot send request: not connected')
      return
    }

    try {
      let data: string | ArrayBuffer

      if (this.useProtobuf) {
        // 使用手动实现的 Protobuf 编码
        const codecRequest: CodecSignalRequest = {
          join: request.join ? {
            roomName: request.join.roomName,
            identity: request.join.identity,
            name: request.join.name,
            autoSubscribe: request.join.autoSubscribe,
            reconnect: request.join.reconnect
          } : undefined,
          offer: request.offer ? {
            type: request.offer.type,
            sdp: request.offer.sdp
          } : undefined,
          answer: request.answer ? {
            type: request.answer.type,
            sdp: request.answer.sdp
          } : undefined,
          trickle: request.trickle ? {
            candidateInit: request.trickle.candidateInit,
            target: request.trickle.target
          } : undefined,
          leave: request.leave ? {
            canReconnect: request.leave.canReconnect,
            reason: request.leave.reason
          } : undefined,
          mute: request.mute ? {
            sid: request.mute.sid,
            muted: request.mute.muted
          } : undefined,
          addTrack: request.addTrack ? {
            cid: request.addTrack.cid,
            name: request.addTrack.name,
            type: request.addTrack.type,
            source: request.addTrack.source,
            muted: request.addTrack.muted,
            disableDtx: request.addTrack.disableDtx,
            disableRed: request.addTrack.disableRed
          } : undefined
        }
        const buffer = encodeSignalRequest(codecRequest)
        data = buffer.buffer.slice(buffer.byteOffset, buffer.byteOffset + buffer.byteLength)
      } else {
        // JSON 编码
        data = JSON.stringify(request)
      }

      this.ws.send(data, (err: Error, value: boolean) => {
        if (err) {
          console.error('[SignalClient] Send error:', err)
        } else {
          // 记录发送的消息类型
          const sentTypes: string[] = []
          if (request.join) sentTypes.push('join')
          if (request.offer) sentTypes.push('offer')
          if (request.answer) sentTypes.push('answer')
          if (request.trickle) sentTypes.push('trickle')
          if (request.leave) sentTypes.push('leave')
          if (request.mute) sentTypes.push('mute')
          if (request.addTrack) sentTypes.push('addTrack')

          if (sentTypes.length > 0) {
            console.info('[SignalClient] Sent:', sentTypes.join(', '))
          }
        }
      })
    } catch (error) {
      console.error('[SignalClient] Send error:', error)
    }
  }

  private handleMessage(data: string | ArrayBuffer): void {
    try {
      if (data instanceof ArrayBuffer && this.useProtobuf) {
        // 使用手动实现的 Protobuf 解码
        const buffer = new Uint8Array(data)
        const decoded = decodeSignalResponse(buffer)
        
        // 转换为 types.ets 中定义的 SignalResponse 格式
        const response: SignalResponse = this.convertDecodedResponse(decoded)
        
        // 打印收到的消息类型
        const receivedTypes: string[] = []
        if (response.join) receivedTypes.push('join')
        if (response.offer) receivedTypes.push('offer')
        if (response.answer) receivedTypes.push('answer')
        if (response.trickle) receivedTypes.push('trickle')
        if (response.update) receivedTypes.push('update')
        if (response.trackPublished) receivedTypes.push('trackPublished')
        if (response.leave) receivedTypes.push('leave')
        if (receivedTypes.length > 0) {
          console.info('[SignalClient] Received:', receivedTypes.join(', '))
        }
        
        this.dispatchResponse(response)
      } else if (typeof data === 'string') {
        // JSON 解码
        const response: SignalResponse = JSON.parse(data)
        this.dispatchResponse(response)
      } else if (data instanceof ArrayBuffer) {
        // 尝试将 ArrayBuffer 作为 JSON 解码
        const textDecoder = util.TextDecoder.create('utf-8')
        const text = textDecoder.decodeToString(new Uint8Array(data))
        const response: SignalResponse = JSON.parse(text)
        this.dispatchResponse(response)
      }

    } catch (error) {
      console.error('[SignalClient] Parse message error:', error)
    }
  }

  /**
   * 转换解码后的响应为 SignalResponse 类型
   */
  private convertDecodedResponse(decoded: ESObject): SignalResponse {
    const response: SignalResponse = {}
    
    if (decoded.join) {
      response.join = {
        room: decoded.join.room,
        participant: decoded.join.participant,
        otherParticipants: decoded.join.otherParticipants || [],
        serverVersion: decoded.join.serverVersion || '',
        iceServers: decoded.join.iceServers || [],
        subscriberPrimary: decoded.join.subscriberPrimary || false
      }
    }
    
    if (decoded.offer) {
      console.info('[SignalClient] Decoded offer - type:', decoded.offer.type, 
        ', sdp length:', decoded.offer.sdp?.length || 0)
      response.offer = {
        type: decoded.offer.type || 'offer',
        sdp: decoded.offer.sdp || ''
      }
    }
    
    if (decoded.answer) {
      response.answer = {
        type: decoded.answer.type || 'answer',
        sdp: decoded.answer.sdp || ''
      }
    }
    
    if (decoded.trickle) {
      response.trickle = {
        candidateInit: decoded.trickle.candidateInit || '',
        target: decoded.trickle.target || 0
      }
    }
    
    if (decoded.update) {
      response.update = decoded.update
    }
    
    if (decoded.trackPublished) {
      response.trackPublished = decoded.trackPublished
    }
    
    if (decoded.leave) {
      response.leave = {
        canReconnect: decoded.leave.canReconnect,
        reason: decoded.leave.reason
      }
    }
    
    if (decoded.speakersChanged) {
      response.speakersChanged = decoded.speakersChanged
    }
    
    if (decoded.roomUpdate) {
      response.roomUpdate = decoded.roomUpdate
    }
    
    if (decoded.connectionQuality) {
      response.connectionQuality = decoded.connectionQuality
    }
    
    return response
  }

  private dispatchResponse(response: SignalResponse): void {
    // 根据响应类型分发事件
    if (response.join) {
      console.info('[SignalClient] Dispatching join event')
      this.emit('join', response)
    }
    if (response.offer) {
      console.info('[SignalClient] Dispatching offer event, sdp length:', response.offer.sdp?.length || 0)
      this.emit('offer', response)
    }
    if (response.answer) {
      this.emit('answer', response)
    }
    if (response.trickle) {
      this.emit('trickle', response)
    }
    if (response.update) {
      this.emit('participantUpdate', response)
    }
    if (response.trackPublished) {
      this.emit('trackPublished', response)
    }
    if (response.leave) {
      this.emit('leave', response)
    }
    if (response.speakersChanged) {
      this.emit('speakersChanged', response)
    }
    if (response.roomUpdate) {
      this.emit('roomUpdate', response)
    }
    if (response.connectionQuality) {
      this.emit('connectionQuality', response)
    }
  }

  private emit(event: string, response: SignalResponse): void {
    const handlers = this.eventHandlers.get(event)
    if (handlers) {
      for (let i = 0; i < handlers.length; i++) {
        try {
          handlers[i](response)
        } catch (error) {
          console.error(`[SignalClient] Event handler error for ${event}:`, error)
        }
      }
    }
  }

  private handleDisconnect(): void {
    // 检查是否应该重连
    if (!this._shouldReconnect) {
      console.info('[SignalClient] Reconnect disabled, not reconnecting')
      return
    }
    
    // 检查是否正在连接中
    if (this._isConnecting) {
      console.info('[SignalClient] Already connecting, skip reconnect')
      return
    }
    
    // 尝试重连
    if (this.reconnectAttempts < this.maxReconnectAttempts) {
      this.reconnectAttempts++
      const delay = this.reconnectDelay * this.reconnectAttempts
      console.info(`[SignalClient] Reconnecting in ${delay}ms... attempt ${this.reconnectAttempts}`)

      setTimeout(() => {
        if (this._isConnected || this._isConnecting) {
          console.info('[SignalClient] Already connected/connecting, skip reconnect')
          return
        }
        this.connect(this.url, this.token).catch((error:ESObject) => {
          console.error('[SignalClient] Reconnect failed:', error)
        })
      }, delay)
    } else {
      console.warn('[SignalClient] Max reconnect attempts reached')
      this.emit('disconnected', {} as SignalResponse)
    }
  }
}
