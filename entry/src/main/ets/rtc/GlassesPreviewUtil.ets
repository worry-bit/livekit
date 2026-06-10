import { abilityAccessCtrl, common } from '@kit.AbilityKit'
import { BusinessError } from '@kit.BasicServicesKit'
import { camera } from '@kit.CameraKit'

// CameraKit 文档中的 CAMERA_CONNECTION_REMOTE 枚举值，保留数值兜底是为了兼容真机日志和 ArkTS 枚举比较。
const REMOTE_CAMERA_CONNECTION_TYPE = 2
// AI 眼镜预览按视频场景创建会话，真机诊断里该枚举值为 2。
const GLASSES_PREVIEW_SCENE_MODE = camera.SceneMode.NORMAL_VIDEO
// CameraDevice.hostDeviceName 返回的眼镜主机名；它是反参筛选条件，不是传给 CameraKit 的入参。
const AI_GLASSES_HOST_NAME = 'AI Glasses'
// 真机抓日志使用的稳定前缀，便于从 hilog 中精确抽取 entry 侧 CameraKit 入参/反参。
const AI_GLASS_LOG_PREFIX = '[AI_GLASS_DBG]'

interface CameraPositionQueryCase {
  name: string
  value: camera.CameraPosition
}

interface CameraTypeQueryCase {
  name: string
  values: camera.CameraType[]
}

/**
 * AI 眼镜本地预览实验工具。
 * 这里只使用 CameraKit 打开系统枚举到的 remote camera，并把预览直接渲染到页面 XComponent。
 * 它不连接 SFU、不创建 LiveKit 房间，也不经过 @ohos/webrtc，便于单独验证眼镜摄像头是否可被第三方应用预览。
 */
class GlassesPreviewUtil {
  errorMessage: string = ''
  diagnosticText: string = ''
  isPreviewing: boolean = false

  private context: common.UIAbilityContext = getContext(this) as common.UIAbilityContext
  private cameraInput: camera.CameraInput | null = null
  private previewOutput: camera.PreviewOutput | null = null
  private session: camera.Session | null = null

