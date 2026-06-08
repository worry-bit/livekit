# 2026-06-08 LiveKit 关闭推流入口临时关闭报告

## 背景

真机验证后，“关闭直播推流”仍会导致页面状态异常。为保证当前版本可稳定使用“开始直播推流”和“切换摄像头”，本轮按约定临时关闭关闭入口，但保留原关闭相关代码，后续可以继续排查恢复。

## 改动

### `entry/src/main/ets/pages/Index1.ets`

- 将 `ENABLE_LIVEKIT_PUSH_STOP_BUTTON` 从 `true` 改为 `false`。
- 推流中再次点击主按钮时，点击事件会直接被策略拦截，不再调用 `stopLiveKitPush()`。
- `stopLiveKitPush()`、强制复位代码和相关注释全部保留，后续只需要打开开关即可恢复入口。

### `entry/src/main/ets/push/LiveKitPushPolicy.ets`

- `getLiveKitPushButtonText()` 增加 `canStop` 参数。
  - `canStop=true`：保持原来的“关闭直播推流”。
  - `canStop=false`：显示“直播推流中”。
- `getLiveKitPushButtonColor()` 增加 `canStop` 参数。
  - 关闭入口禁用时，推流中按钮使用灰色。
- `canClickLiveKitPushButton()` 增加 `isPublished/canStop` 参数。
  - 未推流时仍可点击开始。
  - 已推流且 `canStop=false` 时不可点击。

### `entry/src/test/LocalUnit.test.ets`

- 补充关闭入口禁用策略测试：
  - 推流中显示“直播推流中”。
  - 推流中按钮置灰。
  - 已推流且关闭入口禁用时按钮不可点击。

## 验证

已执行：

```bash
git diff --check
DEVECO_SDK_HOME=/Users/wangrui/Downloads/command-line-tools/sdk /Users/wangrui/Downloads/command-line-tools/hvigor/bin/hvigorw test --no-daemon --stacktrace -p properties.enableSignTask=false
DEVECO_SDK_HOME=/Users/wangrui/Downloads/command-line-tools/sdk /Users/wangrui/Downloads/command-line-tools/hvigor/bin/hvigorw clean assembleApp --no-daemon --stacktrace -p properties.enableSignTask=false
```

结果：

- 单测通过。
- 占位符版本构建通过。
- 既有 webrtc 资源名冲突 warning 和 ArkTS warning 仍存在，不影响本轮改动。

## 恢复方式

如需恢复关闭入口，把 `Index1.ets` 中：

```ts
const ENABLE_LIVEKIT_PUSH_STOP_BUTTON = false
```

改回：

```ts
const ENABLE_LIVEKIT_PUSH_STOP_BUTTON = true
```

即可重新显示并启用“关闭直播推流”能力。
