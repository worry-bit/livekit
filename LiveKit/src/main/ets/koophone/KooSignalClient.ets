import { webSocket } from '@kit.NetworkKit'
import {
  KooSignalMessage,
  KooAuthorizePayload,
  KooStartPayload
} from './KooPhoneTypes'

interface HandshakeJson {
  sid: string
  pingInterval: number
  pingTimeout: number
}

// Socket.IO 事件帧结构：42["eventName", payload]
interface SocketEventFrame {
  eventName: string
  payload: Record<string, Object>
}

export class KooSignalClient {
  private ws: webSocket.WebSocket | null = null
  private heartbeatTimer: number | null = null
  private _connected: boolean = false

  // 事件回调
  onAuthorize: ((authorized: boolean) => void) | null = null
  onStart: ((payload: KooStartPayload) => void) | null = null
  onMessage: ((message: KooSignalMessage) => void) | null = null
  onClosed: (() => void) | null = null

  get isConnected(): boolean {
    return this._connected
  }

  /**
   * 连接信令服务器
   * @param url 信令服务器地址，如 wss://host:port
   * @param query query 参数，如 authtype=token&boxid=xxx&token=xxx
   */
  connect(url: string, query: string): void {
    if (this.ws !== null) {
      console.warn('[KooSignalClient] Already connected')
      return
    }

    // 拼接 Socket.IO v2 握手 URL
    const separator = url.includes('?') ? '&' : '?'
    const wsUrl = `${url}/socket.io/${separator}EIO=3&transport=websocket&${query}`
    console.info('[KooSignalClient] Connecting:', wsUrl)

    this.ws = webSocket.createWebSocket()

    this.ws.on('open', (err: Error) => {
      if (err) {
        console.error('[KooSignalClient] WebSocket open error:', err?.message)
        return
      }
      console.info('[KooSignalClient] WebSocket opened')
    })

    this.ws.on('message', (err: Error, data: string | ArrayBuffer) => {
      if (err) {
        console.error('[KooSignalClient] Message error:', err?.message)
        return
      }
      if (typeof data !== 'string') {
        return
      }
      this.handleFrame(data)
    })

    this.ws.on('close', (err: Error, result: webSocket.CloseResult) => {
      console.info('[KooSignalClient] WebSocket closed, code:', result?.code)
      this.stopHeartbeat()
      this._connected = false
      this.onClosed?.()
    })

    this.ws.on('error', (err: Error) => {
      console.error('[KooSignalClient] WebSocket error:', err?.message)
      this.stopHeartbeat()
      this._connected = false
    })

    this.ws.connect(wsUrl, (err: Error, success: boolean) => {
      if (!success || err) {
        console.error('[KooSignalClient] Connect failed:', err?.message)
      }
    })
  }

  /**
   * 发送 data 类型消息（用于 init 请求，data 为 base64 编码的 JSON）
   */
  emitData(type: string, to: string, data: string): void {
    const msg = JSON.stringify({ to, type, data })
    this.sendFrame(`42["message",${msg}]`)
  }

  /**
   * 发送 message 类型消息（用于 answer/candidate）
   */
  emitMessage(type: string, to: string, payload: Record<string, Object>): void {
    const msg = JSON.stringify({ to, type, payload })
    this.sendFrame(`42["message",${msg}]`)
  }

  /**
   * 关闭连接，释放资源
   */
  close(): void {
    this.stopHeartbeat()
    if (this.ws !== null) {
      this.ws.off('open')
      this.ws.off('message')
      this.ws.off('close')
      this.ws.off('error')
      this.ws.close((err: Error) => {
        if (err) {
          console.error('[KooSignalClient] Close error:', err?.message)
        }
      })
      this.ws = null
    }
    this._connected = false
  }

  // ==================== 私有方法 ====================

  private handleFrame(data: string): void {
    console.debug('[KooSignalClient] Frame received:', data.substring(0, 100))

    if (data.startsWith('0')) {
      // Handshake: 0{"sid":"...","pingInterval":25000,"pingTimeout":5000}
      try {
        const json = JSON.parse(data.slice(1)) as HandshakeJson
        console.info('[KooSignalClient] Handshake, sid:', json.sid,
          'pingInterval:', json.pingInterval)
        this.startHeartbeat(json.pingInterval)
      } catch (e) {
        console.error('[KooSignalClient] Handshake parse error:', String(e))
      }
    } else if (data === '40') {
      // Socket.IO namespace connected
      console.info('[KooSignalClient] Socket.IO connected')
      this._connected = true
    } else if (data.startsWith('42')) {
      // Event: 42["eventName", payload]
      this.handleEvent(data.slice(2))
    } else if (data === '2') {
      // Ping from server → reply Pong
      this.sendFrame('3')
    }
  }

  private handleEvent(jsonStr: string): void {
    try {
      // 解析为 [eventName, payload] 数组，用 Object[] 避免 ESObject/any
      const arr = JSON.parse(jsonStr) as Object[]
      if (arr.length < 2) {
        return
      }
      const frame: SocketEventFrame = {
        eventName: arr[0] as string,
        payload: arr[1] as Record<string, Object>
      }

      console.info('[KooSignalClient] Event:', frame.eventName)

      if (frame.eventName === 'authorize') {
        const auth: KooAuthorizePayload = {
          authorized: frame.payload['authorized'] as boolean,
          code: frame.payload['code'] as number
        }
        console.info('[KooSignalClient] Authorize result:', auth.authorized)
        this.onAuthorize?.(auth.authorized === true)
      } else if (frame.eventName === 'start') {
        const startPayload: KooStartPayload = {
          streamId: frame.payload['streamId'] as string,
          vcodec: frame.payload['vcodec'] as string | undefined
        }
        console.info('[KooSignalClient] Start, streamId:', startPayload.streamId)
        this.onStart?.(startPayload)
      } else if (frame.eventName === 'message') {
        const msg: KooSignalMessage = {
          type: frame.payload['type'] as string,
          from: frame.payload['from'] as string,
          payload: frame.payload['payload'] as Record<string, Object> | undefined,
          data: frame.payload['data'] as string | undefined
        }
        this.onMessage?.(msg)
      } else if (frame.eventName === 'close') {
        console.info('[KooSignalClient] Server closed connection')
        this.onClosed?.()
      }
    } catch (e) {
      console.error('[KooSignalClient] Event parse error:', String(e))
    }
  }

  private sendFrame(frame: string): void {
    if (this.ws === null) {
      console.warn('[KooSignalClient] Cannot send, ws is null')
      return
    }
    this.ws.send(frame, (err: Error, success: boolean) => {
      if (!success) {
        console.error('[KooSignalClient] Send failed:', err?.message)
      }
    })
  }

  private startHeartbeat(intervalMs: number): void {
    this.stopHeartbeat()
    this.heartbeatTimer = setInterval(() => {
      this.sendFrame('3')
    }, intervalMs) as number
    console.info('[KooSignalClient] Heartbeat started, interval:', intervalMs, 'ms')
  }

  private stopHeartbeat(): void {
    if (this.heartbeatTimer !== null) {
      clearInterval(this.heartbeatTimer)
      this.heartbeatTimer = null
    }
  }
}
