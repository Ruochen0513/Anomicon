import { LibraryContentRef } from '../domain/LibraryContentRef';
import {
  readingActivityCreditedEndUptime,
  readingActivityHasReachedIdle,
  readingActivityIdleEndedAt
} from '../domain/ReadingActivityPolicy';
import {
  ResearchActivityCheckpoint,
  ResearchActivityFinish,
  ResearchActivityStart
} from '../domain/ResearchProgress';
import { ResearchActivitySink } from '../domain/ResearchActivityRepo';
import {
  IdGeneratorPort,
  RuntimeClockPort
} from 'anomiconbasic';

/** 活跃页面每 30 秒把单调时钟累计值写入 provisional 账本行。 */
const READING_ACTIVITY_CHECKPOINT_MS: number = 30 * 1000;
/** 没有新的阅读交互时最多继续计入 90 秒，防止前台长期放置刷取阅历。 */
const READING_ACTIVITY_IDLE_TIMEOUT_MS: number = 90 * 1000;
const READING_ACTIVITY_START_RETRY_INITIAL_MS: number = 2 * 1000;
const READING_ACTIVITY_START_RETRY_MAX_MS: number = 30 * 1000;

/**
 * 阅读活动生命周期协调器。
 *
 * 只有 Ability 位于前台、NavDestination 已显示且处于 Active、正文已就绪时
 * 才能建立账本会话。运行时状态不进入 V2 UI 状态；AppStorageV2 中只发布由
 * RDB 账本派生的 ResearchProgress 快照。
 */
export class ReadingActivityCoord {
  private readonly profile: ResearchActivitySink;
  private readonly clock: RuntimeClockPort;
  private readonly idGenerator: IdGeneratorPort;
  /** NavDestination 实例身份，防止旧页面的迟到回调释放同 slug 的新页面。 */
  private pageOwnerId: string = '';
  private content: LibraryContentRef | undefined = undefined;
  private abilityForeground: boolean = false;
  private destinationShown: boolean = false;
  private destinationActive: boolean = false;
  private contentReady: boolean = false;
  private idlePaused: boolean = false;
  private continuousInteraction: boolean = false;
  private lastOffset: number = 0;

  private segmentId: string = '';
  private segmentStartedAt: number = 0;
  private segmentActiveMs: number = 0;
  private segmentCheckpointSequence: number = 0;
  private lastMeasuredUptime: number = -1;
  private lastInteractionUptime: number = -1;
  private lastInteractionWallTime: number = 0;
  private checkpointTimer: number = -1;
  private startRetryTimer: number = -1;
  private startRetryDelayMs: number = READING_ACTIVITY_START_RETRY_INITIAL_MS;
  private finishRetryTimer: number = -1;
  private finishRetryDelayMs: number = READING_ACTIVITY_START_RETRY_INITIAL_MS;
  /** finalize 失败后保留完整累计值；后续生命周期节点会继续幂等重试。 */
  private pendingFinishes: Map<string, ResearchActivityFinish> =
    new Map<string, ResearchActivityFinish>();
  private finishInFlight: Map<string, boolean> = new Map<string, boolean>();
  /**
   * Persistence operations which have been handed to the profile sink but
   * have not settled yet.  Ability teardown is asynchronous, so keeping this
   * small in-memory ledger lets the composition root wait for the final
   * checkpoint/finalize pair without exposing RDB promises to the View.
   */
  private readonly persistenceTasks: Set<Promise<void>> = new Set<Promise<void>>();

  constructor(
    profile: ResearchActivitySink,
    clock: RuntimeClockPort,
    idGenerator: IdGeneratorPort
  ) {
    this.profile = profile;
    this.clock = clock;
    this.idGenerator = idGenerator;
  }

  initialize(): Promise<void> {
    const task = this.profile.initialize();
    task.then((): void => {
      this.retryPendingFinishes();
    }).catch((): void => {
      // 初始化错误由共享 ViewModel 发布；下一次显式初始化仍可重试。
    });
    return task;
  }

