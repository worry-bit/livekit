# 双直播时 AI 眼镜预览推流黑屏修复

## 问题

单路云机直播时，AI 眼镜 CameraKit 预览兜底推流正常；同时打开淘宝和抖音两路云机直播后，再推 AI 眼镜预览流，SFU 端看到黑屏。

## 分析

当前 AI 眼镜推流仍是兜底链路：

```text
CameraKit AI Glasses preview -> XComponent surface -> @ohos/webrtc 屏幕采集 -> SFU
```

`@ohos/webrtc` 当前没有按 XComponent 矩形区域裁剪的公开参数，所以只能让页面进入“只显示预览 surface”的采集态。

双直播黑屏的高概率原因是 surface 生命周期竞态：

- 淘宝/抖音双直播时页面上存在两个 KooPhone `XComponent` surface。
- AI 眼镜推流切入全屏采集态时，页面会从双直播布局切到只显示 AI 预览的布局。
- 旧的本机推流小预览 surface 可能还被 `liveKitXCtrl` 持有。
- 如果直接复用旧 surfaceId，CameraKit 可能绑定到即将销毁、不可见或尺寸不对的 surface，屏幕采集端表现为黑屏。

## 修改

文件：`entry/src/main/ets/pages/Index1.ets`

### 新增常量

```ts
const AI_GLASSES_CAPTURE_SURFACE_WAIT_ROUNDS = 28
const AI_GLASSES_DISPLAY_CAPTURE_SETTLE_MS = 1200
```

### 新增方法

```ts
private async prepareAiGlassesDisplayCaptureSurface(reason: string): Promise<string>
```

能力：

- 进入 AI 眼镜采集态前先停止残留 CameraKit 预览。
- 清空旧 `liveKitSurfaceId`。
- 新建 `XComponentController`。
- 递增 `liveKitPreviewRevision`，强制 ArkUI 创建新的 native surface。
- 设置 `aiGlassesDisplayCaptureFocused = true`，让根页面切到全屏 AI 眼镜预览画布。
- 等待新的 full-screen surface `onLoad` 后，再把该 surfaceId 交给 CameraKit。

### 调整启动链路

AI 眼镜源启动时不再调用通用 `waitForLiveKitPreviewSurfaceId()`，而是调用：

```ts
await this.prepareAiGlassesDisplayCaptureSurface('start')
```

手机源仍走原来的本机预览 surface 链路。

### 调整切源链路

从手机视频流切到 AI 眼镜视频流时，不再复用当前小预览 surface，而是调用：

```ts
await this.prepareAiGlassesDisplayCaptureSurface('switch')
```

### 延迟屏幕采集

AI 眼镜 CameraKit 预览启动后，等待 `1200ms` 再调用 `publishDisplayVideo()`，避免双直播布局切换、全屏 surface 创建和首帧渲染还没稳定时就开始采集。

## 验证

- `git diff --check`
- `hvigorw assembleApp --no-daemon --stacktrace`
- 已安装到 Mate X7：`dist/full-params/entry-dev-all-in-ai-glasses-dual-live-black-fix-full-params-com.samples.ndkopengl-signed.hap`

## 仍需真机确认

请按以下路径验收：

1. 同时打开淘宝直播和抖音直播。
2. 点击“推送AI眼镜视频流”。
3. 确认手机 UI 切到只显示 AI 眼镜预览的黑底全屏画布。
4. 确认 SFU 端不再是黑屏，而是 AI 眼镜预览画面。

如果仍然黑屏，下一步需要抓取同一轮 hilog，重点看 `AI glasses display capture surface ready`、`CameraKit remote glasses preview started`、`publishDisplayVideo` 的先后顺序，以及 CameraKit 是否在双 KooPhone 会话存在时回调 `cameraInput error code=7400201`。
