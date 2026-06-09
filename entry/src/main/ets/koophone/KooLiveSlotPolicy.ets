export interface KooLiveAddSlotState {
  isExpandedScreen: boolean
  isFoldedVisibleStoppedSlot: boolean
  isSlotLiveActive: boolean
  isSlotFailed: boolean
  hasAnyLiveActive: boolean
  isPendingAdd: boolean
}

export interface KooLiveFailureStopState {
  shouldStart: boolean
  isSlotFailed: boolean
}

/**
 * 判断展开屏未直播半屏是否应展示补开直播选择页。
 * 内屏空半屏可补选；外屏只有“当前可见直播被用户停止且另一侧仍在播”时才展示。
 */
export function shouldShowKooLiveAddPanel(state: KooLiveAddSlotState): boolean {
  return (state.isExpandedScreen || state.isFoldedVisibleStoppedSlot) &&
    !state.isSlotLiveActive &&
    !state.isSlotFailed &&
    state.hasAnyLiveActive
}

/**
 * 判断补开直播按钮是否可点击。除了满足展示条件，还要求用户已在补开面板里
 * 选择了当前空槽位对应的平台。
 */
export function canStartKooLiveAddSelection(state: KooLiveAddSlotState): boolean {
  return shouldShowKooLiveAddPanel(state) && state.isPendingAdd
}

/**
 * 判断失败态是否仍应展示单路停止按钮。
 * 失败后 shouldStart 仍表示本次串流流程未被用户退出，必须允许用户手动收尾。
 */
export function shouldShowKooLiveFailureStopControl(state: KooLiveFailureStopState): boolean {
  return state.shouldStart && state.isSlotFailed
}

/**
 * 从内屏折叠到外屏时选择默认显示槽位。
 * 双路直播固定优先展示内屏左侧；只有左侧没有直播且右侧仍在播时才展示右侧。
 */
export function resolveKooFoldedVisibleSlot(isLeftLiveActive: boolean, isRightLiveActive: boolean): string {
  return isLeftLiveActive ? 'left' : (isRightLiveActive ? 'right' : 'left')
}

/**
 * 外屏只有双路直播时才显示切换按钮；内屏不显示该按钮。
 */
export function shouldShowKooFoldedSwitch(
  isExpandedScreen: boolean,
  isLeftLiveActive: boolean,
  isRightLiveActive: boolean
): boolean {
  return !isExpandedScreen && isLeftLiveActive && isRightLiveActive
}

/**
 * 外屏切换按钮的最终渲染开关。保留原有双路外屏切换策略，
 * 但允许页面层通过功能开关临时隐藏入口，后续恢复时只需要打开开关。
 */
export function shouldRenderKooFoldedSwitch(
  isSwitchFeatureEnabled: boolean,
  isExpandedScreen: boolean,
  isLeftLiveActive: boolean,
  isRightLiveActive: boolean
): boolean {
  return isSwitchFeatureEnabled &&
    shouldShowKooFoldedSwitch(isExpandedScreen, isLeftLiveActive, isRightLiveActive)
}

/**
 * 生成直播 XComponent 的稳定业务 id。surfaceRevision 递增时强制 ArkUI
 * 创建新的 native surface，避免停止后补开复用旧外屏 surface。
 */
export function buildKooLiveSurfaceComponentId(platformKey: string, surfaceRevision: number): string {
  return `${platformKey}-surface-${surfaceRevision}`
}

/**
 * 补开面板的选项禁用规则：只锁定仍在直播的实例。
 * 曾经选择过但已经停止的直播应恢复可选，允许用户重新补开。
 */
export function isKooLiveAddOptionDisabled(isOptionLiveActive: boolean): boolean {
  return isOptionLiveActive
}

/**
 * 补开面板里正在直播的平台要明确标注，避免用户以为两路都不可选。
 */
export function getKooLiveAddOptionTitle(title: string, isOptionLiveActive: boolean): string {
  return isOptionLiveActive ? `${title}（正在直播中）` : title
}
