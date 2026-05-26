import liveKitUtil from '../rtc/LiveKitUtil'

@Entry
@Component
struct Index {
  @State xComponentReady: boolean = false
  @State isVideoPublished: boolean = false
  private xComponentCtrl: XComponentController = new XComponentController()
  private surfaceId: string = ''

  build() {
    Column() {
      // 本地摄像头预览区域
      XComponent({
        type: XComponentType.SURFACE,
        controller: this.xComponentCtrl
      })
        .width('100%')
        .aspectRatio(9 / 16)
        .backgroundColor(Color.Black)
        .onLoad(() => {
          this.surfaceId = this.xComponentCtrl.getXComponentSurfaceId()
          this.xComponentReady = true
          console.info('[Index] XComponent loaded, surfaceId:', this.surfaceId)
        })
        .onDestroy(() => {
          if (this.isVideoPublished) {
            liveKitUtil.unpublishVideo()
          }
          this.xComponentReady = false
          this.surfaceId = ''
          this.isVideoPublished = false
        })

      // 连接控制行
      Row({ space: 12 }) {
        Button('获取权限')
          .onClick(() => {
            liveKitUtil.requestPermissions()
          })
        Button('加入房间')
          .onClick(() => {
            const token = 'your-token'
            const url = 'your-wss'
            liveKitUtil.joinRoom(url, token)
          })
        Button('退出房间')
          .onClick(() => {
            liveKitUtil.leaveRoom()
            this.isVideoPublished = false
          })
      }
      .padding({ top: 12 })

      // 视频控制行
      Row({ space: 12 }) {
        Button(this.isVideoPublished ? '关闭视频' : '开启视频')
          .enabled(this.xComponentReady)
          .onClick(async () => {
            if (this.isVideoPublished) {
              await liveKitUtil.unpublishVideo()
              this.isVideoPublished = false
            } else {
              await liveKitUtil.publishVideo(this.surfaceId)
              this.isVideoPublished = liveKitUtil.isVideoPublished
            }
          })

        Button('切换摄像头')
          .enabled(this.isVideoPublished)
          .onClick(async () => {
            await liveKitUtil.switchCamera()
          })
      }
      .padding({ top: 12 })
    }
    .height('100%')
    .width('100%')
    .padding(16)
  }
}
