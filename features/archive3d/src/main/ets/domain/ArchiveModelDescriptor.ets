import {
  Scp3DAssetDelivery,
  Scp3DAssetSource,
  Scp3DModelAsset
} from './Scp3DModelAsset';

/** How a reviewed model reaches the device. */
export enum ArchiveModelDelivery {
  BUNDLED = 'bundled',
  REMOTE = 'remote'
}

/** File kind understood by the product-owned ArkGraphics3D adapter. */
export enum ArchiveSceneSourceKind {
  BUNDLED_RAWFILE = 'bundled_rawfile',
  SANDBOX_FILE = 'sandbox_file'
}

/** Attribution travels with each immutable binary revision. */
export class ArchiveModelAttribution {
  readonly credits: string;
  readonly licenseName: string;
  readonly sourceUrl: string;
  readonly modificationNotice: string;

  constructor(
    credits: string,
    licenseName: string,
    sourceUrl: string,
    modificationNotice: string
  ) {
    this.credits = credits.trim();
    this.licenseName = licenseName.trim();
    this.sourceUrl = sourceUrl.trim();
    this.modificationNotice = modificationNotice.trim();
    if (this.credits.length === 0 || this.licenseName.length === 0 ||
      !this.sourceUrl.startsWith('https://') || this.modificationNotice.length === 0) {
      throw new Error('三维模型必须包含作者、许可、来源和修改说明');
    }
  }
}

/**
 * Versioned descriptor shared by bundled and on-demand packages.
 *
 * `location` is a reviewed rawfile path for bundled content and an HTTPS URL
 * for remote content. The descriptor deliberately contains no native objects.
 */
export class ArchiveModelDescriptor {
  readonly assetId: string;
  readonly contentId: string;
  readonly assetVersion: number;
  readonly delivery: ArchiveModelDelivery;
  readonly location: string;
  readonly byteLength: number;
  readonly sha256: string;
  readonly attribution: ArchiveModelAttribution;
  readonly modelAsset: Scp3DModelAsset | undefined;

  constructor(
    assetId: string,
    assetVersion: number,
    delivery: ArchiveModelDelivery,
    location: string,
    byteLength: number,
    sha256: string,
    attribution: ArchiveModelAttribution,
    contentId: string = '',
    modelAsset: Scp3DModelAsset | undefined = undefined
  ) {
    const normalizedAssetId = assetId.trim().toLowerCase();
    const normalizedLocation = location.trim();
    const normalizedHash = sha256.trim().toLowerCase();
    if (!/^[a-z0-9][a-z0-9_-]{2,63}$/.test(normalizedAssetId)) {
      throw new Error('三维模型 assetId 无效');
    }
    if (!Number.isSafeInteger(assetVersion) || assetVersion <= 0) {
      throw new Error('三维模型版本无效');
    }
    if (!Number.isSafeInteger(byteLength) || byteLength <= 12) {
      throw new Error('三维模型文件大小无效');
    }
    if (!/^[0-9a-f]{64}$/.test(normalizedHash)) {
      throw new Error('三维模型 SHA-256 无效');
    }
    if (delivery === ArchiveModelDelivery.BUNDLED) {
      if (!(normalizedLocation.startsWith('models/') || normalizedLocation.startsWith('archive3d/')) ||
        !normalizedLocation.endsWith('.glb') || normalizedLocation.indexOf('..') >= 0 ||
        normalizedLocation.indexOf('\\') >= 0) {
        throw new Error('内置三维模型 rawfile 路径无效');
      }
    } else if (!normalizedLocation.startsWith('https://')) {
      throw new Error('远程三维模型必须使用 HTTPS');
    }
    this.assetId = normalizedAssetId;
    this.contentId = contentId.trim().toLowerCase();
    this.assetVersion = assetVersion;
    this.delivery = delivery;
    this.location = normalizedLocation;
    this.byteLength = byteLength;
    this.sha256 = normalizedHash;
    this.attribution = attribution;
    this.modelAsset = modelAsset;
  }

