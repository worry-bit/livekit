# 2026-06-05 单路停止、外屏切换与共享实例池容灾增量报告

## 背景

本轮在 Mate X7 双路 KooPhone 串流基础上继续增强直播态操作：

- 每路直播都有独立“停止直播”按钮。
- 外屏双路直播时可以切换当前可见直播。
- 展开屏布局固定为左淘宝、右抖音，外屏切换不影响展开屏槽位。
- 每个平台当前实例重试 3 次后，从同租户共享实例池里选择备用实例。
- 状态浮层和停止按钮降低到 30% 不透明度，减少遮挡真实云手机操作。

## 修改文件

### `LiveKit/src/main/ets/koophone/KooInstancePool.ets`

新增纯策略模块：

- `KooInstancePoolEntry`
  - 手写共享实例池条目，目前只包含 `id`，对应 KooPhone `kp_id`。
- `KooInstanceSelectionInput`
  - 选择备用实例所需上下文：当前实例、本平台已尝试实例、另一直播占用实例。
- `includesKooInstanceId(instanceIds, instanceId)`
  - 判断实例 ID 是否在列表中，用于跳过已尝试或被占用实例。
- `selectNextAvailableKooInstance(pool, input)`
  - 从共享池中选择第一个可用备用实例。
  - 规则为跳过当前实例、跳过本平台已尝试实例、跳过另一直播正在占用的实例。
  - 池耗尽时返回空字符串，由页面层展示失败状态。

### `LiveKit/Index.ets`

新增导出：

- `includesKooInstanceId`
- `selectNextAvailableKooInstance`
- `KooInstancePoolEntry`
- `KooInstanceSelectionInput`

这样 entry 页面可以通过 `livekit-harmony` 包入口调用实例池策略，不需要跨 HAR 内部路径深层导入。

### `entry/src/main/ets/pages/Index1.ets`

新增常量：

- `KOOPHONE_INSTANCE_POOL`
  - 当前包含 `dhb4q9j4` 和 `sKuBZq7c`。
  - 后续同租户备用实例可手动追加到这个列表。
- `OVERLAY_BACKGROUND = '#4D000000'`
  - 30% 黑色透明浮层。
- `CONTROL_BACKGROUND = '#4D20232A'`
  - 30% 停止/切换按钮背景。

新增状态和运行时字段：

- `foldedVisiblePlatform`
  - 外屏当前显示哪一路直播。
- `taobaoInstanceId / douyinInstanceId`
  - 两个平台当前使用的 KooPhone 实例。
- `taobaoTriedInstanceIds / douyinTriedInstanceIds`
  - 本轮直播中每个平台已经尝试过的实例集合。

新增/调整方法：

- `getPlatformConfig(platform)`
  - 按当前平台实例动态生成 KooPhone auth URL。
  - 实例切换后下一次重试会重新走 IAM + KooPhone auth。
- `buildKooAuthUrl(instanceId)`
  - 生成 `/openapi/koophone/v1/instances/{kp_id}/auth` 完整路径。
- `prepareInitialInstanceAssignments()`
  - 开始直播时设置平台首选实例：淘宝优先 `dhb4q9j4`，抖音优先 `sKuBZq7c`。
- `resolveInitialInstance(platform, preferredInstanceId)`
  - 首选实例不可用或被另一直播占用时，从共享池找空闲实例。
- `findNextAvailableInstance(platform)`
  - 调用 `selectNextAvailableKooInstance()` 查找备用实例。
- `switchToNextAvailableInstance(platform)`
  - 当前实例三次重试耗尽后切换备用实例；共享池耗尽时返回 `false`。
- `stopPlatformStream(platform)`
  - 只停止当前平台播放器、清理该路 retry timer、设置该路 `shouldStart=false`。
  - 不取消选择页勾选状态。
  - 两路都停止后回到选择页。
- `getFoldedDisplayPlatform()`
  - 外屏优先显示用户切到的平台；该平台停止/失败时自动回落到另一活跃平台。
- `toggleFoldedVisiblePlatform()`
  - 外屏双路直播时切换可见平台，不改变展开屏左右布局。
