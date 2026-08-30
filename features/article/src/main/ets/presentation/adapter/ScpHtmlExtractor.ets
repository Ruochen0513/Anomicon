import { webview } from '@kit.ArkWeb';
import { util } from '@kit.ArkTS';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN = 0x0000;
const TAG = 'AnomiconExtractor';
const EXTRACTION_SCRIPT_FILE: string = 'dom_extract.js';
const LIFECYCLE_TIMEOUT_MS: number = 15000;

/**
 * 离屏 DOM 提取器：把缓存的原始 HTML 交给 ArkWeb 渲染一次，
 * 运行 dom_extract.js，产出结构化文章 JSON。目录与故事索引已经改为
 * ArkTS + TaskPool 原生解析，本组件只保留正文 DOM 映射所需的最小能力。
 */
@ComponentV2
export struct ScpHtmlExtractor {
  @Require @Param html: string;
  @Require @Param baseUrl: string;
  /**
   * 宿主生成的不可变请求代次。提取器把 appear 时捕获的值原样带回，
   * 避免组件参数已切到下一篇后，旧 ArkWeb 回调污染新状态。
   */
  @Param requestId: number = 0;
  @Event onExtracted: (json: string, requestId: number) => void;
  @Event onFailed: (message: string, requestId: number) => void;

  private controller: webview.WebviewController = new webview.WebviewController();
  private started: boolean = false;
  private finished: boolean = false;
  private completed: boolean = false;
  private script: string = '';
  private lifecycleWatchdog: number = -1;
  private destroyed: boolean = false;
  private capturedRequestId: number = 0;
  /** 组件每次出现/消失都会推进代次，隔离上一生命周期迟到的 Promise 与定时器。 */
  private lifecycleEpoch: number = 0;

  aboutToAppear(): void {
    const epoch = ++this.lifecycleEpoch;
    this.destroyed = false;
    this.completed = false;
    this.started = false;
    this.finished = false;
    this.capturedRequestId = this.requestId;
    this.armLifecycleWatchdog(epoch);
    try {
      const hostContext = this.getUIContext().getHostContext();
      if (hostContext === undefined) {
        throw new Error('当前组件没有可用的 Ability Context');
      }
      const bytes = hostContext.resourceManager.getRawFileContentSync(EXTRACTION_SCRIPT_FILE);
      this.script = util.TextDecoder.create('utf-8').decodeToString(bytes);
      hilog.info(DOMAIN, TAG, 'extract script loaded, %{public}d chars', this.script.length);
    } catch (error) {
      const message = error instanceof Error ? error.message : 'unknown error';
      hilog.error(DOMAIN, TAG, 'read extract script failed: %{public}s', message);
      this.completeWithFailure(`读取提取脚本失败：${message}`, epoch);
    }
  }

  aboutToDisappear(): void {
    this.lifecycleEpoch++;
    this.destroyed = true;
    this.clearLifecycleWatchdog();
    try {
      this.controller.stop();
    } catch (error) {
      // 控制器尚未挂载或已经销毁时无需额外处理。
    }
  }

  private armLifecycleWatchdog(epoch: number): void {
    this.clearLifecycleWatchdog();
    this.lifecycleWatchdog = setTimeout(() => {
      this.completeWithFailure('DOM 提取超时，请重试', epoch);
    }, LIFECYCLE_TIMEOUT_MS);
  }

  private clearLifecycleWatchdog(): void {
    if (this.lifecycleWatchdog >= 0) {
      clearTimeout(this.lifecycleWatchdog);
      this.lifecycleWatchdog = -1;
    }
  }

  private isActiveEpoch(epoch: number): boolean {
    return epoch === this.lifecycleEpoch && !this.destroyed && !this.completed;
  }

  private completeWithResult(json: string, epoch: number): void {
    if (!this.isActiveEpoch(epoch)) {
      return;
    }
    this.completed = true;
    this.clearLifecycleWatchdog();
    this.onExtracted(json, this.capturedRequestId);
  }

  private completeWithFailure(message: string, epoch: number): void {
    if (!this.isActiveEpoch(epoch)) {
      return;
    }
    this.completed = true;
    this.clearLifecycleWatchdog();
    this.onFailed(message, this.capturedRequestId);
  }

