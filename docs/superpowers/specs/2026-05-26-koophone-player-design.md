# KooPhone 云手机串流播放器设计文档

**日期：** 2026-05-26
**项目：** LiveKitDemo-main（HarmonyOS 鸿蒙）
**范围：** 在 `koophone/` 目录下全新实现云手机端侧 WebRTC 串流客户端，不修改任何已有代码

---

## 1. 目标与约束

### 目标
将 H5 端云手机串流客户端（`Connection.js` + `RTCSource.js` + `CloudPlayer.js`）移植为鸿蒙原生 ArkTS 实现，覆盖以下流程：
1. 与信令服务器建立 Socket.IO v2 连接（含授权）
2. 发送 `init` 请求触发 boxrtc 初始化
3. 接收 `offer`，生成并发送 `answer`
4. 双端 ICE candidate 协商
5. 接收 WebRTC 视频流，本地渲染并通过回调暴露给调用方

### 不在本期范围内
- 音频控制（mute/unmute）
- 重连逻辑
- 统计信息（getStats 轮询）
- 摄像头/麦克风上行流
- DataChannel 输入控制

### 硬性约束
- 不修改任何 `koophone/` 目录之外的已有文件
- 信令协议：Socket.IO v2（EIO=3），通过 `@kit.NetworkKit` 的原生 `webSocket` 实现
- WebRTC：全部调用 `@ohos/webrtc` 已有接口（`PeerConnectionFactory`、`RTCPeerConnection`、`NativeVideoRenderer`）
- 连接参数与 init payload 字段与 H5 版本完全一致

---

## 2. 技术选型

### 信令层：原生 WebSocket 模拟 Socket.IO v2

Socket.IO v2 底层是 WebSocket + Engine.IO v3 协议，帧格式如下：

| 包类型 | 格式 | 说明 |
|---|---|---|
| Handshake | `0{...json...}` | 服务器发送，含 sid、pingInterval、pingTimeout |
| Connect | `40` | 服务器确认连接 |
| Event | `42["event_name", payload]` | 双向事件消息 |
| Ping | `2` | 服务器发送心跳 |
| Pong | `3` | 客户端回复心跳 |

握手 URL 格式：
```
wss://<host>/socket.io/?EIO=3&transport=websocket&<query>
```

### WebRTC 层：@ohos/webrtc

| H5 API | 鸿蒙 API |
|---|---|
| `new RTCPeerConnection(config)` | `peerConnectionFactory.createPeerConnection(config)` |
| `pc.setRemoteDescription(sdp)` | `pc.setRemoteDescription(sdp)` |
| `pc.createAnswer()` | `pc.createAnswer()` |
| `pc.setLocalDescription(desc)` | `pc.setLocalDescription(desc)` |
| `pc.addIceCandidate(candidate)` | `pc.addIceCandidate(candidateInit)` |
| `video.srcObject = stream` | `NativeVideoRenderer.init(surfaceId)` + `setVideoTrack(track)` |

---

## 3. 架构

### 文件结构

```
LiveKit/src/main/ets/koophone/
├── Connection.js              # H5 参考（只读，不修改）
├── RTCSource.js               # H5 参考（只读，不修改）
├── H5端 WebRTC 串流流程代码追踪.md  # H5 参考（只读，不修改）
├── h5端侧项目总结.md           # H5 参考（只读，不修改）
├── KooPhoneTypes.ets          # 类型定义
├── KooSignalClient.ets        # Socket.IO v2 信令层
├── KooRTCSource.ets           # WebRTC PeerConnection + 视频渲染
└── KooPhonePlayer.ets         # 状态机 + 公共 API
```

### 数据流

```
调用方
  │
  │ open(params, surfaceId)
  ▼
KooPhonePlayer
  │
  ├─ KooSignalClient.connect(url, query)
  │       │
  │       │ WebSocket 握手 (EIO=3)
  │       │ 收到 40 → CONNECTED
  │       │ 收到 42["authorize", {authorized:true}] → AUTHORIZED
  │       ▼
  ├─ sendInit()    42["message", {to, type:"init", data:base64(params)}]
  │       │
  │       │ 收到 42["message", {type:"offer", payload}]
  │       ▼
  ├─ KooRTCSource.setRemoteDescription(offer)
  │       │
  │       │ createAnswer()
  │       │ setLocalDescription(answer)
  │       │ onDescription(answer)
  │       ▼
  ├─ KooSignalClient.emitMessage("answer", remoteId, answer)
  │
  │  ICE candidate 收集
  │  ├─ RTCPeerConnection.onicecandidate
  │  │       └─ KooSignalClient.emitMessage("candidate", remoteId, {label, id, candidate})
  │  │
  │  └─ 收到 42["message", {type:"candidate", payload}]
  │          └─ KooRTCSource.addRemoteIceCandidate(candidate)
  │
  │  RTCPeerConnection.ontrack (远端视频轨道到达)
  │  ├─ NativeVideoRenderer.setVideoTrack(track)  ← 内部渲染到 XComponent
  │  └─ onTrack(track) 回调 → 调用方              ← 暴露给 UI 层
  │
  └─ connectionState = 'connected'
          └─ KooPhonePlayer 状态 → PLAYING
```

