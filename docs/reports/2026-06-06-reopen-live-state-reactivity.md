# 2026-06-06 内屏补开直播状态响应式修复报告

## 背景

上一轮修复把重点放在旧外屏 surface 复用上：停止时清空 surface、替换 `XComponentController`、递增 `XComponent id`。这能减少旧 surface 复用风险，但没有解决用户反馈的核心现象：

- 外屏停止直播后，展开内屏补开同一路。
- 串流链路实际可以启动，日志里能看到 `KooPhonePlayer.open()`、remote video track、`playing`。
- 但内屏对应槽位仍显示“暂无直播内容”。
- 再合上外屏后，直播画面才出现。

## 真正原因

页面渲染直播层和空态层的判断最终依赖：

```text
liveSurfaceLayer(platform)
  -> isPlatformLiveActive(platform)
  -> shouldStartPlatform(platform)
  -> shouldStartTaobao / shouldStartDouyin
```

之前 `shouldStartTaobao / shouldStartDouyin` 是普通字段。补开时这些字段虽然被赋值为 `true`，但 ArkUI 不会因为普通字段变化触发重绘，所以内屏仍保留旧的空态分支。

当用户合上折叠屏时，`rootWidth` 是 `@State`，窗口尺寸变化触发页面重绘，直播层才重新计算并显示。这就是为什么画面看起来“只在外屏出现”。

## 本轮改动

### `entry/src/main/ets/pages/Index1.ets`

- 将 `shouldStartTaobao` 从普通字段改为 `@State`。
- 将 `shouldStartDouyin` 从普通字段改为 `@State`。
- `setShouldStartPlatform(platform, shouldStart)` 写入这两个 `@State` 字段后，ArkUI 会重新计算：
  - `liveSurfaceLayer(platform)`
  - `inactiveLiveSlotLayer(platform)`
  - `liveControlLayer(platform)`

这样外屏停止后再展开内屏补开时，点击“开始直播”后当前内屏槽位会立刻从空态切换到直播 surface 层，不需要再依赖折叠/展开触发重绘。

## 关于上一轮测试为什么无效

上一轮测试只验证了策略函数和构建：

- `shouldShowKooLiveAddPanel()`
- `buildKooLiveSurfaceComponentId()`
- `hvigorw test`
- `hvigorw clean assembleApp`

这些都不能覆盖 ArkUI `@State` 响应式渲染问题，也不能证明真机 native surface 生命周期正确。这个问题没有现成的自动化测试缝隙，需要真机折叠屏手动复现验证。

## 验证

- `git diff --check`
- `hvigorw test --no-daemon --stacktrace -p properties.enableSignTask=false`
- `hvigorw clean assembleApp --no-daemon --stacktrace`

## 真机验证步骤

1. 卸载手机旧包。
2. 安装最新完整体 HAP。
3. 内屏同时开启淘宝、抖音两路直播。
4. 合上折叠屏进入外屏。
5. 在外屏停止当前直播。
6. 展开内屏，在停止平台对应槽位选择并开始直播。
7. 预期：该内屏槽位立即显示直播画面，不再停留在“暂无直播内容”。