  /**
   * Drain writes currently handed to the profile sink.
   *
   * The method is intentionally additive: existing callers can continue to
   * use the synchronous lifecycle methods, while Ability teardown can await
   * this best-effort drain.  A single immediate retry is attempted for a
   * finalize that failed before teardown; repeated failures remain in
   * `pendingFinishes` for the next foreground lifecycle rather than blocking
   * shutdown indefinitely.
   */
  async flush(): Promise<void> {
    let retriedPendingFinishes = false;
    while (this.persistenceTasks.size > 0 ||
      (!retriedPendingFinishes && this.pendingFinishes.size > 0)) {
      if (this.persistenceTasks.size === 0 && this.pendingFinishes.size > 0) {
        retriedPendingFinishes = true;
        // A teardown must not leave a retry timer alive solely to perform the
        // same write after the Ability has already gone away.
        this.clearFinishRetryTimer();
        this.retryPendingFinishes();
      }
      const tasks: Promise<void>[] = [];
      this.persistenceTasks.forEach((task: Promise<void>): void => {
        tasks.push(task);
      });
      if (tasks.length === 0) {
        break;
      }
      // Tracked tasks absorb their own rejection, so shutdown remains
      // best-effort even when the database is unavailable.
      await Promise.all(tasks);
    }
  }

  /** WindowStage/Ability 重建时清除全部页面资格，避免新前台继承旧目的地信号。 */
  resetAbility(): void {
    this.abilityForeground = false;
    this.clearStartRetryTimer();
    this.clearFinishRetryTimer();
    this.finishSession('ability_reset');
    this.content = undefined;
    this.resetPageSignals();
  }

  /** Ability 生命周期是所有页面计时资格的最外层门控。 */
  setAbilityForeground(foreground: boolean): void {
    if (this.abilityForeground === foreground) {
      return;
    }
    this.abilityForeground = foreground;
    if (foreground) {
      this.retryPendingFinishes();
      this.registerInteractionAt(this.currentUptime(), this.currentWallTime());
      this.reconcileEligibility('ability_foreground');
    } else {
      this.endContinuousInteraction();
      this.reconcileEligibility('ability_background');
      // 待结束记录保留在内存；回到前台时统一重试，后台不再周期唤醒。
      this.clearFinishRetryTimer();
    }
  }

  /** onReady 只附着页面身份；正文加载完成前不会开始计时。 */
  attachPage(
    ownerId: string,
    content: LibraryContentRef,
    ready: boolean,
    offset: number
  ): void {
    if (this.pageOwnerId !== ownerId ||
      (this.content !== undefined && this.content.key !== content.key)) {
      this.finishSession('page_replaced');
      this.resetPageSignals();
    }
    this.pageOwnerId = ownerId;
    this.content = content;
    this.contentReady = ready;
    this.lastOffset = this.normalizeOffset(offset);
    if (!ready) {
      this.endContinuousInteraction();
      this.reconcileEligibility('content_loading');
    }
  }

  setPageShown(
    ownerId: string,
    content: LibraryContentRef,
    shown: boolean,
    ready: boolean,
    offset: number
  ): void {
    if (!this.isCurrentPage(ownerId, content)) {
      return;
    }
    this.destinationShown = shown;
    if (!shown || !ready) {
      this.endContinuousInteraction();
    }
    this.contentReady = ready;
    this.lastOffset = this.normalizeOffset(offset);
    if (shown) {
      this.registerInteractionAt(this.currentUptime(), this.currentWallTime());
    }
    this.reconcileEligibility(shown ? 'destination_shown' : 'destination_hidden');
  }

