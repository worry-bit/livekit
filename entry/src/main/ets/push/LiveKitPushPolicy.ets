const LIVEKIT_PLACEHOLDER_PREFIX = '__LIVEKIT_'

export const LIVEKIT_PUSH_GREEN = '#2EAD5B'
export const LIVEKIT_PUSH_RED = '#E53935'
export const LIVEKIT_PUSH_DISABLED = '#8F98A6'

/**
 * 判断 LiveKit SFU 参数是否已替换为真实值。
 * git 中保留 __LIVEKIT_*__ 占位符，真机完整体安装时再临时注入真实 url/token。
 */
export function isLiveKitPushConfigReady(url: string, token: string): boolean {
  return isFilledLiveKitValue(url) && isFilledLiveKitValue(token)
}

function isFilledLiveKitValue(value: string): boolean {
  const normalized = value.trim()
  return normalized.length > 0 && normalized.indexOf(LIVEKIT_PLACEHOLDER_PREFIX) < 0
}

/**
 * 全局推流按钮文案。canStop=false 时保留推流能力，但隐藏关闭入口。
 */
export function getLiveKitPushButtonText(isPublished: boolean, isBusy: boolean, canStop: boolean = true): string {
  if (isBusy) {
    return isPublished ? '关闭中...' : '推流中...'
  }
  if (!isPublished) {
    return '开始直播推流'
  }
  return canStop ? '关闭直播推流' : '直播推流中'
}

/**
 * 全局推流按钮颜色：开始为绿色，关闭为红色，过渡态或关闭入口禁用时置灰。
 */
export function getLiveKitPushButtonColor(isPublished: boolean, isBusy: boolean, canStop: boolean = true): string {
  if (isBusy) {
    return LIVEKIT_PUSH_DISABLED
  }
  if (!isPublished) {
    return LIVEKIT_PUSH_GREEN
  }
  return canStop ? LIVEKIT_PUSH_RED : LIVEKIT_PUSH_DISABLED
}

/**
 * 只有本机摄像头预览 surface 准备好且当前没有异步操作时，才允许切换推流状态。
 */
export function canToggleLiveKitPush(isSurfaceReady: boolean, isBusy: boolean): boolean {
  return isSurfaceReady && !isBusy
}

/**
 * 推流按钮是否允许响应点击。关闭推流不依赖 preview surface；开始推流时页面会再做 surface 校验。
 * 这个策略避免关闭后 XComponent 尚未重新 onLoad 时，按钮长期处于灰色不可点状态。
 */
export function canClickLiveKitPushButton(isBusy: boolean, isPublished: boolean = false, canStop: boolean = true): boolean {
  if (isBusy) {
    return false
  }
  return !isPublished || canStop
}

/**
 * 本机摄像头预览 XComponent 的稳定业务 id。关闭推流后递增 revision，
 * 让 ArkUI 销毁旧 native surface，避免预览区停留最后一帧。
 */
export function buildLiveKitPreviewComponentId(baseId: string, revision: number): string {
  return `${baseId}-${revision}`
}

/**
 * 所有云机直播都停止、失败或页面退出时，需要释放本机摄像头推流。
 */
export function shouldStopLiveKitPush(hasTaobaoLiveActive: boolean, hasDouyinLiveActive: boolean): boolean {
  return !hasTaobaoLiveActive && !hasDouyinLiveActive
}
