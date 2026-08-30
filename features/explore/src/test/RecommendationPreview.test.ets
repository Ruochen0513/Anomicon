import { describe, expect, it } from '@ohos/hypium';
import { RecommendationService } from '../main/ets/data/RecommendationService';
import {
  ExploreFetchedPage,
  ExplorePreview,
  ExploreRecommendationPageGateway,
  PreviewRepository
} from '../main/ets/Index';

const FETCHED_AT: number = 1788000000000;

class ImagePageGateway implements ExploreRecommendationPageGateway {
  readonly urls: string[] = [];

  fetchPage(sourceUrl: string): Promise<ExploreFetchedPage> {
    this.urls.push(sourceUrl);
    const itemId = sourceUrl.substring(sourceUrl.lastIndexOf('/') + 1).toUpperCase();
    const html = '<html><head><title>' + itemId + ' - SCP基金会</title></head>' +
      '<body><div id="page-content"><p>推荐条目正文。</p>' +
      '<img src="https://scp-wiki.wdfiles.com/local--files/' +
      itemId.toLowerCase() + '/cover.jpg" /></div></body></html>';
    return Promise.resolve(new ExploreFetchedPage(html, FETCHED_AT));
  }
}

class RecordingPreviewRepository implements PreviewRepository {
  readonly itemIds: string[] = [];
  readonly htmls: string[] = [];
  readonly fetchedAts: number[] = [];

  getPreview(_itemId: string): Promise<ExplorePreview> {
    return Promise.resolve(new ExplorePreview());
  }

  resolveFetchedHtml(
    itemId: string,
    html: string,
    fetchedAt?: number
  ): Promise<ExplorePreview> {
    this.itemIds.push(itemId);
    this.htmls.push(html);
    this.fetchedAts.push(fetchedAt ?? 0);
    return Promise.resolve(new ExplorePreview(
      '/data/storage/el2/base/cache/scp_images/img_cover.jpg',
      1.5,
      '推荐卡片描述',
      'https://scp-wiki.wdfiles.com/fallback.jpg',
      fetchedAt ?? 0,
      false
    ));
  }
}

class FailingPageGateway implements ExploreRecommendationPageGateway {
  fetchPage(_sourceUrl: string): Promise<ExploreFetchedPage> {
    return Promise.reject(new Error('offline'));
  }
}

export default function recommendationPreviewTest(): void {
  describe('RecommendationPreviewContract', () => {
    it('passes the fetched page and complete preview value to each card', 0, async () => {
      const gateway = new ImagePageGateway();
      const preview = new RecordingPreviewRepository();
      const service = new RecommendationService(gateway, preview);

      const recommendations = await service.loadDaily(0, '2026-08-30');

      expect(recommendations.length).assertEqual(6);
      expect(gateway.urls.length).assertEqual(6);
      expect(preview.itemIds.length).assertEqual(6);
      expect(preview.fetchedAts.length).assertEqual(6);
      expect(preview.fetchedAts[0]).assertEqual(FETCHED_AT);
      expect(preview.htmls[0].indexOf('page-content') >= 0).assertTrue();
      expect(recommendations[0].entry.title).assertEqual(recommendations[0].entry.itemId);
      expect(recommendations[0].preview.path).assertEqual(
        '/data/storage/el2/base/cache/scp_images/img_cover.jpg'
      );
      expect(recommendations[0].preview.url).assertEqual(
        'https://scp-wiki.wdfiles.com/fallback.jpg'
      );
      expect(recommendations[0].preview.aspect).assertEqual(1.5);
      expect(recommendations[0].preview.description).assertEqual('推荐卡片描述');
      expect(recommendations[0].preview.fetchedAt).assertEqual(FETCHED_AT);
    });

    it('returns an empty recommendation set only for genuine missing pages', 0, async () => {
      const service = new RecommendationService(
        new MissingPageGateway(),
        new EmptyPreviewRepository()
      );

      const recommendations = await service.loadDaily(4, '2026-08-30');

      expect(recommendations.length).assertEqual(0);
    });

    it('surfaces transport failures instead of publishing an empty ready batch', 0, async () => {
      const service = new RecommendationService(
        new FailingPageGateway(),
        new EmptyPreviewRepository()
      );
      let message: string = '';

      try {
        await service.loadDaily(0, '2026-08-30');
      } catch (error) {
        message = error instanceof Error ? error.message : '';
      }

      expect(message).assertEqual('今日推荐部分请求失败');
    });
  });
}

class MissingPageGateway implements ExploreRecommendationPageGateway {
  fetchPage(_sourceUrl: string): Promise<ExploreFetchedPage> {
    return Promise.resolve(new ExploreFetchedPage(
      '<html><body>This page does not exist yet</body></html>',
      FETCHED_AT
    ));
  }
}

class EmptyPreviewRepository implements PreviewRepository {
  getPreview(_itemId: string): Promise<ExplorePreview> {
    return Promise.resolve(new ExplorePreview());
  }

  resolveFetchedHtml(
    _itemId: string,
    _html: string,
    _fetchedAt?: number
  ): Promise<ExplorePreview> {
    return Promise.resolve(new ExplorePreview());
  }
}