  setPageActive(
    ownerId: string,
    content: LibraryContentRef,
    active: boolean,
    ready: boolean,
    offset: number
  ): void {
    if (!this.isCurrentPage(ownerId, content)) {
      return;
    }
    this.destinationActive = active;
    this.contentReady = ready;
    if (!active || !ready) {
      this.endContinuousInteraction();
    }
    this.lastOffset = this.normalizeOffset(offset);
    if (active) {
      this.registerInteractionAt(this.currentUptime(), this.currentWallTime());
    }
    this.reconcileEligibility(active ? 'destination_active' : 'destination_inactive');
  }

  setContentReady(
    ownerId: string,
    content: LibraryContentRef,
    ready: boolean,
    offset: number
  ): void {
    if (this.pageOwnerId !== ownerId ||
      this.content === undefined || this.content.key !== content.key) {
      // 解析回调没有取得页面所有权的资格；旧页面迟到结果必须静默丢弃。
      return;
    }
    // 使用解析后的可读标题和更精确的展示类型刷新当前会话元数据。
    const becameReady = ready && !this.contentReady;
    this.content = content;
    this.contentReady = ready;
    if (!ready) {
      this.endContinuousInteraction();
    }
    this.lastOffset = this.normalizeOffset(offset);
    if (becameReady) {
      this.registerInteractionAt(this.currentUptime(), this.currentWallTime());
    }
    this.reconcileEligibility(ready ? 'content_ready' : 'content_unavailable');
  }

  /** 滚动开始、折叠块操作等真实阅读交互会解除空闲暂停。 */
  noteInteraction(ownerId: string, content: LibraryContentRef, offset: number): void {
    if (this.pageOwnerId !== ownerId ||
      this.content === undefined || this.content.key !== content.key) {
      return;
    }
    this.content = content;
    this.lastOffset = this.normalizeOffset(offset);
    const now = this.currentUptime();
    if (now === undefined) {
      return;
    }
    const wallTime = this.currentWallTime();
    if (this.segmentId.length > 0 && this.hasReachedIdleDeadline(now)) {
      this.accrueUntil(now);
      this.finishSession('idle');
    } else {
      this.accrueUntil(now);
    }
    this.registerInteractionAt(now, wallTime);
    this.reconcileEligibility('interaction');
  }

  /** 滚动停止时同步保存位置，并立即保存本会话的累计可信时长。 */
  checkpoint(ownerId: string, content: LibraryContentRef, offset: number): void {
    if (this.pageOwnerId !== ownerId ||
      this.content === undefined || this.content.key !== content.key) {
      return;
    }
    this.noteInteraction(ownerId, content, offset);
    this.persistCheckpoint();
  }

  /** Scroll 的 start/stop 区间持续视为交互，避免长距离滚动被 90 秒空闲规则截断。 */
  setContinuousInteraction(
    ownerId: string,
    content: LibraryContentRef,
    active: boolean,
    offset: number
  ): void {
    if (this.pageOwnerId !== ownerId ||
      this.content === undefined || this.content.key !== content.key) {
      return;
    }
    this.lastOffset = this.normalizeOffset(offset);
    if (active) {
      // 先按旧 idle deadline 封存空闲段，再把后续区间标记为连续滚动。
      this.noteInteraction(ownerId, content, offset);
      this.continuousInteraction = true;
    } else {
      this.endContinuousInteraction();
    }
  }

  releasePage(ownerId: string, contentKey: string, offset: number): void {
    if (this.pageOwnerId !== ownerId ||
      this.content === undefined || this.content.key !== contentKey) {
      return;
    }
    this.lastOffset = this.normalizeOffset(offset);
    this.finishSession('page_released');
    this.content = undefined;
    this.resetPageSignals();
  }

  private isCurrentPage(ownerId: string, content: LibraryContentRef): boolean {
    if (this.pageOwnerId !== ownerId ||
      this.content === undefined || this.content.key !== content.key) {
      return false;
    }
    this.content = content;
    return true;
  }

  private reconcileEligibility(reason: string): void {
    if (this.isEligible()) {
      this.startSessionIfNeeded();
      return;
    }
    this.clearStartRetryTimer();
    if (this.segmentId.length > 0) {
      this.finishSession(reason);
    }
  }