  /**
   * 打开当前系统已注册的 remote camera 本地预览。
   * @param surfaceId XComponent onLoad 后取得的 surfaceId。
   * @param preferredDeviceId 真机构建时临时注入的 remote cameraId，仅作为优先匹配项。
   */
  async startPreview(surfaceId: string, preferredDeviceId: string = ''): Promise<boolean> {
    // 校验 ArkUI XComponent 已经创建出可给相机预览使用的 surface。
    if (surfaceId.length === 0) {
      // 记录页面可见错误，避免在没有渲染目标时继续调用 CameraKit。
      this.errorMessage = '眼镜预览 surface 未准备好'
      // surface 缺失时直接返回失败，此时不会触发 AI 眼镜。
      return false
    }

    // 记录本次调用开始状态，preferredDeviceId 只用于优先匹配，不是 CameraKit 强制入参。
    this.diagnosticText = `startPreview: surface=ready, preferredDeviceId=${this.maskDeviceId(preferredDeviceId)}`

    // 请求当前应用访问相机的运行时权限。
    const permissionGranted = await this.requestCameraPermission()
    // 权限未授予时，不能创建 CameraInput。
    if (!permissionGranted) {
      // 权限失败会在 requestCameraPermission 内写入 errorMessage。
      return false
    }

    // 从 CameraKit 返回的 remote camera 列表中解析要使用的 AI Glasses CameraDevice。
    const cameraDevice = this.resolveRemoteCamera(preferredDeviceId)
    // 如果系统当前没有暴露 AI Glasses remote camera，就停止本次预览。
    if (!cameraDevice) {
      // resolveRemoteCamera 会记录“没有 CAMERA_CONNECTION_REMOTE 返回眼镜摄像头”等诊断。
      return false
    }

    // 打开新预览前先释放旧会话，避免同一页面重复占用摄像头。
    await this.stopPreview()

    try {
      // 创建 CameraManager；后续所有 CameraKit 枚举、输入、输出、会话都从它发起。
      const cameraManager = camera.getCameraManager(this.context)
      // 注册 CameraManager cameraStatus 回调，记录系统上报的 cameraId/status。
      this.registerCameraStatusLogger(cameraManager)
      // 诊断记录：这里使用的 cameraDevice 就是 remote 查询返回且 hostDeviceName=AI Glasses 的对象。
      this.appendDiagnosticLine(`createCameraInput(cameraDevice): id=${this.maskDeviceId(cameraDevice.cameraId)}`)
      // 使用 CameraDevice 创建 CameraInput；这是把 AI Glasses remote device 真正交给 CameraKit 的关键调用。
      const cameraInput = cameraManager.createCameraInput(cameraDevice)
      // 注册 CameraInput 错误与遮挡检测回调，观察 AI 眼镜/CameraKit 是否把隐私灯问题透回应用层。
      this.registerCameraInputLoggers(cameraInput, cameraDevice)
      // 打开 CameraInput；真机上这一步会触发 AI 眼镜本体的摄像头启用流程。
      await cameraInput.open()
      // 诊断记录：open 成功说明 CameraKit 接受了这个 remote CameraDevice。
      this.appendDiagnosticLine('cameraInput.open(): success')

      // 查询并选择适合当前 remote CameraDevice 的预览 profile。
      const previewProfile = this.resolvePreviewProfile(cameraManager, cameraDevice, GLASSES_PREVIEW_SCENE_MODE)
      // 诊断记录：把即将用于 createPreviewOutput 的分辨率写到页面上。
      this.appendDiagnosticLine(
        // 当前优先选择接近 1280x720 的 preview profile。
        `createPreviewOutput(profile, surfaceId): ${previewProfile.size.width}x${previewProfile.size.height}`
      )
      // 创建预览输出，把 CameraKit 输出绑定到 ArkUI XComponent surface。
      const previewOutput = cameraManager.createPreviewOutput(previewProfile, surfaceId)
      // 诊断记录：当前使用普通视频会话 NORMAL_VIDEO，数值为 2。
      this.appendDiagnosticLine(`createSession(mode): NORMAL_VIDEO=${Number(GLASSES_PREVIEW_SCENE_MODE)}`)
      // 创建 VideoSession，用于把输入 cameraInput 和输出 previewOutput 配成一条相机预览管线。
      const session = cameraManager.createSession(GLASSES_PREVIEW_SCENE_MODE) as camera.VideoSession
      // 开始配置相机会话；beginConfig 和 commitConfig 之间只能做 addInput/addOutput 等配置动作。
      session.beginConfig()
      // 把 AI Glasses remote CameraInput 加入会话。
      session.addInput(cameraInput)
      // 把 XComponent 对应的预览输出加入会话。
      session.addOutput(previewOutput)
      // 提交会话配置；这一步通过后，输入输出管线已经配置完成。
      await session.commitConfig()
      // 诊断记录：commitConfig 成功。
      this.appendDiagnosticLine('session.commitConfig(): success')
      // 启动会话；这一步成功后 CameraService 会出现 Active Camera。
      await session.start()
      // 诊断记录：session.start 成功，说明 CameraKit 链路已经跑到系统相机会话层。
      this.appendDiagnosticLine('session.start(): success')

      // 保存 CameraInput 引用，后续停止预览时需要 close。
      this.cameraInput = cameraInput
      // 保存 PreviewOutput 引用，后续停止预览时需要 release。
      this.previewOutput = previewOutput
      // 保存 Session 引用，后续停止预览时需要 stop/release。
      this.session = session
      // 标记页面当前处于预览状态，用于按钮文案和状态切换。
      this.isPreviewing = true
      // 清空错误文案，避免成功后继续展示旧错误。
      this.errorMessage = ''
      // 输出 hilog，方便从设备日志里确认远端眼镜预览已经启动。
      console.info('[GlassesPreviewUtil] CameraKit remote glasses preview started with NORMAL_VIDEO session')
      // 返回成功给页面，页面会把按钮切成“关闭眼镜预览”。
      return true
    } catch (error) {
      // 任意 CameraKit 调用失败时，把错误透出到页面。
      this.errorMessage = `打开眼镜预览失败：${String(error)}`
      // 输出失败日志，保留具体 CameraKit 错误信息。
      console.error('[GlassesPreviewUtil] CameraKit startPreview failed:', error)
      // 失败后释放半初始化资源，避免相机输入或 surface 泄漏。
      await this.stopPreview()
      // 返回失败给页面，页面保持“开始眼镜预览”状态。
      return false
    }
  }

  /**
   * 停止 CameraKit 会话并释放 input/output。这里吞掉释放阶段异常，避免关闭按钮把页面卡住。
   */
  async stopPreview(): Promise<void> {
    const session = this.session
    const previewOutput = this.previewOutput
    const cameraInput = this.cameraInput

    this.session = null
    this.previewOutput = null
    this.cameraInput = null
    this.isPreviewing = false

    if (session) {
      try {
        await session.stop()
      } catch (error) {
        console.warn('[GlassesPreviewUtil] session.stop skipped:', String(error))
      }
      try {
        await session.release()
      } catch (error) {
        console.warn('[GlassesPreviewUtil] session.release skipped:', String(error))
      }
    }

    if (previewOutput) {
      try {
        await previewOutput.release()
      } catch (error) {
        console.warn('[GlassesPreviewUtil] previewOutput.release skipped:', String(error))
      }
    }

    if (cameraInput) {
      try {
        await cameraInput.close()
      } catch (error) {
        console.warn('[GlassesPreviewUtil] cameraInput.close skipped:', String(error))
      }
    }
  }

