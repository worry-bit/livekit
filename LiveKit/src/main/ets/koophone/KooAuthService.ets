import { http } from '@kit.NetworkKit'
import {
  IamPasswordConfig,
  KooAuthConfig,
  KooAuthTokenResult,
  LivePlatformConfig
} from './KooPhoneTypes'

const DEFAULT_CONNECT_TIMEOUT_MS = 5000
const DEFAULT_READ_TIMEOUT_MS = 10000

interface IamDomain {
  name: string
}

interface IamUser {
  domain: IamDomain
  name: string
  password: string
}

interface IamPassword {
  user: IamUser
}

interface IamIdentity {
  methods: string[]
  password: IamPassword
}

interface IamProjectScope {
  name: string
}

interface IamScope {
  project?: IamProjectScope
  domain?: IamDomain
}

interface IamAuth {
  identity: IamIdentity
  scope: IamScope
}

interface IamTokenRequest {
  auth: IamAuth
}

interface KooAuthRequest {
  iamToken: string
  boxId: string
  tenantId?: string
  projectId?: string
}

interface KooAuthResponse {
  token?: string
  expiresAt?: string
}

/**
 * 负责串流前的两段式鉴权：
 * 1. 调 IAM /v3/auth/tokens 获取租户 IAM token；
 * 2. 用 IAM token 调预留 KooPhone auth 接口，换取约 15 秒有效的 SDK token。
 */
export class KooAuthService {
  /**
   * 获取 KooPhone SDK 短效 token。signalingUrl/boxId 保持平台固定配置，
   * 返回 token 只在当前 open 尝试中使用，重试时会重新获取。
   */
  async requestSdkToken(config: LivePlatformConfig): Promise<KooAuthTokenResult> {
    const iamToken = await this.requestIamToken(config.iam)
    return this.requestKooPhoneAuth(config.kooAuth, config.boxId, iamToken)
  }

  /**
   * 调用华为云 IAM 用户密码认证接口。
   * 官方接口将 token 放在响应头 X-Subject-Token 中。
   */
  private async requestIamToken(config: IamPasswordConfig): Promise<string> {
    this.assertIamConfig(config)

    const req = http.createHttp()
    try {
      const body = this.buildIamTokenRequest(config)
      const res = await this.safeRequest(req, `${config.authUrl}?nocatalog=true`, {
        method: http.RequestMethod.POST,
        header: { 'Content-Type': 'application/json;charset=utf8' },
        extraData: JSON.stringify(body),
        connectTimeout: DEFAULT_CONNECT_TIMEOUT_MS,
        readTimeout: DEFAULT_READ_TIMEOUT_MS
      }, 'IAM token network request failed')

      const statusCode = res.responseCode
      if (statusCode < 200 || statusCode >= 300) {
        throw new Error(`IAM token request failed: ${statusCode}`)
      }

      const token = this.findHeaderValue(JSON.stringify(res.header), 'X-Subject-Token')
      if (token.length === 0) {
        throw new Error('IAM response missing X-Subject-Token')
      }
      return token
    } finally {
      req.destroy()
    }
  }

  /**
   * 调用 KooPhone auth 预留接口。当前官网接口已下线，先固定约定：
   * 响应 body 为 JSON，SDK token 位于 body.token。
   */
  private async requestKooPhoneAuth(config: KooAuthConfig, boxId: string, iamToken: string): Promise<KooAuthTokenResult> {
    this.assertKooAuthConfig(config)

    const req = http.createHttp()
    try {
      const body: KooAuthRequest = {
        iamToken,
        boxId,
        tenantId: config.tenantId,
        projectId: config.projectId
      }
      const res = await this.safeRequest(req, config.authUrl, {
        method: http.RequestMethod.POST,
        header: {
          'Content-Type': 'application/json;charset=utf8',
          'X-Auth-Token': iamToken
        },
        extraData: JSON.stringify(body),
        connectTimeout: DEFAULT_CONNECT_TIMEOUT_MS,
        readTimeout: DEFAULT_READ_TIMEOUT_MS
      }, 'KooPhone auth network request failed')

      const statusCode = res.responseCode
      if (statusCode < 200 || statusCode >= 300) {
        throw new Error(`KooPhone auth request failed: ${statusCode}`)
      }

      const raw = `${res.result}`
      const auth = JSON.parse(raw) as KooAuthResponse
      const token = auth.token ?? ''
      if (token.length === 0) {
        throw new Error('KooPhone auth response missing body.token')
      }

      return {
        token,
        expiresAt: auth.expiresAt
      }
    } finally {
      req.destroy()
    }
  }

  private buildIamTokenRequest(config: IamPasswordConfig): IamTokenRequest {
    const scope: IamScope = config.projectName ?
      { project: { name: config.projectName } } :
      { domain: { name: config.domainName } }

    return {
      auth: {
        identity: {
          methods: ['password'],
          password: {
            user: {
              domain: { name: config.domainName },
              name: config.userName,
              password: config.password
            }
          }
        },
        scope
      }
    }
  }

  private assertIamConfig(config: IamPasswordConfig): void {
    if (!config.authUrl || !config.domainName || !config.userName || !config.password) {
      throw new Error('IAM config is incomplete')
    }
  }

  private assertKooAuthConfig(config: KooAuthConfig): void {
    if (!config.authUrl) {
      throw new Error('KooPhone auth config is incomplete')
    }
  }

  /**
   * NetworkKit 的 request 会抛网络异常。统一转换后，页面状态浮层和重试日志
   * 能显示稳定的业务错误文本，而不是底层异常对象。
   */
  private async safeRequest(
    req: http.HttpRequest,
    url: string,
    options: http.HttpRequestOptions,
    errorPrefix: string
  ): Promise<http.HttpResponse> {
    try {
      return await req.request(url, options)
    } catch (e) {
      throw new Error(`${errorPrefix}: ${String(e)}`)
    }
  }

  private findHeaderValue(headerText: string, name: string): string {
    const normalized = headerText.toLowerCase()
    const nameIndex = normalized.indexOf(`"${name.toLowerCase()}"`)
    if (nameIndex < 0) {
      return ''
    }

    const colonIndex = normalized.indexOf(':', nameIndex)
    if (colonIndex < 0) {
      return ''
    }

    const startQuoteIndex = headerText.indexOf('"', colonIndex + 1)
    if (startQuoteIndex < 0) {
      return ''
    }

    const endQuoteIndex = headerText.indexOf('"', startQuoteIndex + 1)
    if (endQuoteIndex < 0) {
      return ''
    }

    return headerText.substring(startQuoteIndex + 1, endQuoteIndex)
  }
}

export function createKooAuthService(): KooAuthService {
  return new KooAuthService()
}
