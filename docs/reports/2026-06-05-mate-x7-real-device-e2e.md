# 2026-06-05 Mate X7 真机端到端联调报告

## 背景

本轮真实 Mate X7 已通过 `hdc` 连接到本机，设备 ID 为 `62H0125729000162`，设备型号返回 `DEL-AL10`。RenderService 能识别两块折叠屏：

- 展开屏：`2416x2210`
- 外屏：`1080x2444`

用户提供了两个真实 KooPhone 实例 ID：

- 淘宝直播：`dhb4q9j4`
- 抖音直播：`sKuBZq7c`

## 本轮代码增量

### `entry/src/main/ets/pages/Index1.ets`

新增常量：

- `KOOPHONE_AUTH_HOST`
- `TAOBAO_INSTANCE_ID`
- `DOUYIN_INSTANCE_ID`

实现能力：

- 淘宝实例鉴权路径自动拼成：
  `http://100.93.2.248:8669/openapi/koophone/v1/instances/dhb4q9j4/auth`
- 抖音实例鉴权路径自动拼成：
  `http://100.93.2.248:8669/openapi/koophone/v1/instances/sKuBZq7c/auth`
- `startPlatformIfReady()` 增加启动、鉴权成功、失败日志。
- `schedulePlatformRetry()` 增加每次重试日志。

### `LiveKit/src/main/ets/koophone/KooAuthService.ets`

新增脱敏诊断日志：

- IAM 请求开始。
- IAM HTTP 状态码。
- KooPhone auth 请求开始，实例 ID 用 `***` 脱敏。
- KooPhone auth HTTP 状态码。

不打印 IAM token、KooPhone `device_token` 或密码。

### `LiveKit/src/main/ets/koophone/KooAuthParser.ets`

增强 `parseKooInstanceAuthResponse(raw)`：

- `error_code` 同时兼容字符串 `"0"` 和数字 `0`。

### `LiveKit/src/test/LocalUnit.test.ets`

新增测试：

- `parsesNumericSuccessCode`：覆盖 KooPhone auth 返回数字型 `error_code: 0` 的情况。

## 真机验证步骤

已执行：

```bash
hdc -t 62H0125729000162 shell param get const.product.model
hdc -t 62H0125729000162 shell hidumper -s RenderService -a screen
hvigorw test --no-daemon --stacktrace -p properties.enableSignTask=false
hvigorw clean assembleApp --no-daemon --stacktrace
hdc -t 62H0125729000162 install -r entry/build/default/outputs/default/entry-default-signed.hap
hdc -t 62H0125729000162 shell aa start -b com.hssw.livekit -a EntryAbility
hdc -t 62H0125729000162 shell snapshot_display -f /data/local/tmp/livekit-matex7-real-selection.jpeg
hdc -t 62H0125729000162 shell snapshot_display -f /data/local/tmp/livekit-matex7-real-double-attempt.jpeg
```

验证结果：

- 真机安装签名 HAP 成功。
- 真机启动 `EntryAbility` 成功。
- 展开屏选择页显示正常。
- 自动双选淘宝、抖音后点击开始直播，进入左右双直播布局。
- 两路 `XComponent` 均加载完成并拿到 `surfaceId`。
- 两路各自独立执行 3 次自动重试。

截图：

- `outputs/livekit-matex7-real-selection.jpeg`
- `outputs/livekit-matex7-real-double-attempt.jpeg`

## 当前阻塞点

当前还没有真正调用 IAM HTTP 接口，因为 `Index1.ets` 中 IAM 配置仍为空：

- `domainName`
- `userName`
- `password`
- `projectName`（如果当前 IAM 需要 project scope）

真机页面和 hilog 都确认失败点为：

```text
Error: IAM config is incomplete; 已自动重试 3 次
```

关键 hilog：

```text
[Index1] 淘宝直播 start attempt 0/3
[Index1] Taobao XComponent loaded
[Index1] 淘宝直播 start failed: Error: IAM config is incomplete
[Index1] 抖音直播 start attempt 0/3
[Index1] Douyin XComponent loaded
[Index1] 抖音直播 start failed: Error: IAM config is incomplete
```

## 下一步

要继续完成真正端到端串流，需要把 IAM 字段补进本地配置后重新安装运行。补齐后预期链路为：

```text
startPlatformIfReady()
  -> KooAuthService.requestIamToken()
  -> POST https://iam.myhuaweicloud.com/v3/auth/tokens?nocatalog=true
  -> 读取 X-Subject-Token
  -> POST http://100.93.2.248:8669/openapi/koophone/v1/instances/{kp_id}/auth
  -> 解析 signaling_url / device_token / device_id
  -> KooPhonePlayer.open()
  -> KooSignalClient WebSocket
  -> KooRTCSource WebRTC 画面
```

真实 IAM 密码不应提交到 git；建议只在本地调试时临时填入，或者后续单独做一个不入库的本地配置注入机制。
