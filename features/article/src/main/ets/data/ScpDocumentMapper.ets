import {
  ScpArticleDocument,
  ScpBlockType,
  ScpContentBlock,
  ScpFootnote,
  ScpTextSpan,
  ScpTextStyle
} from '../domain/ScpDocument';

interface RawSpan {
  s: string;
  t: string;
  u?: string;
  r?: string;
}

interface RawBlock {
  k: string;
  spans?: RawSpan[];
  level?: number;
  title?: string;
  blocks?: RawBlock[];
  src?: string;
  caption?: string;
}

interface RawImage {
  src: string;
  caption: string;
}

interface RawFootnote {
  id: string;
  index: number;
  blocks: RawBlock[];
}

interface PayloadValidationBudget {
  blockCount: number;
  spanCount: number;
}

const MAX_PAYLOAD_STRING_LENGTH: number = 1024 * 1024;
const MAX_PAYLOAD_TAGS: number = 512;
const MAX_PAYLOAD_IMAGES: number = 512;
const MAX_PAYLOAD_FOOTNOTES: number = 512;
const MAX_PAYLOAD_WARNINGS: number = 512;
const MAX_PAYLOAD_BLOCKS: number = 8192;
const MAX_PAYLOAD_SPANS: number = 32768;
const MAX_PAYLOAD_DEPTH: number = 32;

export interface ScpExtractPayload {
  parserVersion: number;
  ok: boolean;
  error: string;
  title: string;
  rating: string;
  pageVersion: string;
  tags: string[];
  images: RawImage[];
  blocks: RawBlock[];
  footnotes: RawFootnote[];
  warnings: string[];
}

/** 把 ArkWeb 提取脚本的输出投影为正式文档模型。 */
export class ScpDocumentMapper {
  toDocument(
    payload: ScpExtractPayload,
    sourceUrl: string,
    fetchedAt: number,
  ): ScpArticleDocument {
    const contractError = this.validatePayloadInternal(payload);
    if (contractError.length > 0) {
      throw new Error(contractError);
    }
    const itemId = this.itemIdOf(sourceUrl);
    const images: ScpContentBlock[] = [];
    for (let index: number = 0; index < payload.images.length; index++) {
      const image = payload.images[index];
      images.push(new ScpContentBlock(
        `${itemId}:image:${index}`,
        ScpBlockType.IMAGE,
        [],
        image.src,
        image.caption
      ));
    }

    const blocks = this.mapBlocks(itemId, payload.blocks);
    const footnotes: ScpFootnote[] = [];
    for (let index: number = 0; index < payload.footnotes.length; index++) {
      const footnote = payload.footnotes[index];
      footnotes.push(new ScpFootnote(
        footnote.id,
        footnote.index,
        this.mapBlocksWithPrefix(itemId, footnote.blocks, `${itemId}:fn:${footnote.index}`)
      ));
    }

    const objectClass = this.objectClassOf(blocks);

    return new ScpArticleDocument(
      itemId,
      payload.title,
      objectClass,
      sourceUrl,
      fetchedAt,
      blocks,
      footnotes,
      '',
      this.parserWarningsOf(payload),
      payload.rating,
      payload.tags,
      payload.pageVersion,
      images
    );
  }

