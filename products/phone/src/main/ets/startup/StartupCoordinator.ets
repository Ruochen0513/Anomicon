import { accessibility } from '@kit.AccessibilityKit';
import { FrameCallback, UIContext } from '@kit.ArkUI';
import { schedulingOptimization } from '@kit.FASTKit';
import { ExploreHeroAnchor } from 'explore';
import { FastPerformanceHintScope } from '../composition/FastPerformanceHints';

const MAX_LAYOUT_WAIT_FRAMES: number = 5;
const REQUIRED_STABLE_LAYOUT_SAMPLES: number = 2;
const LAYOUT_SAMPLE_TOLERANCE: number = 0.25;
const LOCKED_LAYOUT_TOLERANCE: number = 2;
/** Native starting-window mark size, shared by the coordinator and overlay. */
export const SYSTEM_START_MARK_PX: number = 144;
const STARTING_WINDOW_RELEASE_WATCHDOG_MS: number = 5200;
const SYSTEM_WINDOW_SETTLE_DELAY_MS: number = 360;
const CONTAIN_DURATION_MS: number = 140;
const UNFOLD_DURATION_MS: number = 300;
const HANDOFF_DURATION_MS: number = 220;
const FALLBACK_EXIT_DURATION_MS: number = 210;
const REDUCED_MOTION_DURATION_MS: number = 120;

interface StartupRect {
  readonly windowX: number;
  readonly windowY: number;
  readonly width: number;
  readonly height: number;
}

interface StartupLayoutSample {
  readonly overlay: StartupRect;
  readonly hero: ExploreHeroAnchor;
}

/** The brand sequence is process-cold-start only, not a page recreation effect. */
let startupClaimedInProcess: boolean = false;
let startingWindowReleased: boolean = false;
const startingWindowReleaseTasks: Array<() => void> = [];

/**
 * EntryAbility calls this after the explicit Starting Window removal attempt
 * resolves.  On failure it still releases the coordinator so the page reaches
 * a ready state beneath the system's five-second safety timeout.
 */
export function notifyStartingWindowReleased(): void {
  if (startingWindowReleased) {
    return;
  }
  startingWindowReleased = true;
  const tasks = startingWindowReleaseTasks.splice(0, startingWindowReleaseTasks.length);
  tasks.forEach((task: () => void): void => task());
}

function runAfterStartingWindowRelease(task: () => void): () => void {
  if (startingWindowReleased) {
    task();
    return (): void => {};
  }
  startingWindowReleaseTasks.push(task);
  return (): void => {
    const taskIndex = startingWindowReleaseTasks.indexOf(task);
    if (taskIndex >= 0) {
      startingWindowReleaseTasks.splice(taskIndex, 1);
    }
  };
}

class StartupFrameCallback extends FrameCallback {
  private readonly task: () => void;

  constructor(task: () => void) {
    super();
    this.task = task;
  }

  onFrame(_frameTimeInNano: number): void {
    this.task();
  }
}

/**
 * Product-owned state for the cold-start hand-off.
 *
 * Explore reports only a window-space numeric anchor. This coordinator waits
 * for two stable frames, locks the destination, and then drives transform and
 * opacity properties only. Network/repository state never gates the motion.
 */
@ObservedV2
export class StartupCoordinator {
  @Trace visible: boolean = true;
  @Trace backdropOpacity: number = 1;
  @Trace markOpacity: number = 1;
  @Trace cubeOpacity: number = 1;
  @Trace cubeScale: number = 1;
  @Trace branchOpacity: number = 1;
  @Trace branchScale: number = 1;
  @Trace primaryOffsetX: number = 0;
  @Trace primaryOffsetY: number = 0;
  @Trace accentOffsetX: number = 0;
  @Trace accentOffsetY: number = 0;

  @Trace deckVisible: boolean = false;
  @Trace deckOpacity: number = 0;
  @Trace deckScale: number = 0.12;
  @Trace deckTranslateX: number = 0;
  @Trace deckTranslateY: number = 0;
  @Trace deckX: number = 0;
  @Trace deckY: number = 0;
  @Trace deckWidth: number = 0;
  @Trace deckHeight: number = 0;
  @Trace homeSkeletonAnimated: boolean = false;

