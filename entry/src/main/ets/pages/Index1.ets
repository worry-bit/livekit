import {
  createKooAuthService,
  createKooPhonePlayer,
  KooAuthService,
  KooInputController,
  KooPhoneError,
  KooPhoneParams,
  KooPhonePlayer,
  KooPhoneState,
  KooAuthTokenResult,
  LivePlatformConfig,
  TouchAction,
  TouchPoint
} from 'livekit-harmony'

enum LivePlatform {
  TAOBAO = 'taobao',
  DOUYIN = 'douyin'
}

const KOOPHONE_AUTH_HOST = 'http://100.93.2.248:8669'
const IAM_AUTH_URL = 'https://iam.cn-north-7.myhuaweicloud.com/v3/auth/tokens'
const IAM_DOMAIN_NAME = '__IAM_DOMAIN_NAME__'
const IAM_USER_NAME = '__IAM_USER_NAME__'
const IAM_PASSWORD = '__IAM_PASSWORD__'
const IAM_PROJECT_NAME = 'cn-north-7'
const TAOBAO_INSTANCE_ID = 'dhb4q9j4'
const DOUYIN_INSTANCE_ID = 'sKuBZq7c'

const TAOBAO_CONFIG: LivePlatformConfig = {
  iam: {
    authUrl: IAM_AUTH_URL,
    domainName: IAM_DOMAIN_NAME,
    userName: IAM_USER_NAME,
    password: IAM_PASSWORD,
    projectName: IAM_PROJECT_NAME
  },
  kooAuth: {
    authUrl: `${KOOPHONE_AUTH_HOST}/openapi/koophone/v1/instances/${TAOBAO_INSTANCE_ID}/auth`,
    tenantId: '',
    projectId: ''
  }
}

const DOUYIN_CONFIG: LivePlatformConfig = {
  iam: {
    authUrl: IAM_AUTH_URL,
    domainName: IAM_DOMAIN_NAME,
    userName: IAM_USER_NAME,
    password: IAM_PASSWORD,
    projectName: IAM_PROJECT_NAME
  },
  kooAuth: {
    authUrl: `${KOOPHONE_AUTH_HOST}/openapi/koophone/v1/instances/${DOUYIN_INSTANCE_ID}/auth`,
    tenantId: '',
    projectId: ''
  }
}

const EXPANDED_SCREEN_MIN_WIDTH = 700
const MAX_STREAM_RETRY = 3
const PAGE_BACKGROUND = '#F7F8FC'
const ROW_BACKGROUND = '#F0F2F7'
const TEXT_PRIMARY = '#20232A'
const TEXT_SECONDARY = '#6A7280'
const DISABLED_BUTTON = '#D7DBE3'
const LIVE_RED = '#E53935'

@Entry
@Component
struct Index1 {
  private authService: KooAuthService = createKooAuthService()
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
  private taobaoRetryTimer: number = -1
  private douyinRetryTimer: number = -1

  @State rootWidth: number = 0
  @State rootHeight: number = 0
  @State selectedTaobao: boolean = false
  @State selectedDouyin: boolean = false
  @State isLiveStarted: boolean = false
  @State taobaoReady: boolean = false
  @State douyinReady: boolean = false
  @State taobaoPlaying: boolean = false
  @State douyinPlaying: boolean = false
  @State taobaoStarting: boolean = false
  @State douyinStarting: boolean = false
  @State taobaoRetryCount: number = 0
  @State douyinRetryCount: number = 0
  @State taobaoStateText: string = 'NEW'
  @State douyinStateText: string = 'NEW'
  @State taobaoErrorText: string = ''
  @State douyinErrorText: string = ''

  aboutToAppear(): void {
    this.taobaoPlayer.onStateChange = (s: KooPhoneState) => {
      this.handlePlatformStateChange(LivePlatform.TAOBAO, s)
    }

    this.taobaoPlayer.onError = (code: KooPhoneError, msg: string) => {
      this.handlePlatformError(LivePlatform.TAOBAO, code, msg)
    }

    this.taobaoPlayer.onTrack = () => {
      console.info('[Index1] Taobao remote video track received')
    }

    this.douyinPlayer.onStateChange = (s: KooPhoneState) => {
      this.handlePlatformStateChange(LivePlatform.DOUYIN, s)
    }

    this.douyinPlayer.onError = (code: KooPhoneError, msg: string) => {
      this.handlePlatformError(LivePlatform.DOUYIN, code, msg)
    }

    this.douyinPlayer.onTrack = () => {
      console.info('[Index1] Douyin remote video track received')
    }
  }

