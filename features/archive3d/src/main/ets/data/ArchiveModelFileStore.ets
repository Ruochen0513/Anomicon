import { util } from '@kit.ArkTS';
import { fileIo as fs, hash } from '@kit.CoreFileKit';
import { ArchiveModelDescriptor, ArchiveSceneSource } from '../domain/ArchiveModelDescriptor';

const GLB_HEADER_BYTES: number = 12;
const GLB_MAGIC_0: number = 0x67;
const GLB_MAGIC_1: number = 0x6c;
const GLB_MAGIC_2: number = 0x54;
const GLB_MAGIC_3: number = 0x46;
const MAX_PENDING_BYTES: number = 16 * 1024;

interface PendingModelDownloadPayload {
  assetId: string;
  assetVersion: number;
  url: string;
  byteLength: number;
  sha256: string;
  taskId: string;
  token: string;
  stagingPath: string;
}

/** Durable request-agent identity persisted before a task is started. */
export class PendingModelDownloadRecord {
  readonly assetId: string;
  readonly assetVersion: number;
  readonly url: string;
  readonly byteLength: number;
  readonly sha256: string;
  readonly taskId: string;
  readonly token: string;
  readonly stagingPath: string;

  constructor(
    assetId: string,
    assetVersion: number,
    url: string,
    byteLength: number,
    sha256: string,
    taskId: string,
    token: string,
    stagingPath: string
  ) {
    this.assetId = assetId.trim().toLowerCase();
    this.assetVersion = assetVersion;
    this.url = url.trim();
    this.byteLength = byteLength;
    this.sha256 = sha256.trim().toLowerCase();
    this.taskId = taskId.trim();
    this.token = token.trim();
    this.stagingPath = stagingPath.trim();
  }

  static create(
    model: ArchiveModelDescriptor,
    taskId: string,
    token: string,
    stagingPath: string
  ): PendingModelDownloadRecord {
    return new PendingModelDownloadRecord(
      model.assetId,
      model.assetVersion,
      model.location,
      model.byteLength,
      model.sha256,
      taskId,
      token,
      stagingPath
    );
  }

  matches(model: ArchiveModelDescriptor): boolean {
    return this.assetId === model.assetId && this.assetVersion === model.assetVersion &&
      this.url === model.location && this.byteLength === model.byteLength &&
      this.sha256 === model.sha256;
  }
}

/** Narrow binary-store seam for repository and contract tests. */
export interface ArchiveModelStore {
  initialize(): Promise<void>;
  prepareStaging(model: ArchiveModelDescriptor): Promise<string>;
  locate(model: ArchiveModelDescriptor, verifyHash?: boolean): Promise<ArchiveSceneSource | undefined>;
  verifyAndPublish(model: ArchiveModelDescriptor, stagingPath: string): Promise<ArchiveSceneSource>;
  removeInstalled(model: ArchiveModelDescriptor): Promise<void>;
  removeStaging(model: ArchiveModelDescriptor): Promise<void>;
  writePending(model: ArchiveModelDescriptor, record: PendingModelDownloadRecord): Promise<void>;
  readPending(model: ArchiveModelDescriptor): Promise<PendingModelDownloadRecord | undefined>;
  removePending(model: ArchiveModelDescriptor): Promise<void>;
  removeRecordedStaging(record: PendingModelDownloadRecord): Promise<void>;
}

/**
 * filesDir-backed content-addressed GLB store.
 *
 * A staging file is never returned to Scene.load. Size, GLB header and SHA-256
 * are checked before an atomic same-filesystem rename publishes the object.
 */
export class ArchiveModelFileStore implements ArchiveModelStore {
  private readonly rootDirectory: string;
  private readonly stagingDirectory: string;
  private readonly objectsDirectory: string;
  private readonly jobsDirectory: string;
  private readonly encoder: util.TextEncoder = util.TextEncoder.create('utf-8');
  private readonly decoder: util.TextDecoder = util.TextDecoder.create('utf-8', { fatal: true });
  private initialization: Promise<void> | undefined = undefined;

  constructor(filesDir: string) {
    const root = filesDir.trim().replace(/\/$/, '');
    if (root.length === 0 || root.indexOf('..') >= 0) {
      throw new Error('三维模型 filesDir 无效');
    }
    this.rootDirectory = `${root}/archive3d/v1`;
    this.stagingDirectory = `${this.rootDirectory}/staging`;
    this.objectsDirectory = `${this.rootDirectory}/objects`;
    this.jobsDirectory = `${this.rootDirectory}/jobs`;
  }

