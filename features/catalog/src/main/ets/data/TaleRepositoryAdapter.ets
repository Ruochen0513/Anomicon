import {
  ScpHtmlRequestPriority,
  ScpHtmlSource
} from '../domain/ArticleHtmlRepository';
import {
  CatalogParser,
  CatalogSnapshotSource,
  CatalogTaleEntry,
  TaleParseResult,
  TaleSnapshot
} from '../domain/CatalogContracts';
import { TaleRepository, TaleSnapshotListener } from '../domain/CatalogRepositories';
import { ScpCachePolicy } from '../domain/ScpCachePolicy';
import {
  TALE_LIST_PARSER_VERSION,
  TalePayload,
  TaleRawEntry
} from '../domain/StaticCatalogContracts';
import {
  ScpStoredTaleList,
  TaleListService
} from './TaleListService';

/** 故事列表 Data adapter；持久化与解析依赖由 feature composition 显式注入。 */
export class TaleRepositoryAdapter implements TaleRepository {
  private readonly service: TaleListService;
  private readonly parser: CatalogParser;
  private readonly listeners: Array<TaleSnapshotListener> = [];

  constructor(service: TaleListService, parser: CatalogParser) {
    this.service = service;
    this.parser = parser;
  }

  async getCached(): Promise<TaleSnapshot | undefined> {
    let stored: ScpStoredTaleList | undefined = undefined;
    try {
      stored = await this.service.read();
    } catch (error) {
      // The tale list is a rebuildable cache.  Continue to the network path
      // when RDB reads fail instead of turning a transient cache error into a
      // page-level failure.
      console.warn(`Read tale cache failed: ${error instanceof Error ? error.message : 'unknown error'}`);
      return undefined;
    }
    if (stored === undefined) {
      return undefined;
    }
    return this.decodeStored(stored);
  }

  async load(priority: ScpHtmlRequestPriority = ScpHtmlRequestPriority.USER_INITIATED): Promise<TaleSnapshot> {
    const cached = await this.getCached();
    if (cached !== undefined) {
      return cached;
    }
    return this.fetchAndParse(priority);
  }

  async refresh(priority: ScpHtmlRequestPriority = ScpHtmlRequestPriority.BACKGROUND): Promise<TaleSnapshot> {
    const cached = await this.getCached();
    const result = await this.service.loadHtmlForRequest(true, priority);
    if (result.source === ScpHtmlSource.STALE_CACHE && cached !== undefined) {
      return cached;
    }
    const parsed = await this.parser.parseTales(result.html);
    const tales = this.validatedTales(parsed);
    const rawTales: TaleRawEntry[] = [];
    for (let index = 0; index < tales.length; index++) {
      const tale = tales[index];
      const rawTale: TaleRawEntry = { id: tale.id, title: tale.title };
      rawTales.push(rawTale);
    }
    const payload: TalePayload = {
      parserVersion: parsed.parserVersion,
      ok: parsed.ok,
      error: typeof parsed.error === 'string' ? parsed.error : '',
      tales: rawTales
    };
    await this.persist(payload, result.fetchedAt);
    const snapshot = new TaleSnapshot(
      tales,
      result.source === ScpHtmlSource.STALE_CACHE ? CatalogSnapshotSource.STALE_CACHE :
        (result.source === ScpHtmlSource.FRESH_CACHE ? CatalogSnapshotSource.CACHE : CatalogSnapshotSource.NETWORK),
      result.fetchedAt,
      result.source === ScpHtmlSource.STALE_CACHE,
      false,
      parsed.parserVersion
    );
    this.notify(snapshot);
    return snapshot;
  }

  subscribe(listener: TaleSnapshotListener): () => void {
    if (this.listeners.indexOf(listener) < 0) {
      this.listeners.push(listener);
    }
    return (): void => {
      const index = this.listeners.indexOf(listener);
      if (index >= 0) {
        this.listeners.splice(index, 1);
      }
    };
  }

