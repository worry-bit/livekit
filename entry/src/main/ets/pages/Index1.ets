import { createKooPhonePlayer, KooPhonePlayer } from '../../../../../../LiveKit/src/main/ets/koophone/KooPhonePlayer'
import { KooPhoneState, KooPhoneError } from '../../../../../../LiveKit/src/main/ets/koophone/KooPhoneTypes'
import { TouchAction, TouchPoint } from '../../../../../../LiveKit/src/main/ets/koophone/KooInputController'

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

  @State xComponentWidth: number = 0
  @State xComponentHeight: number = 0
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

  private convertTouches(touches: TouchObject[]): TouchPoint[] {
    const points: TouchPoint[] = []
    for (let i = 0; i < touches.length; i++) {
      const t = touches[i]
      const pt: TouchPoint = { id: t.id, x: t.x, y: t.y }
      points.push(pt)
    }
    return points
  }

  build() {
    Column({ space: 0 }) {
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
        .onAreaChange((_old: Area, newArea: Area) => {
          this.xComponentWidth = newArea.width as number
          this.xComponentHeight = newArea.height as number
          this.player.inputController.setViewSize(this.xComponentWidth, this.xComponentHeight)
        })
        .onTouch((event: TouchEvent) => {
          if (!this.isPlaying) {
            return
          }
          const ctrl = this.player.inputController
          switch (event.type) {
            case TouchType.Down:
              ctrl.sendTouchEvent(TouchAction.DOWN, this.convertTouches(event.touches))
              break
            case TouchType.Move:
              ctrl.sendTouchEvent(TouchAction.MOVE, this.convertTouches(event.touches))
              break
            case TouchType.Up:
            case TouchType.Cancel:
              ctrl.sendTouchEvent(TouchAction.UP, this.convertTouches(event.changedTouches))
              break
          }
        })

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
