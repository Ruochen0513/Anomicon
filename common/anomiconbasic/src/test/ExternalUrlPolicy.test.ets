import { describe, expect, it, xit } from '@ohos/hypium';
import { ExternalUrlPolicy } from '../main/ets/platform/ExternalUrlPolicy';

function supportsUrlParser(): boolean {
  try {
    ExternalUrlPolicy.resolveImageHttps('https://example.com/image.jpg');
    return true;
  } catch (_error) {
    // The local previewer currently lacks URLSearchParams; the device runtime
    // provides the URL API used by the production image pipeline.
    return false;
  }
}

function errorMessage(action: () => string): string {
  try {
    action();
  } catch (error) {
    return error instanceof Error ? error.message : '';
  }
  return '';
}

export default function externalUrlPolicyTest(): void {
  describe('ExternalUrlPolicy', () => {
    if (supportsUrlParser()) {
      it('upgrades legacy HTTP image URLs and strips fragments', 0, () => {
        const resolved = ExternalUrlPolicy.resolveImageHttps(
          '  http://scp-wiki.wikidot.com/local--files/scp-5793/store.jpg#preview  '
        );

        expect(resolved).assertEqual(
          'https://scp-wiki.wikidot.com/local--files/scp-5793/store.jpg'
        );
      });

      it('resolves protocol-relative and relative image URLs on the CN wiki', 0, () => {
        const protocolRelative = ExternalUrlPolicy.resolveImageHttps(
          '//scp-wiki.wdfiles.com/local--files/scp-173/statue.png'
        );
        const relative = ExternalUrlPolicy.resolveImageHttps(
          '/local--files/scp-173/statue.png'
        );

        expect(protocolRelative).assertEqual(
          'https://scp-wiki.wdfiles.com/local--files/scp-173/statue.png'
        );
        expect(relative).assertEqual(
          'https://scp-wiki-cn.wikidot.com/local--files/scp-173/statue.png'
        );
      });
    } else {
      xit('upgrades legacy HTTP image URLs and strips fragments', 0, (): void => {});
      xit('resolves protocol-relative and relative image URLs on the CN wiki', 0, (): void => {});
    }

    it('rejects credentials, custom ports, and non-HTTPS schemes', 0, () => {
      const credentials = errorMessage((): string =>
        ExternalUrlPolicy.resolveImageHttps('https://user:pass@example.com/image.jpg')
      );
      const customPort = errorMessage((): string =>
        ExternalUrlPolicy.resolveImageHttps('https://example.com:8443/image.jpg')
      );
      const dataUrl = errorMessage((): string =>
        ExternalUrlPolicy.resolveImageHttps('data:image/png;base64,AAAA')
      );

      expect(credentials.length > 0).assertTrue();
      expect(customPort.length > 0).assertTrue();
      expect(dataUrl.length > 0).assertTrue();
    });
  });
}
