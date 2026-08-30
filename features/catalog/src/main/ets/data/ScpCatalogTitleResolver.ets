import {
  SCP_CATALOG_PARSER_VERSION,
  ScpCatalogPayload,
  ScpCatalogRawEntry
} from '../domain/StaticCatalogContracts';
import { ScpCatalogCacheService, ScpStoredCatalog } from './ScpCatalogCacheService';

/** 从编号定位主站系列目录缓存；SCP-001…999 属于 I，1000…1999 属于 II，以此类推。 */
function seriesIdOf(itemId: string): string {
  const match = /^scp-([0-9]{1,4})$/i.exec(itemId.trim());
  if (match === null) {
    return '';
  }
  const value = Number(match[1]);
  if (!Number.isInteger(value) || value < 0 || value > 9999) {
    return '';
  }
  const seriesIndex = Math.floor(value / 1000);
  return seriesIndex === 0 ? 'scp-series' : `scp-series-${seriesIndex + 1}`;
}

/**
 * SCP 单篇正文的 page-title 通常只有编号；项目名称以系列目录为准。
 * 解析器只消费本地派生缓存，不会为了终端标题额外请求网络。
 */
export class ScpCatalogTitleResolver {
  private readonly catalogStore: ScpCatalogCacheService;

  constructor(catalogStore: ScpCatalogCacheService) {
    this.catalogStore = catalogStore;
  }

  async resolve(itemId: string): Promise<string> {
    const normalizedId = itemId.trim().toLowerCase();
    const titles = await this.resolveMany([normalizedId]);
    return titles.get(normalizedId) ?? '';
  }

  async resolveMany(itemIds: string[]): Promise<Map<string, string>> {
    const requestedBySeries: Map<string, Set<string>> = new Map<string, Set<string>>();
    for (let index = 0; index < itemIds.length; index++) {
      const normalizedId = itemIds[index].trim().toLowerCase();
      const seriesId = seriesIdOf(normalizedId);
      if (seriesId.length === 0) {
        continue;
      }
      const requested = requestedBySeries.get(seriesId) ?? new Set<string>();
      requested.add(normalizedId);
      requestedBySeries.set(seriesId, requested);
    }

    const result: Map<string, string> = new Map<string, string>();
    const seriesIds = Array.from(requestedBySeries.keys());
    for (let index = 0; index < seriesIds.length; index++) {
      const seriesId = seriesIds[index];
      let stored: ScpStoredCatalog | undefined = undefined;
      try {
        stored = await this.catalogStore.get(seriesId);
      } catch (error) {
        continue;
      }
      if (stored === undefined) {
        continue;
      }
      const requested = requestedBySeries.get(seriesId)!;
      const entries = this.entriesOf(stored);
      for (let entryIndex = 0; entryIndex < entries.length; entryIndex++) {
        const entry = entries[entryIndex];
        const normalizedId = entry.itemId.trim().toLowerCase();
        const title = entry.title.trim();
        if (requested.has(normalizedId) && title.length > 0 && title.toLowerCase() !== normalizedId) {
          result.set(normalizedId, title);
        }
      }
    }
    return result;
  }

  private entriesOf(stored: ScpStoredCatalog): ScpCatalogRawEntry[] {
    try {
      const payload = JSON.parse(stored.json) as ScpCatalogPayload;
      return payload.parserVersion === SCP_CATALOG_PARSER_VERSION &&
        payload.ok && Array.isArray(payload.entries) ? payload.entries : [];
    } catch (error) {
      return [];
    }
  }
}
