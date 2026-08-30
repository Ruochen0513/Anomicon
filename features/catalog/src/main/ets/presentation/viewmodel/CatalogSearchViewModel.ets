import {
  ViewModelErrorInfo,
  ViewModelLifecycle,
  ViewModelLoadState,
  ViewModelSnapshot
} from 'anomiconbasic';
import {
  CatalogSearchUseCase
} from '../../application/CatalogUseCases';
import {
  CatalogEntry,
  CatalogSnapshot
} from '../../domain/CatalogContracts';
import { filterCatalogEntries } from '../../domain/CatalogRepositories';
import {
  DEFAULT_SERIES_ID,
  SCP_SERIES,
  ScpSeriesDescriptor
} from '../../domain/ScpSeriesItem';

const CATALOG_LOAD_TIMEOUT_MS: number = 40 * 1000;

/** Immutable screen projection consumed by the Catalog search View. */
export class CatalogSearchScreenData {
  readonly query: string;
  readonly seriesId: string;
  readonly entries: CatalogEntry[];
  readonly random: CatalogEntry[];
  readonly history: string[];
  readonly catalogPending: boolean;

  constructor(
    query: string,
    seriesId: string,
    entries: CatalogEntry[],
    random: CatalogEntry[],
    history: string[],
    catalogPending: boolean
  ) {
    this.query = query;
    this.seriesId = seriesId;
    this.entries = entries.slice();
    this.random = random.slice();
    this.history = history.slice();
    this.catalogPending = catalogPending;
  }
}

/** 搜索页 ViewModel：管理目录观察、历史、随机发现和请求 token。 */
@ObservedV2
export class CatalogSearchViewModel implements ViewModelLifecycle {
  @Trace query: string = '';
  @Trace seriesId: string = DEFAULT_SERIES_ID;
  @Trace entries: CatalogEntry[] = [];
  @Trace visibleEntries: CatalogEntry[] = [];
  @Trace randomItems: CatalogEntry[] = [];
  @Trace history: string[] = [];
  @Trace catalogPending: boolean = false;
  @Trace status: ViewModelLoadState = ViewModelLoadState.IDLE;
  @Trace errorMessage: string = '';
  @Trace fetchedAt: number = 0;
  @Trace stale: boolean = false;
  @Trace snapshot: ViewModelSnapshot<CatalogSearchScreenData>;

  private readonly search: CatalogSearchUseCase;
  private readonly randomCount: number;
  private token: number = 0;
  private active: boolean = false;
  private disposed: boolean = false;
  private initialized: boolean = false;
  private unsubscribe: (() => void) | undefined = undefined;
  private pendingTimeout: number = -1;
  private snapshotRevision: number = 0;

  constructor(search: CatalogSearchUseCase, randomCount: number = 10) {
    this.search = search;
    this.randomCount = randomCount;
    this.snapshot = new ViewModelSnapshot<CatalogSearchScreenData>(
      ViewModelLoadState.IDLE,
      new CatalogSearchScreenData('', DEFAULT_SERIES_ID, [], [], [], false)
    );
  }

  activate(): void {
    if (this.disposed || this.active) {
      return;
    }
    this.active = true;
    this.publishSnapshot();
    if (!this.initialized) {
      this.initialized = true;
      try {
        this.history = this.search.listHistory();
      } catch (error) {
        // History is optional; a preferences failure must not prevent the
        // catalog itself from becoming usable.
        this.history = [];
        console.warn(`Read search history failed: ${error instanceof Error ? error.message : 'unknown error'}`);
      }
      this.observeSeries(this.seriesId);
    } else {
      this.observeSeries(this.seriesId);
    }
  }

  deactivate(): void {
    if (this.disposed || !this.active) {
      return;
    }
    this.active = false;
    this.token++;
    this.stopObservation();
    this.publishSnapshot();
  }

  dispose(): void {
    if (this.disposed) {
      return;
    }
    this.deactivate();
    this.disposed = true;
    this.entries = [];
    this.visibleEntries = [];
    this.randomItems = [];
    this.publishSnapshot();
  }

  setQuery(query: string): void {
    if (this.disposed) {
      return;
    }
    this.query = query;
    this.publishVisible();
    this.publishSnapshot();
  }

  selectSeries(seriesId: string): void {
    if (this.disposed || this.seriesId === seriesId) {
      return;
    }
    // Do not project the previous series while the new cache snapshot is
    // pending.  This also invalidates an old observer in the A→B→A route
    // sequence and keeps search results tied to the selected series.
    this.token++;
    this.stopObservation();
    this.seriesId = this.descriptor(seriesId).id;
    this.initialized = false;
    this.entries = [];
    this.visibleEntries = [];
    this.randomItems = [];
    this.catalogPending = false;
    this.fetchedAt = 0;
    this.stale = false;
    this.errorMessage = '';
    this.status = ViewModelLoadState.IDLE;
    this.publishSnapshot();
    if (this.active) {
      this.observeSeries(this.seriesId);
    }
  }

  addHistory(value: string): void {
    if (this.disposed) {
      return;
    }
    this.search.addHistory(value);
    this.history = this.search.listHistory();
    this.publishSnapshot();
  }

  clearHistory(): void {
    if (this.disposed) {
      return;
    }
    this.search.clearHistory();
    this.history = [];
    this.publishSnapshot();
  }

  retry(): void {
    if (this.active) {
      // A retry is an explicit user action.  Do not read the same stale or
      // corrupt cache again; go through the repository's force-refresh path.
      this.observeSeries(this.seriesId, true);
    }
  }

