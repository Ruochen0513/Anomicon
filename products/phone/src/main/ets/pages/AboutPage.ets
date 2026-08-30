import { AppInfoPort } from 'anomiconbasic';
import {
  AboutPageBuilder as SettingsAboutPageBuilder,
  AboutPageContent
} from 'settings';

/** Thin phone adapter that supplies product identity to the Settings About View. */
@Builder
export function AboutPageBuilder(appInfo: AppInfoPort) {
  SettingsAboutPageBuilder(new AboutPageContent(
    '格异录',
    'Anomicon',
    appInfo.versionName(),
    $r('app.media.appIcon')
  ));
}
