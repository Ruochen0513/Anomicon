import {
  ArticleHtmlPort,
  ArticleHtmlSnapshot,
  ArticleHtmlSource
} from 'article';
import {
  ArticleHtmlRepository,
  ScpHtmlLoadResult,
  ScpHtmlRequestPriority,
  ScpHtmlSource
} from 'catalog';

/**
 * Explicit product bridge from Catalog's shared HTML pipeline to Article's
 * narrow source receipt. Neither feature imports the other's model layer.
 */
export class CatalogArticleHtmlAdapter implements ArticleHtmlPort {
  private readonly repository: ArticleHtmlRepository;

  constructor(repository: ArticleHtmlRepository) {
    this.repository = repository;
  }

  async load(sourceUrl: string, forceNetwork: boolean = false): Promise<ArticleHtmlSnapshot> {
    const result: ScpHtmlLoadResult = await this.repository.loadHtml(
      sourceUrl,
      forceNetwork,
      ScpHtmlRequestPriority.USER_INITIATED
    );
    return new ArticleHtmlSnapshot(
      result.html,
      this.sourceOf(result.source),
      result.fetchedAt
    );
  }

  private sourceOf(source: ScpHtmlSource): ArticleHtmlSource {
    switch (source) {
      case ScpHtmlSource.FRESH_CACHE:
        return ArticleHtmlSource.FRESH_CACHE;
      case ScpHtmlSource.STALE_CACHE:
        return ArticleHtmlSource.STALE_CACHE;
      default:
        return ArticleHtmlSource.NETWORK;
    }
  }
}
