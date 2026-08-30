import { CACHE_FRESH_DURATION_MS } from 'anomiconbasic';

/** Six-hour freshness window for derived article documents. */
export class ArticleCachePolicy {
  static readonly FRESH_DURATION_MS: number = CACHE_FRESH_DURATION_MS;

  static isFresh(timestamp: number, now: number = Date.now()): boolean {
    return timestamp > 0 && now >= timestamp &&
      now - timestamp < ArticleCachePolicy.FRESH_DURATION_MS;
  }

  private constructor() {
  }
}
