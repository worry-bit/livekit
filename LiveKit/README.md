# LiveKit HarmonyOS 模块

基于 `@ohos/webrtc` 官方 ArkTS API 实现的 LiveKit 实时音频通信客户端，适用于 HarmonyOS (OpenHarmony) 应用。

## 模块信息

| 项目 | 值 |
|------|-----|
| 包名 | `livekit-harmony` |
| 版本 | 1.0.0 |
| 类型 | HAR (Harmony Archive) |
| 依赖 | `@ohos/webrtc ^1.0.0`、`protobufjs ^7.2.4` |
| 仓库 | [GitHub](https://github.com/paitasuo1/LiveKitDemo) |
| OHPM | [livekit-harmony](https://ohpm.openharmony.cn/#/cn/detail/livekit-harmony) |

## 目录结构

```
LiveKit/
├── Index.ets                          # 公共 API 导出入口
├── oh-package.json5                   # 模块配置
└── src/main/ets/util/
    ├── LiveKitClient.ets              # 主客户端（对外 API 层）
    ├── RTCEngine.ets                  # WebRTC 引擎（PeerConnection 管理）
    ├── SignalClient.ets               # WebSocket 信令客户端
    ├── AudioManager.ets               # 远程音频播放器管理
    ├── ProtobufCodec.ets              # 手写 Protobuf 编解码
    └── types.ets                      # 所有类型/接口/枚举定义
```

## 架构概览

```
┌──────────────────────────────────────────────────────────┐
│                    业务层 (LiveKitUtil)                    │
│  joinRoom()  leaveRoom()  toggleMute()  audioLevelObserver│
└──────────────────────┬───────────────────────────────────┘
                       │
┌──────────────────────▼───────────────────────────────────┐
│                   LiveKitClient                           │
│  connect / disconnect / publishAudio / setMuted           │
│  on / off 事件系统 / startAudioLevelObserver              │
├──────────────┬───────────────────────────┬───────────────┤
│  RTCEngine   │                           │ SignalClient   │
│  publisherPC │ (WebRTC PeerConnection)   │ (WebSocket)    │
│  subscriberPC│                           │ Protobuf 编解码│
└──────┬───────┘                           └───────┬───────┘
       │ @ohos/webrtc                              │ @ohos.net.webSocket
       ▼                                           ▼
┌──────────────┐                           ┌───────────────┐
│ 麦克风/扬声器 │                           │ LiveKit Server │
└──────────────┘                           └───────────────┘
```

## 快速开始

### 1. 导入模块

```typescript
import {
  createLiveKitClient,
  LiveKitClient,
  AudioLevelInfo
} from 'livekit-harmony'
```

### 2. 创建客户端并连接

```typescript
const client: LiveKitClient = createLiveKitClient()

await client.connect('wss://your-livekit-server.com', 'your-jwt-token', {
  publishAudio: true,              // 连接后自动发布麦克风音频
  audioOptions: {
    sampleRate: 48000,
    channelCount: 1,
    echoCancellation: true,        // 回声消除
    noiseSuppression: true,        // 噪音抑制
    autoGainControl: true          // 自动增益控制
  }
})
```

### 3. 监听事件

```typescript
client.on('connected', () => {
  console.info('已连接到房间')
})

client.on('participantConnected', (data: ESObject) => {
  console.info('参与者加入:', data.participant.identity)
})

client.on('participantDisconnected', (data: ESObject) => {
  console.info('参与者离开:', data.participant.identity)
})

client.on('trackSubscribed', (data: ESObject) => {
  console.info('收到远程音频轨道:', data.track.kind)
})

client.on('activeSpeakersChanged', (data: ESObject) => {
  console.info('当前说话人:', data.speakers)
})
```

### 4. 控制音频

```typescript
// 静音 / 取消静音
client.setMuted(true)
client.setMuted(false)

// 查询静音状态
const muted = client.isMicMuted()

// 手动发布 / 取消发布音频
await client.publishAudio()
await client.unpublishAudio()
```

### 5. 音频电平观察

```typescript
// 开始监听本地和远端音频电平
client.startAudioLevelObserver((levels: AudioLevelInfo[]) => {
  for (let i = 0; i < levels.length; i++) {
    const info = levels[i]
    if (info.isLocal) {
      console.info('本地电平:', info.level, '说话中:', info.isSpeaking)
    } else {
      console.info('远端:', info.participantSid, '电平:', info.level)
    }
  }
}, {
  intervalMs: 500,           // 轮询间隔 (ms)
  speakingThreshold: 0.05    // 说话判定阈值
})

// 停止观察
client.stopAudioLevelObserver()
```

### 6. 断开连接

```typescript
await client.disconnect()
```

---

## API 参考

### LiveKitClient

#### 属性

| 属性 | 类型 | 说明 |
|------|------|------|
| `state` | `RoomState` | 当前连接状态 |
| `roomInfo` | `RoomInfo \| null` | 房间信息 |
| `localParticipant` | `ParticipantInfo \| null` | 本地参与者信息 |
| `remoteParticipants` | `ParticipantInfo[]` | 远端参与者列表 |
| `isConnected` | `boolean` | 是否已连接 |

#### 方法

| 方法 | 返回值 | 说明 |
|------|--------|------|
| `connect(url, token, options?)` | `Promise<void>` | 连接到 LiveKit 房间 |
| `disconnect()` | `Promise<void>` | 断开连接，自动清理所有资源 |
| `publishAudio(options?)` | `Promise<void>` | 发布本地麦克风音频 |
| `unpublishAudio()` | `Promise<void>` | 取消发布音频 |
| `setMuted(muted)` | `void` | 设置静音状态 |
| `isMicMuted()` | `boolean` | 获取静音状态 |
| `startAudioLevelObserver(callback, options?)` | `void` | 开始音频电平轮询 |
| `stopAudioLevelObserver()` | `void` | 停止音频电平轮询 |
| `on(event, handler)` | `void` | 注册事件监听 |
| `off(event, handler)` | `void` | 移除事件监听 |

---

### 事件列表

| 事件名 | 回调数据 | 触发时机 |
|--------|----------|----------|
| `connected` | `{ room: RoomInfo }` | 成功连接到房间 |
| `disconnected` | `{ error?: Error }` | 断开连接 |
| `reconnecting` | `{}` | 正在尝试重连 |
| `reconnected` | `{}` | 重连成功 |
| `participantConnected` | `{ participant: ParticipantInfo }` | 远端参与者加入 |
| `participantDisconnected` | `{ participant: ParticipantInfo }` | 远端参与者离开 |
| `trackPublished` | `{ kind: 'audio' }` | 本地轨道已发布 |
| `trackUnpublished` | `{ kind: 'audio' }` | 本地轨道已取消发布 |
| `trackSubscribed` | `{ track, streams }` | 订阅到远端轨道 |
| `trackUnsubscribed` | `{ track }` | 远端轨道移除 |
| `trackMuted` | `{ kind: 'audio' }` | 轨道被静音 |
| `trackUnmuted` | `{ kind: 'audio' }` | 轨道取消静音 |
| `activeSpeakersChanged` | `{ speakers: SpeakerInfo[] }` | 服务端检测到说话人变化 |
| `audioLevelsChanged` | `{ levels: AudioLevelInfo[] }` | 音频电平轮询结果 |
| `connectionQualityChanged` | `{ updates: ConnectionQualityInfo[] }` | 连接质量变化 |
| `dataReceived` | `{ data }` | 收到数据消息 |

---

### 类型定义

#### ConnectOptions

```typescript
interface ConnectOptions {
  autoSubscribe?: boolean       // 自动订阅远端轨道，默认 true
  publishAudio?: boolean        // 连接后自动发布音频
  publishVideo?: boolean        // 连接后自动发布视频
  audioOptions?: AudioCaptureOptions
}
```

#### AudioCaptureOptions

```typescript
interface AudioCaptureOptions {
  sampleRate?: number           // 采样率，默认 48000
  channelCount?: number         // 声道数，默认 1 (单声道)
  echoCancellation?: boolean    // 回声消除
  noiseSuppression?: boolean    // 噪音抑制
  autoGainControl?: boolean     // 自动增益控制
}
```

#### AudioLevelInfo

```typescript
interface AudioLevelInfo {
  participantSid: string        // 参与者 SID，本地为 localParticipant.sid
  isLocal: boolean              // 是否是本地音频
  level: number                 // 电平值 0.0 - 1.0
  isSpeaking: boolean           // 是否正在说话 (level > threshold)
}
```

#### AudioLevelObserverOptions

```typescript
interface AudioLevelObserverOptions {
  intervalMs?: number           // 轮询间隔，默认 100ms
  speakingThreshold?: number    // 说话阈值，默认 0.05
}
```

#### ParticipantInfo

```typescript
interface ParticipantInfo {
  sid: string                   // 会话 ID
  identity: string              // 身份标识
  name: string                  // 显示名称
  state: ParticipantState       // JOINING=0 | JOINED=1 | ACTIVE=2 | DISCONNECTED=3
  metadata?: string             // 自定义元数据
  joinedAt: number              // 加入时间戳
  permission?: ParticipantPermission
}
```

#### SpeakerInfo

```typescript
interface SpeakerInfo {
  sid: string                   // 参与者 SID
  level: number                 // 音量 0-1
  active: boolean               // 是否正在说话
}
```

#### RoomState

```typescript
enum RoomState {
  DISCONNECTED = 'disconnected'
  CONNECTING   = 'connecting'
  CONNECTED    = 'connected'
  RECONNECTING = 'reconnecting'
}
```

---

## 连接流程

```
1. client.connect(url, token)
   │
   ├─ SignalClient.connect()          # WebSocket 握手 + JoinResponse
   │   └─ 返回: room / participant / iceServers / otherParticipants
   │
   ├─ RTCEngine.createPeerConnections()
   │   ├─ publisherPC   (发布者，发送本地音频)
   │   └─ subscriberPC  (订阅者，接收远端音频)
   │
   ├─ RTCEngine.enableSpeakerphone(true)   # 切换到扬声器输出
   │
   ├─ emit('connected')
   │
   └─ publishAudio()  (如果 options.publishAudio = true)
       ├─ createAudioSource(constraints)   # 麦克风采集
       ├─ createAudioTrack(id, source)
       ├─ signalClient.sendAddTrack()      # 通知服务端
       └─ publisherPC.addTrack()           # 触发 SDP 协商
           ├─ createOffer → sendOffer
           ├─ 服务端返回 answer → setRemoteDescription
           └─ ICE candidates 交换 (trickle)

2. 远端音频接收
   │
   ├─ 服务端发送 offer → subscriberPC.setRemoteDescription
   ├─ subscriberPC.createAnswer → sendAnswer
   ├─ subscriberPC.ontrack 触发
   │   └─ delegate.onTrackAdded() → emit('trackSubscribed')
   └─ WebRTC 自动播放远端音频

3. client.disconnect()
   │
   ├─ stopAudioLevelObserver()        # 停止电平轮询
   ├─ unpublishAudio()                # 取消发布音频
   ├─ signalClient.sendLeave()        # 通知服务端
   ├─ rtcEngine.close()               # 关闭 PeerConnections
   ├─ signalClient.close()            # 关闭 WebSocket
   └─ emit('disconnected')
```

---

## 音频电平检测原理

### 本地电平
通过 `publisherPC.getStats()` 读取 WebRTC 统计数据中 `type === 'media-source'` 且 `kind === 'audio'` 的条目的 `audioLevel` 字段 (0.0 - 1.0)。

### 远端电平
通过 `subscriberPC.getStats()` 读取 `type === 'inbound-rtp'` 且 `kind === 'audio'` 的条目：
- 优先使用 `audioLevel` 字段
- 备选：通过 `totalAudioEnergy / totalSamplesDuration` 计算 RMS 电平

### 轮询策略

| 参数 | 默认值 | 说明 |
|------|--------|------|
| `intervalMs` | 100ms | 轮询频率，推荐 100-500ms |
| `speakingThreshold` | 0.05 | 高于此值判定为正在说话 |

> `disconnect()` 时自动停止轮询，无需手动调用 `stopAudioLevelObserver()`。

---

## 信令协议

使用自定义 Protobuf 编解码 (非 protobufjs 运行时) 与 LiveKit 服务端通信。

### 客户端 → 服务端

| 消息类型 | 字段号 | 用途 |
|----------|--------|------|
| Offer | 1 | 发送 SDP offer (发布者) |
| Answer | 2 | 发送 SDP answer (订阅者) |
| Trickle | 3 | 发送 ICE candidate |
| AddTrack | 4 | 请求发布新轨道 |
| MuteTrack | 5 | 静音/取消静音轨道 |
| Leave | 8 | 离开房间 |

### 服务端 → 客户端

| 消息类型 | 字段号 | 用途 |
|----------|--------|------|
| JoinResponse | 1 | 加入响应 (房间/参与者/ICE 服务器) |
| Answer | 2 | SDP answer (发布者协商) |
| Offer | 3 | SDP offer (订阅者协商) |
| Trickle | 4 | ICE candidate |
| ParticipantUpdate | 5 | 参与者状态变化 |
| TrackPublished | 6 | 轨道发布确认 |
| Leave | 7 | 服务端要求断开 |
| SpeakersChanged | 8 | 活跃说话人变化 |
| RoomUpdate | 9 | 房间信息更新 |
| ConnectionQuality | 10 | 连接质量更新 |

---

## 重连机制

`SignalClient` 内置自动重连逻辑：

- 最多重试 **5** 次
- 指数退避：`Math.min(1000 * 2^attempt, 10000)` ms
- 服务端主动关闭 (code >= 4000) 时不重连
- 重连时触发 `'reconnecting'` 事件，成功后触发 `'reconnected'`

---

## 安装与发布

### 安装（在其他项目中使用）

```bash
ohpm install livekit-harmony
```

### 发布到 OHPM 中心仓

如果你是维护者，需要发布新版本：

**快速发布：**
```bash
cd LiveKit
./publish.sh
```

**详细指南：**
- 📖 [快速发布指南](./QUICK_PUBLISH.md)
- 📖 [完整发布文档](./PUBLISH_GUIDE.md)

---

## 所需权限

在 `module.json5` 中声明：

```json
{
  "requestPermissions": [
    { "name": "ohos.permission.MICROPHONE" },
    { "name": "ohos.permission.INTERNET" }
  ]
}
```