  /**
   * 只解析 AI 眼镜 remote cameraId，不打开 CameraKit 预览。
   * LiveKit 推流会把这个 cameraId 作为 VideoCaptureOptions.deviceId 交给 SDK。
   */
  resolveAiGlassesCameraId(preferredDeviceId: string = ''): string {
    this.diagnosticText = `resolveAiGlassesCameraId: preferredDeviceId=${this.maskDeviceId(preferredDeviceId)}`
    const cameraDevice = this.resolveRemoteCamera(preferredDeviceId)
    if (!cameraDevice) {
      return ''
    }

    this.errorMessage = ''
    this.appendDiagnosticLine(`ai glasses deviceId ready: ${this.maskDeviceId(cameraDevice.cameraId)}`)
    return cameraDevice.cameraId
  }

  /**
   * 选择一个明确的本机摄像头 cameraId，避免 @ohos/webrtc 在 Mate X7 折叠态自行猜前摄。
   * 默认优先后置广角；如果后置不可用，再退到其它有 preview profile 的本机摄像头。
   */
  resolvePreferredPhoneCameraId(): string {
    try {
      const cameraManager = camera.getCameraManager(this.context)
      const phoneCameras = this.getLocalPhoneCameras(cameraManager)
      this.logCameraDeviceList('getSupportedCameras.phoneCandidates', phoneCameras)
      if (phoneCameras.length === 0) {
        this.errorMessage = '没有可用的本机摄像头'
        return ''
      }

      const cameraDevice = this.pickPreferredPhoneCamera(phoneCameras)
      this.errorMessage = ''
      this.diagnosticText = `selected phone camera: ${this.describeCameraDevice('phone', 0, cameraDevice)}`
      console.info(`${AI_GLASS_LOG_PREFIX} selected phone camera ${this.describeCameraDevice('phone', 0, cameraDevice)}`)
      return cameraDevice.cameraId
    } catch (error) {
      this.errorMessage = `枚举本机摄像头失败：${String(error)}`
      console.error('[GlassesPreviewUtil] resolvePreferredPhoneCameraId failed:', error)
      return ''
    }
  }

  /**
   * 推流中切换手机摄像头时使用。它只在已知的安全本机 cameraId 列表中循环，
   * 不调用 SDK 的默认 switchCamera，避免再次进入折叠屏前摄崩溃路径。
   */
  resolveNextPhoneCameraId(currentDeviceId: string): string {
    try {
      const cameraManager = camera.getCameraManager(this.context)
      const phoneCameras = this.getLocalPhoneCameras(cameraManager)
      this.logCameraDeviceList('getSupportedCameras.phoneSwitchCandidates', phoneCameras)
      if (phoneCameras.length === 0) {
        this.errorMessage = '没有可切换的本机摄像头'
        return ''
      }
      if (phoneCameras.length === 1) {
        this.errorMessage = '当前只有一个可用的本机摄像头'
        return phoneCameras[0].cameraId
      }

      const normalizedCurrent = currentDeviceId.trim()
      let currentIndex = -1
      for (let i = 0; i < phoneCameras.length; i++) {
        if (phoneCameras[i].cameraId === normalizedCurrent) {
          currentIndex = i
          break
        }
      }

      const nextIndex = currentIndex < 0 ? 0 : (currentIndex + 1) % phoneCameras.length
      const nextCamera = phoneCameras[nextIndex]
      this.errorMessage = ''
      this.diagnosticText = `switch phone camera: ${this.describeCameraDevice('phone', nextIndex, nextCamera)}`
      console.info(`${AI_GLASS_LOG_PREFIX} switch phone camera ${this.describeCameraDevice('phone', nextIndex, nextCamera)}`)
      return nextCamera.cameraId
    } catch (error) {
      this.errorMessage = `切换本机摄像头失败：${String(error)}`
      console.error('[GlassesPreviewUtil] resolveNextPhoneCameraId failed:', error)
      return ''
    }
  }

  /**
   * 只请求摄像头权限。眼镜本地预览不需要麦克风，也不需要连接 SFU。
   */
  private async requestCameraPermission(): Promise<boolean> {
    const atManager = abilityAccessCtrl.createAtManager()
    try {
      const result = await atManager.requestPermissionsFromUser(this.context, ['ohos.permission.CAMERA'])
      const cameraGranted = result.authResults.length > 0 && result.authResults[0] === 0
      if (!cameraGranted) {
        this.errorMessage = '需要摄像头权限才能预览眼镜画面'
        return false
      }
      this.errorMessage = ''
      return true
    } catch (error) {
      this.errorMessage = `请求摄像头权限失败：${String(error)}`
      console.error('[GlassesPreviewUtil] requestCameraPermission failed:', error)
      return false
    }
  }

