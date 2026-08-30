import { ScpHtmlRequestPriority } from '../../domain/ArticleHtmlRepository';
import { ViewModelLifecycle, ViewModelLoadState } from 'anomiconbasic';
import { TaleContentUseCase } from '../../application/CatalogUseCases';
import {
  CatalogTaleEntry,
  TaleSnapshot
} from '../../domain/CatalogContracts';
import { filterTaleEntries } from '../../domain/CatalogRepositories';

/** 故事列表页面 ViewModel；筛选状态属于页面瞬态，不写入 AppStorageV2。 */
@ObservedV2
export class TaleListViewModel implements ViewModelLifecycle {
  @Trace query: string = '';
  @Trace letter: string = '';
  @Trace tales: CatalogTaleEntry[] = [];
  @Trace visibleTales: CatalogTaleEntry[] = [];
  @Trace status: ViewModelLoadState = ViewModelLoadState.IDLE;
  @Trace loading: boolean = false;
  @Trace refreshing: boolean = false;
  @Trace errorMessage: string = '';
  @Trace stale: boolean = false;
  @Trace partial: boolean = false;

  private readonly content: TaleContentUseCase;
  private generation: number = 0;
  private active: boolean = false;
  private disposed: boolean = false;
  private initialized: boolean = false;
  /** Re-run only a request that was interrupted while the page was hidden. */
  private refreshOnActivate: boolean = false;

  constructor(content: TaleContentUseCase) {
    this.content = content;
  }

  activate(): void {
    if (this.disposed || this.active) {
      return;
    }
    this.active = true;
    if (this.refreshOnActivate) {
      this.refreshOnActivate = false;
      this.loadInternal(true).catch((): void => {
        // 错误通过状态发布。
      });
    } else if (!this.initialized) {
      this.initialized = true;
      this.load().catch((): void => {
        // 错误通过状态发布。
      });
    } else if (this.tales.length > 0 && this.stale) {
      // 只有快照过期时才在重新可见时重新检查缓存；新鲜列表保持滚动位置。
      this.load().catch((): void => {
        // 错误通过状态发布。
      });
    }
  }

  deactivate(): void {
    if (this.disposed || !this.active) {
      return;
    }
    const interruptedStatus = this.status;
    const interruptedRequest = this.loading || this.refreshing ||
      interruptedStatus === ViewModelLoadState.LOADING ||
      interruptedStatus === ViewModelLoadState.REFRESHING;
    this.active = false;
    this.generation++;
    this.loading = false;
    this.refreshing = false;
    if (this.tales.length === 0) {
      this.status = ViewModelLoadState.IDLE;
      this.initialized = false;
    } else if (interruptedStatus === ViewModelLoadState.LOADING ||
      interruptedStatus === ViewModelLoadState.REFRESHING) {
      this.status = this.partial ? ViewModelLoadState.PARTIAL : ViewModelLoadState.READY;
      this.initialized = false;
    }
    this.refreshOnActivate = interruptedRequest || (this.tales.length > 0 && this.stale);
  }

  dispose(): void {
    if (this.disposed) {
      return;
    }
    this.deactivate();
    this.disposed = true;
    this.tales = [];
    this.visibleTales = [];
  }

  setQuery(query: string): void {
    if (this.disposed) {
      return;
    }
    this.query = query;
    this.publishVisible();
  }

  setLetter(letter: string): void {
    if (this.disposed) {
      return;
    }
    this.letter = letter.trim().toUpperCase();
    this.publishVisible();
  }

  clearFilter(): void {
    if (this.disposed) {
      return;
    }
    this.query = '';
    this.letter = '';
    this.publishVisible();
  }

  load(): Promise<void> {
    return this.loadInternal(false);
  }

  refresh(): Promise<void> {
    return this.loadInternal(true);
  }

  retry(): Promise<void> {
    return this.loadInternal(true);
  }

  private async loadInternal(forceRefresh: boolean): Promise<void> {
    if (this.disposed || !this.active) {
      return;
    }
    const generation = ++this.generation;
    this.loading = !forceRefresh || this.tales.length === 0;
    this.refreshing = forceRefresh && this.tales.length > 0;
    this.errorMessage = '';
    this.status = this.refreshing ? ViewModelLoadState.REFRESHING : ViewModelLoadState.LOADING;
    try {
      const snapshot = forceRefresh ?
        await this.content.refresh(ScpHtmlRequestPriority.USER_INITIATED) :
        await this.content.load(ScpHtmlRequestPriority.USER_INITIATED);
      if (!this.isCurrent(generation)) {
        return;
      }
      this.applySnapshot(snapshot);
      if (snapshot.stale && !forceRefresh) {
        this.status = snapshot.partial ? ViewModelLoadState.PARTIAL : ViewModelLoadState.REFRESHING;
        this.refreshing = !snapshot.partial;
        this.content.refresh(ScpHtmlRequestPriority.BACKGROUND).then((updated: TaleSnapshot): void => {
          if (this.isCurrent(generation)) {
            this.applySnapshot(updated);
          }
        }).catch((error: Object): void => {
          if (this.isCurrent(generation)) {
            this.loading = false;
            this.refreshing = false;
            this.stale = true;
            this.partial = true;
            this.errorMessage = error instanceof Error ? error.message :
              '故事目录更新失败，正在显示缓存内容';
            this.status = ViewModelLoadState.PARTIAL;
          }
        });
      }
    } catch (error) {
      if (!this.isCurrent(generation)) {
        return;
      }
      this.loading = false;
      this.refreshing = false;
      this.status = ViewModelLoadState.ERROR;
      this.errorMessage = error instanceof Error ? error.message : '故事目录加载失败';
      throw new Error(error instanceof Error ? error.message : '故事目录加载失败');
    }
  }

  private applySnapshot(snapshot: TaleSnapshot): void {
    this.tales = snapshot.tales.slice();
    this.stale = snapshot.stale;
    this.partial = snapshot.partial;
    this.loading = false;
    this.refreshing = false;
    this.errorMessage = snapshot.error;
    this.status = snapshot.partial || snapshot.stale ?
      ViewModelLoadState.PARTIAL : ViewModelLoadState.READY;
    this.publishVisible();
  }

  private publishVisible(): void {
    this.visibleTales = filterTaleEntries(this.tales, this.query, this.letter);
  }

  private isCurrent(generation: number): boolean {
    return !this.disposed && this.active && generation === this.generation;
  }

}
