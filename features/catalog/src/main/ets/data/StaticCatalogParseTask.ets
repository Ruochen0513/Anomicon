import { taskpool } from '@kit.ArkTS';
import {
  SCP_CATALOG_PARSER_VERSION,
  ScpCatalogPayload,
  TALE_LIST_PARSER_VERSION,
  TalePayload
} from '../domain/StaticCatalogContracts';
import { StaticCatalogHtmlParser } from './StaticCatalogHtmlParser';

// @Concurrent 函数只引用导入变量与局部变量，满足 TaskPool 的并发函数约束。
@Concurrent
function parseCatalogHtmlTask(html: string): string {
  return JSON.stringify(StaticCatalogHtmlParser.parseCatalog(html));
}

@Concurrent
function parseTaleHtmlTask(html: string): string {
  return JSON.stringify(StaticCatalogHtmlParser.parseTales(html));
}

/** 在线程池解析系列目录，返回可直接进入现有派生缓存的数据契约。 */
export async function parseCatalogHtml(html: string): Promise<ScpCatalogPayload> {
  try {
    // 目录是首屏数据；复用系统线程池并提高优先级，避免新建 Worker 的启动开销。
    const task = new taskpool.GenericsTask<[string], string>(parseCatalogHtmlTask, html);
    const json = await taskpool.execute<[string], string>(task, taskpool.Priority.HIGH);
    return JSON.parse(json) as ScpCatalogPayload;
  } catch (error) {
    const message = error instanceof Error ? error.message : 'unknown TaskPool error';
    return { parserVersion: SCP_CATALOG_PARSER_VERSION, ok: false, error: message, entries: [] };
  }
}

/** 在线程池解析故事索引，返回可直接进入现有派生缓存的数据契约。 */
export async function parseTaleHtml(html: string): Promise<TalePayload> {
  try {
    const json = await taskpool.execute<[string], string>(parseTaleHtmlTask, html);
    return JSON.parse(json) as TalePayload;
  } catch (error) {
    const message = error instanceof Error ? error.message : 'unknown TaskPool error';
    return { parserVersion: TALE_LIST_PARSER_VERSION, ok: false, error: message, tales: [] };
  }
}