  /**
   * 从 CameraKit 当前设备列表中选择 remote camera。
   * 当前 Mate X7 只有当 AI 眼镜以分布式摄像头注册成功时，这里才会返回 CameraDevice；
   * 只有蓝牙连接但未注册 remote camera 时，会返回 null 并提示用户检查眼镜协同连接状态。
   */
  private resolveRemoteCamera(preferredDeviceId: string): camera.CameraDevice | null {
    try {
      // 创建 CameraManager，用于查询当前系统暴露的摄像头设备。
      const cameraManager = camera.getCameraManager(this.context)
      // 只用 CAMERA_CONNECTION_REMOTE 查询 remote camera，避免误选本机摄像头。
      const remoteCameras = this.getRemoteCamerasFromConnectionQuery(cameraManager)

      // 如果 remote 查询没有返回任何相机，说明当前 AI 眼镜还没有注册成 remote camera。
      if (remoteCameras.length === 0) {
        // 把无法枚举 remote camera 的原因展示到页面。
        this.errorMessage = '当前系统没有通过 CAMERA_CONNECTION_REMOTE 返回眼镜摄像头'
        // 同步输出日志，方便和 CameraService 的 Number of Cameras 交叉验证。
        console.warn('[GlassesPreviewUtil] No CAMERA_CONNECTION_REMOTE camera found')
        // 返回 null，调用方不会继续 createCameraInput。
        return null
      }

      // 去掉外部传入 cameraId 的空白字符。
      const normalizedPreferredId = preferredDeviceId.trim()
      // 如果真机构建临时注入了具体 remote cameraId，则先按 cameraId 精确匹配。
      if (normalizedPreferredId.length > 0) {
        // 遍历所有 remote camera，寻找 cameraId 完全一致的设备。
        for (let i = 0; i < remoteCameras.length; i++) {
          // cameraId 完全一致时，优先使用该 CameraDevice。
          if (remoteCameras[i].cameraId === normalizedPreferredId) {
            // 记录最终选择原因和 CameraDevice 反参。
            this.appendSelectedCameraDiagnostic('preferred cameraId', remoteCameras[i])
            // 输出日志，说明命中了 preferredDeviceId。
            console.info('[GlassesPreviewUtil] Using preferred CAMERA_CONNECTION_REMOTE camera')
            // 返回 CameraKit 反参里的 CameraDevice 对象，后续传给 createCameraInput。
            return remoteCameras[i]
          }
        }
      }

      // 如果没有指定 cameraId，或指定 cameraId 没匹配到，则按 hostDeviceName 选择 AI Glasses。
      for (let i = 0; i < remoteCameras.length; i++) {
        // hostDeviceName 是 CameraDevice 的只读反参，当前 AI 眼镜返回值为 AI Glasses。
        if (remoteCameras[i].hostDeviceName === AI_GLASSES_HOST_NAME) {
          // 记录最终选择原因是 hostDeviceName AI Glasses。
          this.appendSelectedCameraDiagnostic('hostDeviceName AI Glasses', remoteCameras[i])
          // 输出日志，说明当前选择的是 AI Glasses remote camera。
          console.info('[GlassesPreviewUtil] Using AI Glasses CAMERA_CONNECTION_REMOTE camera')
          // 返回 CameraKit 反参里的 AI Glasses CameraDevice。
          return remoteCameras[i]
        }
      }

      // 如果系统返回 remote camera 但 host 不是 AI Glasses，则退化使用第一个 remote camera。
      console.info('[GlassesPreviewUtil] Using first CAMERA_CONNECTION_REMOTE camera')
      // 记录 fallback 选择结果，方便排查是否误选了非眼镜设备。
      this.appendSelectedCameraDiagnostic('first remote fallback', remoteCameras[0])
      // 返回第一个 remote CameraDevice。
      return remoteCameras[0]
    } catch (error) {
      // 枚举或选择 remote camera 过程中出现异常时，把异常展示到页面。
      this.errorMessage = `枚举眼镜摄像头失败：${String(error)}`
      // 输出错误日志，便于 hilog 定位。
      console.error('[GlassesPreviewUtil] resolveRemoteCamera failed:', error)
      // 返回 null，调用方不会继续打开相机。
      return null
    }
  }

