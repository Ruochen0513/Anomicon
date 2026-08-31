import { ArchiveModelDescriptor, ArchiveSceneSource } from './ArchiveModelDescriptor';

/** Lightweight source receipt; ArkGraphics3D Scene remains phone-owned. */
export class SceneLoadReceipt {
  readonly assetId: string;
  readonly source: ArchiveSceneSource;
  readonly loadedAt: number;

  constructor(assetId: string, source: ArchiveSceneSource, loadedAt: number = Date.now()) {
    this.assetId = assetId;
    this.source = source;
    this.loadedAt = loadedAt;
  }
}

export interface SceneRepository {
  load(model: ArchiveModelDescriptor): Promise<SceneLoadReceipt>;
  release(receipt: SceneLoadReceipt): void;
}
