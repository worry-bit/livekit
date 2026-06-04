import { createKooPhonePlayer, KooPhonePlayer } from '../../../../../../LiveKit/src/main/ets/koophone/KooPhonePlayer'
import { KooPhoneState, KooPhoneError, KooPhoneParams } from '../../../../../../LiveKit/src/main/ets/koophone/KooPhoneTypes'
import { TouchAction, TouchPoint } from '../../../../../../LiveKit/src/main/ets/koophone/KooInputController'

enum LivePlatform {
  TAOBAO = 'taobao',
  DOUYIN = 'douyin'
}

const TAOBAO_PARAMS: KooPhoneParams = {
  signalingUrl: 'wss://your-taobao-signal-server',
  boxId: 'your-taobao-box-id',
  token: 'your-taobao-token'
}

const DOUYIN_PARAMS: KooPhoneParams = {
  signalingUrl: 'wss://your-douyin-signal-server',
  boxId: 'your-douyin-box-id',
  token: 'your-douyin-token'
}

const EXPANDED_SCREEN_MIN_WIDTH = 700
const PAGE_BACKGROUND = '#F7F8FC'
const ROW_BACKGROUND = '#F0F2F7'
const TEXT_PRIMARY = '#20232A'
const TEXT_SECONDARY = '#6A7280'
const DISABLED_BUTTON = '#D7DBE3'
const LIVE_RED = '#E53935'

@Entry
@Component
struct Index1 {
  private taobaoPlayer: KooPhonePlayer = createKooPhonePlayer()
  private douyinPlayer: KooPhonePlayer = createKooPhonePlayer()
  private taobaoXCtrl: XComponentController = new XComponentController()
  private douyinXCtrl: XComponentController = new XComponentController()
  private taobaoSurfaceId: string = ''
  private douyinSurfaceId: string = ''
  private shouldStartTaobao: boolean = false
  private shouldStartDouyin: boolean = false
  private taobaoStarted: boolean = false
  private douyinStarted: boolean = false

  @State rootWidth: number = 0
  @State rootHeight: number = 0
  @State selectedTaobao: boolean = false
  @State selectedDouyin: boolean = false
  @State isLiveStarted: boolean = false
  @State taobaoReady: boolean = false
  @State douyinReady: boolean = false
  @State taobaoPlaying: boolean = false
  @State douyinPlaying: boolean = false
  @State taobaoStateText: string = 'NEW'
  @State douyinStateText: string = 'NEW'
  @State taobaoErrorText: string = ''
  @State douyinErrorText: string = ''

  aboutToAppear(): void {
    this.taobaoPlayer.onStateChange = (s: KooPhoneState) => {
      this.taobaoStateText = s
      this.taobaoPlaying = (s === KooPhoneState.PLAYING)
    }

    this.taobaoPlayer.onError = (code: KooPhoneError, msg: string) => {
      this.taobaoErrorText = `Error ${code}: ${msg}`
      this.taobaoPlaying = false
    }

    this.taobaoPlayer.onTrack = () => {
      console.info('[Index1] Taobao remote video track received')
    }

    this.douyinPlayer.onStateChange = (s: KooPhoneState) => {
      this.douyinStateText = s
      this.douyinPlaying = (s === KooPhoneState.PLAYING)
    }

    this.douyinPlayer.onError = (code: KooPhoneError, msg: string) => {
      this.douyinErrorText = `Error ${code}: ${msg}`
      this.douyinPlaying = false
    }

    this.douyinPlayer.onTrack = () => {
      console.info('[Index1] Douyin remote video track received')
    }
  }

