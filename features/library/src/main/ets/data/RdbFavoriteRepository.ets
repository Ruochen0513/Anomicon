import { common } from '@kit.AbilityKit';
import { relationalStore } from '@kit.ArkData';
import { ArkTSUtils } from '@kit.ArkTS';
import { ANOMICON_DATABASE_NAME } from 'anomiconbasic';
import {
  LibraryContentKind,
  LibraryContentRef,
  LibraryFavorite,
  parseLibraryContentKind
} from '../domain/LibraryContentRef';
import { FavoriteRepository } from '../domain/LibraryRepositories';

const TABLE_NAME: string = 'library_favorites';
const CREATE_TABLE: string =
  'CREATE TABLE IF NOT EXISTS library_favorites (' +
  'content_key TEXT PRIMARY KEY, content_id TEXT NOT NULL, title TEXT NOT NULL, ' +
  'content_kind TEXT NOT NULL, favorited_at INTEGER NOT NULL)';
const CREATE_TIME_INDEX: string =
  'CREATE INDEX IF NOT EXISTS idx_library_favorites_time ' +
  'ON library_favorites(favorited_at DESC, content_key ASC)';

/** 初始化迁移使用的数据库原始行；storedKey 可能仍是旧版 kind:id。 */
class StoredFavoriteMigrationRow {
  readonly storedKey: string;
  readonly content: LibraryContentRef;
  readonly favoritedAt: number;

  constructor(storedKey: string, content: LibraryContentRef, favoritedAt: number) {
    this.storedKey = storedKey;
    this.content = content;
    this.favoritedAt = favoritedAt;
  }
}

/** 收藏持久化：单表存储，并串行化所有写操作，避免快速双击产生读改写竞态。 */
export class RdbFavoriteRepository implements FavoriteRepository {
  private readonly context: common.UIAbilityContext;
  private store: relationalStore.RdbStore | undefined = undefined;
  private initialization: Promise<void> | undefined = undefined;
  private readonly operationLock: ArkTSUtils.locks.AsyncLock =
    new ArkTSUtils.locks.AsyncLock();

  constructor(context: common.UIAbilityContext) {
    this.context = context;
  }

  /** Opens the feature-owned store; repeated calls share one task. */
  public initialize(): Promise<void> {
    if (this.initialization !== undefined) {
      return this.initialization;
    }
    this.initialization = this.open(this.context);
    return this.initialization;
  }

  /** 按收藏时间倒序读取快照；同毫秒写入时用稳定主键确定顺序。 */
  async list(): Promise<LibraryFavorite[]> {
    return this.operationLock.lockAsync<LibraryFavorite[]>(
      (): Promise<LibraryFavorite[]> => this.listNow(),
      ArkTSUtils.locks.AsyncLockMode.SHARED
    );
  }

  /**
   * 在写队列中重新读取当前值后翻转，连续两次调用必定得到相反结果，
   * 不依赖调用方可能尚未刷新的 UI 状态。
   */
  async toggle(content: LibraryContentRef): Promise<boolean> {
    let favorite = false;
    await this.enqueueMutation(async (): Promise<void> => {
      favorite = !(await this.containsNow(content.key));
      await this.setFavoriteNow(content, favorite);
    });
    return favorite;
  }

  /** 幂等设置收藏状态，返回写入后的状态。 */
  async setFavorite(content: LibraryContentRef, favorite: boolean): Promise<boolean> {
    await this.enqueueMutation(async (): Promise<void> => {
      await this.setFavoriteNow(content, favorite);
    });
    return favorite;
  }