  initialize(): Promise<void> {
    if (this.initialization !== undefined) {
      return this.initialization;
    }
    const task = this.ensureDirectories();
    this.initialization = task;
    task.catch((): void => {
      if (this.initialization === task) {
        this.initialization = undefined;
      }
    });
    return task;
  }

  async prepareStaging(model: ArchiveModelDescriptor): Promise<string> {
    await this.initialize();
    const path = this.stagingPath(model);
    await this.removeIfExists(path);
    return path;
  }

  async locate(model: ArchiveModelDescriptor, verifyHash: boolean = false): Promise<ArchiveSceneSource | undefined> {
    await this.initialize();
    const path = this.objectPath(model);
    if (!(await this.validateBinary(path, model, verifyHash))) {
      return undefined;
    }
    return ArchiveSceneSource.sandbox(model, path);
  }

  async verifyAndPublish(model: ArchiveModelDescriptor, stagingPath: string): Promise<ArchiveSceneSource> {
    await this.initialize();
    if (stagingPath !== this.stagingPath(model)) {
      throw new Error('三维模型临时文件路径无效');
    }
    if (!(await this.validateBinary(stagingPath, model, true))) {
      await this.removeIfExists(stagingPath);
      throw new Error('下载的三维模型未通过完整性校验');
    }
    const prefixDirectory = `${this.objectsDirectory}/${model.sha256.substring(0, 2)}`;
    if (!(await fs.access(prefixDirectory))) {
      await fs.mkdir(prefixDirectory, true);
    }
    const finalPath = this.objectPath(model);
    if (await fs.access(finalPath)) {
      if (await this.validateBinary(finalPath, model, true)) {
        await this.removeIfExists(stagingPath);
        return ArchiveSceneSource.sandbox(model, finalPath);
      }
      await fs.unlink(finalPath);
    }
    await fs.rename(stagingPath, finalPath);
    return ArchiveSceneSource.sandbox(model, finalPath);
  }

  async removeInstalled(model: ArchiveModelDescriptor): Promise<void> {
    await this.removeIfExists(this.objectPath(model));
  }

  async removeStaging(model: ArchiveModelDescriptor): Promise<void> {
    await this.removeIfExists(this.stagingPath(model));
  }

  async writePending(model: ArchiveModelDescriptor, record: PendingModelDownloadRecord): Promise<void> {
    await this.initialize();
    if (!record.matches(model) || record.stagingPath !== this.stagingPath(model)) {
      throw new Error('三维下载任务记录与模型版本不匹配');
    }
    const bytes = this.encoder.encodeInto(JSON.stringify(record));
    if (bytes.byteLength <= 0 || bytes.byteLength > MAX_PENDING_BYTES) {
      throw new Error('三维下载任务记录大小无效');
    }
    const finalPath = this.jobPath(model);
    const temporaryPath = `${finalPath}.${util.generateRandomUUID(true).toLowerCase()}.tmp`;
    let file: fs.File | undefined = undefined;
    try {
      file = await fs.open(
        temporaryPath,
        fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC | fs.OpenMode.NOFOLLOW
      );
      const written = await fs.write(file.fd, bytes.buffer as ArrayBuffer);
      if (written !== bytes.byteLength) {
        throw new Error('三维下载任务记录写入不完整');
      }
      await fs.fsync(file.fd);
      await fs.close(file);
      file = undefined;
      if (await fs.access(finalPath)) {
        await fs.unlink(finalPath);
      }
      await fs.rename(temporaryPath, finalPath);
    } finally {
      await this.closeQuietly(file);
      await this.removeIfExistsQuietly(temporaryPath);
    }
  }

  async readPending(model: ArchiveModelDescriptor): Promise<PendingModelDownloadRecord | undefined> {
    await this.initialize();
    const path = this.jobPath(model);
    let file: fs.File | undefined = undefined;
    try {
      if (!(await fs.access(path))) {
        return undefined;
      }
      const stat = await fs.stat(path);
      if (!stat.isFile() || stat.size <= 0 || stat.size > MAX_PENDING_BYTES) {
        throw new Error('三维下载任务记录大小无效');
      }
      file = await fs.open(path, fs.OpenMode.READ_ONLY | fs.OpenMode.NOFOLLOW);
      const bytes = new ArrayBuffer(stat.size);
      const read = await fs.read(file.fd, bytes);
      if (read !== stat.size) {
        throw new Error('三维下载任务记录读取不完整');
      }
      const payload = JSON.parse(this.decoder.decodeToString(new Uint8Array(bytes))) as PendingModelDownloadPayload;
      if (typeof payload.assetId !== 'string' || typeof payload.assetVersion !== 'number' ||
        typeof payload.url !== 'string' || typeof payload.byteLength !== 'number' ||
        typeof payload.sha256 !== 'string' || typeof payload.taskId !== 'string' ||
        typeof payload.token !== 'string' || typeof payload.stagingPath !== 'string') {
        throw new Error('三维下载任务记录字段无效');
      }
      const record = new PendingModelDownloadRecord(
        payload.assetId,
        payload.assetVersion,
        payload.url,
        payload.byteLength,
        payload.sha256,
        payload.taskId,
        payload.token,
        payload.stagingPath
      );
      if (record.assetId !== model.assetId || record.taskId.length === 0 || record.token.length === 0 ||
        !this.isManagedStagingPath(record.stagingPath)) {
        throw new Error('三维下载任务记录身份或路径无效');
      }
      return record;
    } catch (error) {
      throw new Error(error instanceof Error ? error.message : '三维下载任务记录读取失败');
    } finally {
      await this.closeQuietly(file);
    }
  }

