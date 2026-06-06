/**
 * KooInputController — 将鸿蒙触摸/按键事件编码为云端可识别的二进制帧
 *
 * 帧格式完全对齐 H5 Input.js：
 *   WEB_INPUT_TOUCH_ext (205): 4B length + 1B type + 4B timestamp + 2B action + 1B count + n*(4B id + 4B x + 4B y)
 *   WEB_INPUT_KEY_ext   (207): 4B length + 1B type + 4B timestamp + 2B action + 2B keyCode + 2B modifiers
 *   WEB_TEXT_MESSAGE    (211): 4B length + 1B type + nB json
 */

// ==================== 常量（与 H5 KeyType 对应） ====================

const KEY_TYPE_TOUCH_EXT: number = 205
const KEY_TYPE_KEY_EXT: number = 207
const KEY_TYPE_TEXT_MSG: number = 211

// ==================== Action 枚举（与 H5 Action 对应） ====================

export enum TouchAction {
  DOWN = 0,
  UP = 1,
  MOVE = 2
}

export enum KeyAction {
  DOWN = 0,
  UP = 1
}

// ==================== 触点信息接口 ====================

export interface TouchPoint {
  id: number    // 触点 identifier
  x: number     // 归一化坐标 [0, 1]
  y: number     // 归一化坐标 [0, 1]
}

// ==================== DataChannel 发送接口 ====================

export type SendDataFn = (data: ArrayBuffer) => void

// ==================== KooInputController ====================

export class KooInputController {
  private sendData: SendDataFn | null = null

  // 组件尺寸（由外部设置，用于将像素坐标归一化）
  private viewWidth: number = 1
  private viewHeight: number = 1

  setSendFunction(fn: SendDataFn): void {
    this.sendData = fn
  }

  setViewSize(width: number, height: number): void {
    if (width > 0) this.viewWidth = width
    if (height > 0) this.viewHeight = height
  }

  /**
   * 发送触摸事件帧
   * @param action DOWN / UP / MOVE
   * @param touches 触点列表（像素坐标）
   * @param componentWidth  XComponent 当前宽度（px）
   * @param componentHeight XComponent 当前高度（px）
   */
  sendTouchEvent(action: number, touches: TouchPoint[]): void {
    if (!this.sendData || touches.length === 0) {
      return
    }

    const fingerCount = touches.length
    // 帧格式：4B len + 1B type + 4B ts + 2B action + 1B count + n*(4+4+4) bytes
    const frameLen = 12 + 12 * fingerCount
    const buf = new ArrayBuffer(frameLen)
    const view = new DataView(buf)
    let off = 0

    // length (big-endian, H5 用 setUint32 false = big-endian)
    view.setUint32(off, frameLen, false); off += 4
    // type
    view.setUint8(off, KEY_TYPE_TOUCH_EXT); off += 1
    // timestamp（毫秒，float32）
    view.setFloat32(off, Date.now() % 100000, false); off += 4
    // action（uint16）
    view.setUint16(off, action, false); off += 2
    // fingerCount
    view.setUint8(off, fingerCount); off += 1

    for (let i = 0; i < fingerCount; i++) {
      const t = touches[i]
      // 归一化坐标
      const nx = t.x / this.viewWidth
      const ny = t.y / this.viewHeight
      view.setUint32(off, t.id & 0xFFFFFFFF, false); off += 4
      view.setFloat32(off, Math.max(0, Math.min(1, nx)), false); off += 4
      view.setFloat32(off, Math.max(0, Math.min(1, ny)), false); off += 4
    }

    this.sendData(buf)
  }

  /**
   * 发送按键事件帧（对应 H5 makeKeyEvent）
   * @param action DOWN / UP
   * @param keyCode Android keyCode（参见 H5 Input.js _makeKeyCodeMap）
   * @param modifiers 修饰键 bitmask（默认 0）
   */
  sendKeyEvent(action: number, keyCode: number, modifiers: number = 0): void {
    if (!this.sendData) {
      return
    }

    const frameLen = 15
    const buf = new ArrayBuffer(frameLen)
    const view = new DataView(buf)
    let off = 0

    view.setUint32(off, frameLen, false); off += 4
    view.setUint8(off, KEY_TYPE_KEY_EXT); off += 1
    view.setFloat32(off, Date.now() % 100000, false); off += 4
    view.setUint16(off, action, false); off += 2
    view.setUint16(off, keyCode, false); off += 2
    view.setUint16(off, modifiers, false)

    this.sendData(buf)
  }

  /**
   * 发送 WebTextMessage（对应 H5 Input.makeWebTextMessage）
   * @param content 任意 JSON 可序列化对象
   */
  sendTextMessage(content: Record<string, Object>): void {
    if (!this.sendData) {
      return
    }

    const jsonStr = JSON.stringify(content)
    // 手动编码为 UTF-8 字节
    const textBytes = this.encodeUtf8(jsonStr)
    const frameLen = 5 + textBytes.length
    const buf = new ArrayBuffer(frameLen)
    const view = new DataView(buf)
    let off = 0

    view.setUint32(off, frameLen, false); off += 4
    view.setUint8(off, KEY_TYPE_TEXT_MSG); off += 1
    for (let i = 0; i < textBytes.length; i++) {
      view.setInt8(off, textBytes[i]); off += 1
    }

    this.sendData(buf)
  }

  // ==================== 私有工具方法 ====================

  private encodeUtf8(str: string): number[] {
    const bytes: number[] = []
    for (let i = 0; i < str.length; i++) {
      let code = str.charCodeAt(i)
      if (code < 0x80) {
        bytes.push(code)
      } else if (code < 0x800) {
        bytes.push(0xC0 | (code >> 6))
        bytes.push(0x80 | (code & 0x3F))
      } else {
        bytes.push(0xE0 | (code >> 12))
        bytes.push(0x80 | ((code >> 6) & 0x3F))
        bytes.push(0x80 | (code & 0x3F))
      }
    }
    return bytes
  }
}

export function createKooInputController(): KooInputController {
  return new KooInputController()
}