  private validatePayloadInternal(payload: ScpExtractPayload): string {
    if (payload === undefined || payload === null || typeof payload !== 'object' ||
      Array.isArray(payload)) {
      return '正文解析结果不是对象';
    }
    if (payload.ok !== true) {
      return `正文解析失败：${typeof payload.error === 'string' ? payload.error : '未知错误'}`;
    }
    if (payload.parserVersion !== ScpArticleDocument.CURRENT_PARSER_VERSION) {
      const version = typeof payload.parserVersion === 'number' ? `${payload.parserVersion}` : 'unknown';
      return `正文解析器版本不兼容：${version}`;
    }
    if (typeof payload.title !== 'string' || payload.title.trim().length === 0) {
      return '正文解析结果缺少标题';
    }
    if (typeof payload.error !== 'string' || typeof payload.rating !== 'string' ||
      typeof payload.pageVersion !== 'string' || payload.error.length > MAX_PAYLOAD_STRING_LENGTH ||
      payload.title.length > MAX_PAYLOAD_STRING_LENGTH ||
      payload.rating.length > MAX_PAYLOAD_STRING_LENGTH ||
      payload.pageVersion.length > MAX_PAYLOAD_STRING_LENGTH) {
      return '正文解析结果字段格式错误';
    }
    if (!Array.isArray(payload.blocks) || !Array.isArray(payload.images) ||
      !Array.isArray(payload.footnotes) || !Array.isArray(payload.tags)) {
      return '正文解析结果字段不完整';
    }
    if (payload.tags.length > MAX_PAYLOAD_TAGS || !this.validateTags(payload.tags)) {
      return '正文解析标签字段格式错误';
    }
    if (payload.images.length > MAX_PAYLOAD_IMAGES || !this.validateImages(payload.images)) {
      return '正文解析图片字段格式错误';
    }
    if (payload.footnotes.length > MAX_PAYLOAD_FOOTNOTES) {
      return '正文解析脚注数量超限';
    }
    const budget: PayloadValidationBudget = { blockCount: 0, spanCount: 0 };
    if (!this.validateBlocks(payload.blocks, 0, budget) ||
      !this.validateFootnotes(payload.footnotes, budget)) {
      return '正文解析正文结构格式错误';
    }
    if (!Array.isArray(payload.warnings) || payload.warnings.length > MAX_PAYLOAD_WARNINGS ||
      !this.validateWarnings(payload.warnings)) {
      return '正文解析警告字段格式错误';
    }
    if (!this.hasReadableBlocks(payload.blocks) && !this.hasReadableImage(payload.images)) {
      return '正文解析结果为空';
    }
    return '';
  }

  private validateTags(tags: string[]): boolean {
    for (let index: number = 0; index < tags.length; index++) {
      if (typeof tags[index] !== 'string' || tags[index].length > MAX_PAYLOAD_STRING_LENGTH) {
        return false;
      }
    }
    return true;
  }

  private validateWarnings(warnings: string[]): boolean {
    for (let index: number = 0; index < warnings.length; index++) {
      if (typeof warnings[index] !== 'string' || warnings[index].length > MAX_PAYLOAD_STRING_LENGTH) {
        return false;
      }
    }
    return true;
  }

  private validateImages(images: RawImage[]): boolean {
    for (let index: number = 0; index < images.length; index++) {
      const image = images[index];
      if (image === undefined || image === null || typeof image !== 'object' ||
        typeof image.src !== 'string' || image.src.length > MAX_PAYLOAD_STRING_LENGTH) {
        return false;
      }
      if (typeof image.caption !== 'string') {
        return false;
      }
      if (image.caption.length > MAX_PAYLOAD_STRING_LENGTH) {
        return false;
      }
    }
    return true;
  }

  private validateFootnotes(
    footnotes: RawFootnote[],
    budget: PayloadValidationBudget
  ): boolean {
    for (let index: number = 0; index < footnotes.length; index++) {
      const footnote = footnotes[index];
      if (footnote === undefined || footnote === null || typeof footnote !== 'object' ||
        typeof footnote.id !== 'string' || footnote.id.length > MAX_PAYLOAD_STRING_LENGTH ||
        typeof footnote.index !== 'number' || !Number.isFinite(footnote.index) ||
        footnote.index < 0 || !Array.isArray(footnote.blocks) ||
        !this.validateBlocks(footnote.blocks, 0, budget)) {
        return false;
      }
    }
    return true;
  }

