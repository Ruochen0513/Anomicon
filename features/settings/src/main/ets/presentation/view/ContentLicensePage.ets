import {
  HideMode,
  HdsNavDestination,
  HdsNavDestinationTitleMode
} from '@kit.UIDesignKit';
import {
  AppBodyText,
  AppTypography,
  createAppTitleBarStyle,
  pageContentTop
} from 'anomiconbasic';
import {
  ContentLicenseContent,
  ContentLicenseLink
} from './SettingsViewContracts';

@Builder
export function ContentLicensePageBuilder(content: ContentLicenseContent) {
  ContentLicensePage({
    content: content
  })
}

/** Device-independent licence page; product-specific copy and URLs are injected. */
@ComponentV2
export struct ContentLicensePage {
  @Require @Param content: ContentLicenseContent;
  private scroller: Scroller = new Scroller();

  @Builder
  private linkRow(link: ContentLicenseLink) {
    Row() {
      Hyperlink(link.address, link.title)
        .color($r('sys.color.font'))
        .layoutWeight(1)
      SymbolGlyph($r('sys.symbol.arrow_up_right'))
        .fontSize(18)
        .fontColor([$r('sys.color.icon_secondary')])
    }
    .width('100%')
    .height(58)
    .padding({ left: 16, right: 16 })
  }

  @Builder
  private divider() {
    Divider()
      .strokeWidth(0.5)
      .color($r('sys.color.comp_divider'))
      .margin({ left: 16, right: 16 })
  }

  build() {
    HdsNavDestination() {
      Scroll(this.scroller) {
        Column({ space: 20 }) {
          Column({ space: 10 }) {
            Text(this.content.licenseName)
              .fontSize(AppTypography.TITLE_M)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('sys.color.font'))
            AppBodyText({
              content: this.content.usageNotice,
              color: $r('sys.color.font_secondary')
            })
          }
          .alignItems(HorizontalAlign.Start)
          .width('100%')
          .padding(20)
          .backgroundColor($r('sys.color.comp_background_primary'))
          .borderRadius(16)

          Column() {
            ForEach(this.content.links, (link: ContentLicenseLink, index: number) => {
              this.linkRow(link)
              if (index < this.content.links.length - 1) {
                this.divider()
              }
            }, (link: ContentLicenseLink) => link.address)
          }
          .width('100%')
          .backgroundColor($r('sys.color.comp_background_primary'))
          .borderRadius(16)
          .clip(true)

          Text(this.content.disclaimer)
            .fontSize(AppTypography.CAPTION_L)
            .fontColor($r('sys.color.font_tertiary'))
            .textAlign(TextAlign.Center)
            .enableAutoSpacing(true)
            .width('100%')
            .padding({ top: 4, bottom: 32 })
        }
        .width('100%')
        .constraintSize({ maxWidth: 680 })
        .padding({ left: 16, right: 16, top: pageContentTop() })
      }
      .width('100%')
      .height('100%')
      .align(Alignment.Top)
      .clip(false)
      .backgroundColor($r('sys.color.background_secondary'))
      .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
      .scrollBar(BarState.Off)
    }
    .titleBar({
      avoidLayoutSafeArea: false,
      enableComponentSafeArea: false,
      content: {
        title: {
          mainTitle: this.content.pageTitle
        },
        backIcon: {
          label: '返回',
          componentId: 'contentLicenseBackButton'
        }
      },
      style: createAppTitleBarStyle()
    })
    .titleMode(HdsNavDestinationTitleMode.MINI)
    .backgroundColor($r('sys.color.background_secondary'))
    .bindToScrollable([this.scroller])
    .dynamicHideTitleBar({
      hideTitleArea: true,
      hideStatusBar: false,
      mode: HideMode.SCROLL_UP,
      hideRatio: 1.5
    })
    .ignoreLayoutSafeArea(
      [LayoutSafeAreaType.SYSTEM],
      [LayoutSafeAreaEdge.TOP, LayoutSafeAreaEdge.BOTTOM]
    )
  }
}
