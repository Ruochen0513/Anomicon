import { common } from '@kit.AbilityKit';
import { fileIo, fileUri } from '@kit.CoreFileKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { ImagePreviewActions } from 'anomiconbasic';
import { ExternalUrlPolicy } from 'anomiconbasic';
import { ScpImageCacheService } from './ScpImageCacheService';

/**
 * Platform adapter for image-preview side effects.
 *
 * The full-screen image View never receives a UIContext, File or photo helper;
 * it only invokes this narrow port.  Keeping the adapter in catalog/data also
 * keeps cache access and HTTPS validation behind the feature boundary.
 */
export class PreviewActionsAdapter implements ImagePreviewActions {
  private readonly context: common.UIAbilityContext;
  private readonly cache: ScpImageCacheService;

  constructor(
    context: common.UIAbilityContext,
    cache: ScpImageCacheService
  ) {
    this.context = context;
    this.cache = cache;
  }

  resolveUrl(url: string): string {
    return ExternalUrlPolicy.resolveImageHttps(url);
  }

  async save(url: string): Promise<boolean> {
    try {
      const safeUrl = this.resolveUrl(url);
      const path = await this.cache.load(safeUrl);
      const uri = fileUri.getUriFromPath(path);
      const dotIndex = path.lastIndexOf('.');
      const extension = dotIndex >= 0 ? path.substring(dotIndex + 1) : 'jpg';

      // Media-library and file APIs are capability-dependent and explicitly
      // report failures through exceptions.  Convert them to the port's
      // boolean result so a denied/cancelled save never escapes the View.
      let destinationUris: string[] = [];
      try {
        destinationUris = await photoAccessHelper.getPhotoAccessHelper(this.context)
          .showAssetsCreationDialog([uri], [{
            title: 'Anomicon',
            fileNameExtension: extension,
            photoType: photoAccessHelper.PhotoType.IMAGE
          }]);
      } catch (_error) {
        return false;
      }
      if (destinationUris.length === 0) {
        return false;
      }

      let sourceFile: fileIo.File | undefined = undefined;
      let destinationFile: fileIo.File | undefined = undefined;
      try {
        destinationFile = await fileIo.open(destinationUris[0], fileIo.OpenMode.WRITE_ONLY);
        sourceFile = await fileIo.open(uri, fileIo.OpenMode.READ_ONLY);
        await fileIo.copyFile(sourceFile.fd, destinationFile.fd);
      } finally {
        if (sourceFile !== undefined) {
          try {
            fileIo.closeSync(sourceFile);
          } catch (_error) {
            // Best-effort cleanup; the original save result is already settled.
          }
        }
        if (destinationFile !== undefined) {
          try {
            fileIo.closeSync(destinationFile);
          } catch (_error) {
            // Best-effort cleanup.
          }
        }
      }
      return true;
    } catch (_error) {
      // Cache, URI, and file operations can fail on an unavailable or
      // revoked capability.  Keep the adapter contract deterministic.
      return false;
    }
  }

  async open(url: string): Promise<void> {
    await this.context.openLink(this.resolveUrl(url));
  }
}