  aboutToDisappear(): void {
    this.closeAllStreams()
  }

  /**
   * 将 ArkUI 触摸点转换为云手机输入控制器使用的 TouchPoint。
   * 直播画面可见且 WebRTC DataChannel 就绪后，这些点会被编码并发往云手机。
   */
  private convertTouches(touches: TouchObject[]): TouchPoint[] {
    const points: TouchPoint[] = []
    for (let i = 0; i < touches.length; i++) {
      const t = touches[i]
      const pt: TouchPoint = { id: t.id, x: t.x, y: t.y }
      points.push(pt)
    }
    return points
  }

  /**
   * 只要淘宝或抖音任意一路被选中，开始按钮就进入可点击态。
   */
  private hasSelection(): boolean {
    return this.selectedTaobao || this.selectedDouyin
  }

  /**
   * Mate X7 展开屏宽度远大于外屏；这里用窗口宽度判断当前布局形态。
   */
  private isExpandedScreen(): boolean {
    return this.rootWidth >= EXPANDED_SCREEN_MIN_WIDTH
  }

  /**
   * 展开屏给选择页更大的左右留白，外屏保留更紧凑的可用空间。
   */
  private getPagePadding(): number {
    return this.rootWidth >= EXPANDED_SCREEN_MIN_WIDTH ? 48 : 24
  }

  /**
   * 展开屏中部标题下移，外屏减少顶部空间占用。
   */
  private getPromptTop(): number {
    return this.rootWidth >= EXPANDED_SCREEN_MIN_WIDTH ? 96 : 56
  }

  /**
   * 主直播永远显示在左侧或外屏：双选优先淘宝，单选抖音时抖音成为主直播。
   */
  private getPrimaryPlatform(): LivePlatform {
    if (this.selectedTaobao) {
      return LivePlatform.TAOBAO
    }
    return LivePlatform.DOUYIN
  }

  /**
   * 点击平台行时切换选中态；两个平台互不排斥，因此天然支持单选和双选。
   */
  private togglePlatform(platform: LivePlatform): void {
    if (platform === LivePlatform.TAOBAO) {
      this.selectedTaobao = !this.selectedTaobao
      return
    }
    this.selectedDouyin = !this.selectedDouyin
  }

  /**
   * 从选择页进入直播页。这里只记录“应当启动哪些平台”，真正 open 会等 XComponent
   * surfaceId 准备好后由 startPlatformIfReady 触发。
   */
  private startSelectedStreams(): void {
    if (!this.hasSelection()) {
      return
    }

    this.resetPlatformRuntime(LivePlatform.TAOBAO)
    this.resetPlatformRuntime(LivePlatform.DOUYIN)
    this.shouldStartTaobao = this.selectedTaobao
    this.shouldStartDouyin = this.selectedDouyin
    this.isLiveStarted = true
  }

  /**
   * surfaceId 就绪后启动某一路串流。每次启动先获取 IAM token，再调用预留
   * KooPhone auth 获取 15 秒短效 SDK token，最后才调用 KooPhonePlayer.open。
   */
  private async startPlatformIfReady(platform: LivePlatform): Promise<void> {
    if (!this.canStartPlatform(platform)) {
      return
    }

    this.setPlatformStarting(platform, true)
    this.setPlatformErrorText(platform, '')
    this.setPlatformStateText(platform, `authenticating(${this.getRetryCount(platform)}/${MAX_STREAM_RETRY})`)
    console.info(`[Index1] ${this.getPlatformTitle(platform)} start attempt ${this.getRetryCount(platform)}/${MAX_STREAM_RETRY}`)

    try {
      const config = this.getPlatformConfig(platform)
      const tokenResult = await this.authService.requestSdkToken(config)
      if (!this.canOpenPlatformAfterAuth(platform)) {
        this.setPlatformStarting(platform, false)
        return
      }

      const params = this.buildKooPhoneParams(config, tokenResult)
      this.setPlatformStarted(platform, true)
      this.setPlatformStarting(platform, false)
      this.setPlatformStateText(platform, 'connecting')
      console.info(`[Index1] ${this.getPlatformTitle(platform)} auth ok, opening KooPhonePlayer`)
      this.getPlatformPlayer(platform).open(params, this.getPlatformSurfaceId(platform))
    } catch (e) {
      this.setPlatformStarting(platform, false)
      console.error(`[Index1] ${this.getPlatformTitle(platform)} start failed: ${String(e)}`)
      this.schedulePlatformRetry(platform, String(e))
    }
  }

