import {
  Quaternion
} from '@kit.ArkGraphics3D';
import {
  HdsNavDestination,
  HdsNavDestinationTitleMode
} from '@kit.UIDesignKit';
import {
  AppTypography,
  PHONE_PAGE_MARGIN,
  createAppTitleBarStyle,
  pageContentTop
} from 'anomiconbasic';
import {
  Scp3DModelAsset,
  resolveScp3DModelAsset
} from 'archive3d';
import { LibraryContentKind } from 'library';
import { Scp3DArchiveRouteParams } from '../navigation/AppRoutes';
import { parseScp3DArchiveRoute } from '../navigation/RouteParamAdapters';
import {
  Archive3DSceneHandle,
  loadArchive3DScene
} from '../composition/Archive3DSceneLoader';

const VIEWER_HEIGHT: number = 388;
const MIN_MODEL_SCALE: number = 0.72;
const MAX_MODEL_SCALE: number = 1.65;
const ROTATION_SENSITIVITY_X: number = 0.008;
const ROTATION_SENSITIVITY_Y: number = 0.006;
const MIN_PITCH: number = -1.05;
const MAX_PITCH: number = 1.05;
const AUTO_ROTATE_INTERVAL_MS: number = 50;
const AUTO_ROTATE_STEP: number = 0.014;

/** Product route adapter; no native graphics object crosses the route seam. */
@Builder
export function Scp3DArchivePageBuilder() {
  Scp3DArchivePage();
}

/**
 * Offline-first three-dimensional archive screen.
 *
 * The page owns the short-lived Scene/Node graph because Component3D is a
 * product/platform concern. The archive HAR contributes only an immutable
 * manifest row, which keeps route serialization, caching and licensing data
 * independent from native graphics lifetimes.
 */
@ComponentV2
struct Scp3DArchivePage {
  private readonly scroller: Scroller = new Scroller();
  private sceneHandle: Archive3DSceneHandle | undefined = undefined;
  private loadGeneration: number = 0;
  private renderTimer: number = -1;
  private autoRotateTimer: number = -1;
  private pageActive: boolean = false;
  private pageShown: boolean = false;
  private panStartYaw: number = 0;
  private panStartPitch: number = 0;
  private pinchStartScale: number = 1;

  @Local private routeResolved: boolean = false;
  @Local private contentId: string = '';
  @Local private title: string = '';
  @Local private asset: Scp3DModelAsset | undefined = undefined;
  @Local private loading: boolean = false;
  @Local private sceneReady: boolean = false;
  // Component3D reads SceneOptions only when the native control is created;
  // keep one stable object for the lifetime of each loaded Scene so gesture
  // state changes never look like a dynamic scene-option mutation.
  private sceneOptions: SceneOptions | undefined = undefined;
  @Local private errorMessage: string = '';
  @Local private interactionHint: string = '单指旋转 · 双指缩放';
  @Local private autoRotate: boolean = false;
  @Local private creditsVisible: boolean = false;
  @Local private yaw: number = 0;
  @Local private pitch: number = 0;
  @Local private modelScale: number = 1;

  aboutToAppear(): void {
    this.pageActive = false;
    this.pageShown = false;
  }

  aboutToDisappear(): void {
    this.pageActive = false;
    this.pageShown = false;
    this.invalidateLoad();
    this.stopAutoRotate();
    this.cancelRender();
    this.releaseScene();
  }

  private isRenderable(): boolean {
    return this.pageActive && this.pageShown && this.sceneHandle !== undefined;
  }

  private applyRouteParam(param: Object | null | undefined): void {
    this.routeResolved = false;
    this.contentId = '';
    this.title = '';
    this.asset = undefined;
    this.errorMessage = '';
    this.creditsVisible = false;
    this.loading = false;
    this.invalidateLoad();
    this.stopAutoRotate();
    this.releaseScene();

    const route: Scp3DArchiveRouteParams | undefined = parseScp3DArchiveRoute(param);
    if (route === undefined || route.content.kind !== LibraryContentKind.SCP) {
      this.errorMessage = '三维档案参数无效，请从 SCP 对象文章页重新进入。';
      return;
    }
    const content = route.content;
    const resolved = resolveScp3DModelAsset(content.id, content.title);
    if (resolved === undefined) {
      this.errorMessage = '此 SCP 对象暂未配置可审计的三维模型。';
      return;
    }
    this.routeResolved = true;
    this.contentId = content.id.toUpperCase();
    this.title = content.title.trim().length > 0 ? content.title : this.contentId;
    this.asset = resolved;
    this.interactionHint = '单指旋转 · 双指缩放';
    this.requestLoadIfNeeded();
  }

