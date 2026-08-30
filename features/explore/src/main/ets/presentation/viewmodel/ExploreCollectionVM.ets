import {
  ExploreCombinedSnapshot,
  ExploreContentItem,
  exploreDayKey
} from '../../domain/ExploreContracts';
import { ExploreContentUseCase } from '../../application/ExploreContentUseCase';
import {
  ViewModelErrorInfo,
  ViewModelLifecycle,
  ViewModelLoadState,
  ViewModelSnapshot
} from 'anomiconbasic';
import {
  ExploreCollectionEvent,
  ExploreCollectionEventType
} from './ExploreViewModelContracts';
import { ExploreCollectionMode } from '../../domain/ExploreContracts';

/** Immutable payload published to the Explore collection View. */
export class ExploreCollectionScreenData {
  readonly mode: ExploreCollectionMode;
  readonly items: ExploreContentItem[];
  readonly routeError: ViewModelErrorInfo | undefined;

  constructor(
    mode: ExploreCollectionMode,
    items: ExploreContentItem[],
    routeError: ViewModelErrorInfo | undefined = undefined
  ) {
    this.mode = mode;
    this.items = items.slice();
    this.routeError = routeError;
  }
}

/** 最近更新/轻松一下全量页的屏幕 ViewModel。 */
@ObservedV2
export class ExploreCollectionVM implements ViewModelLifecycle {
  @Trace mode: ExploreCollectionMode;
  @Trace items: ExploreContentItem[] = [];
  @Trace itemCount: number = 0;
  @Trace dayKey: string;
  @Trace routeError: string = '';
  @Trace loading: boolean = false;
  @Trace refreshing: boolean = false;
  @Trace errorMessage: string = '';
  @Trace status: ViewModelLoadState = ViewModelLoadState.IDLE;
  @Trace fetchedAt: number = 0;
  @Trace stale: boolean = false;
  @Trace partial: boolean = false;
  @Trace snapshot: ViewModelSnapshot<ExploreCollectionScreenData>;

  private readonly contentUseCase: ExploreContentUseCase;
  private readonly dayKeyProvider: () => string;
  private dayRolloverTimer: number = -1;
  private loadToken: number = 0;
  private lifecycleEpoch: number = 0;
  private active: boolean = false;
  private disposed: boolean = false;
  private initialized: boolean = false;
  /** Revalidate only stale data or a request interrupted while hidden. */
  private reloadOnActivate: boolean = false;
  private forceReloadOnActivate: boolean = false;
  private snapshotRevision: number = 0;

  constructor(
    contentUseCase: ExploreContentUseCase,
    mode: ExploreCollectionMode = ExploreCollectionMode.RECENT,
    dayKeyProvider: () => string = exploreDayKey
  ) {
    this.contentUseCase = contentUseCase;
    this.mode = mode;
    this.dayKeyProvider = dayKeyProvider;
    this.dayKey = dayKeyProvider();
    this.snapshot = new ViewModelSnapshot<ExploreCollectionScreenData>(
      ViewModelLoadState.IDLE,
      new ExploreCollectionScreenData(mode, [])
    );
  }

  /** 激活页面并按当前模式加载内容。 */
  activate(): Promise<void> {
    if (this.disposed || this.active) {
      return Promise.resolve();
    }
    this.active = true;
    this.publishSnapshot();
    // An invalid route is a terminal screen state until the product creates a
    // new destination.  Do not silently fall back to RECENT and issue a
    // network request when NavDestination sends its later onActive callback.
    if (this.routeError.length > 0) {
      this.status = ViewModelLoadState.ERROR;
      this.loading = false;
      this.refreshing = false;
      this.publishSnapshot();
      return Promise.resolve();
    }
    this.scheduleDayRollover();
    if (this.forceReloadOnActivate) {
      this.forceReloadOnActivate = false;
      this.reloadOnActivate = false;
      this.initialized = true;
      return this.loadContent(true);
    }
    if (this.reloadOnActivate) {
      this.reloadOnActivate = false;
      this.initialized = true;
      return this.loadContent(false);
    }
    if (!this.initialized || (this.items.length === 0 &&
      this.status !== ViewModelLoadState.READY && this.status !== ViewModelLoadState.PARTIAL) ||
      this.status === ViewModelLoadState.ERROR) {
      this.initialized = true;
      return this.loadContent(false);
    }
    this.refreshDay();
    return Promise.resolve();
  }

