import { HdsNavigationMenuContentOptions } from '@kit.UIDesignKit';
import { HomeTabId, TabItem } from './TabItem';

interface TabMenuActions {
  onCatalogSearch: () => void;
  onOpenSettings: () => void;
}

/** Phone-product tab state; menu actions are injected by the composition root. */
@ObservedV2
export class TabsViewModel {
  @Trace currentIndex: number = HomeTabId.EXPLORE;
  readonly items: TabItem[];

  constructor(actions: TabMenuActions) {
    this.items = [
      new TabItem(
        HomeTabId.EXPLORE,
        '探索',
        undefined,
        $r('sys.symbol.discover'),
        $r('sys.symbol.discover_fill')
      ),
      new TabItem(
        HomeTabId.CATALOG,
        '图鉴',
        this.createSearchMenu('搜索图鉴', actions.onCatalogSearch),
        $r('sys.symbol.list_book'),
        $r('sys.symbol.list_book_fill')
      ),
      new TabItem(
        HomeTabId.STORY,
        '故事',
        undefined,
        $r('sys.symbol.doc_text'),
        $r('sys.symbol.doc_text_fill')
      ),
      new TabItem(
        HomeTabId.TERMINAL,
        '终端',
        this.createSettingsMenu(actions.onOpenSettings),
        $r('sys.symbol.computer'),
        $r('sys.symbol.computer_fill')
      )
    ];
  }

  @Computed
  get currentTab(): TabItem {
    const index = this.currentIndex >= 0 && this.currentIndex < this.items.length ?
      this.currentIndex : 0;
    return this.items[index];
  }

  select(index: number): boolean {
    if (index < 0 || index >= this.items.length || index === this.currentIndex) {
      return false;
    }
    this.currentIndex = index;
    return true;
  }

  private createSearchMenu(
    label: string,
    action: () => void
  ): HdsNavigationMenuContentOptions {
    return {
      value: [{
        content: {
          icon: $r('sys.symbol.magnifyingglass'),
          label: label,
          action: action
        }
      }]
    };
  }

  private createSettingsMenu(action: () => void): HdsNavigationMenuContentOptions {
    return {
      value: [{
        content: {
          icon: $r('sys.symbol.gearshape'),
          label: '设置',
          action: action
        }
      }]
    };
  }
}
