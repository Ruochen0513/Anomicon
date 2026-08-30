import { SearchHistoryRepository } from '../domain/CatalogRepositories';
import { ScpSearchHistoryService } from './ScpSearchHistoryService';

/** Preferences 搜索历史的窄化适配器。 */
export class SearchHistoryAdapter implements SearchHistoryRepository {
  private readonly service: ScpSearchHistoryService;

  constructor(service: ScpSearchHistoryService) {
    this.service = service;
  }

  list(): string[] {
    return this.service.list();
  }

  add(query: string): void {
    this.service.add(query);
  }

  clear(): void {
    this.service.clear();
  }
}
