import {
  Animation,
  Camera,
  EnvironmentBackgroundType,
  Light,
  LightType,
  Node,
  NodeType,
  Quaternion,
  RenderingPipelineType,
  Scene,
  SceneResourceFactory
} from '@kit.ArkGraphics3D';
import {
  ArchiveSceneSource,
  ArchiveSceneSourceKind,
  Scp3DAssetDelivery,
  Scp3DAssetFormat,
  Scp3DAssetSource,
  Scp3DModelAsset
} from 'archive3d';

const INTERACTION_ROOT_NAME: string = 'AnomiconInteractivePivot';
const RUNTIME_CORRECTION_NAME: string = 'AnomiconRuntimeCorrection';
const RUNTIME_SCALE_NAME: string = 'AnomiconRuntimeScale';

/** Native scene ownership stays in the phone product, never in a HAR/VM. */
export interface Archive3DSceneHandle {
  readonly scene: Scene;
  readonly modelRoot: Node;
  readonly camera: Camera;
  readonly keyLight: Light;
  readonly fillLight: Light;
  dispose(): void;
}

/** Concrete owner keeps the native Scene and its teardown in one place. */
class Archive3DSceneHandleImpl implements Archive3DSceneHandle {
  readonly scene: Scene;
  readonly modelRoot: Node;
  readonly camera: Camera;
  readonly keyLight: Light;
  readonly fillLight: Light;
  private disposed: boolean = false;

  constructor(scene: Scene, modelRoot: Node, camera: Camera, keyLight: Light, fillLight: Light) {
    this.scene = scene;
    this.modelRoot = modelRoot;
    this.camera = camera;
    this.keyLight = keyLight;
    this.fillLight = fillLight;
  }

  dispose(): void {
    if (this.disposed) {
      return;
    }
    this.disposed = true;
    try {
      this.scene.destroy();
    } catch (_error) {
      // Teardown is idempotent from the page's point of view. Native
      // graphics resources may already be released during ability death.
    }
  }
}

/**
 * Load a reviewed asset and add the minimum camera/light rig needed by
 * custom Component3D mode.
 *
 * Bundled rows retain the old one-argument API.  On-demand rows must pass the
 * source returned by `ArchiveModelUseCase.resolve`; this keeps Scene.load
 * behind the product boundary while allowing only verified app-owned files to
 * reach ArkGraphics3D.
 */
export async function loadArchive3DScene(
  asset: Scp3DModelAsset,
  source?: ArchiveSceneSource
): Promise<Archive3DSceneHandle> {
  validateAsset(asset);
  validateSource(asset, source);

  // Keep rawfile references literal. The ArkGraphics resource resolver is
  // stricter on some API 26 builds than ordinary string APIs; a reviewed
  // manifest row is deliberately mapped here instead of interpolating a path.
  const scene: Scene = source === undefined ?
    await loadBundledScene(asset.resourcePath) : await loadSceneSource(source);
  try {
    const root: Node | null = scene.root;
    if (root === null) {
      throw new Error('场景缺少根节点');
    }

    disableAuthoredCamerasAndLights(root);
    const factory: SceneResourceFactory = scene.getResourceFactory();
    const authoredRoot: Node | undefined = findNodeByName(root, INTERACTION_ROOT_NAME);
    const modelRoot: Node = authoredRoot ?? await createInteractionRoot(root, factory);
    // Runtime corrections live below the interactive pivot.  The page is free
    // to overwrite `modelRoot.scale` while pinch-zooming without losing the
    // scale/offset required by an upstream export.
    await applyRuntimeCorrection(modelRoot, root, factory, asset);
    sampleAndPausePose(scene, asset);

    const target = modelRoot.position;

    const camera: Camera = await factory.createCamera({ name: 'AnomiconArchiveCamera' });
    camera.position = {
      x: target.x,
      y: target.y,
      z: target.z + asset.cameraDistance
    };
    camera.rotation = identityQuaternion();
    camera.fov = asset.fieldOfView;
    camera.nearPlane = 0.05;
    camera.farPlane = 100;
    camera.clearColor = { r: 0.018, g: 0.027, b: 0.052, a: 1 };
    camera.msaa = false;
    camera.renderingPipeline = RenderingPipelineType.FORWARD_LIGHTWEIGHT;
    camera.enabled = true;
    attachIfOrphan(root, camera);

    const keyLight: Light = await factory.createLight(
      { name: 'AnomiconArchiveKeyLight' },
      LightType.DIRECTIONAL
    );
    keyLight.rotation = quaternionFromPitchYaw(-0.62, -0.58);
    keyLight.color = { r: 1, g: 0.92, b: 0.80, a: 1 };
    keyLight.intensity = 4.2;
    // Shadows are deliberately off for the first mobile asset budget. They
    // can be enabled per reviewed asset once a device tier is known.
    keyLight.shadowEnabled = false;
    keyLight.enabled = true;
    attachIfOrphan(root, keyLight);

    const fillLight: Light = await factory.createLight(
      { name: 'AnomiconArchiveFillLight' },
      LightType.DIRECTIONAL
    );
    fillLight.rotation = quaternionFromPitchYaw(0.35, 0.95);
    fillLight.color = { r: 0.42, g: 0.62, b: 1, a: 1 };
    fillLight.intensity = 1.8;
    fillLight.shadowEnabled = false;
    fillLight.enabled = true;
    attachIfOrphan(root, fillLight);

    // A custom clear colour is only honoured when the environment background
    // is disabled. The assignment is supported by API 12+ and avoids a gray
    // default environment behind the dark archive stage.
    scene.environment.backgroundType = EnvironmentBackgroundType.BACKGROUND_NONE;
    scene.renderFrame({ alwaysRender: false });

    return new Archive3DSceneHandleImpl(scene, modelRoot, camera, keyLight, fillLight);
  } catch (error) {
    try {
      scene.destroy();
    } catch (_error) {
      // Preserve the original configuration error.
    }
    throw new Error(error instanceof Error ? error.message : '三维场景配置失败');
  }
}

