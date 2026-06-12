# 2026-06-10 AI 眼镜 CameraKit 接口说明

## 结论

当前 demo 里和 AI 眼镜摄像头相关的两个核心 CameraKit 接口是：

1. 枚举 AI 眼镜 remote camera：`cameraManager.getCameraDevices(...)`
2. 实际把 AI 眼镜 CameraDevice 交给 CameraKit 拉流：`cameraManager.createCameraInput(cameraDevice)`

其中 `createCameraInput(cameraDevice)` 只是创建输入对象，真正让系统开始启用摄像头的是后面的 `cameraInput.open()`、`session.addInput(cameraInput)`、`session.start()` 这一组调用。

当前真实 Mate X7 + HUAWEI AI Glasses-7667 抓到的结果是：

1. demo 已经通过 CameraKit 正确枚举到 `hostDeviceName = AI Glasses`、`connectionType = CAMERA_CONNECTION_REMOTE` 的远端摄像头。
2. demo 已经把这个 `CameraDevice` 传入 `createCameraInput(cameraDevice)`，并且 `cameraInput.open()`、`session.commitConfig()`、`session.start()` 都先后成功。
3. 报错不是发生在 entry 入参校验阶段，也不是因为没有传入 AI 眼镜设备；报错发生在系统/眼镜服务后续处理阶段。
4. app 最终收到的公开错误是 `cameraInput error code=7400201`，官方含义是 `Camera service fatal error`。
5. 底层日志显示 AI 眼镜/分布式相机链路随后执行了强制切回本机摄像头：`McuNotifyForceSwitchLocalCamera -> device/0`，并关闭了 distributed camera，底层返回 `result = -9, content = sink stop dcamera business`。

因此，从当前证据看，问题更像是 **AI 眼镜侧隐私灯/白名单/MCU 策略/分布式相机服务状态拒绝了本次第三方应用 remote camera 使用**，不像是 demo 传给 CameraKit 的入参不对。

上一轮真实抓取日志报告见：

```text
docs/reports/2026-06-09-ai-glasses-preview-log-capture.md
```

## 鸿蒙官方接口链接

- CameraManager：`getCameraDevices()` 和 `createCameraInput()` 所在官方页面
  https://developer.huawei.com/consumer/cn/doc/harmonyos-references/arkts-apis-camera-cameramanager
- `getCameraDevices()` 锚点
  https://developer.huawei.com/consumer/cn/doc/harmonyos-references/arkts-apis-camera-cameramanager#getcameradevices
- `createCameraInput()` 锚点
  https://developer.huawei.com/consumer/cn/doc/harmonyos-references/arkts-apis-camera-cameramanager#createcamerainput
- Camera 错误码，`7400201` 对应 `Camera service fatal error`
  https://developer.huawei.com/consumer/cn/doc/harmonyos-references-v5/errorcode-camera-V5

> 说明：华为网页在部分环境下不会稳定展开到锚点，但这几个接口属于同一个 `CameraManager` 官方页面。当前 demo 使用的是标准 `@kit.CameraKit` 的 `CameraManager` 能力。

## 接口一：枚举 AI 眼镜摄像头

### 接口

```ts
cameraManager.getCameraDevices(
  camera.CameraPosition.CAMERA_POSITION_BACK,
  [camera.CameraType.CAMERA_TYPE_WIDE_ANGLE],
  camera.ConnectionType.CAMERA_CONNECTION_REMOTE
)
```

### 代码位置

```text
entry/src/main/ets/rtc/GlassesPreviewUtil.ets
getRemoteCamerasFromConnectionQuery()
```

### 当前代码

```ts
const remoteCameras = cameraManager.getCameraDevices(
  camera.CameraPosition.CAMERA_POSITION_BACK,
  [camera.CameraType.CAMERA_TYPE_WIDE_ANGLE],
  camera.ConnectionType.CAMERA_CONNECTION_REMOTE
)
```

### 入参 JSON

