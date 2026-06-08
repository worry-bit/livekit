# 2026-06-08 LiveKit upstream 刷新与 KooPhone SDK 导出报告

## 背景

用户要求将当前仓库的 `LiveKit/` 替换为 `SpikeX-21/livekit` 的最新 `LiveKit/`，后续以这个 SDK 为准。同时按给定 1-11 项修改 KooPhone 相关 SDK 文件，并让 `entry` 使用 SDK 顶层接口。

## upstream 替换

已执行：

```bash
git fetch upstream main --prune
git restore --source=upstream/main -- LiveKit
```

当前 upstream commit：

```text
bbc34ea5c09bca92ef80e94488e2655e021ae21a
```

upstream 最新 `LiveKit` 新增了 `KooUserMedia.ets`，当前已加入本仓库。

## SDK 修改

- `KooInputController.ets`
  - 为 `TouchAction / KeyAction` 增加显式接口类型，修复 ArkTS 对对象字面量的限制。
- `KooPhonePlayer.ets`
  - 调整本机摄像头轨道添加后的 DataChannel 文本消息字段。
  - answer/candidate payload 字段显式写成字符串 key。
  - `keeping_time` 改为 `60`。
  - offer/answer SDP 对象补 `toJSON()`。
  - UUID 生成函数替换为用户提供版本。
- `KooRTCSource.ets`
  - DataChannel `onmessage` 类型支持 `string | ArrayBuffer`。
  - 重协商 offer 和 answer 对象补 `toJSON()`。
- `KooSignalClient.ets`
  - 增加 `StartPayload`，`emitStart()` 使用显式 payload 类型。
- `Index.ets`
  - 顶层导出 KooPhone 相关公共接口，`entry` 不再依赖 SDK 深路径。
- `RTCEngine.ets / KooUserMedia.ets`
  - 额外去掉 `VideoSource.release()` 调用。当前 `@ohos/webrtc` 类型没有该方法，保留会导致编译失败。

## entry 调整

- `entry/src/main/ets/pages/Index1.ets`
  - KooPhone 相关导入改为 `from 'livekit-harmony'`。
- `entry/src/main/ets/koophone/KooAuthTypes.ets`
  - `KooIceServer` 改为从 `livekit-harmony` 顶层导入和转出。

## 验证

已通过：

```bash
/Applications/DevEco-CommandLineTools/6.1.1.280/command-line-tools/bin/ohpm install
git diff --check
/Applications/DevEco-CommandLineTools/6.1.1.280/command-line-tools/bin/hvigorw test --no-daemon --stacktrace -p properties.enableSignTask=false
/Applications/DevEco-CommandLineTools/6.1.1.280/command-line-tools/bin/hvigorw clean assembleApp --no-daemon --stacktrace -p properties.enableSignTask=false
```

构建产物：

```text
entry/build/default/outputs/default/app/entry-default.hap
entry/build/default/outputs/default/entry-default-unsigned.hap
```

运行尝试：

```bash
/Applications/DevEco-CommandLineTools/6.1.1.280/command-line-tools/sdk/default/openharmony/toolchains/hdc list targets
```

结果：

```text
[Empty]
```

当前没有可用真机或模拟器目标，所以未安装启动。
