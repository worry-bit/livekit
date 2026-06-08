# 2026-06-08 KooPhone 直播画面触摸代理层修复报告

## 背景

真机 Mate X7 上，淘宝/抖音 KooPhone 串流成功后，用户点击云机画面没有明显响应。此前页面把触摸直接挂在 `XComponent(SURFACE).onTouch` 上，并在其上方叠加直播状态、停止按钮、本机推流控制等 ArkUI 控件。

## 根因

真机日志显示点击可以命中直播 `XComponent`，但 `XComponent(SURFACE).onTouch` 在当前 Native surface 场景下不稳定触发。也就是说系统输入到达了 surface 区域，但页面侧不一定收到 ArkUI touch 回调，自然无法调用 `KooInputController.sendTouchEvent()`。

同时，原来的直播控制层是整屏/整半屏透明覆盖层，虽然设置了透明命中策略，但在 Native surface 与 ArkUI 叠层混用时会增加命中不确定性。

## 修改内容

修改文件：

- `entry/src/main/ets/pages/Index1.ets`

新增/调整能力：

- 新增 `liveTouchProxyLayer(platform)`：
  - 在每个可见直播 surface 上方放置同尺寸透明 ArkUI 触摸代理层。
  - 代理层接收 `onTouch` 后继续调用原有 `handleSurfaceTouch(platform, event)`。
  - 停止按钮等控制控件使用更高 `zIndex`，优先响应自己的点击。

- 调整 `handleSurfaceTouch(platform, event)`：
  - 触摸发送条件从“必须 `PLAYING`”放宽为“平台仍处于本次直播活跃态”。
  - DataChannel 未就绪时，SDK `inputController` 会自行丢弃，避免页面层误拦截已经有画面但状态尚未切到 `PLAYING` 的场景。

- 移除淘宝/抖音 `XComponent` 自身的 `.onTouch(...)`：
  - 避免依赖 Native surface 的 ArkUI touch 回调。
  - 避免代理层与 `XComponent` 未来同时触发导致重复发送。

- 收窄直播控制浮层命中范围：
  - `liveControlLayer()` 不再创建整屏透明覆盖容器。
  - `streamStatusOverlay()`、`stopPlatformButton()`、保留的 `foldedSwitchButton()` 改为按直播槽位绝对定位的小控件。
  - `liveKitPushOverlay()` 从全宽顶部栏改为只占用实际控制面板宽度，减少遮挡云机顶部区域。

## 真机验证

验证设备：Mate X7 真机。

验证结果：

- 双选淘宝/抖音后，两路均进入 `playing`。
- `dumpLayout` 显示每路直播 surface 上方都有 zIndex 20 的 `Stack` 触摸代理层。
- 临时日志验证点击进入 `handleSurfaceTouch()`，坐标为代理层局部坐标。
- 点击后日志出现云机侧 `app_message` 回调，说明输入已通过 DataChannel 发送到云机侧。
- `uitest uiInput swipe` 验证滑动时系统连续产生 `P:M` move 事件，命中对象仍为直播代理层 `Stack`，与点击走同一条转发链路。

## 验证命令

```bash
/Applications/DevEco-CommandLineTools/6.1.1.280/command-line-tools/bin/hvigorw clean assembleApp --no-daemon --stacktrace
/Applications/DevEco-Studio.app/Contents/sdk/default/openharmony/toolchains/hdc install -r entry/build/default/outputs/default/entry-default-signed.hap
/Applications/DevEco-Studio.app/Contents/sdk/default/openharmony/toolchains/hdc shell aa start -b com.hssw.livekit -a EntryAbility
/Applications/DevEco-Studio.app/Contents/sdk/default/openharmony/toolchains/hdc shell uitest uiInput click 1680 1280
/Applications/DevEco-Studio.app/Contents/sdk/default/openharmony/toolchains/hdc shell uitest uiInput swipe 1680 1800 1680 760 1200
```

## 注意事项

- 本轮没有修改 `LiveKit` SDK 模块。
- 提交到 git 的代码仍需保持 IAM、LiveKit SFU 等参数为占位符；真机安装完整体包时才临时注入真实参数。