---

## 4. 接口设计

### 4.1 KooPhoneTypes.ets

```typescript
// 连接参数（与 H5 CloudPlayer._open() 参数一致）
export interface KooPhoneParams {
  signalingUrl: string       // 信令服务器地址，如 wss://host:port
  boxId: string              // 设备 ID
  token: string              // 鉴权 token
  iceServers?: KooIceServer[] // ICE 服务器配置（可选，有默认值）
  // init 请求 payload 字段（与 H5 _createPeer() 一致）
  mode?: string              // 默认 'app'
  role?: string              // 默认 'master'
  sole?: boolean             // 默认 true
  volume?: number            // 默认 100
}

export interface KooIceServer {
  uri: string
  usr?: string
  pwd?: string
}

// 播放器状态（与 H5 PlayerState 对应）
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

// 事件回调类型
export type OnStateChange = (state: KooPhoneState) => void
export type OnTrack = (track: webrtc.MediaStreamTrack) => void
export type OnError = (code: KooPhoneError, message: string) => void
```

### 4.2 KooSignalClient.ets

```typescript
export class KooSignalClient {
  // 事件回调
  onAuthorize: ((authorized: boolean) => void) | null
  onMessage: ((message: KooSignalMessage) => void) | null
  onClosed: (() => void) | null

  // 连接信令服务器
  // query 格式: "authtype=token&boxid=xxx&token=xxx"
  connect(url: string, query: string): void

  // 发送 init 请求（type=data，data=base64编码的JSON）
  emitData(type: string, to: string, data: string): void

  // 发送 answer/candidate 等消息（type=message，payload=JSON对象）
  emitMessage(type: string, to: string, payload: ESObject): void

  // 关闭连接
  close(): void
}

export interface KooSignalMessage {
  type: string    // 'offer' | 'answer' | 'candidate'
  from: string
  payload?: ESObject
  data?: string   // base64 编码
}
```

**Socket.IO v2 帧解析逻辑：**

```
收到消息 → 读取第一个字符判断包类型：
  '0' → Handshake，解析 JSON，存 sid，记录 pingInterval
  '40' → Connect 确认，触发连接成功
  '42' → Event，解析 JSON 数组: [eventName, payload]
           eventName='authorize' → 调用 onAuthorize
           eventName='message'  → 调用 onMessage
           eventName='close'    → 调用 onClosed
  '2' → Ping，立即回复 '3'（Pong）

发送消息格式：
  emitData/emitMessage → '42["message", {to, type, data/payload}]'
```

**心跳机制：** 收到 Handshake 后，按 `pingInterval`（通常 25000ms）定时发送 `2`，服务器回复 `3` 维持连接。

### 4.3 KooRTCSource.ets

```typescript
export class KooRTCSource {
  // 事件回调
  onDescription: ((desc: webrtc.RTCSessionDescription) => void) | null
  onIceCandidate: ((candidate: webrtc.RTCIceCandidate) => void) | null
  onConnectionStateChange: ((state: webrtc.RTCPeerConnectionState) => void) | null
  onTrack: ((track: webrtc.MediaStreamTrack) => void) | null

  // 创建 PeerConnection
  open(iceServers: KooIceServer[]): void

  // 设置本地预览 surfaceId（用于 NativeVideoRenderer）
  setSurfaceId(surfaceId: string): void

  // 收到 offer 时调用，内部自动 createAnswer
  setRemoteDescription(sdp: webrtc.RTCSessionDescription): Promise<void>

  // 添加远端 ICE candidate（含重试：remoteDesc 未就绪时缓存）
  addRemoteIceCandidate(candidate: webrtc.RTCIceCandidateInit): void

  // 关闭并释放资源
  close(): void
}
```

**`setRemoteDescription` 内部流程：**
```
setRemoteDescription(offer)
  → pc.setRemoteDescription(offer)
  → 若 offer.type === 'offer':
      createAnswer()
      → pc.createAnswer()
      → pc.setLocalDescription(answer)
      → onDescription(answer)   ← 触发回调，调用方发送 answer
```

**`ontrack` 处理：**
```
pc.ontrack = (event) => {
  if (event.track.kind === 'video') {
    if (localRenderer && surfaceId) {
      localRenderer.setVideoTrack(event.track)   // 内部渲染
    }
    onTrack?.(event.track)                         // 暴露给调用方
  }
}
```

**ICE candidate 重试：** candidate 到达时若 `pc.remoteDescription` 为 null，缓存到数组，`setRemoteDescription` 完成后统一 `addIceCandidate`。

### 4.4 KooPhonePlayer.ets（公共 API）

```typescript
export class KooPhonePlayer {
  // 事件回调（调用方注册）
  onStateChange: OnStateChange | null
  onTrack: OnTrack | null
  onError: OnError | null

  /**
   * 开始串流
   * @param params 连接参数
   * @param surfaceId XComponent 的 surfaceId，用于远端视频渲染
   */
  open(params: KooPhoneParams, surfaceId: string): void

  /**
   * 停止串流，释放所有资源
   */
  close(): void

  /**
   * 获取当前播放器状态
   */
  get state(): KooPhoneState
}

export function createKooPhonePlayer(): KooPhonePlayer
```