  private getRemoteCamerasFromConnectionQuery(cameraManager: camera.CameraManager): camera.CameraDevice[] {
    try {
      // 调用 HarmonyOS CameraKit 标准接口：按方向、类型、连接方式查询指定相机设备。
      const remoteCameras = cameraManager.getCameraDevices(
        // 入参 1：只查询后置方向的摄像头，AI 眼镜 remote camera 当前返回 pos=1/back。
        camera.CameraPosition.CAMERA_POSITION_BACK,
        // 入参 2：只查询广角摄像头，AI 眼镜 remote camera 当前返回 type=1/wide-angle。
        [camera.CameraType.CAMERA_TYPE_WIDE_ANGLE],
        // 入参 3：只查询远端摄像头，避免把 Mate X7 自带摄像头误当作眼镜。
        camera.ConnectionType.CAMERA_CONNECTION_REMOTE
      )
      // hilog 记录 getCameraDevices 入参和返回数量。
      console.info(`${AI_GLASS_LOG_PREFIX} getCameraDevices input position=BACK,type=WIDE_ANGLE,connection=REMOTE`)
      // hilog 记录 getCameraDevices 返回的完整 CameraDevice 摘要。
      this.logCameraDeviceList('getCameraDevices.remoteReturn', remoteCameras)
      // 额外做一次 position/type 全组合枚举，排查 BACK + WIDE_ANGLE 过滤条件是否遗漏其他 AI 眼镜设备。
      this.logRemoteCameraQueryMatrix(cameraManager)
      // 把 getCameraDevices 的反参和 getSupportedCameras 的本机列表都写入诊断文本。
      this.updateCameraDiagnostics(cameraManager, remoteCameras, 'strict remote query')
      // 创建过滤后的 remote camera 列表。
      const filteredCameras: camera.CameraDevice[] = []
      // 遍历 getCameraDevices 返回的 CameraDevice[]。
      for (let i = 0; i < remoteCameras.length; i++) {
        // 二次校验 connectionType，确保只保留 CAMERA_CONNECTION_REMOTE。
        if (this.isStrictRemoteCamera(remoteCameras[i])) {
          // 通过 strict remote 校验后加入候选列表。
          filteredCameras.push(remoteCameras[i])
        }
      }
      // 返回只包含 remote camera 的候选列表。
      return filteredCameras
    } catch (error) {
      // getCameraDevices 失败时记录日志，通常需要和系统 CameraService 状态一起看。
      console.warn('[GlassesPreviewUtil] query remote camera by connection type failed:', String(error))
      // 页面诊断记录严格 remote 查询失败。
      this.updateCameraDiagnostics(cameraManager, [], `strict remote query failed: ${String(error)}`)
      // 查询失败时返回空列表，调用方不会继续打开相机。
      return []
    }
  }

  private getLocalPhoneCameras(cameraManager: camera.CameraManager): camera.CameraDevice[] {
    const supportedCameras = cameraManager.getSupportedCameras()
    this.logCameraDeviceList('getSupportedCameras.allForPhoneQuery', supportedCameras)
    const result: camera.CameraDevice[] = []

    for (let i = 0; i < supportedCameras.length; i++) {
      const cameraDevice = supportedCameras[i]
      if (this.isStrictRemoteCamera(cameraDevice)) {
        continue
      }
      if (!this.hasUsablePreviewProfile(cameraManager, cameraDevice)) {
        console.warn(`${AI_GLASS_LOG_PREFIX} skip phone camera without preview profile: ${this.describeCameraDevice('phone', i, cameraDevice)}`)
        continue
      }
      result.push(cameraDevice)
    }
    return result
  }

  private pickPreferredPhoneCamera(cameraDevices: camera.CameraDevice[]): camera.CameraDevice {
    for (let i = 0; i < cameraDevices.length; i++) {
      if (cameraDevices[i].cameraPosition === camera.CameraPosition.CAMERA_POSITION_BACK &&
        cameraDevices[i].cameraType === camera.CameraType.CAMERA_TYPE_WIDE_ANGLE) {
        return cameraDevices[i]
      }
    }
    for (let i = 0; i < cameraDevices.length; i++) {
      if (cameraDevices[i].cameraPosition === camera.CameraPosition.CAMERA_POSITION_BACK) {
        return cameraDevices[i]
      }
    }
    return cameraDevices[0]
  }

  private hasUsablePreviewProfile(
    cameraManager: camera.CameraManager,
    cameraDevice: camera.CameraDevice
  ): boolean {
    try {
      let outputCapability = cameraManager.getSupportedOutputCapability(cameraDevice, camera.SceneMode.NORMAL_VIDEO)
      if (outputCapability.previewProfiles.length === 0) {
        outputCapability = cameraManager.getSupportedOutputCapability(cameraDevice)
      }
      return outputCapability.previewProfiles.length > 0
    } catch (error) {
      console.warn(
        `${AI_GLASS_LOG_PREFIX} getSupportedOutputCapability failed for ` +
          `${this.describeCameraDevice('phone', 0, cameraDevice)}: ${String(error)}`
      )
      return false
    }
  }

  /**
   * 记录本机相机列表和严格 remote 查询结果，便于真机实验时确认当前是否真的枚举到 AI 眼镜。
   */
  private updateCameraDiagnostics(
    cameraManager: camera.CameraManager,
    remoteCameras: camera.CameraDevice[],
    stage: string
  ): void {
    // 查询 CameraKit 当前能看到的全部摄像头，用来和 strict remote 查询结果做对照。
    const supportedCameras = cameraManager.getSupportedCameras()
    // hilog 记录 getSupportedCameras 的完整返回，和 strict remote 返回做对照。
    this.logCameraDeviceList('getSupportedCameras.allReturn', supportedCameras)
    // 创建页面诊断文本行数组。
    const lines: string[] = []
    // 第一行记录当前阶段、全部摄像头数量、strict remote 摄像头数量。
    lines.push(`${stage}: all=${supportedCameras.length}, remote=${remoteCameras.length}`)

    // 遍历全部摄像头，输出本机内置摄像头和系统暴露的其他摄像头。
    for (let i = 0; i < supportedCameras.length; i++) {
      // 把每个 CameraDevice 的 cameraId、连接类型、方向、host 等字段格式化。
      lines.push(this.describeCameraDevice('all', i, supportedCameras[i]))
    }

    // 遍历 strict remote 查询返回的摄像头。
    for (let i = 0; i < remoteCameras.length; i++) {
      // 把 remote CameraDevice 的字段也写入诊断，重点看 hostDeviceName 是否为 AI Glasses。
      lines.push(this.describeCameraDevice('remote', i, remoteCameras[i]))
    }

    // 把诊断数组合并成多行文本，页面会直接展示这段内容。
    this.diagnosticText = lines.join('\n')
    // 同步写 hilog，便于用日志复盘设备枚举结果。
    console.info('[GlassesPreviewUtil] camera diagnostics:', this.diagnosticText)
  }

