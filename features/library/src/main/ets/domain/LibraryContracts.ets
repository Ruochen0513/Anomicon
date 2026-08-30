import { LibraryContentRef } from './LibraryContentRef';

/** 资料库全量页模式；页面只依赖此领域值，不依赖 navigation。 */
export enum LibraryCollectionMode {
  FAVORITES = 'favorites',
  CONTINUE_READING = 'continue_reading',
  RECENT = 'recent'
}

/** 用于 LazyForEach 的轻量投影，不泄漏数据库记录。 */
export class LibraryCollectionItem {
  readonly content: LibraryContentRef;
  readonly timestamp: number;

  constructor(content: LibraryContentRef, timestamp: number) {
    this.content = content;
    this.timestamp = timestamp;
  }
}

/** 将产品路由字符串收窄为资料库模式；未知值交由页面展示错误。 */
export function parseLibraryCollectionMode(value: string | undefined): LibraryCollectionMode | undefined {
  switch (value) {
    case LibraryCollectionMode.FAVORITES:
      return LibraryCollectionMode.FAVORITES;
    case LibraryCollectionMode.CONTINUE_READING:
      return LibraryCollectionMode.CONTINUE_READING;
    case LibraryCollectionMode.RECENT:
      return LibraryCollectionMode.RECENT;
    default:
      return undefined;
  }
}
