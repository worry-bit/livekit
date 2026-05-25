/**
 * 手动实现的 Protobuf 编解码器
 * 不依赖 protobufjs，避免鸿蒙的 new Function() 限制
 * 
 * 仅实现 LiveKit 信令协议需要的部分
 */

import { util } from '@kit.ArkTS'

// ==================== Wire Types ====================
const WIRE_VARINT = 0        // int32, int64, uint32, uint64, sint32, sint64, bool, enum
const WIRE_64BIT = 1         // fixed64, sfixed64, double
const WIRE_LENGTH_DELIM = 2  // string, bytes, embedded messages, packed repeated fields
const WIRE_32BIT = 5         // fixed32, sfixed32, float

// ==================== 编码工具函数 ====================

/**
 * 编码 varint
 */
function encodeVarint(value: number): Uint8Array {
  const bytes: number[] = []
  while (value > 0x7f) {
    bytes.push((value & 0x7f) | 0x80)
    value >>>= 7
  }
  bytes.push(value & 0x7f)
  return new Uint8Array(bytes)
}

/**
 * 编码字段 tag
 */
function encodeTag(fieldNumber: number, wireType: number): Uint8Array {
  return encodeVarint((fieldNumber << 3) | wireType)
}

/**
 * 编码 string
 */
function encodeString(value: string): Uint8Array {
  const textEncoder = new util.TextEncoder()
  const strBytes = textEncoder.encodeInto(value)
  const lenBytes = encodeVarint(strBytes.length)
  const result = new Uint8Array(lenBytes.length + strBytes.length)
  result.set(lenBytes, 0)
  result.set(strBytes, lenBytes.length)
  return result
}

/**
 * 编码带 tag 的 string 字段
 */
function encodeStringField(fieldNumber: number, value: string): Uint8Array {
  if (!value) return new Uint8Array(0)
  const tag = encodeTag(fieldNumber, WIRE_LENGTH_DELIM)
  const data = encodeString(value)
  const result = new Uint8Array(tag.length + data.length)
  result.set(tag, 0)
  result.set(data, tag.length)
  return result
}

/**
 * 编码带 tag 的 int32 字段
 */
function encodeInt32Field(fieldNumber: number, value: number): Uint8Array {
  if (value === 0) return new Uint8Array(0)
  const tag = encodeTag(fieldNumber, WIRE_VARINT)
  const data = encodeVarint(value)
  const result = new Uint8Array(tag.length + data.length)
  result.set(tag, 0)
  result.set(data, tag.length)
  return result
}

/**
 * 编码带 tag 的 bool 字段
 */
function encodeBoolField(fieldNumber: number, value: boolean): Uint8Array {
  const tag = encodeTag(fieldNumber, WIRE_VARINT)
  const result = new Uint8Array(tag.length + 1)
  result.set(tag, 0)
  result[tag.length] = value ? 1 : 0
  return result
}

/**
 * 编码嵌套消息字段
 */
function encodeMessageField(fieldNumber: number, data: Uint8Array): Uint8Array {
  if (data.length === 0) return new Uint8Array(0)
  const tag = encodeTag(fieldNumber, WIRE_LENGTH_DELIM)
  const lenBytes = encodeVarint(data.length)
  const result = new Uint8Array(tag.length + lenBytes.length + data.length)
  result.set(tag, 0)
  result.set(lenBytes, tag.length)
  result.set(data, tag.length + lenBytes.length)
  return result
}

/**
 * 合并多个 Uint8Array
 */
function concatBytes(arrays: Uint8Array[]): Uint8Array {
  let totalLen = 0
  for (let i = 0; i < arrays.length; i++) {
    totalLen += arrays[i].length
  }
  const result = new Uint8Array(totalLen)
  let offset = 0
  for (let i = 0; i < arrays.length; i++) {
    result.set(arrays[i], offset)
    offset += arrays[i].length
  }
  return result
}

// ==================== 解码工具函数 ====================

class ProtobufReader {
  private data: Uint8Array
  private pos: number = 0

  constructor(data: Uint8Array) {
    this.data = data
  }

  get remaining(): number {
    return this.data.length - this.pos
  }

