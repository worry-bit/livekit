# 2026-06-05 IAM 测试环境与 Mate X7 双路串流成功报告

## 背景

本轮补齐测试环境 IAM 接口信息后，在真实 Huawei Mate X7 上完成了双路端到端串流验证。两路直播分别绑定：

- 淘宝直播：KooPhone 实例 `__TAOBAO_INSTANCE_ID__`
- 抖音直播：KooPhone 实例 `__DOUYIN_INSTANCE_ID__`

测试环境接口：

- IAM token：`__IAM_AUTH_URL__`
- KooPhone auth host：`__KOOPHONE_AUTH_HOST__`

真实 IAM 账号和密码只在本地真机调试时临时写入，提交前已恢复为占位符。

## 代码增量

### `LiveKit/src/main/ets/koophone/KooAuthService.ets`

修改 `requestIamToken(config)`：

- IAM URL 不再拼 `?nocatalog=true`。
- 按测试环境要求把 `nocatalog: true` 放入 header。
- `Content-Type` 改为 `application/json`。
- 继续从响应头 `X-Subject-Token` 读取 IAM token。

新增 `isPlaceholder(value)`：

- `''`、`__IAM_DOMAIN_NAME__`、`__IAM_USER_NAME__`、`__IAM_PASSWORD__` 这类占位符都会被视为配置未完成。
- 防止提交后的占位符被误拿去请求 IAM。

### `entry/src/main/ets/pages/Index1.ets`

新增/调整顶部常量：

- `IAM_AUTH_URL`
- `IAM_DOMAIN_NAME`
- `IAM_USER_NAME`
- `IAM_PASSWORD`
- `IAM_PROJECT_NAME`
- `KOOPHONE_AUTH_HOST`
- `TAOBAO_INSTANCE_ID`
- `DOUYIN_INSTANCE_ID`

当前提交版保留测试环境 URL 和实例 ID，但 IAM 账号密码字段使用占位符：

```text
__IAM_DOMAIN_NAME__
__IAM_USER_NAME__
__IAM_PASSWORD__
```

真机调试时把这三个值替换为真实 IAM 信息即可。后续切生产环境时，如果请求体不变，只需要修改：

- `IAM_AUTH_URL`
- `KOOPHONE_AUTH_HOST`
- 必要时修改 `TAOBAO_INSTANCE_ID / DOUYIN_INSTANCE_ID`

新增/增强方法：

- `handlePlatformStateChange(platform, state)`
  - 统一同步播放器状态到页面。
  - 进入 `playing` 后清空本轮启动重试计数和错误。
  - 如果已启动后异常进入 `closed`，页面侧兜底触发重试，避免底层只抛状态不抛错误。
- `schedulePlatformRetry(platform, reason)`
  - 关闭播放器前先把 `started` 标记置为 `false`，避免状态兜底和显式错误重试互相递归。

### `LiveKit/src/main/ets/koophone/KooSignalClient.ets`

新增脱敏日志：

- `maskSignalUrl(url)`
- `maskQueryParam(input, key)`
- `maskId(value)`

实现能力：

- WebSocket 连接日志不再打印明文 `boxid/token/sessionid/streamingid`。
- start frame 日志只打印脱敏后的 room。
- init data frame 日志只打印 `type/to/dataLength`，不打印 base64 内容。

### `LiveKit/src/main/ets/koophone/KooPhonePlayer.ets`

新增脱敏日志：

- `maskId(value)`

实现能力：

- `Opening` 日志不再打印完整 `boxId`。
- `Init payload JSON/base64` 不再完整输出。
- `Sending init` 日志中的 `uuid/streamingId` 改为脱敏输出。

## 真机验证结果

设备：

- 真实 Mate X7：`62H0125729000162`
- 型号：`DEL-AL10`
- 展开屏分辨率：`2416x2210`

已执行：

```bash
git diff --check
hvigorw test --no-daemon --stacktrace -p properties.enableSignTask=false
hvigorw clean assembleApp --no-daemon --stacktrace
hdc -t 62H0125729000162 install -r entry/build/default/outputs/default/entry-default-signed.hap
hdc -t 62H0125729000162 shell aa start -b com.hssw.livekit -a EntryAbility
```

关键链路结果：

- 淘宝、抖音两路 `XComponent` 均加载完成。
- 两路 IAM token 请求均返回 `201`。
- 两路 KooPhone auth 均返回 `200`。
- 两路 WebSocket 均 `Authorize result: true`。
- 两路均收到 remote video track。
- 两路 WebRTC connection 均进入 `connected`。
- 两路播放器状态均进入 `playing`。
- 后续观察到 WebSocket close 后，页面层已补充 `closed` 状态兜底重试逻辑；当前提交版包含这个补强。

真机截图：

- `outputs/livekit-matex7-real-iam-e2e.jpeg`

脱敏日志：

- `outputs/livekit-matex7-real-iam-e2e-hilog-redacted.txt`

## 注意事项

- 当前 git 提交不包含 IAM 明文账号和密码。
- 本机真机上安装过的 HAP 曾包含临时测试 IAM 凭据，只用于本轮端到端验证。
- 如果后续重新构建提交版占位符代码，未替换 IAM 账号密码时页面会显示 `IAM config is incomplete`，这是预期保护行为。
- `device_token` 只有短有效期，但仍不能写入文档、commit 或长期日志。