  private async fetchAndParse(priority: ScpHtmlRequestPriority): Promise<TaleSnapshot> {
    const result = await this.service.loadHtmlForRequest(false, priority);
    const parsed = await this.parser.parseTales(result.html);
    const tales = this.validatedTales(parsed);
    const rawTales: TaleRawEntry[] = [];
    for (let index = 0; index < tales.length; index++) {
      const tale = tales[index];
      const rawTale: TaleRawEntry = { id: tale.id, title: tale.title };
      rawTales.push(rawTale);
    }
    const payload: TalePayload = {
      parserVersion: parsed.parserVersion,
      ok: parsed.ok,
      error: typeof parsed.error === 'string' ? parsed.error : '',
      tales: rawTales
    };
    await this.persist(payload, result.fetchedAt);
    const snapshot = new TaleSnapshot(
      tales,
      result.source === ScpHtmlSource.STALE_CACHE ? CatalogSnapshotSource.STALE_CACHE :
        (result.source === ScpHtmlSource.FRESH_CACHE ? CatalogSnapshotSource.CACHE : CatalogSnapshotSource.NETWORK),
      result.fetchedAt,
      result.source === ScpHtmlSource.STALE_CACHE,
      false,
      parsed.parserVersion
    );
    this.notify(snapshot);
    return snapshot;
  }

  private decodeStored(stored: ScpStoredTaleList): TaleSnapshot | undefined {
    try {
      const payload = JSON.parse(stored.json) as TalePayload;
      if (payload === undefined || payload === null || typeof payload !== 'object' ||
        payload.parserVersion !== TALE_LIST_PARSER_VERSION ||
        payload.ok !== true || !Array.isArray(payload.tales)) {
        return undefined;
      }
      const tales = this.normalize(payload.tales.map((tale) =>
        new CatalogTaleEntry(tale.id, tale.title)));
      if (tales.length === 0) {
        return undefined;
      }
      return new TaleSnapshot(
        tales,
        CatalogSnapshotSource.CACHE,
        stored.parsedAt,
        !ScpCachePolicy.isFresh(stored.parsedAt),
        false,
        payload.parserVersion
      );
    } catch (error) {
      return undefined;
    }
  }

  private validatedTales(parsed: TaleParseResult): CatalogTaleEntry[] {
    if (parsed === undefined || parsed === null || typeof parsed !== 'object') {
      throw new Error('故事目录解析结果不是对象');
    }
    if (!Array.isArray(parsed.tales)) {
      throw new Error('故事目录解析结果字段不完整');
    }
    const tales = this.normalize(parsed.tales);
    if (parsed.parserVersion !== TALE_LIST_PARSER_VERSION || parsed.ok !== true || tales.length === 0) {
      throw new Error(parsed.parserVersion !== TALE_LIST_PARSER_VERSION ?
        `故事目录解析器版本不兼容：${parsed.parserVersion}` :
        (parsed.ok === true ? '故事目录解析结果为空' :
          `故事目录解析失败：${typeof parsed.error === 'string' ? parsed.error : '未知错误'}`));
    }
    return tales;
  }

  private async persist(payload: TalePayload, fetchedAt: number): Promise<void> {
    try {
      await this.service.put(payload, fetchedAt);
    } catch (error) {
      // Persistence is an acceleration layer; a valid network response is
      // still useful when the local database is read-only/full/unavailable.
      console.warn(`Write tale cache failed: ${error instanceof Error ? error.message : 'unknown error'}`);
    }
  }

  private normalize(tales: CatalogTaleEntry[]): CatalogTaleEntry[] {
    const seen: Set<string> = new Set<string>();
    const result: CatalogTaleEntry[] = [];
    for (let index = 0; index < tales.length; index++) {
      const tale = tales[index];
      if (tale === undefined || tale === null || typeof tale !== 'object' ||
        typeof tale.id !== 'string' || typeof tale.title !== 'string') {
        continue;
      }
      const id = tale.id.trim();
      const title = tale.title.trim();
      if (id.length === 0 || title.length < 2 || seen.has(id)) {
        continue;
      }
      seen.add(id);
      result.push(new CatalogTaleEntry(id, title));
    }
    return result;
  }

  private notify(snapshot: TaleSnapshot): void {
    const listeners = this.listeners.slice();
    for (let index = 0; index < listeners.length; index++) {
      try {
        listeners[index](snapshot);
      } catch (error) {
        console.warn(`Notify tale snapshot failed: ${error instanceof Error ? error.message : 'unknown error'}`);
      }
    }
  }
}
