# 2026-06-05 补开面板重选 Bug 与直播浮层样式修复报告

## 背景

真机测试发现一个补开面板问题：如果一开始同时选择淘宝和抖音两路直播，随后停止其中一路，展开屏空半屏的“请选择直播平台”中两个选项都会置灰，导致被停止的那一路无法重新选择。

本轮修复为：

- 只有仍在直播的平台置灰不可选。
- 已停止的平台即使之前选择过，也恢复可选。
- 正在直播的平台文案追加“（正在直播中）”。
- 直播画面左上角状态浮层更小、更靠左上。
- 每路“停止直播”按钮改为红色，并缩小尺寸。

## 修改文件

### `LiveKit/src/main/ets/koophone/KooLiveSlotPolicy.ets`

新增纯策略方法：

- `isKooLiveAddOptionDisabled(isOptionLiveActive)`
  - 只根据是否正在直播判断是否禁用。
  - 解决“曾经选择过但已经停止的平台仍然置灰”的问题。
- `getKooLiveAddOptionTitle(title, isOptionLiveActive)`
  - 正在直播时返回 `平台名（正在直播中）`。
  - 非直播时返回原始平台名。

### `LiveKit/Index.ets`

新增导出：

- `isKooLiveAddOptionDisabled`
- `getKooLiveAddOptionTitle`

### `entry/src/main/ets/pages/Index1.ets`

调整方法：

- `isLiveAddOptionDisabled(platform)`
  - 原逻辑：`isPlatformSelected(platform) || isPlatformLiveActive(platform)`。
  - 新逻辑：只调用 `isKooLiveAddOptionDisabled(this.isPlatformLiveActive(platform))`。
  - 停止后的平台保持可选，正在直播的平台置灰。
- `getLiveAddOptionTitle(platform)`
  - 新增补开面板文案方法。
  - 正在直播的平台展示为 `淘宝直播（正在直播中）` 或 `抖音直播（正在直播中）`。
- `liveAddPlatformOption(platform)`
  - 改为使用 `getLiveAddOptionTitle(platform)`。

调整 UI：

- `streamStatusOverlay(platform)`
  - 平台名从 `12sp` 降到 `10sp`。
  - 状态/错误从 `9sp` 降到 `8sp`。
  - padding 缩小为 `4/6`。
  - 普通态 margin 从 `{ top: 12, left: 12 }` 改为 `{ top: 6, left: 6 }`。
  - 外屏切换按钮存在时的 top 从 `54` 改为 `48`。
- `stopPlatformButton(platform)`
  - 背景改为 `LIVE_RED`。
  - 尺寸从 `78x34` 改为 `66x28`。
  - 字号从 `11sp` 改为 `10sp`。
  - 右下角 margin 从 `{ right: 12, bottom: 14 }` 改为 `{ right: 8, bottom: 10 }`。

### `LiveKit/src/test/LocalUnit.test.ets`

新增测试：

- `enablesStoppedPlatformEvenIfItWasSelectedBefore`
  - 验证未直播平台不会被禁用，可重新选择。
- `labelsOnlyActivePlatformAsPlaying`
  - 验证只有正在直播的平台文案追加“（正在直播中）”。

## 行为说明

双选直播后停止其中一路：

- 被停止平台：可选，可以重新点击并开始直播。
- 仍在直播平台：置灰不可选，文案显示“（正在直播中）”。
- 点击被停止平台后，补开按钮变红，可重新串流该平台。

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

## 安全与安装规则

- git 提交继续保留 IAM 占位符。
- 真机安装继续使用完整体：临时注入真实 IAM 参数构建，安装后恢复源码占位符。
- 不提交真实 IAM 账号、密码、KooPhone `device_token` 或本机签名材料。