  private isEligible(): boolean {
    return this.content !== undefined &&
      this.abilityForeground &&
      this.destinationShown &&
      this.destinationActive &&
      this.contentReady &&
      !this.idlePaused;
  }

  private startSessionIfNeeded(): void {
    if (this.segmentId.length > 0 || this.content === undefined) {
      return;
    }
    if (this.pendingFinishes.size > 0) {
      // 先封存上一段，再允许新段开始，避免 startSession 将待结束行改为 interrupted。
      this.retryPendingFinishes();
      this.scheduleFinishRetry();
      return;
    }
    this.retryPendingFinishes();
    this.clearStartRetryTimer();
    const uptime = this.currentUptime();
    if (uptime === undefined) {
      this.scheduleStartRetry();
      return;
    }
    const wallTime = this.currentWallTime();
    const content = this.content;
    const segmentId = this.idGenerator.generate();
    this.segmentId = segmentId;
    this.segmentStartedAt = wallTime;
    this.segmentActiveMs = 0;
    this.segmentCheckpointSequence = 0;
    this.lastMeasuredUptime = uptime;
    this.lastInteractionUptime = uptime;
    this.lastInteractionWallTime = wallTime;
    this.startCheckpointTimer();
    const startTask = this.profile.startSession(new ResearchActivityStart(
      segmentId,
      content,
      wallTime,
      this.lastOffset,
      wallTime,
      this.segmentCheckpointSequence,
      -new Date(wallTime).getTimezoneOffset()
    ));
    this.trackPersistence(startTask);
    startTask.then((): void => {
      this.startRetryDelayMs = READING_ACTIVITY_START_RETRY_INITIAL_MS;
    }).catch((error: Error): void => {
      console.warn(`Start research activity failed: ${error.message}`);
      // start 未落盘时，该 segment 的 checkpoint/finalize 没有可重试对象。
      this.pendingFinishes.delete(segmentId);
      if (this.segmentId === segmentId) {
        this.clearCheckpointTimer();
        this.clearSessionState();
        this.scheduleStartRetry();
      }
    });
  }

  private persistCheckpoint(): void {
    if (this.segmentId.length === 0) {
      return;
    }
    const now = this.currentUptime();
    if (now === undefined) {
      return;
    }
    if (this.continuousInteraction) {
      this.refreshContinuousInteractionAt(now, this.currentWallTime());
    } else {
      this.accrueUntil(now);
    }
    if (this.hasReachedIdleDeadline(now)) {
      this.finishSession('idle');
      return;
    }
    const segmentId = this.segmentId;
    const wallTime = this.currentWallTime();
    const checkpointSequence = this.nextCheckpointSequence();
    const checkpointTask = this.profile.checkpointSession(new ResearchActivityCheckpoint(
      segmentId,
      this.segmentActiveMs,
      this.lastOffset,
      wallTime,
      checkpointSequence
    ));
    this.trackPersistence(checkpointTask);
    checkpointTask.catch((error: Error): void => {
      console.warn(`Checkpoint research activity failed: ${error.message}`);
    });
  }