  private appendSelectedCameraDiagnostic(reason: string, cameraDevice: camera.CameraDevice): void {
    // 在诊断文本末尾补充最终选中的 CameraDevice，以及选中原因。
    this.appendDiagnosticLine(`selected(${reason}): ${this.describeCameraDevice('camera', 0, cameraDevice)}`)
    // hilog 单独记录最终选择的 CameraDevice，便于确认是否真的使用 AI Glasses。
    console.info(`${AI_GLASS_LOG_PREFIX} selected reason=${reason}, ${this.describeCameraDevice('camera', 0, cameraDevice)}`)
  }

  private registerCameraStatusLogger(cameraManager: camera.CameraManager): void {
    try {
      // 监听系统 cameraStatus 事件，确认打开/关闭的 cameraId 是否和 AI Glasses remote camera 一致。
      cameraManager.on('cameraStatus', (error: BusinessError, statusInfo: camera.CameraStatusInfo) => {
        // 如果 CameraKit 回调带错误，优先打印错误码和错误消息。
        if (error) {
          // 记录 cameraStatus 回调错误。
          console.error(`${AI_GLASS_LOG_PREFIX} cameraStatus callback error code=${error.code}, message=${error.message}`)
          // 错误回调没有可靠 statusInfo 时直接返回。
          return
        }
        // statusInfo 为空时记录空返回，避免误判为没有回调。
        if (!statusInfo) {
          // 记录 cameraStatus 空返回。
          console.info(`${AI_GLASS_LOG_PREFIX} cameraStatus callback empty statusInfo`)
          // 结束本次回调处理。
          return
        }
        // 打印 CameraStatusInfo 中的 camera 和 status。
        console.info(
          `${AI_GLASS_LOG_PREFIX} cameraStatus status=${Number(statusInfo.status)}, ` +
            `${this.describeCameraDevice('status.camera', 0, statusInfo.camera)}`
        )
      })
      // 记录 cameraStatus 监听注册成功。
      console.info(`${AI_GLASS_LOG_PREFIX} cameraStatus logger registered`)
    } catch (error) {
      // 注册失败时也要打印，避免以为没有系统回调。
      console.warn(`${AI_GLASS_LOG_PREFIX} cameraStatus logger register failed: ${String(error)}`)
    }
  }

  private registerCameraInputLoggers(cameraInput: camera.CameraInput, cameraDevice: camera.CameraDevice): void {
    try {
      // 监听 CameraInput error，捕捉 CameraKit 能回传到应用层的设备错误。
      cameraInput.on('error', cameraDevice, (error: BusinessError) => {
        // 打印错误码、错误消息和 cameraId。
        console.error(
          `${AI_GLASS_LOG_PREFIX} cameraInput error code=${error.code}, message=${error.message}, ` +
            `${this.describeCameraDevice('input.camera', 0, cameraDevice)}`
        )
      })
      // 记录 CameraInput error 监听注册成功。
      console.info(`${AI_GLASS_LOG_PREFIX} cameraInput error logger registered`)
    } catch (error) {
      // 注册失败时记录原因。
      console.warn(`${AI_GLASS_LOG_PREFIX} cameraInput error logger register failed: ${String(error)}`)
    }

    try {
      // 监听 CameraKit API 23 提供的遮挡检测结果。
      cameraInput.on(
        'cameraOcclusionDetection',
        (error: BusinessError, result: camera.CameraOcclusionDetectionResult) => {
          // 如果回调带错误，打印错误码和消息。
          if (error) {
            // 记录遮挡检测回调错误。
            console.error(
              `${AI_GLASS_LOG_PREFIX} cameraOcclusionDetection error code=${error.code}, message=${error.message}`
            )
            // 错误时不读取 result。
            return
          }
          // result 为空时记录空返回。
          if (!result) {
            // 记录空遮挡检测返回。
            console.info(`${AI_GLASS_LOG_PREFIX} cameraOcclusionDetection empty result`)
            // 结束本次回调处理。
            return
          }
          // 打印遮挡检测的两个公开字段：是否遮挡、镜头是否脏污。
          console.info(
            `${AI_GLASS_LOG_PREFIX} cameraOcclusionDetection ` +
              `isCameraOccluded=${String(result.isCameraOccluded)}, ` +
              `isCameraLensDirty=${String(result.isCameraLensDirty)}`
          )
        }
      )
      // 记录遮挡检测监听注册成功。
      console.info(`${AI_GLASS_LOG_PREFIX} cameraOcclusionDetection logger registered`)
    } catch (error) {
      // 部分设备/场景不支持该回调时会到这里。
      console.warn(`${AI_GLASS_LOG_PREFIX} cameraOcclusionDetection logger register failed: ${String(error)}`)
    }
  }

