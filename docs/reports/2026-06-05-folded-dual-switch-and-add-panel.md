# 2026-06-05 外屏双直播切换与停止后补开面板修复报告

## 背景

真机 Mate X7 外屏双路直播测试发现三个问题：

- “切换直播”按钮位于左上角，和平台状态浮层抢位置。
- 点击“切换直播”后没有稳定切到另一直播画面。
- 外屏双路直播时停止当前直播，页面显示“暂无直播内容”，没有出现可重新选择的补开面板。

本轮修复目标是：外屏双路直播时右上角显示绿色切换按钮，点击后在两路画面间无缝切换；外屏停止当前直播后显示和初始页一致的选择面板，并沿用“已停止可选、正在直播置灰并追加（正在直播中）”的规则。

## 修改文件

### `entry/src/main/ets/pages/Index1.ets`

新增常量：

- `FOLDED_SWITCH_GREEN`
  - 外屏“切换直播”按钮背景色。

新增/调整方法：

- `isFoldedVisibleStoppedSlot(platform)`
  - 判断外屏当前可见槽位是否已经被用户停止，且另一平台仍在直播。
  - 该状态下允许外屏展示补开选择页。
- `getFoldedSlotPlatform()`
  - 外屏槽位选择入口。
  - 双路直播时显示 `foldedVisiblePlatform`。
  - 当前可见直播被停止后，保留在被停止的平台槽位，显示补开选择页。
  - 普通单路直播仍回落到活跃直播。
- `toggleFoldedVisiblePlatform()`
  - 仍只修改外屏可见平台，不影响展开屏左淘宝、右抖音布局。
  - 切换后主动调用当前平台播放器的 `setSurfaceId()`，保证播放器重新绑定当前可见 surface。
- `stopPlatformStream(platform)`
  - 如果外屏双路直播时停止当前可见平台，不再自动切到另一平台。
  - 保留 `foldedVisiblePlatform = platform`，清空补开临时选择，后续由补开面板承接。
- `foldedSurfaceLayer(platform)`
  - 外屏双路直播时保留单个平台 surface。
  - 通过 `opacity` 和 `zIndex` 控制当前可见直播。
- `foldedDualStreamPanel()`
  - 外屏双路直播专用面板。
  - 同时挂载淘宝、抖音两个 surface，避免切换时销毁另一直播 surface。
  - 左上角显示当前直播状态，右上角显示绿色“切换直播”，右下角“停止直播”作用于当前可见平台。

调整 UI：

- `foldedSwitchButton()`
  - 从左上角移到右上角。
  - 背景改为绿色。
  - 尺寸改为 `66x28`，圆角 `14`，字号 `10sp`。
- `streamStatusOverlay(platform)`
  - 平台名缩小到 `9sp`。
  - 状态/错误缩小到 `7sp`。
  - 贴近左上角，和右上角切换按钮形成对称的小型控制区。

### `LiveKit/src/main/ets/koophone/KooLiveSlotPolicy.ets`

扩展 `KooLiveAddSlotState`：

- 新增 `isFoldedVisibleStoppedSlot`
  - 表达“外屏当前可见槽位已停止但另一直播仍活跃”的场景。

调整 `shouldShowKooLiveAddPanel(state)`：

- 原逻辑只允许展开屏空半屏显示补开面板。
- 新逻辑允许两种场景显示：
  - 展开屏空半屏。
  - 外屏当前可见槽位被停止且另一平台仍在直播。

### `LiveKit/src/test/LocalUnit.test.ets`

新增测试：

- `showsAddPanelForFoldedStoppedVisibleSlot`
  - 验证外屏当前可见槽位停止后可以显示补开面板。
- `keepsSingleFoldedLiveFromShowingAddPanel`
  - 验证普通外屏单路直播不会提前显示补开面板。

### `docs/koophone-live-debug-guide.md`

补充：

- 外屏双路直播保留两路 surface，通过层级切换当前可见直播。
- 外屏停止当前直播后显示补开选择页。
- 右上角绿色“切换直播”和左上角状态浮层的最新布局。

## 行为说明

外屏双路直播：

- 左上角显示当前直播平台和状态。
- 右上角显示绿色“切换直播”按钮。
- 点击“切换直播”后，只切换外屏当前可见平台；展开屏左右布局不变。
- 两路 surface 都保持挂载，减少切换时黑屏或重新渲染的概率。

外屏停止当前直播：

- 当前平台停止。
- 页面停留在当前平台槽位并显示“请选择直播平台”。
- 被停止的平台可选。
- 仍在直播的平台置灰，文案追加“（正在直播中）”。
- 重新选择被停止平台并点击“开始直播”后，会重新走 IAM token、KooPhone auth、SDK open 流程。

普通外屏单路直播：

- 仍只显示当前直播画面。
- 不展示补开面板。
- 需要展开内屏后才能在另一半屏补开第二路。

## 验证命令

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

真机安装继续按既定规则处理：

- git 提交保持 IAM 占位符。
- 安装到 Mate X7 前临时注入真实 IAM 参数。
- 安装完成后恢复源码占位符，并重建占位符 HAP 覆盖本地产物。
