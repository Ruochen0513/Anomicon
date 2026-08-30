import { common } from '@kit.AbilityKit';
import { relationalStore } from '@kit.ArkData';
import { ANOMICON_DATABASE_NAME } from 'anomiconbasic';
import { ArticleViewStatePort } from '../domain/ArticleContracts';

const TABLE_NAME: string = 'scp_reading_progress';
const CREATE_TABLE: string =
  'CREATE TABLE IF NOT EXISTS scp_reading_progress (' +
  'item_id TEXT PRIMARY KEY, expanded_json TEXT NOT NULL DEFAULT \'\', ' +
  'updated_at INTEGER NOT NULL)';
const ADD_EXPANDED_JSON_COLUMN: string =
  'ALTER TABLE scp_reading_progress ADD COLUMN expanded_json TEXT NOT NULL DEFAULT \'\'';
const ADD_UPDATED_AT_COLUMN: string =
  'ALTER TABLE scp_reading_progress ADD COLUMN updated_at INTEGER NOT NULL DEFAULT 0';
const MAX_EXPANDED_KEYS: number = 512;
const MAX_EXPANDED_KEY_LENGTH: number = 256;

class StoredArticleViewState {
  readonly expandedKeys: string[];
  constructor(expandedKeys: string[]) {
    this.expandedKeys = expandedKeys;
  }
}

/** 文章界面状态的 RDB 实现。阅读进度统一由 Library 历史仓储负责。 */
export class ArticleViewStateRepo implements ArticleViewStatePort {
  private readonly context: common.UIAbilityContext;
  private store: relationalStore.RdbStore | undefined = undefined;
  /** Old releases used this NOT NULL column for scroll progress. */
  private hasLegacyScrollOffset: boolean = false;
  private initialization: Promise<void> | undefined = undefined;
  private mutationTail: Promise<void> = Promise.resolve();

  constructor(context: common.UIAbilityContext) {
    this.context = context;
  }

  async read(articleId: string): Promise<string[]> {
    const state = await this.get(articleId);
    return state?.expandedKeys.slice() ?? [];
  }

  private async get(articleId: string): Promise<StoredArticleViewState | undefined> {
    await this.mutationTail;
    return this.getNow(articleId);
  }

  async save(articleId: string, expandedKeys: string[]): Promise<void> {
    const snapshot = expandedKeys.slice();
    await this.enqueueMutation(async (): Promise<void> => {
      const store = await this.requireStore();
      const values: relationalStore.ValuesBucket = {
        'item_id': articleId,
        'expanded_json': JSON.stringify(snapshot),
        'updated_at': Date.now()
      };
      // Keep inserts valid against an upgraded legacy table whose
      // `scroll_offset` column is still NOT NULL and has no default.  Reading
      // progress now belongs to Library; zero is only a compatibility value.
      if (this.hasLegacyScrollOffset) {
        values['scroll_offset'] = 0;
      }
      try {
        const rowId = await store.insert(
          TABLE_NAME,
          values,
          relationalStore.ConflictResolution.ON_CONFLICT_REPLACE
        );
        if (rowId < 0) {
          throw new Error(`写入文章界面状态失败：${articleId}`);
        }
      } catch (error) {
        throw this.stateError('写入', error);
      }
    });
  }

  private async getNow(articleId: string): Promise<StoredArticleViewState | undefined> {
    const store = await this.requireStore();
    const predicates = new relationalStore.RdbPredicates(TABLE_NAME);
    predicates.equalTo('item_id', articleId);
    let resultSet: relationalStore.ResultSet | undefined = undefined;
    try {
      resultSet = await store.query(predicates, ['item_id', 'expanded_json']);
      if (!resultSet.goToFirstRow()) {
        return undefined;
      }
      return new StoredArticleViewState(
        this.parseExpanded(resultSet.getString(resultSet.getColumnIndex('expanded_json')))
      );
    } catch (error) {
      throw this.stateError('读取', error);
    } finally {
      try {
        resultSet?.close();
      } catch (error) {
        console.warn(
          `Close article state result set failed: ${error instanceof Error ? error.message : 'unknown error'}`
        );
      }
    }
  }

  private parseExpanded(json: string): string[] {
    if (json.length === 0) {
      return [];
    }
    try {
      const parsed = JSON.parse(json) as Object[];
      if (!Array.isArray(parsed)) {
        return [];
      }
      const keys: string[] = [];
      const seen: Set<string> = new Set<string>();
      for (let index = 0; index < parsed.length && keys.length < MAX_EXPANDED_KEYS; index++) {
        const value = parsed[index];
        if (typeof value !== 'string') {
          continue;
        }
        const key = value.trim();
        if (key.length === 0 || key.length > MAX_EXPANDED_KEY_LENGTH || seen.has(key)) {
          continue;
        }
        seen.add(key);
        keys.push(key);
      }
      return keys;
    } catch (error) {
      return [];
    }
  }

  private enqueueMutation(operation: () => Promise<void>): Promise<void> {
    const next = this.mutationTail.then(operation, operation);
    this.mutationTail = next.catch((): void => {
      // 单次失败不阻断后续文章界面状态写入。
    });
    return next;
  }

  private initialize(): Promise<void> {
    if (this.initialization !== undefined) {
      return this.initialization;
    }
    this.initialization = this.open();
    return this.initialization;
  }

  private async open(): Promise<void> {
    try {
      const store = await relationalStore.getRdbStore(this.context, {
        name: ANOMICON_DATABASE_NAME,
        securityLevel: relationalStore.SecurityLevel.S1,
        encrypt: false
      });
      await store.executeSql(CREATE_TABLE);
      await this.ensureSchema(store);
      this.store = store;
    } catch (error) {
      this.initialization = undefined;
      throw this.stateError('初始化', error);
    }
  }

  private async requireStore(): Promise<relationalStore.RdbStore> {
    await this.initialize();
    if (this.store === undefined) {
      throw new Error('文章界面状态存储尚未初始化');
    }
    return this.store;
  }

  /**
   * `CREATE TABLE IF NOT EXISTS` does not alter the pre-existing table used by
   * the first article implementation (which only had `item_id` and
   * `scroll_offset`).  Add the current fold-state columns before any query or
   * write so an upgrade cannot fail with "column not found".
   */
  private async ensureSchema(store: relationalStore.RdbStore): Promise<void> {
    const columns: Set<string> = new Set<string>();
    let resultSet: relationalStore.ResultSet | undefined = undefined;
    try {
      resultSet = await store.querySql(`PRAGMA table_info(${TABLE_NAME})`);
      while (resultSet.goToNextRow()) {
        columns.add(resultSet.getString(resultSet.getColumnIndex('name')));
      }
    } catch (error) {
      throw this.stateError('检查表结构', error);
    } finally {
      try {
        resultSet?.close();
      } catch (error) {
        console.warn(
          `Close article state schema result set failed: ${error instanceof Error ? error.message : 'unknown error'}`
        );
      }
    }
    if (!columns.has('expanded_json')) {
      try {
        await store.executeSql(ADD_EXPANDED_JSON_COLUMN);
      } catch (error) {
        throw this.stateError('升级表结构', error);
      }
    }
    if (!columns.has('updated_at')) {
      try {
        await store.executeSql(ADD_UPDATED_AT_COLUMN);
      } catch (error) {
        throw this.stateError('升级表结构', error);
      }
    }
    this.hasLegacyScrollOffset = columns.has('scroll_offset');
  }

  private stateError(operation: string, error: Object): Error {
    const message = error instanceof Error ? error.message : '未知数据库错误';
    return new Error(`文章界面状态${operation}失败：${message}`);
  }
}
