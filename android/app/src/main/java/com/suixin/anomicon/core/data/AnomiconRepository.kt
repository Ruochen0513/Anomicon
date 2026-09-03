package com.suixin.anomicon.core.data

import com.suixin.anomicon.core.model.CatalogEntry
import com.suixin.anomicon.core.model.ArchiveAsset
import com.suixin.anomicon.core.model.ContentKind
import com.suixin.anomicon.core.model.ContentRef
import com.suixin.anomicon.core.model.ExploreContentItem
import com.suixin.anomicon.core.model.ExploreEntry
import com.suixin.anomicon.core.model.ExploreHomeData
import com.suixin.anomicon.core.model.ExploreSource
import com.suixin.anomicon.core.model.ScpSeriesDescriptors
import com.suixin.anomicon.core.model.TaleEntry
import com.suixin.anomicon.core.model.dayKey
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.withContext
import org.json.JSONArray
import org.json.JSONObject
import kotlinx.coroutines.Dispatchers
import java.time.LocalDate
import java.io.File

class AnomiconRepository(
    private val wikiGateway: WikiGateway = WikiGateway(),
    private val contentCache: AndroidContentCache? = null,
    private val archiveAssetStore: AndroidArchiveAssetStore? = null
) {
    suspend fun installedArchiveAsset(asset: ArchiveAsset): Result<File?> =
        runCatching {
            archiveAssetStore?.installedFile(asset)
        }

    suspend fun downloadArchiveAsset(
        asset: ArchiveAsset,
        onProgress: suspend (ArchiveDownloadProgress) -> Unit = {}
    ): Result<File> =
        runCatching {
            archiveAssetStore?.download(asset, onProgress)
                ?: throw IllegalStateException("三维模型缓存未启用")
        }

    suspend fun deleteArchiveAsset(asset: ArchiveAsset): Result<Boolean> =
        runCatching {
            archiveAssetStore?.delete(asset)
                ?: throw IllegalStateException("三维模型缓存未启用")
        }

    suspend fun loadCatalog(seriesId: String): Result<List<CatalogEntry>> =
        runCatching {
            val series = ScpSeriesDescriptors.firstOrNull { it.id == seriesId }
                ?: ScpSeriesDescriptors.first()
            val network = wikiGateway.loadCatalog(series)
            if (network.isNotEmpty()) {
                writeCache("catalog:${series.id}", encodeCatalog(network))
                network
            } else {
                readCatalog(series.id) ?: SeedData.fallbackCatalog
            }
        }.recoverCatching {
            readCatalog(seriesId) ?: SeedData.fallbackCatalog
        }

    suspend fun loadTales(): Result<List<TaleEntry>> =
        runCatching {
            val network = wikiGateway.loadTales()
            if (network.isNotEmpty()) {
                writeCache("tales", encodeTales(network))
                network
            } else {
                readTales() ?: SeedData.fallbackTales
            }
        }.recoverCatching {
            readTales() ?: SeedData.fallbackTales
        }

    suspend fun loadArticle(content: ContentRef): Result<com.suixin.anomicon.core.model.ArticleDocument> =
        runCatching {
            val fetchedAt = System.currentTimeMillis()
            val html = wikiGateway.loadArticleHtml(content)
            writeCache("article:${content.key}", html, "html", fetchedAt)
            wikiGateway.parseArticle(content, html, fetchedAt)
        }.recoverCatching {
            val cached = readCache("article:${content.key}", "html")
                ?: throw IllegalStateException("文章尚未缓存，且当前无法连接网络")
            wikiGateway.parseArticle(content, cached.body, cached.fetchedAt)
        }

    suspend fun loadImageFile(url: String): Result<File> =
        runCatching {
            withContext(Dispatchers.IO) {
                contentCache?.readFile("image:$url", "img")
            } ?: run {
                val bytes = wikiGateway.loadResource(url)
                withContext(Dispatchers.IO) {
                    contentCache?.writeBytes("image:$url", "img", bytes)
                        ?: throw IllegalStateException("图片缓存未启用")
                }
            }
        }.recoverCatching {
            withContext(Dispatchers.IO) {
                contentCache?.readFile("image:$url", "img")
            } ?: throw it
        }

    suspend fun loadExplore(date: LocalDate = LocalDate.now()): ExploreHomeData =
        coroutineScope {
            val topRated = async { loadExploreSource(ExploreSource.TopRated) }
            val recentTranslated = async { loadExploreSource(ExploreSource.RecentTranslated) }
            val recentOriginal = async { loadExploreSource(ExploreSource.RecentOriginal) }
            val jokeScps = async { loadExploreSource(ExploreSource.JokeScps) }
            val jokeTales = async { loadExploreSource(ExploreSource.JokeTales) }

            val topRatedEntries = topRated.await().ifEmpty { SeedData.fallbackExplore }
            val recent = combineRecent(recentTranslated.await(), recentOriginal.await())
            val jokes = combineJokes(jokeScps.await(), jokeTales.await(), dayKey(date))
            val recommendations = dailyRecommendations(topRatedEntries, date)

            ExploreHomeData(
                topRated = topRatedEntries,
                recent = recent.ifEmpty {
                    SeedData.fallbackExplore.take(4).map {
                        ExploreContentItem(it, ContentKind.Wiki, "本地回退")
                    }
                },
                jokes = jokes.ifEmpty {
                    SeedData.fallbackExplore.takeLast(3).map {
                        ExploreContentItem(it, ContentKind.Scp, "本地回退")
                    }
                },
                recommendations = recommendations
            )
        }

    private suspend fun loadExploreSource(source: ExploreSource): List<ExploreEntry> =
        runCatching {
            val network = wikiGateway.loadExplore(source)
            if (network.isNotEmpty()) {
                writeCache("explore:${source.name}", encodeExplore(network))
                network
            } else {
                readExplore(source) ?: emptyList()
            }
        }.getOrElse {
            readExplore(source) ?: emptyList()
        }

    private suspend fun readCatalog(seriesId: String): List<CatalogEntry>? =
        readCache("catalog:$seriesId")?.let { decodeCatalog(it.body) }

    private suspend fun readTales(): List<TaleEntry>? =
        readCache("tales")?.let { decodeTales(it.body) }

    private suspend fun readExplore(source: ExploreSource): List<ExploreEntry>? =
        readCache("explore:${source.name}")?.let { decodeExplore(it.body) }

    private suspend fun writeCache(key: String, body: String, extension: String = "json", fetchedAt: Long = System.currentTimeMillis()) {
        withContext(Dispatchers.IO) {
            contentCache?.write(key, extension, body, fetchedAt)
        }
    }

    private suspend fun readCache(key: String, extension: String = "json"): CachedContent? =
        withContext(Dispatchers.IO) {
            contentCache?.read(key, extension)
        }

    private fun encodeCatalog(entries: List<CatalogEntry>): String = JSONArray().also { array ->
        entries.forEach { entry ->
            array.put(JSONObject().put("itemId", entry.itemId).put("title", entry.title).put("description", entry.description).put("hasArchive3D", entry.hasArchive3D))
        }
    }.toString()

    private fun decodeCatalog(raw: String): List<CatalogEntry> = runCatching {
        val array = JSONArray(raw)
        List(array.length()) { index ->
            val item = array.getJSONObject(index)
            CatalogEntry(item.getString("itemId"), item.optString("title"), item.optString("description"), item.optBoolean("hasArchive3D"))
        }
    }.getOrDefault(emptyList())

    private fun encodeTales(entries: List<TaleEntry>): String = JSONArray().also { array ->
        entries.forEach { entry -> array.put(JSONObject().put("id", entry.id).put("title", entry.title)) }
    }.toString()

    private fun decodeTales(raw: String): List<TaleEntry> = runCatching {
        val array = JSONArray(raw)
        List(array.length()) { index ->
            val item = array.getJSONObject(index)
            TaleEntry(item.getString("id"), item.optString("title"))
        }
    }.getOrDefault(emptyList())

    private fun encodeExplore(entries: List<ExploreEntry>): String = JSONArray().also { array ->
        entries.forEach { entry ->
            array.put(JSONObject().put("id", entry.id).put("title", entry.title).put("score", entry.score).put("date", entry.date).put("comments", entry.comments))
        }
    }.toString()

    private fun decodeExplore(raw: String): List<ExploreEntry> = runCatching {
        val array = JSONArray(raw)
        List(array.length()) { index ->
            val item = array.getJSONObject(index)
            ExploreEntry(item.getString("id"), item.optString("title"), item.optInt("score", -1), item.optString("date"), item.optString("comments"))
        }
    }.getOrDefault(emptyList())

    private fun combineRecent(
        translated: List<ExploreEntry>,
        original: List<ExploreEntry>
    ): List<ExploreContentItem> {
        val seen = linkedSetOf<String>()
        return buildList {
            translated.forEach { entry ->
                if (seen.add(entry.normalizedId)) add(ExploreContentItem(entry, ContentKind.Wiki, "翻译主站"))
            }
            original.forEach { entry ->
                if (seen.add(entry.normalizedId)) add(ExploreContentItem(entry, ContentKind.Wiki, "原创"))
            }
        }.take(20)
    }

    private fun combineJokes(
        scps: List<ExploreEntry>,
        tales: List<ExploreEntry>,
        salt: String
    ): List<ExploreContentItem> {
        val pool = scps.map { ExploreContentItem(it, ContentKind.Scp, "搞笑 SCP") } +
            tales.map { ExploreContentItem(it, ContentKind.Tale, "搞笑故事") }
        return pool.stableShuffle(salt).take(20)
    }

    private suspend fun dailyRecommendations(
        fallbackPool: List<ExploreEntry>,
        date: LocalDate
    ): List<ExploreEntry> {
        val ids = candidateIds(dayKey(date)).take(10)
        val resolved = coroutineScope {
            ids.map { id ->
                async {
                    runCatching {
                        ExploreEntry(id.lowercase(), wikiGateway.resolveTitle(id))
                    }.getOrNull()
                }
            }.mapNotNull { it.await() }
        }
        return resolved.take(6).ifEmpty { fallbackPool.take(6) }
    }

    private fun candidateIds(salt: String): List<String> =
        (1..9999)
            .map { it.toString().padStart(3, '0') }
            .stableShuffle("wiki-random-recommendations:$salt")
            .map { "SCP-$it" }

    private fun <T> List<T>.stableShuffle(salt: String): List<T> =
        mapIndexed { index, item -> stableHash("$salt:$index:$item") to item }
            .sortedBy { it.first }
            .map { it.second }

    private fun stableHash(value: String): Long {
        var hash = 1125899906842597L
        value.forEach { char ->
            hash = 31L * hash + char.code
        }
        return hash
    }
}