function validateAsset(asset: Scp3DModelAsset): void {
  if (asset.format !== Scp3DAssetFormat.GLTF && asset.format !== Scp3DAssetFormat.GLB) {
    throw new Error('当前设备仅支持 glTF/GLB 三维模型');
  }
  if (asset.hasExternalDependencies) {
    throw new Error('包含外部依赖的三维模型暂不支持');
  }
  if (asset.source === Scp3DAssetSource.BUNDLED && asset.delivery !== Scp3DAssetDelivery.BUNDLED) {
    throw new Error('内置三维模型交付状态无效');
  }
  if (asset.source === Scp3DAssetSource.REMOTE && asset.delivery !== Scp3DAssetDelivery.ON_DEMAND) {
    throw new Error('远程三维模型交付状态无效');
  }
}

function validateSource(asset: Scp3DModelAsset, source: ArchiveSceneSource | undefined): void {
  if (source === undefined) {
    if (asset.source !== Scp3DAssetSource.BUNDLED || asset.delivery !== Scp3DAssetDelivery.BUNDLED) {
      throw new Error('按需下载资源尚未安装');
    }
    validateBundledPath(asset.resourcePath);
    return;
  }

  if (source.assetId !== asset.assetId || source.byteLength !== asset.byteLength ||
    source.sha256.toLowerCase() !== asset.sha256.toLowerCase()) {
    throw new Error('三维模型来源与清单校验信息不一致');
  }
  if (source.kind === ArchiveSceneSourceKind.BUNDLED_RAWFILE) {
    if (asset.source !== Scp3DAssetSource.BUNDLED || asset.delivery !== Scp3DAssetDelivery.BUNDLED) {
      throw new Error('远程三维模型不能从 rawfile 加载');
    }
    validateBundledPath(source.reference);
    return;
  }
  if (source.kind === ArchiveSceneSourceKind.SANDBOX_FILE) {
    if (asset.source !== Scp3DAssetSource.REMOTE || asset.delivery !== Scp3DAssetDelivery.ON_DEMAND) {
      throw new Error('内置三维模型不能从下载缓存加载');
    }
    validateSandboxPath(source.reference, source.sha256);
    return;
  }
  throw new Error('未知三维模型来源');
}

function validateBundledPath(pathValue: string): void {
  const path: string = pathValue.trim();
  if (!(path.startsWith('models/') || path.startsWith('archive3d/')) ||
    path.indexOf('..') >= 0 || path.indexOf('\\') >= 0 || !path.endsWith('.glb')) {
    throw new Error('三维模型资源路径无效');
  }
}

function validateSandboxPath(pathValue: string, sha256Value: string): void {
  const path: string = pathValue.trim();
  const hash: string = sha256Value.trim().toLowerCase();
  const expectedSuffix: string = `/archive3d/v1/objects/${hash.substring(0, 2)}/${hash}.glb`;
  if (!/^([0-9a-f]{64})$/.test(hash) || !path.startsWith('/data/storage/') ||
    path.indexOf('..') >= 0 || path.indexOf('\\') >= 0 || !path.endsWith(expectedSuffix)) {
    throw new Error('远程三维模型沙箱路径无效');
  }
}

async function loadSceneSource(source: ArchiveSceneSource): Promise<Scene> {
  if (source.kind === ArchiveSceneSourceKind.SANDBOX_FILE) {
    return await Scene.load(source.reference);
  }
  return await loadBundledScene(source.reference);
}

