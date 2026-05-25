# LiveKit HarmonyOS 接入指南

## 📖 项目简介

本项目是一个基于 LiveKit 的 HarmonyOS 实时音频通信客户端，使用 `@ohos/webrtc` 官方 ArkTS API 实现，支持多人实时语音通话功能。

### 核心特性

- ✅ 实时音频通信（支持多人通话）
- ✅ 自动重连机制
- ✅ 音频电平检测（说话状态识别）
- ✅ 回声消除、噪音抑制、自动增益控制
- ✅ 静音控制
- ✅ 参与者管理
- ✅ 连接状态监控

---

## 🛠️ 环境要求

### 开发环境

| 项目 | 版本要求 |
|------|---------|
| DevEco Studio | 4.0 或更高版本 |
| HarmonyOS SDK | API 9 (6.1.0) 或更高 |
| Node.js | 14.x 或更高 |

### 依赖模块

| 模块 | 版本 | 说明 |
|------|------|------|
| `@ohos/webrtc` | ^1.0.0 | WebRTC 官方 API |
| `protobufjs` | ^7.2.4 | Protobuf 编解码 |

---

## 🚀 快速开始

### 1. 项目结构

```
LiveKitDemo/
├── entry/                    # 主应用模块
│   ├── src/main/
│   │   ├── ets/pages/
│   │   │   ├── Index.ets            # 主页面（示例）
│   │   │   ├── LiveKitUtil.ets      # LiveKit 工具类
│   │   │   └── RtcModel.ets         # 数据模型
│   │   └── module.json5             # 模块配置（权限声明）
│   └── oh-package.json5             # 依赖配置
│
├── LiveKit/                  # LiveKit HAR 模块
│   ├── Index.ets                    # API 导出入口
│   └── src/main/ets/util/
│       ├── LiveKitClient.ets        # 主客户端
│       ├── RTCEngine.ets            # WebRTC 引擎
│       ├── SignalClient.ets         # 信令客户端
│       ├── AudioManager.ets         # 音频管理
│       └── types.ets                # 类型定义
│
└── build-profile.json5       # 项目构建配置
```

### 2. 配置权限

在 `entry/src/main/module.json5` 中添加必要权限：

```json5
{
  "module": {
    "requestPermissions": [
      {
        "name": "ohos.permission.INTERNET",
        "reason": "$string:Internet_reason",
        "usedScene": {
          "abilities": ["EntryAbility"],
          "when": "always"
        }
      },
      {
        "name": "ohos.permission.MICROPHONE",
        "reason": "$string:Audio_reason",
        "usedScene": {
          "abilities": ["EntryAbility"],
          "when": "always"
        }
      }
    ]
  }
}
```

### 3. 添加依赖

在 `entry/oh-package.json5` 中添加 LiveKit 模块依赖：

```json5
{
  "dependencies": {
    "livekit": "file:../LiveKit"
  }
}
```

---

## 📝 详细集成步骤

### 步骤 1：导入模块

```typescript
import { AudioLevelInfo, createLiveKitClient, LiveKitClient } from "livekit"
```

### 步骤 2：创建客户端实例

```typescript
// 创建 LiveKit 客户端
const client: LiveKitClient = createLiveKitClient()
```

### 步骤 3：连接到房间

```typescript
// 连接到 LiveKit 服务器
await client.connect(
  'wss://your-livekit-server.com',  // LiveKit 服务器地址
  'your-jwt-token',                  // JWT 访问令牌
  {
    publishAudio: true,              // 自动发布音频
    audioOptions: {
      sampleRate: 48000,             // 采样率
      channelCount: 1,               // 声道数（单声道）
      echoCancellation: true,        // 回声消除
      noiseSuppression: true,        // 噪音抑制
      autoGainControl: true          // 自动增益控制
    }
  }
)
```

### 步骤 4：监听事件

```typescript
// 连接成功
client.on('connected', () => {
  console.info('已连接到房间')
})

// 断开连接
client.on('disconnected', (data: ESObject) => {
  console.info('已断开连接')
  if (data.error) {
    console.error('断开原因:', data.error.message)
  }
})

// 参与者加入
client.on('participantConnected', (data: ESObject) => {
  console.info('参与者加入:', data.participant.identity)
})

// 参与者离开
client.on('participantDisconnected', (data: ESObject) => {
  console.info('参与者离开:', data.participant.identity)
})

// 收到远程音频
client.on('trackSubscribed', (data: ESObject) => {
  console.info('收到远程音频轨道')
})

// 说话人变化
client.on('activeSpeakersChanged', (data: ESObject) => {
  console.info('当前说话人:', data.speakers)
})
```

