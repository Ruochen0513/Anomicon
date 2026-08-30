import {
  SCP_CATALOG_PARSER_VERSION,
  ScpCatalogPayload,
  ScpCatalogRawEntry,
  TALE_LIST_PARSER_VERSION,
  TalePayload,
  TaleRawEntry
} from '../domain/StaticCatalogContracts';

/**
 * 目录类页面的原生静态 HTML 解析器。
 *
 * 系列目录与故事索引均已包含在服务端 HTML 的 page-content 内，无需创建
 * 隐藏 ArkWeb。公开入口通过 TaskPool 执行，避免数千条链接的扫描与文本清理
 * 阻塞 UI 线程。
 */
export class StaticCatalogHtmlParser {
  static parseCatalog(html: string): ScpCatalogPayload {
    const entries: ScpCatalogRawEntry[] = [];
    try {
      const pageContent = StaticCatalogHtmlParser.pageContent(html);
      if (pageContent.length === 0) {
        return StaticCatalogHtmlParser.catalogFailure('page-content node not found');
      }
      const content = StaticCatalogHtmlParser.catalogPanel(pageContent);
      const lowerContent = content.toLowerCase();
      const seen: Set<string> = new Set();
      const linkPattern: RegExp = /<a\b[^>]*\bhref\s*=\s*(["'])([^"']*)\1[^>]*>([\s\S]*?)<\/a\s*>/gi;
      let match: RegExpExecArray | null = linkPattern.exec(content);
      while (match !== null) {
        const href = StaticCatalogHtmlParser.normalizeHref(match[2] as string);
        const id = href.startsWith('/') ? href.substring(1).toUpperCase() : '';
        if (/^SCP-\d{3,4}$/.test(id) && !seen.has(id)) {
          seen.add(id);
          const linkText = StaticCatalogHtmlParser.cleanText(match[3] as string);
          let title = StaticCatalogHtmlParser.stripIdPrefix(linkText, id);
          if (title.length === 0 && match.index !== undefined) {
            const linkEnd = match.index + match[0].length;
            const parentText = StaticCatalogHtmlParser.nearestParentText(
              content,
              lowerContent,
              match.index,
              linkEnd
            );
            title = StaticCatalogHtmlParser.stripIdPrefix(parentText, id);
          }
          entries.push({
            itemId: id,
            title: StaticCatalogHtmlParser.cleanCatalogTitle(title),
            description: ''
          });
        }
        match = linkPattern.exec(content);
      }
      if (entries.length === 0) {
        return StaticCatalogHtmlParser.catalogFailure('series entries not found');
      }
      return {
        parserVersion: SCP_CATALOG_PARSER_VERSION,
        ok: true,
        error: '',
        entries: entries
      };
    } catch (error) {
      const message = error instanceof Error ? error.message : 'unknown catalog parse error';
      return StaticCatalogHtmlParser.catalogFailure(message);
    }
  }

  static parseTales(html: string): TalePayload {
    const tales: TaleRawEntry[] = [];
    try {
      const content = StaticCatalogHtmlParser.pageContent(html);
      if (content.length === 0) {
        return StaticCatalogHtmlParser.taleFailure('page-content node not found');
      }
      const seen: Set<string> = new Set();
      const linkPattern: RegExp = /<a\b[^>]*\bhref\s*=\s*(["'])([^"']*)\1[^>]*>([\s\S]*?)<\/a\s*>/gi;
      let match: RegExpExecArray | null = linkPattern.exec(content);
      while (match !== null) {
        const href = StaticCatalogHtmlParser.normalizeHref(match[2] as string);
        const title = StaticCatalogHtmlParser.cleanText(match[3] as string);
        if (StaticCatalogHtmlParser.isTaleLink(href, title)) {
          const id = href.substring(1);
          if (!seen.has(id)) {
            seen.add(id);
            tales.push({ id: id, title: title });
          }
        }
        match = linkPattern.exec(content);
      }
      if (tales.length === 0) {
        return StaticCatalogHtmlParser.taleFailure('no tale links found');
      }
      // 保留旧列表按页面名排序的展示语义，同时把大列表排序留在线程池。
      tales.sort((left: TaleRawEntry, right: TaleRawEntry) => left.id.localeCompare(right.id));
      return {
        parserVersion: TALE_LIST_PARSER_VERSION,
        ok: true,
        error: '',
        tales: tales
      };
    } catch (error) {
      const message = error instanceof Error ? error.message : 'unknown tale parse error';
      return StaticCatalogHtmlParser.taleFailure(message);
    }
  }

  private static catalogFailure(message: string): ScpCatalogPayload {
    return {
      parserVersion: SCP_CATALOG_PARSER_VERSION,
      ok: false,
      error: message,
      entries: []
    };
  }

  private static taleFailure(message: string): TalePayload {
    return {
      parserVersion: TALE_LIST_PARSER_VERSION,
      ok: false,
      error: message,
      tales: []
    };
  }

  /** 只保留 page-content 正文，避免侧栏与页脚导航链接混入结果。 */
  private static pageContent(html: string): string {
    const marker = /<div\b[^>]*\bid\s*=\s*(["'])page-content\1[^>]*>/i.exec(html);
    if (marker === null || marker.index === undefined) {
      return '';
    }
    const start = marker.index + marker[0].length;
    const tail = html.substring(start);
    const endPatterns: RegExp[] = [
      /<div\b[^>]*\bclass\s*=\s*(["'])[^"']*\bpage-tags\b[^"']*\1[^>]*>/i,
      /<div\b[^>]*\bid\s*=\s*(["'])page-info-break\1[^>]*>/i,
      /<div\b[^>]*\bid\s*=\s*(["'])page-options-container\1[^>]*>/i
    ];
    let end = tail.length;
    for (let index: number = 0; index < endPatterns.length; index++) {
      const candidate = endPatterns[index].exec(tail);
      if (candidate !== null && candidate.index !== undefined && candidate.index < end) {
        end = candidate.index;
      }
    }
    return tail.substring(0, end);
  }

  /** 对齐旧 DOM 提取器：优先 .content-panel.series，再回退 .content-panel。 */
  private static catalogPanel(pageContent: string): string {
    const divPattern: RegExp = /<div\b[^>]*>/gi;
    let firstPanelStart = -1;
    let firstPanelEnd = -1;
    let match: RegExpExecArray | null = divPattern.exec(pageContent);
    while (match !== null) {
      const classMatch = /\bclass\s*=\s*(["'])([^"']*)\1/i.exec(match[0]);
      if (classMatch !== null) {
        const classNames = ` ${StaticCatalogHtmlParser.collapseSpace(classMatch[2] as string).toLowerCase()} `;
        if (classNames.indexOf(' content-panel ') >= 0) {
          const start = match.index === undefined ? 0 : match.index + match[0].length;
          if (classNames.indexOf(' series ') >= 0) {
            return StaticCatalogHtmlParser.balancedDivContent(pageContent, start);
          }
          if (firstPanelStart < 0) {
            firstPanelStart = start;
            firstPanelEnd = match.index === undefined ? 0 : match.index;
          }
        }
      }
      match = divPattern.exec(pageContent);
    }
    if (firstPanelStart >= 0) {
      const panel = StaticCatalogHtmlParser.balancedDivContent(pageContent, firstPanelStart);
      if (panel.length > 0) {
        return panel;
      }
      return pageContent.substring(firstPanelEnd);
    }
    return pageContent;
  }

  private static balancedDivContent(source: string, start: number): string {
    const tagPattern: RegExp = /<\/?div\b[^>]*>/gi;
    tagPattern.lastIndex = start;
    let depth = 1;
    let match: RegExpExecArray | null = tagPattern.exec(source);
    while (match !== null) {
      if (/^<\s*\/div/i.test(match[0])) {
        depth--;
        if (depth === 0) {
          return source.substring(start, match.index);
        }
      } else {
        depth++;
      }
      match = tagPattern.exec(source);
    }
    return source.substring(start);
  }

  /** 取链接最近的父元素文本，覆盖「链接只有编号、标题在相邻文本」的系列页结构。 */
  private static nearestParentText(
    source: string,
    lowerSource: string,
    linkStart: number,
    linkEnd: number
  ): string {
    const tags: string[] = ['span', 'li', 'p', 'td', 'div', 'h1', 'h2', 'h3', 'h4', 'h5', 'h6'];
    let bestStart = -1;
    let bestEnd = -1;
    for (let index: number = 0; index < tags.length; index++) {
      const tag = tags[index];
      const open = lowerSource.lastIndexOf(`<${tag}`, linkStart);
      if (open < 0 || open < bestStart ||
        !StaticCatalogHtmlParser.isTagBoundary(lowerSource, open + tag.length + 1)) {
        continue;
      }
      const closedBeforeLink = lowerSource.lastIndexOf(`</${tag}`, linkStart);
      if (closedBeforeLink > open) {
        continue;
      }
      const close = lowerSource.indexOf(`</${tag}`, linkEnd);
      if (close < linkEnd || close - open > 4096) {
        continue;
      }
      bestStart = open;
      bestEnd = close;
    }
    if (bestStart < 0 || bestEnd <= bestStart) {
      const end = Math.min(source.length, linkEnd + 512);
      return StaticCatalogHtmlParser.cleanText(source.substring(linkStart, end));
    }
    return StaticCatalogHtmlParser.cleanText(source.substring(bestStart, bestEnd));
  }

  private static isTagBoundary(source: string, index: number): boolean {
    if (index >= source.length) {
      return true;
    }
    const value = source.charAt(index);
    return value === '>' || value === '/' || /\s/.test(value);
  }

  private static stripIdPrefix(value: string, id: string): string {
    const index = value.toUpperCase().indexOf(id);
    return index < 0 ? value : value.substring(index + id.length);
  }

  private static cleanCatalogTitle(value: string): string {
    return value
      .replace(/^[\s\-–—:：'"‘’“”\[（(]+/, '')
      .replace(/\[[^\]]*\]\s*$/g, '')
      .replace(/[\s\-–—:：'"‘’“”\]）)]+$/, '')
      .trim();
  }

  /** 保留既有故事索引的导航过滤语义。 */
  private static isTaleLink(href: string, title: string): boolean {
    if (title.length < 2 || href.length < 2 || !href.startsWith('/')) {
      return false;
    }
    const lowerHref = href.toLowerCase();
    if (lowerHref.startsWith('/system:') || lowerHref.startsWith('/_')) {
      return false;
    }
    return lowerHref.indexOf('tales-by') < 0 &&
      !lowerHref.startsWith('/tale') &&
      lowerHref.indexOf('foundation-tales') < 0 &&
      lowerHref.indexOf('canon') < 0 &&
      !lowerHref.startsWith('/user:');
  }

  private static normalizeHref(value: string): string {
    const decoded = StaticCatalogHtmlParser.decodeEntities(value).trim();
    const hash = decoded.indexOf('#');
    return (hash >= 0 ? decoded.substring(0, hash) : decoded).trim();
  }

  private static cleanText(value: string): string {
    const withoutMarkup = value
      .replace(/<(script|style)\b[\s\S]*?<\/\1>/gi, ' ')
      .replace(/<!--[\s\S]*?-->/g, ' ')
      .replace(/<[^>]+>/g, ' ');
    return StaticCatalogHtmlParser.collapseSpace(
      StaticCatalogHtmlParser.decodeEntities(withoutMarkup)
    ).trim();
  }

  private static decodeEntities(value: string): string {
    return value
      .replace(/&amp;/gi, '&')
      .replace(/&nbsp;|&#160;|&ensp;|&emsp;|&thinsp;/gi, ' ')
      .replace(/&lt;/gi, '<')
      .replace(/&gt;/gi, '>')
      .replace(/&quot;|&#34;/gi, '"')
      .replace(/&#39;|&apos;/gi, '\'')
      .replace(/&ndash;/gi, '–')
      .replace(/&mdash;/gi, '—')
      .replace(/&minus;/gi, '−')
      .replace(/&lsquo;/gi, '‘')
      .replace(/&rsquo;/gi, '’')
      .replace(/&ldquo;/gi, '“')
      .replace(/&rdquo;/gi, '”')
      .replace(/&hellip;/gi, '…')
      .replace(/&middot;/gi, '·')
      .replace(/&bull;/gi, '•')
      .replace(/&laquo;/gi, '«')
      .replace(/&raquo;/gi, '»')
      .replace(/&#x([0-9a-f]+);/gi, (_whole: string, hex: string): string =>
        StaticCatalogHtmlParser.codePointText(parseInt(hex, 16)))
      .replace(/&#(\d+);/g, (_whole: string, decimal: string): string =>
        StaticCatalogHtmlParser.codePointText(parseInt(decimal, 10)));
  }

  private static collapseSpace(value: string): string {
    return value.replace(/\s+/g, ' ');
  }

  private static codePointText(value: number): string {
    if (!Number.isFinite(value) || value <= 0 || value > 0x10FFFF) {
      return '';
    }
    return String.fromCodePoint(value);
  }
}