  /**
   * 停止按钮使用的显式停止入口。停止后回到选择页，但保留当前平台选择，
   * 方便用户在外屏/展开屏之间反复调试。
   */
  private stopSelectedStreams(): void {
    this.closeAllStreams()
    this.taobaoErrorText = ''
    this.douyinErrorText = ''
    this.taobaoStateText = 'NEW'
    this.douyinStateText = 'NEW'
    this.isLiveStarted = false
  }

  /**
   * 页面销毁、停止串流或重试前使用的统一清理方法。
   */
  private closeAllStreams(): void {
    this.clearRetryTimer(LivePlatform.TAOBAO)
    this.clearRetryTimer(LivePlatform.DOUYIN)
    this.taobaoPlayer.close()
    this.douyinPlayer.close()
    this.shouldStartTaobao = false
    this.shouldStartDouyin = false
    this.taobaoStarted = false
    this.douyinStarted = false
    this.taobaoStarting = false
    this.douyinStarting = false
    this.taobaoPlaying = false
    this.douyinPlaying = false
    this.taobaoRetryCount = 0
    this.douyinRetryCount = 0
  }

  private resetPlatformRuntime(platform: LivePlatform): void {
    this.clearRetryTimer(platform)
    if (platform === LivePlatform.TAOBAO) {
      this.taobaoStarted = false
      this.taobaoStarting = false
      this.taobaoPlaying = false
      this.taobaoRetryCount = 0
      this.taobaoErrorText = ''
      this.taobaoStateText = 'NEW'
      return
    }
    this.douyinStarted = false
    this.douyinStarting = false
    this.douyinPlaying = false
    this.douyinRetryCount = 0
    this.douyinErrorText = ''
    this.douyinStateText = 'NEW'
  }

  private canStartPlatform(platform: LivePlatform): boolean {
    return this.shouldStartPlatform(platform) &&
      !this.isPlatformStarted(platform) &&
      !this.isPlatformStarting(platform) &&
      this.isPlatformReady(platform) &&
      this.getPlatformSurfaceId(platform).length > 0
  }

  private canOpenPlatformAfterAuth(platform: LivePlatform): boolean {
    return this.shouldStartPlatform(platform) &&
      this.isPlatformReady(platform) &&
      this.getPlatformSurfaceId(platform).length > 0
  }

  private shouldStartPlatform(platform: LivePlatform): boolean {
    return platform === LivePlatform.TAOBAO ? this.shouldStartTaobao : this.shouldStartDouyin
  }

  private isPlatformReady(platform: LivePlatform): boolean {
    return platform === LivePlatform.TAOBAO ? this.taobaoReady : this.douyinReady
  }

  private isPlatformStarted(platform: LivePlatform): boolean {
    return platform === LivePlatform.TAOBAO ? this.taobaoStarted : this.douyinStarted
  }

  private isPlatformStarting(platform: LivePlatform): boolean {
    return platform === LivePlatform.TAOBAO ? this.taobaoStarting : this.douyinStarting
  }

  private getRetryCount(platform: LivePlatform): number {
    return platform === LivePlatform.TAOBAO ? this.taobaoRetryCount : this.douyinRetryCount
  }

  private getPlatformSurfaceId(platform: LivePlatform): string {
    return platform === LivePlatform.TAOBAO ? this.taobaoSurfaceId : this.douyinSurfaceId
  }

  private getPlatformConfig(platform: LivePlatform): LivePlatformConfig {
    return platform === LivePlatform.TAOBAO ? TAOBAO_CONFIG : DOUYIN_CONFIG
  }

  private getPlatformPlayer(platform: LivePlatform): KooPhonePlayer {
    return platform === LivePlatform.TAOBAO ? this.taobaoPlayer : this.douyinPlayer
  }

  private buildKooPhoneParams(config: LivePlatformConfig, auth: KooAuthTokenResult): KooPhoneParams {
    return {
      signalingUrl: auth.signalingUrl,
      boxId: auth.boxId,
      token: auth.token,
      streamingId: auth.streamingId,
      iceServers: auth.iceServers ?? config.iceServers,
      mode: config.mode,
      role: config.role,
      sole: config.sole,
      volume: config.volume
    }
  }

  private setPlatformStarted(platform: LivePlatform, started: boolean): void {
    if (platform === LivePlatform.TAOBAO) {
      this.taobaoStarted = started
      return
    }
    this.douyinStarted = started
  }

