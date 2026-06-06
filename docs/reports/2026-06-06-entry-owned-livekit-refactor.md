# 2026-06-06 entry 承载业务能力与 LiveKit SDK 回退报告

## 背景

用户确认 `entry` 才是当前 App，`LiveKit` 是 SDK 模块，后续会由其他项目人员继续维护。为避免冲突，本轮要求把之前新增到 `LiveKit` 的业务能力迁回 `entry`，并让 `LiveKit` 除原始入口导出外回到最开始拉取的状态。

## 改动

### LiveKit SDK 回退

- `LiveKit` 当前与 `upstream/main` 对齐。
- 撤回之前在 SDK 中新增的 KooPhone auth、实例池、折叠屏策略、LiveKit 推流策略、单测、JS shim 和底层修补。
- `LiveKit/src/test/LocalUnit.test.ets` 回到初始示例测试，业务测试迁入 `entry/src/test/LocalUnit.test.ets`。

验证命令：

```bash
git diff --name-status upstream/main -- LiveKit
```

预期无输出。

### entry 承载业务能力

新增或保留在 `entry` 内的业务实现：

- `entry/src/main/ets/koophone/**`
  - IAM token 获取。
  - KooPhone 实例鉴权响应解析。
  - KooPhone 双路播放器、信令、RTC、输入控制。
  - 实例池和折叠屏槽位策略。
- `entry/src/main/ets/livekit/**`
  - 本机摄像头采集。
  - LiveKit SFU 建连。
  - 视频发布、取消发布、切换摄像头。
- `entry/src/main/ets/push/LiveKitPushPolicy.ets`
  - 本机推流按钮文案、颜色、占位符判断和自动关闭策略。
- `entry/src/test/LocalUnit.test.ets`
  - KooPhone auth、实例池、槽位策略、推流策略单测。

### 构建配置

- `entry/oh-package.json5` 移除 `livekit-harmony: file:../LiveKit`。
- `entry/oh-package.json5` 增加 `@ohos/webrtc`。
- `build-profile.json5` 的根模块列表移除 `LiveKit`，当前 App 构建只打 `entry`。

这样做的原因是：保持 SDK 源码初始状态时，不应让 App 构建继续被 SDK 内部实现和 SDK 团队后续改动影响。

## 验证

已执行：

```bash
/Applications/DevEco-CommandLineTools/6.1.1.280/command-line-tools/ohpm/bin/ohpm install
DEVECO_SDK_HOME=/Users/wangrui/Downloads/command-line-tools/sdk /Users/wangrui/Downloads/command-line-tools/hvigor/bin/hvigorw test --no-daemon --stacktrace -p properties.enableSignTask=false
git diff --check
DEVECO_SDK_HOME=/Users/wangrui/Downloads/command-line-tools/sdk /Users/wangrui/Downloads/command-line-tools/hvigor/bin/hvigorw clean assembleApp --no-daemon --stacktrace -p properties.enableSignTask=false
```

结果：

- `entry:test` 通过。
- `clean assembleApp` 通过。
- 构建日志只包含 `entry` 模块任务，不再编译 `LiveKit`。
- `@ohos/webrtc` 与 entry 资源存在 warning 级同名资源提示，不影响打包。

## 真机完整体构建与安装尝试

完整体构建流程：

- 临时注入真实 IAM 参数。
- 临时注入真实 LiveKit SFU url/token。
- 临时切换 `build-profile.json5` 到本机 `default_livekit` 签名材料。
- 执行 `assembleApp`，签名 HAP 构建成功。
- 构建完成后恢复占位符和仓库安全签名配置。

生成的完整体 HAP：

```text
entry/build/default/outputs/default/entry-default-signed.hap
```

安装尝试：

```bash
/Users/wangrui/Downloads/command-line-tools/sdk/default/openharmony/toolchains/hdc list targets
/Users/wangrui/Downloads/command-line-tools/sdk/default/openharmony/toolchains/hdc install -r entry/build/default/outputs/default/entry-default-signed.hap
```

结果：

- `hdc list targets` 返回 `[Empty]`。
- `hdc install` 返回 `ExecuteCommand need connect-key`。
- 当前 Mac 没有识别到 Mate X7 调试设备，所以 HAP 已构建但未能安装到真机。
- 重新插线、开启 USB 调试并在手机侧确认授权后，可直接用上述 HAP 路径重新安装。

## 敏感信息

- git 中保留 IAM 与 LiveKit SFU 占位符。
- 真机安装完整体时可以临时注入真实参数构建 HAP，安装后必须恢复占位符再提交。

## 后续建议

- SDK 团队如果提供稳定公共原子能力，`entry/src/main/ets/koophone/**` 和 `entry/src/main/ets/livekit/**` 中的适配实现可以再收敛到 SDK 公共导出。
- 当前阶段为了避免冲突，App 侧先保持功能闭合，SDK 侧不再继续改。
