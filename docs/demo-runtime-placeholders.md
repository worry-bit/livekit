# Demo 运行参数占位符说明

本仓库提交和 tag 中不保存 IAM 明文、SFU JWT、DevEco 签名材料路径或已签名 HAP。真实联调前需要在本地临时替换以下占位符，构建和安装完成后再恢复占位符。

## `entry/src/main/ets/pages/Index1.ets`

| 占位符 | 用途 | 示例格式 |
| --- | --- | --- |
| `__KOOPHONE_AUTH_HOST__` | KooPhone 实例鉴权服务 host | `http://<host>:<port>` |
| `__IAM_AUTH_URL__` | 华为云 IAM 获取 token 接口 | `https://<iam-endpoint>/v3/auth/tokens` |
| `__IAM_DOMAIN_NAME__` | IAM 账号所属 domain name | 租户 domain name |
| `__IAM_USER_NAME__` | IAM 用户名 | IAM user name |
| `__IAM_PASSWORD__` | IAM 用户密码 | IAM password |
| `__IAM_PROJECT_NAME__` | IAM project name | 例如区域 project name |
| `__TAOBAO_INSTANCE_ID__` | 淘宝直播默认 KooPhone 实例 ID | kp_id |
| `__TAOBAO_BACKUP_INSTANCE_ID__` | 淘宝直播备用 KooPhone 实例 ID | kp_id |
| `__DOUYIN_INSTANCE_ID__` | 抖音直播默认 KooPhone 实例 ID | kp_id |
| `__LIVEKIT_SFU_URL__` | LiveKit SFU WebSocket 地址 | `ws://<host>:<port>` |
| `__LIVEKIT_SFU_TOKEN__` | LiveKit room token/JWT | JWT 字符串 |
| `__LIVEKIT_GLASSES_CAMERA_DEVICE_ID__` | 可选 AI 眼镜 remote cameraId 优先值 | 不确定时保持占位符，运行时会枚举 AI Glasses |

## `build-profile.json5`

远端提交中 `signingConfigs` 为空，不包含本机签名材料。真机构建签名 HAP 时，需要在 DevEco Studio 中配置签名，或临时填入本机签名材料：

| 字段 | 用途 |
| --- | --- |
| `certpath` | DevEco 生成的 `.cer` 路径 |
| `profile` | DevEco 生成的 `.p7b` profile 路径 |
| `storeFile` | DevEco 生成的 `.p12` 路径 |
| `keyAlias` | p12 key alias |
| `keyPassword` | DevEco 加密后的 key password |
| `storePassword` | DevEco 加密后的 store password |

提交或打 tag 前必须再次确认 `build-profile.json5` 不包含本机绝对路径、`.p12/.cer/.p7b` 文件名或加密口令。

## 验证命令

提交前建议执行：

```sh
rg -n "<真实 IAM 用户名>|<真实 IAM 租户>|<真实 SFU JWT 前缀>|<本机签名配置名>|keyPassword|storePassword" \
  --glob '!oh_modules/**' --glob '!entry/build/**' --glob '!LiveKit/build/**' --glob '!dist/**' --glob '!screenshots/**' .
```

预期结果中不应出现真实 IAM 用户、真实 JWT、真实签名材料路径或口令。
