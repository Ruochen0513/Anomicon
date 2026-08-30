import { vibrator } from '@kit.SensorServiceKit';
import { HapticFeedbackPort } from './PlatformPorts';

/** HarmonyOS implementation of the optional selection haptic. */
export class HapticFeedbackAdapter implements HapticFeedbackPort {
  private effectId: vibrator.HapticFeedback | undefined = undefined;
  private effectResolved: boolean = false;

  playSelection(enabled: boolean): void {
    if (!enabled) {
      return;
    }

    const effectId = this.resolveEffect();
    if (effectId === undefined) {
      return;
    }

    vibrator.startVibration({
      type: 'preset',
      effectId: effectId,
      count: 1
    }, {
      id: 0,
      usage: 'touch'
    }).catch(() => {
      // 模拟器或临时不可用时静默降级，不影响设置状态。
    });
  }

  private resolveEffect(): vibrator.HapticFeedback | undefined {
    if (this.effectResolved) {
      return this.effectId;
    }

    try {
      if (vibrator.isSupportEffectSync(vibrator.HapticFeedback.EFFECT_HARD)) {
        this.effectId = vibrator.HapticFeedback.EFFECT_HARD;
        this.effectResolved = true;
        return this.effectId;
      }
      if (vibrator.isSupportEffectSync(vibrator.HapticFeedback.EFFECT_SOFT)) {
        this.effectId = vibrator.HapticFeedback.EFFECT_SOFT;
        this.effectResolved = true;
        return this.effectId;
      }
    } catch (error) {
      // Capability queries may fail transiently while the device service is
      // starting.  Keep the unresolved state so a later interaction can retry
      // instead of permanently disabling haptics for the whole process.
      return undefined;
    }
    this.effectResolved = true;
    return undefined;
  }
}
