# 2026-06-08 entry 直接依赖 LiveKit SDK 边界清理报告

## 背景

用户指出 `entry/src/main/ets/koophone` 下的 `KooPhonePlayer / KooPhoneTypes / KooRTCSource / KooSignalClient` 等文件与 `LiveKit/src/main/ets/koophone` 下 SDK 文件重复。当前目标是：`LiveKit` 作为 SDK 保持最初状态，`entry` 不再复制 SDK 实现，而是直接依赖 `LiveKit`。

## 比对结果

本轮比对了 `entry/src/main/ets/koophone` 和 `LiveKit/src/main/ets/koophone` 的同名文件：

| 文件 | 结论 |
| --- | --- |
| `KooPhonePlayer.ets` | `entry` 内为 SDK 派生复制件，删除 |
| `KooPhoneTypes.ets` | `entry` 内为 SDK 类型复制件，删除 |
| `KooRTCSource.ets` | `entry` 内为 SDK 派生复制件，删除 |
| `KooSignalClient.ets` | `entry` 内为 SDK 派生复制件，删除 |
| `KooInputController.ets` | `entry` 内为 SDK 派生复制件，删除 |

同名文件扫描：

```bash
comm -12 <(find entry/src/main/ets -type f -name '*.ets' -exec basename {} \; | sort) <(find LiveKit/src/main/ets -type f -name '*.ets' -exec basename {} \; | sort)
```

当前无输出。

## 代码改动

- `entry/oh-package.json5`
  - 增加 `livekit-harmony: file:../LiveKit`。
  - 移除 `entry` 对 `@ohos/webrtc` 的直接依赖，改为由 SDK 自己声明。
- `entry/src/main/ets/pages/Index1.ets`
  - KooPhone 播放器、类型、输入控制改为从 `livekit-harmony/src/main/ets/koophone/...` 导入。
- `entry/src/main/ets/koophone/KooAuthTypes.ets`
  - `KooIceServer` 改为从 SDK 类型导入并转出。
- 删除 `entry/src/main/ets/koophone` 下 5 个 SDK 复制件。
- 删除 `entry/src/main/ets/livekit` 下 6 个 LiveKit SDK 复制件。
- `entry/src/main/ets/rtc/LiveKitUtil.ets`
  - 已改为从 `livekit-harmony` 顶层入口使用 `createLiveKitClient` 等 SDK 能力。

## LiveKit 状态

本轮没有修改 `LiveKit`：

```bash
git diff --name-status e5fb1b5 -- LiveKit
```

当前无输出。

注意：`LiveKit/Index.ets` 目前未导出 KooPhone 相关类，因此 `entry` 暂时使用深路径导入。后续如果 SDK 负责人只允许顶层导入，需要由 SDK 侧在 `LiveKit/Index.ets` 补充 KooPhone 导出。

## 验证

已通过：

```bash
/Applications/DevEco-CommandLineTools/6.1.1.280/command-line-tools/bin/ohpm install
git diff --check
/Applications/DevEco-CommandLineTools/6.1.1.280/command-line-tools/bin/hvigorw test --no-daemon --stacktrace -p properties.enableSignTask=false
```

完整 HAP 构建当前失败：

```bash
/Applications/DevEco-CommandLineTools/6.1.1.280/command-line-tools/bin/hvigorw clean assembleApp --no-daemon --stacktrace -p properties.enableSignTask=false
```

失败原因是 `LiveKit` 初始 SDK 源码在当前 DevEco/HarmonyOS ArkTS 编译器下存在 13 个 SDK 侧错误，主要包括：

- `KooInputController.ets` 的 `TouchAction / KeyAction` 对象字面量不符合 ArkTS 严格类型。
- `KooSignalClient.ets` 和 `KooPhonePlayer.ets` 的信令 payload 对象字面量未声明明确接口。
- `KooPhonePlayer.ets` 的动态索引访问不符合 ArkTS 限制。
- `KooPhonePlayer.ets` 和 `KooRTCSource.ets` 里的 SDP 对象缺少 `RTCSessionDescription.toJSON`。
- `RTCEngine.ets` 调用的 `VideoSource.release()` 不存在于当前 `@ohos/webrtc` 类型。

这说明：`entry` 侧重复实现已经清理干净；要恢复完整 HAP 构建，需要 SDK 侧修复原始 `LiveKit` 编译问题或提供可编译的 HAR/HSP。