  private finishSession(reason: string): void {
    if (this.segmentId.length === 0) {
      return;
    }
    const now = this.currentUptime();
    const writtenAt = this.currentWallTime();
    if (now !== undefined) {
      if (this.continuousInteraction) {
        this.refreshContinuousInteractionAt(now, writtenAt);
      } else {
        this.accrueUntil(now);
      }
    }
    const reachedIdle = !this.continuousInteraction &&
      now !== undefined && this.hasReachedIdleDeadline(now);
    const effectiveReason = reachedIdle ? 'idle' : reason;
    const segmentId = this.segmentId;
    const startedAt = this.segmentStartedAt;
    const activeMs = this.segmentActiveMs;
    const endedAt = reachedIdle ?
      readingActivityIdleEndedAt(
        startedAt,
        this.lastInteractionWallTime,
        READING_ACTIVITY_IDLE_TIMEOUT_MS
      ) :
      Math.max(startedAt, writtenAt);
    const offset = this.lastOffset;
    const checkpointSequence = this.nextCheckpointSequence();
    const finishSequence = this.nextCheckpointSequence();
    this.clearCheckpointTimer();
    this.clearSessionState();
    if (effectiveReason === 'idle') {
      this.idlePaused = true;
    }
    const checkpoint = new ResearchActivityCheckpoint(
      segmentId,
      activeMs,
      offset,
      writtenAt,
      checkpointSequence
    );
    const finish = new ResearchActivityFinish(
      segmentId,
      endedAt,
      activeMs,
      offset,
      effectiveReason,
      writtenAt,
      finishSequence
    );
    // 先写最后 checkpoint：即使 finalize 瞬时失败，重启恢复也能保留短会话。
    const checkpointTask = this.profile.checkpointSession(checkpoint);
    this.trackPersistence(checkpointTask);
    checkpointTask.catch((error: Error): void => {
      console.warn(`Final checkpoint research activity failed: ${error.message}`);
    });
    this.pendingFinishes.set(segmentId, finish);
    this.persistFinish(finish);
  }

  private persistFinish(finish: ResearchActivityFinish): void {
    if (this.finishInFlight.get(finish.segmentId) === true) {
      return;
    }
    this.finishInFlight.set(finish.segmentId, true);
    const finalizeTask = this.profile.finalizeSession(finish);
    this.trackPersistence(finalizeTask);
    finalizeTask.then((): void => {
      this.finishInFlight.delete(finish.segmentId);
      this.pendingFinishes.delete(finish.segmentId);
      if (this.pendingFinishes.size === 0) {
        this.clearFinishRetryTimer();
        this.finishRetryDelayMs = READING_ACTIVITY_START_RETRY_INITIAL_MS;
        this.reconcileEligibility('finish_persisted');
      }
    }).catch((error: Error): void => {
      this.finishInFlight.delete(finish.segmentId);
      console.warn(`Finalize research activity failed: ${error.message}`);
      this.scheduleFinishRetry();
    });
  }

  /** Add a sink write to the teardown ledger and swallow only the tracking
   * promise's rejection; the original task remains available to its caller's
   * normal success/error handlers above. */
  private trackPersistence<T>(task: Promise<T>): void {
    const settled: Promise<void> = task.then(
      (): void => {
      },
      (): void => {
      }
    );
    this.persistenceTasks.add(settled);
    settled.then((): void => {
      this.persistenceTasks.delete(settled);
    });
  }

  private retryPendingFinishes(): void {
    this.pendingFinishes.forEach((finish: ResearchActivityFinish): void => {
      this.persistFinish(finish);
    });
  }

  private scheduleStartRetry(): void {
    if (!this.isEligible() || this.startRetryTimer >= 0) {
      return;
    }
    const delay = this.startRetryDelayMs;
    this.startRetryDelayMs = Math.min(
      READING_ACTIVITY_START_RETRY_MAX_MS,
      this.startRetryDelayMs * 2
    );
    this.startRetryTimer = setTimeout((): void => {
      this.startRetryTimer = -1;
      this.reconcileEligibility('start_retry');
    }, delay);
  }

  private clearStartRetryTimer(): void {
    if (this.startRetryTimer >= 0) {
      clearTimeout(this.startRetryTimer);
      this.startRetryTimer = -1;
    }
  }

  private scheduleFinishRetry(): void {
    if (!this.abilityForeground || this.pendingFinishes.size === 0 || this.finishRetryTimer >= 0) {
      return;
    }
    const delay = this.finishRetryDelayMs;
    this.finishRetryDelayMs = Math.min(
      READING_ACTIVITY_START_RETRY_MAX_MS,
      this.finishRetryDelayMs * 2
    );
    this.finishRetryTimer = setTimeout((): void => {
      this.finishRetryTimer = -1;
      this.retryPendingFinishes();
      if (this.pendingFinishes.size > 0) {
        this.scheduleFinishRetry();
      }
    }, delay);
  }