  private validateBlocks(
    blocks: RawBlock[],
    depth: number,
    budget: PayloadValidationBudget
  ): boolean {
    if (depth > MAX_PAYLOAD_DEPTH || blocks.length > MAX_PAYLOAD_BLOCKS) {
      return false;
    }
    for (let index: number = 0; index < blocks.length; index++) {
      const block = blocks[index];
      if (block === undefined || block === null || typeof block !== 'object' ||
        typeof block.k !== 'string' || block.k.length === 0 ||
        block.k.length > 128) {
        return false;
      }
      budget.blockCount++;
      if (budget.blockCount > MAX_PAYLOAD_BLOCKS) {
        return false;
      }
      if (block.level !== undefined &&
        (typeof block.level !== 'number' || !Number.isFinite(block.level) ||
          block.level < 1 || block.level > 6)) {
        return false;
      }
      if (block.title !== undefined &&
        (typeof block.title !== 'string' || block.title.length > MAX_PAYLOAD_STRING_LENGTH)) {
        return false;
      }
      if (block.src !== undefined &&
        (typeof block.src !== 'string' || block.src.length > MAX_PAYLOAD_STRING_LENGTH)) {
        return false;
      }
      if (block.caption !== undefined &&
        (typeof block.caption !== 'string' || block.caption.length > MAX_PAYLOAD_STRING_LENGTH)) {
        return false;
      }
      if (block.spans !== undefined &&
        (!Array.isArray(block.spans) || !this.validateSpans(block.spans, budget))) {
        return false;
      }
      if (block.blocks !== undefined &&
        (!Array.isArray(block.blocks) || !this.validateBlocks(block.blocks, depth + 1, budget))) {
        return false;
      }
    }
    return true;
  }

  private validateSpans(spans: RawSpan[], budget: PayloadValidationBudget): boolean {
    if (spans.length > MAX_PAYLOAD_SPANS) {
      return false;
    }
    for (let index: number = 0; index < spans.length; index++) {
      const span = spans[index];
      if (span === undefined || span === null || typeof span !== 'object' ||
        typeof span.s !== 'string' || typeof span.t !== 'string' ||
        span.s.length > 128 || span.t.length > MAX_PAYLOAD_STRING_LENGTH ||
        (span.u !== undefined && (typeof span.u !== 'string' || span.u.length > MAX_PAYLOAD_STRING_LENGTH)) ||
        (span.r !== undefined && (typeof span.r !== 'string' || span.r.length > MAX_PAYLOAD_STRING_LENGTH))) {
        return false;
      }
      budget.spanCount++;
      if (budget.spanCount > MAX_PAYLOAD_SPANS) {
        return false;
      }
    }
    return true;
  }

  private hasReadableBlocks(blocks: RawBlock[]): boolean {
    for (let index: number = 0; index < blocks.length; index++) {
      const block = blocks[index];
      if (block === undefined || block === null) {
        continue;
      }
      const spans = block.spans ?? [];
      for (let spanIndex: number = 0; spanIndex < spans.length; spanIndex++) {
        const text = spans[spanIndex].t;
        if (typeof text === 'string' && text.trim().length > 0) {
          return true;
        }
      }
      if (block.k === 'embed' && typeof block.src === 'string' && block.src.trim().length > 0) {
        return true;
      }
      if (this.hasReadableBlocks(block.blocks ?? [])) {
        return true;
      }
    }
    return false;
  }

  private hasReadableImage(images: RawImage[]): boolean {
    for (let index: number = 0; index < images.length; index++) {
      if (typeof images[index].src === 'string' && images[index].src.trim().length > 0) {
        return true;
      }
    }
    return false;
  }

  private parserWarningsOf(payload: ScpExtractPayload): string[] {
    const result: string[] = [];
    const warnings = payload.warnings;
    for (let index: number = 0; index < warnings.length; index++) {
      const warning = warnings[index];
      if (warning.length > 0 && result.indexOf(warning) < 0) {
        result.push(warning);
      }
    }
    return result;
  }

  private mapBlocks(itemId: string, raw: RawBlock[]): ScpContentBlock[] {
    return this.mapBlocksWithPrefix(itemId, raw, `${itemId}:0`);
  }

  /** 嵌套层级各自携带父级前缀，保证块 key 全局唯一（ForEach key / 展开状态都依赖它）。 */
  private mapBlocksWithPrefix(itemId: string, raw: RawBlock[], prefix: string): ScpContentBlock[] {
    const result: ScpContentBlock[] = [];
    for (let index: number = 0; index < raw.length; index++) {
      result.push(this.mapBlock(itemId, `${prefix}:${index}`, raw[index]));
    }
    return result;
  }