- `streamStatusOverlay(platform)`
  - 渲染 30% 不透明度状态浮层，平台名 `12sp`，状态/错误 `9sp`。
- `foldedSwitchButton()`
  - 外屏双路直播时的“切换直播”按钮。
- `stopPlatformButton(platform)`
  - 每路直播内部的“停止直播”按钮，字体 `11sp`。
- `platformLiveSlot(platform)`
  - 固定槽位渲染：活跃时显示直播面板，否则显示“暂无直播内容”或失败信息。
- `liveContent()`
  - 展开屏固定左淘宝、右抖音。
  - 外屏只显示 `getFoldedDisplayPlatform()` 返回的平台。

调整重试策略：

- `schedulePlatformRetry(platform, reason)`
  - 现改为“每个实例最多 3 次”。
  - 当前实例失败 3 次后调用 `switchToNextAvailableInstance(platform)`。
  - 每次同实例重试或切换实例后的重试，都会重新调用 IAM 和 KooPhone auth，避免复用短效 `device_token`。
  - 池耗尽后该平台进入 `failed`，另一平台不受影响。

### `LiveKit/src/test/LocalUnit.test.ets`

新增实例池策略单测：

- `selectsFirstBackupThatIsNotCurrentTriedOrOccupied`
  - 当前实例失败且另一直播占用第二个实例时，选择第三个备用实例。
- `doesNotSelectInstanceOccupiedByOtherLiveRoom`
  - 只有两个实例且另一路占用第二个实例时，返回空字符串，避免抢占。
- `skipsInstancesAlreadyTriedBySamePlatform`
  - 本平台已经尝试过的实例不会再次被选中。

### `docs/koophone-live-debug-guide.md`

补充：

- 架构图新增 `KooInstancePool`。
- 开始直播链路补充 `prepareInitialInstanceAssignments()`。
- 折叠屏布局更新为固定左右槽位和外屏可见平台切换。
- 重试逻辑更新为“每实例 3 次 + 共享实例池切换”。
- 真实参数位置补充 `KOOPHONE_INSTANCE_POOL`。

## 行为说明

展开屏：

- 左槽固定淘宝直播。
- 右槽固定抖音直播。
- 停止左路后左槽显示“暂无直播内容”，右路继续播放。
- 停止右路后右槽显示“暂无直播内容”，左路继续播放。

外屏：

- 单路直播时只显示该路。
- 双路直播时显示左上角“切换直播”按钮。
- 点击切换只改变外屏当前可见平台。
- 关闭当前可见直播后，如果另一直播还在运行，自动显示另一直播。
- 两路都关闭后返回选择页。

共享实例池：

- 淘宝优先 `dhb4q9j4`。
- 抖音优先 `sKuBZq7c`。
- 同一实例最多重试 3 次。
- 切备用实例时不抢占另一直播正在使用的实例。
- 池耗尽只让当前平台失败，不关闭另一平台。

## 验证

已执行：

```bash
git diff --check
/Applications/DevEco-CommandLineTools/current/bin/hvigorw test --no-daemon --stacktrace -p properties.enableSignTask=false
/Applications/DevEco-CommandLineTools/current/bin/ohpm install
/Applications/DevEco-CommandLineTools/current/bin/hvigorw clean assembleApp --no-daemon --stacktrace
```

当前结果：

- `git diff --check`：通过。
- `hvigorw test`：`BUILD SUCCESSFUL`。
- `ohpm install`：完成，依赖无新增变更。
- `hvigorw clean assembleApp`：`BUILD SUCCESSFUL`，`SignHap` 和 `SignApp` 均成功。
- 签名 HAP 产物：`entry/build/default/outputs/default/entry-default-signed.hap`。
- 测试阶段仍有既有资源重复、`ESObject`、deprecated API 和 INTERNET 权限 warning，不是本轮新增失败。

## 安全处理

- 未提交 IAM 明文账号、密码。
- 未提交 KooPhone `device_token`、`sessionid` 或临时 auth 返回。
- 提交内容包含 KooPhone 内网 host 和实例 ID，远端仓库必须保持 private。
- `build-profile.json5` 是本机/DevEco 签名相关本地改动，不纳入提交。