  private setPlatformStarting(platform: LivePlatform, starting: boolean): void {
    if (platform === LivePlatform.TAOBAO) {
      this.taobaoStarting = starting
      return
    }
    this.douyinStarting = starting
  }

  private setPlatformRetryCount(platform: LivePlatform, retryCount: number): void {
    if (platform === LivePlatform.TAOBAO) {
      this.taobaoRetryCount = retryCount
      return
    }
    this.douyinRetryCount = retryCount
  }

  private setPlatformStateText(platform: LivePlatform, text: string): void {
    if (platform === LivePlatform.TAOBAO) {
      this.taobaoStateText = text
      return
    }
    this.douyinStateText = text
  }

  private setPlatformErrorText(platform: LivePlatform, text: string): void {
    if (platform === LivePlatform.TAOBAO) {
      this.taobaoErrorText = text
      return
    }
    this.douyinErrorText = text
  }

  private clearRetryTimer(platform: LivePlatform): void {
    const timer = platform === LivePlatform.TAOBAO ? this.taobaoRetryTimer : this.douyinRetryTimer
    if (timer !== -1) {
      clearTimeout(timer)
    }
    if (platform === LivePlatform.TAOBAO) {
      this.taobaoRetryTimer = -1
      return
    }
    this.douyinRetryTimer = -1
  }

  private setRetryTimer(platform: LivePlatform, timer: number): void {
    if (platform === LivePlatform.TAOBAO) {
      this.taobaoRetryTimer = timer
      return
    }
    this.douyinRetryTimer = timer
  }

  /**
   * 同步播放器状态到页面状态。进入 PLAYING 后清空本轮启动重试计数；
   * 如果已启动后异常 CLOSED，则兜底触发页面重试，避免底层只抛状态不抛错误。
   */
  private handlePlatformStateChange(platform: LivePlatform, state: KooPhoneState): void {
    this.setPlatformStateText(platform, state)
    const isPlaying = state === KooPhoneState.PLAYING
    if (platform === LivePlatform.TAOBAO) {
      this.taobaoPlaying = isPlaying
    } else {
      this.douyinPlaying = isPlaying
    }

    if (isPlaying) {
      this.setPlatformRetryCount(platform, 0)
      this.setPlatformErrorText(platform, '')
      return
    }

    if (state === KooPhoneState.CLOSED &&
      this.shouldStartPlatform(platform) &&
      this.isPlatformStarted(platform) &&
      !this.isPlatformStarting(platform)) {
      this.schedulePlatformRetry(platform, 'KooPhone player closed unexpectedly')
    }
  }

  /**
   * 接收播放器底层错误并交给重试调度。双选时每个平台独立处理，
   * 一路失败不会影响另一路已启动或正在重试的串流。
   */
  private handlePlatformError(platform: LivePlatform, code: KooPhoneError, msg: string): void {
    if (platform === LivePlatform.TAOBAO) {
      this.taobaoPlaying = false
    } else {
      this.douyinPlaying = false
    }
    this.schedulePlatformRetry(platform, `Error ${code}: ${msg}`)
  }

  /**
   * 串流失败后最多自动重试三次。每次重试都重新走 IAM + KooPhone auth，
   * 避免复用已经接近过期的 15 秒 SDK token。
   */
  private schedulePlatformRetry(platform: LivePlatform, reason: string): void {
    if (!this.shouldStartPlatform(platform)) {
      return
    }

    this.clearRetryTimer(platform)
    this.setPlatformStarted(platform, false)
    this.setPlatformStarting(platform, false)
    this.getPlatformPlayer(platform).close()

    const currentRetryCount = this.getRetryCount(platform)
    if (currentRetryCount >= MAX_STREAM_RETRY) {
      this.setPlatformStateText(platform, 'failed')
      this.setPlatformErrorText(platform, `${reason}; 已自动重试 ${MAX_STREAM_RETRY} 次`)
      return
    }

    const nextRetryCount = currentRetryCount + 1
    this.setPlatformRetryCount(platform, nextRetryCount)
    this.setPlatformErrorText(platform, `${reason}; 正在自动重试 ${nextRetryCount}/${MAX_STREAM_RETRY}`)
    this.setPlatformStateText(platform, 'retrying')
    console.warn(`[Index1] ${this.getPlatformTitle(platform)} retry ${nextRetryCount}/${MAX_STREAM_RETRY}: ${reason}`)

    const timer = setTimeout(() => {
      this.setRetryTimer(platform, -1)
      this.startPlatformIfReady(platform)
    }, this.getRetryDelayMs(nextRetryCount)) as number
    this.setRetryTimer(platform, timer)
  }