  private started: boolean = false;
  private finished: boolean = false;
  private aborting: boolean = false;
  private targetLocked: boolean = false;
  private waitedFrames: number = 0;
  private stableSamples: number = 0;
  private heroAnchor: ExploreHeroAnchor | undefined = undefined;
  private overlayRect: StartupRect | undefined = undefined;
  private lastLayoutSample: StartupLayoutSample | undefined = undefined;
  private uiContext: UIContext | undefined = undefined;
  private releaseGateOpened: boolean = false;
  private releaseGateToken: number = 0;
  private cancelStartingWindowWait: (() => void) | undefined = undefined;
  /** The custom cold-start hand-off is a bounded app-launch scene. */
  private readonly launchHint: FastPerformanceHintScope =
    new FastPerformanceHintScope(
      schedulingOptimization.SceneType.APP_LAUNCH,
      schedulingOptimization.DurationType.MEDIUM
    );

  constructor() {
    if (startupClaimedInProcess) {
      this.visible = false;
      this.backdropOpacity = 0;
      this.markOpacity = 0;
      this.homeSkeletonAnimated = true;
      this.finished = true;
      return;
    }
    startupClaimedInProcess = true;
  }

  updateHeroAnchor(anchor: ExploreHeroAnchor): void {
    if (!this.validHeroAnchor(anchor)) {
      return;
    }
    if (this.targetLocked && this.heroAnchor !== undefined &&
      !this.sameHeroAnchor(this.heroAnchor, anchor, LOCKED_LAYOUT_TOLERANCE)) {
      this.heroAnchor = anchor;
      this.fastExit();
      return;
    }
    this.heroAnchor = anchor;
  }

  updateOverlayArea(area: Area): void {
    const rect = this.rectFromArea(area);
    if (rect === undefined) {
      return;
    }
    if (this.targetLocked && this.overlayRect !== undefined &&
      !this.sameRect(this.overlayRect, rect, LOCKED_LAYOUT_TOLERANCE)) {
      this.overlayRect = rect;
      this.fastExit();
      return;
    }
    this.overlayRect = rect;
  }

  start(uiContext: UIContext): void {
    if (this.started || this.finished) {
      return;
    }
    this.started = true;
    this.launchHint.begin();
    this.uiContext = uiContext;
    const gateToken = ++this.releaseGateToken;
    const openReleaseGate = (watchdogExpired: boolean): void => {
      if (gateToken !== this.releaseGateToken || this.releaseGateOpened ||
        this.finished || this.aborting) {
        return;
      }
      this.releaseGateOpened = true;
      this.cancelStartingWindowWait?.();
      this.cancelStartingWindowWait = undefined;
      if (watchdogExpired) {
        // The system removes an app-controlled Starting Window after its own
        // safety timeout, but it does not notify this coordinator. Never leave
        // the product overlay blocking input if the removal callback is lost.
        this.fallbackExit(uiContext);
        return;
      }
      if (this.shouldReduceMotion()) {
        this.reducedMotionExit(uiContext);
      } else {
        // The explicit release attempt completes before this measured delay
        // begins. HarmonyOS exposes no launch-animation-finished event, so keep
        // the matching mark still briefly, then sample the stable destination.
        uiContext.postDelayedFrameCallback(new StartupFrameCallback((): void => {
          this.waitForStableLayout(uiContext);
        }), SYSTEM_WINDOW_SETTLE_DELAY_MS);
      }
    };
    this.cancelStartingWindowWait = runAfterStartingWindowRelease((): void => {
      openReleaseGate(false);
    });
    uiContext.postDelayedFrameCallback(new StartupFrameCallback((): void => {
      openReleaseGate(true);
    }), STARTING_WINDOW_RELEASE_WATCHDOG_MS);
  }

  dispose(): void {
    this.finish();
  }

