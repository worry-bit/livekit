import { webSocket } from '@kit.NetworkKit'
import {
  KooSignalMessage,
  KooAuthorizePayload,
  KooStartPayload,
  KooSignalPayload
} from './KooPhoneTypes'

interface HandshakeJson {
  sid: string
  pingInterval: number
  pingTimeout: number
}

// Socket.IO 事件帧结构：42["eventName", payload]
interface SocketEventFrame {
  eventName: string
  payload: SocketPayload
}

interface SocketPayload {
  authorized?: boolean
  code?: number
  streamId?: string
  vcodec?: string
  type?: string
  from?: string
  payload?: KooSignalPayload
  data?: string
}

interface StartFramePayload {
  room: string
  times: number
}

interface DataFramePayload {
  to: string
  type: string
  data: string
}

interface MessageFramePayload {
  to: string
  type: string
  payload: KooSignalPayload
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

    // 将 http/https scheme 转换为 ws/wss（socket.io-client 会自动转，原生 WebSocket 不会）
    let baseUrl = url
    if (baseUrl.startsWith('http://')) {
      baseUrl = 'ws://' + baseUrl.slice('http://'.length)
    } else if (baseUrl.startsWith('https://')) {
      baseUrl = 'wss://' + baseUrl.slice('https://'.length)
    }
    // 去掉末尾斜杠，统一拼接
    baseUrl = baseUrl.replace(/\/+$/, '')

    // 拼接 Socket.IO v2 握手 URL：固定用 ? 分隔，/socket.io/ 路径后不含已有参数
    const wsUrl = `${baseUrl}/socket.io/?EIO=3&transport=websocket&${query}`
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
   * 发送 start 请求（AUTHORIZED 后客户端主动触发，服务端回调 start 事件返回 streamId）
   * @param times 重连次数，首次连接传 0
   */
  emitStart(boxId: string, times: number = 0): void {
    const payload: StartFramePayload = { room: boxId, times }
    const frame = `42["start",${JSON.stringify(payload)}]`
    console.info('[KooSignalClient] Sent start frame:', frame)
    this.sendFrame(frame)
  }

  /**
   * 发送 data 类型消息（用于 init 请求，data 为 base64 编码的 JSON）
   */
  emitData(type: string, to: string, data: string): void {
    const payload: DataFramePayload = { to, type, data }
    const msg = JSON.stringify(payload)
    const frame = `42["message",${msg}]`
    console.info('[KooSignalClient] emitData frame:', frame.substring(0, 200))
    this.sendFrame(frame)
  }

  /**
   * 发送 message 类型消息（用于 answer/candidate）
   */
  emitMessage(type: string, to: string, payload: KooSignalPayload): void {
    const message: MessageFramePayload = { to, type, payload }
    const msg = JSON.stringify(message)
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
        payload: arr[1] as SocketPayload
      }

      console.info('[KooSignalClient] Event:', frame.eventName)

      if (frame.eventName === 'authorize') {
        const auth: KooAuthorizePayload = {
          authorized: frame.payload.authorized === true,
          code: frame.payload.code ?? 0
        }
        console.info('[KooSignalClient] Authorize result:', auth.authorized)
        this.onAuthorize?.(auth.authorized === true)
      } else if (frame.eventName === 'start') {
        const startPayload: KooStartPayload = {
          streamId: frame.payload.streamId ?? '',
          vcodec: frame.payload.vcodec
        }
        console.info('[KooSignalClient] Start, streamId:', startPayload.streamId)
        this.onStart?.(startPayload)
      } else if (frame.eventName === 'message') {
        // 打印原始 payload 结构，便于排查 payload/data 字段
        console.info('[KooSignalClient] Message payload keys:',
          JSON.stringify(frame.payload).substring(0, 200))
        const msg: KooSignalMessage = {
          type: frame.payload.type ?? '',
          from: frame.payload.from ?? '',
          payload: frame.payload.payload,
          data: frame.payload.data
        }
        console.info('[KooSignalClient] Message type:', msg.type,
          'hasPayload:', !!msg.payload, 'hasData:', !!msg.data)
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
