/**
 * Actions needed by a full-screen image View.  The View renders state and
 * forwards user intent; URL validation, cache lookup, album dialogs and
 * browser launching are supplied by a platform/data adapter.
 */
export interface ImagePreviewActions {
  resolveUrl(url: string): string;
  /** Returns false when the user cancels the system save dialog. */
  save(url: string): Promise<boolean>;
  open(url: string): Promise<void>;
}