### 步骤 5：控制音频

```typescript
// 静音
client.setMuted(true)

// 取消静音
client.setMuted(false)

// 查询静音状态
const isMuted = client.isMicMuted()
```

### 步骤 6：音频电平检测

```typescript
// 启动音频电平观察
client.startAudioLevelObserver((levels: AudioLevelInfo[]) => {
  for (let i = 0; i < levels.length; i++) {
    const info = levels[i]
    if (info.isLocal) {
      // 本地音频电平
      console.info('本地电平:', info.level, '说话中:', info.isSpeaking)
    } else {
      // 远端音频电平
      console.info('远端:', info.participantSid, '电平:', info.level)
    }
  }
}, {
  intervalMs: 500,           // 轮询间隔（毫秒）
  speakingThreshold: 0.05    // 说话判定阈值
})

// 停止观察
client.stopAudioLevelObserver()
```

### 步骤 7：断开连接

```typescript
await client.disconnect()
```

---

## 💡 完整使用示例

参考项目中的 `LiveKitUtil.ets` 实现：

```typescript
import { AudioLevelInfo, createLiveKitClient, LiveKitClient } from "livekit"
import { abilityAccessCtrl, common } from "@kit.AbilityKit"

class LiveKitUtil {
  roomState: string = 'disconnected'
  participantCount: number = 0
  private client: LiveKitClient = createLiveKitClient()
  private context: common.UIAbilityContext = getContext(this) as common.UIAbilityContext

  constructor() {
    this.setupEventHandlers()
  }

  // 加入房间
  async joinRoom(url: string, token: string): Promise<void> {
    if (this.roomState !== 'disconnected') {
      console.warn('Already connecting or connected')
      return
    }
    
    this.roomState = 'connecting'
    try {
      await this.client.connect(url, token, {
        publishAudio: true,
        audioOptions: {
          sampleRate: 48000,
          channelCount: 1,
          echoCancellation: true,
          noiseSuppression: true,
          autoGainControl: true
        }
      })
    } catch (error) {
      this.roomState = 'disconnected'
      console.error('加入房间失败:', error)
    }
  }

  // 离开房间
  async leaveRoom(): Promise<void> {
    await this.client.disconnect()
  }

  // 切换静音
  toggleMute(isMuted: boolean): void {
    this.client.setMuted(isMuted)
  }

  // 请求权限
  async requestPermissions(): Promise<void> {
    const atManager = abilityAccessCtrl.createAtManager()
    const result = await atManager.requestPermissionsFromUser(
      this.context,
      ['ohos.permission.MICROPHONE']
    )
    if (result.authResults[0] !== 0) {
      console.error('需要麦克风权限')
    }
  }

  // 设置事件处理器
  private setupEventHandlers(): void {
    this.client.on('connected', () => {
      this.roomState = 'connected'
      console.info('已连接到房间')
      
      // 启动音频电平观察
      this.client.startAudioLevelObserver((levels: AudioLevelInfo[]) => {
        for (let i = 0; i < levels.length; i++) {
          const info = levels[i]
          if (info.isLocal) {
            console.debug('本地说话状态:', info.isSpeaking)
          } else {
            console.debug('远端说话状态:', info.isSpeaking)
          }
        }
      }, { intervalMs: 500, speakingThreshold: 0.05 })
    })

    this.client.on('disconnected', () => {
      this.roomState = 'disconnected'
      this.client.stopAudioLevelObserver()
      console.info('已断开连接')
    })

    this.client.on('participantConnected', (data: ESObject) => {
      this.participantCount++
      console.info('参与者加入:', data.participant.identity)
    })

    this.client.on('participantDisconnected', (data: ESObject) => {
      this.participantCount--
      console.info('参与者离开:', data.participant.identity)
    })
  }
}

// 导出单例
let liveKitUtil = new LiveKitUtil()
export default liveKitUtil
```

### UI 层使用示例

```typescript
import liveKitUtil from './LiveKitUtil'

@Entry
@Component
struct Index {
  build() {
    Column() {
      Button('获取麦克风权限')
        .onClick(() => {
          liveKitUtil.requestPermissions()
        })
      
      Button('加入房间')
        .onClick(() => {
          const token = "your-jwt-token"
          const url = 'wss://your-livekit-server.com'
          liveKitUtil.joinRoom(url, token)
        })
      
      Button('退出房间')
        .onClick(() => {
          liveKitUtil.leaveRoom()
        })
      
      Button('切换静音')
        .onClick(() => {
          liveKitUtil.toggleMute(true)
        })
    }
  }
}
```

