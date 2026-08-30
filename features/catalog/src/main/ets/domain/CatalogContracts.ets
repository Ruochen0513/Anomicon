/**
 * 目录读取来源。`fetchedAt` 始终来自原始 HTML 的抓取时间，不能用解析时间
 * 伪造新鲜度；STALE_CACHE 仍可展示，但必须继续标记为过期。
 */
export enum CatalogSnapshotSource {
  CACHE = 'cache',
  NETWORK = 'network',
  STALE_CACHE = 'stale_cache'
}

/** 目录条目的领域值对象。预览图属于派生数据，不放进该契约。 */
export class CatalogEntry {
  readonly itemId: string;
  readonly title: string;
  readonly description: string;

  constructor(itemId: string, title: string, description: string = '') {
    this.itemId = itemId;
    this.title = title;
    this.description = description;
  }
}

/** 系列目录读取快照，供 ViewModel 处理 fresh/stale/partial/error 语义。 */
export class CatalogSnapshot {
  readonly seriesId: string;
  readonly entries: CatalogEntry[];
  readonly source: CatalogSnapshotSource;
  readonly fetchedAt: number;
  readonly stale: boolean;
  readonly partial: boolean;
  readonly parserVersion: number;
  readonly error: string;

  constructor(
    seriesId: string,
    entries: CatalogEntry[],
    source: CatalogSnapshotSource,
    fetchedAt: number,
    stale: boolean = false,
    partial: boolean = false,
    parserVersion: number = 0,
    error: string = ''
  ) {
    this.seriesId = seriesId;
    this.entries = entries.slice();
    this.source = source;
    this.fetchedAt = fetchedAt;
    this.stale = stale;
    this.partial = partial;
    this.parserVersion = parserVersion;
    this.error = error;
  }
}

/** 故事目录条目。id 为主站路径名，title 为页面展示名称。 */
export class CatalogTaleEntry {
  readonly id: string;
  readonly title: string;

  constructor(id: string, title: string) {
    this.id = id;
    this.title = title;
  }
}

/** 故事列表读取快照。 */
export class TaleSnapshot {
  readonly tales: CatalogTaleEntry[];
  readonly source: CatalogSnapshotSource;
  readonly fetchedAt: number;
  readonly stale: boolean;
  readonly partial: boolean;
  readonly parserVersion: number;
  readonly error: string;

  constructor(
    tales: CatalogTaleEntry[],
    source: CatalogSnapshotSource,
    fetchedAt: number,
    stale: boolean = false,
    partial: boolean = false,
    parserVersion: number = 0,
    error: string = ''
  ) {
    this.tales = tales.slice();
    this.source = source;
    this.fetchedAt = fetchedAt;
    this.stale = stale;
    this.partial = partial;
    this.parserVersion = parserVersion;
    this.error = error;
  }
}

/** 卡片预览值对象；下载、图片安全校验和 RDB 均隐藏在 Data adapter。 */
export class CatalogPreview {
  readonly path: string;
  readonly aspect: number;
  readonly description: string;
  readonly url: string;
  readonly fetchedAt: number;
  readonly stale: boolean;
  /** 非空表示 HTML/网络阶段失败；空图本身仍是合法的无图结果。 */
  readonly error: string;
  readonly failed: boolean;

  constructor(
    path: string,
    aspect: number,
    description: string = '',
    url: string = '',
    fetchedAt: number = 0,
    stale: boolean = false,
    error: string = ''
  ) {
    this.path = path;
    this.aspect = aspect;
    this.description = description;
    this.url = url;
    this.fetchedAt = fetchedAt;
    this.stale = stale;
    this.error = error;
    this.failed = error.trim().length > 0;
  }
}

/** 目录解析器端口；具体 TaskPool/HTML 实现留在 data。 */
export interface CatalogParser {
  parseCatalog(html: string): Promise<CatalogParseResult>;
  parseTales(html: string): Promise<TaleParseResult>;
}

export interface CatalogParseResult {
  parserVersion: number;
  ok: boolean;
  error: string;
  entries: CatalogEntry[];
}

export interface TaleParseResult {
  parserVersion: number;
  ok: boolean;
  error: string;
  tales: CatalogTaleEntry[];
}

export function normalizeCatalogItemId(value: string): string {
  return value.trim().toUpperCase();
}
