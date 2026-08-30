import { describe, expect, it } from '@ohos/hypium';
import { RetryableInitialization } from '../main/ets/data/RetryableInitialization';

/** Fully in-memory adapter used to exercise the initialization contract. */
class ControlledInitializer {
  attempts: number = 0;
  private resolveCurrent: (() => void) | undefined = undefined;
  private rejectCurrent: ((error: Error) => void) | undefined = undefined;

  initialize(): Promise<void> {
    this.attempts += 1;
    return new Promise<void>(
      (resolve: () => void, reject: (error: Error) => void): void => {
        this.resolveCurrent = resolve;
        this.rejectCurrent = reject;
      }
    );
  }

  succeed(): void {
    const resolve = this.resolveCurrent;
    this.clearCallbacks();
    resolve?.();
  }

  fail(message: string): void {
    const reject = this.rejectCurrent;
    this.clearCallbacks();
    reject?.(new Error(message));
  }

  private clearCallbacks(): void {
    this.resolveCurrent = undefined;
    this.rejectCurrent = undefined;
  }
}

export default function exploreInitializationTest(): void {
  describe('ExploreInitializationContract', () => {
    it('shares the first attempt and retries after rejection', 0, async () => {
      const gate = new RetryableInitialization();
      const adapter = new ControlledInitializer();

      const first = gate.run((): Promise<void> => adapter.initialize());
      const concurrent = gate.run((): Promise<void> => adapter.initialize());
      expect(first === concurrent).assertTrue();
      await Promise.resolve();
      expect(adapter.attempts).assertEqual(1);

      let firstRejected: boolean = false;
      let concurrentRejected: boolean = false;
      const firstHandled = first.catch((_error: Object): void => {
        firstRejected = true;
      });
      const concurrentHandled = concurrent.catch((_error: Object): void => {
        concurrentRejected = true;
      });
      adapter.fail('transient RDB open failure');
      await firstHandled;
      await concurrentHandled;
      expect(firstRejected).assertTrue();
      expect(concurrentRejected).assertTrue();

      const retry = gate.run((): Promise<void> => adapter.initialize());
      const retryConcurrent = gate.run((): Promise<void> => adapter.initialize());
      expect(retry === first).assertFalse();
      expect(retry === retryConcurrent).assertTrue();
      await Promise.resolve();
      expect(adapter.attempts).assertEqual(2);

      adapter.succeed();
      await retry;
      const afterSuccess = gate.run((): Promise<void> => adapter.initialize());
      expect(afterSuccess === retry).assertTrue();
      expect(adapter.attempts).assertEqual(2);
    });
  });
}
