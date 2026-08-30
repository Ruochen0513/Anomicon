import catalogSearchSnapshotTest from './CatalogSearchSnapshot.test';
import scpPageFetchLifecycleTest from './ScpPageFetchLifecycle.test';
import staticCatalogHtmlParserTest from './StaticCatalogHtmlParser.test';
import scpPreviewImageFallbackTest from './ScpPreviewImageFallback.test';

/** Local Hypium entry point for the Catalog HAR. */
export default function testsuite(): void {
  catalogSearchSnapshotTest();
  scpPageFetchLifecycleTest();
  staticCatalogHtmlParserTest();
  scpPreviewImageFallbackTest();
}