  aboutToDisappear(): void {
    this.closeAllStreams()
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

  private hasSelection(): boolean {
    return this.selectedTaobao || this.selectedDouyin
  }

  private isExpandedScreen(): boolean {
    return this.rootWidth >= EXPANDED_SCREEN_MIN_WIDTH
  }

  private getPagePadding(): number {
    return this.rootWidth >= EXPANDED_SCREEN_MIN_WIDTH ? 48 : 24
  }

  private getPromptTop(): number {
    return this.rootWidth >= EXPANDED_SCREEN_MIN_WIDTH ? 96 : 56
  }

  private getPrimaryPlatform(): LivePlatform {
    if (this.selectedTaobao) {
      return LivePlatform.TAOBAO
    }
    return LivePlatform.DOUYIN
  }

  private togglePlatform(platform: LivePlatform): void {
    if (platform === LivePlatform.TAOBAO) {
      this.selectedTaobao = !this.selectedTaobao
      return
    }
    this.selectedDouyin = !this.selectedDouyin
  }

  private startSelectedStreams(): void {
    if (!this.hasSelection()) {
      return
    }

    this.taobaoErrorText = ''
    this.douyinErrorText = ''
    this.shouldStartTaobao = this.selectedTaobao
    this.shouldStartDouyin = this.selectedDouyin
    this.isLiveStarted = true
  }

  private startPlatformIfReady(platform: LivePlatform): void {
    if (platform === LivePlatform.TAOBAO) {
      if (!this.shouldStartTaobao || this.taobaoStarted || !this.taobaoReady || this.taobaoSurfaceId.length === 0) {
        return
      }
      this.taobaoStarted = true
      this.taobaoPlayer.open(TAOBAO_PARAMS, this.taobaoSurfaceId)
      return
    }

    if (!this.shouldStartDouyin || this.douyinStarted || !this.douyinReady || this.douyinSurfaceId.length === 0) {
      return
    }
    this.douyinStarted = true
    this.douyinPlayer.open(DOUYIN_PARAMS, this.douyinSurfaceId)
  }

  private closeAllStreams(): void {
    this.taobaoPlayer.close()
    this.douyinPlayer.close()
    this.shouldStartTaobao = false
    this.shouldStartDouyin = false
    this.taobaoStarted = false
    this.douyinStarted = false
    this.taobaoPlaying = false
    this.douyinPlaying = false
  }

  private getPlatformTitle(platform: LivePlatform): string {
    return platform === LivePlatform.TAOBAO ? '淘宝直播' : '抖音直播'
  }

  private getStateText(platform: LivePlatform): string {
    return platform === LivePlatform.TAOBAO ? this.taobaoStateText : this.douyinStateText
  }

  private getErrorText(platform: LivePlatform): string {
    return platform === LivePlatform.TAOBAO ? this.taobaoErrorText : this.douyinErrorText
  }

  private isPlatformPlaying(platform: LivePlatform): boolean {
    return platform === LivePlatform.TAOBAO ? this.taobaoPlaying : this.douyinPlaying
  }

  private handleSurfaceTouch(platform: LivePlatform, event: TouchEvent): void {
    if (!this.isPlatformPlaying(platform)) {
      return
    }

    const player = platform === LivePlatform.TAOBAO ? this.taobaoPlayer : this.douyinPlayer
    const ctrl = player.inputController
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
  }

  @Builder
  selectIndicator(selected: boolean) {
    Stack({ alignContent: Alignment.Center }) {
      Text('')
        .width(28)
        .height(28)
        .border({
          width: 1.5,
          color: selected ? LIVE_RED : '#AAB1BD'
        })
        .borderRadius(14)
        .backgroundColor(Color.Transparent)

      if (selected) {
        Text('')
          .width(14)
          .height(14)
          .borderRadius(7)
          .backgroundColor(LIVE_RED)
      }
    }
    .width(32)
    .height(32)
  }

  @Builder
  platformOption(platform: LivePlatform, title: string, selected: boolean) {
    Row({ space: 18 }) {
      this.selectIndicator(selected)

      Text(title)
        .fontSize(20)
        .fontWeight(FontWeight.Medium)
        .fontColor(TEXT_PRIMARY)
        .maxLines(1)
    }
    .width('100%')
    .height(72)
    .padding({ left: 28, right: 24 })
    .backgroundColor(ROW_BACKGROUND)
    .borderRadius(4)
    .alignItems(VerticalAlign.Center)
    .onClick(() => {
      this.togglePlatform(platform)
    })
  }

  @Builder
  selectionPage() {
    Column() {
      Text('开始直播')
        .fontSize(26)
        .fontWeight(FontWeight.Bold)
        .fontColor(TEXT_PRIMARY)
        .width('100%')

      Text('请选择直播平台')
        .fontSize(22)
        .fontColor(TEXT_SECONDARY)
        .width('100%')
        .textAlign(TextAlign.Center)
        .margin({ top: this.getPromptTop(), bottom: 28 })

      Column({ space: 22 }) {
        this.platformOption(LivePlatform.TAOBAO, '淘宝直播', this.selectedTaobao)
        this.platformOption(LivePlatform.DOUYIN, '抖音直播', this.selectedDouyin)
      }
      .width('100%')

      Blank()

      Row() {
        Blank()
        Button('开始直播')
          .width(154)
          .height(54)
          .fontSize(18)
          .fontWeight(FontWeight.Medium)
          .fontColor(Color.White)
          .backgroundColor(this.hasSelection() ? LIVE_RED : DISABLED_BUTTON)
          .borderRadius(27)
          .enabled(this.hasSelection())
          .onClick(() => {
            this.startSelectedStreams()
          })
      }
      .width('100%')
    }
    .width('100%')
    .height('100%')
    .padding({
      top: this.rootWidth >= EXPANDED_SCREEN_MIN_WIDTH ? 58 : 32,
      left: this.getPagePadding(),
      right: this.getPagePadding(),
      bottom: 36
    })
    .backgroundColor(PAGE_BACKGROUND)
  }

  @Builder
  taobaoSurface() {
    XComponent({
      type: XComponentType.SURFACE,
      controller: this.taobaoXCtrl
    })
      .width('100%')
      .height('100%')
      .backgroundColor(Color.Black)
      .onLoad(() => {
        this.taobaoSurfaceId = this.taobaoXCtrl.getXComponentSurfaceId()
        this.taobaoReady = true
        this.taobaoPlayer.setSurfaceId(this.taobaoSurfaceId)
        this.startPlatformIfReady(LivePlatform.TAOBAO)
        console.info('[Index1] Taobao XComponent loaded, surfaceId:', this.taobaoSurfaceId)
      })
      .onDestroy(() => {
        this.taobaoReady = false
        this.taobaoSurfaceId = ''
        this.taobaoPlayer.setSurfaceId('')
      })
      .onAreaChange((_old: Area, newArea: Area) => {
        this.taobaoPlayer.inputController.setViewSize(newArea.width as number, newArea.height as number)
      })
      .onTouch((event: TouchEvent) => {
        this.handleSurfaceTouch(LivePlatform.TAOBAO, event)
      })
  }

  @Builder
  douyinSurface() {
    XComponent({
      type: XComponentType.SURFACE,
      controller: this.douyinXCtrl
    })
    .width('100%')
    .height('100%')
    .backgroundColor(Color.Black)
    .onLoad(() => {
      this.douyinSurfaceId = this.douyinXCtrl.getXComponentSurfaceId()
      this.douyinReady = true
      this.douyinPlayer.setSurfaceId(this.douyinSurfaceId)
      this.startPlatformIfReady(LivePlatform.DOUYIN)
      console.info('[Index1] Douyin XComponent loaded, surfaceId:', this.douyinSurfaceId)
    })
    .onDestroy(() => {
      this.douyinReady = false
      this.douyinSurfaceId = ''
      this.douyinPlayer.setSurfaceId('')
    })
    .onAreaChange((_old: Area, newArea: Area) => {
      this.douyinPlayer.inputController.setViewSize(newArea.width as number, newArea.height as number)
    })
    .onTouch((event: TouchEvent) => {
      this.handleSurfaceTouch(LivePlatform.DOUYIN, event)
    })
  }

  @Builder
  surfaceForPlatform(platform: LivePlatform) {
    if (platform === LivePlatform.TAOBAO) {
      this.taobaoSurface()
    } else {
      this.douyinSurface()
    }
  }

  @Builder
  streamPanel(platform: LivePlatform) {
    Stack({ alignContent: Alignment.TopStart }) {
      this.surfaceForPlatform(platform)

      Column({ space: 3 }) {
        Text(this.getPlatformTitle(platform))
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor(Color.White)
          .maxLines(1)

        if (this.getErrorText(platform).length > 0) {
          Text(this.getErrorText(platform))
            .fontSize(11)
            .fontColor('#FFD3D3')
            .maxLines(2)
        } else {
          Text(this.getStateText(platform))
            .fontSize(11)
            .fontColor('#DDE3EA')
            .maxLines(1)
        }
      }
      .padding({ top: 8, right: 12, bottom: 8, left: 12 })
      .margin({ top: 16, left: 16 })
      .borderRadius(6)
      .backgroundColor('#66000000')
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Color.Black)
  }

  @Builder
  emptyLivePanel() {
    Column() {
      Blank()
      Text('暂无直播内容')
        .fontSize(22)
        .fontWeight(FontWeight.Medium)
        .fontColor(TEXT_SECONDARY)
        .textAlign(TextAlign.Center)
      Blank()
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#F1F3F8')
  }

  @Builder
  livePage() {
    if (this.isExpandedScreen()) {
      Row() {
        Column() {
          this.streamPanel(this.getPrimaryPlatform())
        }
        .height('100%')
        .layoutWeight(1)

        Column() {
          if (this.selectedTaobao && this.selectedDouyin) {
            this.streamPanel(LivePlatform.DOUYIN)
          } else {
            this.emptyLivePanel()
          }
        }
        .height('100%')
        .layoutWeight(1)
      }
      .width('100%')
      .height('100%')
      .backgroundColor(Color.Black)
    } else {
      this.streamPanel(this.getPrimaryPlatform())
    }
  }

  build() {
    Column() {
      if (this.isLiveStarted) {
        this.livePage()
      } else {
        this.selectionPage()
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.isLiveStarted ? Color.Black : PAGE_BACKGROUND)
    .onAreaChange((_old: Area, newArea: Area) => {
      this.rootWidth = newArea.width as number
      this.rootHeight = newArea.height as number
    })
  }
}
