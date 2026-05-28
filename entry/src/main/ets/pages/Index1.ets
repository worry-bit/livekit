import { createKooPhonePlayer, KooPhonePlayer } from '../../../../../../LiveKit/src/main/ets/koophone/KooPhonePlayer'
import { KooPhoneState, KooPhoneError } from '../../../../../../LiveKit/src/main/ets/koophone/KooPhoneTypes'

// ===== 测试参数，按需修改 =====
const SIGNALING_URL = 'wss://your-signal-server'
const BOX_ID = 'your-box-id'
const TOKEN = 'your-token'
// ==============================

@Entry
@Component
struct Index1 {
  private player: KooPhonePlayer = createKooPhonePlayer()
  private xCtrl: XComponentController = new XComponentController()
  private surfaceId: string = ''

  @State stateText: string = 'NEW'
  @State errorText: string = ''
  @State isPlaying: boolean = false
  @State xComponentReady: boolean = false

  aboutToAppear(): void {
    this.player.onStateChange = (s: KooPhoneState) => {
      this.stateText = s
      this.isPlaying = (s === KooPhoneState.PLAYING)
    }

    this.player.onError = (code: KooPhoneError, msg: string) => {
      this.errorText = `Error ${code}: ${msg}`
      this.isPlaying = false
    }

    this.player.onTrack = () => {
      console.info('[Index1] Remote video track received')
    }
  }

  aboutToDisappear(): void {
    this.player.close()
  }

  build() {
    Column({ space: 0 }) {
      // 远端视频渲染区域
      XComponent({
        type: XComponentType.SURFACE,
        controller: this.xCtrl
      })
        .width('100%')
        .aspectRatio(16 / 9)
        .backgroundColor(Color.Black)
        .onLoad(() => {
          this.surfaceId = this.xCtrl.getXComponentSurfaceId()
          this.xComponentReady = true
          console.info('[Index1] XComponent loaded, surfaceId:', this.surfaceId)
        })
        .onDestroy(() => {
          this.xComponentReady = false
          this.surfaceId = ''
        })

      // 状态显示
      Column({ space: 4 }) {
        Text(`状态: ${this.stateText}`)
          .fontSize(15)
          .fontColor(this.isPlaying ? Color.Green : Color.Gray)
          .width('100%')

        if (this.errorText) {
          Text(this.errorText)
            .fontSize(13)
            .fontColor(Color.Red)
            .width('100%')
        }
      }
      .padding({ top: 12, left: 16, right: 16 })
      .width('100%')

      // 控制按钮
      Row({ space: 16 }) {
        Button('开始串流')
          .enabled(this.xComponentReady && !this.isPlaying)
          .onClick(() => {
            this.errorText = ''
            this.player.open({
              signalingUrl: SIGNALING_URL,
              boxId: BOX_ID,
              token: TOKEN
            }, this.surfaceId)
          })

        Button('停止串流')
          .enabled(this.isPlaying)
          .onClick(() => {
            this.player.close()
          })
      }
      .padding({ top: 16 })
    }
    .height('100%')
    .width('100%')
    .padding({ bottom: 16 })
  }
}
