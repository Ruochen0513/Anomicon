import { describe, expect, it } from '@ohos/hypium';
import { createLibraryContentRef, LibraryContentKind, LibraryContentRef } from 'library';
import {
  ArticleDocumentCachePort,
  ArticleDocumentCacheRecord,
  ArticleHtmlPort,
  ArticleHtmlSnapshot
} from '../main/ets/domain/ArticleContracts';
import { ScpArticleDocument } from '../main/ets/domain/ScpDocument';
import { createArticleDocumentParser } from '../main/ets/composition/ArticleFeatureFactory';
import { ContentGateway } from '../main/ets/data/ContentGateway';
import { PendingExtraction } from '../main/ets/domain/ArticleContracts';
import { CURRENT_PAYLOAD } from './ArticleTestFixtures';

/** A cache substitute that keeps this test focused on the extraction hand-off. */
class EmptyDocumentCache implements ArticleDocumentCachePort {
  get(_itemId: string): Promise<ArticleDocumentCacheRecord | undefined> {
    return Promise.resolve(undefined);
  }

  put(_record: ArticleDocumentCacheRecord): Promise<void> {
    return Promise.resolve();
  }

  isFresh(_record: ArticleDocumentCacheRecord): boolean {
    return true;
  }
}

class UnusedHtmlPort implements ArticleHtmlPort {
  load(_sourceUrl: string, _forceNetwork: boolean = false): Promise<ArticleHtmlSnapshot> {
    return Promise.reject(new Error('not used by this test'));
  }
}

function arkWebStringResult(payload: string): string {
  // runJavaScript is string-typed, while the extraction script already
  // returns JSON.stringify(out); this models an additional bridge encoding.
  return JSON.stringify(payload);
}

function pendingFor(content: LibraryContentRef): PendingExtraction {
  return new PendingExtraction(
    1,
    content.key,
    content.id,
    `https://scp-wiki-cn.wikidot.com/${content.id}`,
    '<html></html>',
    1_700_000_000_000
  );
}

export default function articlePayloadCompatibilityTest(): void {
  describe('ArticlePayloadCompatibility', () => {
    it('maps a normal JSON extraction result', 0, () => {
      const parser = createArticleDocumentParser();
      const document = parser.parse(
        CURRENT_PAYLOAD,
        'https://scp-wiki-cn.wikidot.com/scp-173',
        1_700_000_000_000
      );

      expect(document.title).assertEqual('SCP-173 - 雕像');
      expect(document.blocks.length > 0).assertTrue();
    });

    it('unwraps an extra JSON string layer returned by ArkWeb', 0, () => {
      const parser = createArticleDocumentParser();
      const document = parser.parse(
        arkWebStringResult(CURRENT_PAYLOAD),
        'https://scp-wiki-cn.wikidot.com/scp-173',
        1_700_000_000_000
      );

      expect(document.title).assertEqual('SCP-173 - 雕像');
      expect(document.objectClass).assertEqual('Safe');
    });

    it('uses the same extraction payload for project and story content', 0, async () => {
      const gateway = new ContentGateway(
        new UnusedHtmlPort(),
        new EmptyDocumentCache(),
        createArticleDocumentParser()
      );
      const encoded = arkWebStringResult(CURRENT_PAYLOAD);
      const kinds: LibraryContentKind[] = [LibraryContentKind.SCP, LibraryContentKind.TALE];

      for (let index: number = 0; index < kinds.length; index++) {
        const kind = kinds[index];
        const content = createLibraryContentRef(
          kind,
          kind === LibraryContentKind.SCP ? 'scp-173' : 'a-test-tale',
          kind === LibraryContentKind.SCP ? 'SCP-173' : '测试故事'
        );
        const document: ScpArticleDocument = await gateway.completeExtraction(
          content,
          pendingFor(content),
          encoded
        );

        expect(document.title).assertEqual('SCP-173 - 雕像');
        expect(document.blocks.length > 0).assertTrue();
      }
    });
  });
}
