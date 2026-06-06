# 2026-06-06 外屏停止后内屏补开 Surface 修复报告

## 背景

真机复现路径：

1. 内屏打开两路直播。
2. 合上折叠屏进入外屏。
3. 在外屏停止当前直播。
4. 打开内屏，在空槽位里选择刚刚停止的直播并开始。

问题表现：内屏对应槽位仍显示“暂无直播内容”，但合上到外屏后可以看到这一路新开的直播画面。

## 根因

上一版补开逻辑在 `startAdditionalPlatform(platform)` 里会立即调用 `syncPlatformSurfaceAndStart(platform)`。外屏停止直播后，旧的外屏 `XComponent` / native surface 销毁和内屏新 `XComponent` 创建并不是严格同步的。

在这个竞态窗口中，`XComponentController.getXComponentSurfaceId()` 可能仍返回外屏旧 surface。随后 `KooPhonePlayer.open(params, surfaceId)` 绑定到了旧外屏 surface，所以内屏当前槽位看起来仍是空态，只有再次合上外屏时才看到画面。

## 本轮改动

### `entry/src/main/ets/pages/Index1.ets`

- 新增 `taobaoSurfaceRevision / douyinSurfaceRevision`
  - 每路直播独立维护 surface 版本。

- 新增 `bumpPlatformSurfaceRevision(platform)`
  - 递增对应平台的 surface 版本。

- 新增 `invalidatePlatformSurface(platform)`
  - 清空该平台 `surfaceId`。
  - 设置 ready 为 `false`。
  - 调用 `KooPhonePlayer.setSurfaceId('')` 解除播放器旧 surface 绑定。
  - 替换该平台的 `XComponentController`。
  - 递增 surface revision，强制下一次渲染新 `XComponent`。

- 新增 `getPlatformXComponentId(platform)`
  - 使用 `buildKooLiveSurfaceComponentId(platform, revision)` 生成业务 id。

- 修改 `stopPlatformStream(platform)`
  - 单路停止时除了关闭播放器，还调用 `invalidatePlatformSurface(platform)`。
  - 这样外屏停止后再展开内屏补开时，不会继续复用旧外屏 surface。

- 修改 `taobaoSurface()` / `douyinSurface()`
  - `XComponent` 增加动态 `id`。
  - surface revision 变化时 ArkUI 会创建新的 native surface，播放器只能绑定当前槽位的新 surface。

### `LiveKit/src/main/ets/koophone/KooLiveSlotPolicy.ets`

- 新增 `buildKooLiveSurfaceComponentId(platformKey, surfaceRevision)`
  - 生成 `taobao-surface-1` 这类稳定 id。
  - 便于单测覆盖 revision 变化。

### `LiveKit/src/test/LocalUnit.test.ets`

- 新增 `changesSurfaceComponentIdWhenRevisionIncrements`
  - 验证 surface revision 递增会生成不同的 `XComponent id`。

## 验证

- `git diff --check`
- `hvigorw test --no-daemon --stacktrace -p properties.enableSignTask=false`
- `hvigorw clean assembleApp --no-daemon --stacktrace`

以上均已通过。构建中仍有既有资源名冲突、`ESObject` 使用限制和弃用 API 警告，本轮没有新增编译错误。

## 真机验证重点

- 内屏双路直播后合上外屏。
- 外屏停止当前直播。
- 展开内屏，在停止平台所在槽位重新选择并开始直播。
- 预期：画面直接出现在内屏对应槽位，不需要再合上外屏才显示。
- 再次折叠外屏时，外屏仍按当前活跃直播展示。