  private waitForStableLayout(uiContext: UIContext): void {
    if (this.finished || this.aborting) {
      return;
    }
    this.waitedFrames++;
    const sample = this.currentLayoutSample();
    if (sample !== undefined) {
      if (this.lastLayoutSample !== undefined &&
        this.sameLayoutSample(this.lastLayoutSample, sample)) {
        this.stableSamples++;
      } else {
        this.stableSamples = 1;
        this.lastLayoutSample = sample;
      }
      if (this.stableSamples >= REQUIRED_STABLE_LAYOUT_SAMPLES) {
        this.lockHeroTarget(uiContext, sample);
        // V2 geometry set by lockHeroTarget must reach the render tree before
        // animateTo opens a transaction.  Otherwise the still-dirty position
        // and size are captured with the transform and the card takes a false
        // detour instead of travelling directly to its locked anchor.
        uiContext.postFrameCallback(new StartupFrameCallback((): void => {
          this.runContainment(uiContext);
        }));
        return;
      }
    }
    if (this.waitedFrames >= MAX_LAYOUT_WAIT_FRAMES) {
      this.runContainment(uiContext);
      return;
    }
    uiContext.postFrameCallback(new StartupFrameCallback((): void => {
      this.waitForStableLayout(uiContext);
    }));
  }

  private lockHeroTarget(uiContext: UIContext, sample: StartupLayoutSample): void {
    const localX = sample.hero.windowX - sample.overlay.windowX;
    const localY = sample.hero.windowY - sample.overlay.windowY;
    this.deckX = localX;
    this.deckY = localY;
    this.deckWidth = sample.hero.width;
    this.deckHeight = sample.hero.height;
    const overlayCenterX = sample.overlay.width / 2;
    const overlayCenterY = sample.overlay.height / 2;
    const deckCenterX = localX + sample.hero.width / 2;
    const deckCenterY = localY + sample.hero.height / 2;
    this.deckTranslateX = overlayCenterX - deckCenterX;
    this.deckTranslateY = overlayCenterY - deckCenterY;
    const markSize = uiContext.px2vp(SYSTEM_START_MARK_PX);
    const shortestDeckEdge = Math.max(1, Math.min(sample.hero.width, sample.hero.height));
    this.deckScale = Math.max(0.1, Math.min(0.22, markSize / shortestDeckEdge));
    this.deckOpacity = 0;
    this.deckVisible = true;
    this.targetLocked = true;
  }

  private runContainment(uiContext: UIContext): void {
    if (this.finished || this.aborting) {
      return;
    }
    uiContext.animateTo({
      duration: CONTAIN_DURATION_MS,
      curve: Curve.EaseInOut,
      onFinish: (): void => {
        if (this.targetLocked) {
          this.unfoldArchive(uiContext);
        } else {
          this.fallbackExit(uiContext);
        }
      }
    }, (): void => {
      this.branchOpacity = 0;
      this.branchScale = 0.72;
      this.primaryOffsetX = 4;
      this.primaryOffsetY = 3;
      this.accentOffsetX = -4;
      this.accentOffsetY = 3;
      this.cubeScale = 0.78;
    });
  }

  private unfoldArchive(uiContext: UIContext): void {
    if (this.finished || this.aborting) {
      return;
    }
    uiContext.animateTo({
      duration: UNFOLD_DURATION_MS,
      curve: Curve.Friction,
      onFinish: (): void => this.handoffToHome(uiContext)
    }, (): void => {
      this.cubeOpacity = 0;
      this.deckOpacity = 1;
      this.deckScale = 1;
      this.deckTranslateX = 0;
      this.deckTranslateY = 0;
    });
  }

  private handoffToHome(uiContext: UIContext): void {
    if (this.finished || this.aborting) {
      return;
    }
    // The real Explore skeleton becomes the only shimmer owner.  It starts
    // after the empty archive container has reached its final geometry, while
    // the opaque startup surface still masks the first submitted frame.
    this.homeSkeletonAnimated = true;
    uiContext.animateTo({
      duration: HANDOFF_DURATION_MS,
      curve: Curve.EaseOut,
      onFinish: (): void => this.finish()
    }, (): void => {
      this.backdropOpacity = 0;
      this.markOpacity = 0;
      this.deckOpacity = 0;
    });
  }

  private fallbackExit(uiContext: UIContext): void {
    if (this.finished || this.aborting) {
      return;
    }
    this.homeSkeletonAnimated = true;
    uiContext.animateTo({
      duration: FALLBACK_EXIT_DURATION_MS,
      curve: Curve.EaseOut,
      onFinish: (): void => this.finish()
    }, (): void => {
      this.backdropOpacity = 0;
      this.markOpacity = 0;
    });
  }

