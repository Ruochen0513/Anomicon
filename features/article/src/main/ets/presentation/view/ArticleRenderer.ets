import {
  ScpContentBlock,
  ScpTextStyle
} from '../../domain/ScpDocument';

/**
 * Pure article-rendering projection helpers.
 *
 * ArkUI builders are deliberately kept at the page/view edge.  This class
 * contains the block/span decisions that can be tested without a WebView,
 * UIContext, database or navigation stack, and gives native block components
 * one stable input contract.
 */
export class ArticleRenderer {
  static textOf(block: ScpContentBlock): string {
    let result: string = '';
    for (let index = 0; index < block.spans.length; index++) {
      result += block.spans[index].text;
    }
    return result;
  }

  static footnoteReferenceIds(block: ScpContentBlock): string[] {
    const ids: string[] = [];
    for (let index = 0; index < block.spans.length; index++) {
      const span = block.spans[index];
      if (span.style === ScpTextStyle.FOOTNOTE_REFERENCE && span.referenceId.length > 0) {
        ids.push(span.referenceId);
      }
    }
    return ids;
  }

  static isExpanded(expandedKeys: string[], blockKey: string): boolean {
    return expandedKeys.indexOf(blockKey) >= 0;
  }

  /** Return a new immutable key list after a collapsible block is toggled. */
  static toggleExpanded(expandedKeys: string[], blockKey: string): string[] {
    const next = expandedKeys.slice();
    const index = next.indexOf(blockKey);
    if (index >= 0) {
      next.splice(index, 1);
    } else {
      next.push(blockKey);
    }
    return next;
  }

  private constructor() {
  }
}
