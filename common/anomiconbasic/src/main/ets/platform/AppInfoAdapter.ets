import { bundleManager } from '@kit.AbilityKit';
import { AppInfoPort } from './PlatformPorts';

/** HarmonyOS implementation of the app-info port. */
export class AppInfoAdapter implements AppInfoPort {
  private cachedVersionName: string | undefined = undefined;

  versionName(): string {
    if (this.cachedVersionName !== undefined) {
      return this.cachedVersionName;
    }

    try {
      const bundleInfo = bundleManager.getBundleInfoForSelfSync(
        bundleManager.BundleFlag.GET_BUNDLE_INFO_DEFAULT
      );
      this.cachedVersionName = bundleInfo.versionName;
    } catch (error) {
      const businessError = error as BusinessError;
      console.error(`Read application version failed. Code: ${businessError.code}, message: ${businessError.message}`);
      // A bundle-manager failure can be transient during Ability startup.
      // Return a display fallback for this call, but do not memoize the
      // failure so a later render can retry the platform query.
      return '—';
    }
    return this.cachedVersionName ?? '—';
  }
}