```json
{
  "api": "camera.CameraManager.getCameraDevices",
  "cameraPosition": {
    "symbol": "camera.CameraPosition.CAMERA_POSITION_BACK",
    "valueFromLog": "BACK",
    "meaning": "只查询后置方向摄像头"
  },
  "cameraTypes": [
    {
      "symbol": "camera.CameraType.CAMERA_TYPE_WIDE_ANGLE",
      "valueFromLog": "WIDE_ANGLE",
      "meaning": "只查询广角摄像头"
    }
  ],
  "connectionType": {
    "symbol": "camera.ConnectionType.CAMERA_CONNECTION_REMOTE",
    "valueFromLog": 2,
    "meaning": "只查询远端/分布式摄像头，避免误选 Mate X7 本机摄像头"
  }
}
```

### 入参逐项解释

| 参数 | 当前传值 | 真实日志值 | 作用 | 为什么这样传 |
| --- | --- | --- | --- | --- |
| `cameraPosition` | `camera.CameraPosition.CAMERA_POSITION_BACK` | `BACK` / `1` | 查询后置方向摄像头。 | 当前 AI Glasses remote camera 返回 `cameraPosition = 1`，和 back 匹配。 |
| `cameraTypes` | `[camera.CameraType.CAMERA_TYPE_WIDE_ANGLE]` | `WIDE_ANGLE` / `1` | 查询广角摄像头。 | 当前 AI Glasses remote camera 返回 `cameraType = 1`，和 wide-angle 匹配。 |
| `connectionType` | `camera.ConnectionType.CAMERA_CONNECTION_REMOTE` | `REMOTE` / `2` | 只查询远端/分布式摄像头。 | 这是关键参数，用来避免误选 Mate X7 本机 `device/0`、`device/6`。 |

这里没有传入眼镜的蓝牙名、Wi-Fi 地址或外部设备句柄。CameraKit 的标准路径是：先让系统把眼镜注册成 remote camera，然后通过 `getCameraDevices(..., CAMERA_CONNECTION_REMOTE)` 拿到系统返回的 `CameraDevice` 对象。

### 反参 JSON

上一轮真实日志返回值：

```json
{
  "count": 1,
  "devices": [
    {
      "cameraId": "93bf0c42736ba0fb10955d6257dd12a7c1dc11e683983c67616488cb82dfaaa9__Camera_device/0",
      "connectionType": 2,
      "cameraType": 1,
      "cameraPosition": 1,
      "hostDeviceName": "AI Glasses",
      "hostDeviceType": 2609
    }
  ]
}
```

### 反参逐项解释

| 字段 | 当前真实值 | 含义 | 诊断价值 |
| --- | --- | --- | --- |
| `cameraId` | `93bf...__Camera_device/0` | 系统给这路 remote camera 分配的完整相机 id。 | 后续 `createCameraInput(cameraDevice)` 使用的是包含这个 id 的完整 `CameraDevice`。 |
| `connectionType` | `2` | remote connection。 | 证明它不是 Mate X7 本机摄像头。 |
| `cameraType` | `1` | wide-angle。 | 和入参 `[CAMERA_TYPE_WIDE_ANGLE]` 匹配。 |
| `cameraPosition` | `1` | back。 | 和入参 `CAMERA_POSITION_BACK` 匹配。 |
| `hostDeviceName` | `AI Glasses` | 远端设备主机名。 | 这是当前 demo 判断“这就是 AI 眼镜”的关键反参。 |
| `hostDeviceType` | `2609` | 远端设备类型，系统/厂商定义值。 | 进一步证明这是系统暴露的外部设备，不是普通本机相机。 |

对应日志：

```text
[AI_GLASS_DBG] getCameraDevices input position=BACK,type=WIDE_ANGLE,connection=REMOTE
[AI_GLASS_DBG] getCameraDevices.remoteReturn count=1
[AI_GLASS_DBG] getCameraDevices.remoteReturn[0] camera[0] id=93bf...__Camera_device/0, conn=2, type=1, pos=1, host=AI Glasses, hostType=2609
```

### 代码逻辑

