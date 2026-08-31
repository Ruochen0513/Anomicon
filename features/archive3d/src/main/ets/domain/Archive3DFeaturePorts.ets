import { ArchiveModelDescriptor } from './ArchiveModelDescriptor';
import { ArchiveModelPackageRepository } from './ArchiveModelInstall';
import { SceneRepository } from './SceneRepository';

/** Product-facing archive graph; platform objects stay in the phone product. */
export interface Archive3DFeatureGraph {
  readonly modelPackages: ArchiveModelPackageRepository;
  readonly sceneRepository: SceneRepository;
  initialize(models?: ArchiveModelDescriptor[]): Promise<void>;
}
