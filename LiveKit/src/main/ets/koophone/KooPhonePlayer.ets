import webrtc from '@ohos/webrtc'
import {
  KooPhoneParams,
  KooPhoneState,
  KooPhoneError,
  KooSignalMessage,
  OnStateChange,
  OnTrack,
  OnError
} from './KooPhoneTypes'
import { KooSignalClient } from './KooSignalClient'
import { KooRTCSource } from './KooRTCSource'
import { util } from '@kit.ArkTS'

const DEFAULT_ICE_SERVERS = [
  { uri: 'stun:stun.l.google.com:19302' },
  { uri: 'stun:stun1.l.google.com:19302' }
]

export class KooPhonePlayer {
  // Event callbacks (caller registers these)
  onStateChange: OnStateChange | null = null
  onTrack: OnTrack | null = null
  onError: OnError | null = null

  // Private members
  private signalClient: KooSignalClient
  private rtcSource: KooRTCSource
  private _state: KooPhoneState = KooPhoneState.NEW
  private params: KooPhoneParams | null = null
  private surfaceId: string = ''
  private remoteId: string = ''

  constructor() {
    // Create signalClient and rtcSource
    this.signalClient = new KooSignalClient()
    this.rtcSource = new KooRTCSource()

    // Set up signalClient callbacks
    this.signalClient.onConnected = () => {
      this.handleSignalConnected()
    }

    this.signalClient.onAuthorize = (authorized: boolean) => {
      this.handleSignalAuthorize(authorized)
    }

    this.signalClient.onStart = (streamId: string) => {
      this.remoteId = streamId
      this.startStreaming()
    }

    this.signalClient.onMessage = (message: KooSignalMessage) => {
      this.handleSignalMessage(message)
    }

    this.signalClient.onClosed = () => {
      this.transitionTo(KooPhoneState.CLOSED)
    }

    // Set up rtcSource callbacks
    this.rtcSource.onDescription = (desc: webrtc.RTCSessionDescription) => {
      if (desc.type === 'answer') {
        this.signalClient.emitMessage('answer', this.remoteId, { sdp: desc.sdp })
      }
    }

    this.rtcSource.onIceCandidate = (candidate: webrtc.RTCIceCandidate) => {
      this.signalClient.emitMessage('candidate', this.remoteId, {
        candidate: candidate.candidate,
        id: candidate.sdpMid,
        label: candidate.sdpMLineIndex
      })
    }

    this.rtcSource.onConnectionStateChange = (state: string) => {
      if (state === 'connected') {
        this.transitionTo(KooPhoneState.PLAYING)
      }
    }

    this.rtcSource.onTrack = (track: webrtc.MediaStreamTrack) => {
      this.onTrack?.(track)
    }
  }

  // Get current state
  get state(): KooPhoneState {
    return this._state
  }

  // Start streaming
  open(params: KooPhoneParams, surfaceId: string): void {
    try {
      // Validate params
      if (!params.signalingUrl) {
        throw new Error('signalingUrl is required')
      }
      if (!params.boxId) {
        throw new Error('boxId is required')
      }
      if (!params.token) {
        throw new Error('token is required')
      }

      // Store params and surfaceId
      this.params = params
      this.surfaceId = surfaceId

      // Build query string
      const query = `authtype=token&boxid=${params.boxId}&token=${params.token}`

      // Set rtcSource surfaceId
      this.rtcSource.setSurfaceId(surfaceId)

      // Connect signal client
      this.signalClient.connect(params.signalingUrl, query)

      // Transition to CONNECTING
      this.transitionTo(KooPhoneState.CONNECTING)
    } catch (e) {
      this.handleError(KooPhoneError.PARAM_INVALID, String(e))
    }
  }

  // Stop streaming and release all resources
  close(): void {
    this.transitionTo(KooPhoneState.CLOSED)

    try {
      this.rtcSource.close()
    } catch (e) {
      console.error('Error closing rtcSource:', e)
    }

    try {
      this.signalClient.close()
    } catch (e) {
      console.error('Error closing signalClient:', e)
    }
  }

  // Private: Handle signal client connected
  private handleSignalConnected(): void {
    // Connection established, wait for authorize event
    console.info('KooPhonePlayer: Signal client connected')
  }

  // Private: Handle authorization response
  private handleSignalAuthorize(authorized: boolean): void {
    if (authorized) {
      this.transitionTo(KooPhoneState.AUTHORIZED)
    } else {
      this.handleError(KooPhoneError.SIGNAL_AUTH_FAILED, 'Authorization failed')
    }
  }

  // Private: Start streaming (called after onStart event)
  private startStreaming(): void {
    try {
      if (!this.params) {
        throw new Error('Params not set')
      }

      // Transition to PEER_CONNECTING
      this.transitionTo(KooPhoneState.PEER_CONNECTING)

      // Open rtcSource with iceServers
      const iceServers = this.params.iceServers || DEFAULT_ICE_SERVERS
      this.rtcSource.open(iceServers)

      // Build init payload
      const initPayload = {
        mode: this.params.mode || 'app',
        role: this.params.role || 'master',
        sole: this.params.sole !== false,
        volume: this.params.volume ?? 100,
        profile_name: this.params.role === 'master' ? 'master' : 'groupControl',
        network_type: 'wifi',
        profile: 'high',
        vcodec: 'auto'
      }

      // Encode to base64
      const jsonString = JSON.stringify(initPayload)
      const base64Helper = new util.Base64Helper()
      const base64Data = base64Helper.encodeToStringSync(jsonString)

      // Send init message
      this.signalClient.emitData('init', this.remoteId, base64Data)
    } catch (e) {
      this.handleError(KooPhoneError.PEER_FAILED, String(e))
    }
  }

  // Private: Handle signal messages
  private handleSignalMessage(message: KooSignalMessage): void {
    try {
      switch (message.type) {
        case 'offer':
          if (message.payload) {
            const offerDesc: webrtc.RTCSessionDescription = {
              type: 'offer',
              sdp: message.payload.sdp as string
            }
            this.rtcSource.setRemoteDescription(offerDesc)
              .catch((e: Error) => {
                this.handleError(KooPhoneError.SDP_ERROR, `Failed to handle offer: ${e.message}`)
              })
          }
          break
        case 'candidate':
          if (message.payload) {
            const candidateInit: webrtc.RTCIceCandidateInit = {
              candidate: message.payload.candidate as string,
              sdpMid: message.payload.id as string,
              sdpMLineIndex: message.payload.label as number
            }
            this.rtcSource.addRemoteIceCandidate(candidateInit)
          }
          break
        default:
          console.info(`Unhandled message type: ${message.type}`)
      }
    } catch (e) {
      this.handleError(KooPhoneError.SIGNAL_CONNECT_FAILED, String(e))
    }
  }

  // Private: Transition to new state
  private transitionTo(newState: KooPhoneState): void {
    if (this._state !== newState) {
      this._state = newState
      this.onStateChange?.(newState)
    }
  }

  // Private: Handle errors
  private handleError(code: KooPhoneError, message: string): void {
    this.onError?.(code, message)
    this.close()
  }
}

// Factory function
export function createKooPhonePlayer(): KooPhonePlayer {
  return new KooPhonePlayer()
}
