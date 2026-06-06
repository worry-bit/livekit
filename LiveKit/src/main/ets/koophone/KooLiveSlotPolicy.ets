export interface KooLiveAddSlotState {
  isExpandedScreen: boolean
  isFoldedVisibleStoppedSlot: boolean
  isSlotLiveActive: boolean
  isSlotFailed: boolean
  hasAnyLiveActive: boolean
  isPendingAdd: boolean
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