  private requestLoadIfNeeded(): void {
    if (!this.pageActive || !this.pageShown || !this.routeResolved ||
      this.asset === undefined || this.loading || this.sceneReady) {
      return;
    }
    this.beginLoad(this.asset);
  }

  private beginLoad(asset: Scp3DModelAsset): void {
    const generation: number = ++this.loadGeneration;
    this.releaseScene();
    this.loading = true;
    this.errorMessage = '';
    this.interactionHint = '正在准备三维场景…';
    this.loadSceneAsync(asset, generation);
  }

  private async loadSceneAsync(asset: Scp3DModelAsset, generation: number): Promise<void> {
    try {
      const handle: Archive3DSceneHandle = await loadArchive3DScene(asset);
      if (generation !== this.loadGeneration || !this.pageActive || !this.pageShown) {
        handle.dispose();
        return;
      }
      this.sceneHandle = handle;
      this.yaw = 0;
      this.pitch = 0;
      this.modelScale = 1;
      this.sceneOptions = {
        scene: handle.scene,
        modelType: ModelType.SURFACE
      } as SceneOptions;
      this.sceneReady = true;
      this.loading = false;
      this.errorMessage = '';
      this.interactionHint = '单指旋转 · 双指缩放';
      this.applyModelTransform();
      this.requestRender();
    } catch (_error) {
      if (generation !== this.loadGeneration || !this.pageActive || !this.pageShown) {
        return;
      }
      this.loading = false;
      this.sceneReady = false;
      this.errorMessage = '三维模型暂时无法加载，请稍后重试。';
      this.interactionHint = '模型不可用';
    }
  }

  private retryLoad(): void {
    if (this.asset === undefined || !this.pageActive || !this.pageShown || this.loading) {
      return;
    }
    this.errorMessage = '';
    this.beginLoad(this.asset);
  }

  private invalidateLoad(): void {
    this.loadGeneration++;
  }

  private releaseScene(): void {
    this.sceneReady = false;
    // Remove the native control from the tree before releasing its Scene.
    this.sceneOptions = undefined;
    const handle: Archive3DSceneHandle | undefined = this.sceneHandle;
    this.sceneHandle = undefined;
    handle?.dispose();
  }

  private cancelRender(): void {
    if (this.renderTimer >= 0) {
      clearTimeout(this.renderTimer);
      this.renderTimer = -1;
    }
  }

  /** Coalesce gesture updates to roughly one native frame instead of forcing
   * a render for every touch sample. Idle scenes never use alwaysRender=true. */
  private requestRender(): void {
    if (!this.isRenderable() || this.renderTimer >= 0) {
      return;
    }
    this.renderTimer = setTimeout((): void => {
      this.renderTimer = -1;
      if (this.isRenderable()) {
        this.sceneHandle?.scene.renderFrame({ alwaysRender: false });
      }
    }, 16);
  }

  private clamp(value: number, minimum: number, maximum: number): number {
    return Math.max(minimum, Math.min(maximum, value));
  }

  private multiplyQuaternion(a: Quaternion, b: Quaternion): Quaternion {
    return {
      x: a.w * b.x + a.x * b.w + a.y * b.z - a.z * b.y,
      y: a.w * b.y - a.x * b.z + a.y * b.w + a.z * b.x,
      z: a.w * b.z + a.x * b.y - a.y * b.x + a.z * b.w,
      w: a.w * b.w - a.x * b.x - a.y * b.y - a.z * b.z
    };
  }

  private rotationFor(yaw: number, pitch: number): Quaternion {
    const yawRotation: Quaternion = {
      x: 0,
      y: Math.sin(yaw * 0.5),
      z: 0,
      w: Math.cos(yaw * 0.5)
    };
    const pitchRotation: Quaternion = {
      x: Math.sin(pitch * 0.5),
      y: 0,
      z: 0,
      w: Math.cos(pitch * 0.5)
    };
    return this.multiplyQuaternion(yawRotation, pitchRotation);
  }

  private applyModelTransform(): void {
    const root = this.sceneHandle?.modelRoot;
    if (root === undefined) {
      return;
    }
    root.rotation = this.rotationFor(this.yaw, this.pitch);
    root.scale = {
      x: this.modelScale,
      y: this.modelScale,
      z: this.modelScale
    };
    this.requestRender();
  }

