/**
 * 3D asset metadata deliberately contains no ArkUI or ArkGraphics objects.
 *
 * The product renderer consumes this manifest and owns the native Scene
 * lifetime. Keeping the manifest serializable makes it possible to add an
 * on-demand downloader later without changing the article route or viewer
 * contract.
 */
export const SCP_3D_ASSET_SCHEMA_VERSION: number = 2;

export enum Scp3DAssetFormat {
  GLTF = 'gltf',
  GLB = 'glb'
}

/** Where the reviewed source came from. */
export enum Scp3DAssetSource {
  BUNDLED = 'bundled'
}

/** How the app delivers the bytes to the viewer. */
export enum Scp3DAssetDelivery {
  BUNDLED = 'bundled',
  ON_DEMAND = 'on_demand'
}

export enum Scp3DAssetKind {
  SPECIFIC = 'specific',
  GENERIC = 'generic'
}

/** Build-time manifest row; it never contains a native Scene handle. */
export interface Scp3DAssetManifestEntry {
  readonly assetId: string;
  readonly contentId: string;
  readonly resourcePath: string;
  readonly format: Scp3DAssetFormat;
  readonly source: Scp3DAssetSource;
  readonly delivery: Scp3DAssetDelivery;
  readonly version: string;
  readonly byteLength: number;
  readonly sha256: string;
  readonly license: string;
  readonly licenseUrl: string;
  readonly attribution: string;
  readonly contentAttribution: string;
  readonly sourceLabel: string;
  readonly sourceUrl: string;
  readonly contentSourceUrl: string;
  readonly description: string;
  readonly objectClass: string;
  /** A short, item-specific licensing or representation notice. */
  readonly notice: string;
  /** Processing performed before the binary was shipped in the app. */
  readonly modificationNote: string;
  /** Renderer budget metadata; it is not a runtime graphics object. */
  readonly estimatedTriangleCount: number;
  readonly renderTargetMaxPx: number;
  readonly cameraDistance: number;
  readonly fieldOfView: number;
  readonly initialScale: number;
  readonly minimumScale: number;
  readonly maximumScale: number;
  readonly hasExternalDependencies: boolean;
  readonly isConceptual: boolean;
}

/**
 * An item-bound asset descriptor. The same immutable asset can be rendered for
 * one canonical SCP page while `itemId` keeps the page identity explicit in
 * analytics and future cache keys.
 */
export class Scp3DModelAsset {
  readonly schemaVersion: number;
  readonly assetId: string;
  readonly itemId: string;
  readonly title: string;
  readonly kind: Scp3DAssetKind;
  readonly resourcePath: string;
  readonly format: Scp3DAssetFormat;
  readonly source: Scp3DAssetSource;
  readonly delivery: Scp3DAssetDelivery;
  readonly version: string;
  readonly byteLength: number;
  readonly sha256: string;
  readonly license: string;
  readonly licenseUrl: string;
  readonly attribution: string;
  readonly contentAttribution: string;
  readonly sourceLabel: string;
  readonly sourceUrl: string;
  readonly contentSourceUrl: string;
  readonly description: string;
  readonly objectClass: string;
  readonly notice: string;
  readonly modificationNote: string;
  readonly estimatedTriangleCount: number;
  readonly renderTargetMaxPx: number;
  readonly cameraDistance: number;
  readonly fieldOfView: number;
  readonly initialScale: number;
  readonly minimumScale: number;
  readonly maximumScale: number;
  readonly hasExternalDependencies: boolean;
  readonly isConceptual: boolean;

  constructor(
    itemId: string,
    title: string,
    manifest: Scp3DAssetManifestEntry,
    kind: Scp3DAssetKind = Scp3DAssetKind.SPECIFIC
  ) {
    this.schemaVersion = SCP_3D_ASSET_SCHEMA_VERSION;
    this.assetId = manifest.assetId;
    this.itemId = itemId;
    this.title = title;
    this.kind = kind;
    this.resourcePath = manifest.resourcePath;
    this.format = manifest.format;
    this.source = manifest.source;
    this.delivery = manifest.delivery;
    this.version = manifest.version;
    this.byteLength = manifest.byteLength;
    this.sha256 = manifest.sha256;
    this.license = manifest.license;
    this.licenseUrl = manifest.licenseUrl;
    this.attribution = manifest.attribution;
    this.contentAttribution = manifest.contentAttribution;
    this.sourceLabel = manifest.sourceLabel;
    this.sourceUrl = manifest.sourceUrl;
    this.contentSourceUrl = manifest.contentSourceUrl;
    this.description = manifest.description;
    this.objectClass = manifest.objectClass;
    this.notice = manifest.notice;
    this.modificationNote = manifest.modificationNote;
    this.estimatedTriangleCount = manifest.estimatedTriangleCount;
    this.renderTargetMaxPx = manifest.renderTargetMaxPx;
    this.cameraDistance = manifest.cameraDistance;
    this.fieldOfView = manifest.fieldOfView;
    this.initialScale = manifest.initialScale;
    this.minimumScale = manifest.minimumScale;
    this.maximumScale = manifest.maximumScale;
    this.hasExternalDependencies = manifest.hasExternalDependencies;
    this.isConceptual = manifest.isConceptual;
  }
}

