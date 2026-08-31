import {
  ArchiveModelInstallListener,
  ArchiveModelInstallSnapshot,
  ArchiveModelPackageRepository
} from '../domain/ArchiveModelInstall';
import { ArchiveModelDescriptor, ArchiveSceneSource } from '../domain/ArchiveModelDescriptor';

/** Application service for install, pause/resume, cancellation and deletion. */
export class ArchiveModelUseCase {
  private readonly repository: ArchiveModelPackageRepository;

  constructor(repository: ArchiveModelPackageRepository) {
    this.repository = repository;
  }

  snapshot(model: ArchiveModelDescriptor): Promise<ArchiveModelInstallSnapshot> {
    return this.repository.snapshot(model);
  }

  subscribe(model: ArchiveModelDescriptor, listener: ArchiveModelInstallListener): () => void {
    return this.repository.subscribe(model.assetId, listener);
  }

  install(model: ArchiveModelDescriptor): Promise<void> {
    return this.repository.install(model);
  }

  pause(model: ArchiveModelDescriptor): Promise<void> {
    return this.repository.pause(model);
  }

  resume(model: ArchiveModelDescriptor): Promise<void> {
    return this.repository.resume(model);
  }

  cancel(model: ArchiveModelDescriptor): Promise<void> {
    return this.repository.cancel(model);
  }

  remove(model: ArchiveModelDescriptor): Promise<void> {
    return this.repository.remove(model);
  }

  resolve(model: ArchiveModelDescriptor): Promise<ArchiveSceneSource> {
    return this.repository.resolve(model);
  }
}
