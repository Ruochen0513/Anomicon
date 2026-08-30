import { SettingsPageBuilder } from '../SettingsPage';
import { AboutPageBuilder } from '../AboutPage';
import { ContentLicensePageBuilder } from '../ContentLicensePage';
import { ScpArticlePageBuilder } from '../ScpArticlePage';
import { ScpSearchPageBuilder } from '../ScpSearchPage';
import { LibraryCollectionPageBuilder } from '../LibraryCollectionPage';
import { ExploreCollectionPageBuilder } from '../ExploreCollectionPage';
import { AppContainer } from '../../composition/AppContainer';

/**
 * Route adapters are deliberately boring: route_map only knows these product
 * builders, while each feature page remains free to evolve its ViewModel.
 * Screen-scoped ViewModels and cross-cutting ports are assembled here from
 * the product composition root; page components receive only those narrow
 * capabilities and never reach into AppContainer themselves.
 */
@Builder
export function SettingsRouteAdapter() {
  SettingsPageBuilder(
    AppContainer.getInstance().settings(),
    AppContainer.getInstance().appInfo(),
    AppContainer.getInstance().createHapticFeedback()
  );
}
@Builder
export function AboutRouteAdapter() {
  AboutPageBuilder(AppContainer.getInstance().appInfo());
}

@Builder
export function ContentLicenseRouteAdapter() {
  ContentLicensePageBuilder();
}

@Builder
export function ArticleRouteAdapter() {
  ScpArticlePageBuilder(
    AppContainer.getInstance().createArticleViewModel(),
    AppContainer.getInstance().createImagePreviewActions(),
    AppContainer.getInstance().createHapticFeedback(),
    AppContainer.getInstance().settings(),
    AppContainer.getInstance().researchProfile()
  );
}

@Builder
export function SearchRouteAdapter() {
  ScpSearchPageBuilder(AppContainer.getInstance().createCatalogSearchViewModel());
}

@Builder
export function LibraryCollectionRouteAdapter() {
  LibraryCollectionPageBuilder(AppContainer.getInstance().createLibraryCollectionVM());
}

@Builder
export function ExploreCollectionRouteAdapter() {
  ExploreCollectionPageBuilder(AppContainer.getInstance().createExploreCollectionVM());
}
