import {
  CatalogEntry,
  CatalogParseResult,
  CatalogParser,
  CatalogTaleEntry,
  TaleParseResult
} from '../domain/CatalogContracts';
import {
  ScpCatalogPayload,
  TalePayload
} from '../domain/StaticCatalogContracts';
import {
  parseCatalogHtml,
  parseTaleHtml
} from './StaticCatalogParseTask';

/**
 * 旧静态解析器的窄化适配器。
 * TaskPool、解析器版本和 HTML 细节均停留在 data，application 只看领域结果。
 */
export class StaticParserAdapter implements CatalogParser {
  async parseCatalog(html: string): Promise<CatalogParseResult> {
    const payload: ScpCatalogPayload = await parseCatalogHtml(html);
    if (payload === undefined || payload === null || typeof payload !== 'object') {
      return {
        parserVersion: 0,
        ok: false,
        error: '目录解析结果不是对象',
        entries: []
      };
    }
    const entries: CatalogEntry[] = [];
    if (Array.isArray(payload.entries)) {
      for (let index: number = 0; index < payload.entries.length; index++) {
        const entry = payload.entries[index];
        if (entry === undefined || entry === null || typeof entry !== 'object' ||
          typeof entry.itemId !== 'string' || typeof entry.title !== 'string') {
          continue;
        }
        entries.push(new CatalogEntry(
          entry.itemId,
          entry.title,
          typeof entry.description === 'string' ? entry.description : ''
        ));
      }
    }
    return {
      parserVersion: typeof payload.parserVersion === 'number' ? payload.parserVersion : 0,
      ok: payload.ok === true,
      error: typeof payload.error === 'string' ? payload.error : '未知解析错误',
      entries: entries
    };
  }

  async parseTales(html: string): Promise<TaleParseResult> {
    const payload: TalePayload = await parseTaleHtml(html);
    if (payload === undefined || payload === null || typeof payload !== 'object') {
      return {
        parserVersion: 0,
        ok: false,
        error: '故事目录解析结果不是对象',
        tales: []
      };
    }
    const tales: CatalogTaleEntry[] = [];
    if (Array.isArray(payload.tales)) {
      for (let index: number = 0; index < payload.tales.length; index++) {
        const tale = payload.tales[index];
        if (tale === undefined || tale === null || typeof tale !== 'object' ||
          typeof tale.id !== 'string' || typeof tale.title !== 'string') {
          continue;
        }
        tales.push(new CatalogTaleEntry(tale.id, tale.title));
      }
    }
    return {
      parserVersion: typeof payload.parserVersion === 'number' ? payload.parserVersion : 0,
      ok: payload.ok === true,
      error: typeof payload.error === 'string' ? payload.error : '未知解析错误',
      tales: tales
    };
  }
}
