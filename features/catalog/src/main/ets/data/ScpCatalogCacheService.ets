import { common } from '@kit.AbilityKit';
import { ArkTSUtils } from '@kit.ArkTS';
import { relationalStore } from '@kit.ArkData';
import { ANOMICON_DATABASE_NAME } from 'anomiconbasic';

const TABLE_NAME: string = 'scp_catalog_series';
const CREATE_CATALOG_TABLE: string =
  'CREATE TABLE IF NOT EXISTS scp_catalog_series (' +
  'series_id TEXT PRIMARY KEY, json TEXT NOT NULL, parsed_at INTEGER NOT NULL)';

export class ScpStoredCatalog {
  readonly seriesId: string;
  readonly json: string;
  readonly parsedAt: number;

  constructor(seriesId: string, json: string, parsedAt: number) {
    this.seriesId = seriesId;
    this.json = json;
    this.parsedAt = parsedAt;
  }
}

type ScpCatalogListener = (catalog: ScpStoredCatalog) => void;

/** 系列索引的持久化派生缓存：先秒开，过期后由页面后台重验。 */
export class ScpCatalogCacheService {
  private store: relationalStore.RdbStore | undefined = undefined;
  private initialization: Promise<void> | undefined = undefined;
  private context: common.UIAbilityContext | undefined = undefined;
  private readonly operationLock: ArkTSUtils.locks.AsyncLock =
    new ArkTSUtils.locks.AsyncLock();
  private readonly listeners: Map<string, ScpCatalogListener[]> =
    new Map<string, ScpCatalogListener[]>();

  initialize(context: common.UIAbilityContext): Promise<void> {
    this.context = context;
    if (this.store !== undefined) {
      return Promise.resolve();
    }
    if (this.initialization !== undefined) {
      return this.initialization;
    }
    this.initialization = this.open(context);
    return this.initialization;
  }

  async get(seriesId: string): Promise<ScpStoredCatalog | undefined> {
    try {
      return await this.readNow(seriesId);
    } catch (error) {
      throw this.catalogError('读取', error);
    }
  }

  async put(catalog: ScpStoredCatalog): Promise<void> {
    let accepted: boolean = false;
    try {
      await this.enqueueOperation(async (): Promise<void> => {
        const store = await this.requireStore();
        // normal/force requests use separate inflight keys and can finish out
        // of order.  Never let an older source snapshot roll the durable
        // derived catalog back over a newer one.
        const previous = await this.readNow(catalog.seriesId);
        if (previous !== undefined && previous.parsedAt > catalog.parsedAt) {
          return;
        }
        const values: relationalStore.ValuesBucket = {
          'series_id': catalog.seriesId,
          'json': catalog.json,
          'parsed_at': catalog.parsedAt
        };
        const rowId = await store.insert(
          TABLE_NAME,
          values,
          relationalStore.ConflictResolution.ON_CONFLICT_REPLACE
        );
        if (rowId < 0) {
          throw new Error(`系列目录写入返回无效行号：${catalog.seriesId}`);
        }
        accepted = true;
      });
    } catch (error) {
      throw this.catalogError('写入', error);
    }
    if (accepted) {
      this.notifyUpdated(catalog);
    }
  }

  /** 同进程目录更新通知：搜索页无需定时轮询 RDB。 */
  subscribe(seriesId: string, listener: ScpCatalogListener): () => void {
    const current = this.listeners.get(seriesId) ?? [];
    if (current.indexOf(listener) < 0) {
      current.push(listener);
      this.listeners.set(seriesId, current);
    }
    return (): void => {
      const registered = this.listeners.get(seriesId);
      if (registered === undefined) {
        return;
      }
      const index = registered.indexOf(listener);
      if (index >= 0) {
        registered.splice(index, 1);
      }
      if (registered.length === 0) {
        this.listeners.delete(seriesId);
      }
    };
  }

  private notifyUpdated(catalog: ScpStoredCatalog): void {
    const registered = this.listeners.get(catalog.seriesId)?.slice() ?? [];
    for (let index = 0; index < registered.length; index++) {
      try {
        registered[index](catalog);
      } catch (error) {
        console.warn(
          `Notify catalog update failed: ${error instanceof Error ? error.message : 'unknown error'}`
        );
      }
    }
  }

  private async open(context: common.UIAbilityContext): Promise<void> {
    try {
      const store = await relationalStore.getRdbStore(context, {
        name: ANOMICON_DATABASE_NAME,
        securityLevel: relationalStore.SecurityLevel.S1,
        encrypt: false
      });
      await store.executeSql(CREATE_CATALOG_TABLE);
      this.store = store;
    } catch (error) {
      this.initialization = undefined;
      throw this.catalogError('初始化', error);
    }
  }

  private async readNow(seriesId: string): Promise<ScpStoredCatalog | undefined> {
    const store = await this.requireStore();
    const predicates = new relationalStore.RdbPredicates(TABLE_NAME);
    predicates.equalTo('series_id', seriesId);
    let resultSet: relationalStore.ResultSet | undefined = undefined;
    try {
      resultSet = await store.query(predicates, ['series_id', 'json', 'parsed_at']);
      if (!resultSet.goToFirstRow()) {
        return undefined;
      }
      return new ScpStoredCatalog(
        resultSet.getString(resultSet.getColumnIndex('series_id')),
        resultSet.getString(resultSet.getColumnIndex('json')),
        resultSet.getLong(resultSet.getColumnIndex('parsed_at'))
      );
    } finally {
      try {
        resultSet?.close();
      } catch (error) {
        console.warn(`Close catalog result set failed: ${error instanceof Error ? error.message : 'unknown error'}`);
      }
    }
  }

  private enqueueOperation(operation: () => Promise<void>): Promise<void> {
    try {
      return this.operationLock.lockAsync<void>(
        operation,
        ArkTSUtils.locks.AsyncLockMode.EXCLUSIVE
      );
    } catch (error) {
      return Promise.reject(error);
    }
  }

  private async requireStore(): Promise<relationalStore.RdbStore> {
    if (this.initialization !== undefined) {
      await this.initialization;
    }
    if (this.store === undefined && this.context !== undefined) {
      // Opening RDB is allowed to fail transiently (for example while the
      // ability is restoring).  Retry lazily on the next cache operation.
      await this.initialize(this.context);
    }
    if (this.store === undefined) {
      throw new Error('目录缓存尚未初始化');
    }
    return this.store;
  }

  private catalogError(operation: string, error: Object): Error {
    const message = error instanceof Error ? error.message : '未知数据库错误';
    return new Error(`目录缓存${operation}失败：${message}`);
  }
}