1. 用 `CAMERA_CONNECTION_REMOTE` 只查远端摄像头。
2. 对返回的 `CameraDevice[]` 再做一次 `connectionType === 2` 校验。
3. 优先按 `preferredDeviceId` 精确匹配。
4. 如果没有传入固定 id，则按 `hostDeviceName === 'AI Glasses'` 选择眼镜。
5. 选中的 `CameraDevice` 会继续传给第二个接口 `createCameraInput(cameraDevice)`。

## 接口二：实际拉取 AI 眼镜摄像头

### 接口

```ts
cameraManager.createCameraInput(cameraDevice)
```

配套启用链路：

```ts
await cameraInput.open()
const previewOutput = cameraManager.createPreviewOutput(previewProfile, surfaceId)
const session = cameraManager.createSession(camera.SceneMode.NORMAL_VIDEO) as camera.VideoSession
session.beginConfig()
session.addInput(cameraInput)
session.addOutput(previewOutput)
await session.commitConfig()
await session.start()
```

### 代码位置

```text
entry/src/main/ets/rtc/GlassesPreviewUtil.ets
startPreview()
```

### 当前代码

```ts
const cameraInput = cameraManager.createCameraInput(cameraDevice)
this.registerCameraInputLoggers(cameraInput, cameraDevice)
await cameraInput.open()

const previewProfile = this.resolvePreviewProfile(cameraManager, cameraDevice, GLASSES_PREVIEW_SCENE_MODE)
const previewOutput = cameraManager.createPreviewOutput(previewProfile, surfaceId)
const session = cameraManager.createSession(GLASSES_PREVIEW_SCENE_MODE) as camera.VideoSession

session.beginConfig()
session.addInput(cameraInput)
session.addOutput(previewOutput)
await session.commitConfig()
await session.start()
```

### 入参 JSON

`createCameraInput(cameraDevice)` 的入参就是第一个接口返回并筛选后的 AI Glasses `CameraDevice`：

```json
{
  "api": "camera.CameraManager.createCameraInput",
  "cameraDevice": {
    "cameraId": "93bf0c42736ba0fb10955d6257dd12a7c1dc11e683983c67616488cb82dfaaa9__Camera_device/0",
    "connectionType": 2,
    "cameraType": 1,
    "cameraPosition": 1,
    "hostDeviceName": "AI Glasses",
    "hostDeviceType": 2609
  }
}
```

### `createCameraInput(cameraDevice)` 入参逐项解释

| 参数 | 当前传值 | 含义 | 是否来自 demo 手写 |
| --- | --- | --- | --- |
| `cameraDevice` | `getCameraDevices(..., CAMERA_CONNECTION_REMOTE)` 返回的 `CameraDevice` 对象 | CameraKit 需要的相机设备对象。 | 否。它不是 demo 拼出来的 JSON，而是 CameraKit 返回的对象。 |
| `cameraDevice.cameraId` | `93bf...__Camera_device/0` | AI 眼镜 remote camera 的系统 id。 | 否，来自系统反参。 |
| `cameraDevice.connectionType` | `2` | remote camera。 | 否，来自系统反参。 |
| `cameraDevice.hostDeviceName` | `AI Glasses` | 远端设备名。 | 否，来自系统反参。 |

demo 把系统返回的完整 `CameraDevice` 对象传给 `createCameraInput(cameraDevice)`。

后续预览输出和会话入参：

```json
{
  "createPreviewOutput": {
    "profile": {
      "size": {
        "width": 1280,
        "height": 720
      }
    },
    "surfaceId": "XComponent.onLoad 返回的 surfaceId"
  },
  "createSession": {
    "sceneMode": {
      "symbol": "camera.SceneMode.NORMAL_VIDEO",
      "valueFromCode": 2
    }
  },
  "sessionConfig": {
    "input": "AI Glasses cameraInput",
    "output": "XComponent previewOutput"
  }
}
```

### 后续会话入参逐项解释

