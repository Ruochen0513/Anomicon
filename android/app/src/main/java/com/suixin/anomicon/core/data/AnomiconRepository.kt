package com.suixin.anomicon.core.data

import com.suixin.anomicon.core.model.CatalogEntry
import com.suixin.anomicon.core.model.ContentKind
import com.suixin.anomicon.core.model.ExploreContentItem
import com.suixin.anomicon.core.model.ExploreEntry
import com.suixin.anomicon.core.model.ExploreHomeData
import com.suixin.anomicon.core.model.ExploreSource
import com.suixin.anomicon.core.model.ScpSeriesDescriptors
import com.suixin.anomicon.core.model.TaleEntry
import com.suixin.anomicon.core.model.dayKey
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import java.time.LocalDate

class AnomiconRepository(
    private val wikiGateway: WikiGateway = WikiGateway()
) {
    suspend fun loadCatalog(seriesId: String): Result<List<CatalogEntry>> =
        runCatching {
            val series = ScpSeriesDescriptors.firstOrNull { it.id == seriesId }
                ?: ScpSeriesDescriptors.first()
            wikiGateway.loadCatalog(series).ifEmpty { SeedData.fallbackCatalog }
        }.recoverCatching {
            SeedData.fallbackCatalog
        }

    suspend fun loadTales(): Result<List<TaleEntry>> =
        runCatching {
            wikiGateway.loadTales().ifEmpty { SeedData.fallbackTales }
        }.recoverCatching {
            SeedData.fallbackTales
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
        runCatching { wikiGateway.loadExplore(source) }.getOrDefault(emptyList())

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