  readVarint(): number {
    let result = 0
    let shift = 0
    while (this.pos < this.data.length) {
      const byte = this.data[this.pos++]
      result |= (byte & 0x7f) << shift
      if ((byte & 0x80) === 0) break
      shift += 7
    }
    return result >>> 0 // 转为无符号
  }

  readTag(): ReadTag {
    const tag = this.readVarint()
    return {
      fieldNumber: tag >>> 3,
      wireType: tag & 0x07
    }
  }

  readString(): string {
    const len = this.readVarint()
    const bytes = this.data.slice(this.pos, this.pos + len)
    this.pos += len
    const textDecoder = util.TextDecoder.create('utf-8')
    return textDecoder.decodeToString(bytes)
  }

  readBytes(): Uint8Array {
    const len = this.readVarint()
    const bytes = this.data.slice(this.pos, this.pos + len)
    this.pos += len
    return bytes
  }

  readInt32(): number {
    return this.readVarint()
  }

  readBool(): boolean {
    return this.readVarint() !== 0
  }

  readFloat(): number {
    const bytes = this.data.slice(this.pos, this.pos + 4)
    this.pos += 4
    const view = new DataView(bytes.buffer, bytes.byteOffset, 4)
    return view.getFloat32(0, true)
  }

  skip(wireType: number): void {
    switch (wireType) {
      case WIRE_VARINT: {
        this.readVarint()
        break
      }
      case WIRE_64BIT: {
        this.pos += 8
        break
      }
      case WIRE_LENGTH_DELIM: {
        const len = this.readVarint()
        this.pos += len
        break
      }
      case WIRE_32BIT: {
        this.pos += 4
        break
      }
      default: {
        break
      }
    }
  }
}

// ==================== LiveKit 消息类型 ====================

export interface  ReadTag{
  fieldNumber : number
  wireType : number
}

export interface JoinRequest {
  roomName?: string      // field 1
  identity?: string      // field 2  
  name?: string          // field 3
  autoSubscribe?: boolean // field 4
  reconnect?: boolean    // field 5
}

export interface SessionDescription {
  type?: string  // field 1
  sdp?: string   // field 2
}

export interface TrickleRequest {
  candidateInit?: string  // field 1
  target?: number         // field 2 (SignalTarget enum)
}

export interface LeaveRequest {
  canReconnect?: boolean  // field 1
  reason?: number         // field 2
}

export interface MuteTrackRequest {
  sid?: string    // field 1
  muted?: boolean // field 2
}

export interface SignalRequest {
  // LiveKit SignalRequest 字段编号 (livekit_rtc.proto):
  // 注意: join 不在 SignalRequest 中，而是通过 URL 参数传递
  join?: JoinRequest           // 仅内部使用，不会编码到 protobuf
  offer?: SessionDescription   // field 1 - 客户端发送 offer (publisher)
  answer?: SessionDescription  // field 2 - 客户端发送 answer (subscriber)
  trickle?: TrickleRequest     // field 3 - ICE candidate
  addTrack?: AddTrackRequest   // field 4 - 添加轨道请求
  leave?: LeaveRequest         // field 8 - 离开请求
  mute?: MuteTrackRequest      // field 5 - 静音请求
}

// Response types
export interface Room {
  sid?: string           // field 1
  name?: string          // field 2
  numParticipants?: number // field 3
}

export interface ParticipantInfo {
  sid?: string       // field 1
  identity?: string  // field 2
  name?: string      // field 3
  state?: number     // field 4
}

export interface ICEServer {
  urls?: string[]      // field 1 (repeated)
  username?: string    // field 2
  credential?: string  // field 3
}

export interface JoinResponse {
  room?: Room                      // field 1
  participant?: ParticipantInfo    // field 2
  otherParticipants?: ParticipantInfo[] // field 3 (repeated)
  serverVersion?: string           // field 4
  iceServers?: ICEServer[]         // field 5 (repeated)
  subscriberPrimary?: boolean      // field 6
}

export interface TrackInfo {
  sid?: string   // field 1
  type?: number  // field 2
  name?: string  // field 3
}

export interface TrackPublishedResponse {
  cid?: string       // field 1
  track?: TrackInfo  // field 2
}