  /** 暂停页面并作废在途请求。 */
  deactivate(): void {
    if (this.disposed || !this.active) {
      return;
    }
    const interruptedRequest = this.loading || this.refreshing ||
      this.status === ViewModelLoadState.LOADING || this.status === ViewModelLoadState.REFRESHING;
    this.active = false;
    this.lifecycleEpoch++;
    this.loadToken++;
    this.loading = false;
    this.refreshing = false;
    if (interruptedRequest) {
      this.status = this.items.length === 0 ?
        (this.errorMessage.length > 0 ? ViewModelLoadState.ERROR : ViewModelLoadState.IDLE) :
        (this.errorMessage.length > 0 || this.stale || this.partial ?
          ViewModelLoadState.PARTIAL : ViewModelLoadState.READY);
      this.initialized = false;
    }
    this.forceReloadOnActivate = interruptedRequest;
    this.reloadOnActivate = interruptedRequest || (this.items.length > 0 &&
      (this.stale || this.partial || this.errorMessage.length > 0));
    this.clearDayRolloverTimer();
    this.publishSnapshot();
  }

  /** 永久释放页面状态。 */
  dispose(): void {
    if (this.disposed) {
      return;
    }
    this.deactivate();
    this.disposed = true;
    this.publishSnapshot();
  }

  dispatch(event: ExploreCollectionEvent): Promise<void> {
    switch (event.type) {
      case ExploreCollectionEventType.RETRY:
        return this.retry();
      case ExploreCollectionEventType.SET_MODE:
        return this.setMode(event.mode);
      case ExploreCollectionEventType.REFRESH_DAY:
        return this.refreshDay();
    }
    return Promise.resolve();
  }

  /** 路由层只传递字符串参数；非法值不会触发网络请求。 */
  setRouteMode(value: string | undefined): Promise<void> {
    if (this.disposed) {
      return Promise.resolve();
    }
    if (value !== ExploreCollectionMode.RECENT && value !== ExploreCollectionMode.JOKE) {
      this.routeError = '探索列表参数无效';
      this.loading = false;
      this.refreshing = false;
      this.items = [];
      this.itemCount = 0;
      this.errorMessage = '';
      this.status = ViewModelLoadState.ERROR;
      this.fetchedAt = 0;
      this.stale = false;
      this.partial = false;
      this.loadToken++;
      this.clearDayRolloverTimer();
      this.publishSnapshot();
      return Promise.resolve();
    }
    this.routeError = '';
    return this.setMode(value);
  }

  setMode(value: ExploreCollectionMode | undefined): Promise<void> {
    if (this.disposed) {
      return Promise.resolve();
    }
    if (value === undefined) {
      return Promise.resolve();
    }
    if (value !== ExploreCollectionMode.RECENT && value !== ExploreCollectionMode.JOKE) {
      return this.setRouteMode(undefined);
    }
    if (this.mode === value && this.initialized && this.items.length > 0) {
      return Promise.resolve();
    }
    this.mode = value;
    this.dayKey = this.dayKeyProvider();
    this.publishSnapshot();
    this.initialized = true;
    if (!this.active) {
      // A route may provide its mode before NavDestination activation.  The
      // first network request is intentionally deferred to activate().
      this.initialized = false;
      return Promise.resolve();
    }
    return this.loadContent(false);
  }