const SOURCE_REPOSITORY: string = 'https://github.com/Yni-Viar/scp-unity-assets';
const SOURCE_COMMIT: string = '7fda38944f51db7ee3aeb4d9e5ca821263153da5';
const CC_BY_SA_3_URL: string = 'https://creativecommons.org/licenses/by-sa/3.0/';
const MOBILE_PROCESSING_NOTICE: string =
  '移动端优化：移除动画、将内嵌贴图缩放至 1024px、清理未使用数据，并加入档案交互根节点。';
const REPRESENTATION_NOTICE: string =
  '社区创作的视觉重建，不代表 SCP 官方形象或实体复原。';

function sourceUrl(folder: string, fileName: string): string {
  return `${SOURCE_REPOSITORY}/blob/${SOURCE_COMMIT}/Rigged-Ready/${folder}/${fileName}.glb`;
}

/**
 * Reviewed, bundled seed models. Only rows in this list expose a 三维档案
 * action; an unknown SCP number never falls back to a generic placeholder.
 */
export const SCP_3D_ASSET_MANIFEST: Scp3DAssetManifestEntry[] = [
  {
    assetId: 'scp-049-mobile-v2',
    contentId: 'scp-049',
    resourcePath: 'models/scp-049.glb',
    format: Scp3DAssetFormat.GLB,
    source: Scp3DAssetSource.BUNDLED,
    delivery: Scp3DAssetDelivery.BUNDLED,
    version: '2.0.0-mobile',
    byteLength: 6945764,
    sha256: '70781b10ed06b5b95e10dd4c0f31db366a2f01a2c61290cd43e2cea8b42e0287',
    license: 'CC BY-SA 3.0',
    licenseUrl: CC_BY_SA_3_URL,
    attribution: 'Aruspice（模型/贴图）、Shakles（绑定/动画）、PixelPuffin（概念设计）',
    contentAttribution: '条目作者：Gabriel Jade；重写：djkaktus、Gabriel Jade',
    sourceLabel: 'Yni-Viar/scp-unity-assets · Rigged-Ready/Scp049',
    sourceUrl: sourceUrl('Scp049', 'Scp049'),
    contentSourceUrl: 'https://scp-wiki.wikidot.com/scp-049',
    description: 'SCP-049 的社区视觉重建移动端版本。',
    objectClass: 'EUCLID',
    notice: REPRESENTATION_NOTICE,
    modificationNote: MOBILE_PROCESSING_NOTICE,
    estimatedTriangleCount: 12720,
    renderTargetMaxPx: 768,
    cameraDistance: 6.8,
    fieldOfView: 0.56,
    initialScale: 1.09,
    minimumScale: 0.66,
    maximumScale: 1.75,
    hasExternalDependencies: false,
    isConceptual: true
  },
  {
    assetId: 'scp-173-mobile-v2',
    contentId: 'scp-173',
    resourcePath: 'models/scp-173.glb',
    format: Scp3DAssetFormat.GLB,
    source: Scp3DAssetSource.BUNDLED,
    delivery: Scp3DAssetDelivery.BUNDLED,
    version: '2.0.0-mobile',
    byteLength: 3969704,
    sha256: '4b346ef05a2e0ae674d034e9e0c83e5b3ce2ee90b027363afe88c4e951e9f18c',
    license: 'CC BY-SA 3.0',
    licenseUrl: CC_BY_SA_3_URL,
    attribution: 'Aruspice（模型/贴图）、Shakles（绑定/动画）、PixelPuffin（概念设计）',
    contentAttribution: '条目作者：Moto42',
    sourceLabel: 'Yni-Viar/scp-unity-assets · Rigged-Ready/Scp173',
    sourceUrl: sourceUrl('Scp173', 'Scp173'),
    contentSourceUrl: 'https://scp-wiki.wikidot.com/scp-173',
    description: 'SCP-173 NEO（版本 2）社区视觉重建移动端版本。',
    objectClass: 'EUCLID',
    notice: `${REPRESENTATION_NOTICE} 本资源标记为 NEO/版本 2 重制；SCP 官方许可指南对旧版雕塑形象的商业使用另有说明，请在分发前复核。`,
    modificationNote: MOBILE_PROCESSING_NOTICE,
    estimatedTriangleCount: 16104,
    renderTargetMaxPx: 768,
    cameraDistance: 6.8,
    fieldOfView: 0.56,
    initialScale: 1.04,
    minimumScale: 0.62,
    maximumScale: 1.62,
    hasExternalDependencies: false,
    isConceptual: true
  },
  {
    assetId: 'scp-939-mobile-v2',
    contentId: 'scp-939',
    resourcePath: 'models/scp-939.glb',
    format: Scp3DAssetFormat.GLB,
    source: Scp3DAssetSource.BUNDLED,
    delivery: Scp3DAssetDelivery.BUNDLED,
    version: '2.0.0-mobile',
    byteLength: 3207564,
    sha256: '6abc175b9f7b79f53bf27e1a21c821155b68bbfcf148b53e0c1c06474b4fd7ab',
    license: 'CC BY-SA 3.0',
    licenseUrl: CC_BY_SA_3_URL,
    attribution: 'Apocryphos（模型）、Shadowscale（贴图）、Shakles（绑定/动画）',
    contentAttribution: '条目作者：Adam Smascher、EchoFourDelta',
    sourceLabel: 'Yni-Viar/scp-unity-assets · Rigged-Ready/Scp939',
    sourceUrl: sourceUrl('Scp939', 'Scp939'),
    contentSourceUrl: 'https://scp-wiki.wikidot.com/scp-939',
    description: 'SCP-939 的社区视觉重建移动端版本。',
    objectClass: 'KETER',
    notice: REPRESENTATION_NOTICE,
    modificationNote: MOBILE_PROCESSING_NOTICE,
    estimatedTriangleCount: 10368,
    renderTargetMaxPx: 768,
    cameraDistance: 6.8,
    fieldOfView: 0.56,
    initialScale: 1.32,
    minimumScale: 0.79,
    maximumScale: 2.11,
    hasExternalDependencies: false,
    isConceptual: true
  }
];

