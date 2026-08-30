import { describe, expect, it } from '@ohos/hypium';
import {
  SCP_CATALOG_PARSER_VERSION,
  TALE_LIST_PARSER_VERSION
} from '../main/ets/domain/StaticCatalogContracts';
import { StaticCatalogHtmlParser } from '../main/ets/data/StaticCatalogHtmlParser';

export default function staticCatalogHtmlParserTest(): void {
  describe('StaticCatalogHtmlParserContract', () => {
    it('returns a validated catalog payload for the series panel', 0, () => {
      const html = '<div id="page-content"><div class="content-panel series">' +
        '<a href="/scp-173">SCP-173 - 雕像</a></div></div>';
      const result = StaticCatalogHtmlParser.parseCatalog(html);

      expect(result.ok).assertTrue();
      expect(result.parserVersion).assertEqual(SCP_CATALOG_PARSER_VERSION);
      expect(result.entries.length).assertEqual(1);
      expect(result.entries[0].itemId).assertEqual('SCP-173');
    });

    it('rejects malformed pages with a typed failure payload', 0, () => {
      const catalog = StaticCatalogHtmlParser.parseCatalog('<html></html>');
      const tales = StaticCatalogHtmlParser.parseTales('<html></html>');

      expect(catalog.ok).assertFalse();
      expect(catalog.parserVersion).assertEqual(SCP_CATALOG_PARSER_VERSION);
      expect(catalog.entries.length).assertEqual(0);
      expect(tales.ok).assertFalse();
      expect(tales.parserVersion).assertEqual(TALE_LIST_PARSER_VERSION);
      expect(tales.tales.length).assertEqual(0);
    });
  });
}
