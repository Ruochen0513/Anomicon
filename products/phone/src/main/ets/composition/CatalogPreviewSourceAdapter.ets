import { fileUri } from '@kit.CoreFileKit';

/**
 * Convert an application sandbox path into an ArkUI-compatible image source.
 * Catalog presentation receives this narrow function and stays independent of
 * CoreFileKit and product filesystem details.
 */
export function resolveCatalogPreviewFileSource(path: string): string {
  return fileUri.getUriFromPath(path);
}
