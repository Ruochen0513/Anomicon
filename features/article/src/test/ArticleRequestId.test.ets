import { describe, expect, it } from '@ohos/hypium';
import { createLibraryContentRef, LibraryContentKind, LibraryContentRef } from 'library';
import { ArticleContentUseCase } from '../main/ets/application/ArticleContentUseCase';
import {
  ArticleContentGateway,
  ArticleContentSource,
  ArticleLoadResult,
  PendingExtraction
} from '../main/ets/domain/ArticleContracts';
import { ScpArticleDocument } from '../main/ets/domain/ScpDocument';
import { ArticleViewModel } from '../main/ets/presentation/viewmodel/ArticleViewModel';
import { createRendererDocument } from './ArticleTestFixtures';

class PendingGateway implements ArticleContentGateway {
  completionCount: number = 0;

  load(content: LibraryContentRef, requestId: number,
    _forceNetwork: boolean = false): Promise<ArticleLoadResult> {
    return Promise.resolve(new ArticleLoadResult(
      undefined,
      new PendingExtraction(
        requestId,
        content.key,
        content.id,
        `https://scp-wiki-cn.wikidot.com/${content.id}`,
        '<html></html>',
        1_700_000_000_000
      ),
      ArticleContentSource.NETWORK,
      1_700_000_000_000
    ));
  }

  completeExtraction(
    _content: LibraryContentRef,
    _pending: PendingExtraction,
    _payload: string
  ): Promise<ScpArticleDocument> {
    this.completionCount += 1;
    return Promise.resolve(createRendererDocument());
  }
}

async function drainMicrotasks(rounds: number = 12): Promise<void> {
  for (let index = 0; index < rounds; index++) {
    await Promise.resolve();
  }
}

export default function articleRequestIdTest(): void {
  describe('ArticleRequestIdGuard', () => {
    it('drops extraction callbacks from a different request', 0, async () => {
      const gateway = new PendingGateway();
      const viewModel = new ArticleViewModel(new ArticleContentUseCase(gateway));
      const content = createLibraryContentRef(LibraryContentKind.SCP, 'scp-173', 'SCP-173');
      viewModel.setRouteContent(content);
      viewModel.activate();
      await drainMicrotasks();

      const requestId = viewModel.pendingExtraction?.requestId ?? 0;
      expect(requestId > 0).assertTrue();
      expect(viewModel.parsing).assertTrue();

      viewModel.onExtractionResult(requestId + 1, '{}');
      viewModel.onExtractionFailed(requestId + 1, 'stale failure');
      await drainMicrotasks();

      expect(gateway.completionCount).assertEqual(0);
      expect(viewModel.pendingExtraction?.requestId).assertEqual(requestId);
      expect(viewModel.parsing).assertTrue();
      expect(viewModel.error === undefined).assertTrue();
      viewModel.dispose();
    });
  });
}
