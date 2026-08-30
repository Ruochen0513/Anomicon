import { AbilityConstant, UIAbility, Want } from '@kit.AbilityKit';
import { abilityDelegatorRegistry } from '@kit.TestKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { Hypium } from '@ohos/hypium';
import testsuite from '../test/List.test';

const TEST_TAG: string = 'AnomiconTest';

/** Minimal UIAbility host used by the phone ohosTest target. */
export default class TestAbility extends UIAbility {
  private abilityDelegator: abilityDelegatorRegistry.AbilityDelegator;

  constructor() {
    super();
    this.abilityDelegator = abilityDelegatorRegistry.getAbilityDelegator();
  }

  onCreate(_want: Want, _launchParam: AbilityConstant.LaunchParam): void {
    const args = abilityDelegatorRegistry.getArguments();
    hilog.info(0x0000, TEST_TAG, '%{public}s', 'starting phone Hypium suite');
    Hypium.hypiumTest(this.abilityDelegator, args, testsuite);
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    windowStage.loadContent('testability/pages/Index', (error) => {
      if (error.code !== 0) {
        hilog.error(0x0000, TEST_TAG, 'failed to load test page: %{public}s', JSON.stringify(error));
      }
    });
  }

}