export interface SpeakerInfo {
  sid?: string    // field 1
  level?: number  // field 2
  active?: boolean // field 3
}

export interface SpeakersChanged {
  speakers?: SpeakerInfo[] // field 1 (repeated)
}

export interface RoomUpdate {
  room?: Room // field 1
}

export interface ConnectionQualityInfo {
  participantSid?: string // field 1
  quality?: number        // field 2
}

export interface ConnectionQualityUpdate {
  updates?: ConnectionQualityInfo[] // field 1 (repeated)
}

export interface ParticipantUpdate {
  participants?: ParticipantInfo[] // field 1 (repeated)
}

export interface SignalResponse {
  // LiveKit SignalResponse 字段编号 (livekit_rtc.proto):
  join?: JoinResponse                    // field 1 - 加入响应
  answer?: SessionDescription            // field 2 - 服务端回复 answer (给 publisher)
  offer?: SessionDescription             // field 3 - 服务端发送 offer (给 subscriber)
  trickle?: TrickleRequest               // field 4 - ICE candidate
  update?: ParticipantUpdate             // field 5 - 参与者更新
  trackPublished?: TrackPublishedResponse // field 6 - 轨道发布确认
  leave?: LeaveRequest                   // field 7 - 离开通知
  speakersChanged?: SpeakersChanged      // field 8 - 说话者变化
  roomUpdate?: RoomUpdate                // field 9 - 房间更新
  connectionQuality?: ConnectionQualityUpdate // field 10 - 连接质量
}

// ==================== 编码器 ====================

export function encodeJoinRequest(req: JoinRequest): Uint8Array {
  return concatBytes([
    encodeStringField(1, req.roomName ?? ''),
    encodeStringField(2, req.identity ?? ''),
    encodeStringField(3, req.name ?? ''),
    req.autoSubscribe !== undefined ? encodeBoolField(4, req.autoSubscribe) : new Uint8Array(0),
    req.reconnect !== undefined ? encodeBoolField(5, req.reconnect) : new Uint8Array(0)
  ])
}

export function encodeSessionDescription(desc: SessionDescription): Uint8Array {
  return concatBytes([
    encodeStringField(1, desc.type ?? ''),
    encodeStringField(2, desc.sdp ?? '')
  ])
}

export function encodeTrickleRequest(req: TrickleRequest): Uint8Array {
  return concatBytes([
    encodeStringField(1, req.candidateInit ?? ''),
    encodeInt32Field(2, req.target ?? 0)
  ])
}

export function encodeLeaveRequest(req: LeaveRequest): Uint8Array {
  return concatBytes([
    req.canReconnect !== undefined ? encodeBoolField(1, req.canReconnect) : new Uint8Array(0),
    encodeInt32Field(2, req.reason ?? 0)
  ])
}

export function encodeMuteTrackRequest(req: MuteTrackRequest): Uint8Array {
  return concatBytes([
    encodeStringField(1, req.sid ?? ''),
    req.muted !== undefined ? encodeBoolField(2, req.muted) : new Uint8Array(0)
  ])
}

// AddTrackRequest 编码
// field 1 = cid, field 2 = name, field 3 = type, 
// field 6 = muted, field 7 = disable_dtx, field 8 = source, field 13 = disable_red
export interface AddTrackRequest {
  cid: string           // 客户端轨道 ID
  name?: string         // 轨道名称
  type: number          // 轨道类型: 0=AUDIO, 1=VIDEO, 2=DATA
  source?: number       // 轨道来源: 0=UNKNOWN, 1=CAMERA, 2=MICROPHONE
  muted?: boolean       // 是否静音
  disableDtx?: boolean  // 是否禁用 DTX
  disableRed?: boolean  // 是否禁用 RED
}

// 强制编码 int32（即使值为 0）
function encodeInt32FieldForced(fieldNumber: number, value: number): Uint8Array {
  const tag = encodeTag(fieldNumber, WIRE_VARINT)
  // 对于值为 0，编码为单字节 0
  if (value === 0) {
    const result = new Uint8Array(tag.length + 1)
    result.set(tag, 0)
    result[tag.length] = 0
    return result
  }
  const data = encodeVarint(value)
  const result = new Uint8Array(tag.length + data.length)
  result.set(tag, 0)
  result.set(data, tag.length)
  return result
}

