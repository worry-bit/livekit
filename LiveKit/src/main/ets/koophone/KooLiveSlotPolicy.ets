export interface KooLiveAddSlotState {
  isExpandedScreen: boolean
  isSlotLiveActive: boolean
  isSlotFailed: boolean
  hasAnyLiveActive: boolean
  isPendingAdd: boolean
}

/**
 * 判断展开屏未直播半屏是否应展示补开直播选择页。
 * 外屏不展示该面板；只有内屏且另一侧仍有直播时，空半屏才允许补选另一路。
 */
export function shouldShowKooLiveAddPanel(state: KooLiveAddSlotState): boolean {
  return state.isExpandedScreen &&
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
