import { describe, expect, it } from '@ohos/hypium';
import { RecommendationService } from '../main/ets/data/RecommendationService';
import { ExplorePreview } from '../main/ets/domain/ExploreContracts';
import {
  ExploreFetchedPage,
  ExploreRecommendationPageGateway,
  PreviewRepository
} from '../main/ets/domain/ExploreRepositories';

class MissingPageGateway implements ExploreRecommendationPageGateway {
  readonly urls: string[] = [];

  fetchPage(sourceUrl: string): Promise<ExploreFetchedPage> {
    this.urls.push(sourceUrl);
    return Promise.resolve(new ExploreFetchedPage('This page does not exist yet', 1));
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

export default function exploreRecommendationServiceTest(): void {
  describe('RecommendationService', () => {
    it('pads one and two digit candidate ids without changing larger ids', 0, async () => {
      const gateway = new MissingPageGateway();
      const service = new RecommendationService(gateway, new EmptyPreviewRepository());

      const recommendations = await service.loadDaily(18, '2020-01-03');

      expect(recommendations.length).assertEqual(0);
      expect(gateway.urls.length).assertEqual(24);
      expect(gateway.urls.indexOf('https://scp-wiki-cn.wikidot.com/scp-007') >= 0).assertTrue();
      expect(gateway.urls.indexOf('https://scp-wiki-cn.wikidot.com/scp-062') >= 0).assertTrue();
      expect(gateway.urls.indexOf('https://scp-wiki-cn.wikidot.com/scp-117') >= 0).assertTrue();
      expect(gateway.urls.indexOf('https://scp-wiki-cn.wikidot.com/scp-2713') >= 0).assertTrue();
    });
  });
}
