import { describe, expect, it } from '@ohos/hypium';
import { ArticleRenderer } from '../main/ets/presentation/view/ArticleRenderer';
import { createRendererDocument } from './ArticleTestFixtures';

export default function articleRendererTest(): void {
  describe('ArticleRendererProjection', () => {
    it('projects spans and collapse state immutably', 0, () => {
      const document = createRendererDocument();
      const text = document.blocks[0];
      const collapsible = document.blocks[1];
      const initialKeys: string[] = [];

      expect(ArticleRenderer.textOf(text)).assertEqual('AB1');
      expect(JSON.stringify(ArticleRenderer.footnoteReferenceIds(text)))
        .assertEqual('["note-1"]');

      const openedKeys = ArticleRenderer.toggleExpanded(initialKeys, collapsible.key);
      expect(initialKeys.length).assertEqual(0);
      expect(openedKeys === initialKeys).assertFalse();
      expect(ArticleRenderer.isExpanded(openedKeys, collapsible.key)).assertTrue();

      const closedKeys = ArticleRenderer.toggleExpanded(openedKeys, collapsible.key);
      expect(ArticleRenderer.isExpanded(closedKeys, collapsible.key)).assertFalse();
      expect(ArticleRenderer.isExpanded(openedKeys, collapsible.key)).assertTrue();
    });
  });
}
