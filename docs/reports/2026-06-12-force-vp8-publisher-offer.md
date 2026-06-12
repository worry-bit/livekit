# 2026-06-12 强制 VP8 发布端编码报告

## 背景

当前 AI 眼镜 demo 的 SFU 推流有两条路径：

- 本机摄像头：`Index1.ets -> LiveKitClient.publishVideo() -> RTCEngine.publishVideo()`
- AI 眼镜兜底录屏：`Index1.ets -> LiveKitClient.publishDisplayVideo() -> RTCEngine.publishDisplayVideo()`

两条路径最终都会把视频轨道添加到 `publisherPC`，然后走 `RTCEngine.negotiate()` 创建 publisher offer 并发送给 LiveKit SFU。因此强制上传 VP8 的最小改动点是 `RTCEngine.negotiate()`。

## 修改文件

### `LiveKit/src/main/ets/util/RTCEngine.ets`

新增发布端 SDP 改写逻辑：

- `forcePublisherOfferToVp8()`
  - 在 `createOffer()` 之后、`setLocalDescription()` 之前处理 publisher offer。
  - 打印改写前后的 `m=video` codec payload 顺序。
  - 如果没有 VP8，直接抛错，避免静默回落到 H264。
  - 本地 `setLocalDescription()` 仍使用原始 offer，避免 HarmonyOS WebRTC 因本地 SDP 与内部 codec 能力不完全一致而报 `Invalid argument`；发送给 SFU 的信令 offer 使用 VP8-only SDP。

- `forceVideoCodecInSdp()`
  - 定位 `m=video` 段。
  - 只保留 VP8 payload 和其关联 RTX payload。
  - 删除 H264、VP9、AV1、RED、ULPFEC 等其他视频 codec payload 相关的 `a=rtpmap`、`a=fmtp`、`a=rtcp-fb` 行。

- `describeVideoCodecOrder()`
  - 用于日志追踪实际 offer 中的视频编码顺序。
  - 真机日志应能看到类似：
    - `Publisher offer video codecs before VP8 force: ... H264 ... VP8 ...`
    - `Publisher offer video codecs after VP8 force: ... VP8 ...`
    - `Sent VP8-only publisher offer`
    - `Remote answer video codecs: ... VP8 ...`

没有使用 `RTCRtpTransceiver.setCodecPreferences()` 的原因：

- 当前工程依赖的 `@ohos/webrtc` HAR 没有稳定暴露 `RTCRtpSender.getCapabilities()`、`RTCRtpTransceiver`、`setCodecPreferences()` 等 ArkTS 类型/API。
- 直接写这些接口会增加编译风险。
- SDP 改写点位可控，且更容易通过日志和实际 offer 追踪。

### `LiveKit/src/main/ets/util/SignalClient.ets`

视频 `AddTrackRequest` 增加：

```ts
disableRed: type === 1
```

原因：

- VP8 强制主要由 SDP 完成。
- 同时关闭视频 RED，避免服务端继续尝试 RED 相关协商分支。

## 验证方式

编译检查：

```bash
git diff --check
hvigorw assembleApp --no-daemon --stacktrace -p properties.enableSignTask=false
```

真机日志关键字：

```bash
hdc hilog | grep -E "Publisher offer video codecs|VP8-only|Negotiate error"
```

判断标准：

- 成功：`after VP8 force` 只包含 `VP8` 和 `RTX(apt=VP8)`，随后出现 `Sent VP8-only publisher offer to SFU`，并且 `Remote answer video codecs` 也只包含 VP8 相关 payload。
- 失败：日志出现 `VP8 codec is not available in publisher offer SDP`，说明当前 WebRTC 生成的 publisher offer 本身没有 VP8，需要继续查 `@ohos/webrtc` 版本或创建视频源时的 codec 支持。

## 注意事项

- 本轮改动会同时影响本机摄像头推流和 AI 眼镜录屏兜底推流，因为二者共用 publisher offer。
- KooPhone 云机串流里的 `vcodec: H264` 不属于上传到 LiveKit SFU 的本机/眼镜视频流，本轮没有修改。
- 本地真实 IAM、SFU token、签名配置仍只用于打包安装，不应提交到远端。