  private getRetryDelayMs(retryCount: number): number {
    if (retryCount === 1) {
      return 800
    }
    if (retryCount === 2) {
      return 1600
    }
    return 2400
  }

  private getPlatformTitle(platform: LivePlatform): string {
    return platform === LivePlatform.TAOBAO ? '淘宝直播' : '抖音直播'
  }

  private isPlatformSelected(platform: LivePlatform): boolean {
    return platform === LivePlatform.TAOBAO ? this.selectedTaobao : this.selectedDouyin
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

  /**
   * 直播画面触摸转发入口。只有 WebRTC 已进入 PLAYING 后才发送触摸数据，
   * 防止连接阶段把无效输入发给云手机。
   */
  private handleSurfaceTouch(platform: LivePlatform, event: TouchEvent): void {
    if (!this.isPlatformPlaying(platform)) {
      return
    }

    const player: KooPhonePlayer = platform === LivePlatform.TAOBAO ? this.taobaoPlayer : this.douyinPlayer
    const ctrl: KooInputController = player.inputController
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

  /**
   * 选中态圆点。直接读取平台状态，避免 @Builder 参数缓存导致 UI 不刷新。
   */
  @Builder
  selectIndicator(platform: LivePlatform) {
    Stack({ alignContent: Alignment.Center }) {
      Text('')
        .width(28)
        .height(28)
        .border({
          width: 1.5,
          color: this.isPlatformSelected(platform) ? LIVE_RED : '#AAB1BD'
        })
        .borderRadius(14)
        .backgroundColor(Color.Transparent)

      if (this.isPlatformSelected(platform)) {
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

  /**
   * 平台选择行。外屏和展开屏共用同一组件，保证选择逻辑一致。
   */
  @Builder
  platformOption(platform: LivePlatform, title: string) {
    Row({ space: 18 }) {
      this.selectIndicator(platform)

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

  /**
   * 开始直播选择页。rootWidth 变化时只调整间距，不改变交互逻辑。
   */
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
        this.platformOption(LivePlatform.TAOBAO, '淘宝直播')
        this.platformOption(LivePlatform.DOUYIN, '抖音直播')
      }
      .width('100%')

      Blank()

      Row() {
        Blank()
        Row() {
          Text('开始直播')
            .fontSize(18)
            .fontWeight(FontWeight.Medium)
            .fontColor(Color.White)
            .maxLines(1)
        }
          .width(154)
          .height(54)
          .justifyContent(FlexAlign.Center)
          .backgroundColor(this.hasSelection() ? LIVE_RED : DISABLED_BUTTON)
          .borderRadius(27)
          .onClick(() => {
            if (!this.hasSelection()) {
              return
            }
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

  /**
   * 淘宝直播 surface。XComponent 加载完成后才能拿到 surfaceId，
   * 再触发 auth + open 流程。
   */
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

  /**
   * 抖音直播 surface。双选但处于外屏时，该 surface 会等展开后再加载并启动。
   */
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

  /**
   * 按平台选择实际渲染哪个 XComponent。
   */
  @Builder
  surfaceForPlatform(platform: LivePlatform) {
    if (platform === LivePlatform.TAOBAO) {
      this.taobaoSurface()
    } else {
      this.douyinSurface()
    }
  }

  /**
   * 直播画面面板，包含视频 surface 和状态浮层。
   */
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

  /**
   * 展开屏单选时右侧占位。
   */
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

  /**
   * 直播态停止按钮。使用自绘按钮，避免系统 Button 禁用/默认态覆盖颜色。
   */
  @Builder
  stopStreamButton() {
    Row() {
      Text('停止串流')
        .fontSize(15)
        .fontWeight(FontWeight.Medium)
        .fontColor(Color.White)
        .maxLines(1)
    }
    .height(42)
    .padding({ left: 18, right: 18 })
    .justifyContent(FlexAlign.Center)
    .borderRadius(21)
    .backgroundColor('#CC20232A')
    .margin({ right: 20, bottom: 28 })
    .onClick(() => {
      this.stopSelectedStreams()
    })
  }

  /**
   * 纯直播内容区：展开屏左右分栏，外屏/窄屏只展示主直播。
   */
  @Builder
  liveContent() {
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

  /**
   * 直播态根布局。停止按钮覆盖在内容右上角，外屏和展开屏都能直接停止。
   */
  @Builder
  livePage() {
    Stack({ alignContent: Alignment.BottomEnd }) {
      this.liveContent()
      this.stopStreamButton()
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Color.Black)
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