  private mapBlock(itemId: string, key: string, raw: RawBlock): ScpContentBlock {
    const spans = this.mapSpans(raw.spans);
    switch (raw.k) {
      case 'paragraph':
        return new ScpContentBlock(key, ScpBlockType.PARAGRAPH, spans);
      case 'heading':
        return new ScpContentBlock(key, ScpBlockType.HEADING, spans, '', '', raw.level ?? 2);
      case 'quote':
        return new ScpContentBlock(key, ScpBlockType.QUOTE, spans, '', '', 0,
          this.mapBlocksWithPrefix(itemId, raw.blocks ?? [], key));
      case 'collapsible':
        return new ScpContentBlock(key, ScpBlockType.COLLAPSIBLE, [], '', raw.title ?? '', 0,
          this.mapBlocksWithPrefix(itemId, raw.blocks ?? [], key));
      case 'table':
        return new ScpContentBlock(key, ScpBlockType.TABLE, [], '', '', 0,
          this.mapBlocksWithPrefix(itemId, raw.blocks ?? [], key));
      case 'row':
        return new ScpContentBlock(key, ScpBlockType.TABLE_ROW, [], '', '', 0,
          this.mapBlocksWithPrefix(itemId, raw.blocks ?? [], key));
      case 'cell':
        return new ScpContentBlock(key, ScpBlockType.TABLE_CELL, spans);
      case 'divider':
        return new ScpContentBlock(key, ScpBlockType.DIVIDER);
      case 'embed':
        return new ScpContentBlock(key, ScpBlockType.EMBED, [], raw.src ?? '');
      case 'image':
        return new ScpContentBlock(key, ScpBlockType.IMAGE, [], raw.src ?? '', raw.caption ?? '');
      default:
        return new ScpContentBlock(key, ScpBlockType.UNSUPPORTED, spans);
    }
  }

  private mapSpans(raw: RawSpan[] | undefined): ScpTextSpan[] {
    const result: ScpTextSpan[] = [];
    if (raw === undefined) {
      return result;
    }
    for (let index: number = 0; index < raw.length; index++) {
      const span = raw[index];
      switch (span.s) {
        case 'strong':
          result.push(new ScpTextSpan(ScpTextStyle.STRONG, span.t));
          break;
        case 'em':
          result.push(new ScpTextSpan(ScpTextStyle.EMPHASIS, span.t));
          break;
        case 'del':
          result.push(new ScpTextSpan(ScpTextStyle.DELETED, span.t));
          break;
        case 'code':
          result.push(new ScpTextSpan(ScpTextStyle.CODE, span.t));
          break;
        case 'link':
          result.push(new ScpTextSpan(ScpTextStyle.LINK, span.t, span.u ?? ''));
          break;
        case 'footnote':
          result.push(new ScpTextSpan(ScpTextStyle.FOOTNOTE_REFERENCE, span.t, '', span.r ?? ''));
          break;
        default:
          result.push(new ScpTextSpan(ScpTextStyle.PLAIN, span.t));
          break;
      }
    }
    return result;
  }

  private itemIdOf(sourceUrl: string): string {
    const match = /\/(scp-\d+)(?:$|\/)/i.exec(sourceUrl);
    return match !== null ? match[1].toUpperCase() : sourceUrl;
  }

  private objectClassOf(blocks: ScpContentBlock[]): string {
    for (let index: number = 0; index < blocks.length; index++) {
      const text = this.plainText(blocks[index]);
      const match = /项目等级：?\s*([A-Za-z\u4e00-\u9fa5]+)/.exec(text);
      if (match !== null) {
        return match[1];
      }
    }
    return '';
  }

  private plainText(block: ScpContentBlock): string {
    let text = '';
    for (let index: number = 0; index < block.spans.length; index++) {
      text += block.spans[index].text;
    }
    for (let index: number = 0; index < block.children.length; index++) {
      text += this.plainText(block.children[index]);
    }
    return text;
  }
}
