import { common } from '@kit.AbilityKit';
import { SettingsFeatureGraph } from '../domain/SettingsFeaturePorts';
import { SettingsPreferencesRepo } from '../data/SettingsPreferencesRepo';
import { HarmonyThemeModeApplier } from '../data/HarmonyThemeModeApplier';

/** Builds the settings graph while keeping Preferences and system UI APIs private. */
export function createSettingsFeatureGraph(context: common.UIAbilityContext): SettingsFeatureGraph {
  const repository = new SettingsPreferencesRepo(context);
  const applier = new HarmonyThemeModeApplier(context.getApplicationContext());
  return {
    settingsRepository: repository,
    themeModeApplier: applier
  };
}