  /** Build a descriptor from the current manifest model without touching UI. */
  static fromAsset(asset: Scp3DModelAsset, remoteUrl: string = ''): ArchiveModelDescriptor {
    if (asset.delivery === Scp3DAssetDelivery.BUNDLED &&
      asset.source !== Scp3DAssetSource.BUNDLED) {
      throw new Error('内置三维模型的来源标记不一致');
    }
    if (asset.delivery === Scp3DAssetDelivery.ON_DEMAND &&
      asset.source !== Scp3DAssetSource.REMOTE) {
      throw new Error('按需三维模型的来源标记不一致');
    }
    const delivery = asset.delivery === Scp3DAssetDelivery.BUNDLED ?
      ArchiveModelDelivery.BUNDLED : ArchiveModelDelivery.REMOTE;
    const location = delivery === ArchiveModelDelivery.BUNDLED ? asset.resourcePath :
      ArchiveModelDescriptor.inferRemoteUrl(asset, remoteUrl.length > 0 ? remoteUrl : asset.downloadUrl);
    const versionNumber = ArchiveModelDescriptor.versionNumber(asset.version);
    const attribution = new ArchiveModelAttribution(
      `${asset.attribution}; ${asset.contentAttribution}`,
      asset.license,
      asset.sourceUrl,
      asset.modificationNote
    );
    return new ArchiveModelDescriptor(
      asset.assetId,
      versionNumber,
      delivery,
      location,
      asset.byteLength,
      asset.sha256,
      attribution,
      asset.itemId,
      asset
    );
  }

  private static versionNumber(version: string): number {
    const match = /^([0-9]+)/.exec(version.trim());
    const value = match === null ? 1 : Number(match[1]);
    return Number.isSafeInteger(value) && value > 0 ? value : 1;
  }

  /**
   * Prefer an explicit CDN URL; otherwise turn the reviewed GitHub blob URL
   * used by the manifest into its raw counterpart. This keeps the manifest as
   * the source of truth while preventing a HTML blob page from being queued.
   */
  private static inferRemoteUrl(asset: Scp3DModelAsset, override: string): string {
    const explicit = override.trim();
    if (explicit.length > 0) {
      return explicit;
    }
    const source = asset.sourceUrl.trim();
    const marker = 'https://github.com/';
    const blobMarker = '/blob/';
    if (source.startsWith(marker)) {
      const relative = source.substring(marker.length);
      const blobIndex = relative.indexOf(blobMarker);
      if (blobIndex > 0) {
        const repository = relative.substring(0, blobIndex);
        const revisionAndPath = relative.substring(blobIndex + blobMarker.length);
        return `https://raw.githubusercontent.com/${repository}/${revisionAndPath}`;
      }
    }
    return source;
  }
}

/** Platform-free source passed to the product scene loader. */
export class ArchiveSceneSource {
  readonly kind: ArchiveSceneSourceKind;
  readonly assetId: string;
  readonly reference: string;
  readonly byteLength: number;
  readonly sha256: string;

  private constructor(
    kind: ArchiveSceneSourceKind,
    assetId: string,
    reference: string,
    byteLength: number,
    sha256: string
  ) {
    this.kind = kind;
    this.assetId = assetId;
    this.reference = reference;
    this.byteLength = byteLength;
    this.sha256 = sha256;
  }

  static bundled(model: ArchiveModelDescriptor): ArchiveSceneSource {
    if (model.delivery !== ArchiveModelDelivery.BUNDLED) {
      throw new Error('远程三维模型不能声明为内置 rawfile');
    }
    return new ArchiveSceneSource(
      ArchiveSceneSourceKind.BUNDLED_RAWFILE,
      model.assetId,
      model.location,
      model.byteLength,
      model.sha256
    );
  }

  static sandbox(model: ArchiveModelDescriptor, absolutePath: string): ArchiveSceneSource {
    const path = absolutePath.trim();
    if (model.delivery !== ArchiveModelDelivery.REMOTE || !path.startsWith('/data/storage/') ||
      path.length === 0 ||
      path.indexOf('..') >= 0 || path.indexOf('\\') >= 0 ||
      !path.endsWith(`/${model.sha256}.glb`)) {
      throw new Error('远程三维模型沙箱路径无效');
    }
    return new ArchiveSceneSource(
      ArchiveSceneSourceKind.SANDBOX_FILE,
      model.assetId,
      path,
      model.byteLength,
      model.sha256
    );
  }
}