| 接口 | 参数 | 当前传值 | 含义 |
| --- | --- | --- | --- |
| `cameraInput.open()` | 无显式业务参数 | 使用前面创建的 `CameraInput` | 打开 AI Glasses remote camera input。真机上这一步会触发眼镜本体的摄像头启用流程。 |
| `createPreviewOutput(profile, surfaceId)` | `profile` | `1280x720` | 从 AI Glasses remote camera 支持的 preview profiles 中选出的预览规格。 |
| `createPreviewOutput(profile, surfaceId)` | `surfaceId` | XComponent 返回值，例如日志中的 `7834020350603` | 页面上承接预览画面的 ArkUI surface。 |
| `createSession(sceneMode)` | `sceneMode` | `camera.SceneMode.NORMAL_VIDEO`，日志数值 `2` | 用普通视频场景创建 CameraKit 会话。当前远端设备支持的模式日志为 `1,2`，因此 `2` 是支持模式。 |
| `session.addInput(cameraInput)` | `cameraInput` | AI Glasses input | 把眼镜摄像头输入加入会话。 |
| `session.addOutput(previewOutput)` | `previewOutput` | XComponent preview output | 把预览画面输出到页面。 |
| `session.commitConfig()` | 无显式业务参数 | 当前 input/output 配置 | 提交会话配置。日志显示成功。 |
| `session.start()` | 无显式业务参数 | 当前 session | 启动相机会话。日志显示 `StartAsync errorCode:0` 并打印 preview started。 |

### 反参 / 回调 JSON

正常启动阶段日志：

```json
{
  "createCameraInput": "success",
  "cameraInput.open": "success",
  "selectedPreviewProfile": {
    "width": 1280,
    "height": 720
  },
  "session.commitConfig": "success",
  "session.start": "success"
}
```

正常启动阶段逐项解释：

| 阶段 | 真实结果 | 说明 |
| --- | --- | --- |
| `createCameraInput` | success | CameraKit 接受了 AI Glasses `CameraDevice`。 |
| `cameraInput.open` | success | remote camera input 打开成功，没有在 open 阶段因为入参类型/权限直接失败。 |
| `selectedPreviewProfile` | `1280x720` | 能从该设备能力中拿到可用预览规格。 |
| `commitConfig` | success | input/output 配置被 CameraKit 接受。 |
| `session.start` | success | 系统相机会话启动成功，entry 打印 `CameraKit remote glasses preview started`。 |

对应日志：

```text
CameraInput::InitCameraInput Contructor Camera: 93bf...__Camera_device/0
[AI_GLASS_DBG] cameraInput error logger registered
[AI_GLASS_DBG] cameraOcclusionDetection logger registered
[GlassesPreviewUtil] selected preview profile: 1280 720
StartAsync errorCode:0
[GlassesPreviewUtil] CameraKit remote glasses preview started with NORMAL_VIDEO session
```

失败回调：

```json
{
  "publicAppCallback": {
    "source": "cameraInput.on('error')",
    "code": 7400201,
    "message": null,
    "officialMeaning": "Camera service fatal error"
  },
  "cameraInputError": {
    "code": 7400201,
    "message": null,
    "cameraDevice": {
      "cameraId": "93bf0c42736ba0fb10955d6257dd12a7c1dc11e683983c67616488cb82dfaaa9__Camera_device/0",
      "connectionType": 2,
      "cameraType": 1,
      "cameraPosition": 1,
      "hostDeviceName": "AI Glasses",
      "hostDeviceType": 2609
    }
  },
  "cameraServiceCallback": {
    "source": "CameraDeviceServiceCallback::OnError",
    "errorType": 11,
    "errorMsg": 0
  },
  "cameraServiceError": {
    "errorType": 11,
    "errorMsg": 0
  },
  "dcameraHost": [
    {
      "eventType": 1,
      "result": -9,
      "content": "sink stop dcamera business"
    },
    {
      "eventType": 1,
      "result": -7,
      "content": ""
    }
  ]
}
```

失败返回逐项解释：