  private clearFinishRetryTimer(): void {
    if (this.finishRetryTimer >= 0) {
      clearTimeout(this.finishRetryTimer);
      this.finishRetryTimer = -1;
    }
  }

  private accrueUntil(now: number): void {
    if (this.segmentId.length === 0 || this.lastMeasuredUptime < 0) {
      return;
    }
    const creditedEnd = readingActivityCreditedEndUptime(
      now,
      this.lastInteractionUptime,
      READING_ACTIVITY_IDLE_TIMEOUT_MS
    );
    if (creditedEnd > this.lastMeasuredUptime) {
      this.segmentActiveMs += creditedEnd - this.lastMeasuredUptime;
      this.lastMeasuredUptime = creditedEnd;
    }
  }

  private hasReachedIdleDeadline(now: number): boolean {
    return readingActivityHasReachedIdle(
      now,
      this.lastInteractionUptime,
      READING_ACTIVITY_IDLE_TIMEOUT_MS
    );
  }

  private registerInteractionAt(now: number | undefined, wallTime: number): void {
    if (now === undefined) {
      return;
    }
    this.accrueUntil(now);
    this.idlePaused = false;
    this.lastInteractionUptime = now;
    this.lastInteractionWallTime = wallTime;
    if (this.segmentId.length > 0) {
      this.lastMeasuredUptime = now;
    }
  }

  /** 连续滚动的心跳先推进交互截止点，再累计，定时器延迟也不会误丢时长。 */
  private refreshContinuousInteractionAt(now: number, wallTime: number): void {
    this.idlePaused = false;
    this.lastInteractionUptime = now;
    this.lastInteractionWallTime = wallTime;
    this.accrueUntil(now);
    if (this.segmentId.length > 0) {
      this.lastMeasuredUptime = now;
    }
  }

  private endContinuousInteraction(): void {
    if (!this.continuousInteraction) {
      return;
    }
    const now = this.currentUptime();
    if (now !== undefined) {
      this.refreshContinuousInteractionAt(now, this.currentWallTime());
    }
    this.continuousInteraction = false;
  }

  private startCheckpointTimer(): void {
    this.clearCheckpointTimer();
    this.checkpointTimer = setInterval((): void => {
      this.persistCheckpoint();
    }, READING_ACTIVITY_CHECKPOINT_MS);
  }

  private clearCheckpointTimer(): void {
    if (this.checkpointTimer >= 0) {
      clearInterval(this.checkpointTimer);
      this.checkpointTimer = -1;
    }
  }

  private clearSessionState(): void {
    this.segmentId = '';
    this.segmentStartedAt = 0;
    this.segmentActiveMs = 0;
    this.segmentCheckpointSequence = 0;
    this.lastMeasuredUptime = -1;
  }

  private nextCheckpointSequence(): number {
    this.segmentCheckpointSequence++;
    return this.segmentCheckpointSequence;
  }

  private resetPageSignals(): void {
    this.pageOwnerId = '';
    this.destinationShown = false;
    this.destinationActive = false;
    this.contentReady = false;
    this.idlePaused = false;
    this.continuousInteraction = false;
    this.lastOffset = 0;
    this.lastInteractionUptime = -1;
    this.lastInteractionWallTime = 0;
    this.startRetryDelayMs = READING_ACTIVITY_START_RETRY_INITIAL_MS;
  }

  private normalizeOffset(value: number): number {
    if (!Number.isFinite(value) || value <= 0) {
      return 0;
    }
    return Math.floor(value);
  }

  private currentUptime(): number | undefined {
    // 单调时钟不可用时宁可不计时，也不使用可回拨的墙钟推算阅历。
    return this.clock.uptime();
  }

  private currentWallTime(): number {
    return this.clock.wallTime();
  }
}