export function encodeAddTrackRequest(req: AddTrackRequest): Uint8Array {
  return concatBytes([
    encodeStringField(1, req.cid),
    req.name ? encodeStringField(2, req.name) : new Uint8Array(0),
    // type 必须强制编码（即使值为 0=AUDIO）
    encodeInt32FieldForced(3, req.type),
    req.muted !== undefined ? encodeBoolField(6, req.muted) : new Uint8Array(0),
    req.disableDtx !== undefined ? encodeBoolField(7, req.disableDtx) : new Uint8Array(0),
    // source 也需要强制编码（2=MICROPHONE）
    req.source !== undefined ? encodeInt32FieldForced(8, req.source) : new Uint8Array(0),
    req.disableRed !== undefined ? encodeBoolField(13, req.disableRed) : new Uint8Array(0)
  ])
}

export function encodeSignalRequest(req: SignalRequest): Uint8Array {
  // LiveKit SignalRequest 字段编号:
  // field 1 = offer, field 2 = answer, field 3 = trickle, 
  // field 4 = add_track, field 5 = mute, field 8 = leave
  // 注意: SignalRequest 没有 join 字段，join 通过 URL 参数处理
  if (req.offer) {
    return encodeMessageField(1, encodeSessionDescription(req.offer))
  }
  if (req.answer) {
    return encodeMessageField(2, encodeSessionDescription(req.answer))
  }
  if (req.trickle) {
    return encodeMessageField(3, encodeTrickleRequest(req.trickle))
  }
  if (req.addTrack) {
    return encodeMessageField(4, encodeAddTrackRequest(req.addTrack))
  }
  if (req.mute) {
    return encodeMessageField(5, encodeMuteTrackRequest(req.mute))
  }
  if (req.leave) {
    return encodeMessageField(8, encodeLeaveRequest(req.leave))
  }
  return new Uint8Array(0)
}

// ==================== 解码器 ====================

function decodeRoom(reader: ProtobufReader): Room {
  const room: Room = {}
  while (reader.remaining > 0) {
    const tagInfo = reader.readTag()
    switch (tagInfo.fieldNumber) {
      case 1: { room.sid = reader.readString(); break }
      case 2: { room.name = reader.readString(); break }
      case 3: { room.numParticipants = reader.readInt32(); break }
      default: { reader.skip(tagInfo.wireType) }
    }
  }
  return room
}

function decodeParticipantInfo(reader: ProtobufReader): ParticipantInfo {
  const info: ParticipantInfo = {}
  while (reader.remaining > 0) {
    const tagInfo = reader.readTag()
    switch (tagInfo.fieldNumber) {
      case 1: { info.sid = reader.readString(); break }
      case 2: { info.identity = reader.readString(); break }
      case 3: { info.name = reader.readString(); break }
      case 4: { info.state = reader.readInt32(); break }
      default: { reader.skip(tagInfo.wireType) }
    }
  }
  return info
}

function decodeICEServer(reader: ProtobufReader): ICEServer {
  const server: ICEServer = { urls: [] }
  while (reader.remaining > 0) {
    const tagInfo = reader.readTag()
    switch (tagInfo.fieldNumber) {
      case 1: { server.urls!.push(reader.readString()); break }
      case 2: { server.username = reader.readString(); break }
      case 3: { server.credential = reader.readString(); break }
      default: { reader.skip(tagInfo.wireType) }
    }
  }
  return server
}

