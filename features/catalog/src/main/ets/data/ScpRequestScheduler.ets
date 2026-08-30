import { ScpHtmlRequestPriority } from '../domain/ArticleHtmlRepository';

const MAX_CONCURRENT_PAGE_REQUESTS: number = 2;
/** 预取/后台工作最多使用一个槽，为正文和可见卡片保留一个槽。 */
const MAX_LOW_PRIORITY_REQUESTS: number = 1;

class ScpScheduledRequest {
  readonly key: string;
  priority: ScpHtmlRequestPriority;
  readonly sequence: number;
  readonly resolve: (priority: ScpHtmlRequestPriority) => void;

  constructor(
    key: string,
    priority: ScpHtmlRequestPriority,
    sequence: number,
    resolve: (priority: ScpHtmlRequestPriority) => void
  ) {
    this.key = key;
    this.priority = priority;
    this.sequence = sequence;
    this.resolve = resolve;
  }
}

/**
 * 中文主站页面请求的应用级优先级闸门。
 *
 * 正文/可见卡片可使用两个并发槽；预取和后台刷新最多占一个槽。等待任务按
 * 「优先级 → 入队顺序」选择，且同一 URL 的排队任务可以在用户真正打开时晋升。
 */
export class ScpRequestScheduler {
  private activeRequests: number = 0;
  private activeLowPriorityRequests: number = 0;
  private nextSequence: number = 0;
  private readonly waiting: ScpScheduledRequest[] = [];

  async run<T>(
    task: () => Promise<T>,
    priority: ScpHtmlRequestPriority = ScpHtmlRequestPriority.USER_INITIATED,
    key: string = ''
  ): Promise<T> {
    const grantedPriority = await this.acquire(key, priority);
    try {
      return await task();
    } finally {
      this.release(grantedPriority);
    }
  }

  /** 已排队的预取在变为可见/正文请求时原地晋升，不创建第二个网络任务。 */
  promote(key: string, priority: ScpHtmlRequestPriority): void {
    if (key.length === 0) {
      return;
    }
    let changed: boolean = false;
    for (let index: number = 0; index < this.waiting.length; index++) {
      const request = this.waiting[index];
      if (request.key === key && priority < request.priority) {
        request.priority = priority;
        changed = true;
      }
    }
    if (changed) {
      this.drain();
    }
  }

  private acquire(
    key: string,
    priority: ScpHtmlRequestPriority
  ): Promise<ScpHtmlRequestPriority> {
    if (this.canStart(priority) && this.waiting.length === 0) {
      this.markStarted(priority);
      return Promise.resolve(priority);
    }
    return new Promise<ScpHtmlRequestPriority>(
      (resolve: (grantedPriority: ScpHtmlRequestPriority) => void): void => {
        this.waiting.push(new ScpScheduledRequest(key, priority, this.nextSequence++, resolve));
        this.drain();
      }
    );
  }

  private release(priority: ScpHtmlRequestPriority): void {
    this.activeRequests = Math.max(0, this.activeRequests - 1);
    if (this.isLowPriority(priority)) {
      this.activeLowPriorityRequests = Math.max(0, this.activeLowPriorityRequests - 1);
    }
    this.drain();
  }

  private drain(): void {
    while (this.activeRequests < MAX_CONCURRENT_PAGE_REQUESTS) {
      const index = this.nextEligibleIndex();
      if (index < 0) {
        return;
      }
      const request = this.waiting.splice(index, 1)[0];
      // 在唤醒 Promise continuation 前原子占用槽位，避免短暂超发。
      this.markStarted(request.priority);
      request.resolve(request.priority);
    }
  }

  private nextEligibleIndex(): number {
    let selectedIndex: number = -1;
    for (let index: number = 0; index < this.waiting.length; index++) {
      const candidate = this.waiting[index];
      if (!this.canStart(candidate.priority)) {
        continue;
      }
      if (selectedIndex < 0) {
        selectedIndex = index;
        continue;
      }
      const selected = this.waiting[selectedIndex];
      if (candidate.priority < selected.priority ||
        (candidate.priority === selected.priority && candidate.sequence < selected.sequence)) {
        selectedIndex = index;
      }
    }
    return selectedIndex;
  }

  private canStart(priority: ScpHtmlRequestPriority): boolean {
    if (this.activeRequests >= MAX_CONCURRENT_PAGE_REQUESTS) {
      return false;
    }
    return !this.isLowPriority(priority) ||
      this.activeLowPriorityRequests < MAX_LOW_PRIORITY_REQUESTS;
  }

  private markStarted(priority: ScpHtmlRequestPriority): void {
    this.activeRequests++;
    if (this.isLowPriority(priority)) {
      this.activeLowPriorityRequests++;
    }
  }

  private isLowPriority(priority: ScpHtmlRequestPriority): boolean {
    return priority >= ScpHtmlRequestPriority.PREFETCH;
  }
}
