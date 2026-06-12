import { LiveKitClient, VideoCaptureOptions } from 'livekit-harmony'

const PHONE_CAMERA_REOPEN_DELAY_MS = 800
const REMOTE_CAMERA_REOPEN_DELAY_MS = 1200

/**
 * LiveKit 推流摄像头切换协调器。
 *
 * AI 眼镜 remote camera 不能走 RTCRtpSender.replaceTrack() 快切：真机上容易卡住或触发 native 崩溃。
 * 这里只使用 SDK 已公开的 unpublishVideo/publishVideo，在同一个 SFU 房间内释放旧摄像头后再按目标
 * deviceId 重新打开视频源，避免同时占用手机摄像头和 AI 眼镜摄像头。
 */
class LiveKitCameraSwitchCoordinator {
  private switching: Promise<void> = Promise.resolve()

  async switchPublishedVideoSource(
    client: LiveKitClient,
    surfaceId: string,
    options: VideoCaptureOptions,
    targetLabel: string
  ): Promise<void> {
    const nextSwitch = this.switching.then(async () => {
      console.info(`[LiveKitCameraSwitch] switch start target=${targetLabel}`)
      await client.unpublishVideo()
      await this.waitForCameraRelease(targetLabel)
      await client.publishVideo(surfaceId, options)
      console.info(`[LiveKitCameraSwitch] switch done target=${targetLabel}`)
    })
    this.switching = nextSwitch.catch(() => {})
    return nextSwitch
  }

  private waitForCameraRelease(targetLabel: string): Promise<void> {
    const delayMs = targetLabel === 'ai_glasses' ? REMOTE_CAMERA_REOPEN_DELAY_MS : PHONE_CAMERA_REOPEN_DELAY_MS
    return new Promise((resolve: () => void) => {
      setTimeout(() => {
        resolve()
      }, delayMs)
    })
  }
}

const liveKitCameraSwitchCoordinator = new LiveKitCameraSwitchCoordinator()

export default liveKitCameraSwitchCoordinator
