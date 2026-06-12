# AI Glasses remote camera 查询矩阵实验

时间：2026-06-10 11:30-11:34
设备：HUAWEI Mate X7 + HUAWEI AI Glasses-7667
代码边界：只修改 entry 侧实验代码，没有修改 LiveKit SDK 模块。

## 实验目的

验证下面这个查询入参是否过窄，是否因为只查了“后置 + 广角 + 远端”而漏掉了 AI 眼镜的其它 remote camera：

```ts
cameraManager.getCameraDevices(
  camera.CameraPosition.CAMERA_POSITION_BACK,
  [camera.CameraType.CAMERA_TYPE_WIDE_ANGLE],
  camera.ConnectionType.CAMERA_CONNECTION_REMOTE
)
```

## 本次 entry 侧新增的诊断代码

文件：`entry/src/main/ets/rtc/GlassesPreviewUtil.ets`

新增 `CameraPositionQueryCase` / `CameraTypeQueryCase` 两个接口，用来描述查询组合：

```ts
interface CameraPositionQueryCase {
  name: string
  value: camera.CameraPosition
}

interface CameraTypeQueryCase {
  name: string
  values: camera.CameraType[]
}
```

在严格查询返回后，追加调用 `logRemoteCameraQueryMatrix(cameraManager)`。这个方法只打日志，不改变实际选中的 CameraDevice。

```ts
// hilog 记录 getCameraDevices 返回的完整 CameraDevice 摘要。
this.logCameraDeviceList('getCameraDevices.remoteReturn', remoteCameras)
// 额外做一次 position/type 全组合枚举，排查 BACK + WIDE_ANGLE 过滤条件是否遗漏其他 AI 眼镜设备。
this.logRemoteCameraQueryMatrix(cameraManager)
```

核心矩阵方法：

```ts
private logRemoteCameraQueryMatrix(cameraManager: camera.CameraManager): void {
  const positions: CameraPositionQueryCase[] = [
    { name: 'UNSPECIFIED', value: camera.CameraPosition.CAMERA_POSITION_UNSPECIFIED },
    { name: 'BACK', value: camera.CameraPosition.CAMERA_POSITION_BACK },
    { name: 'FRONT', value: camera.CameraPosition.CAMERA_POSITION_FRONT },
    { name: 'FOLD_INNER', value: camera.CameraPosition.CAMERA_POSITION_FOLD_INNER }
  ]
  const allTypes: camera.CameraType[] = [
    camera.CameraType.CAMERA_TYPE_DEFAULT,
    camera.CameraType.CAMERA_TYPE_WIDE_ANGLE,
    camera.CameraType.CAMERA_TYPE_ULTRA_WIDE,
    camera.CameraType.CAMERA_TYPE_TELEPHOTO,
    camera.CameraType.CAMERA_TYPE_TRUE_DEPTH
  ]
  const typeCases: CameraTypeQueryCase[] = [
    { name: 'DEFAULT', values: [camera.CameraType.CAMERA_TYPE_DEFAULT] },
    { name: 'WIDE_ANGLE', values: [camera.CameraType.CAMERA_TYPE_WIDE_ANGLE] },
    { name: 'ULTRA_WIDE', values: [camera.CameraType.CAMERA_TYPE_ULTRA_WIDE] },
    { name: 'TELEPHOTO', values: [camera.CameraType.CAMERA_TYPE_TELEPHOTO] },
    { name: 'TRUE_DEPTH', values: [camera.CameraType.CAMERA_TYPE_TRUE_DEPTH] },
    { name: 'ALL_TYPES', values: allTypes }
  ]

  console.info(`${AI_GLASS_LOG_PREFIX} matrix begin positions=${positions.length}, typeCases=${typeCases.length}`)
  for (let positionIndex = 0; positionIndex < positions.length; positionIndex++) {
    const positionCase = positions[positionIndex]
    for (let typeIndex = 0; typeIndex < typeCases.length; typeIndex++) {
      const typeCase = typeCases[typeIndex]
      try {
        const cameras = cameraManager.getCameraDevices(
          positionCase.value,
          typeCase.values,
          camera.ConnectionType.CAMERA_CONNECTION_REMOTE
        )
        console.info(
          `${AI_GLASS_LOG_PREFIX} matrix position=${positionCase.name}, type=${typeCase.name}, ` +
            `count=${cameras.length}`
        )
        this.logCameraDeviceList(`matrix.${positionCase.name}.${typeCase.name}`, cameras)
      } catch (error) {
        console.warn(
          `${AI_GLASS_LOG_PREFIX} matrix position=${positionCase.name}, type=${typeCase.name}, ` +
            `error=${String(error)}`
        )
      }
    }
  }
  console.info(`${AI_GLASS_LOG_PREFIX} matrix end`)
}
```

## 真机安装和执行

构建命令：

```bash
PATH="/Applications/DevEco-Studio.app/Contents/tools/node/bin:/Applications/DevEco-Studio.app/Contents/tools/ohpm/bin:$PATH" \
DEVECO_SDK_HOME="/Applications/DevEco-CommandLineTools/6.1.1.280/command-line-tools/sdk" \
/Applications/DevEco-Studio.app/Contents/tools/hvigor/bin/hvigorw clean assembleApp --no-daemon --stacktrace
```

签名方式：

