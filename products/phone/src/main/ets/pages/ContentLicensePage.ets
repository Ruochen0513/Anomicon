import {
  ContentLicenseContent,
  ContentLicenseLink,
  ContentLicensePageBuilder as SettingsContentLicensePageBuilder
} from 'settings';

/** Thin phone adapter that supplies product-specific licence copy and links. */
@Builder
export function ContentLicensePageBuilder() {
  SettingsContentLicensePageBuilder(new ContentLicenseContent(
    '内容来源与许可',
    'CC BY-SA 3.0',
    'SCP 条目的许可可能因来源而异；请以具体条目和上游来源记录为准。',
    [
      new ContentLicenseLink('SCP Wiki', 'https://scp-wiki.wikidot.com/'),
      new ContentLicenseLink('SCP Wiki授权指南', 'https://scp-wiki.wikidot.com/licensing-guide'),
      new ContentLicenseLink(
        '三维概念资产许可（Apache-2.0）',
        'https://www.apache.org/licenses/LICENSE-2.0'
      ),
      new ContentLicenseLink('CC BY-SA 3.0许可文本', 'https://creativecommons.org/licenses/by-sa/3.0/')
    ],
    '格异录为非官方应用，与SCP Wiki不存在隶属或认可关系。'
  ));
}