  private async listNow(): Promise<LibraryFavorite[]> {
    const store = await this.requireStore();
    const predicates = new relationalStore.RdbPredicates(TABLE_NAME);
    predicates.orderByDesc('favorited_at');
    predicates.orderByAsc('content_key');
    let resultSet: relationalStore.ResultSet | undefined = undefined;
    const favorites: LibraryFavorite[] = [];
    try {
      resultSet = await store.query(predicates, [
        'content_id',
        'title',
        'content_kind',
        'favorited_at'
      ]);
      while (resultSet.goToNextRow()) {
        const kindValue = resultSet.getString(resultSet.getColumnIndex('content_kind'));
        const kind = parseLibraryContentKind(kindValue);
        if (kind === undefined) {
          continue;
        }
        try {
          const content = new LibraryContentRef(
            kind,
            resultSet.getString(resultSet.getColumnIndex('content_id')),
            resultSet.getString(resultSet.getColumnIndex('title'))
          );
          favorites.push(new LibraryFavorite(
            content,
            resultSet.getLong(resultSet.getColumnIndex('favorited_at'))
          ));
        } catch (error) {
          // 单条历史脏数据不应阻断其他收藏的展示。
        }
      }
      return favorites;
    } catch (error) {
      throw this.favoriteError('读取', error);
    } finally {
      try {
        resultSet?.close();
      } catch (error) {
        console.warn(`Close favorite result set failed: ${error instanceof Error ? error.message : 'unknown error'}`);
      }
    }
  }

  private async containsNow(contentKey: string): Promise<boolean> {
    const store = await this.requireStore();
    const predicates = new relationalStore.RdbPredicates(TABLE_NAME);
    predicates.equalTo('content_key', contentKey);
    predicates.limitAs(1);
    let resultSet: relationalStore.ResultSet | undefined = undefined;
    try {
      resultSet = await store.query(predicates, ['content_key']);
      return resultSet.goToFirstRow();
    } catch (error) {
      throw this.favoriteError('查询', error);
    } finally {
      try {
        resultSet?.close();
      } catch (error) {
        console.warn(`Close favorite lookup failed: ${error instanceof Error ? error.message : 'unknown error'}`);
      }
    }
  }

  private async setFavoriteNow(content: LibraryContentRef, favorite: boolean): Promise<void> {
    const store = await this.requireStore();
    try {
      if (!favorite) {
        const predicates = new relationalStore.RdbPredicates(TABLE_NAME);
        predicates.equalTo('content_key', content.key);
        const deleted = await store.delete(predicates);
        if (deleted < 0) {
          throw new Error(`删除收藏失败：${content.key}`);
        }
        return;
      }
      const values: relationalStore.ValuesBucket = {
        'content_key': content.key,
        'content_id': content.id,
        'title': content.title,
        'content_kind': content.kind,
        'favorited_at': Date.now()
      };
      const rowId = await store.insert(
        TABLE_NAME,
        values,
        relationalStore.ConflictResolution.ON_CONFLICT_REPLACE
      );
      if (rowId < 0) {
        throw new Error(`写入收藏失败：${content.key}`);
      }
    } catch (error) {
      throw this.favoriteError(favorite ? '写入' : '删除', error);
    }
  }

  private enqueueMutation(operation: () => Promise<void>): Promise<void> {
    return this.operationLock.lockAsync<void>(
      operation,
      ArkTSUtils.locks.AsyncLockMode.EXCLUSIVE
    );
  }

  private async open(context: common.UIAbilityContext): Promise<void> {
    try {
      const store = await relationalStore.getRdbStore(context, {
        name: ANOMICON_DATABASE_NAME,
        securityLevel: relationalStore.SecurityLevel.S1,
        encrypt: false
      });
      await store.executeSql(CREATE_TABLE);
      await store.executeSql(CREATE_TIME_INDEX);
      // Finish the key migration before exposing the repository.  Keeping this
      // in the open transaction path makes the new canonical identity the only
      // shape visible to callers after initialization.
      await this.migrateLegacyContentKeys(store);
      this.store = store;
    } catch (error) {
      this.initialization = undefined;
      throw this.favoriteError('初始化', error);
    }
  }

