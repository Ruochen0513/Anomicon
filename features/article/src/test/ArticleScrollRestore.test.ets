import { describe, expect, it } from '@ohos/hypium';
import { ArticleScrollRestore } from '../main/ets/presentation/view/ArticleScrollRestore';

export default function articleScrollRestoreCoordinatorTest(): void {
  describe('ArticleScrollRestore', () => {
    it('restores regardless of whether history or layout finishes first', 0, () => {
      const historyFirst = new ArticleScrollRestore();
      expect(historyFirst.observeRestoredOffset(480, true) === undefined).assertTrue();
      expect(historyFirst.markContentLaidOut()).assertEqual(480);
      expect(historyFirst.observeRestoredOffset(900, true) === undefined).assertTrue();

      const layoutFirst = new ArticleScrollRestore();
      expect(layoutFirst.markContentLaidOut() === undefined).assertTrue();
      expect(layoutFirst.observeRestoredOffset(520, true)).assertEqual(520);
      expect(layoutFirst.markContentLaidOut() === undefined).assertTrue();
    });

    it('distinguishes provisional zero from a resolved zero', 0, () => {
      const coordinator = new ArticleScrollRestore();
      coordinator.markContentLaidOut();

      expect(coordinator.observeRestoredOffset(0, false) === undefined).assertTrue();
      expect(coordinator.observeRestoredOffset(365.9, true)).assertEqual(365);

      coordinator.reset();
      coordinator.markContentLaidOut();
      expect(coordinator.observeRestoredOffset(0, true) === undefined).assertTrue();
      expect(coordinator.observeRestoredOffset(365.9, true) === undefined).assertTrue();
    });

    it('lets an early reader interaction win over a late history result', 0, () => {
      const coordinator = new ArticleScrollRestore();
      coordinator.markContentLaidOut();
      coordinator.observeRestoredOffset(0, false);
      coordinator.cancelForInteraction();

      expect(coordinator.observeRestoredOffset(640, true) === undefined).assertTrue();

      coordinator.reset();
      expect(coordinator.observeRestoredOffset(640, true) === undefined).assertTrue();
      expect(coordinator.markContentLaidOut()).assertEqual(640);
    });
  });
}
