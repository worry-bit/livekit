# KooPhone 云手机串流播放器实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在 `koophone/` 目录下用 ArkTS 实现云手机端侧 WebRTC 串流客户端，覆盖 Socket.IO v2 信令连接、SDP 协商、ICE candidate 交换、远端视频渲染全流程。

**Architecture:** 四层分离架构：`KooPhoneTypes.ets`（类型）→ `KooSignalClient.ets`（Socket.IO v2 信令）→ `KooRTCSource.ets`（WebRTC PeerConnection + NativeVideoRenderer）→ `KooPhonePlayer.ets`（状态机 + 公共 API）。信令层用 `@kit.NetworkKit` 原生 WebSocket 手动实现 Engine.IO v3 帧协议；WebRTC 层全部调用 `@ohos/webrtc` 已有接口。

**Tech Stack:** HarmonyOS ArkTS、`@kit.NetworkKit`（webSocket）、`@ohos/webrtc`（PeerConnectionFactory / RTCPeerConnection / NativeVideoRenderer）、`@kit.ArkTS`（util.Base64Helper）

---

## 文件变更地图

| 文件 | 操作 | 职责 |
|---|---|---|
| `LiveKit/src/main/ets/koophone/KooPhoneTypes.ets` | 新建 | 所有接口、枚举、回调类型定义 |
| `LiveKit/src/main/ets/koophone/KooSignalClient.ets` | 新建 | Socket.IO v2 信令层（WebSocket + 帧解析 + 心跳） |
| `LiveKit/src/main/ets/koophone/KooRTCSource.ets` | 新建 | WebRTC PeerConnection、SDP 协商、ICE、视频渲染 |
| `LiveKit/src/main/ets/koophone/KooPhonePlayer.ets` | 新建 | 状态机 + 流程编排 + 对外公共 API |

**不修改任何已有文件。**

---

## Task 1：KooPhoneTypes.ets — 类型定义

**Files:**
- Create: `LiveKit/src/main/ets/koophone/KooPhoneTypes.ets`

- [ ] **Step 1：创建类型文件**

完整内容：

```typescript
import webrtc from '@ohos/webrtc'

// 连接参数（与 H5 CloudPlayer._open() 参数一致）
export interface KooPhoneParams {
  signalingUrl: string        // 信令服务器地址，如 wss://host:port
  boxId: string               // 设备 ID
  token: string               // 鉴权 token
  iceServers?: KooIceServer[] // ICE 服务器（可选）
  mode?: string               // 默认 'app'
  role?: string               // 默认 'master'
  sole?: boolean              // 默认 true
  volume?: number             // 默认 100
}

export interface KooIceServer {
  uri: string
  usr?: string
  pwd?: string
}

// 播放器状态
export enum KooPhoneState {
  NEW = 'new',
  CONNECTING = 'connecting',
  AUTHORIZED = 'authorized',
  PEER_CONNECTING = 'peer_connecting',
  PLAYING = 'playing',
  CLOSED = 'closed'
}

// 错误码
export enum KooPhoneError {
  PARAM_INVALID = 1001,
  SIGNAL_CONNECT_FAILED = 1002,
  SIGNAL_AUTH_FAILED = 1003,
  SDP_ERROR = 1004,
  ICE_ERROR = 1005,
  PEER_FAILED = 1006
}

// 信令消息结构
export interface KooSignalMessage {
  type: string       // 'offer' | 'answer' | 'candidate'
  from: string
  payload?: ESObject
  data?: string      // base64 编码（init 响应用）
}

// 授权响应结构
export interface KooAuthorizePayload {
  authorized: boolean
  code: number
}

// start 事件响应结构
export interface KooStartPayload {
  streamId: string
  vcodec?: string
}

// 事件回调类型
export type OnStateChange = (state: KooPhoneState) => void
export type OnTrack = (track: webrtc.MediaStreamTrack) => void
export type OnError = (code: KooPhoneError, message: string) => void
```

- [ ] **Step 2：提交**

```bash
cd E:/Programing/code/LiveKitDemo-main
git add LiveKit/src/main/ets/koophone/KooPhoneTypes.ets
git commit -m "feat(koophone): add KooPhoneTypes - interfaces, enums and callback types"
```

---

## Task 2：KooSignalClient.ets — Socket.IO v2 信令层

**Files:**
- Create: `LiveKit/src/main/ets/koophone/KooSignalClient.ets`

> 背景：Socket.IO v2 底层是 Engine.IO v3 协议。握手 URL 为
> `wss://<host>/socket.io/?EIO=3&transport=websocket&<query>`
> 帧格式：`0{json}` = Handshake，`40` = Connect，`42[...]` = Event，`2` = Ping，`3` = Pong。
> 鸿蒙使用 `@kit.NetworkKit` 的 `webSocket` 模块，不需要 Socket.IO 客户端库。

