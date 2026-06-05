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
  KooInstancePoolEntry,
  LivePlatformConfig,
  canStartKooLiveAddSelection,
  selectNextAvailableKooInstance,
  shouldShowKooLiveAddPanel,
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
const KOOPHONE_INSTANCE_POOL: KooInstancePoolEntry[] = [
  { id: TAOBAO_INSTANCE_ID },
  { id: DOUYIN_INSTANCE_ID }
]

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
const OVERLAY_BACKGROUND = '#4D000000'
const CONTROL_BACKGROUND = '#4D20232A'

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
  private taobaoInstanceId: string = TAOBAO_INSTANCE_ID
  private douyinInstanceId: string = DOUYIN_INSTANCE_ID
  private taobaoTriedInstanceIds: string[] = []
  private douyinTriedInstanceIds: string[] = []

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
  @State foldedVisiblePlatform: LivePlatform = LivePlatform.TAOBAO
  @State pendingAddTaobao: boolean = false
  @State pendingAddDouyin: boolean = false

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

    this.clearPendingAddSelection()
    this.resetPlatformRuntime(LivePlatform.TAOBAO)
    this.resetPlatformRuntime(LivePlatform.DOUYIN)
    this.shouldStartTaobao = this.selectedTaobao
    this.shouldStartDouyin = this.selectedDouyin
    this.prepareInitialInstanceAssignments()
    this.foldedVisiblePlatform = this.selectedTaobao ? LivePlatform.TAOBAO : LivePlatform.DOUYIN
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
   * 停止所有正在串流的平台。页面销毁时使用；用户态停止优先使用
   * stopPlatformStream(platform) 关闭单个平台。
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
    this.taobaoTriedInstanceIds = []
    this.douyinTriedInstanceIds = []
    this.taobaoInstanceId = TAOBAO_INSTANCE_ID
    this.douyinInstanceId = DOUYIN_INSTANCE_ID
    this.clearPendingAddSelection()
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
      this.taobaoTriedInstanceIds = []
      this.taobaoInstanceId = TAOBAO_INSTANCE_ID
      return
    }
    this.douyinStarted = false
    this.douyinStarting = false
    this.douyinPlaying = false
    this.douyinRetryCount = 0
    this.douyinErrorText = ''
    this.douyinStateText = 'NEW'
    this.douyinTriedInstanceIds = []
    this.douyinInstanceId = DOUYIN_INSTANCE_ID
  }

  private canStartPlatform(platform: LivePlatform): boolean {
    return this.shouldStartPlatform(platform) &&
      !this.isPlatformStarted(platform) &&
      !this.isPlatformStarting(platform) &&
      !this.isPlatformFailed(platform) &&
      this.isPlatformReady(platform) &&
      this.getPlatformSurfaceId(platform).length > 0
  }

  private canOpenPlatformAfterAuth(platform: LivePlatform): boolean {
    return this.shouldStartPlatform(platform) &&
      !this.isPlatformFailed(platform) &&
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

  /**
   * 生成本次开流使用的平台配置。IAM 配置仍复用静态占位，KooPhone auth URL
   * 按当前实例动态生成，所以实例池切换后会重新鉴权到新的 kp_id。
   */
  private getPlatformConfig(platform: LivePlatform): LivePlatformConfig {
    const baseConfig = platform === LivePlatform.TAOBAO ? TAOBAO_CONFIG : DOUYIN_CONFIG
    const config: LivePlatformConfig = {
      iam: baseConfig.iam,
      kooAuth: {
        authUrl: this.buildKooAuthUrl(this.getPlatformInstanceId(platform)),
        tenantId: baseConfig.kooAuth.tenantId,
        projectId: baseConfig.kooAuth.projectId
      }
    }
    if (baseConfig.iceServers) {
      config.iceServers = baseConfig.iceServers
    }
    if (baseConfig.mode) {
      config.mode = baseConfig.mode
    }
    if (baseConfig.role) {
      config.role = baseConfig.role
    }
    if (baseConfig.sole !== undefined) {
      config.sole = baseConfig.sole
    }
    if (baseConfig.volume !== undefined) {
      config.volume = baseConfig.volume
    }
    return config
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

  private clearPendingAddSelection(): void {
    this.pendingAddTaobao = false
    this.pendingAddDouyin = false
  }

  private isPlatformPendingAdd(platform: LivePlatform): boolean {
    return platform === LivePlatform.TAOBAO ? this.pendingAddTaobao : this.pendingAddDouyin
  }

  private setPlatformPendingAdd(platform: LivePlatform, pending: boolean): void {
    if (platform === LivePlatform.TAOBAO) {
      this.pendingAddTaobao = pending
      return
    }
    this.pendingAddDouyin = pending
  }

  /**
   * 内屏补开面板里的临时选择。已选择或已直播的平台置灰锁定，
   * 只有另一未直播平台可以被选中并启动。
   */
  private togglePendingAddPlatform(platform: LivePlatform): void {
    if (this.isLiveAddOptionDisabled(platform)) {
      return
    }

    const nextPending = !this.isPlatformPendingAdd(platform)
    this.clearPendingAddSelection()
    this.setPlatformPendingAdd(platform, nextPending)
  }

  private isLiveAddOptionDisabled(platform: LivePlatform): boolean {
    return this.isPlatformSelected(platform) || this.isPlatformLiveActive(platform)
  }

  private hasAnyPlatformLiveActive(): boolean {
    return this.isPlatformLiveActive(LivePlatform.TAOBAO) || this.isPlatformLiveActive(LivePlatform.DOUYIN)
  }

  private shouldShowAdditionalSelection(platform: LivePlatform): boolean {
    return shouldShowKooLiveAddPanel({
      isExpandedScreen: this.isExpandedScreen(),
      isSlotLiveActive: this.isPlatformLiveActive(platform),
      isSlotFailed: this.isPlatformFailed(platform),
      hasAnyLiveActive: this.hasAnyPlatformLiveActive(),
      isPendingAdd: this.isPlatformPendingAdd(platform)
    })
  }

  private canStartAdditionalSelection(platform: LivePlatform): boolean {
    return canStartKooLiveAddSelection({
      isExpandedScreen: this.isExpandedScreen(),
      isSlotLiveActive: this.isPlatformLiveActive(platform),
      isSlotFailed: this.isPlatformFailed(platform),
      hasAnyLiveActive: this.hasAnyPlatformLiveActive(),
      isPendingAdd: this.isPlatformPendingAdd(platform)
    })
  }

  private getPreferredInstanceId(platform: LivePlatform): string {
    return platform === LivePlatform.TAOBAO ? TAOBAO_INSTANCE_ID : DOUYIN_INSTANCE_ID
  }

  private setPlatformSelected(platform: LivePlatform, selected: boolean): void {
    if (platform === LivePlatform.TAOBAO) {
      this.selectedTaobao = selected
      return
    }
    this.selectedDouyin = selected
  }

  /**
   * 给补开的单个平台分配初始实例。不会重置另一侧正在播放的平台，
   * 避免补开时破坏现有串流。
   */
  private assignInitialInstanceForPlatform(platform: LivePlatform): void {
    const instanceId = this.resolveInitialInstance(platform, this.getPreferredInstanceId(platform))
    this.setPlatformInstanceId(platform, instanceId)
    this.addTriedInstance(platform, instanceId)
  }

  /**
   * 内屏空半屏点击“开始直播”后的入口。这里只启动当前空槽位对应平台；
   * 外屏不显示该入口，已有直播也不会被重新 open。
   */
  private startAdditionalPlatform(platform: LivePlatform): void {
    if (!this.canStartAdditionalSelection(platform)) {
      return
    }

    this.resetPlatformRuntime(platform)
    this.setPlatformSelected(platform, true)
    this.setShouldStartPlatform(platform, true)
    this.assignInitialInstanceForPlatform(platform)
    this.setPlatformPendingAdd(platform, false)
    this.isLiveStarted = true
    this.startPlatformIfReady(platform)
  }

  private setShouldStartPlatform(platform: LivePlatform, shouldStart: boolean): void {
    if (platform === LivePlatform.TAOBAO) {
      this.shouldStartTaobao = shouldStart
      return
    }
    this.shouldStartDouyin = shouldStart
  }

  private getPlatformInstanceId(platform: LivePlatform): string {
    return platform === LivePlatform.TAOBAO ? this.taobaoInstanceId : this.douyinInstanceId
  }

  private setPlatformInstanceId(platform: LivePlatform, instanceId: string): void {
    if (platform === LivePlatform.TAOBAO) {
      this.taobaoInstanceId = instanceId
      return
    }
    this.douyinInstanceId = instanceId
  }

  /**
   * KooPhone 实例鉴权接口地址。实例 ID 是手写共享池中的 kp_id，
   * 响应里的 signalingUrl、device_token、device_id 会继续传给 SDK。
   */
  private buildKooAuthUrl(instanceId: string): string {
    return `${KOOPHONE_AUTH_HOST}/openapi/koophone/v1/instances/${instanceId}/auth`
  }

  /**
   * 开始直播时保留平台首选实例：淘宝优先 TAOBAO_INSTANCE_ID，
   * 抖音优先 DOUYIN_INSTANCE_ID；后续失败才从共享池选择备用实例。
   */
  private prepareInitialInstanceAssignments(): void {
    if (this.shouldStartTaobao) {
      const taobaoInstanceId = this.resolveInitialInstance(LivePlatform.TAOBAO, TAOBAO_INSTANCE_ID)
      this.setPlatformInstanceId(LivePlatform.TAOBAO, taobaoInstanceId)
      this.addTriedInstance(LivePlatform.TAOBAO, taobaoInstanceId)
    }
    if (this.shouldStartDouyin) {
      const douyinInstanceId = this.resolveInitialInstance(LivePlatform.DOUYIN, DOUYIN_INSTANCE_ID)
      this.setPlatformInstanceId(LivePlatform.DOUYIN, douyinInstanceId)
      this.addTriedInstance(LivePlatform.DOUYIN, douyinInstanceId)
    }
  }

  /**
   * 开始直播的首次实例分配。首选实例不可用或已被另一路占用时，
   * 会从共享池里找第一个本平台尚未尝试且未被占用的实例。
   */
  private resolveInitialInstance(platform: LivePlatform, preferredInstanceId: string): string {
    if (this.isInstanceInPool(preferredInstanceId) &&
      !this.isInstanceUsedByOtherPlatform(platform, preferredInstanceId)) {
      return preferredInstanceId
    }

    const fallbackInstanceId = this.findNextAvailableInstance(platform)
    return fallbackInstanceId.length > 0 ? fallbackInstanceId : preferredInstanceId
  }

  private isInstanceInPool(instanceId: string): boolean {
    for (let i = 0; i < KOOPHONE_INSTANCE_POOL.length; i++) {
      if (KOOPHONE_INSTANCE_POOL[i].id === instanceId) {
        return true
      }
    }
    return false
  }

  private hasTriedInstance(platform: LivePlatform, instanceId: string): boolean {
    const triedInstanceIds = platform === LivePlatform.TAOBAO ? this.taobaoTriedInstanceIds : this.douyinTriedInstanceIds
    for (let i = 0; i < triedInstanceIds.length; i++) {
      if (triedInstanceIds[i] === instanceId) {
        return true
      }
    }
    return false
  }

  private addTriedInstance(platform: LivePlatform, instanceId: string): void {
    if (this.hasTriedInstance(platform, instanceId)) {
      return
    }

    if (platform === LivePlatform.TAOBAO) {
      this.taobaoTriedInstanceIds.push(instanceId)
      return
    }
    this.douyinTriedInstanceIds.push(instanceId)
  }

  private isInstanceUsedByOtherPlatform(platform: LivePlatform, instanceId: string): boolean {
    const otherPlatform = platform === LivePlatform.TAOBAO ? LivePlatform.DOUYIN : LivePlatform.TAOBAO
    return this.shouldStartPlatform(otherPlatform) &&
      !this.isPlatformFailed(otherPlatform) &&
      this.getPlatformInstanceId(otherPlatform) === instanceId
  }

  /**
   * 从共享池中查找备用实例。候选实例必须满足：
   * 不是当前实例、本平台本轮没试过、没有被另一直播正在使用。
   */
  private findNextAvailableInstance(platform: LivePlatform): string {
    const occupiedInstanceIds: string[] = []
    const otherPlatform = platform === LivePlatform.TAOBAO ? LivePlatform.DOUYIN : LivePlatform.TAOBAO
    if (this.shouldStartPlatform(otherPlatform) && !this.isPlatformFailed(otherPlatform)) {
      occupiedInstanceIds.push(this.getPlatformInstanceId(otherPlatform))
    }
    return selectNextAvailableKooInstance(KOOPHONE_INSTANCE_POOL, {
      currentInstanceId: this.getPlatformInstanceId(platform),
      triedInstanceIds: platform === LivePlatform.TAOBAO ? this.taobaoTriedInstanceIds : this.douyinTriedInstanceIds,
      occupiedInstanceIds: occupiedInstanceIds
    })
  }

  /**
   * 当前实例 3 次自动重试耗尽后切到共享池中的下一个空闲实例。
   * 不抢占另一平台正在使用的实例；池耗尽时返回 false。
   */
  private switchToNextAvailableInstance(platform: LivePlatform): boolean {
    const nextInstanceId = this.findNextAvailableInstance(platform)
    if (nextInstanceId.length === 0) {
      return false
    }

    this.setPlatformInstanceId(platform, nextInstanceId)
    this.addTriedInstance(platform, nextInstanceId)
    this.setPlatformRetryCount(platform, 0)
    this.setPlatformStateText(platform, 'switching_instance')
    this.setPlatformErrorText(platform, '当前实例重试失败，正在切换备用实例')
    console.warn(`[Index1] ${this.getPlatformTitle(platform)} switch to backup instance`)
    return true
  }

  /**
   * 用户点击单个平台的“停止直播”时，只关闭该平台当前会话。
   * 选择态保留；如果两路都停止，则回到选择页。
   */
  private stopPlatformStream(platform: LivePlatform): void {
    this.clearRetryTimer(platform)
    this.setShouldStartPlatform(platform, false)
    this.setPlatformStarted(platform, false)
    this.setPlatformStarting(platform, false)
    this.setPlatformRetryCount(platform, 0)
    this.setPlatformErrorText(platform, '')
    this.setPlatformStateText(platform, 'NEW')
    this.setPlatformPendingAdd(platform, false)
    if (platform === LivePlatform.TAOBAO) {
      this.taobaoPlaying = false
      this.taobaoPlayer.close()
    } else {
      this.douyinPlaying = false
      this.douyinPlayer.close()
    }

    this.ensureFoldedVisiblePlatform()
    if (!this.shouldStartTaobao && !this.shouldStartDouyin) {
      this.isLiveStarted = false
    }
  }

  private isPlatformFailed(platform: LivePlatform): boolean {
    return this.getStateText(platform) === 'failed'
  }

  private isPlatformLiveActive(platform: LivePlatform): boolean {
    return this.shouldStartPlatform(platform) && !this.isPlatformFailed(platform)
  }

  private isBothPlatformsLiveActive(): boolean {
    return this.isPlatformLiveActive(LivePlatform.TAOBAO) && this.isPlatformLiveActive(LivePlatform.DOUYIN)
  }

  private shouldShowFoldedSwitch(): boolean {
    return !this.isExpandedScreen() && this.isBothPlatformsLiveActive()
  }

  /**
   * 外屏实际显示哪一路：优先使用用户手动切到的平台；
   * 如果该平台已停止或失败，则自动回落到仍在直播的另一路。
   */
  private getFoldedDisplayPlatform(): LivePlatform {
    if (this.isPlatformLiveActive(this.foldedVisiblePlatform)) {
      return this.foldedVisiblePlatform
    }
    if (this.isPlatformLiveActive(LivePlatform.TAOBAO)) {
      return LivePlatform.TAOBAO
    }
    return LivePlatform.DOUYIN
  }

  private ensureFoldedVisiblePlatform(): void {
    this.foldedVisiblePlatform = this.getFoldedDisplayPlatform()
  }

  /**
   * 外屏切换只修改 foldedVisiblePlatform，不修改 shouldStart 或选择态，
   * 因此展开后仍保持左淘宝、右抖音的固定布局。
   */
  private toggleFoldedVisiblePlatform(): void {
    if (!this.isBothPlatformsLiveActive()) {
      return
    }
    this.foldedVisiblePlatform = this.foldedVisiblePlatform === LivePlatform.TAOBAO ?
      LivePlatform.DOUYIN :
      LivePlatform.TAOBAO
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
   * 串流失败后先对当前实例最多自动重试三次。每次重试都会重新走
   * IAM + KooPhone auth，避免复用 15 秒短效 SDK token；当前实例三次
   * 都失败后再切换共享池备用实例。
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
      if (this.switchToNextAvailableInstance(platform)) {
        const timer = setTimeout(() => {
          this.setRetryTimer(platform, -1)
          this.startPlatformIfReady(platform)
        }, this.getRetryDelayMs(1)) as number
        this.setRetryTimer(platform, timer)
        return
      }
      this.setPlatformStateText(platform, 'failed')
      this.setPlatformErrorText(platform, `${reason}; 当前租户共享实例池已耗尽`)
      this.ensureFoldedVisiblePlatform()
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
   * 内屏补开面板的选项圆点。已直播/已选择的平台使用灰色锁定态；
   * 用户正在补选的平台使用红色选中态。
   */
  @Builder
  liveAddIndicator(platform: LivePlatform, disabled: boolean) {
    Stack({ alignContent: Alignment.Center }) {
      Text('')
        .width(26)
        .height(26)
        .border({
          width: 1.4,
          color: disabled ? '#C5CAD4' : (this.isPlatformPendingAdd(platform) ? LIVE_RED : '#AAB1BD')
        })
        .borderRadius(13)
        .backgroundColor(Color.Transparent)

      if (this.isPlatformPendingAdd(platform) && !disabled) {
        Text('')
          .width(12)
          .height(12)
          .borderRadius(6)
          .backgroundColor(LIVE_RED)
      }
    }
    .width(30)
    .height(30)
  }

  /**
   * 内屏空半屏的补开选项。和初始选择页保持同样的两行结构，
   * 但已选择过的直播平台置灰且不可点击。
   */
  @Builder
  liveAddPlatformOption(platform: LivePlatform) {
    Row({ space: 16 }) {
      this.liveAddIndicator(platform, this.isLiveAddOptionDisabled(platform))

      Text(this.getPlatformTitle(platform))
        .fontSize(18)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.isLiveAddOptionDisabled(platform) ? '#A8AFBA' : TEXT_PRIMARY)
        .maxLines(1)
    }
    .width('100%')
    .height(66)
    .padding({ left: 24, right: 22 })
    .backgroundColor(this.isLiveAddOptionDisabled(platform) ? '#ECEFF5' : ROW_BACKGROUND)
    .borderRadius(4)
    .alignItems(VerticalAlign.Center)
    .onClick(() => {
      this.togglePendingAddPlatform(platform)
    })
  }

  /**
   * 展开屏单路直播时，另一半屏显示的补开选择页。
   * 外屏不渲染这个 Builder，用户需要展开 Mate X7 后才能补开第二路。
   */
  @Builder
  liveAddSelectionPanel(slotPlatform: LivePlatform) {
    Column() {
      Text('开始直播')
        .fontSize(24)
        .fontWeight(FontWeight.Bold)
        .fontColor(TEXT_PRIMARY)
        .width('100%')

      Text('请选择直播平台')
        .fontSize(20)
        .fontColor(TEXT_SECONDARY)
        .width('100%')
        .textAlign(TextAlign.Center)
        .margin({ top: 86, bottom: 24 })

      Column({ space: 18 }) {
        this.liveAddPlatformOption(LivePlatform.TAOBAO)
        this.liveAddPlatformOption(LivePlatform.DOUYIN)
      }
      .width('100%')

      Blank()

      Row() {
        Blank()
        Row() {
          Text('开始直播')
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor(Color.White)
            .maxLines(1)
        }
        .width(136)
        .height(48)
        .justifyContent(FlexAlign.Center)
        .backgroundColor(this.canStartAdditionalSelection(slotPlatform) ? LIVE_RED : DISABLED_BUTTON)
        .borderRadius(24)
        .onClick(() => {
          this.startAdditionalPlatform(slotPlatform)
        })
      }
      .width('100%')
    }
    .width('100%')
    .height('100%')
    .padding({ top: 50, left: 40, right: 40, bottom: 34 })
    .backgroundColor(PAGE_BACKGROUND)
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
   * 直播状态小浮层。透明度固定在 30%，只保留排障所需的平台名、状态和错误摘要。
   */
  @Builder
  streamStatusOverlay(platform: LivePlatform) {
    Column({ space: 2 }) {
      Text(this.getPlatformTitle(platform))
        .fontSize(12)
        .fontWeight(FontWeight.Medium)
        .fontColor(Color.White)
        .maxLines(1)

      if (this.getErrorText(platform).length > 0) {
        Text(this.getErrorText(platform))
          .fontSize(9)
          .fontColor('#FFD3D3')
          .maxLines(2)
      } else {
        Text(this.getStateText(platform))
          .fontSize(9)
          .fontColor('#DDE3EA')
          .maxLines(1)
      }
    }
    .padding({ top: 5, right: 8, bottom: 5, left: 8 })
    .margin({ top: this.shouldShowFoldedSwitch() ? 54 : 12, left: 12 })
    .borderRadius(5)
    .backgroundColor(OVERLAY_BACKGROUND)
  }

  /**
   * 外屏双路直播时的可见直播切换按钮。只改变外屏当前显示的平台，
   * 不改变展开屏左淘宝、右抖音的固定槽位布局。
   */
  @Builder
  foldedSwitchButton() {
    Row() {
      Text('切换直播')
        .fontSize(11)
        .fontWeight(FontWeight.Medium)
        .fontColor(Color.White)
        .maxLines(1)
    }
    .width(78)
    .height(34)
    .justifyContent(FlexAlign.Center)
    .borderRadius(17)
    .backgroundColor(CONTROL_BACKGROUND)
    .margin({ top: 12, left: 12 })
    .onClick(() => {
      this.toggleFoldedVisiblePlatform()
    })
  }

  /**
   * 每路独立停止按钮。点击后只停止当前平台，另一路播放和布局不受影响。
   */
  @Builder
  stopPlatformButton(platform: LivePlatform) {
    Row() {
      Text('停止直播')
        .fontSize(11)
        .fontWeight(FontWeight.Medium)
        .fontColor(Color.White)
        .maxLines(1)
    }
    .width(78)
    .height(34)
    .justifyContent(FlexAlign.Center)
    .borderRadius(17)
    .backgroundColor(CONTROL_BACKGROUND)
    .onClick(() => {
      this.stopPlatformStream(platform)
    })
  }

  /**
   * 直播画面面板，包含视频 surface、低透明状态浮层、外屏切换按钮和单路停止按钮。
   */
  @Builder
  streamPanel(platform: LivePlatform) {
    Stack({ alignContent: Alignment.TopStart }) {
      this.surfaceForPlatform(platform)

      if (this.shouldShowFoldedSwitch()) {
        this.foldedSwitchButton()
      }

      this.streamStatusOverlay(platform)

      Column() {
        Blank()
        Row() {
          Blank()
          this.stopPlatformButton(platform)
        }
        .width('100%')
        .margin({ right: 12, bottom: 14 })
      }
      .width('100%')
      .height('100%')
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Color.Black)
  }

  /**
   * 未开流、已单路停止或实例池耗尽时的固定槽位占位。
   */
  @Builder
  emptyLivePanel(platform: LivePlatform) {
    Column({ space: 10 }) {
      Blank()
      if (this.isPlatformFailed(platform)) {
        Text('串流失败')
          .fontSize(20)
          .fontWeight(FontWeight.Medium)
          .fontColor(TEXT_PRIMARY)
          .textAlign(TextAlign.Center)

        Text(this.getErrorText(platform))
          .fontSize(13)
          .fontColor(TEXT_SECONDARY)
          .textAlign(TextAlign.Center)
          .maxLines(3)
          .padding({ left: 18, right: 18 })
      } else {
        Text('暂无直播内容')
          .fontSize(22)
          .fontWeight(FontWeight.Medium)
          .fontColor(TEXT_SECONDARY)
          .textAlign(TextAlign.Center)
      }
      Blank()
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#F1F3F8')
  }

  /**
   * 固定平台槽位。展开屏左槽始终淘宝，右槽始终抖音；
   * 外屏只渲染当前可见平台，停止当前平台后会自动落到另一活跃平台。
   */
  @Builder
  platformLiveSlot(platform: LivePlatform) {
    if (this.isPlatformLiveActive(platform)) {
      this.streamPanel(platform)
    } else if (this.shouldShowAdditionalSelection(platform)) {
      this.liveAddSelectionPanel(platform)
    } else {
      this.emptyLivePanel(platform)
    }
  }

  /**
   * 纯直播内容区：展开屏固定左右槽位，外屏/窄屏只展示 foldedVisiblePlatform。
   */
  @Builder
  liveContent() {
    if (this.isExpandedScreen()) {
      Row() {
        Column() {
          this.platformLiveSlot(LivePlatform.TAOBAO)
        }
        .height('100%')
        .layoutWeight(1)

        Column() {
          this.platformLiveSlot(LivePlatform.DOUYIN)
        }
        .height('100%')
        .layoutWeight(1)
      }
      .width('100%')
      .height('100%')
      .backgroundColor(Color.Black)
    } else {
      this.platformLiveSlot(this.getFoldedDisplayPlatform())
    }
  }

  /**
   * 直播态根布局。控制按钮已经下沉到每个 streamPanel，根节点只负责承载直播内容。
   */
  @Builder
  livePage() {
    this.liveContent()
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