---

## 5. Socket.IO v2 协议实现细节

### 握手 URL
```
wss://<signalingUrl>/socket.io/?EIO=3&transport=websocket&authtype=token&boxid=<boxId>&token=<token>
```

### 收到消息解析

```typescript
// 收到原始字符串 data
const prefix = data[0]
if (prefix === '0') {
  // Handshake: {"sid":"...","upgrades":[],"pingInterval":25000,"pingTimeout":5000}
  const json = JSON.parse(data.slice(1))
  this.sid = json.sid
  this.startHeartbeat(json.pingInterval)
} else if (data === '40') {
  // Socket.IO connected
  this.onConnected?.()
} else if (data.startsWith('42')) {
  // Event: 42["eventName", payload]
  const arr = JSON.parse(data.slice(2)) as [string, ESObject]
  const eventName = arr[0]
  const payload = arr[1]
  this.dispatchEvent(eventName, payload)
} else if (data === '2') {
  // Ping from server → reply Pong
  this.ws.send('3')
}
```

### 发送消息

```typescript
// emitData: init 请求
// 42["message", {"to": remoteId, "type": "init", "data": base64(JSON)}]
send(`42["message",${JSON.stringify({to, type, data})}]`)

// emitMessage: answer/candidate
// 42["message", {"to": remoteId, "type": "answer", "payload": {...}}]
send(`42["message",${JSON.stringify({to, type, payload})}]`)
```

---

## 6. 调用方使用示例

```typescript
import { createKooPhonePlayer, KooPhoneState } from 'livekit-harmony/koophone'

@Entry @Component
struct CloudPhonePage {
  private player = createKooPhonePlayer()
  private xCtrl: XComponentController = new XComponentController()
  private surfaceId: string = ''
  @State state: string = 'NEW'

  aboutToAppear() {
    this.player.onStateChange = (s: KooPhoneState) => { this.state = s }
    this.player.onTrack = (track) => {
      // 远端视频 track，KooPhonePlayer 内部已渲染到 XComponent
      // 调用方可在此做额外处理
    }
    this.player.onError = (code, msg) => {
      console.error('KooPhone error:', code, msg)
    }
  }

  aboutToDisappear() {
    this.player.close()
  }

  build() {
    Column() {
      XComponent({ type: XComponentType.SURFACE, controller: this.xCtrl })
        .width('100%').aspectRatio(16 / 9)
        .onLoad(() => {
          this.surfaceId = this.xCtrl.getXComponentSurfaceId()
        })

      Button('开始串流').onClick(() => {
        this.player.open({
          signalingUrl: 'wss://your-signal-server',
          boxId: 'your-box-id',
          token: 'your-token'
        }, this.surfaceId)
      })

      Button('停止').onClick(() => { this.player.close() })

      Text(`状态: ${this.state}`)
    }
  }
}
```

---

## 7. 涉及文件清单

| 文件 | 操作 | 职责 |
|---|---|---|
| `koophone/KooPhoneTypes.ets` | 新建 | 所有类型定义、枚举、回调类型 |
| `koophone/KooSignalClient.ets` | 新建 | Socket.IO v2 信令层 |
| `koophone/KooRTCSource.ets` | 新建 | WebRTC PeerConnection + 渲染 |
| `koophone/KooPhonePlayer.ets` | 新建 | 状态机 + 公共 API |

**不修改任何已有文件。**

---

## 8. 关键实现注意事项

1. **Socket.IO 心跳**：收到 Handshake 的 `pingInterval`（默认 25000ms）后必须定期发 `3`（pong），否则服务器会断开连接。鸿蒙端用 `setInterval` 实现。

2. **remoteId 来源**：H5 中 `remoteId` 来自 `_onStart()` 回调的 streamId 字段。鸿蒙端从 `42["start", {streamId}]` 事件中提取，存储后用于 `emitMessage` 的 `to` 字段。

3. **init data 编码**：init payload 需要 `JSON.stringify` 后做 base64 编码（与 H5 的 `btoa(data)` 一致）。鸿蒙用 `util.Base64Helper` 完成编码。

4. **ICE candidate 缓存**：`addRemoteIceCandidate` 可能在 `setRemoteDescription` 完成前到达，需先缓存，待 `setRemoteDescription` 成功后批量添加。

5. **NativeVideoRenderer 生命周期**：`close()` 时必须先 `localRenderer.setVideoTrack(null)`，再 `localRenderer.release()`，最后 `pc.close()`。

6. **ArkTS throw 限制**：所有 `catch` 块中的 `throw` 必须抛 `new Error(String(e))`，不能直接 `throw e`。

7. **`authorize` 事件结构**：根据 H5 `Connection._onSocketAuthorize()`，payload 为 `{authorized: boolean, code: number}`，`authorized=true` 时才进入 AUTHORIZED 状态。

8. **start 事件**：`42["start", {streamId, vcodec}]`，从中提取 `streamId` 作为后续 `emitMessage` 的 `to` 参数，然后触发 `sendInit()`。
