# 2026-06-05 内屏补开第二路直播增量报告

## 背景

原逻辑中，如果只选择一路直播，Mate X7 展开屏另一半显示“暂无直播内容”。本轮改为：只有在展开内屏时，未直播半屏显示一套和初始页相同结构的“开始直播”选择页。已经选择或正在直播的平台置灰不可选，用户可以选择另一平台并在不停止已有直播的情况下补开第二路串流。

外屏仍只显示当前直播内容，不提供补开选择入口；用户需要展开内屏后在空半屏操作。

## 修改文件

### `LiveKit/src/main/ets/koophone/KooLiveSlotPolicy.ets`

新增纯策略模块：

- `KooLiveAddSlotState`
  - 描述空半屏补开面板的判断输入：是否展开屏、当前槽位是否直播、是否失败、是否已有任意直播、是否已临时选择补开平台。
- `shouldShowKooLiveAddPanel(state)`
  - 只有展开屏、当前槽位未直播、当前槽位未失败、另一侧存在直播时返回 `true`。
  - 外屏永远返回 `false`。
- `canStartKooLiveAddSelection(state)`
  - 在展示条件成立并且用户已经临时选择当前空槽位平台后返回 `true`。

### `LiveKit/Index.ets`

新增导出：

- `shouldShowKooLiveAddPanel`
- `canStartKooLiveAddSelection`
- `KooLiveAddSlotState`

entry 页面继续从 `livekit-harmony` 包入口导入，不跨 HAR 内部路径。

### `entry/src/main/ets/pages/Index1.ets`

新增状态：

- `pendingAddTaobao`
- `pendingAddDouyin`

这两个状态只用于内屏补开面板的临时选择，不直接代表已经开流。点击补开面板里的“开始直播”后，才会把对应 `selectedTaobao / selectedDouyin` 置为 `true`。

新增/调整方法：

- `clearPendingAddSelection()`
  - 清空补开面板临时选择。
- `isPlatformPendingAdd(platform)`
  - 判断某个平台是否在补开面板中被临时选中。
- `setPlatformPendingAdd(platform, pending)`
  - 写入补开面板临时选择。
- `togglePendingAddPlatform(platform)`
  - 点击补开面板的平台行时切换临时选中态。
  - 已选择或已直播的平台会直接 return，保持置灰不可选。
- `isLiveAddOptionDisabled(platform)`
  - 已选择过或正在直播的平台返回 `true`，用于置灰。
- `hasAnyPlatformLiveActive()`
  - 判断当前是否至少有一路直播处于活跃态。
- `shouldShowAdditionalSelection(platform)`
  - 页面层调用 `shouldShowKooLiveAddPanel()` 判断当前槽位是否显示补开选择页。
- `canStartAdditionalSelection(platform)`
  - 页面层调用 `canStartKooLiveAddSelection()` 控制补开按钮红/灰和点击。
- `getPreferredInstanceId(platform)`
  - 返回平台首选实例：淘宝 `dhb4q9j4`，抖音 `sKuBZq7c`。
- `setPlatformSelected(platform, selected)`
  - 统一设置平台选择状态。
- `assignInitialInstanceForPlatform(platform)`
  - 只给补开的单个平台分配实例，不重置另一侧正在播放的平台。
- `startAdditionalPlatform(platform)`
  - 内屏空半屏点击“开始直播”的入口。
  - 重置当前空槽位平台运行时状态。
  - 设置该平台为已选择、应启动。
  - 分配实例并触发 `startPlatformIfReady(platform)`。
  - 不影响已有直播。

新增 UI Builder：

- `liveAddIndicator(platform, disabled)`
  - 补开面板里的圆点。已直播/已选择时显示灰色锁定态；临时选择时显示红色选中态。
- `liveAddPlatformOption(platform)`
  - 补开面板的平台行。结构和初始选择页保持一致，但支持置灰不可点。
- `liveAddSelectionPanel(slotPlatform)`
  - 展开屏空半屏显示的选择页。
  - 包含“开始直播”、“请选择直播平台”、淘宝/抖音两行和右下角开始按钮。

调整 Builder：

- `platformLiveSlot(platform)`
  - 原来未活跃时直接显示 `emptyLivePanel(platform)`。
  - 现在如果满足内屏补开条件，显示 `liveAddSelectionPanel(platform)`。
  - 外屏不满足条件，仍只显示当前直播，不出现选择页。

## 行为说明

展开屏单路直播：

- 左侧淘宝直播中，右侧显示补开选择页。
- 右侧抖音直播中，左侧显示补开选择页。
- 已直播平台选项置灰不可选。
- 另一路平台可点选；点选后右下角“开始直播”变红。
- 点击开始后只启动另一平台，不关闭已有直播。

外屏单路直播：

- 只显示当前直播内容。
- 不显示补开选择页。
- 需要展开 Mate X7 内屏后，在另一半屏操作。

实例与重试：

- 补开的第二路也走完整 `IAM token -> KooPhone auth -> KooPhonePlayer.open()` 链路。
- 补开的第二路继续使用共享实例池规则：当前实例 3 次失败后切换备用实例，不抢占另一直播正在使用的实例。

## 测试

新增 Hypium 本地单测：

- `showsAddPanelOnlyForExpandedInactiveSlotWithAnotherActiveStream`
- `doesNotShowAddPanelOnFoldedScreen`
- `doesNotShowAddPanelForFailedSlot`
- `startsAdditionalSelectionOnlyAfterUserChoosesInactivePlatform`

已执行：

```bash
git diff --check
/Applications/DevEco-CommandLineTools/current/bin/hvigorw test --no-daemon --stacktrace -p properties.enableSignTask=false
/Applications/DevEco-CommandLineTools/current/bin/hvigorw clean assembleApp --no-daemon --stacktrace
```

结果：

- `git diff --check`：通过。
- `hvigorw test`：`BUILD SUCCESSFUL`。
- `hvigorw clean assembleApp`：`BUILD SUCCESSFUL`，签名 HAP 构建成功。

## 安全与安装规则

- git 提交继续保留 IAM 占位符。
- 真机安装时需要临时注入真实 IAM 参数，构建完整体 HAP 后安装。
- 安装完成后必须立即恢复源码占位符，不能把真实 IAM 参数提交到远端。
- 本机 `build-profile.json5` 是 DevEco 签名本地配置，不纳入提交。
