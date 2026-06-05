# 2026-06-05 KooPhone 实例鉴权接口接入增量报告

## 背景

本轮拿到 KooPhone 实例鉴权接口真实路径、请求头和返回结构。接口为 `POST`，IAM token 放在请求头 `x-auth-token` 中。实例鉴权返回的三个字段才是 SDK 开流时使用的真实参数：

| KooPhone auth 响应字段 | SDK 参数 |
|---|---|
| `data.resource.rtc.ice_signaling.signaling_url` | `signalingUrl` |
| `data.device_token` | `token` |
| `data.resource.device_id` | `boxId` |

因此旧的 `body.token` 解析和页面侧写死 `signalingUrl / boxId` 的方式已经废弃。

## 修改文件

### `LiveKit/src/main/ets/koophone/KooAuthParser.ets`

新增纯解析模块：
- `parseKooInstanceAuthResponse(raw: string): KooAuthTokenResult`

实现能力：
- 解析 `error_code / error_msg`，非 `0` 时抛出可读错误。
- 从 `data.resource.rtc.ice_signaling.signaling_url` 读取 `signalingUrl`。
- 从 `data.device_token` 读取 SDK `token`。
- 从 `data.resource.device_id` 读取 `boxId`。
- 透传 `data.streamingId` 到 `KooPhoneParams.streamingId`。
- 将 `ice_servers` 转换为 `KooIceServer[]`，后续真实 ICE server 返回不需要再改页面层。
- 缺少关键字段时抛出明确错误，便于页面重试和状态浮层展示。

### `LiveKit/src/main/ets/koophone/KooAuthService.ets`

修改方法：
- `requestSdkToken(config)`
  - 仍然先调用 IAM，再调用 KooPhone auth。
  - 返回结果改为完整 SDK 开流参数，不再只返回 token。
- `requestKooPhoneAuth(config, iamToken)`
  - 请求方式固定为 `POST`。
  - 请求头使用 `x-auth-token: <IAM X-Subject-Token>`。
  - 不再发送旧的 JSON body。
  - 响应交给 `parseKooInstanceAuthResponse()` 解析。

### `LiveKit/src/main/ets/koophone/KooPhoneTypes.ets`

修改类型：
- `KooPhoneParams`
  - 新增 `streamingId?: string`，实例鉴权返回时透传给信令连接。
- `LivePlatformConfig`
  - `signalingUrl / boxId` 改为可选，主路径不再依赖页面写死。
- `KooAuthTokenResult`
  - 新增 `signalingUrl / boxId / streamingId / iceServers`。
  - `token` 明确对应 KooPhone auth 返回的 `data.device_token`。

### `LiveKit/src/main/ets/koophone/KooPhonePlayer.ets`

修改方法：
- `open(params, surfaceId)`
  - 生成 `streamingId` 时优先使用 `params.streamingId`。
  - 未传入时仍回退为本地随机 UUID。

### `entry/src/main/ets/pages/Index1.ets`

修改配置：
- `TAOBAO_CONFIG.kooAuth.authUrl`
- `DOUYIN_CONFIG.kooAuth.authUrl`

2026-06-05 真机联调时已接入真实实例 ID，当前完整路径由 `KOOPHONE_AUTH_HOST` 和实例 ID 生成：

```text
http://100.93.2.248:8669/openapi/koophone/v1/instances/dhb4q9j4/auth
http://100.93.2.248:8669/openapi/koophone/v1/instances/sKuBZq7c/auth
```

后续更换实例时只替换 host 和 kp_id，不需要再改 SDK 参数组装代码。

修改方法：
- `buildKooPhoneParams(config, auth)`
  - `signalingUrl / boxId / token / streamingId / iceServers` 均从 KooPhone auth 返回结果组装。

### `LiveKit/src/test/LocalUnit.test.ets`

新增测试用例：
- `parsesSdkStreamingParams`
  - 使用本轮提供的实例鉴权响应结构，验证 `signalingUrl / token / boxId / streamingId` 映射正确。
- `throwsWhenDeviceTokenMissing`
  - 验证关键字段缺失时会抛出包含 `data.device_token` 的明确错误。

### 旧 H5 JS 参考文件 shim

`hvigorw test` 会把 `LiveKit/src/main/ets/koophone` 下的旧 H5 参考 JS 一起纳入 test bundle。它们不是当前 ArkTS 串流主链路，但原本缺少若干浏览器侧依赖，导致 CLI 测试无法跑完。

本轮新增最小兼容文件：
- `Constants.js`
- `ErrCode.js`
- `Version.js`
- `lib/EventEmitter.js`
- `lib/SocketIOClient.js`
- `lib/WebRTCAdapter.js`
- `util/ConsoleLog.js`
- `util/SdpUtils.js`
- `util/Utils.js`

并将旧 `Connection.js / RTCSource.js` 的外部依赖改成本地 shim。该修改只影响旧 JS 参考文件的测试打包解析，不改变当前 `KooPhonePlayer.ets / KooSignalClient.ets / KooRTCSource.ets` 主链路。

## 当前串流链路

```text
开始直播
  -> startSelectedStreams()
  -> XComponent.onLoad()
  -> startPlatformIfReady(platform)
  -> KooAuthService.requestSdkToken(config)
  -> POST IAM /v3/auth/tokens
  -> 取响应头 X-Subject-Token
  -> POST KooPhone /openapi/koophone/v1/instances/{kp_id}/auth
  -> 解析 signaling_url / device_token / device_id
  -> KooPhonePlayer.open(params, surfaceId)
```

## 验证

已执行：
- `git diff --check`
- `hvigorw test --no-daemon --stacktrace -p properties.enableSignTask=false`
- `hvigorw clean assembleApp --no-daemon --stacktrace -p properties.enableSignTask=false`
- `hdc -t 127.0.0.1:5555 install -r entry/build/default/outputs/default/app/entry-default.hap`
- `hdc -t 127.0.0.1:5555 shell aa start -b com.hssw.livekit -a EntryAbility`
- `hdc -t 127.0.0.1:5555 shell ps -ef | rg com.hssw.livekit`

验证结果：
- `hvigorw test`：`BUILD SUCCESSFUL`
- `assembleApp`：`BUILD SUCCESSFUL`
- Mate X7 模拟器安装启动成功，应用进程存在。

验证截图：
- `outputs/livekit-koophone-auth-selection.jpeg`

测试说明：
- 本轮新增 Hypium 本地单测文件。
- `hvigorw test` 会同时运行 `entry:test` 和 `LiveKit:test`，已通过。
- 测试阶段仍保留既有资源重复、`ESObject`、deprecated API 和 test bundle 权限 warning；这些不是本轮新增错误。

## 安全处理

- 未提交真实 IAM 账号、密码、KooPhone `device_token`。
- 当前提交包含用户提供的 KooPhone 内网 host 和两个实例 ID；远端仓库必须保持 private。
- `build-profile.json5` 中的本机自签名信息仍保留在本地，不纳入提交。
- 远端仓库 `worry-bit/livekit` 已确认是 `PRIVATE`。
