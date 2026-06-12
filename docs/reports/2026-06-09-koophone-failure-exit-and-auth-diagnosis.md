# 2026-06-09 KooPhone 失败态退出与鉴权诊断报告

## 背景

真机串流失败后，页面只显示失败文案，没有“停止直播”按钮，用户无法从失败态主动退出。同时需要判断当前失败是 IAM 实际 token 未获取，还是实例池全部尝试后耗尽。

## 根因

`Index1.ets` 里 `isPlatformLiveActive(platform)` 的判断是 `shouldStart && !failed`。当某路串流三次重试并切换实例后仍失败时，状态会变成 `failed`，因此该路不再进入 `liveControlLayer()`，而“停止直播”按钮只在 `liveControlLayer()` 里渲染。

外屏还有一个边界问题：`getFoldedSlotPlatform()` 原先只保留直播中或补开选择页的槽位。当前可见平台失败后，外屏可能回落到另一路或默认槽位，导致失败态本身不稳定可见。

## 修改内容

修改文件均在 `entry` 模块内：

- `entry/src/main/ets/koophone/KooLiveSlotPolicy.ets`
  - 新增 `KooLiveFailureStopState`。
  - 新增 `shouldShowKooLiveFailureStopControl()`，用于判断“失败但本次开流还未被用户退出”时必须展示停止控件。

- `entry/src/main/ets/pages/Index1.ets`
  - 新增 `shouldShowFailureStopControl()` 和 `shouldRenderFailureControlLayer()`。
  - 新增 `failureControlLayer(platform)`，在直播页顶层 Stack 里叠加失败态“停止直播”按钮。
  - `getFoldedDisplayPlatform()` 和 `getFoldedSlotPlatform()` 增加失败态保留逻辑，外屏当前失败槽位不会被自动吞掉。
  - `schedulePlatformRetry()` 达到最终失败时，使用 `buildTerminalFailureMessage()` 生成更明确的失败文案，并写入日志。
  - 新增 `describeTerminalFailureCause()`，按错误文本区分：
    - IAM 配置缺失或 IAM 请求失败：实际 IAM token 未获取。
    - IAM 响应缺少 `X-Subject-Token`：IAM token 未成功拿到。
    - KooPhone auth 失败：已进入实例鉴权阶段。
    - 其他：已进入 SDK open、信令或播放器阶段。

- `entry/src/main/ets/koophone/KooAuthService.ets`
  - `assertIamConfig()` 从统一的 `IAM config is incomplete` 改为带缺失字段的错误，例如 `domainName,userName,password`，但不会打印真实密码或 token。

- `entry/src/test/LocalUnit.test.ets`
  - 新增失败态停止控件策略测试，覆盖失败可退出、退出后隐藏、未失败不显示。

## 当前失败诊断结论

本轮用当前真机安装包重新点击淘宝直播复现后，通过 `uitest dumpLayout` 读取到页面失败文案：

```text
Error: IAM config is incomplete; 当前租户共享实例池已耗尽
```

因此这次失败的第一原因是 IAM 参数仍然不完整或没有在真机包里临时注入，实际 IAM token 没有获取到。页面上的“当前租户共享实例池已耗尽”是后续现象：同一个 IAM 配置错误在当前实例重试、切换共享池备用实例后重复发生，最终没有实例可切。

从当前提交代码也可以确认：git 中 IAM 参数仍是占位符，这是提交安全策略。如果真机安装包没有在构建前临时注入真实 IAM 参数，失败会首先落在 `IAM config is incomplete`，不会获取实际 IAM token，也不会真正进入有效的 KooPhone 实例鉴权。

修改后页面最终失败文案会直接说明阶段。例如：

- `IAM 配置不完整，实际 IAM token 未获取`
- `IAM token 请求失败，实际 IAM token 未获取`
- `KooPhone 实例鉴权失败，已进入实例鉴权阶段`
- `播放器或信令启动失败，已进入 SDK 开流阶段`

## 诊断命令

```bash
/Applications/DevEco-Studio.app/Contents/sdk/default/openharmony/toolchains/hdc list targets -v
/Applications/DevEco-Studio.app/Contents/sdk/default/openharmony/toolchains/hdc shell hilog -x -z 3000 | rg -i 'Index1|KooAuthService|IAM|KooPhone auth|__TAOBAO_INSTANCE_ID__|__DOUYIN_INSTANCE_ID__|retry|failed|实例池|X-Subject'
```

如果要重新抓一次，需要先打开应用并重新点击淘宝/抖音直播触发失败，再执行上面的 `hilog` 过滤命令。

## 验证

计划验证命令：

```bash
git diff --check
/Applications/DevEco-CommandLineTools/6.1.1.280/command-line-tools/bin/hvigorw test --no-daemon --stacktrace -p properties.enableSignTask=false
/Applications/DevEco-CommandLineTools/6.1.1.280/command-line-tools/bin/hvigorw clean assembleApp --no-daemon --stacktrace -p properties.enableSignTask=false
```

## 注意事项

- 本轮没有修改 `LiveKit` SDK 模块。
- 提交到 git 的 IAM、LiveKit SFU 等真实参数继续保持占位符。
- 真实完整体安装时仍需本地临时注入真实 IAM 参数后构建，安装后再恢复占位符。
