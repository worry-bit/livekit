export interface KooInstancePoolEntry {
  id: string
}

export interface KooInstanceSelectionInput {
  currentInstanceId: string
  triedInstanceIds: string[]
  occupiedInstanceIds: string[]
}

/**
 * 判断实例 ID 是否出现在列表中。实例池容灾链路会频繁判断
 * “是否已尝试”和“是否被另一直播占用”，这里保持为纯函数方便单测。
 */
export function includesKooInstanceId(instanceIds: string[], instanceId: string): boolean {
  for (let i = 0; i < instanceIds.length; i++) {
    if (instanceIds[i] === instanceId) {
      return true
    }
  }
  return false
}

/**
 * 从共享实例池中选择下一个可用实例。
 *
 * 选择条件：
 * 1. 不能继续使用当前实例。
 * 2. 不能选择本平台本轮已经尝试过的实例。
 * 3. 不能选择另一直播正在占用的实例。
 *
 * 找不到候选时返回空字符串，由页面层展示“实例池耗尽”错误。
 */
export function selectNextAvailableKooInstance(
  pool: KooInstancePoolEntry[],
  input: KooInstanceSelectionInput
): string {
  for (let i = 0; i < pool.length; i++) {
    const candidateId = pool[i].id
    if (candidateId === input.currentInstanceId) {
      continue
    }
    if (includesKooInstanceId(input.triedInstanceIds, candidateId)) {
      continue
    }
    if (includesKooInstanceId(input.occupiedInstanceIds, candidateId)) {
      continue
    }
    return candidateId
  }
  return ''
}