- [ ] **Step 1：创建 KooSignalClient.ets**

完整内容：

```typescript
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

    this.ws.on('open', () => {
      console.info('[KooSignalClient] WebSocket opened')
    })

    this.ws.on('message', (err, data: string | ArrayBuffer) => {
      if (typeof data !== 'string') return
      this.handleFrame(data)
    })

    this.ws.on('close', (err, result: webSocket.CloseResult) => {
      console.info('[KooSignalClient] WebSocket closed, code:', result?.code)
      this.stopHeartbeat()
      this._connected = false
      this.onClosed?.()
    })

    this.ws.on('error', (err) => {
      console.error('[KooSignalClient] WebSocket error:', err?.message)
      this.stopHeartbeat()
      this._connected = false
    })

    this.ws.connect(wsUrl, (err, success) => {
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
  emitMessage(type: string, to: string, payload: ESObject): void {
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
      this.ws.close()
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
      const arr = JSON.parse(jsonStr) as ESObject[]
      const eventName = arr[0] as string
      const payload = arr[1] as ESObject

      console.info('[KooSignalClient] Event:', eventName)

      if (eventName === 'authorize') {
        const auth = payload as KooAuthorizePayload
        console.info('[KooSignalClient] Authorize result:', auth.authorized)
        this.onAuthorize?.(auth.authorized)
      } else if (eventName === 'start') {
        const startPayload = payload as KooStartPayload
        console.info('[KooSignalClient] Start, streamId:', startPayload.streamId)
        this.onStart?.(startPayload)
      } else if (eventName === 'message') {
        const msg = payload as KooSignalMessage
        this.onMessage?.(msg)
      } else if (eventName === 'close') {
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
    this.ws.send(frame, (err, success) => {
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
```

- [ ] **Step 2：提交**

```bash
cd E:/Programing/code/LiveKitDemo-main
git add LiveKit/src/main/ets/koophone/KooSignalClient.ets
git commit -m "feat(koophone): add KooSignalClient - Socket.IO v2 signaling over native WebSocket"
```

---

## Task 3：KooRTCSource.ets — WebRTC PeerConnection + 视频渲染

**Files:**
- Create: `LiveKit/src/main/ets/koophone/KooRTCSource.ets`

> 背景：
> - `PeerConnectionFactory` 用 `new webrtc.PeerConnectionFactory()` 创建
> - 收到 offer 后流程：`setRemoteDescription` → `createAnswer` → `setLocalDescription` → 触发 `onDescription` 回调
> - `ontrack` 时：`NativeVideoRenderer.setVideoTrack(track)` 渲染 + 触发 `onTrack` 回调
> - candidate 可能在 setRemoteDescription 之前到达，需缓存后批量添加
> - `close()` 时顺序：`renderer.setVideoTrack(null)` → `renderer.release()` → `pc.close()`
> - ArkTS 限制：`throw` 只能抛 `new Error(String(e))`

- [ ] **Step 1：创建 KooRTCSource.ets**

完整内容：

```typescript
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
    if (!this.pc) return

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
    if (!this.pc) return

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
    if (this.pendingCandidates.length === 0 || !this.pc) return

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
```

- [ ] **Step 2：提交**

```bash
cd E:/Programing/code/LiveKitDemo-main
git add LiveKit/src/main/ets/koophone/KooRTCSource.ets
git commit -m "feat(koophone): add KooRTCSource - WebRTC PeerConnection with SDP negotiation and video rendering"
```

---

## Task 4：KooPhonePlayer.ets — 状态机 + 公共 API

**Files:**
- Create: `LiveKit/src/main/ets/koophone/KooPhonePlayer.ets`

> 背景：
> - `util.Base64Helper` 用于 init payload 的 base64 编码（替代 H5 的 `btoa()`）
> - init payload 结构与 H5 `_createPeer()` 一致：`{sole, mode, role, profile_name, network_type, volume, vcodec}`
> - `remoteId` 从 `start` 事件的 `streamId` 字段提取
> - candidate payload 结构：`{label: sdpMLineIndex, id: sdpMid, candidate: candidateStr}`（与 H5 `_onLocalIceCandidate()` 一致）
> - 状态转换：NEW → CONNECTING → AUTHORIZED → PEER_CONNECTING → PLAYING → CLOSED

- [ ] **Step 1：创建 KooPhonePlayer.ets**

完整内容：

```typescript
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
    if (this._state === KooPhoneState.CLOSED) return

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
      const payload: ESObject = desc.toJSON()
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
    if (!this.params) return

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
        sdp: payload['sdp'] as string,
        toJSON: (): webrtc.RTCSessionDescriptionInit => {
          return { type: payload['type'] as 'offer', sdp: payload['sdp'] as string }
        }
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
```

- [ ] **Step 2：提交**

