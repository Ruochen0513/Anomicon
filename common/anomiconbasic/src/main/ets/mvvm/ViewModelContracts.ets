/**
 * Shared MVVM contracts used by screen ViewModels.
 *
 * This module deliberately contains no ArkUI or platform imports.  It is
 * therefore safe to use from domain/application tests and from every feature
 * without creating a dependency back to a product or a data adapter.
 */

/** Stable load states exposed by a screen ViewModel. */
export enum ViewModelLoadState {
  IDLE = 'idle',
  LOADING = 'loading',
  REFRESHING = 'refreshing',
  READY = 'ready',
  PARTIAL = 'partial',
  ERROR = 'error'
}

/**
 * Every screen ViewModel follows this lifecycle.  `activate` and
 * `deactivate` are intentionally synchronous: a ViewModel may start an
 * asynchronous load from `activate`, but a route does not have to await the
 * load in order to be released safely.
 */
export interface ViewModelLifecycle {
  activate(): void;
  deactivate(): void;
  dispose(): void;
}

/** A serializable, user-facing error description. */
export class ViewModelErrorInfo {
  readonly message: string;
  readonly code: string;
  readonly recoverable: boolean;
  readonly causeMessage: string;

  constructor(
    message: string,
    code: string = '',
    recoverable: boolean = true,
    causeMessage: string = ''
  ) {
    this.message = message.length > 0 ? message : '内容加载失败';
    this.code = code;
    this.recoverable = recoverable;
    this.causeMessage = causeMessage;
  }

  /** Convert an arbitrary caught value without leaking a platform object. */
  static from(error: Object, fallback: string = '内容加载失败'): ViewModelErrorInfo {
    if (error instanceof ViewModelErrorInfo) {
      return error;
    }
    if (error instanceof Error) {
      return new ViewModelErrorInfo(error.message || fallback, '', true, error.message);
    }
    return new ViewModelErrorInfo(fallback);
  }
}

/**
 * Immutable state handed from a ViewModel to a View.
 *
 * `fetchedAt` is the source timestamp, not the time at which a parser ran.
 * This distinction keeps stale-while-revalidate semantics observable to the
 * presentation layer.
 */
export class ViewModelSnapshot<T> {
  readonly state: ViewModelLoadState;
  readonly data: T | undefined;
  readonly error: ViewModelErrorInfo | undefined;
  readonly fetchedAt: number | undefined;
  readonly stale: boolean;
  readonly partial: boolean;
  readonly revision: number;

  constructor(
    state: ViewModelLoadState = ViewModelLoadState.IDLE,
    data: T | undefined = undefined,
    error: ViewModelErrorInfo | undefined = undefined,
    fetchedAt: number | undefined = undefined,
    stale: boolean = false,
    partial: boolean = false,
    revision: number = 0
  ) {
    this.state = state;
    this.data = data;
    this.error = error;
    this.fetchedAt = fetchedAt;
    this.stale = stale;
    this.partial = partial;
    this.revision = revision;
  }

}