function decodeJoinResponse(reader: ProtobufReader): JoinResponse {
  const resp: JoinResponse = { otherParticipants: [], iceServers: [] }
  while (reader.remaining > 0) {
    const tagInfo = reader.readTag()
    const fieldNumber = tagInfo.fieldNumber
    const wireType = tagInfo.wireType
    switch (fieldNumber) {
      case 1: {
        const roomBytes = reader.readBytes()
        resp.room = decodeRoom(new ProtobufReader(roomBytes))
        break
      }
      case 2: {
        const partBytes = reader.readBytes()
        resp.participant = decodeParticipantInfo(new ProtobufReader(partBytes))
        break
      }
      case 3: {
        const otherBytes = reader.readBytes()
        resp.otherParticipants!.push(decodeParticipantInfo(new ProtobufReader(otherBytes)))
        break
      }
      case 4: {
        resp.serverVersion = reader.readString()
        break
      }
      case 5: {
        const iceBytes = reader.readBytes()
        resp.iceServers!.push(decodeICEServer(new ProtobufReader(iceBytes)))
        break
      }
      case 6: {
        resp.subscriberPrimary = reader.readBool()
        break
      }
      default: {
        reader.skip(wireType)
      }
    }
  }
  return resp
}

function decodeSessionDescription(reader: ProtobufReader): SessionDescription {
  const desc: SessionDescription = {}
  while (reader.remaining > 0) {
    const tagInfo = reader.readTag()
    switch (tagInfo.fieldNumber) {
      case 1: { desc.type = reader.readString(); break }
      case 2: { desc.sdp = reader.readString(); break }
      default: { reader.skip(tagInfo.wireType) }
    }
  }
  return desc
}

function decodeTrickleRequest(reader: ProtobufReader): TrickleRequest {
  const req: TrickleRequest = {}
  while (reader.remaining > 0) {
    const tagInfo = reader.readTag()
    switch (tagInfo.fieldNumber) {
      case 1: { req.candidateInit = reader.readString(); break }
      case 2: { req.target = reader.readInt32(); break }
      default: { reader.skip(tagInfo.wireType) }
    }
  }
  return req
}

function decodeLeaveRequest(reader: ProtobufReader): LeaveRequest {
  const req: LeaveRequest = {}
  while (reader.remaining > 0) {
    const tagInfo = reader.readTag()
    switch (tagInfo.fieldNumber) {
      case 1: { req.canReconnect = reader.readBool(); break }
      case 2: { req.reason = reader.readInt32(); break }
      default: { reader.skip(tagInfo.wireType) }
    }
  }
  return req
}

function decodeTrackInfo(reader: ProtobufReader): TrackInfo {
  const info: TrackInfo = {}
  while (reader.remaining > 0) {
    const tagInfo = reader.readTag()
    switch (tagInfo.fieldNumber) {
      case 1: { info.sid = reader.readString(); break }
      case 2: { info.type = reader.readInt32(); break }
      case 3: { info.name = reader.readString(); break }
      default: { reader.skip(tagInfo.wireType) }
    }
  }
  return info
}

function decodeTrackPublishedResponse(reader: ProtobufReader): TrackPublishedResponse {
  const resp: TrackPublishedResponse = {}
  while (reader.remaining > 0) {
    const tagInfo = reader.readTag()
    switch (tagInfo.fieldNumber) {
      case 1: { resp.cid = reader.readString(); break }
      case 2: {
        const trackBytes = reader.readBytes()
        resp.track = decodeTrackInfo(new ProtobufReader(trackBytes))
        break
      }
      default: { reader.skip(tagInfo.wireType) }
    }
  }
  return resp
}

function decodeSpeakerInfo(reader: ProtobufReader): SpeakerInfo {
  const info: SpeakerInfo = {}
  while (reader.remaining > 0) {
    const tagInfo = reader.readTag()
    switch (tagInfo.fieldNumber) {
      case 1: { info.sid = reader.readString(); break }
      case 2: { info.level = reader.readFloat(); break }
      case 3: { info.active = reader.readBool(); break }
      default: { reader.skip(tagInfo.wireType) }
    }
  }
  return info
}

function decodeSpeakersChanged(reader: ProtobufReader): SpeakersChanged {
  const resp: SpeakersChanged = { speakers: [] }
  while (reader.remaining > 0) {
    const tagInfo = reader.readTag()
    switch (tagInfo.fieldNumber) {
      case 1: {
        const speakerBytes = reader.readBytes()
        resp.speakers!.push(decodeSpeakerInfo(new ProtobufReader(speakerBytes)))
        break
      }
      default: { reader.skip(tagInfo.wireType) }
    }
  }
  return resp
}

