package com.suixin.anomicon.core.data

import com.suixin.anomicon.core.model.CatalogEntry
import com.suixin.anomicon.core.model.CatalogSeriesDescriptor
import com.suixin.anomicon.core.model.ArticleBlock
import com.suixin.anomicon.core.model.ArticleDocument
import com.suixin.anomicon.core.model.ContentRef
import com.suixin.anomicon.core.model.ExploreEntry
import com.suixin.anomicon.core.model.ExploreSource
import com.suixin.anomicon.core.model.TaleEntry
import com.suixin.anomicon.core.model.articleUrlOf
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.OkHttpClient
import okhttp3.Request
import org.jsoup.Jsoup
import org.jsoup.nodes.Element
import java.io.IOException
import java.time.Duration
import java.util.Locale

class WikiGateway(
    private val client: OkHttpClient = OkHttpClient.Builder()
        .callTimeout(Duration.ofSeconds(20))
        .connectTimeout(Duration.ofSeconds(10))
        .readTimeout(Duration.ofSeconds(15))
        .build()
) {
    suspend fun loadCatalog(series: CatalogSeriesDescriptor): List<CatalogEntry> =
        withContext(Dispatchers.IO) {
            parseCatalog(fetch(series.url))
        }

    suspend fun loadTales(): List<TaleEntry> =
        withContext(Dispatchers.IO) {
            parseTales(fetch("$WikiCn/tales-by-page-name"))
        }

    suspend fun loadExplore(source: ExploreSource): List<ExploreEntry> =
        withContext(Dispatchers.IO) {
            parseExplore(source, fetch(source.url))
        }

    suspend fun resolveTitle(itemId: String): String =
        withContext(Dispatchers.IO) {
            extractTitle(fetch(articleUrlOf(itemId)), itemId.uppercase(Locale.ROOT))
        }

    suspend fun loadArticleHtml(content: ContentRef): String =
        withContext(Dispatchers.IO) {
            fetch(articleUrlOf(content.id))
        }

    fun parseArticle(content: ContentRef, html: String, fetchedAt: Long = System.currentTimeMillis()): ArticleDocument {
        val document = Jsoup.parse(html, articleUrlOf(content.id))
        val page = document.getElementById("page-content") ?: document.body()
        page.select("script,style,noscript,iframe,form,.page-options,.footer-wikiwalk-nav,#page-info").remove()
        return ArticleDocument(
            content = content,
            sourceUrl = articleUrlOf(content.id),
            fetchedAt = fetchedAt,
            blocks = buildList { appendArticleBlocks(page) }
        )
    }

    private fun MutableList<ArticleBlock>.appendArticleBlocks(element: Element) {
        element.children().forEach { child ->
            when (child.tagName().lowercase(Locale.ROOT)) {
                "h1", "h2", "h3", "h4", "h5", "h6" -> {
                    child.text().cleanText().takeIf { it.isNotBlank() }?.let {
                        add(ArticleBlock.Heading(it, child.tagName().drop(1).toInt()))
                    }
                }
                "p" -> {
                    val images = child.select("img")
                    images.forEach { image -> addImage(image) }
                    child.clone().select("img").remove()
                    child.text().cleanText().takeIf { it.isNotBlank() }?.let { add(ArticleBlock.Paragraph(it)) }
                }
                "img" -> addImage(child)
                "blockquote" -> child.text().cleanText().takeIf { it.isNotBlank() }?.let { add(ArticleBlock.Quote(it)) }
                "ul", "ol" -> {
                    val items = child.children()
                        .filter { it.tagName().equals("li", ignoreCase = true) }
                        .map { it.text().cleanText() }
                        .filter { it.isNotBlank() }
                    if (items.isNotEmpty()) add(ArticleBlock.ListBlock(items, child.tagName() == "ol"))
                }
                "hr" -> add(ArticleBlock.Divider)
                "table" -> {
                    child.select("tr").map { it.text().cleanText() }
                        .filter { it.isNotBlank() }
                        .forEach { add(ArticleBlock.Paragraph(it)) }
                }
                else -> {
                    val hasNestedBlocks = child.children().any { nested ->
                        nested.tagName().lowercase(Locale.ROOT) in BLOCK_TAGS
                    }
                    if (hasNestedBlocks) {
                        appendArticleBlocks(child)
                    } else {
                        child.select("img").forEach { image -> addImage(image) }
                        child.clone().select("img").remove()
                        child.text().cleanText().takeIf { it.isNotBlank() }?.let { add(ArticleBlock.Paragraph(it)) }
                    }
                }
            }
        }
    }

    private fun MutableList<ArticleBlock>.addImage(image: Element) {
        val rawUrl = image.absUrl("src").ifBlank { image.attr("src") }
        val url = when {
            rawUrl.startsWith("//") -> "https:$rawUrl"
            rawUrl.startsWith("http://") || rawUrl.startsWith("https://") -> rawUrl
            rawUrl.startsWith("/") -> "$WikiCn$rawUrl"
            rawUrl.isBlank() -> ""
            else -> "$WikiCn/$rawUrl"
        }
        if (url.isNotBlank()) add(ArticleBlock.Image(url, image.attr("alt").cleanText()))
    }

    fun parseCatalog(html: String): List<CatalogEntry> {
        val content = Jsoup.parse(html).getElementById("page-content") ?: return emptyList()
        val panel = content.selectFirst("div.content-panel.series")
            ?: content.selectFirst("div.content-panel")
            ?: content
        val seen = linkedSetOf<String>()
        return panel.select("a[href]").mapNotNull { link ->
            val href = normalizeHref(link.attr("href"))
            val id = href.removePrefix("/").uppercase(Locale.ROOT)
            if (!id.matches(Regex("^SCP-\\d{3,4}$")) || !seen.add(id)) {
                return@mapNotNull null
            }
            val parentText = link.parent()?.text().orEmpty()
            val linkTitle = cleanCatalogTitle(stripIdPrefix(link.text(), id))
            val rawTitle = linkTitle.ifBlank {
                cleanCatalogTitle(stripIdPrefix(parentText, id))
            }
            CatalogEntry(
                itemId = id,
                title = rawTitle,
                hasArchive3D = SeedData.hasArchiveAsset(id.lowercase(Locale.ROOT))
            )
        }
    }

    fun parseTales(html: String): List<TaleEntry> {
        val content = Jsoup.parse(html).getElementById("page-content") ?: return emptyList()
        val seen = linkedSetOf<String>()
        return content.select("a[href]").mapNotNull { link ->
            val href = normalizeHref(link.attr("href"))
            val title = link.text().cleanText()
            if (!isTaleLink(href, title)) return@mapNotNull null
            val id = href.removePrefix("/")
            if (!seen.add(id)) return@mapNotNull null
            TaleEntry(id = id, title = title)
        }.sortedBy { it.id }
    }

    fun parseExplore(source: ExploreSource, html: String): List<ExploreEntry> {
        val content = Jsoup.parse(html).getElementById("page-content") ?: return emptyList()
        return when (source) {
            ExploreSource.TopRated,
            ExploreSource.RecentTranslated,
            ExploreSource.RecentOriginal -> parseExploreTable(source, content)
            ExploreSource.JokeScps,
            ExploreSource.JokeTales -> parseJokes(source, content)
        }
    }

    private fun fetch(url: String): String {
        val request = Request.Builder()
            .url(url)
            .header("User-Agent", "Anomicon-Android-Migration/1.0")
            .build()
        client.newCall(request).execute().use { response ->
            if (!response.isSuccessful) throw IOException("HTTP ${response.code}: $url")
            return response.body?.string() ?: throw IOException("空响应：$url")
        }
    }

    private fun parseExploreTable(source: ExploreSource, content: Element): List<ExploreEntry> {
        val seen = linkedSetOf<String>()
        return content.select("tr").mapNotNull { row ->
            val cells = row.select("td")
            if (cells.size < 2) return@mapNotNull null
            val link = cells[0].selectFirst("a[href]") ?: return@mapNotNull null
            val href = normalizeHref(link.attr("href"))
            if (isNavigation(href) || !seen.add(href)) return@mapNotNull null
            if (source == ExploreSource.TopRated) {
                ExploreEntry(
                    id = href.removePrefix("/"),
                    title = link.text().cleanText(),
                    score = cells[1].text().cleanText().removePrefix("+").toIntOrNull() ?: -1,
                    comments = cells.getOrNull(2)?.text()?.cleanText().orEmpty()
                )
            } else {
                ExploreEntry(
                    id = href.removePrefix("/"),
                    title = link.text().cleanText(),
                    date = cells[1].text().cleanText(),
                    comments = cells.getOrNull(2)?.text()?.cleanText().orEmpty()
                )
            }
        }.take(40)
    }

    private fun parseJokes(source: ExploreSource, content: Element): List<ExploreEntry> {
        val listContent = when (source) {
            ExploreSource.JokeScps -> content.selectFirst("div.content-panel.standalone.series") ?: content
            ExploreSource.JokeTales -> content
            else -> content
        }
        val seen = linkedSetOf<String>()
        val maxEntries = if (source == ExploreSource.JokeScps) 240 else 180
        return listContent.select("a[href]").mapNotNull { link ->
            val href = normalizeHref(link.attr("href"))
            val title = link.text().cleanText()
            if (!isJokeEntry(source, href, title) || !seen.add(href)) return@mapNotNull null
            ExploreEntry(id = href.removePrefix("/"), title = title)
        }.take(maxEntries)
    }

    private fun extractTitle(html: String, fallback: String): String {
        val doc = Jsoup.parse(html)
        val pageTitle = doc.selectFirst(".page-title")?.text()?.cleanText().orEmpty()
        if (pageTitle.isNotBlank()) return pageTitle
        val title = doc.title()
            .replace(Regex("\\s*[-–—]\\s*SCP(?:基金会| Foundation).*$", RegexOption.IGNORE_CASE), "")
            .cleanText()
        return title.ifBlank { fallback }
    }

    private fun isJokeEntry(source: ExploreSource, href: String, title: String): Boolean {
        if (href.length < 2 || title.length < 2 || isNavigation(href)) return false
        val slug = href.removePrefix("/").lowercase(Locale.ROOT)
        val isScpPage = slug.startsWith("scp-") || slug.startsWith("spc-")
        val isJokePage = isScpPage && (slug.contains("-j") || title.lowercase(Locale.ROOT).contains("-j"))
        return if (source == ExploreSource.JokeScps) isJokePage else !isScpPage
    }

    private fun isTaleLink(href: String, title: String): Boolean {
        if (title.length < 2 || href.length < 2 || !href.startsWith("/")) return false
        val lowerHref = href.lowercase(Locale.ROOT)
        if (lowerHref.startsWith("/system:") || lowerHref.startsWith("/_")) return false
        return !lowerHref.contains("tales-by") &&
            !lowerHref.startsWith("/tale") &&
            !lowerHref.contains("foundation-tales") &&
            !lowerHref.contains("canon") &&
            !lowerHref.startsWith("/user:")
    }

    private fun isNavigation(href: String): Boolean {
        if (!href.startsWith("/") || href.startsWith("//")) return true
        val normalized = href.lowercase(Locale.ROOT)
        return normalized.startsWith("/system:") ||
            normalized.startsWith("/_") ||
            normalized.contains("tales-by") ||
            normalized.contains("foundation-tales") ||
            normalized.contains("most-recently") ||
            normalized.contains("top-rated") ||
            normalized.contains("joke-scps") ||
            normalized.contains("explained-scps") ||
            normalized.contains("random:") ||
            normalized.contains("scp-series") ||
            normalized.startsWith("/forum") ||
            normalized.startsWith("/help") ||
            normalized == "/main" ||
            normalized == "/"
    }

    private fun normalizeHref(value: String): String =
        Jsoup.parse(value).text()
            .substringBefore("#")
            .substringBefore("?")
            .trim()

    private fun stripIdPrefix(value: String, id: String): String {
        val index = value.uppercase(Locale.ROOT).indexOf(id)
        return if (index < 0) value else value.substring(index + id.length)
    }

    private fun cleanCatalogTitle(value: String): String =
        value.cleanText()
            .replace(Regex("^[\\s\\-–—:：'\"‘’“”\\[（(]+"), "")
            .replace(Regex("\\[[^]]*]\\s*$"), "")
            .replace(Regex("[\\s\\-–—:：'\"‘’“”\\]）)]+$"), "")
            .trim()

    private fun String.cleanText(): String =
        replace(Regex("\\s+"), " ").trim()

    companion object {
        private const val WikiCn = "https://scp-wiki-cn.wikidot.com"
        private val BLOCK_TAGS = setOf("h1", "h2", "h3", "h4", "h5", "h6", "p", "blockquote", "ul", "ol", "hr", "table")
    }
}
