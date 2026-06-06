# 2026-06-06 外屏切换按钮隐藏与重开直播 Surface 修复报告

## 背景

真机 Mate X7 测试发现：内屏双路直播后折叠到外屏，再展开内屏停止其中一路并重新选择该路开播时，内屏对应槽位可能继续显示“暂无直播内容”，而新开直播画面只在合上外屏后出现，再次展开后才恢复。

本轮同时按需求隐藏外屏“切换直播”按钮，但不删除能力代码，后续需要恢复时只打开功能开关。

## 本轮代码改动

### `entry/src/main/ets/pages/Index1.ets`

- 新增 `ENABLE_FOLDED_LIVE_SWITCH = false`
  - 外屏切换直播入口由功能开关隐藏。
  - `foldedSwitchButton()`、`toggleFoldedVisiblePlatform()`、`shouldShowFoldedSwitch()` 调用链仍保留。
  - 双路直播折叠到外屏时仍由 `prepareFoldedVisiblePlatformOnFold()` 默认展示内屏左侧淘宝直播。

- 新增 `setPlatformSurfaceId(platform, surfaceId)`
  - 统一写入淘宝/抖音两路当前 `surfaceId`。

- 新增 `setPlatformReady(platform, ready)`
  - 统一写入淘宝/抖音两路 `XComponent` ready 状态。

- 新增 `refreshPlatformSurfaceId(platform)`
  - 从对应 `XComponentController.getXComponentSurfaceId()` 读取当前 surface。
  - 读取成功后立即写入页面状态，并调用 `KooPhonePlayer.setSurfaceId(surfaceId)` 重绑播放器。

- 新增 `syncPlatformSurfaceAndStart(platform)`
  - 补开或重开时先同步当前 surface，再调用 `startPlatformIfReady(platform)`。
  - 避免使用已经失效的旧 surface，也避免必须等折叠/展开触发重绑。

- 新增 `schedulePlatformSurfaceSync(platform)`
  - 在 ArkUI 挂载新 `XComponent` 可能晚于按钮回调一帧的情况下，短延迟再次同步 surface。
  - `XComponent.onLoad()` 仍保留为最终兜底入口。

- 修改 `startAdditionalPlatform(platform)`
  - 设置 `shouldStart=true` 后立即清空补开临时选择。
  - 调用 `syncPlatformSurfaceAndStart(platform)` 和 `schedulePlatformSurfaceSync(platform)`。
  - 重开平台进入直播态后，内屏对应槽位会立即走直播 surface 层，不继续停留在空态。

- 修改 `taobaoSurface()` / `douyinSurface()`
  - `onLoad()` 改为复用 `refreshPlatformSurfaceId(platform)`。
  - `onDestroy()` 增加保护：只有该平台已经不再要求直播时才清空 surface，避免旧 surface 的销毁回调晚于新 surface 加载时把刚重开的播放器解绑。

### `LiveKit/src/main/ets/koophone/KooLiveSlotPolicy.ets`

- 新增 `shouldRenderKooFoldedSwitch(isSwitchFeatureEnabled, isExpandedScreen, isLeftLiveActive, isRightLiveActive)`
  - 保留原有 `shouldShowKooFoldedSwitch()` 策略。
  - 页面最终渲染入口增加功能开关参数。

### `LiveKit/Index.ets`

- 导出 `shouldRenderKooFoldedSwitch()`，供页面和测试复用。

### `LiveKit/src/test/LocalUnit.test.ets`

- 新增 `hidesFoldedSwitchWhenFeatureFlagIsDisabled`
  - 验证开关关闭时，即使外屏双路直播也不显示切换按钮。
  - 验证开关打开后原策略仍可用。

- 新增 `restartedSlotLeavesAddPanelAndReturnsToSurfaceState`
  - 验证停止平台重新进入直播态后，不再继续显示补开面板。

## 验证计划

- `git diff --check`
- `hvigorw test --no-daemon --stacktrace -p properties.enableSignTask=false`
- `hvigorw clean assembleApp --no-daemon --stacktrace`
- 真机 Mate X7 安装完整体 HAP：
  - 内屏双路直播后折叠到外屏，确认不显示“切换直播”按钮。
  - 展开内屏，停止任意一路，再重新选择并开始直播，确认该路画面立即出现在原内屏槽位。
  - 外屏停止当前直播后，确认补开选择页仍按“已停止可选、正在直播置灰并标注”显示。

## 注意事项

- Git 中仍保留 IAM 占位符，不提交真实账号密码。
- 真机安装时需要临时注入真实 IAM 参数构建完整体 HAP，安装完成后立刻恢复占位符。
- 外屏切换能力没有删除，只由 `ENABLE_FOLDED_LIVE_SWITCH` 隐藏。
