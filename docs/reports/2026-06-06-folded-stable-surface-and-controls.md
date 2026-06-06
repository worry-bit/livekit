# 2026-06-06 外屏稳定 Surface、无缝切换与控制层修复报告

## 背景

Mate X7 真机测试发现：内屏串流中合上折叠屏进入外屏时，外屏会黑屏约 15 秒才显示内容；同时外屏右下角“停止直播”、左上角直播状态、右上角“切换直播”控件出现过不可见或不可点的问题。

本轮目标：

- 内屏单路直播合上折叠屏后，外屏直接显示唯一活跃直播，不区分它原来在左半屏还是右半屏。
- 内屏双路直播合上折叠屏后，外屏默认显示内屏左侧直播；右上角“切换直播”可快速切到另一直播，再次点击切回。
- 外屏左上角状态浮层、右上角切换按钮、右下角停止按钮稳定显示在直播画面之上。
- 外屏停止当前直播后，显示补开选择页：被停止平台可选，另一正在直播平台置灰并显示“（正在直播中）”。

## 根因

上一版直播布局在内屏和外屏之间使用不同渲染分支：

- 内屏：`Row -> platformLiveSlot() -> streamPanel() -> XComponent`
- 外屏：`foldedDualStreamPanel() -> foldedSurfaceLayer() -> XComponent`

当 Mate X7 从内屏折叠到外屏时，ArkUI 会销毁内屏分支里的 `XComponent`，再创建外屏分支里的 `XComponent`。虽然播放器支持 `setSurfaceId()` 重绑 surface，但这个销毁和重建过程会导致 NativeVideoRenderer 释放后再初始化，出现明显黑屏等待。

控件消失的问题来自同一类布局分支和层级问题：`XComponent` 是 Native surface，外屏重建后可能盖住没有显式高层级的 ArkUI 控件。

## 修改文件

### `entry/src/main/ets/pages/Index1.ets`

新增/调整方法：

- `prepareFoldedVisiblePlatformOnFold()`
  - 内屏折叠到外屏时同步默认可见直播。
  - 双路直播时固定显示内屏左侧淘宝。
  - 只有右侧抖音直播时，外屏直接显示抖音。
- `getLiveSlotX(platform)`
  - 统一计算直播槽位横向位置。
  - 内屏右侧抖音位于 `rootWidth / 2`，外屏所有直播位于 `0`。
- `getLiveSlotWidth()`
  - 内屏返回 `50%`，外屏返回 `100%`。
- `isFoldedAddPanelVisible()`
  - 判断外屏当前是否处于“停止当前直播后的补开选择页”。
- `isSurfaceLayerVisible(platform)`
  - 判断当前平台 surface 是否应显示。
  - 外屏补开选择页出现时，隐藏另一直播 surface，避免选择页后面露出画面。
- `liveSurfaceLayer(platform)`
  - 新增稳定直播 surface 层。
  - 直播中的 `XComponent` 在内屏/外屏之间不再通过不同分支重建，只调整同一层的位置、宽度、透明度和 `zIndex`。
- `liveControlLayer(platform, showFoldedSwitch)`
  - 新增最高层控制层。
  - 左上角状态浮层、右上角切换按钮、右下角停止按钮统一放到 `zIndex(30+)`。
- `inactiveLiveSlotLayer(platform)`
  - 未直播槽位中层内容。
  - 显示补开选择页或“暂无直播内容”。
- `liveContent()`
  - 改为统一 `Stack`。
  - 底层：两路 `liveSurfaceLayer()`。
  - 中层：无直播槽位的补开页/空态。
  - 高层：当前直播控制层。

调整 `onAreaChange()`：

- 在更新 `rootWidth` 前记录是否原本是内屏。
- 如果本次变化是内屏进入外屏，调用 `prepareFoldedVisiblePlatformOnFold()`。

### `LiveKit/src/main/ets/koophone/KooLiveSlotPolicy.ets`

新增纯策略方法：

- `resolveKooFoldedVisibleSlot(isLeftLiveActive, isRightLiveActive)`
  - 双路或左路直播时返回 `left`。
  - 只有右路直播时返回 `right`。
- `shouldShowKooFoldedSwitch(isExpandedScreen, isLeftLiveActive, isRightLiveActive)`
  - 只有外屏且左右两路都直播时返回 `true`。

### `LiveKit/Index.ets`

新增导出：

- `resolveKooFoldedVisibleSlot`
- `shouldShowKooFoldedSwitch`

### `LiveKit/src/test/LocalUnit.test.ets`

新增测试：

- `defaultsFoldedDisplayToLeftSlotWhenBothStreamsActive`
- `defaultsFoldedDisplayToRightSlotWhenOnlyRightStreamActive`
- `showsFoldedSwitchOnlyForFoldedDualStreams`

### `docs/koophone-live-debug-guide.md`

更新：

- 串流链路从 `streamPanel()` 更新为 `liveSurfaceLayer()` 和 `liveControlLayer()`。
- 补充稳定 surface 层的作用。
- 补充折叠进入外屏时默认显示左侧直播的策略。
- 补充外屏控制层 `zIndex` 修复。

## 行为说明

单路直播：

- 淘宝单路：内屏左侧直播，折叠后外屏显示淘宝。
- 抖音单路：内屏右侧直播，折叠后外屏显示抖音。
- 外屏单路不显示补开选择页；需要展开内屏后补开第二路。

双路直播：

- 内屏左侧固定淘宝，右侧固定抖音。
- 折叠到外屏时默认显示淘宝。
- 点击右上角绿色“切换直播”可在淘宝和抖音之间切换。
- 切换不重建 WebRTC 会话，只调整可见 surface 层。

外屏停止当前直播：

- 停止当前平台播放器。
- 当前槽位显示补开选择页。
- 被停止平台可重新选择。
- 另一正在直播平台置灰，并显示“（正在直播中）”。

## 验证

已执行：

```bash
git diff --check
/Applications/DevEco-CommandLineTools/current/bin/hvigorw test --no-daemon --stacktrace -p properties.enableSignTask=false
/Applications/DevEco-CommandLineTools/current/bin/hvigorw clean assembleApp --no-daemon --stacktrace
```

结果：

- `git diff --check`：通过。
- `hvigorw test`：`BUILD SUCCESSFUL`。
- `hvigorw clean assembleApp`：`BUILD SUCCESSFUL`。

真机安装继续按既定安全规则处理：

- git 中 IAM 账号密码保持占位符。
- 真机安装前临时注入真实 IAM 参数构建完整体 HAP。
- 安装完成后恢复源码占位符，并重建占位符 HAP，避免本地产物残留真实参数。
