import { CACHE_FRESH_DURATION_MS } from 'anomiconbasic';

/**
 * SCP 主站派生缓存的统一新鲜度策略。
 *
 * 原始 HTML、解析文档、系列目录与卡片预览共享同一窗口，避免某一层
 * 已过期而另一层仍被永久命中。过期数据仍可用于 stale-while-revalidate。
 */
export class ScpCachePolicy {
  static readonly FRESH_DURATION_MS: number = CACHE_FRESH_DURATION_MS;

  static isFresh(timestamp: number, now: number = Date.now()): boolean {
    return timestamp > 0 && now >= timestamp &&
      now - timestamp < ScpCachePolicy.FRESH_DURATION_MS;
  }

  private constructor() {
  }
}
