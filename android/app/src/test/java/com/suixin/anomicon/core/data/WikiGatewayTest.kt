package com.suixin.anomicon.core.data

import com.suixin.anomicon.core.model.ExploreSource
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class WikiGatewayTest {
    private val gateway = WikiGateway()

    @Test
    fun parseCatalogKeepsScpEntriesAndMarksArchiveAssets() {
        val html = """
            <html><body>
              <div id="page-content">
                <div class="content-panel standalone series">
                  <p><a href="/scp-173">SCP-173</a> - 雕像</p>
                  <p><a href="/scp-999#comments">SCP-999</a> - 痒痒怪</p>
                  <p><a href="/system:page-tags">tags</a></p>
                </div>
              </div>
            </body></html>
        """.trimIndent()

        val entries = gateway.parseCatalog(html)

        assertEquals(2, entries.size)
        assertEquals("SCP-173", entries[0].itemId)
        assertEquals("雕像", entries[0].title)
        assertTrue(entries[0].hasArchive3D)
        assertEquals("SCP-999", entries[1].itemId)
    }

    @Test
    fun parseTalesFiltersNavigationLinks() {
        val html = """
            <html><body>
              <div id="page-content">
                <a href="/incident-096-1-a">事故 096-1-A</a>
                <a href="/tales-by-page-name">故事索引</a>
                <a href="/user:someone">用户页</a>
              </div>
            </body></html>
        """.trimIndent()

        val tales = gateway.parseTales(html)

        assertEquals(1, tales.size)
        assertEquals("incident-096-1-a", tales[0].id)
        assertEquals("事故 096-1-A", tales[0].title)
    }

    @Test
    fun parseExploreTableReadsScoresAndSkipsNavigation() {
        val html = """
            <html><body>
              <div id="page-content">
                <table>
                  <tr><td><a href="/scp-049">SCP-049</a></td><td>+1888</td><td>42</td></tr>
                  <tr><td><a href="/top-rated-pages">榜单</a></td><td>+1</td><td>0</td></tr>
                </table>
              </div>
            </body></html>
        """.trimIndent()

        val entries = gateway.parseExplore(ExploreSource.TopRated, html)

        assertEquals(1, entries.size)
        assertEquals("scp-049", entries[0].normalizedId)
        assertEquals(1888, entries[0].score)
    }
}