  /**
   * 旧版主键包含入口分类（scp:/tale:/wiki:/knowledge:）。同一主站 slug
   * 可能因此存在多条收藏。迁移先写入合并后的 main:slug，再删除旧行；任一步
   * 中断都不会丢失收藏，下一次初始化可安全重试。
   */
  private async migrateLegacyContentKeys(store: relationalStore.RdbStore): Promise<void> {
    const rows = await this.readFavoriteMigrationRows(store);
    const mergedRows: StoredFavoriteMigrationRow[] = [];
    const mergedIndexes: Map<string, number> = new Map<string, number>();
    const migrationRows: StoredFavoriteMigrationRow[] = [];

    for (let index = 0; index < rows.length; index++) {
      const row = rows[index];
      const canonicalKey = row.content.key;
      const mergedIndex = mergedIndexes.get(canonicalKey);
      if (mergedIndex === undefined) {
        mergedIndexes.set(canonicalKey, mergedRows.length);
        mergedRows.push(row);
      } else if (this.preferFavoriteMigrationRow(mergedRows[mergedIndex], row)) {
        mergedRows[mergedIndex] = row;
      }
      if (row.storedKey !== canonicalKey) {
        migrationRows.push(row);
      }
    }
    if (migrationRows.length === 0) {
      return;
    }

    try {
      // 重复收藏保留最近一次收藏的时间与对应元数据，保持“最近收藏”排序语义。
      for (let index = 0; index < mergedRows.length; index++) {
        const row = mergedRows[index];
        const values: relationalStore.ValuesBucket = {
          'content_key': row.content.key,
          'content_id': row.content.id,
          'title': row.content.title,
          'content_kind': row.content.kind,
          'favorited_at': row.favoritedAt
        };
        const rowId = await store.insert(
          TABLE_NAME,
          values,
          relationalStore.ConflictResolution.ON_CONFLICT_REPLACE
        );
        if (rowId < 0) {
          throw new Error(`写入统一收藏主键失败：${row.content.key}`);
        }
      }
      for (let index = 0; index < migrationRows.length; index++) {
        const predicates = new relationalStore.RdbPredicates(TABLE_NAME);
        predicates.equalTo('content_key', migrationRows[index].storedKey);
        const deleted = await store.delete(predicates);
        if (deleted < 0) {
          throw new Error(`删除旧收藏主键失败：${migrationRows[index].storedKey}`);
        }
      }
    } catch (error) {
      throw this.favoriteError('主键迁移', error);
    }
  }

  private async readFavoriteMigrationRows(
    store: relationalStore.RdbStore
  ): Promise<StoredFavoriteMigrationRow[]> {
    const predicates = new relationalStore.RdbPredicates(TABLE_NAME);
    let resultSet: relationalStore.ResultSet | undefined = undefined;
    const rows: StoredFavoriteMigrationRow[] = [];
    try {
      resultSet = await store.query(predicates, [
        'content_key',
        'content_id',
        'title',
        'content_kind',
        'favorited_at'
      ]);
      while (resultSet.goToNextRow()) {
        const kindValue = resultSet.getString(resultSet.getColumnIndex('content_kind'));
        const kind: LibraryContentKind | undefined = parseLibraryContentKind(kindValue);
        if (kind === undefined) {
          continue;
        }
        try {
          rows.push(new StoredFavoriteMigrationRow(
            resultSet.getString(resultSet.getColumnIndex('content_key')),
            new LibraryContentRef(
              kind,
              resultSet.getString(resultSet.getColumnIndex('content_id')),
              resultSet.getString(resultSet.getColumnIndex('title'))
            ),
            resultSet.getLong(resultSet.getColumnIndex('favorited_at'))
          ));
        } catch (error) {
          // 无法规范化的脏行原样保留，不用迁移失败换取数据丢失。
        }
      }
      return rows;
    } catch (error) {
      throw this.favoriteError('迁移读取', error);
    } finally {
      try {
        resultSet?.close();
      } catch (error) {
        console.warn(
          `Close favorite Migration result set failed: ${error instanceof Error ? error.message : 'unknown error'}`
        );
      }
    }
  }

  private preferFavoriteMigrationRow(
    current: StoredFavoriteMigrationRow,
    candidate: StoredFavoriteMigrationRow
  ): boolean {
    if (candidate.favoritedAt !== current.favoritedAt) {
      return candidate.favoritedAt > current.favoritedAt;
    }
    const currentCanonical = current.storedKey === current.content.key;
    const candidateCanonical = candidate.storedKey === candidate.content.key;
    if (currentCanonical !== candidateCanonical) {
      return candidateCanonical;
    }
    return candidate.storedKey.localeCompare(current.storedKey) < 0;
  }

  private async requireStore(): Promise<relationalStore.RdbStore> {
    await this.initialize();
    if (this.store === undefined) {
      throw new Error('收藏存储尚未初始化');
    }
    return this.store;
  }

  private favoriteError(operation: string, error: Object): Error {
    const message = error instanceof Error ? error.message : '未知数据库错误';
    return new Error(`收藏${operation}失败：${message}`);
  }
}
