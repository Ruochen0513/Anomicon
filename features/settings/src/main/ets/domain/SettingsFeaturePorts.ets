import { SettingsRepository, ThemeModeApplier } from './SettingsRepository';

/** Product-facing settings dependency graph; no Preferences type crosses it. */
export interface SettingsFeatureGraph {
  readonly settingsRepository: SettingsRepository;
  readonly themeModeApplier: ThemeModeApplier;
}
