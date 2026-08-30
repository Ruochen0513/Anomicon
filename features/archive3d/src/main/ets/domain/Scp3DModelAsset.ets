/**
 * 3D asset metadata deliberately contains no ArkUI or ArkGraphics objects.
 *
 * The product renderer consumes this manifest and owns the native Scene
 * lifetime. Keeping the manifest serializable makes it possible to replace
 * the bundled prototype with a verified sandbox asset later without changing
 * the article route or the renderer contract.
 */
export const SCP_3D_ASSET_SCHEMA_VERSION: number = 1;

export enum Scp3DAssetFormat {
  GLTF = 'gltf',
  GLB = 'glb'
}

export enum Scp3DAssetSource {
  BUNDLED = 'bundled'
}

export enum Scp3DAssetKind {
  SPECIFIC = 'specific',
  GENERIC = 'generic'
}

/** Build-time manifest row; it never contains a native Scene handle. */
export interface Scp3DAssetManifestEntry {
  readonly assetId: string;
  readonly resourcePath: string;
  readonly format: Scp3DAssetFormat;
  readonly source: Scp3DAssetSource;
  readonly version: string;
  readonly byteLength: number;
  readonly sha256: string;
  readonly license: string;
  readonly licenseUrl: string;
  readonly attribution: string;
  readonly sourceLabel: string;
  readonly description: string;
  /** Renderer budget metadata; it is not a runtime graphics object. */
  readonly estimatedTriangleCount: number;
  readonly renderTargetMaxPx: number;
  readonly hasExternalDependencies: boolean;
  readonly isConceptual: boolean;
}

/**
 * An item-bound asset descriptor. The same immutable asset can be rendered for
 * many SCP pages while `itemId` keeps the page identity explicit in analytics
 * and future cache keys.
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
  readonly version: string;
  readonly byteLength: number;
  readonly sha256: string;
  readonly license: string;
  readonly licenseUrl: string;
  readonly attribution: string;
  readonly sourceLabel: string;
  readonly description: string;
  readonly estimatedTriangleCount: number;
  readonly renderTargetMaxPx: number;
  readonly hasExternalDependencies: boolean;
  readonly isConceptual: boolean;

  constructor(
    itemId: string,
    title: string,
    manifest: Scp3DAssetManifestEntry,
    kind: Scp3DAssetKind = Scp3DAssetKind.GENERIC
  ) {
    this.schemaVersion = SCP_3D_ASSET_SCHEMA_VERSION;
    this.assetId = manifest.assetId;
    this.itemId = itemId;
    this.title = title;
    this.kind = kind;
    this.resourcePath = manifest.resourcePath;
    this.format = manifest.format;
    this.source = manifest.source;
    this.version = manifest.version;
    this.byteLength = manifest.byteLength;
    this.sha256 = manifest.sha256;
    this.license = manifest.license;
    this.licenseUrl = manifest.licenseUrl;
    this.attribution = manifest.attribution;
    this.sourceLabel = manifest.sourceLabel;
    this.description = manifest.description;
    this.estimatedTriangleCount = manifest.estimatedTriangleCount;
    this.renderTargetMaxPx = manifest.renderTargetMaxPx;
    this.hasExternalDependencies = manifest.hasExternalDependencies;
    this.isConceptual = manifest.isConceptual;
  }
}

/**
 * A small, self-contained, authored glTF asset. It is intentionally a
 * manifest row instead of a URL guessed from an SCP number: future per-item
 * models can be added as reviewed rows without opening a network path.
 */
const GENERIC_CONTAINMENT_ASSET: Scp3DAssetManifestEntry = {
  assetId: 'containment-artifact-v1',
  resourcePath: 'models/containment-artifact.gltf',
  format: Scp3DAssetFormat.GLTF,
  source: Scp3DAssetSource.BUNDLED,
  version: '1.0.0',
  byteLength: 34663,
  sha256: 'fb413953da39505a06129d4adc53816e3982335aa22769a408a3bda006a32be5',
  license: 'Apache-2.0（Anomicon 自制模型）',
  licenseUrl: 'https://www.apache.org/licenses/LICENSE-2.0',
  attribution: 'Anomicon 三维档案组（低多边形概念资产）',
  sourceLabel: 'Anomicon 内置概念资产',
  description: '用于展示收容档案交互的轻量低多边形模型；并非条目原始插图。',
  estimatedTriangleCount: 304,
  renderTargetMaxPx: 640,
  hasExternalDependencies: false,
  isConceptual: true
};

/** Public manifest for future asset review tooling and settings attribution. */
export const SCP_3D_ASSET_MANIFEST: Scp3DAssetManifestEntry[] = [
  GENERIC_CONTAINMENT_ASSET
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

/**
 * Resolve only reviewed, bundled rows. The generic row is an explicit
 * fallback in the manifest and is labelled as such in the UI; no remote URL
 * is inferred from the object id.
 */
export function resolveScp3DModelAsset(
  itemId: string,
  title: string = ''
): Scp3DModelAsset | undefined {
  const normalized = normalizeScpObjectId(itemId);
  if (normalized === undefined) {
    return undefined;
  }
  const manifest = SCP_3D_ASSET_MANIFEST[0];
  return new Scp3DModelAsset(
    normalized,
    boundedTitle(title, normalized.toUpperCase()),
    manifest,
    Scp3DAssetKind.GENERIC
  );
}