function decodeRoomUpdate(reader: ProtobufReader): RoomUpdate {
  const resp: RoomUpdate = {}
  while (reader.remaining > 0) {
    const tagInfo = reader.readTag()
    switch (tagInfo.fieldNumber) {
      case 1: {
        const roomBytes = reader.readBytes()
        resp.room = decodeRoom(new ProtobufReader(roomBytes))
        break
      }
      default: { reader.skip(tagInfo.wireType) }
    }
  }
  return resp
}

function decodeConnectionQualityInfo(reader: ProtobufReader): ConnectionQualityInfo {
  const info: ConnectionQualityInfo = {}
  while (reader.remaining > 0) {
    const tagInfo = reader.readTag()
    switch (tagInfo.fieldNumber) {
      case 1: { info.participantSid = reader.readString(); break }
      case 2: { info.quality = reader.readInt32(); break }
      default: { reader.skip(tagInfo.wireType) }
    }
  }
  return info
}

function decodeConnectionQualityUpdate(reader: ProtobufReader): ConnectionQualityUpdate {
  const resp: ConnectionQualityUpdate = { updates: [] }
  while (reader.remaining > 0) {
    const tagInfo = reader.readTag()
    switch (tagInfo.fieldNumber) {
      case 1: {
        const updateBytes = reader.readBytes()
        resp.updates!.push(decodeConnectionQualityInfo(new ProtobufReader(updateBytes)))
        break
      }
      default: { reader.skip(tagInfo.wireType) }
    }
  }
  return resp
}

function decodeParticipantUpdate(reader: ProtobufReader): ParticipantUpdate {
  const resp: ParticipantUpdate = { participants: [] }
  while (reader.remaining > 0) {
    const tagInfo = reader.readTag()
    switch (tagInfo.fieldNumber) {
      case 1: {
        const partBytes = reader.readBytes()
        resp.participants!.push(decodeParticipantInfo(new ProtobufReader(partBytes)))
        break
      }
      default: { reader.skip(tagInfo.wireType) }
    }
  }
  return resp
}

export function decodeSignalResponse(data: Uint8Array): SignalResponse {
  const reader = new ProtobufReader(data)
  const response: SignalResponse = {}

  while (reader.remaining > 0) {
    const tagInfo = reader.readTag()
    switch (tagInfo.fieldNumber) {
      case 1: {
        const joinBytes = reader.readBytes()
        response.join = decodeJoinResponse(new ProtobufReader(joinBytes))
        break
      }
      case 2: {
        // field 2 = answer (服务端回复 publisher)
        const answerBytes = reader.readBytes()
        response.answer = decodeSessionDescription(new ProtobufReader(answerBytes))
        break
      }
      case 3: {
        // field 3 = offer (服务端发给 subscriber)
        const offerBytes = reader.readBytes()
        response.offer = decodeSessionDescription(new ProtobufReader(offerBytes))
        break
      }
      case 4: {
        const trickleBytes = reader.readBytes()
        response.trickle = decodeTrickleRequest(new ProtobufReader(trickleBytes))
        break
      }
      case 5: {
        const updateBytes = reader.readBytes()
        response.update = decodeParticipantUpdate(new ProtobufReader(updateBytes))
        break
      }
      case 6: {
        const trackPubBytes = reader.readBytes()
        response.trackPublished = decodeTrackPublishedResponse(new ProtobufReader(trackPubBytes))
        break
      }
      case 7: {
        const leaveBytes = reader.readBytes()
        response.leave = decodeLeaveRequest(new ProtobufReader(leaveBytes))
        break
      }
      case 8: {
        const speakersBytes = reader.readBytes()
        response.speakersChanged = decodeSpeakersChanged(new ProtobufReader(speakersBytes))
        break
      }
      case 9: {
        const roomUpdateBytes = reader.readBytes()
        response.roomUpdate = decodeRoomUpdate(new ProtobufReader(roomUpdateBytes))
        break
      }
      case 10: {
        const connQualBytes = reader.readBytes()
        response.connectionQuality = decodeConnectionQualityUpdate(new ProtobufReader(connQualBytes))
        break
      }
      default: {
        reader.skip(tagInfo.wireType)
      }
    }
  }

  return response
}