| 字段 | 当前值 | 含义 | 说明 |
| --- | --- | --- | --- |
| `publicAppCallback.source` | `cameraInput.on('error')` | entry 能直接收到的 CameraKit 错误回调。 | 这是公开 API 层能看到的失败入口。 |
| `publicAppCallback.code` | `7400201` | Camera Kit 错误码。 | 官方错误码说明为 `Camera service fatal error`，不是参数缺失或参数类型错误。 |
| `cameraServiceCallback.errorType` | `11` | CameraService 内部错误类型。 | 公开文档没有把这个内部类型展开成 AI 眼镜业务原因。 |
| `dcameraHost[0].result` | `-9` | 分布式相机底层返回。 | 同一行内容明确是 `sink stop dcamera business`，即接收端/眼镜侧停止 distributed camera 业务。 |
| `dcameraHost[1].result` | `-7` | 后续分布式相机通知。 | 内容为空，不能单独解释具体业务原因。 |

对应日志：

```text
CameraDeviceServiceCallback::OnError() is called!, errorType: 11, errorMsg: 0
[AI_GLASS_DBG] cameraInput error code=7400201, message=undefined, input.camera[0] id=93bf...__Camera_device/0, conn=2, type=1, pos=1, host=AI Glasses, hostType=2609
DCameraDevice::Notify for event type = 1, result = -9, content = sink stop dcamera business.
DCameraDevice::Close distributed camera: 93bf******ce/0
DCameraDevice::Notify for event type = 1, result = -7, content = .
```

## 眼镜服务执行的方法

上一轮日志里，AI 眼镜服务识别到 `com.hssw.livekit` 之后执行了这些方法：

```text
LiveVideoCallManager --> checkAppIsWhiteList
LiveVideoCallManager --> getWhiteListNames
LiveVideoCallManager --> sendAppIsWhiteListToMcu
XRGA_Camera_Control.CheckAppInWhiteList(appName: com.hssw.livekit)
XRGA_Camera_Control.McuNotifyForceSwitchLocalCamera
ConnectManager.SwitchCamera
Js_SwitchCamera
HCameraSwitchSession::SwitchCamera
HCameraSwitchSession::system forced switch
```

最关键的返回：

```json
{
  "aiGlassesService": {
    "whiteListCheckApp": "com.hssw.livekit",
    "sendAppIsWhiteListToMcuResult": 0,
    "forcedSwitch": {
      "method": "McuNotifyForceSwitchLocalCamera",
      "destCameraId": "device/0",
      "meaning": "眼镜服务把 camera 强制切回 Mate X7 本机摄像头"
    }
  }
}
```

## 错误发生时序

按真实 hilog 时间排序，关键时序是：

```text
22:47:53.867 entry 调 getCameraDevices(BACK, [WIDE_ANGLE], REMOTE)
22:47:53.867 CameraKit 返回 remote[0] host=AI Glasses, conn=2
22:47:53.868 entry 选择 hostDeviceName AI Glasses
22:47:54.542 entry 创建 PreviewOutput，profile=1280x720
22:47:54.573 entry 调 session.start()
22:47:54.593 entry 打印 CameraKit remote glasses preview started
22:47:54.593 xr_glass_app_service 执行 CheckAppInWhiteList: appName=com.hssw.livekit
22:47:54.613 xr_glass_app_service 收到 McuNotifyForceSwitchLocalCamera
22:47:54.620 camera_service 执行 HCameraSwitchSession::system forced switch，目标 device/0
22:47:54.629 dcamera_host 返回 result=-9, content=sink stop dcamera business
22:47:54.630 entry 收到 cameraInput error code=7400201
22:47:54.667 眼镜服务回调 OnCameraSwitch，确认 destCameraId=device/0
```

对应 JSON 摘要：

