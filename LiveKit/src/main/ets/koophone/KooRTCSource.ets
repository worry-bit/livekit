import webrtc from '@ohos/webrtc'
import { KooIceServer } from './KooPhoneTypes'

export class KooRTCSource {
  // PeerConnection and factory
  private pc: webrtc.RTCPeerConnection | null = null
  private factory: webrtc.PeerConnectionFactory | null = null

  // Video renderer
  private localRenderer: webrtc.NativeVideoRenderer | null = null
  private surfaceId: string = ''

  // ICE candidate cache for candidates arriving before remote description is set
  private cachedCandidates: webrtc.RTCIceCandidateInit[] = []

  // Event callbacks
  onDescription: ((desc: webrtc.RTCSessionDescription) => void) | null = null
  onIceCandidate: ((candidate: webrtc.RTCIceCandidate) => void) | null = null
  onConnectionStateChange: ((state: webrtc.RTCPeerConnectionState) => void) | null = null
  onTrack: ((track: webrtc.MediaStreamTrack) => void) | null = null

  // Create PeerConnection with ICE servers
  open(iceServers: KooIceServer[]): void {
    try {
      // Create factory
      this.factory = new webrtc.PeerConnectionFactory()

      // Build config with ICE servers
      const config: webrtc.RTCConfiguration = {
        iceServers: iceServers.map((server) => ({
          urls: server.uri,
          username: server.usr || '',
          credential: server.pwd || ''
        }))
      }

      // Create PeerConnection
      this.pc = this.factory.createPeerConnection(config)

      // Set up event handlers
      this.pc.onicecandidate = (event: webrtc.RTCIceCandidateEvent) => {
        if (event.candidate && this.onIceCandidate) {
          this.onIceCandidate(event.candidate)
        }
      }

      this.pc.onconnectionstatechange = () => {
        if (this.onConnectionStateChange && this.pc) {
          this.onConnectionStateChange(this.pc.connectionState)
        }
      }

      this.pc.ontrack = (event: webrtc.RTCTrackEvent) => {
        if (event.track) {
          // Set track to renderer if available
          if (this.localRenderer) {
            this.localRenderer.setVideoTrack(event.track)
          }
          // Notify listener
          if (this.onTrack) {
            this.onTrack(event.track)
          }
        }
      }
    } catch (e) {
      throw new Error(String(e))
    }
  }

  // Set local preview surfaceId (for NativeVideoRenderer)
  setSurfaceId(surfaceId: string): void {
    try {
      this.surfaceId = surfaceId
      this.localRenderer = new webrtc.NativeVideoRenderer()
      this.localRenderer.init(surfaceId)
    } catch (e) {
      throw new Error(String(e))
    }
  }

  // Handle incoming offer, automatically creates answer
  async setRemoteDescription(sdp: webrtc.RTCSessionDescription): Promise<void> {
    try {
      if (!this.pc) {
        throw new Error('PeerConnection not initialized')
      }

      await this.pc.setRemoteDescription(sdp)

      if (sdp.type === 'offer') {
        const answer = await this.pc.createAnswer()
        await this.pc.setLocalDescription(answer)
        if (this.onDescription) {
          this.onDescription(answer)
        }
      }

      // Process any cached candidates
      await this.processCachedCandidates()
    } catch (e) {
      throw new Error(String(e))
    }
  }

  // Add remote ICE candidate (with retry if remoteDesc not ready)
  addRemoteIceCandidate(candidate: webrtc.RTCIceCandidateInit): void {
    try {
      if (!this.pc) {
        throw new Error('PeerConnection not initialized')
      }

      // If remote description is not set yet, cache the candidate
      if (!this.pc.remoteDescription) {
        this.cachedCandidates.push(candidate)
        return
      }

      // Add candidate directly
      this.pc.addIceCandidate(candidate)
    } catch (e) {
      throw new Error(String(e))
    }
  }

  // Process cached ICE candidates after remote description is set
  private async processCachedCandidates(): Promise<void> {
    const candidates = this.cachedCandidates
    this.cachedCandidates = []

    for (const candidate of candidates) {
      let retries = 0
      const maxRetries = 20
      const retryDelay = 100

      while (retries < maxRetries) {
        try {
          if (this.pc && this.pc.remoteDescription) {
            this.pc.addIceCandidate(candidate)
            break
          } else {
            retries++
            await this.sleep(retryDelay)
          }
        } catch (e) {
          retries++
          if (retries >= maxRetries) {
            throw new Error(String(e))
          }
          await this.sleep(retryDelay)
        }
      }
    }
  }

  // Helper method for delay
  private sleep(ms: number): Promise<void> {
    return new Promise((resolve) => setTimeout(resolve, ms))
  }

  // Close and release resources
  close(): void {
    try {
      // Set track to null
      if (this.localRenderer) {
        this.localRenderer.setVideoTrack(null)
      }

      // Release renderer
      if (this.localRenderer) {
        this.localRenderer.release()
        this.localRenderer = null
      }

      // Close PeerConnection
      if (this.pc) {
        this.pc.close()
        this.pc = null
      }

      // Release factory
      if (this.factory) {
        this.factory.release()
        this.factory = null
      }

      // Clear cached candidates
      this.cachedCandidates = []
    } catch (e) {
      throw new Error(String(e))
    }
  }
}
