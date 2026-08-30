import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';

const PREFERENCES_NAME: string = 'anomicon_search';
const HISTORY_KEY: string = 'catalog_search_history_native';
const MAX_HISTORY: number = 10;

interface SearchHistoryPreferenceValues {
  catalog_search_history_native?: preferences.ValueType;
}

/** 搜索历史：本地 preferences 持久化，最近 10 条、去重、可清空。 */
export class ScpSearchHistoryService {
  private store: preferences.Preferences | undefined = undefined;
  private context: common.UIAbilityContext | undefined = undefined;
  private items: string[] = [];
  private dirty: boolean = false;

  initialize(context: common.UIAbilityContext): void {
    this.context = context;
    if (this.store !== undefined) {
      return;
    }
    try {
      const store = preferences.getPreferencesSync(context, { name: PREFERENCES_NAME });
      this.store = store;
      if (!this.dirty) {
        const values = store.getAllSync() as SearchHistoryPreferenceValues;
        const stored = values.catalog_search_history_native;
        if (stored !== undefined) {
          this.items = this.itemsFromValue(stored);
        }
      } else {
        // Retry an edit that was kept in memory after a previous flush error.
        this.flush();
      }
    } catch (error) {
      this.store = undefined;
      // Keep the in-memory history intact.  Preferences may be temporarily
      // unavailable during ability startup; clearing it here would make a
      // recoverable read failure look like an intentional user clear.
      console.warn(`Initialize search history failed: ${error instanceof Error ? error.message : 'unknown error'}`);
    }
  }

  private itemsFromValue(value: preferences.ValueType | undefined): string[] {
    return Array.isArray(value) ? this.normalizeItems(value as string[]) : [];
  }

  list(): string[] {
    this.ensureInitialized();
    return this.items.slice();
  }

  add(query: string): void {
    this.ensureInitialized();
    const value = query.trim();
    if (value.length === 0) {
      return;
    }
    const index = this.items.indexOf(value);
    if (index >= 0) {
      this.items.splice(index, 1);
    }
    this.items.unshift(value);
    if (this.items.length > MAX_HISTORY) {
      this.items.length = MAX_HISTORY;
    }
    this.dirty = true;
    this.flush();
  }

  clear(): void {
    this.ensureInitialized();
    this.items = [];
    this.dirty = true;
    this.flush();
  }

  private ensureInitialized(): void {
    if (this.store === undefined && this.context !== undefined) {
      this.initialize(this.context);
    }
  }

  private normalizeItems(values: string[]): string[] {
    const normalized: string[] = [];
    for (const item of values) {
      if (typeof item !== 'string') {
        continue;
      }
      const value = item.trim();
      if (value.length === 0 || normalized.includes(value)) {
        continue;
      }
      normalized.push(value);
      if (normalized.length >= MAX_HISTORY) {
        break;
      }
    }
    return normalized;
  }

  private flush(): void {
    const store = this.store;
    if (store === undefined) {
      console.warn('Search history preferences unavailable; keeping changes in memory');
      return;
    }
    try {
      store.putSync(HISTORY_KEY, this.items.slice());
      // 历史最多 10 条且只在显式搜索/清空时写入；同步落盘可保证跳转后不丢失，
      // 也避免异步 flush 的拒绝逃出当前 try/catch。
      store.flushSync();
    } catch (error) {
      // Mark the handle unavailable so the next operation can reopen it.  The
      // dirty flag keeps pending in-memory edits from being overwritten by an
      // older persisted value during that retry.
      this.store = undefined;
      console.warn(`Flush search history failed: ${error instanceof Error ? error.message : 'unknown error'}`);
      return;
    }
    this.dirty = false;
  }
}
