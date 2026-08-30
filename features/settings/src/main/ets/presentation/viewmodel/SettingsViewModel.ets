import {
  AppSettings,
  ReadingSettingsRange,
  ThemeMode,
  normalizeReadingFontSize,
  normalizeReadingLineHeight,
} from '../../domain/SettingsModels';
import { SettingsRepository, ThemeModeApplier } from '../../domain/SettingsRepository';

/** 设置页及全局外观消费者共享的可观察展示状态。 */
@ObservedV2
export class SettingsViewModel {
  @Trace themeMode: ThemeMode = ThemeMode.SYSTEM;
  @Trace hapticEnabled: boolean = true;
  @Trace immersiveMaterialEnabled: boolean = true;
  @Trace fontSize: number = ReadingSettingsRange.FONT_SIZE_DEFAULT;
  @Trace lineHeightMultiple: number = ReadingSettingsRange.LINE_HEIGHT_DEFAULT;
  @Trace errorMessage: string = '';

  private readonly repository: SettingsRepository;
  private readonly themeModeApplier: ThemeModeApplier;
  // Settings 是应用级共享状态；生命周期方法不清空或重建设置。
  private lifecycleDisposed: boolean = false;

  constructor(repository: SettingsRepository, themeModeApplier: ThemeModeApplier) {
    this.repository = repository;
    this.themeModeApplier = themeModeApplier;
    this.publish(repository.load());
    this.errorMessage = repository.lastError ?? '';
  }

  /** 释放页面引用；持久化设置仍由 AppContainer 在应用退出时 flush。 */
  dispose(): void {
    if (this.lifecycleDisposed) {
      return;
    }
    this.lifecycleDisposed = true;
  }

  applyThemeMode(): void {
    if (this.lifecycleDisposed) {
      return;
    }
    this.themeModeApplier.apply(this.themeMode);
  }

  setThemeMode(value: ThemeMode): boolean {
    if (this.lifecycleDisposed) {
      return false;
    }
    if (this.themeMode === value) {
      return true;
    }
    if (!this.repository.saveThemeMode(value)) {
      this.errorMessage = this.repository.lastError ?? '设置保存失败';
      return false;
    }
    this.errorMessage = '';
    this.themeMode = value;
    this.applyThemeMode();
    return true;
  }

  setHapticEnabled(value: boolean): boolean {
    if (this.lifecycleDisposed) {
      return false;
    }
    if (this.hapticEnabled === value) {
      return true;
    }
    if (!this.repository.saveHapticEnabled(value)) {
      this.errorMessage = this.repository.lastError ?? '设置保存失败';
      return false;
    }
    this.errorMessage = '';
    this.hapticEnabled = value;
    return true;
  }

  setImmersiveMaterialEnabled(value: boolean): boolean {
    if (this.lifecycleDisposed) {
      return false;
    }
    if (this.immersiveMaterialEnabled === value) {
      return true;
    }
    if (!this.repository.saveImmersiveMaterialEnabled(value)) {
      this.errorMessage = this.repository.lastError ?? '设置保存失败';
      return false;
    }
    this.errorMessage = '';
    this.immersiveMaterialEnabled = value;
    return true;
  }

  setFontSize(value: number): boolean {
    if (this.lifecycleDisposed) {
      return false;
    }
    const normalized = normalizeReadingFontSize(value);
    if (this.fontSize === normalized) {
      return true;
    }
    if (!this.repository.saveFontSize(normalized)) {
      this.errorMessage = this.repository.lastError ?? '设置保存失败';
      return false;
    }
    this.errorMessage = '';
    this.fontSize = normalized;
    return true;
  }

  setLineHeightMultiple(value: number): boolean {
    if (this.lifecycleDisposed) {
      return false;
    }
    const normalized = normalizeReadingLineHeight(value);
    if (this.lineHeightMultiple === normalized) {
      return true;
    }
    if (!this.repository.saveLineHeightMultiple(normalized)) {
      this.errorMessage = this.repository.lastError ?? '设置保存失败';
      return false;
    }
    this.errorMessage = '';
    this.lineHeightMultiple = normalized;
    return true;
  }

  flush(): Promise<void> {
    return this.repository.flush().catch((error: Object): never => {
      this.errorMessage = this.repository.lastError ??
        (error instanceof Error ? error.message : '设置落盘失败');
      throw new Error(error instanceof Error ? error.message : '设置落盘失败');
    });
  }

  /** Re-read platform settings after a transient storage failure. */
  retryLoad(): void {
    if (this.lifecycleDisposed) {
      return;
    }
    const loaded = this.repository.load();
    const loadError = this.repository.lastError ?? '';
    if (loadError.length > 0) {
      // Keep the last known in-memory settings when the platform store is
      // still unavailable; a failed retry must not look like a user reset.
      this.errorMessage = loadError;
      return;
    }
    this.publish(loaded);
    this.errorMessage = '';
    this.applyThemeMode();
  }

  private publish(settings: AppSettings): void {
    this.themeMode = settings.themeMode;
    this.hapticEnabled = settings.hapticEnabled;
    this.immersiveMaterialEnabled = settings.immersiveMaterialEnabled;
    this.fontSize = settings.fontSize;
    this.lineHeightMultiple = settings.lineHeightMultiple;
  }
}