  private resetView(): void {
    this.yaw = 0;
    this.pitch = 0;
    this.modelScale = 1;
    this.interactionHint = '已复位 · 单指旋转 · 双指缩放';
    this.applyModelTransform();
  }

  private changeZoom(factor: number): void {
    if (!this.sceneReady) {
      return;
    }
    this.modelScale = this.clamp(this.modelScale * factor, MIN_MODEL_SCALE, MAX_MODEL_SCALE);
    this.applyModelTransform();
  }

  private beginPan(): void {
    if (!this.sceneReady) {
      return;
    }
    this.stopAutoRotate();
    this.autoRotate = false;
    this.panStartYaw = this.yaw;
    this.panStartPitch = this.pitch;
    this.interactionHint = '拖拽中…';
  }

  private updatePan(event: GestureEvent): void {
    if (!this.sceneReady) {
      return;
    }
    this.yaw = this.panStartYaw + event.offsetX * ROTATION_SENSITIVITY_X;
    this.pitch = this.clamp(
      this.panStartPitch - event.offsetY * ROTATION_SENSITIVITY_Y,
      MIN_PITCH,
      MAX_PITCH
    );
    this.applyModelTransform();
  }

  private endPan(): void {
    if (this.sceneReady) {
      this.interactionHint = '单指旋转 · 双指缩放';
    }
  }

  private beginPinch(): void {
    if (!this.sceneReady) {
      return;
    }
    this.stopAutoRotate();
    this.autoRotate = false;
    this.pinchStartScale = this.modelScale;
    this.interactionHint = '缩放中…';
  }

  private updatePinch(event: GestureEvent): void {
    if (!this.sceneReady || !Number.isFinite(event.scale) || event.scale <= 0) {
      return;
    }
    this.modelScale = this.clamp(
      this.pinchStartScale * event.scale,
      MIN_MODEL_SCALE,
      MAX_MODEL_SCALE
    );
    this.applyModelTransform();
  }

  private endPinch(): void {
    if (this.sceneReady) {
      this.interactionHint = '单指旋转 · 双指缩放';
    }
  }

  private toggleAutoRotate(): void {
    if (!this.sceneReady) {
      return;
    }
    this.autoRotate = !this.autoRotate;
    if (this.autoRotate) {
      this.interactionHint = '自动旋转中 · 触摸可接管';
      this.startAutoRotate();
    } else {
      this.interactionHint = '单指旋转 · 双指缩放';
      this.stopAutoRotate();
    }
  }

  private startAutoRotate(): void {
    this.stopAutoRotate();
    this.autoRotateTimer = setInterval((): void => {
      if (!this.autoRotate || !this.isRenderable() || !this.sceneReady) {
        this.stopAutoRotate();
        return;
      }
      this.yaw += AUTO_ROTATE_STEP;
      this.applyModelTransform();
    }, AUTO_ROTATE_INTERVAL_MS);
  }

  private stopAutoRotate(): void {
    if (this.autoRotateTimer >= 0) {
      clearInterval(this.autoRotateTimer);
      this.autoRotateTimer = -1;
    }
  }

  /**
   * Release native rendering while the destination is not operable, but keep
   * the visibility bit intact. HDS can call onInactive when another surface
   * temporarily covers this destination; onActive must still be able to
   * recreate the scene without waiting for a second onShown callback.
   */
  private pauseRenderer(): void {
    this.pageActive = false;
    this.invalidateLoad();
    this.stopAutoRotate();
    this.autoRotate = false;
    this.cancelRender();
    this.releaseScene();
    this.loading = false;
  }

  /** Mark the destination hidden and release its renderer. */
  private hidePage(): void {
    this.pageShown = false;
    this.pauseRenderer();
  }

  private assetSizeLabel(): string {
    if (this.asset === undefined) {
      return '—';
    }
    return `${(this.asset.byteLength / 1024).toFixed(1)} KB`;
  }

  private archiveStatusLabel(): string {
    if (this.loading) {
      return 'OFFLINE · LOADING';
    }
    if (this.errorMessage.length > 0) {
      return 'OFFLINE · UNAVAILABLE';
    }
    return 'OFFLINE · READY';
  }

