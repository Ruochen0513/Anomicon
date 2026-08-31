/**
 * Platform-neutral request-agent download contracts.
 *
 * Feature code only observes immutable snapshots and never retains a
 * BasicServicesKit task. This keeps a durable transfer usable after a page
 * leaves the navigation stack and makes the repository straightforward to
 * fake in tests.
 */
export enum BackgroundDownloadState {
  INITIALIZED = 'initialized',
  WAITING = 'waiting',
  RUNNING = 'running',
  RETRYING = 'retrying',
  PAUSED = 'paused',
  STOPPED = 'stopped',
  COMPLETED = 'completed',
  FAILED = 'failed',
  REMOVED = 'removed',
  UNKNOWN = 'unknown'
}

export enum BackgroundDownloadErrorKind {
  TASK_NOT_FOUND = 'task_not_found',
  TEMPORARILY_UNAVAILABLE = 'temporarily_unavailable',
  INVALID_TASK_STATE = 'invalid_task_state',
  INVALID_REQUEST = 'invalid_request',
  PERMISSION_DENIED = 'permission_denied',
  UNKNOWN = 'unknown'
}

export class BackgroundDownloadError extends Error {
  readonly kind: BackgroundDownloadErrorKind;
  readonly platformCode: number;

  constructor(message: string, kind: BackgroundDownloadErrorKind, platformCode: number = 0) {
    super(message);
    this.name = 'BackgroundDownloadError';
    this.kind = kind;
    this.platformCode = platformCode;
  }
}

export interface BackgroundDownloadRequest {
  readonly url: string;
  /** Absolute destination below the application's filesDir. */
  readonly destinationPath: string;
  readonly title: string;
  readonly description: string;
  readonly token: string;
  readonly expectedBytes: number;
  readonly allowMetered: boolean;
}

export interface BackgroundDownloadSnapshot {
  readonly id: string;
  readonly token: string;
  readonly state: BackgroundDownloadState;
  readonly destinationPath: string;
  readonly processedBytes: number;
  readonly totalBytes: number;
  readonly expectedBytes: number;
  readonly reason: string;
  readonly faultCode: number;
}

export type BackgroundDownloadListener = (snapshot: BackgroundDownloadSnapshot) => void;

/** dispose() only detaches observers; it never cancels a system task. */
export interface BackgroundDownloadTask {
  readonly id: string;
  readonly token: string;
  start(): Promise<void>;
  pause(): Promise<void>;
  resume(): Promise<void>;
  cancel(): Promise<void>;
  inspect(): Promise<BackgroundDownloadSnapshot>;
  subscribe(listener: BackgroundDownloadListener): () => void;
  dispose(): void;
}

export interface BackgroundDownloadClient {
  create(request: BackgroundDownloadRequest): Promise<BackgroundDownloadTask>;
  reconnect(id: string, token: string): Promise<BackgroundDownloadTask>;
  remove(id: string): Promise<void>;
}