  private logCameraDeviceList(stage: string, cameraDevices: camera.CameraDevice[]): void {
    // 打印列表长度。
    console.info(`${AI_GLASS_LOG_PREFIX} ${stage} count=${cameraDevices.length}`)
    // 遍历并打印每个 CameraDevice 的关键字段。
    for (let i = 0; i < cameraDevices.length; i++) {
      // 输出 cameraId、connectionType、cameraType、position、hostDeviceName、hostDeviceType。
      console.info(`${AI_GLASS_LOG_PREFIX} ${stage}[${i}] ${this.describeCameraDevice('camera', i, cameraDevices[i])}`)
    }
  }

  /**
   * 枚举 CameraKit 支持的 position/type 组合下的 remote camera 返回值。
   * 这个方法只打诊断日志，不改变实际选中的 CameraDevice；目的是验证 AI Glasses 是否还有
   * 非 BACK/WIDE_ANGLE 的 remote camera 暴露形态。
   */
  private logRemoteCameraQueryMatrix(cameraManager: camera.CameraManager): void {
    const positions: CameraPositionQueryCase[] = [
      { name: 'UNSPECIFIED', value: camera.CameraPosition.CAMERA_POSITION_UNSPECIFIED },
      { name: 'BACK', value: camera.CameraPosition.CAMERA_POSITION_BACK },
      { name: 'FRONT', value: camera.CameraPosition.CAMERA_POSITION_FRONT },
      { name: 'FOLD_INNER', value: camera.CameraPosition.CAMERA_POSITION_FOLD_INNER }
    ]
    const allTypes: camera.CameraType[] = [
      camera.CameraType.CAMERA_TYPE_DEFAULT,
      camera.CameraType.CAMERA_TYPE_WIDE_ANGLE,
      camera.CameraType.CAMERA_TYPE_ULTRA_WIDE,
      camera.CameraType.CAMERA_TYPE_TELEPHOTO,
      camera.CameraType.CAMERA_TYPE_TRUE_DEPTH
    ]
    const typeCases: CameraTypeQueryCase[] = [
      { name: 'DEFAULT', values: [camera.CameraType.CAMERA_TYPE_DEFAULT] },
      { name: 'WIDE_ANGLE', values: [camera.CameraType.CAMERA_TYPE_WIDE_ANGLE] },
      { name: 'ULTRA_WIDE', values: [camera.CameraType.CAMERA_TYPE_ULTRA_WIDE] },
      { name: 'TELEPHOTO', values: [camera.CameraType.CAMERA_TYPE_TELEPHOTO] },
      { name: 'TRUE_DEPTH', values: [camera.CameraType.CAMERA_TYPE_TRUE_DEPTH] },
      { name: 'ALL_TYPES', values: allTypes }
    ]

    console.info(`${AI_GLASS_LOG_PREFIX} matrix begin positions=${positions.length}, typeCases=${typeCases.length}`)
    for (let positionIndex = 0; positionIndex < positions.length; positionIndex++) {
      const positionCase = positions[positionIndex]
      for (let typeIndex = 0; typeIndex < typeCases.length; typeIndex++) {
        const typeCase = typeCases[typeIndex]
        try {
          const cameras = cameraManager.getCameraDevices(
            positionCase.value,
            typeCase.values,
            camera.ConnectionType.CAMERA_CONNECTION_REMOTE
          )
          console.info(
            `${AI_GLASS_LOG_PREFIX} matrix position=${positionCase.name}, type=${typeCase.name}, ` +
              `count=${cameras.length}`
          )
          this.logCameraDeviceList(`matrix.${positionCase.name}.${typeCase.name}`, cameras)
        } catch (error) {
          console.warn(
            `${AI_GLASS_LOG_PREFIX} matrix position=${positionCase.name}, type=${typeCase.name}, ` +
              `error=${String(error)}`
          )
        }
      }
    }
    console.info(`${AI_GLASS_LOG_PREFIX} matrix end`)
  }

  private describeCameraDevice(prefix: string, index: number, cameraDevice: camera.CameraDevice): string {
    // prefix 表示当前设备来自 all 列表、remote 列表还是最终 camera 选择。
    return `${prefix}[${index}] id=${cameraDevice.cameraId}, conn=${Number(cameraDevice.connectionType)}, ` +
      // connectionType/type/position 都转成数字，方便和 CameraService hidumper 日志核对。
      `type=${Number(cameraDevice.cameraType)}, pos=${Number(cameraDevice.cameraPosition)}, ` +
      // hostDeviceName/hostDeviceType 是判断 AI Glasses remote camera 的关键反参。
      `host=${cameraDevice.hostDeviceName}, hostType=${Number(cameraDevice.hostDeviceType)}`
  }

