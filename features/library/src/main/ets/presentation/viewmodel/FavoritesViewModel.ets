import { LibraryContentRef, LibraryFavorite } from '../../domain/LibraryContentRef';
import { FavoriteRepository } from '../../domain/LibraryRepositories';

/** Lightweight state listener used by page-level projection ViewModels. */
export type FavoritesViewModelListener = () => void;

/**
 * 收藏的应用级共享状态。
 *
 * 所有数据库动作按触发顺序串行；只有持久化成功并取得有序快照后，
 * 才整体替换 `items`，避免页面观察到数据库尚未提交的乐观状态。
 */
@ObservedV2
export class FavoritesViewModel {
  @Trace items: LibraryFavorite[] = [];
  @Trace loading: boolean = false;
  @Trace error: string = '';
  @Trace initialized: boolean = false;

  private readonly repository: FavoriteRepository;
  private initialization: Promise<void> | undefined = undefined;
  private operationTail: Promise<void> = Promise.resolve();
  private readonly listeners: FavoritesViewModelListener[] = [];

  subscribe(listener: FavoritesViewModelListener): () => void {
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

  constructor(repository: FavoriteRepository) {
    this.repository = repository;
  }

  initialize(): Promise<void> {
    if (this.initialized) {
      return Promise.resolve();
    }
    if (this.initialization !== undefined) {
      return this.initialization;
    }
    const task = this.enqueue(async (): Promise<void> => {
      this.loading = true;
      this.error = '';
      this.notifyListeners();
      try {
        const snapshot = await this.repository.list();
        this.items = snapshot;
        this.initialized = true;
      } catch (error) {
        this.error = this.errorMessage(error);
        this.notifyListeners();
        throw new Error(this.error);
      } finally {
        this.loading = false;
        this.notifyListeners();
      }
    });
    this.initialization = task;
    task.catch((): void => {
      if (this.initialization === task) {
        this.initialization = undefined;
      }
    });
    return task;
  }

  isFavorite(contentKey: string): boolean {
    return this.indexOf(contentKey) >= 0;
  }

  async toggle(content: LibraryContentRef): Promise<boolean> {
    await this.initialize();
    let favorite = this.isFavorite(content.key);
    await this.enqueue(async (): Promise<void> => {
      try {
        favorite = await this.repository.toggle(content);
        this.items = await this.repository.list();
        this.error = '';
        this.notifyListeners();
      } catch (error) {
        this.error = this.errorMessage(error);
        this.notifyListeners();
        throw new Error(this.error);
      }
    });
    return favorite;
  }

  async setFavorite(content: LibraryContentRef, favorite: boolean): Promise<boolean> {
    await this.initialize();
    await this.enqueue(async (): Promise<void> => {
      try {
        await this.repository.setFavorite(content, favorite);
        this.items = await this.repository.list();
        this.error = '';
        this.notifyListeners();
      } catch (error) {
        this.error = this.errorMessage(error);
        this.notifyListeners();
        throw new Error(this.error);
      }
    });
    return favorite;
  }

  async reload(): Promise<void> {
    if (!this.initialized) {
      await this.initialize();
      return;
    }
    await this.enqueue(async (): Promise<void> => {
      this.loading = true;
      this.notifyListeners();
      try {
        this.items = await this.repository.list();
        this.error = '';
      } catch (error) {
        this.error = this.errorMessage(error);
        this.notifyListeners();
        throw new Error(this.error);
      } finally {
        this.loading = false;
        this.notifyListeners();
      }
    });
  }

  private notifyListeners(): void {
    const listeners = this.listeners.slice();
    for (let index = 0; index < listeners.length; index++) {
      try {
        listeners[index]();
      } catch (_error) {
        // A stale page listener must not interrupt persistence operations.
      }
    }
  }

  private indexOf(contentKey: string): number {
    for (let index = 0; index < this.items.length; index++) {
      if (this.items[index].content.key === contentKey) {
        return index;
      }
    }
    return -1;
  }

  private enqueue(operation: () => Promise<void>): Promise<void> {
    const next = this.operationTail.then(operation, operation);
    this.operationTail = next.catch((): void => {
      // 队列尾保持可继续执行；具体错误仍由原始 Promise 交给调用方。
    });
    return next;
  }

  private errorMessage(error: Object): string {
    return error instanceof Error ? error.message : '收藏操作失败';
  }
}
