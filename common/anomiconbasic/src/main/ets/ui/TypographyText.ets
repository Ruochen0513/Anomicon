import { AppTypography } from '../foundation/AppTypography';

/**
 * Text without a maxLines attribute folds naturally with no line cap, so the
 * clamp branch below only applies the attributes when the caller asks for a
 * limit. This keeps the native default instead of faking "unlimited" with a
 * magic large line count.
 */
@ComponentV2
export struct AppBodyText {
  @Require @Param content: string;
  @Require @Param color: ResourceColor;
  @Param paragraphAlign: TextAlign = TextAlign.JUSTIFY;
  @Param maxLines: number | undefined = undefined;
  @Param overflow: TextOverflow = TextOverflow.Clip;

  @Builder
  private text(limit: number | undefined) {
    if (limit !== undefined) {
      Text(this.content)
        .fontSize(AppTypography.BODY_M)
        .fontWeight(FontWeight.Regular)
        .fontColor(this.color)
        .lineHeightMultiple(AppTypography.UI_PARAGRAPH_LINE_HEIGHT)
        .textAlign(this.paragraphAlign)
        .wordBreak(WordBreak.NORMAL)
        .enableAutoSpacing(true)
        .maxLines(limit)
        .textOverflow({ overflow: this.overflow })
        .width('100%')
    } else {
      Text(this.content)
        .fontSize(AppTypography.BODY_M)
        .fontWeight(FontWeight.Regular)
        .fontColor(this.color)
        .lineHeightMultiple(AppTypography.UI_PARAGRAPH_LINE_HEIGHT)
        .textAlign(this.paragraphAlign)
        .wordBreak(WordBreak.NORMAL)
        .enableAutoSpacing(true)
        .width('100%')
    }
  }

  build() {
    Column() {
      this.text(this.maxLines)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }
}

@ComponentV2
export struct ReadingBodyText {
  @Require @Param content: string;
  @Require @Param fontSize: number;
  @Require @Param lineHeightMultiple: number;
  @Require @Param color: ResourceColor;
  @Param paragraphAlign: TextAlign = TextAlign.JUSTIFY;
  @Param maxLines: number | undefined = undefined;
  @Param overflow: TextOverflow = TextOverflow.Clip;

  @Builder
  private text(limit: number | undefined) {
    if (limit !== undefined) {
      Text(this.content)
        .fontSize(this.fontSize)
        .fontWeight(FontWeight.Regular)
        .fontColor(this.color)
        .lineHeightMultiple(this.lineHeightMultiple)
        .textAlign(this.paragraphAlign)
        .wordBreak(WordBreak.NORMAL)
        .enableAutoSpacing(true)
        .maxLines(limit)
        .textOverflow({ overflow: this.overflow })
        .width('100%')
    } else {
      Text(this.content)
        .fontSize(this.fontSize)
        .fontWeight(FontWeight.Regular)
        .fontColor(this.color)
        .lineHeightMultiple(this.lineHeightMultiple)
        .textAlign(this.paragraphAlign)
        .wordBreak(WordBreak.NORMAL)
        .enableAutoSpacing(true)
        .width('100%')
    }
  }

  build() {
    Column() {
      this.text(this.maxLines)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }
}
