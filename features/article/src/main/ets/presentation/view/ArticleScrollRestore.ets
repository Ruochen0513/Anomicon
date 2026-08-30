/**
 * Coordinates the two independent prerequisites of article scroll restore:
 * the persisted offset can arrive before or after the native body is laid out.
 *
 * A provisional zero is not completion because the history lookup is async.
 * If the reader starts scrolling first, their interaction wins and any late
 * persisted offset is ignored for the remainder of this route instance.
 */
export class ArticleScrollRestore {
  private contentLaidOut: boolean = false;
  private completed: boolean = false;
  private pendingOffset: number = 0;

  reset(): void {
    this.contentLaidOut = false;
    this.completed = false;
    this.pendingOffset = 0;
  }

  observeRestoredOffset(offset: number, restoreReady: boolean): number | undefined {
    if (this.completed) {
      return undefined;
    }
    if (!restoreReady) {
      return undefined;
    }
    const normalized = this.normalize(offset);
    if (normalized <= 0) {
      // A resolved zero requires no controller movement, but it is still a
      // completed restore.  This distinction prevents a later stale/fresh
      // document projection from re-opening the route-level handshake.
      this.completed = true;
      return undefined;
    }
    this.pendingOffset = normalized;
    return this.takeReadyOffset();
  }

  markContentLaidOut(): number | undefined {
    this.contentLaidOut = true;
    return this.takeReadyOffset();
  }

  cancelForInteraction(): void {
    if (this.completed) {
      return;
    }
    this.completed = true;
    this.pendingOffset = 0;
  }

  private takeReadyOffset(): number | undefined {
    if (this.completed || !this.contentLaidOut || this.pendingOffset <= 0) {
      return undefined;
    }
    const offset = this.pendingOffset;
    this.completed = true;
    this.pendingOffset = 0;
    return offset;
  }

  private normalize(offset: number): number {
    if (!Number.isFinite(offset) || offset <= 0) {
      return 0;
    }
    return Math.floor(offset);
  }
}
