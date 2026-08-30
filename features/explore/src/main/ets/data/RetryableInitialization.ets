/** A shared initialization task that is sticky on success and retryable on failure. */
export class RetryableInitialization {
  private task: Promise<void> | undefined = undefined;

  /**
   * Concurrent callers share one in-flight task. A successful task remains
   * cached, while a rejected task is removed before callers handle the error
   * so the next activate/retry can make a fresh attempt.
   */
  run(initializer: () => Promise<void>): Promise<void> {
    if (this.task !== undefined) {
      return this.task;
    }
    // Starting in a promise continuation also converts a synchronous adapter
    // exception into the same rejected-promise contract.
    const current = Promise.resolve().then((): Promise<void> => initializer());
    this.task = current;
    current.catch((_error: Object): void => {
      if (this.task === current) {
        this.task = undefined;
      }
    });
    return current;
  }

  /** Wait for an initialization already started by another caller, if any. */
  waitForCurrent(): Promise<void> {
    return this.task ?? Promise.resolve();
  }
}
