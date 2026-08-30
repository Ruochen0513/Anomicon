import { FrameCallback } from '@kit.ArkUI';
import { accessibility } from '@kit.AccessibilityKit';

// Keep the travel relative to the placeholder width so short rows and wide
// cards receive the same complete sweep.
const SKELETON_START_X: string = '-100%';
const SKELETON_END_X: string = '100%';
const SKELETON_DURATION_MS: number = 2000;

class SkeletonFrameCallback extends FrameCallback {
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
 * A geometry-preserving placeholder for text, icons, and compact list rows.
 * The parent supplies the size; the block only owns the placeholder surface
 * and its optional shimmer. Keeping that responsibility here avoids each
 * feature inventing a subtly different loading treatment.
 */
@ComponentV2
export struct SkeletonBlock {
  @Param animated: boolean = true;
  @Param radius: number = 6;
  @Local private shimmerOffsetX: string = SKELETON_START_X;
  private shimmerRunning: boolean = false;
  private shimmerToken: number = 0;

  private reduceMotion(): boolean {
    try {
      return accessibility.isAnimationReduceEnabledSync();
    } catch (_error) {
      return false;
    }
  }

  private scheduleShimmer(): void {
    if (!this.animated || this.reduceMotion() || this.shimmerRunning) {
      return;
    }
    this.shimmerOffsetX = SKELETON_START_X;
    const token = ++this.shimmerToken;
    this.getUIContext().postFrameCallback(new SkeletonFrameCallback((): void => {
      if (token !== this.shimmerToken || !this.animated || this.reduceMotion() ||
        this.shimmerRunning) {
        return;
      }
      this.shimmerRunning = true;
      this.getUIContext().animateTo({
        duration: SKELETON_DURATION_MS,
        curve: Curve.EaseInOut,
        iterations: -1,
        playMode: PlayMode.Normal
      }, (): void => {
        this.shimmerOffsetX = SKELETON_END_X;
      });
    }));
  }

  private stopShimmer(): void {
    this.shimmerToken++;
    if (!this.shimmerRunning) {
      this.shimmerOffsetX = SKELETON_START_X;
      return;
    }
    this.shimmerRunning = false;
    this.getUIContext().animateTo({ duration: 0 }, (): void => {
      this.shimmerOffsetX = SKELETON_START_X;
    });
  }

  aboutToAppear(): void {
    this.scheduleShimmer();
  }

  aboutToDisappear(): void {
    this.stopShimmer();
  }

  @Monitor('animated')
  onAnimatedChanged(): void {
    if (this.animated) {
      this.scheduleShimmer();
    } else {
      this.stopShimmer();
    }
  }

  build() {
    Stack() {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor($r('sys.color.comp_background_tertiary'))

      if (this.animated && !this.reduceMotion()) {
        Column()
          // A full-size layer makes percentage translation cover the whole
          // placeholder instead of stopping near the center of wide cards.
          .width('100%')
          .height('100%')
          .linearGradient({
            angle: 90,
            colors: [
              ['rgba(255, 255, 255, 0)', 0],
              ['rgba(255, 255, 255, 0)', 0.42],
              ['rgba(255, 255, 255, 0.24)', 0.5],
              ['rgba(255, 255, 255, 0)', 0.58],
              ['rgba(255, 255, 255, 0)', 1]
            ]
          })
          .translate({ x: this.shimmerOffsetX, y: 0 })
          .hitTestBehavior(HitTestMode.None)
      }
    }
    .width('100%')
    .height('100%')
    .borderRadius(this.radius)
    .clip(true)
  }
}