---

## 🔑 JWT Token 生成

LiveKit 使用 JWT Token 进行身份验证。Token 需要包含以下信息：

### Token 结构

```json
{
  "name": "用户名称",
  "video": {
    "roomJoin": true,
    "room": "房间名称",
    "canPublish": true,
    "canSubscribe": true,
    "canPublishData": true
  },
  "sub": "用户ID",
  "iss": "devkey",
  "nbf": 1779260966,
  "exp": 2139257366
}
```

### 生成方式

1. **服务端生成**（推荐）：通过 LiveKit 服务端 API 生成
2. **开发测试**：可使用 LiveKit 官方工具生成测试 Token

---

## 📡 LiveKit 服务器配置

### 服务器要求

- 支持 WebSocket 连接
- 使用 Protobuf 协议通信
- 提供 JWT Token 验证

### 连接地址格式

```
wss://your-livekit-server.com:port
```

---

## ⚠️ 注意事项

### 1. 权限申请

- 必须在使用前申请 `MICROPHONE` 权限
- 建议在应用启动时或进入通话页面前申请

### 2. 连接管理

- 避免重复调用 `connect()`
- 离开页面时务必调用 `disconnect()`
- 使用 `roomState` 状态管理连接状态

### 3. 音频电平观察

- 连接成功后再启动观察
- 断开连接时停止观察以节省资源
- 推荐轮询间隔：100-500ms

### 4. 错误处理

```typescript
try {
  await client.connect(url, token, options)
} catch (error) {
  console.error('连接失败:', error)
  // 处理错误，如提示用户、重试等
}
```

### 5. 内存管理

- 及时断开连接释放资源
- 避免创建多个客户端实例
- 使用单例模式管理客户端

---

## 🔧 常见问题

### Q1: 连接失败怎么办？

**A:** 检查以下项：
- 网络连接是否正常
- JWT Token 是否有效
- LiveKit 服务器地址是否正确
- 是否已申请麦克风权限

### Q2: 听不到对方声音？

**A:** 检查以下项：
- 对方是否已发布音频
- 本地是否已订阅（默认自动订阅）
- 设备音量是否开启
- 是否有其他应用占用音频

### Q3: 音频有回声怎么办？

**A:** 确保已启用回声消除：
```typescript
audioOptions: {
  echoCancellation: true  // 启用回声消除
}
```

### Q4: 如何判断是否在说话？

**A:** 使用音频电平检测：
```typescript
client.startAudioLevelObserver((levels) => {
  const localLevel = levels.find(l => l.isLocal)
  if (localLevel && localLevel.isSpeaking) {
    console.info('正在说话')
  }
})
```

### Q5: 支持哪些音频采样率？

**A:** 推荐使用：
- 48000 Hz（推荐，音质最佳）
- 44100 Hz
- 16000 Hz（节省带宽）

---

## 📚 API 参考

详细 API 文档请参考 `LiveKit/README.md`

### 核心方法

| 方法 | 说明 |
|------|------|
| `connect(url, token, options)` | 连接到房间 |
| `disconnect()` | 断开连接 |
| `setMuted(muted)` | 设置静音 |
| `isMicMuted()` | 查询静音状态 |
| `startAudioLevelObserver(callback, options)` | 启动音频电平观察 |
| `stopAudioLevelObserver()` | 停止音频电平观察 |

### 核心事件

| 事件 | 说明 |
|------|------|
| `connected` | 连接成功 |
| `disconnected` | 断开连接 |
| `participantConnected` | 参与者加入 |
| `participantDisconnected` | 参与者离开 |
| `trackSubscribed` | 收到远程音频 |
| `activeSpeakersChanged` | 说话人变化 |

---

## 📄 许可证

本项目遵循 MIT 许可证。

---

## 🆘 技术支持

如遇问题，请检查：
1. 项目构建是否成功
2. 权限是否正确配置
3. LiveKit 服务器是否正常运行
4. JWT Token 是否有效

更多详细信息请参考：
- [LiveKit 官方文档](https://github.com/livekit)
- [HarmonyOS 开发文档](https://developer.harmonyos.com)
