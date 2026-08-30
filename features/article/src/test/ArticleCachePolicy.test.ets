import { describe, expect, it } from '@ohos/hypium';
import { ArticleCachePolicy } from '../main/ets/domain/ArticleCachePolicy';

export default function articleDocumentCachePolicyTest(): void {
  describe('ArticleCachePolicy', () => {
    it('uses an exclusive six-hour freshness boundary', 0, () => {
      const now = 1_800_000_000_000;
      const duration = ArticleCachePolicy.FRESH_DURATION_MS;

      expect(duration).assertEqual(6 * 60 * 60 * 1000);
      expect(ArticleCachePolicy.isFresh(now, now)).assertTrue();
      expect(ArticleCachePolicy.isFresh(now - duration + 1, now)).assertTrue();
      expect(ArticleCachePolicy.isFresh(now - duration, now)).assertFalse();
      expect(ArticleCachePolicy.isFresh(now - duration - 1, now)).assertFalse();
      expect(ArticleCachePolicy.isFresh(0, now)).assertFalse();
      expect(ArticleCachePolicy.isFresh(now + 1, now)).assertFalse();
    });
  });
}