  private isStrictRemoteCamera(cameraDevice: camera.CameraDevice): boolean {
    // 优先用 CameraKit 枚举比较，确认该设备是 remote camera。
    return cameraDevice.connectionType === camera.ConnectionType.CAMERA_CONNECTION_REMOTE ||
      // 数值兜底用于处理真机枚举对象和文档枚举对象比较不稳定的情况。
      Number(cameraDevice.connectionType) === REMOTE_CAMERA_CONNECTION_TYPE
  }

  private resolvePreviewProfile(
    cameraManager: camera.CameraManager,
    cameraDevice: camera.CameraDevice,
    sceneMode: camera.SceneMode
  ): camera.Profile {
    // 查询当前 AI Glasses remote CameraDevice 支持的场景模式。
    const supportedModes = cameraManager.getSupportedSceneModes(cameraDevice)
    // 输出场景模式日志；真机上当前看到 1,2，即 NORMAL_PHOTO 和 NORMAL_VIDEO。
    console.info('[GlassesPreviewUtil] remote camera supported scene modes:', supportedModes.join(','))
    // 优先按 NORMAL_VIDEO 场景查询输出能力，目的是拿到视频预览 profile。
    let outputCapability = cameraManager.getSupportedOutputCapability(cameraDevice, sceneMode)
    // 如果指定场景没有 previewProfiles，则退回到不指定场景的能力查询。
    if (outputCapability.previewProfiles.length === 0) {
      // 兜底查询当前 CameraDevice 的通用输出能力。
      outputCapability = cameraManager.getSupportedOutputCapability(cameraDevice)
    }

    // 如果仍然没有预览 profile，说明该 remote camera 当前不能创建预览输出。
    if (outputCapability.previewProfiles.length === 0) {
      // 抛出异常，外层 startPreview 会停止并释放资源。
      throw new Error('眼镜摄像头没有可用 preview profile')
    }

    // 默认选第一个 preview profile。
    let selected = outputCapability.previewProfiles[0]
    // 计算默认 profile 距离目标 1280x720 的差值。
    let selectedDistance = this.profileDistance(selected, 1280, 720)
    // 从第二个 profile 开始遍历所有候选。
    for (let i = 1; i < outputCapability.previewProfiles.length; i++) {
      // 当前遍历到的候选 profile。
      const profile = outputCapability.previewProfiles[i]
      // 计算当前候选距离 1280x720 的差值。
      const distance = this.profileDistance(profile, 1280, 720)
      // 如果当前候选更接近 1280x720，则替换为当前候选。
      if (distance < selectedDistance) {
        // 记录新的最佳 profile。
        selected = profile
        // 记录新的最佳差值。
        selectedDistance = distance
      }
    }
    // 输出最终选中的预览分辨率。
    console.info('[GlassesPreviewUtil] selected preview profile:', selected.size.width, selected.size.height)
    // 页面诊断记录 supported scene modes。
    this.appendDiagnosticLine(`getSupportedSceneModes(): ${supportedModes.join(',')}`)
    // 页面诊断记录最终选中的 preview profile。
    this.appendDiagnosticLine(`selected preview profile: ${selected.size.width}x${selected.size.height}`)
    // 返回最终 profile，供 createPreviewOutput 使用。
    return selected
  }

  private profileDistance(profile: camera.Profile, targetWidth: number, targetHeight: number): number {
    // 用宽高差的曼哈顿距离衡量 profile 是否接近目标分辨率。
    return Math.abs(profile.size.width - targetWidth) + Math.abs(profile.size.height - targetHeight)
  }

  private appendDiagnosticLine(line: string): void {
    // 如果当前还没有诊断文本，则直接写入第一行。
    if (this.diagnosticText.length === 0) {
      // 记录第一行诊断文本。
      this.diagnosticText = line
      // 结束本次追加。
      return
    }
    // 如果已有诊断文本，则换行追加，页面会展示完整调用链。
    this.diagnosticText = `${this.diagnosticText}\n${line}`
  }

  private maskDeviceId(deviceId: string): string {
    // cameraId 较短时不脱敏，便于开发期直接查看。
    if (deviceId.length <= 18) {
      // 返回原始短 id。
      return deviceId
    }
    // 长 cameraId 只保留头尾，避免页面诊断过长挤压 UI。
    return `${deviceId.slice(0, 8)}...${deviceId.slice(deviceId.length - 10)}`
  }
}

// 导出单例，Index1 页面统一通过这个实例启动或停止眼镜预览。
const glassesPreviewUtil = new GlassesPreviewUtil()

// 默认导出给 entry 页面使用；LiveKit SDK 模块不依赖这个实验工具。
export default glassesPreviewUtil
