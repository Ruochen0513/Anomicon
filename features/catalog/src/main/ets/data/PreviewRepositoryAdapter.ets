import {
  ScpHtmlRequestPriority
} from '../domain/ArticleHtmlRepository';
import { CatalogPreview } from '../domain/CatalogContracts';
import {
  PreviewRefreshListener,
  PreviewRepository
} from '../domain/CatalogRepositories';
import {
  ScpPreviewInfo,
  ScpPreviewService
} from './ScpPreviewService';

/** 预览管线适配器：显式注入的数据管线不会穿透到 presentation。 */
export class PreviewRepositoryAdapter implements PreviewRepository {
  private readonly service: ScpPreviewService;

  constructor(service: ScpPreviewService) {
    this.service = service;
  }

  getPreview(
    itemId: string,
    onRefreshed?: PreviewRefreshListener,
    priority: ScpHtmlRequestPriority = ScpHtmlRequestPriority.VISIBLE,
    forceRefresh: boolean = false
  ): Promise<CatalogPreview> {
    return this.service.getPreview(
      itemId,
      onRefreshed === undefined ? undefined : (info: ScpPreviewInfo): void => {
        onRefreshed(this.toDomain(info));
      },
      priority,
      forceRefresh
    ).then((info: ScpPreviewInfo): CatalogPreview => this.toDomain(info));
  }

  resolveFetchedHtml(
    itemId: string,
    html: string,
    fetchedAt: number = Date.now()
  ): Promise<CatalogPreview> {
    return this.service.resolveFetchedHtml(itemId, html, fetchedAt)
      .then((info: ScpPreviewInfo): CatalogPreview => this.toDomain(info));
  }

  prefetch(itemIds: string[]): void {
    this.service.prefetch(itemIds);
  }

  cancelQueuedPrefetch(itemIds: string[]): void {
    this.service.cancelQueuedPrefetch(itemIds);
  }

  private toDomain(info: ScpPreviewInfo): CatalogPreview {
    return new CatalogPreview(
      info.path,
      info.aspect,
      info.description,
      info.url,
      info.fetchedAt,
      info.stale,
      info.error
    );
  }
}