```bash
cd E:/Programing/code/LiveKitDemo-main
git add LiveKit/src/main/ets/koophone/KooPhonePlayer.ets
git commit -m "feat(koophone): add KooPhonePlayer - state machine and public API"
```

---

## Task 5：集成验证 — 编译检查 + UI 示例

**Files:**
- Modify: `entry/src/main/ets/pages/Index.ets` (仅添加示例按钮，不影响现有功能)

> 注意：HarmonyOS 项目无法在命令行运行测试，通过 hvigorw assembleDebug 验证编译，
> 功能验证需要在真机上进行。

- [ ] **Step 1：编译检查**

```bash
cd E:/Programing/code/LiveKitDemo-main
hvigorw assembleDebug 2>&1
```

预期：`BUILD SUCCESSFUL`，无 ArkTS 编译错误。如果有类型错误，根据错误信息修正对应文件。

- [ ] **Step 2：在 Index.ets 添加 KooPhone 测试入口（可选验证）**

在 `entry/src/main/ets/pages/Index.ets` 中，在现有按钮行后追加：

```typescript
// 在文件顶部 import 区加入（如需测试 KooPhone）：
// import { createKooPhonePlayer, KooPhoneState } from 'livekit-harmony/koophone'
```

如果需要完整 UI 测试，可在 `entry/src/main/ets/pages/` 下新建 `KooPhonePage.ets`：

```typescript
import { createKooPhonePlayer, KooPhonePlayer, KooPhoneState, KooPhoneError }
  from '../../../../../../LiveKit/src/main/ets/koophone/KooPhonePlayer'

@Entry
@Component
struct KooPhonePage {
  private player: KooPhonePlayer = createKooPhonePlayer()
  private xCtrl: XComponentController = new XComponentController()
  private surfaceId: string = ''
  @State stateText: string = 'NEW'

  aboutToAppear(): void {
    this.player.onStateChange = (s: KooPhoneState) => {
      this.stateText = s
    }
    this.player.onError = (code: KooPhoneError, msg: string) => {
      this.stateText = `Error ${code}: ${msg}`
    }
    this.player.onTrack = () => {
      console.info('[KooPhonePage] Remote video track received')
    }
  }

  aboutToDisappear(): void {
    this.player.close()
  }

  build() {
    Column({ space: 12 }) {
      XComponent({ type: XComponentType.SURFACE, controller: this.xCtrl })
        .width('100%')
        .aspectRatio(16 / 9)
        .backgroundColor(Color.Black)
        .onLoad(() => {
          this.surfaceId = this.xCtrl.getXComponentSurfaceId()
          console.info('[KooPhonePage] XComponent loaded, surfaceId:', this.surfaceId)
        })

      Text(`状态: ${this.stateText}`).fontSize(16)

      Row({ space: 12 }) {
        Button('开始串流').onClick(() => {
          this.player.open({
            signalingUrl: 'wss://your-signal-server',
            boxId: 'your-box-id',
            token: 'your-token'
          }, this.surfaceId)
        })

        Button('停止').onClick(() => {
          this.player.close()
        })
      }
    }
    .width('100%').height('100%').padding(16)
  }
}
```

- [ ] **Step 3：最终提交**

```bash
cd E:/Programing/code/LiveKitDemo-main
git add .
git commit -m "feat(koophone): complete cloud phone streaming player implementation"
```

---

## 自检：Spec 覆盖确认

| Spec 要求 | 实现 Task |
|---|---|
| Socket.IO v2 握手（EIO=3）| Task 2 KooSignalClient.connect() |
| 授权（authorize 事件）| Task 2 handleEvent() + Task 4 onAuthorize |
| start 事件提取 streamId | Task 2 handleEvent() + Task 4 onStart |
| 发送 init（base64 编码）| Task 4 sendInit()，util.Base64Helper |
| 接收 offer，生成 answer | Task 3 setRemoteDescription() + createAnswer() |
| 发送 answer | Task 4 onDescription → emitMessage('answer') |
| 本地 ICE candidate 收集并发送 | Task 3 onicecandidate + Task 4 onIceCandidate |
| 接收远端 candidate | Task 4 handleSignalMessage + Task 3 addRemoteIceCandidate |
| candidate 缓存（remoteDesc 未就绪）| Task 3 pendingCandidates + flushPendingCandidates |
| 远端视频渲染（NativeVideoRenderer）| Task 3 ontrack → setVideoTrack |
| 远端 track 回调给调用方 | Task 3 onTrack → Task 4 onTrack → 调用方 |
| Socket.IO 心跳 | Task 2 startHeartbeat()，发送 '3' |
| close() 资源释放顺序 | Task 3 renderer.setVideoTrack(null)→release→pc.close |
| 不修改已有文件 | 所有 Task 仅新建文件 |
| ArkTS throw 限制 | Task 2/3/4 catch 块均用 String(e) |