  loadContent(force: boolean = false): Promise<void> {
    if (this.disposed || !this.active || this.routeError.length > 0) {
      return Promise.resolve();
    }
    const epoch = this.lifecycleEpoch;
    const token = ++this.loadToken;
    this.loading = true;
    this.refreshing = force && this.items.length > 0;
    this.errorMessage = '';
    this.status = this.items.length > 0 ?
      ViewModelLoadState.REFRESHING : ViewModelLoadState.LOADING;
    this.publishSnapshot();
    const task: Promise<ExploreCombinedSnapshot> = this.mode === ExploreCollectionMode.RECENT ?
      this.contentUseCase.loadRecent(force) :
      this.contentUseCase.loadJokes(this.dayKey, force);
    return task.then((snapshot: ExploreCombinedSnapshot): void => {
      if (!this.isCurrent(epoch, token)) {
        return;
      }
      this.items = snapshot.items;
      this.itemCount = snapshot.items.length;
      this.errorMessage = snapshot.error;
      this.fetchedAt = snapshot.fetchedAt;
      this.stale = snapshot.stale;
      this.partial = snapshot.partial;
      this.status = this.statusOf(snapshot.items.length, snapshot.error, snapshot.stale);
      this.publishSnapshot();
    }).catch((error: Object): void => {
      if (!this.isCurrent(epoch, token)) {
        return;
      }
      this.errorMessage = error instanceof Error ? error.message : '探索内容加载失败';
      this.status = this.items.length > 0 ? ViewModelLoadState.PARTIAL : ViewModelLoadState.ERROR;
      this.partial = this.items.length > 0;
      this.publishSnapshot();
    }).finally((): void => {
      if (this.isCurrent(epoch, token)) {
        this.loading = false;
        this.refreshing = false;
        this.publishSnapshot();
      }
    });
  }

  retry(): Promise<void> {
    if (this.disposed || this.routeError.length > 0) {
      return Promise.resolve();
    }
    return this.loadContent(true);
  }

  refreshDay(): Promise<void> {
    if (this.disposed) {
      return Promise.resolve();
    }
    const today = this.dayKeyProvider();
    if (today === this.dayKey) {
      return Promise.resolve();
    }
    this.dayKey = today;
    this.publishSnapshot();
    if (this.mode !== ExploreCollectionMode.JOKE) {
      return Promise.resolve();
    }
    return this.loadContent(false);
  }

  currentError(): string {
    if (this.routeError.length > 0) {
      return this.routeError;
    }
    return this.errorMessage;
  }

  isLoading(): boolean {
    return this.itemCount === 0 && this.loading;
  }

  private statusOf(itemCount: number, error: string, stale: boolean): ViewModelLoadState {
    if (itemCount === 0 && error.length > 0) {
      return ViewModelLoadState.ERROR;
    }
    if (error.length > 0 || stale) {
      return ViewModelLoadState.PARTIAL;
    }
    return ViewModelLoadState.READY;
  }

  private isCurrent(epoch: number, token: number): boolean {
    return !this.disposed && this.active && epoch === this.lifecycleEpoch && token === this.loadToken;
  }

  private scheduleDayRollover(): void {
    this.clearDayRolloverTimer();
    const now = new Date();
    const nextDay = new Date(now.getTime());
    nextDay.setHours(24, 0, 0, 250);
    this.dayRolloverTimer = setTimeout((): void => {
      this.dayRolloverTimer = -1;
      this.refreshDay();
      if (this.active && !this.disposed) {
        this.scheduleDayRollover();
      }
    }, Math.max(1000, nextDay.getTime() - now.getTime()));
  }

  private clearDayRolloverTimer(): void {
    if (this.dayRolloverTimer >= 0) {
      clearTimeout(this.dayRolloverTimer);
      this.dayRolloverTimer = -1;
    }
  }

  private publishSnapshot(): void {
    const routeError = this.routeError.length > 0 ?
      new ViewModelErrorInfo(this.routeError, 'invalid_route', false) : undefined;
    const loadError = routeError === undefined && this.errorMessage.length > 0 &&
      (this.status === ViewModelLoadState.ERROR || this.status === ViewModelLoadState.PARTIAL) ?
      new ViewModelErrorInfo(this.errorMessage) : undefined;
    this.snapshotRevision += 1;
    this.snapshot = new ViewModelSnapshot<ExploreCollectionScreenData>(
      this.status,
      new ExploreCollectionScreenData(this.mode, this.items, routeError),
      routeError ?? loadError,
      this.fetchedAt > 0 ? this.fetchedAt : undefined,
      this.stale,
      this.status === ViewModelLoadState.PARTIAL || this.partial,
      this.snapshotRevision
    );
  }
}
