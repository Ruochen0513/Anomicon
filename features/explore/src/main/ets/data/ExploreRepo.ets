import { common } from '@kit.AbilityKit';
import {
  ExploreDataOrigin,
  ExploreLoadedPayload,
  ExplorePayload,
  ExploreSource,
  ExploreStoredSnapshot,
  EXPLORE_FRESH_CACHE_DURATION
} from '../domain/ExploreContracts';
import { ExploreHtmlSource, ExploreListRepository } from '../domain/ExploreRepositories';
import { ExploreListService } from './ExploreListService';

/** Data adapter that exposes the Explore persistence and HTML pipeline through domain ports. */
export class ExploreRepo implements ExploreListRepository {
  private readonly service: ExploreListService;
  private context: common.UIAbilityContext | undefined = undefined;

  constructor(service: ExploreListService) {
    this.service = service;
  }

  initialize(context: common.UIAbilityContext): Promise<void> {
    this.context = context;
    return this.service.initialize(context);
  }

  async read(source: ExploreSource): Promise<ExploreStoredSnapshot | undefined> {
    await this.ensureInitialized();
    const stored = await this.service.read(source);
    if (stored === undefined) {
      return undefined;
    }
    return new ExploreStoredSnapshot(stored.json, stored.parsedAt);
  }

  isFresh(snapshot: ExploreStoredSnapshot, now: number = Date.now()): boolean {
    // Keep the freshness rule here so domain/application tests can supply a clock.
    return snapshot.parsedAt > 0 && now >= snapshot.parsedAt &&
      now - snapshot.parsedAt < EXPLORE_FRESH_CACHE_DURATION;
  }

  async load(source: ExploreSource, forceNetwork: boolean = false): Promise<ExploreLoadedPayload> {
    const loaded = await this.service.load(source, forceNetwork);
    return new ExploreLoadedPayload(
      loaded.payload,
      this.toOrigin(loaded.htmlSource),
      loaded.fetchedAt
    );
  }

  put(source: ExploreSource, payload: ExplorePayload, fetchedAt: number = Date.now()): Promise<void> {
    return this.putInitialized(source, payload, fetchedAt);
  }

  private async putInitialized(
    source: ExploreSource,
    payload: ExplorePayload,
    fetchedAt: number
  ): Promise<void> {
    await this.ensureInitialized();
    await this.service.put(source, payload, fetchedAt);
  }

  /** Retry a transient RDB open failure on the next repository operation. */
  private async ensureInitialized(): Promise<void> {
    const context = this.context;
    if (context === undefined) {
      throw new Error('探索列表仓储尚未配置应用上下文');
    }
    await this.service.initialize(context);
  }

  private toOrigin(source: string): ExploreDataOrigin {
    switch (source) {
      case ExploreHtmlSource.FRESH_CACHE:
        return ExploreDataOrigin.FRESH_CACHE;
      case ExploreHtmlSource.STALE_CACHE:
        return ExploreDataOrigin.STALE_CACHE;
      default:
        return ExploreDataOrigin.NETWORK;
    }
  }
}