/** Normalize and validate an SCP object id at the feature boundary. */
export function normalizeScpObjectId(value: string): string | undefined {
  let normalized = value.trim().toLowerCase();
  while (normalized.startsWith('/')) {
    normalized = normalized.substring(1);
  }
  if (normalized.length === 0 || normalized.length > 68 ||
    !/^scp-[a-z0-9][a-z0-9_-]{0,63}$/.test(normalized)) {
    return undefined;
  }
  return normalized;
}

function boundedTitle(title: string, fallback: string): string {
  const trimmed = title.trim();
  if (trimmed.length === 0) {
    return fallback;
  }
  return trimmed.length > 120 ? trimmed.substring(0, 120) : trimmed;
}

function findManifestEntry(normalizedId: string): Scp3DAssetManifestEntry | undefined {
  for (let index: number = 0; index < SCP_3D_ASSET_MANIFEST.length; index++) {
    const candidate = SCP_3D_ASSET_MANIFEST[index];
    // The availability gate is intentionally conservative: an on-demand row
    // will become visible only after a future installer promotes it to a
    // bundled/app-owned entry.
    if (candidate.contentId === normalizedId &&
      candidate.delivery === Scp3DAssetDelivery.BUNDLED) {
      return candidate;
    }
  }
  return undefined;
}

/** True only for SCP object ids with a reviewed, shipped 3D model. */
export function hasScp3DModel(itemId: string): boolean {
  const normalized = normalizeScpObjectId(itemId);
  return normalized !== undefined && findManifestEntry(normalized) !== undefined;
}

/** Resolve only reviewed rows; no network URL or generic fallback is inferred. */
export function resolveScp3DModelAsset(
  itemId: string,
  title: string = ''
): Scp3DModelAsset | undefined {
  const normalized = normalizeScpObjectId(itemId);
  if (normalized === undefined) {
    return undefined;
  }
  const manifest = findManifestEntry(normalized);
  if (manifest === undefined) {
    return undefined;
  }
  return new Scp3DModelAsset(
    normalized,
    boundedTitle(title, normalized.toUpperCase()),
    manifest,
    Scp3DAssetKind.SPECIFIC
  );
}
