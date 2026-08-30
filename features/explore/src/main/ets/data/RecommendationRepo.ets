import {
  ExplorePreview,
  ExploreRecommendation,
  ExploreRecommendationEntry
} from '../domain/ExploreContracts';
import { RecommendationRepository } from '../domain/ExploreRepositories';
import { RecommendationService } from './RecommendationService';

/** Adapts recommendation data objects to the Explore domain model. */
export class RecommendationRepo implements RecommendationRepository {
  private readonly service: RecommendationService;

  constructor(service: RecommendationService) {
    this.service = service;
  }

  async loadDaily(batchIndex: number, dayKey?: string): Promise<ExploreRecommendation[]> {
    const currentRecommendations = dayKey === undefined ?
      await this.service.loadDaily(batchIndex) :
      await this.service.loadDaily(batchIndex, dayKey);
    const recommendations: ExploreRecommendation[] = [];
    for (let index = 0; index < currentRecommendations.length; index++) {
      const item = currentRecommendations[index];
      const preview = item.preview;
      recommendations.push(new ExploreRecommendation(
        new ExploreRecommendationEntry(item.entry.itemId, item.entry.title),
        new ExplorePreview(preview.path, preview.aspect, preview.description, preview.url,
          preview.fetchedAt, preview.stale, preview.error)
      ));
    }
    return recommendations;
  }
}