- 未修改仓库签名配置。
- 使用本机 DevEco 签名材料在内存中解密密码，调用 `hap-sign-tool.jar sign-app` 生成 `/tmp/livekit-entry-default-signed.hap`。
- 安装结果：`install bundle successfully`。

## 关键日志

日志文件：

```text
/tmp/ai_glasses_matrix_20260610_113401/hilog_all.txt
```

严格查询结果：

```text
[AI_GLASS_DBG] getCameraDevices input position=BACK,type=WIDE_ANGLE,connection=REMOTE
[AI_GLASS_DBG] getCameraDevices.remoteReturn count=1
[AI_GLASS_DBG] getCameraDevices.remoteReturn[0] camera[0] id=93bf...__Camera_device/0, conn=2, type=1, pos=1, host=AI Glasses, hostType=2609
```

矩阵结果：

```text
[AI_GLASS_DBG] matrix position=UNSPECIFIED, type=DEFAULT, error=Error: cameraDeviceList is null.
[AI_GLASS_DBG] matrix position=UNSPECIFIED, type=WIDE_ANGLE, error=Error: cameraDeviceList is null.
[AI_GLASS_DBG] matrix position=BACK, type=DEFAULT, error=Error: cameraDeviceList is null.
[AI_GLASS_DBG] matrix position=BACK, type=WIDE_ANGLE, count=1
[AI_GLASS_DBG] matrix.BACK.WIDE_ANGLE[0] camera[0] id=93bf...__Camera_device/0, conn=2, type=1, pos=1, host=AI Glasses, hostType=2609
[AI_GLASS_DBG] matrix position=BACK, type=ALL_TYPES, count=1
[AI_GLASS_DBG] matrix.BACK.ALL_TYPES[0] camera[0] id=93bf...__Camera_device/0, conn=2, type=1, pos=1, host=AI Glasses, hostType=2609
[AI_GLASS_DBG] matrix position=FRONT, type=ALL_TYPES, error=Error: cameraDeviceList is null.
[AI_GLASS_DBG] matrix position=FOLD_INNER, type=ALL_TYPES, error=Error: cameraDeviceList is null.
```

对照 `getSupportedCameras()`：

```text
[AI_GLASS_DBG] getSupportedCameras.allReturn count=2
[AI_GLASS_DBG] getSupportedCameras.allReturn[0] camera[0] id=device/0, conn=0, type=0, pos=1, host=, hostType=0
[AI_GLASS_DBG] getSupportedCameras.allReturn[1] camera[1] id=device/6, conn=0, type=4, pos=2, host=, hostType=0
```

实际打开 AI Glasses remote camera：

```text
[AI_GLASS_DBG] selected reason=hostDeviceName AI Glasses, camera[0] id=93bf...__Camera_device/0, conn=2, type=1, pos=1, host=AI Glasses, hostType=2609
[AI_GLASS_DBG] cameraInput error logger registered
[AI_GLASS_DBG] cameraOcclusionDetection logger registered
[GlassesPreviewUtil] remote camera supported scene modes: 1,2
[GlassesPreviewUtil] selected preview profile: 1280 720
[GlassesPreviewUtil] CameraKit remote glasses preview started with NORMAL_VIDEO session
[AI_GLASS_DBG] cameraInput error code=7400201, message=undefined, input.camera[0] id=93bf...__Camera_device/0, conn=2, type=1, pos=1, host=AI Glasses, hostType=2609
```

眼镜服务侧能识别绑定设备，并观察到 camera 状态先打开 remote camera，随后切回本机 `device/0`：

```text
VisionGlass: Services.DeviceManager.Device --> getBoundDevice res id C0:DA****:67 name HUAWEI AI Glasses-7667
VisionGlass: COMMON_EVENT_CAMERA_STATUS ... "cameraId":"93bf...__Camera_device/0","cameraState":18,"clientName":"com.hssw.livekit"
VisionGlass: COMMON_EVENT_CAMERA_STATUS ... "cameraId":"device/0","cameraState":2,"clientName":"com.hssw.livekit"
VisionGlass: COMMON_EVENT_CAMERA_STATUS ... "cameraId":"device/0","cameraState":0,"clientName":"com.hssw.livekit"
```

## 结论

这次结果基本排除了“查询入参选了后置 + 广角导致漏掉眼镜摄像头”的假设。

实际系统只暴露了一个 AI Glasses remote camera：

```text
position=BACK
type=WIDE_ANGLE
connection=REMOTE
hostDeviceName=AI Glasses
hostDeviceType=2609
```

`BACK + ALL_TYPES` 返回的也是同一个 remote camera，不存在另一个 `FRONT`、`FOLD_INNER`、`ULTRA_WIDE`、`TELEPHOTO` 或 `TRUE_DEPTH` 形态的 AI Glasses camera。

当前失败点不在枚举，也不在 `CameraDevice` 选择。entry 已经把 `hostDeviceName=AI Glasses` 的 remote `CameraDevice` 传给 `cameraManager.createCameraInput(cameraDevice)` 并启动了预览会话；失败发生在 CameraKit/眼镜服务后续状态切换阶段，应用层收到：

```text
cameraInput error code=7400201
```

同时眼镜服务把 active camera 从 remote `93bf...__Camera_device/0` 切回本机 `device/0`。这更像是眼镜服务策略、白名单、隐私灯/场景权限或 remote camera 服务内部限制导致的回退，不是 entry 传入的 CameraKit 查询参数不正确。
