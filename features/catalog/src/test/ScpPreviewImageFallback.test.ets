import { describe, expect, it, xit } from '@ohos/hypium';
import { url } from '@kit.ArkTS';
import { CachedArticleRepo } from '../main/ets/data/CachedArticleRepo';
import { ScpImageCacheService } from '../main/ets/data/ScpImageCacheService';
import { ScpPageCacheService } from '../main/ets/data/ScpPageCacheService';
import { ScpPageFetchService } from '../main/ets/data/ScpPageFetchService';
import { ScpPreviewService } from '../main/ets/data/ScpPreviewService';
import { ScpRequestScheduler } from '../main/ets/data/ScpRequestScheduler';

const FETCHED_AT: number = 1788000000000;

function supportsUrlParser(): boolean {
  try {
    url.URL.parseURL('https://example.com/image.jpg');
    return true;
  } catch (_error) {
    return false;
  }
}

/** Forces the same transient image failure seen in the device hilog. */
class FailingImageCache extends ScpImageCacheService {
  readonly requestedUrls: string[] = [];

  async load(sourceUrl: string): Promise<string> {
    this.requestedUrls.push(sourceUrl);
    return Promise.reject(new Error('图片请求失败：HTTP 500'));
  }
}

function createRepository(): CachedArticleRepo {
  const scheduler = new ScpRequestScheduler();
  return new CachedArticleRepo(
    new ScpPageFetchService(scheduler),
    new ScpPageCacheService(),
    scheduler
  );
}

export default function scpPreviewImageFallbackTest(): void {
  describe('ScpPreviewImageFallback', () => {
    const fallbackTest = async (): Promise<void> => {
      const imageCache = new FailingImageCache();
      const service = new ScpPreviewService(createRepository(), imageCache);
      const html = '<html><body><div id="page-content">' +
        '<p>描述：这是一段足够长的正文描述，用于验证失败回退仍保留卡片文案。</p>' +
        '<img src="http://scp-wiki.wikidot.com/local--files/scp-5793/store.jpg" />' +
        '</div></body></html>';

      const preview = await service.resolveFetchedHtml('SCP-5793', html, FETCHED_AT);

      expect(imageCache.requestedUrls.length).assertEqual(1);
      expect(imageCache.requestedUrls[0]).assertEqual(
        'https://scp-wiki.wikidot.com/local--files/scp-5793/store.jpg'
      );
      expect(preview.path).assertEqual('');
      expect(preview.url).assertEqual(
        'https://scp-wiki.wikidot.com/local--files/scp-5793/store.jpg'
      );
      expect(preview.aspect).assertEqual(1);
      expect(preview.description.length > 0).assertTrue();
      expect(preview.fetchedAt).assertEqual(FETCHED_AT);
      expect(preview.stale).assertFalse();
    };
    if (supportsUrlParser()) {
      it('keeps the remote image URL when local download fails', 0, fallbackTest);
    } else {
      xit('keeps the remote image URL when local download fails', 0, (): void => {});
    }
  });
}
