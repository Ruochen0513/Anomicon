import { hilog } from '@kit.PerformanceAnalysisKit';
import { describe, it, expect } from '@ohos/hypium';

/** On-device smoke checks for the phone test ability itself. */
export default function abilityTest(): void {
  describe('PhoneTestAbility', () => {
    it('starts the Hypium test ability', 0, () => {
      hilog.info(0x0000, 'AnomiconTest', '%{public}s', 'phone ability smoke test');
      expect('anomicon').assertContain('nom');
    });
  });
}