async function loadBundledScene(resourcePath: string): Promise<Scene> {
  switch (resourcePath) {
    case 'models/scp-049.glb':
      return await Scene.load($rawfile('models/scp-049.glb'));
    case 'models/scp-106.glb':
      return await Scene.load($rawfile('models/scp-106.glb'));
    case 'models/scp-173.glb':
      return await Scene.load($rawfile('models/scp-173.glb'));
    case 'models/scp-939.glb':
      return await Scene.load($rawfile('models/scp-939.glb'));
    // Preserve compatibility with the historical archive3d rawfile naming
    // while new manifest rows use `models/scp-xxx.glb`.
    case 'archive3d/scp_049.glb':
      return await Scene.load($rawfile('models/scp-049.glb'));
    case 'archive3d/scp_106.glb':
      return await Scene.load($rawfile('models/scp-106.glb'));
    case 'archive3d/scp_173.glb':
      return await Scene.load($rawfile('models/scp-173.glb'));
    case 'archive3d/scp_939.glb':
      return await Scene.load($rawfile('models/scp-939.glb'));
    default:
      throw new Error('三维模型资源尚未注册');
  }
}

/**
 * Return an authored pivot when present; otherwise put every renderable
 * top-level child below a product-owned pivot. Moving children (instead of a
 * single geometry leaf) preserves upstream skeleton/animation transforms.
 */
async function createInteractionRoot(root: Node, factory: SceneResourceFactory): Promise<Node> {
  const renderChildren: Node[] = [];
  const count: number = root.children.count();
  for (let index: number = 0; index < count; index++) {
    const child: Node | null = root.children.get(index);
    if (child !== null && child.nodeType !== NodeType.CAMERA && child.nodeType !== NodeType.LIGHT) {
      renderChildren.push(child);
    }
  }
  if (renderChildren.length === 0) {
    // A geometry root cannot be reparented without cloning the whole Scene.
    // Keep it as the interaction target; this is an unusual but valid GLB.
    return findFirstRenderableNode(root) ?? root;
  }

  const pivot: Node = await factory.createNode({ name: INTERACTION_ROOT_NAME });
  root.children.append(pivot);
  for (let index: number = 0; index < renderChildren.length; index++) {
    const child: Node = renderChildren[index];
    root.children.remove(child);
    pivot.children.append(child);
  }
  return pivot;
}

/** Apply raw-export corrections below the page-controlled interaction pivot. */
async function applyRuntimeCorrection(
  modelRoot: Node,
  sceneRoot: Node,
  factory: SceneResourceFactory,
  asset: Scp3DModelAsset
): Promise<void> {
  const scale: number = Number.isFinite(asset.runtimeScale) && asset.runtimeScale > 0 ?
    asset.runtimeScale : 1;
  const offsetX: number = Number.isFinite(asset.runtimeOffsetX) ? asset.runtimeOffsetX : 0;
  const offsetY: number = Number.isFinite(asset.runtimeOffsetY) ? asset.runtimeOffsetY : 0;
  const offsetZ: number = Number.isFinite(asset.runtimeOffsetZ) ? asset.runtimeOffsetZ : 0;
  if (scale === 1 && offsetX === 0 && offsetY === 0 && offsetZ === 0) {
    return;
  }

  // If the interaction target is itself a geometry root, there is no legal
  // parent to insert below it. Apply the correction directly as a safe
  // fallback; normal imported GLBs use a Node root and take the branch below.
  if (modelRoot.nodeType === NodeType.GEOMETRY) {
    const currentScale = modelRoot.scale;
    modelRoot.scale = {
      x: currentScale.x * scale,
      y: currentScale.y * scale,
      z: currentScale.z * scale
    };
    const currentPosition = modelRoot.position;
    modelRoot.position = {
      // Match the normal wrapper order (scale above offset) even in this
      // degenerate geometry-root fallback where a second parent is impossible.
      x: currentPosition.x + offsetX * scale,
      y: currentPosition.y + offsetY * scale,
      z: currentPosition.z + offsetZ * scale
    };
    return;
  }

  const correction: Node = await factory.createNode({ name: RUNTIME_CORRECTION_NAME });
  const children: Node[] = [];
  const count: number = modelRoot.children.count();
  for (let index: number = 0; index < count; index++) {
    const child: Node | null = modelRoot.children.get(index);
    if (child !== null && child !== correction && child !== sceneRoot &&
      child.nodeType !== NodeType.CAMERA && child.nodeType !== NodeType.LIGHT) {
      children.push(child);
    }
  }
  let correctionParent: Node = modelRoot;
  if (scale !== 1) {
    // Keep scale above offset, matching the build-time archive-root tool so
    // the centering translation remains stable for unusual unit systems.
    const scaleRoot: Node = await factory.createNode({ name: RUNTIME_SCALE_NAME });
    scaleRoot.scale = { x: scale, y: scale, z: scale };
    modelRoot.children.append(scaleRoot);
    correctionParent = scaleRoot;
  }
  correctionParent.children.append(correction);
  for (let index: number = 0; index < children.length; index++) {
    const child: Node = children[index];
    modelRoot.children.remove(child);
    correction.children.append(child);
  }
  correction.position = { x: offsetX, y: offsetY, z: offsetZ };
}

