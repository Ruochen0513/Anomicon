export enum ThemeMode {
  SYSTEM = 'system',
  LIGHT = 'light',
  DARK = 'dark'
}

export class ReadingSettingsRange {
  static readonly FONT_SIZE_MIN: number = 14;
  static readonly FONT_SIZE_DEFAULT: number = 18;
  static readonly FONT_SIZE_MAX: number = 22;
  static readonly FONT_SIZE_STEP: number = 0.01;
  static readonly LINE_HEIGHT_MIN: number = 1.2;
  static readonly LINE_HEIGHT_DEFAULT: number = 1.6;
  static readonly LINE_HEIGHT_MAX: number = 2.0;
  static readonly LINE_HEIGHT_STEP: number = 0.001;
}

/** 与存储和 ArkUI 无关的设置快照。 */
export class AppSettings {
  readonly themeMode: ThemeMode;
  readonly hapticEnabled: boolean;
  readonly immersiveMaterialEnabled: boolean;
  readonly fontSize: number;
  readonly lineHeightMultiple: number;

  constructor(
    themeMode: ThemeMode = ThemeMode.SYSTEM,
    hapticEnabled: boolean = true,
    immersiveMaterialEnabled: boolean = true,
    fontSize: number = ReadingSettingsRange.FONT_SIZE_DEFAULT,
    lineHeightMultiple: number = ReadingSettingsRange.LINE_HEIGHT_DEFAULT
  ) {
    this.themeMode = themeMode;
    this.hapticEnabled = hapticEnabled;
    this.immersiveMaterialEnabled = immersiveMaterialEnabled;
    this.fontSize = normalizeReadingFontSize(fontSize);
    this.lineHeightMultiple = normalizeReadingLineHeight(lineHeightMultiple);
  }
}

export function normalizeReadingFontSize(value: number): number {
  if (!Number.isFinite(value)) {
    return ReadingSettingsRange.FONT_SIZE_DEFAULT;
  }
  const clamped = Math.max(
    ReadingSettingsRange.FONT_SIZE_MIN,
    Math.min(ReadingSettingsRange.FONT_SIZE_MAX, value)
  );
  return Math.round(clamped / ReadingSettingsRange.FONT_SIZE_STEP) *
    ReadingSettingsRange.FONT_SIZE_STEP;
}

export function normalizeReadingLineHeight(value: number): number {
  if (!Number.isFinite(value)) {
    return ReadingSettingsRange.LINE_HEIGHT_DEFAULT;
  }
  const clamped = Math.max(
    ReadingSettingsRange.LINE_HEIGHT_MIN,
    Math.min(ReadingSettingsRange.LINE_HEIGHT_MAX, value)
  );
  return Math.round(clamped / ReadingSettingsRange.LINE_HEIGHT_STEP) *
    ReadingSettingsRange.LINE_HEIGHT_STEP;
}