  private observeSeries(id: string, forceRefresh: boolean = false): void {
    this.stopObservation();
    const token = ++this.token;
    const hasEntries = this.entries.length > 0;
    this.catalogPending = forceRefresh && !hasEntries;
    this.status = forceRefresh && hasEntries ?
      ViewModelLoadState.REFRESHING : ViewModelLoadState.LOADING;
    this.errorMessage = '';
    this.publishSnapshot();
    this.unsubscribe = this.search.observe(id, (snapshot: CatalogSnapshot): void => {
      if (this.isCurrent(token, id)) {
        this.applySnapshot(snapshot);
      }
    });
    if (this.catalogPending) {
      this.armPendingTimeout(id, token);
    }
    this.loadCached(id, token, forceRefresh);
  }

  private async loadCached(id: string, token: number, forceRefresh: boolean = false): Promise<void> {
    try {
      if (forceRefresh) {
        const loaded = await this.search.refresh(this.descriptor(id));
        if (!this.isCurrent(token, id)) {
          return;
        }
        // An observer may have received the same cache notification first;
        // applying the returned force-refresh result still guarantees that a
        // repository which cannot notify subscribers completes the retry.
        this.applySnapshot(loaded);
        return;
      }
      const cached = await this.search.cached(id);
      if (!this.isCurrent(token, id)) {
        return;
      }
      if (cached === undefined) {
        this.entries = [];
        this.randomItems = [];
        this.catalogPending = true;
        this.armPendingTimeout(id, token);
        this.status = ViewModelLoadState.LOADING;
        this.publishSnapshot();
        const loaded = await this.search.load(this.descriptor(id));
        if (!this.isCurrent(token, id)) {
          return;
        }
        // The shared catalog repository may publish the same snapshot through
        // observe() before load() resolves.  Only project the returned value
        // when no observer has already completed this cold load, avoiding a
        // second random-discovery shuffle while still surviving cache-write
        // failures that cannot notify subscribers.
        if (this.catalogPending) {
          this.applySnapshot(loaded);
        }
        return;
      }
      this.stopPendingTimeout();
      this.applySnapshot(cached);
      if (cached.stale) {
        // 图鉴页会负责重验；搜索页只观察更新通知，避免重复网络请求。
        this.status = cached.partial || cached.stale ?
          ViewModelLoadState.PARTIAL : ViewModelLoadState.READY;
        this.publishSnapshot();
      }
    } catch (error) {
      if (!this.isCurrent(token, id)) {
        return;
      }
      this.catalogPending = false;
      this.stopPendingTimeout();
      this.status = ViewModelLoadState.ERROR;
      this.errorMessage = error instanceof Error ? error.message : '搜索目录读取失败';
      this.publishSnapshot();
    }
  }

  private applySnapshot(snapshot: CatalogSnapshot): void {
    this.entries = snapshot.entries.slice();
    // Random discovery is an application concern; keep the ViewModel focused
    // on lifecycle/state projection and request-token guards.
    this.randomItems = this.search.pickRandom(this.entries, this.randomCount);
    this.catalogPending = false;
    this.fetchedAt = snapshot.fetchedAt;
    this.stale = snapshot.stale;
    this.errorMessage = snapshot.error;
    this.status = snapshot.partial || snapshot.stale ?
      ViewModelLoadState.PARTIAL : ViewModelLoadState.READY;
    this.stopPendingTimeout();
    this.publishVisible();
    this.publishSnapshot();
  }

  private publishVisible(): void {
    this.visibleEntries = filterCatalogEntries(this.entries, this.query);
  }

  private armPendingTimeout(id: string, token: number): void {
    if (this.pendingTimeout >= 0) {
      return;
    }
    this.pendingTimeout = setTimeout((): void => {
      this.pendingTimeout = -1;
      if (!this.isCurrent(token, id)) {
        return;
      }
      this.catalogPending = false;
      this.status = ViewModelLoadState.ERROR;
      this.errorMessage = '目录加载超时，请重试';
      this.token++;
      this.publishSnapshot();
    }, CATALOG_LOAD_TIMEOUT_MS);
  }

  private stopPendingTimeout(): void {
    if (this.pendingTimeout >= 0) {
      clearTimeout(this.pendingTimeout);
      this.pendingTimeout = -1;
    }
  }

  private stopObservation(): void {
    this.stopPendingTimeout();
    this.unsubscribe?.();
    this.unsubscribe = undefined;
  }

  private isCurrent(token: number, id: string): boolean {
    return !this.disposed && this.active && token === this.token && id === this.seriesId;
  }

  private publishSnapshot(): void {
    const error = this.errorMessage.length > 0 &&
      (this.status === ViewModelLoadState.ERROR || this.status === ViewModelLoadState.PARTIAL) ?
      new ViewModelErrorInfo(this.errorMessage) : undefined;
    this.snapshotRevision += 1;
    this.snapshot = new ViewModelSnapshot<CatalogSearchScreenData>(
      this.status,
      new CatalogSearchScreenData(
        this.query,
        this.seriesId,
        this.visibleEntries,
        this.randomItems,
        this.history,
        this.catalogPending
      ),
      error,
      this.fetchedAt > 0 ? this.fetchedAt : undefined,
      this.stale,
      this.status === ViewModelLoadState.PARTIAL,
      this.snapshotRevision
    );
  }

  private descriptor(id: string): ScpSeriesDescriptor {
    for (let index = 0; index < SCP_SERIES.length; index++) {
      if (SCP_SERIES[index].id === id) {
        return SCP_SERIES[index];
      }
    }
    return SCP_SERIES[0];
  }
}