/** Sample one named clip and pause every animation to keep archive scenes idle. */
function sampleAndPausePose(scene: Scene, asset: Scp3DModelAsset): void {
  let animations: Animation[] = [];
  try {
    animations = scene.animations;
  } catch (_error) {
    // Animation resources are optional for a static archive render. A scene
    // that exposes no animation collection can still be displayed normally.
    return;
  }
  if (animations.length === 0) {
    return;
  }
  const requestedName: string = asset.poseAnimationName.trim();
  let selected: Animation | undefined = undefined;
  for (let index: number = 0; index < animations.length; index++) {
    const animation: Animation = animations[index];
    if (requestedName.length > 0 && animation.name === requestedName && selected === undefined) {
      selected = animation;
    }
  }
  // Exporters occasionally change only the case of a clip name. Match that
  // harmless variation, but never fall back to an arbitrary first clip.
  if (selected === undefined && requestedName.length > 0) {
    const foldedName: string = requestedName.toLowerCase();
    for (let index: number = 0; index < animations.length; index++) {
      const animation: Animation = animations[index];
      if (animation.name.trim().toLowerCase() === foldedName) {
        selected = animation;
        break;
      }
    }
  }

  for (let index: number = 0; index < animations.length; index++) {
    const animation: Animation = animations[index];
    try {
      animation.pause();
      if (animation !== selected) {
        animation.enabled = false;
      }
    } catch (_error) {
      // A malformed optional animation must not prevent static rendering.
    }
  }
  if (selected === undefined) {
    return;
  }

  try {
    selected.enabled = true;
    const ratio: number = Number.isFinite(asset.poseSampleRatio) ?
      Math.max(0, Math.min(1, asset.poseSampleRatio)) : 0.5;
    selected.seek(ratio);
    selected.pause();
  } catch (_error) {
    // Keep the imported bind pose if the optional clip cannot be sampled.
  }
}

function attachIfOrphan(root: Node, node: Node): void {
  if (node.parent === null) {
    root.children.append(node);
  }
}

function disableAuthoredCamerasAndLights(node: Node): void {
  if (node.nodeType === NodeType.CAMERA) {
    (node as Camera).enabled = false;
  } else if (node.nodeType === NodeType.LIGHT) {
    (node as Light).enabled = false;
  }
  const count: number = node.children.count();
  for (let index: number = 0; index < count; index++) {
    const child: Node | null = node.children.get(index);
    if (child !== null) {
      disableAuthoredCamerasAndLights(child);
    }
  }
}

function findNodeByName(node: Node, name: string): Node | undefined {
  if (node.name === name) {
    return node;
  }
  const count: number = node.children.count();
  for (let index: number = 0; index < count; index++) {
    const child: Node | null = node.children.get(index);
    if (child !== null) {
      const match: Node | undefined = findNodeByName(child, name);
      if (match !== undefined) {
        return match;
      }
    }
  }
  return undefined;
}

function findFirstRenderableNode(node: Node): Node | undefined {
  if (node.nodeType === NodeType.GEOMETRY) {
    return node;
  }
  const count: number = node.children.count();
  for (let index: number = 0; index < count; index++) {
    const child: Node | null = node.children.get(index);
    if (child === null || child.nodeType === NodeType.CAMERA || child.nodeType === NodeType.LIGHT) {
      continue;
    }
    const match: Node | undefined = findFirstRenderableNode(child);
    if (match !== undefined) {
      return match;
    }
  }
  return undefined;
}

function identityQuaternion(): Quaternion {
  return { x: 0, y: 0, z: 0, w: 1 };
}

function quaternionFromPitchYaw(pitch: number, yaw: number): Quaternion {
  const pitchSin: number = Math.sin(pitch / 2);
  const pitchCos: number = Math.cos(pitch / 2);
  const yawSin: number = Math.sin(yaw / 2);
  const yawCos: number = Math.cos(yaw / 2);
  return {
    x: pitchSin * yawCos,
    y: pitchCos * yawSin,
    z: -pitchSin * yawSin,
    w: pitchCos * yawCos
  };
}