```json
{
  "entry": {
    "selectedCamera": {
      "hostDeviceName": "AI Glasses",
      "connectionType": 2,
      "cameraType": 1,
      "cameraPosition": 1
    },
    "cameraKitCalls": [
      "getCameraDevices(BACK, [WIDE_ANGLE], REMOTE)",
      "createCameraInput(aiGlassesCameraDevice)",
      "cameraInput.open()",
      "createPreviewOutput(1280x720, surfaceId)",
      "createSession(NORMAL_VIDEO)",
      "session.addInput(aiGlassesCameraInput)",
      "session.addOutput(previewOutput)",
      "session.commitConfig()",
      "session.start()"
    ],
    "publicError": {
      "callback": "cameraInput.on('error')",
      "code": 7400201,
      "message": null
    }
  },
  "aiGlassesService": {
    "whiteListCheck": {
      "method": "CheckAppInWhiteList",
      "appName": "com.hssw.livekit",
      "visibleFailureCode": null
    },
    "forcedSwitch": {
      "method": "McuNotifyForceSwitchLocalCamera",
      "destCameraId": "device/0",
      "result": "system forced switch"
    },
    "distributedCamera": {
      "result": -9,
      "content": "sink stop dcamera business"
    }
  }
}
```

## 是否是入参不对

当前证据不支持“demo 入参不对”这个判断，理由如下：

1. `getCameraDevices()` 的三个入参和返回值匹配：`BACK` 对应返回 `cameraPosition=1`，`WIDE_ANGLE` 对应返回 `cameraType=1`，`REMOTE` 对应返回 `connectionType=2`。
2. demo 传给 `createCameraInput()` 的不是手写对象，而是 CameraKit 自己返回的 `CameraDevice`。
3. `cameraInput.open()` 成功，说明 `createCameraInput(cameraDevice)` 和 open 阶段没有直接因为参数类型、权限或设备对象无效失败。
4. `getSupportedSceneModes()` 返回 `1,2`，当前使用 `NORMAL_VIDEO=2`，属于设备支持的场景模式。
5. `session.commitConfig()` 和 `session.start()` 都成功，失败是在 start 成功之后由眼镜服务/分布式相机链路上报。
6. 如果是典型参数缺失或参数类型错误，通常会更早暴露为参数类错误；本次公开错误是 `7400201 Camera service fatal error`，同时底层有 `sink stop dcamera business` 和 `system forced switch`。

更可能的原因是：

1. AI 眼镜侧检测到隐私灯/外置隐私保护条件不满足，所以停止 remote camera business。用户听到的“外置隐私灯被遮挡，无法使用此功能”与这一方向吻合。
2. `com.hssw.livekit` 虽然触发了 `CheckAppInWhiteList`，但当前日志没有展示白名单通过/拒绝的明确业务码；不能排除三方 bundle 未获得眼镜第一视角直播能力完整授权。
3. 眼镜 MCU 下发了强制切本机相机的动作，系统随后执行 `device/0`，说明眼镜侧或系统策略主动回退，而不是 entry 主动切回手机摄像头。
4. 公开 CameraKit API 没有把 AI 眼镜内部“隐私灯遮挡”的业务错误透成明确字段；entry 只能拿到泛化的 `7400201`。

## 当前判断

当前 demo 已经用 CameraKit 标准接口走到了 AI Glasses remote camera：

```text
getCameraDevices(BACK, [WIDE_ANGLE], REMOTE)
-> select CameraDevice.hostDeviceName == "AI Glasses"
-> createCameraInput(cameraDevice)
-> cameraInput.open()
-> createPreviewOutput()
-> createSession(NORMAL_VIDEO)
-> addInput/addOutput
-> commitConfig()
-> start()
```

真正失败点在 `session.start()` 成功后的眼镜服务/分布式相机阶段。AI 眼镜执行了白名单检查、MCU 通信、强制切回本机相机、关闭 distributed camera。当前日志可以证明“AI 眼镜服务停止了 remote camera business”，但不能从公开 API 里进一步证明它停止的唯一原因；结合眼镜语音播报，优先怀疑隐私灯/遮挡保护或眼镜侧对三方应用第一视角能力的策略限制。

最终结论：最终将包名换成了com.samples.ndkopengl并且将华为眼镜的app升级之后问题就解决了，所以当前代码完全没有问题确实可以获取到ai眼镜的摄像头的视频流