  async removePending(model: ArchiveModelDescriptor): Promise<void> {
    await this.removeIfExists(this.jobPath(model));
  }

  async removeRecordedStaging(record: PendingModelDownloadRecord): Promise<void> {
    if (!this.isManagedStagingPath(record.stagingPath)) {
      throw new Error('三维模型临时文件路径无效');
    }
    await this.removeIfExists(record.stagingPath);
  }

  private async validateBinary(path: string, model: ArchiveModelDescriptor, verifyHash: boolean): Promise<boolean> {
    let file: fs.File | undefined = undefined;
    try {
      if (!(await fs.access(path))) {
        return false;
      }
      const stat = await fs.stat(path);
      if (!stat.isFile() || stat.size !== model.byteLength) {
        return false;
      }
      file = await fs.open(path, fs.OpenMode.READ_ONLY | fs.OpenMode.NOFOLLOW);
      const buffer = new ArrayBuffer(GLB_HEADER_BYTES);
      const read = await fs.read(file.fd, buffer);
      if (read !== GLB_HEADER_BYTES) {
        return false;
      }
      const header = new Uint8Array(buffer);
      if (header[0] !== GLB_MAGIC_0 || header[1] !== GLB_MAGIC_1 || header[2] !== GLB_MAGIC_2 ||
        header[3] !== GLB_MAGIC_3 || this.readUint32(header, 4) !== 2 ||
        this.readUint32(header, 8) !== model.byteLength) {
        return false;
      }
      if (!verifyHash) {
        return true;
      }
      return (await hash.hash(path, 'sha256')).toLowerCase() === model.sha256;
    } catch (_error) {
      return false;
    } finally {
      await this.closeQuietly(file);
    }
  }

  private readUint32(bytes: Uint8Array, offset: number): number {
    return bytes[offset] + bytes[offset + 1] * 256 + bytes[offset + 2] * 65536 + bytes[offset + 3] * 16777216;
  }

  private stagingPath(model: ArchiveModelDescriptor): string {
    return `${this.stagingDirectory}/${model.assetId}_${model.assetVersion}_${model.sha256}.part`;
  }

  private isManagedStagingPath(path: string): boolean {
    const prefix = `${this.stagingDirectory}/`;
    if (!path.startsWith(prefix) || path.indexOf('..') >= 0 || path.indexOf('\\') >= 0) {
      return false;
    }
    return /^[a-z0-9][a-z0-9_-]{2,63}_[1-9][0-9]*_[0-9a-f]{64}\.part$/.test(path.substring(prefix.length));
  }

  private objectPath(model: ArchiveModelDescriptor): string {
    return `${this.objectsDirectory}/${model.sha256.substring(0, 2)}/${model.sha256}.glb`;
  }

  private jobPath(model: ArchiveModelDescriptor): string {
    return `${this.jobsDirectory}/${model.assetId}.json`;
  }

  private async ensureDirectories(): Promise<void> {
    const paths = [this.rootDirectory, this.stagingDirectory, this.objectsDirectory, this.jobsDirectory];
    for (let index: number = 0; index < paths.length; index++) {
      if (!(await fs.access(paths[index]))) {
        await fs.mkdir(paths[index], true);
      }
    }
  }

  private async removeIfExists(path: string): Promise<void> {
    if (await fs.access(path)) {
      await fs.unlink(path);
    }
  }

  private async removeIfExistsQuietly(path: string): Promise<void> {
    try { await this.removeIfExists(path); } catch (_error) {}
  }

  private async closeQuietly(file: fs.File | undefined): Promise<void> {
    if (file === undefined) {
      return;
    }
    try { await fs.close(file); } catch (_error) {}
  }
}
