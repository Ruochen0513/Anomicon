import {
  HideMode,
  HdsNavDestination,
  HdsNavDestinationTitleMode
} from '@kit.UIDesignKit';
import {
  CatalogSearchView,
  CatalogSearchViewInput,
  CatalogSearchViewModel,
  ScpCatalogSearchState,
  sharedCatalogSearchState
} from 'catalog';
import {
  LibraryContentKind,
  createLibraryContentRef
} from 'library';
import {
  AppRoutes,
  ScpArticleRouteParams
} from '../navigation/AppRoutes';
import { AppNavigationCoordinator } from '../navigation/AppNavigationCoordinator';
import { createAppTitleBarStyle } from 'anomiconbasic';

@Builder
export function ScpSearchPageBuilder(viewModel: CatalogSearchViewModel) {
  ScpSearchPage({
    viewModel: viewModel
  });
}

/**
 * Phone route host for Catalog search.
 *
 * The Catalog HAR owns the complete search content and ViewModel projection;
 * this product seam owns the HDS destination, app-scoped search-state binding,
 * NavPathStack and the replace-to-Article effect.
 */
@ComponentV2
struct ScpSearchPage {
  @Require @Param viewModel: CatalogSearchViewModel;
  private pageStack: NavPathStack | undefined = undefined;
  private readonly contentScroller: Scroller = new Scroller();
  @Local private readonly searchState: ScpCatalogSearchState = sharedCatalogSearchState();

  private openContent(itemId: string, title: string): void {
    const params: ScpArticleRouteParams = {
      content: createLibraryContentRef(LibraryContentKind.SCP, itemId, title)
    };
    // Search is replaced by Article, so returning from Article lands directly
    // on Catalog. Keep the shared query until the replacement is confirmed;
    // a failed navigation must leave the user's search recoverable.
    AppNavigationCoordinator.replace(this.pageStack, AppRoutes.ARTICLE, params)
      .then((success: boolean): void => {
        if (success) {
          this.searchState.clear();
        }
      });
  }

  build() {
    HdsNavDestination() {
      CatalogSearchView(new CatalogSearchViewInput(
        this.viewModel,
        this.contentScroller,
        this.searchState,
        (itemId: string, title: string): void => this.openContent(itemId, title)
      ));
    }
    .titleBar({
      avoidLayoutSafeArea: false,
      enableComponentSafeArea: false,
      content: {
        title: { mainTitle: '搜索' },
        backIcon: { label: '返回', componentId: 'searchBackButton' }
      },
      style: createAppTitleBarStyle()
    })
    .titleMode(HdsNavDestinationTitleMode.MINI)
    .backgroundColor($r('sys.color.background_secondary'))
    .bindToScrollable([this.contentScroller])
    .dynamicHideTitleBar({
      hideTitleArea: true,
      hideStatusBar: false,
      mode: HideMode.SCROLL_UP,
      hideRatio: 1.5
    })
    .onReady((context: NavDestinationContext) => {
      this.pageStack = context.pathStack;
    })
    .onActive(() => {
      this.viewModel.activate();
    })
    .onInactive(() => {
      this.viewModel.deactivate();
    })
    .onBackPressed(() => {
      this.searchState.clear();
      return false;
    })
    .ignoreLayoutSafeArea(
      [LayoutSafeAreaType.SYSTEM],
      [LayoutSafeAreaEdge.TOP, LayoutSafeAreaEdge.BOTTOM]
    );
  }
}