  @Builder
  private pageHeader() {
    Column({ space: 8 }) {
      Row() {
        Text('ARCHIVE 3D')
          .fontSize(AppTypography.CAPTION_M)
          .fontWeight(FontWeight.Bold)
          .fontColor('#6D83AE');
        Blank();
        Text(this.archiveStatusLabel())
          .fontSize(AppTypography.CAPTION_M)
          .fontColor('#6D83AE');
      }
      .width('100%');
      Text(this.contentId)
        .fontSize(30)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('sys.color.font'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis });
      Text(this.title)
        .fontSize(AppTypography.SUBTITLE_M)
        .fontColor($r('sys.color.font_secondary'))
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis });
      Text('独立三维档案空间 · 不阻塞正文阅读 · 资源随应用离线提供')
        .fontSize(AppTypography.BODY_S)
        .fontColor($r('sys.color.font_tertiary'))
        .lineHeightMultiple(AppTypography.UI_PARAGRAPH_LINE_HEIGHT);
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start);
  }

  @Builder
  private stageBadge() {
    Row({ space: 8 }) {
      Text('SCP OBJECT')
        .fontSize(10)
        .fontWeight(FontWeight.Bold)
        .fontColor('#EAF2FF')
        .padding({ left: 10, right: 10, top: 6, bottom: 6 })
        .backgroundColor('#314F86')
        .borderRadius(8);
      Text(this.interactionHint)
        .fontSize(11)
        .fontColor('#B2C3E4')
        .layoutWeight(1)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis });
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 14 });
  }

  @Builder
  private stageControls() {
    Row({ space: 8 }) {
      Button(this.autoRotate ? '停止自动旋转' : '自动旋转', { stateEffect: false })
        .height(36)
        .fontSize(12)
        .fontColor('#DCE8FF')
        .backgroundColor('#263B64')
        .onClick(() => this.toggleAutoRotate());
      Blank().layoutWeight(1);
      Button('−', { stateEffect: false })
        .width(38)
        .height(36)
        .fontSize(20)
        .fontColor('#DCE8FF')
        .backgroundColor('#1C2C4B')
        .onClick(() => this.changeZoom(0.90));
      Button('+', { stateEffect: false })
        .width(38)
        .height(36)
        .fontSize(18)
        .fontColor('#DCE8FF')
        .backgroundColor('#1C2C4B')
        .onClick(() => this.changeZoom(1.10));
      Button('复位', { stateEffect: false })
        .height(36)
        .fontSize(12)
        .fontColor('#DCE8FF')
        .backgroundColor('#1C2C4B')
        .onClick(() => this.resetView());
    }
    .width('100%')
    .padding({ left: 14, right: 14, top: 10, bottom: 12 })
    .backgroundColor('#D90D1728')
    .borderRadius(18)
    .align(Alignment.Bottom);
  }

  @Builder
  private loadingOverlay() {
    Column({ space: 10 }) {
      LoadingProgress()
        .width(34)
        .height(34)
        .color('#8FB4FF');
      Text('正在载入收容场景')
        .fontSize(AppTypography.SUBTITLE_S)
        .fontColor('#EAF0FF');
      Text(this.asset?.isConceptual === true ? '轻量概念资产 · 无外部依赖' : '正在读取已验证资源')
        .fontSize(AppTypography.BODY_S)
        .fontColor('#9DACC8');
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .backgroundColor('#E60A1220')
    .hitTestBehavior(HitTestMode.None);
  }

  @Builder
  private errorOverlay() {
    Column({ space: 12 }) {
      SymbolGlyph($r('sys.symbol.exclamationmark_circle'))
        .fontSize(28)
        .fontColor(['#F0B66B']);
      Text(this.errorMessage)
        .fontSize(AppTypography.BODY_M)
        .fontColor('#EAF0FF')
        .textAlign(TextAlign.Center)
        .lineHeightMultiple(AppTypography.UI_PARAGRAPH_LINE_HEIGHT)
        .maxLines(3)
        .textOverflow({ overflow: TextOverflow.Ellipsis });
      if (this.asset !== undefined) {
        Button('重新加载', { stateEffect: false })
          .height(38)
          .fontSize(13)
          .fontColor('#FFFFFF')
          .backgroundColor('#3E65B2')
          .onClick(() => this.retryLoad());
      } else {
        Text('请返回文章页重新进入三维档案')
          .fontSize(AppTypography.BODY_S)
          .fontColor('#AAB9D3');
      }
    }
    .width('100%')
    .height('100%')
    .padding({ left: 28, right: 28 })
    .justifyContent(FlexAlign.Center)
    .backgroundColor('#E60A1220');
  }

  @Builder
  private viewerStage() {
    Stack({ alignContent: Alignment.Top }) {
      if (this.sceneReady && this.sceneHandle !== undefined && this.sceneOptions !== undefined) {
        Component3D(this.sceneOptions)
          .width('100%')
          .height('100%')
          // Component3D accepts percentage render targets on API 26. A
          // slightly smaller GPU target preserves crisp upscaling while
          // keeping the mobile frame budget below the full surface size.
          .renderWidth('90%')
          .renderHeight('90%')
          .onAppear(() => this.requestRender());
      }

      // A dedicated gesture layer keeps the native Component3D surface as a
      // pure renderer child and takes priority over the surrounding Scroll;
      // users can scroll from the content outside the observation stage.
      Column()
        .width('100%')
        .height('100%')
        .gesture(
          PanGesture({ fingers: 1, direction: PanDirection.All, distance: 3 })
            .onActionStart(() => this.beginPan())
            .onActionUpdate((event: GestureEvent) => this.updatePan(event))
            .onActionEnd(() => this.endPan())
            .onActionCancel(() => this.endPan())
        )
        .gesture(
          // HarmonyOS uses 5vp as the default/minimum useful pinch threshold;
          // matching it avoids an ignored gesture on API 26 devices.
          PinchGesture({ fingers: 2, distance: 5 })
            .onActionStart(() => this.beginPinch())
            .onActionUpdate((event: GestureEvent) => this.updatePinch(event))
            .onActionEnd(() => this.endPinch())
            .onActionCancel(() => this.endPinch())
        )
        .accessibilityText(`${this.contentId} 三维模型，可单指旋转、双指缩放`)
        .hitTestBehavior(HitTestMode.Default);

      this.stageBadge();
      if (this.loading) {
        this.loadingOverlay();
      } else if (this.errorMessage.length > 0) {
        this.errorOverlay();
      }
      if (!this.loading && this.errorMessage.length === 0 && this.sceneReady) {
        this.stageControls();
      }
      if (this.creditsVisible) {
        this.creditsOverlay();
      }
    }
    .width('100%')
    .height(VIEWER_HEIGHT)
    .backgroundColor('#0A1221')
    .borderRadius(24)
    .clip(true)
    .accessibilityText('三维档案观察区');
  }

  @Builder
  private creditsOverlay() {
    if (this.asset !== undefined) {
      Column({ space: 12 }) {
        Row() {
          Text('资源来源与许可')
            .fontSize(AppTypography.SUBTITLE_M)
            .fontWeight(FontWeight.Bold)
            .fontColor('#F2F6FF')
            .layoutWeight(1);
          Button('关闭', { stateEffect: false })
            .height(32)
            .fontSize(12)
            .fontColor('#DCE8FF')
            .backgroundColor('#263B64')
            .onClick(() => this.creditsVisible = false);
        }
        .width('100%');
        Text(this.asset.attribution)
          .fontSize(AppTypography.BODY_S)
          .fontColor('#DCE8FF')
          .width('100%')
          .lineHeightMultiple(AppTypography.UI_PARAGRAPH_LINE_HEIGHT);
        Text(`许可：${this.asset.license}`)
          .fontSize(AppTypography.BODY_S)
          .fontColor('#AAB9D3')
          .width('100%');
        Hyperlink(this.asset.licenseUrl, '查看许可文本')
          .color('#9FC0FF')
          .width('100%');
        Text('模型为 Anomicon 自制概念资产，不代表对 SCP 原始实体的复原或官方视觉设定。')
          .fontSize(AppTypography.CAPTION_L)
          .fontColor('#F0C77A')
          .width('100%')
          .lineHeightMultiple(AppTypography.UI_PARAGRAPH_LINE_HEIGHT);
      }
      .width('92%')
      .padding(18)
      .backgroundColor('#F01A2942')
      .borderRadius(22)
      .align(Alignment.Center)
      .hitTestBehavior(HitTestMode.Default);
    }
  }

  @Builder
  private metadataRow(label: string, value: string) {
    Row() {
      Text(label)
        .fontSize(AppTypography.BODY_S)
        .fontColor($r('sys.color.font_secondary'))
        .layoutWeight(1);
      Text(value)
        .fontSize(AppTypography.BODY_S)
        .fontColor($r('sys.color.font'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis });
    }
    .width('100%')
    .padding({ top: 9, bottom: 9 });
  }

  @Builder
  private archiveInfo() {
    if (this.asset !== undefined) {
      Column({ space: 12 }) {
        Row() {
          Column({ space: 3 }) {
            Text('档案说明')
              .fontSize(AppTypography.SUBTITLE_M)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('sys.color.font'));
            Text('可审计的离线资源 · 进入即用')
              .fontSize(AppTypography.CAPTION_L)
              .fontColor($r('sys.color.font_tertiary'));
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1);
          Button('来源', { stateEffect: false })
            .height(34)
            .fontSize(12)
            .fontColor('#2F5C9E')
            .backgroundColor('#E6EEFF')
            .onClick(() => this.creditsVisible = true);
        }
        .width('100%');
        Text(this.asset.description)
          .fontSize(AppTypography.BODY_M)
          .fontColor($r('sys.color.font_secondary'))
          .width('100%')
          .lineHeightMultiple(AppTypography.UI_PARAGRAPH_LINE_HEIGHT);
        Divider()
          .strokeWidth(0.5)
          .color($r('sys.color.comp_divider'));
        this.metadataRow('资源格式', this.asset.format.toUpperCase());
        this.metadataRow('资源大小', this.assetSizeLabel());
        this.metadataRow('模型预算', `${this.asset.estimatedTriangleCount} triangles`);
        this.metadataRow('交付方式', '应用内置 · 无网络依赖');
        this.metadataRow('资源版本', this.asset.version);
      }
      .width('100%')
      .padding(18)
      .backgroundColor($r('sys.color.comp_background_primary'))
      .borderRadius(20);
    }
  }

  @Builder
  private performanceNote() {
    Column({ space: 7 }) {
      Row({ space: 8 }) {
        SymbolGlyph($r('sys.symbol.performance'))
          .fontSize(18)
          .fontColor([$r('sys.color.icon_secondary')]);
        Text('为移动端保留余量')
          .fontSize(AppTypography.SUBTITLE_S)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('sys.color.font'));
      }
      Text('模型只在本页可见且处于活动状态时加载；离开页面立即释放 Scene。默认关闭连续渲染、MSAA 与阴影，手势更新按帧合并。')
        .fontSize(AppTypography.BODY_S)
        .fontColor($r('sys.color.font_secondary'))
        .lineHeightMultiple(AppTypography.UI_PARAGRAPH_LINE_HEIGHT)
        .width('100%');
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding(16)
    .backgroundColor($r('sys.color.comp_background_tertiary'))
    .borderRadius(16);
  }

  build() {
    HdsNavDestination() {
      Scroll(this.scroller) {
        Column({ space: 16 }) {
          this.pageHeader();
          this.viewerStage();
          this.archiveInfo();
          this.performanceNote();
        }
        .width('100%')
        .constraintSize({ maxWidth: 640 })
        .padding({
          left: PHONE_PAGE_MARGIN,
          right: PHONE_PAGE_MARGIN,
          top: pageContentTop(),
          bottom: 34
        });
      }
      .width('100%')
      .height('100%')
      .backgroundColor($r('sys.color.background_secondary'))
      .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
      .scrollBar(BarState.Off);
    }
    .titleBar({
      avoidLayoutSafeArea: false,
      enableComponentSafeArea: false,
      content: {
        title: {
          mainTitle: '三维档案',
          subTitle: this.contentId
        },
        backIcon: { label: '返回', componentId: 'scp3dArchiveBackButton' }
      },
      style: createAppTitleBarStyle()
    })
    .titleMode(HdsNavDestinationTitleMode.MINI)
    .backgroundColor($r('sys.color.background_secondary'))
    .bindToScrollable([this.scroller])
    .onReady((context: NavDestinationContext) => {
      this.applyRouteParam(context.pathInfo.param as Object | null | undefined);
    })
    .onShown(() => {
      this.pageShown = true;
      this.requestLoadIfNeeded();
    })
    .onHidden(() => this.hidePage())
    .onActive(() => {
      this.pageActive = true;
      this.requestLoadIfNeeded();
    })
    .onInactive(() => this.pauseRenderer())
    .onWillDisappear(() => this.hidePage())
    .ignoreLayoutSafeArea(
      [LayoutSafeAreaType.SYSTEM],
      [LayoutSafeAreaEdge.TOP, LayoutSafeAreaEdge.BOTTOM]
    );
  }
}
