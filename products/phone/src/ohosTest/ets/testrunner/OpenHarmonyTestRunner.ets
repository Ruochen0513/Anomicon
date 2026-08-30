import { abilityDelegatorRegistry, TestRunner } from '@kit.TestKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { Hypium } from '@ohos/hypium';
import testsuite from '../test/List.test';

const TEST_TAG: string = 'AnomiconTest';

/** SDK 26-compatible runner; keep the framework handshake synchronous. */
export default class OpenHarmonyTestRunner implements TestRunner {
  onPrepare(): void {
    hilog.info(0x0000, TEST_TAG, '%{public}s', 'OpenHarmonyTestRunner onPrepare');
  }

  onRun(): void {
    const args = abilityDelegatorRegistry.getArguments();
    const delegator = abilityDelegatorRegistry.getAbilityDelegator();
    hilog.info(0x0000, TEST_TAG, '%{public}s', 'OpenHarmonyTestRunner onRun');
    Hypium.hypiumTest(delegator, args, testsuite);
  }
}
