import { BackgroundDownloadClient, IdGeneratorPort } from 'anomiconbasic';
import { Scp3DModelAsset } from '../domain/Scp3DModelAsset';
import {
  Archive3DFeatureGraph
} from '../domain/Archive3DFeaturePorts';
import { ArchiveModelDescriptor } from '../domain/ArchiveModelDescriptor';
import { ArchiveModelPackageRepository } from '../domain/ArchiveModelInstall';
import { BundledSceneRepository } from '../data/BundledSceneRepository';
import { SandboxArchiveModelPackageRepository } from '../data/SandboxArchiveModelPackageRepository';

class Archive3DFeatureGraphImpl implements Archive3DFeatureGraph {
  readonly modelPackages: ArchiveModelPackageRepository;
  readonly sceneRepository: BundledSceneRepository;
  private readonly initialModels: ArchiveModelDescriptor[];
  private initialization: Promise<void> | undefined = undefined;

  constructor(
    modelPackages: ArchiveModelPackageRepository,
    initialModels: ArchiveModelDescriptor[] = []
  ) {
    this.modelPackages = modelPackages;
    this.sceneRepository = new BundledSceneRepository(modelPackages);
    this.initialModels = initialModels.slice();
  }

  initialize(models: ArchiveModelDescriptor[] = this.initialModels): Promise<void> {
    if (this.initialization !== undefined) {
      return this.initialization;
    }
    const task = this.modelPackages.initialize(models);
    this.initialization = task;
    task.catch((): void => {
      if (this.initialization === task) {
        this.initialization = undefined;
      }
    });
    return task;
  }
}

/**
 * Build the application-scoped archive package graph.
 *
 * The download adapter is injected from the phone product so this HAR stays
 * free of notification/Ability details. `initialModels` may be omitted when
 * the product wants to register manifest rows during startup.
 */
export function createArchive3DFeatureGraph(
  filesDir: string,
  downloads: BackgroundDownloadClient,
  ids: IdGeneratorPort,
  initialModels: ArchiveModelDescriptor[] = []
): Archive3DFeatureGraph {
  const packages = new SandboxArchiveModelPackageRepository(filesDir, downloads, ids);
  return new Archive3DFeatureGraphImpl(packages, initialModels);
}

/** Convert a manifest model into a downloader descriptor at the product edge. */
export function describeScp3DAsset(asset: Scp3DModelAsset, remoteUrl: string = ''): ArchiveModelDescriptor {
  return ArchiveModelDescriptor.fromAsset(asset, remoteUrl);
}
