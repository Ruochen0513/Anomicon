import { describe, expect, it } from '@ohos/hypium';
import { ScpPageFetchService } from '../main/ets/data/ScpPageFetchService';
import { ScpRequestScheduler } from '../main/ets/data/ScpRequestScheduler';

export default function scpPageFetchLifecycleTest(): void {
  describe('ScpPageFetchLifecycle', () => {
    it('rejects new requests after repeated disposal', 0, async () => {
      const service = new ScpPageFetchService(new ScpRequestScheduler());

      service.dispose();
      service.dispose();

      let message: string = '';
      try {
        await service.fetchPage('https://scp-wiki-cn.wikidot.com/scp-173');
      } catch (error) {
        message = error instanceof Error ? error.message : '';
      }
      expect(message).assertEqual('RCP 会话已关闭');
    });
  });
}
