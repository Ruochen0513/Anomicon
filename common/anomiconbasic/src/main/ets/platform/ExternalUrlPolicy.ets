import { url } from '@kit.ArkTS';

/**
 * Shared URL safety boundary for article links and media.
 *
 * The policy is intentionally feature-independent: it only normalizes the
 * allowed HTTPS shape and never performs navigation, file I/O, or caching.
 * Product/data adapters decide what to do with the validated URL.
 */
export class ExternalUrlPolicy {
  /** Article images may be HTTP in historical HTML; display them as HTTPS. */
  static resolveImageHttps(
    rawUrl: string,
    baseUrl: string = 'https://scp-wiki-cn.wikidot.com/'
  ): string {
    let candidate = rawUrl.trim();
    if (candidate.length === 0) {
      throw new Error('图片地址为空');
    }
    if (candidate.startsWith('//')) {
      candidate = `https:${candidate}`;
    }
    let parsed: url.URL;
    try {
      parsed = url.URL.parseURL(candidate, baseUrl);
    } catch (_error) {
      throw new Error('图片地址无效');
    }
    if (parsed.protocol.toLowerCase() === 'http:') {
      parsed.protocol = 'https:';
    }
    if (parsed.protocol.toLowerCase() !== 'https:' || parsed.hostname.length === 0) {
      throw new Error('图片地址必须使用 HTTPS');
    }
    if (parsed.username.length > 0 || parsed.password.length > 0 || parsed.port.length > 0) {
      throw new Error('图片地址不能包含凭据或自定义端口');
    }
    parsed.hash = '';
    return parsed.href;
  }

  /** External article links resolve against the supplied base and must end up on HTTPS. */
  static resolveHttps(rawUrl: string, baseUrl: string): string {
    const candidate = rawUrl.trim();
    if (candidate.length === 0) {
      throw new Error('链接地址为空');
    }
    let parsed: url.URL;
    try {
      parsed = url.URL.parseURL(candidate, baseUrl);
    } catch (_error) {
      throw new Error('链接地址无效');
    }
    if (parsed.protocol.toLowerCase() !== 'https:') {
      throw new Error('只允许打开 HTTPS 链接');
    }
    if (parsed.username.length > 0 || parsed.password.length > 0) {
      throw new Error('链接不能包含身份凭据');
    }
    if (parsed.port.length > 0) {
      throw new Error('链接不能使用自定义端口');
    }
    return parsed.href;
  }
}
