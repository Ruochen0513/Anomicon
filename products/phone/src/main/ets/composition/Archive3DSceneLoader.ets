import {
  Camera,
  EnvironmentBackgroundType,
  Light,
  LightType,
  Node,
  NodeType,
  Quaternion,
  RenderingPipelineType,
  Scene
} from '@kit.ArkGraphics3D';
import {
  Scp3DAssetFormat,
  Scp3DAssetSource,
  Scp3DModelAsset
} from 'archive3d';

const INTERACTION_ROOT_NAME: string = 'AnomiconInteractivePivot';
const MODEL_CAMERA_DISTANCE: number = 4.2;
const MODEL_FIELD_OF_VIEW: number = Math.PI / 3;

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
 * Load one reviewed bundled asset and add the minimum camera/light rig needed
 * by custom Component3D mode.  The function intentionally accepts no URL:
 * remote files must first be verified and committed to an app-owned cache in
 * a future download adapter before they can reach this boundary.
 */
export async function loadArchive3DScene(asset: Scp3DModelAsset): Promise<Archive3DSceneHandle> {
  validateBundledAsset(asset);
  // Keep rawfile references literal. The ArkGraphics resource resolver is
  // stricter on some API 26 builds than ordinary string APIs; a reviewed
  // manifest row is deliberately mapped here instead of interpolating a path.
  let scene: Scene;
  switch (asset.resourcePath) {
    case 'models/containment-artifact.gltf':
      scene = await Scene.load($rawfile('models/containment-artifact.gltf'));
      break;
    default:
      throw new Error('三维模型资源尚未注册');
  }
  try {
    const root: Node | null = scene.root;
    if (root === null) {
      throw new Error('场景缺少根节点');
    }

    disableAuthoredCamerasAndLights(root);
    const modelRoot: Node = findNodeByName(root, INTERACTION_ROOT_NAME) ??
      findFirstRenderableNode(root) ?? root;
    const target = modelRoot.position;
    const factory = scene.getResourceFactory();

    const camera: Camera = await factory.createCamera({ name: 'AnomiconArchiveCamera' });
    camera.position = {
      x: target.x,
      y: target.y,
      z: target.z + MODEL_CAMERA_DISTANCE
    };
    camera.rotation = identityQuaternion();
    camera.fov = MODEL_FIELD_OF_VIEW;
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

function validateBundledAsset(asset: Scp3DModelAsset): void {
  if (asset.source !== Scp3DAssetSource.BUNDLED) {
    throw new Error('三维模型必须来自应用内置资源');
  }
  if (asset.format !== Scp3DAssetFormat.GLTF && asset.format !== Scp3DAssetFormat.GLB) {
    throw new Error('当前设备仅支持 glTF/GLB 三维模型');
  }
  const path: string = asset.resourcePath.trim();
  if (!path.startsWith('models/') || path.indexOf('..') >= 0 || path.indexOf('\\') >= 0 ||
    !(path.endsWith('.gltf') || path.endsWith('.glb'))) {
    throw new Error('三维模型资源路径无效');
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
      return child;
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