  private reducedMotionExit(uiContext: UIContext): void {
    if (this.finished) {
      return;
    }
    this.homeSkeletonAnimated = true;
    uiContext.animateTo({
      duration: REDUCED_MOTION_DURATION_MS,
      curve: Curve.EaseOut,
      onFinish: (): void => this.finish()
    }, (): void => {
      this.backdropOpacity = 0;
      this.markOpacity = 0;
    });
  }

  private fastExit(): void {
    if (!this.targetLocked || this.finished || this.aborting) {
      return;
    }
    this.aborting = true;
    const uiContext = this.uiContext;
    if (uiContext === undefined) {
      this.finish();
      return;
    }
    this.homeSkeletonAnimated = true;
    uiContext.animateTo({
      duration: REDUCED_MOTION_DURATION_MS,
      curve: Curve.EaseOut,
      onFinish: (): void => this.finish()
    }, (): void => {
      this.backdropOpacity = 0;
      this.markOpacity = 0;
      this.deckOpacity = 0;
    });
  }

  private currentLayoutSample(): StartupLayoutSample | undefined {
    if (this.overlayRect === undefined || this.heroAnchor === undefined) {
      return undefined;
    }
    return {
      overlay: this.overlayRect,
      hero: this.heroAnchor
    };
  }

  private sameLayoutSample(before: StartupLayoutSample, after: StartupLayoutSample): boolean {
    return this.sameRect(before.overlay, after.overlay, LAYOUT_SAMPLE_TOLERANCE) &&
      this.sameHeroAnchor(before.hero, after.hero, LAYOUT_SAMPLE_TOLERANCE);
  }

  private sameHeroAnchor(
    before: ExploreHeroAnchor,
    after: ExploreHeroAnchor,
    tolerance: number
  ): boolean {
    return Math.abs(before.windowX - after.windowX) <= tolerance &&
      Math.abs(before.windowY - after.windowY) <= tolerance &&
      Math.abs(before.width - after.width) <= tolerance &&
      Math.abs(before.height - after.height) <= tolerance;
  }

  private sameRect(before: StartupRect, after: StartupRect, tolerance: number): boolean {
    return Math.abs(before.windowX - after.windowX) <= tolerance &&
      Math.abs(before.windowY - after.windowY) <= tolerance &&
      Math.abs(before.width - after.width) <= tolerance &&
      Math.abs(before.height - after.height) <= tolerance;
  }

  private validRect(rect: StartupRect): boolean {
    return Number.isFinite(rect.windowX) && Number.isFinite(rect.windowY) &&
      Number.isFinite(rect.width) && Number.isFinite(rect.height) &&
      rect.width > 0 && rect.height > 0;
  }

  private validHeroAnchor(anchor: ExploreHeroAnchor): boolean {
    return Number.isFinite(anchor.windowX) && Number.isFinite(anchor.windowY) &&
      Number.isFinite(anchor.width) && Number.isFinite(anchor.height) &&
      anchor.width > 0 && anchor.height > 0;
  }

  private rectFromArea(area: Area): StartupRect | undefined {
    const globalPosition = area.globalPosition;
    if (globalPosition === undefined || globalPosition.x === undefined ||
      globalPosition.y === undefined) {
      return undefined;
    }
    const rect: StartupRect = {
      windowX: Number(globalPosition.x),
      windowY: Number(globalPosition.y),
      width: Number(area.width),
      height: Number(area.height)
    };
    return this.validRect(rect) ? rect : undefined;
  }

  private shouldReduceMotion(): boolean {
    try {
      return accessibility.isAnimationReduceEnabledSync();
    } catch (_error) {
      return false;
    }
  }

  private finish(): void {
    if (this.finished) {
      return;
    }
    this.finished = true;
    this.launchHint.end();
    this.releaseGateToken++;
    this.cancelStartingWindowWait?.();
    this.cancelStartingWindowWait = undefined;
    this.backdropOpacity = 0;
    this.markOpacity = 0;
    this.deckOpacity = 0;
    this.deckVisible = false;
    this.homeSkeletonAnimated = true;
    this.visible = false;
    this.uiContext = undefined;
  }
}
