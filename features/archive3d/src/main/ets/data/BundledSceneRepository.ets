import { ArchiveModelDescriptor } from '../domain/ArchiveModelDescriptor';
import { ArchiveModelPackageRepository } from '../domain/ArchiveModelInstall';
import { SceneLoadReceipt, SceneRepository } from '../domain/SceneRepository';

/** Resolves a verified bundle/cache source without creating native scenes. */
export class BundledSceneRepository implements SceneRepository {
  private readonly packages: ArchiveModelPackageRepository;

  constructor(packages: ArchiveModelPackageRepository) {
    this.packages = packages;
  }

  async load(model: ArchiveModelDescriptor): Promise<SceneLoadReceipt> {
    const source = await this.packages.resolve(model);
    return new SceneLoadReceipt(model.assetId, source);
  }

  release(_receipt: SceneLoadReceipt): void {
    // The phone renderer owns ArkGraphics3D Scene lifetime.
  }
}
