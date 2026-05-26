import { socket } from '@kit.NetworkKit'
import { util } from '@kit.ArkTS'
import { KooSignalMessage } from './KooPhoneTypes'

export class KooSignalClient {
  // Event callbacks - caller will set these
  onConnected: (() => void) | null = null
  onAuthorize: ((authorized: boolean) => void) | null = null
  onMessage: ((message: KooSignalMessage) => void) | null = null
  onStart: ((streamId: string, vcodec?: string) => void) | null = null
  onClosed: (() => void) | null = null

  private wsSocket: socket.Socket | null = null
  private pingInterval: number = 25000
  private pingTimer: number | null = null
  private sid: string = ''

  // Connect to signaling server
  // query format: "authtype=token&boxid=xxx&token=xxx"
  connect(url: string, query: string): void {
    try {
      // Construct Socket.IO v2 handshake URL
      const fullUrl = `${url}/socket.io/?EIO=3&transport=websocket&${query}`

      // Create WebSocket
      this.wsSocket = socket.constructSocket()

      // Set up event listeners
      this.wsSocket.on('open', () => {
        console.info('KooSignalClient: WebSocket opened')
      })

      this.wsSocket.on('message', (data: ESObject) => {
        this.handleMessage(String(data))
      })

      this.wsSocket.on('close', () => {
        console.info('KooSignalClient: WebSocket closed')
        this.cleanup()
        if (this.onClosed) {
          this.onClosed()
        }
      })

      this.wsSocket.on('error', (err: ESObject) => {
        console.error('KooSignalClient: WebSocket error:', JSON.stringify(err))
        this.cleanup()
        throw new Error(String(err))
      })

      // Connect to server
      this.wsSocket.connect(fullUrl)
    } catch (e) {
      throw new Error(String(e))
    }
  }

  // Handle incoming messages
  private handleMessage(data: string): void {
    try {
      if (data.length === 0) {
        return
      }

      const prefix = data.charAt(0)

      // Handshake response (Engine.IO)
      if (prefix === '0') {
        const handshakeJson = data.substring(1)
        const handshake = JSON.parse(handshakeJson)
        this.sid = handshake.sid
        this.pingInterval = handshake.pingInterval || 25000
        this.pingTimeout = handshake.pingTimeout || 60000

        // Start heartbeat timer
        this.startHeartbeat()
        return
      }

      // Socket.IO connect confirmation
      if (data === '40') {
        if (this.onConnected) {
          this.onConnected()
        }
        return
      }

      // Socket.IO event
      if (prefix === '4' && data.length > 2 && data.charAt(1) === '2') {
        const eventJson = data.substring(2)
        const eventArray = JSON.parse(eventJson)

        if (Array.isArray(eventArray) && eventArray.length >= 2) {
          const eventName = eventArray[0] as string
          const payload = eventArray[1] as ESObject

          this.handleEvent(eventName, payload)
        }
        return
      }

      // Ping from server
      if (data === '2') {
        // Reply with Pong
        this.sendRaw('3')
        return
      }
    } catch (e) {
      console.error('KooSignalClient: Error handling message:', String(e))
      throw new Error(String(e))
    }
  }

  // Handle Socket.IO events
  private handleEvent(eventName: string, payload: ESObject): void {
    try {
      switch (eventName) {
        case 'authorize':
          if (this.onAuthorize) {
            this.onAuthorize(payload.authorized === true)
          }
          break

        case 'start':
          if (this.onStart) {
            this.onStart(payload.streamId, payload.vcodec)
          }
          break

        case 'message':
          if (this.onMessage) {
            const message: KooSignalMessage = {
              type: payload.type,
              from: payload.from,
              payload: payload.payload,
              data: payload.data
            }
            this.onMessage(message)
          }
          break

        case 'close':
          if (this.onClosed) {
            this.onClosed()
          }
          this.close()
          break

        default:
          console.info('KooSignalClient: Unknown event:', eventName)
      }
    } catch (e) {
      throw new Error(String(e))
    }
  }

  // Start heartbeat timer
  private startHeartbeat(): void {
    try {
      if (this.pingTimer) {
        clearInterval(this.pingTimer)
      }

      this.pingTimer = setInterval(() => {
        this.sendRaw('3')
      }, this.pingInterval)
    } catch (e) {
      throw new Error(String(e))
    }
  }

  // Send raw data over WebSocket
  private sendRaw(data: string): void {
    try {
      if (this.wsSocket) {
        this.wsSocket.send(data)
      }
    } catch (e) {
      throw new Error(String(e))
    }
  }

  // Send init request (type=data, data=base64 encoded JSON)
  emitData(type: string, to: string, data: string): void {
    try {
      const message = `42["message",{"to":"${to}","type":"${type}","data":"${data}"}]`
      this.sendRaw(message)
    } catch (e) {
      throw new Error(String(e))
    }
  }

  // Send answer/candidate messages (type=message, payload=JSON object)
  emitMessage(type: string, to: string, payload: ESObject): void {
    try {
      const payloadStr = JSON.stringify(payload)
      const message = `42["message",{"to":"${to}","type":"${type}","payload":${payloadStr}}]`
      this.sendRaw(message)
    } catch (e) {
      throw new Error(String(e))
    }
  }

  // Close connection
  close(): void {
    try {
      this.cleanup()
      if (this.wsSocket) {
        this.wsSocket.close()
        this.wsSocket = null
      }
    } catch (e) {
      throw new Error(String(e))
    }
  }

  // Cleanup resources
  private cleanup(): void {
    try {
      if (this.pingTimer) {
        clearInterval(this.pingTimer)
        this.pingTimer = null
      }
    } catch (e) {
      throw new Error(String(e))
    }
  }

  private pingTimeout: number = 60000
}