  private startExtraction(): void {
    if (this.started || this.completed || this.script.length === 0) {
      return;
    }
    this.started = true;
    const epoch = this.lifecycleEpoch;
    // baseUrl 指向 wiki 域名，使相对路径可解析。
    const content = this.sanitizeHtml(this.html);
    try {
      this.controller.loadData(content, 'text/html', 'UTF-8', this.baseUrl, this.baseUrl);
    } catch (error) {
      const message = error instanceof Error ? error.message : 'unknown error';
      hilog.error(DOMAIN, TAG, 'load extraction document failed: %{public}s', message);
      this.completeWithFailure(`载入待解析文档失败：${message}`, epoch);
    }
  }

  private runExtraction(): void {
    if (this.finished || this.completed) {
      return;
    }
    this.finished = true;
    const epoch = this.lifecycleEpoch;
    this.runOnce(epoch);
  }

  private runOnce(epoch: number): void {
    try {
      this.controller.runJavaScript(`(${this.script})()`)
        .then((result: string) => {
          if (!this.isActiveEpoch(epoch)) {
            return;
          }
          if (typeof result !== 'string') {
            this.completeWithFailure('DOM 提取结果格式错误', epoch);
            return;
          }
          hilog.info(DOMAIN, TAG, 'extraction result %{public}d chars', result.length);
          this.completeWithResult(result, epoch);
        })
        .catch((error: BusinessError) => this.failExtraction(error, epoch));
    } catch (error) {
      // Some WebView states reject synchronously (for example after a detach).
      // Convert that path to the same one-shot failure notification instead of
      // waiting for the watchdog while the page remains in `parsing`.
      const message = error instanceof Error ? error.message : 'unknown error';
      hilog.error(DOMAIN, TAG, 'runJavaScript threw: %{public}s', message);
      this.completeWithFailure(`DOM 提取执行失败：${message}`, epoch);
    }
  }

  private failExtraction(error: BusinessError, epoch: number): void {
    if (!this.isActiveEpoch(epoch)) {
      return;
    }
    hilog.error(DOMAIN, TAG, 'runJavaScript failed: %{public}d %{public}s', error.code, error.message);
    this.completeWithFailure(`DOM 提取执行失败：${error.message}（错误码 ${error.code}）`, epoch);
  }

  /**
   * `loadData` receives the source URL as its base URL so relative links keep
   * their original meaning.  ArkWeb therefore reports that HTTPS URL as the
   * main-frame request even though no network fetch is needed.  Only that
   * document request may pass the intercept gate; subframes/resources remain
   * blocked below.
   */
  private isMainDocumentUrl(value: string): boolean {
    const candidate = value.trim();
    if (candidate.startsWith('data:')) {
      return true;
    }
    const base = this.baseUrl.trim();
    if (base.length === 0) {
      return candidate.startsWith('about:');
    }
    return candidate === base || candidate === `${base}/`;
  }

  /** 剥离远端脚本、样式和外链；正文映射只需要服务端 HTML 的 DOM。 */
  private sanitizeHtml(html: string): string {
    return html
      .replace(/<script\b[\s\S]*?<\/script>/gi, '')
      .replace(/<style\b[\s\S]*?<\/style>/gi, '')
      .replace(/<noscript\b[\s\S]*?<\/noscript>/gi, '')
      .replace(/<link\b[^>]*>/gi, '');
  }

  build() {
    Web({ src: '', controller: this.controller })
      .width(1)
      .height(1)
      .opacity(0)
      .javaScriptAccess(true)
      .imageAccess(false)
      .onlineImageAccess(false)
      .fileAccess(false)
      .domStorageAccess(false)
      .databaseAccess(false)
      .geolocationAccess(false)
      .onControllerAttached(() => this.startExtraction())
      .onLoadIntercept((event) => {
        const url = event.data.getRequestUrl();
        // `isMainFrame()` is the authoritative distinction here.  With an
        // HTTPS loadData base URL the main document itself is HTTPS, while a
        // same-origin image/style request may share its prefix and must still
        // be blocked.
        if (event.data.isMainFrame()) {
          return !this.isMainDocumentUrl(url);
        }
        return !(url.startsWith('data:') || url.startsWith('about:'));
      })
      .onPageEnd((event: OnPageEndEvent) => {
        // Ignore the initial about:blank page emitted before loadData.  The
        // loaded document is either a data URL or the explicit base URL.
        if (this.isMainDocumentUrl(event.url)) {
          this.runExtraction();
        }
      })
  }
}
