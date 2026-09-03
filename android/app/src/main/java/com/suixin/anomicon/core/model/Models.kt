package com.suixin.anomicon.core.model

import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.util.Locale
import kotlin.math.max
import kotlin.math.min
import kotlin.math.round

const val WikiBaseUrl = "https://scp-wiki-cn.wikidot.com"

enum class ContentKind(val label: String) {
    Scp("SCP"),
    Tale("故事"),
    Wiki("页面"),
    Knowledge("知识")
}

data class ContentRef(
    val kind: ContentKind,
    val id: String,
    val title: String
) {
    val key: String = "main:${normalizeContentId(id)}"

    companion object {
        fun create(kind: ContentKind, id: String, title: String): ContentRef {
            val normalizedId = normalizeContentId(id)
            val resolvedTitle = title.trim().ifEmpty { normalizedId.uppercase(Locale.ROOT) }
            return ContentRef(kind, normalizedId, resolvedTitle)
        }
    }
}

enum class ThemeMode {
    System,
    Light,
    Dark
}

data class AppSettings(
    val themeMode: ThemeMode = ThemeMode.System,
    val hapticEnabled: Boolean = true,
    val immersiveMaterialEnabled: Boolean = true,
    val fontSize: Float = ReadingSettingsRange.DefaultFontSize,
    val lineHeightMultiple: Float = ReadingSettingsRange.DefaultLineHeight
) {
    fun normalized(): AppSettings = copy(
        fontSize = normalizeFontSize(fontSize),
        lineHeightMultiple = normalizeLineHeight(lineHeightMultiple)
    )
}

object ReadingSettingsRange {
    const val MinFontSize = 14f
    const val DefaultFontSize = 18f
    const val MaxFontSize = 22f
    const val MinLineHeight = 1.2f
    const val DefaultLineHeight = 1.6f
    const val MaxLineHeight = 2.0f
}

data class CatalogSeriesDescriptor(
    val id: String,
    val label: String,
    val url: String
)

data class CatalogEntry(
    val itemId: String,
    val title: String,
    val description: String = "",
    val hasArchive3D: Boolean = false
) {
    val contentRef: ContentRef = ContentRef.create(ContentKind.Scp, itemId, displayTitle)
    val displayTitle: String
        get() = title.ifBlank { itemId.uppercase(Locale.ROOT) }
}

data class TaleEntry(
    val id: String,
    val title: String
) {
    val contentRef: ContentRef = ContentRef.create(ContentKind.Tale, id, title)
}

enum class ExploreSource(val url: String, val label: String) {
    TopRated("$WikiBaseUrl/top-rated-pages", "高评分"),
    RecentTranslated("$WikiBaseUrl/most-recently-created-translated", "近期翻译"),
    RecentOriginal("$WikiBaseUrl/most-recently-created-cn", "近期原创"),
    JokeScps("$WikiBaseUrl/joke-scps", "搞笑 SCP"),
    JokeTales("$WikiBaseUrl/joke-scps-tales-edition", "搞笑故事")
}

data class ExploreEntry(
    val id: String,
    val title: String,
    val score: Int = -1,
    val date: String = "",
    val comments: String = ""
) {
    val normalizedId: String = normalizeContentId(id)
}

data class ExploreContentItem(
    val entry: ExploreEntry,
    val kind: ContentKind,
    val sourceLabel: String,
    val timestamp: Long = 0L
) {
    val key: String = "${kind.name}:${entry.normalizedId}"
    val contentRef: ContentRef = ContentRef.create(kind, entry.normalizedId, entry.title)
}

data class ExploreHomeData(
    val topRated: List<ExploreEntry> = emptyList(),
    val recent: List<ExploreContentItem> = emptyList(),
    val jokes: List<ExploreContentItem> = emptyList(),
    val recommendations: List<ExploreEntry> = emptyList(),
    val error: String? = null
)

sealed interface ArticleBlock {
    data class Heading(val text: String, val level: Int) : ArticleBlock
    data class Paragraph(val text: String) : ArticleBlock
    data class Image(val url: String, val alt: String) : ArticleBlock
    data class Quote(val text: String) : ArticleBlock
    data class ListBlock(val items: List<String>, val ordered: Boolean) : ArticleBlock
    data object Divider : ArticleBlock
}

data class ArticleDocument(
    val content: ContentRef,
    val sourceUrl: String,
    val fetchedAt: Long,
    val blocks: List<ArticleBlock>
)

enum class ArchiveAssetSource {
    Bundled,
    Remote
}

enum class ArchiveAssetDelivery {
    Bundled,
    OnDemand
}

data class ArchiveAsset(
    val assetId: String,
    val contentId: String,
    val resourcePath: String,
    val source: ArchiveAssetSource,
    val delivery: ArchiveAssetDelivery,
    val version: String,
    val byteLength: Long,
    val sha256: String,
    val license: String,
    val attribution: String,
    val contentAttribution: String,
    val sourceLabel: String,
    val sourceUrl: String,
    val downloadUrl: String,
    val contentSourceUrl: String,
    val description: String,
    val objectClass: String,
    val notice: String,
    val modificationNote: String,
    val estimatedTriangleCount: Int,
    val renderTargetMaxPx: Int,
    val initialScale: Float
) {
    val title: String = contentId.uppercase(Locale.ROOT)
    val isReadyByDefault: Boolean = delivery == ArchiveAssetDelivery.Bundled
    val contentRef: ContentRef = ContentRef.create(ContentKind.Scp, contentId, title)
}

data class ReadingHistoryEntry(
    val content: ContentRef,
    val openedAt: Long,
    val lastReadAt: Long,
    val scrollOffset: Int = 0,
    val blockCount: Int = 0,
    val activeMs: Long = 0L
)

data class LibrarySnapshot(
    val favorites: List<ContentRef> = emptyList(),
    val history: List<ReadingHistoryEntry> = emptyList(),
    val activitySegments: List<ResearchActivitySegment> = emptyList()
)

data class ResearchActivitySegment(
    val segmentId: String,
    val content: ContentRef,
    val startedAt: Long,
    val endedAt: Long,
    val activeMs: Long,
    val lastOffset: Int = 0
)

enum class ResearchRankTitle(val label: String) {
    Visitor("初访者"),
    Retriever("检索者"),
    Reader("研读者"),
    Cataloger("编目者"),
    Researcher("考据者"),
    Archivist("典藏者")
}

data class ResearchDailyProgress(
    val day: LocalDate,
    val activeMs: Long
)

data class ResearchContentProgress(
    val content: ContentRef,
    val activeMs: Long,
    val researched: Boolean
)

data class ResearchProgress(
    val rawActiveMs: Long,
    val creditedActiveMs: Long,
    val todayActiveMs: Long,
    val researchedContentCount: Int,
    val experience: Int,
    val level: Int,
    val rankTitle: ResearchRankTitle,
    val levelThreshold: Int,
    val nextLevelThreshold: Int,
    val levelExperience: Int,
    val levelExperienceTarget: Int,
    val daily: List<ResearchDailyProgress>,
    val contents: List<ResearchContentProgress>
) {
    val levelProgressPercent: Float =
        if (levelExperienceTarget <= 0) 1f else (levelExperience.toFloat() / levelExperienceTarget).coerceIn(0f, 1f)
}

private data class ResearchDaySlice(
    val content: ContentRef,
    val day: LocalDate,
    val startedAt: Long,
    val endedAt: Long,
    val activeMs: Long
)

private data class CreditedResearchSlice(
    val content: ContentRef,
    val day: LocalDate,
    val startedAt: Long,
    val activeMs: Long
)

const val ResearchMinuteMs: Long = 60_000L
const val ResearchDailyCapMinutes: Long = 180L
const val ResearchDailyCapMs: Long = ResearchDailyCapMinutes * ResearchMinuteMs
const val ResearchedContentMinMs: Long = ResearchMinuteMs
const val ResearchedContentReward: Int = 8
const val ResearchMaxLevel: Int = 50

val ScpSeriesDescriptors: List<CatalogSeriesDescriptor> =
    buildList {
        add(CatalogSeriesDescriptor("scp-series", "I", "$WikiBaseUrl/scp-series"))
        listOf("II", "III", "IV", "V", "VI", "VII", "VIII", "IX", "X")
            .forEachIndexed { index, label ->
                val suffix = index + 2
                add(CatalogSeriesDescriptor("scp-series-$suffix", label, "$WikiBaseUrl/scp-series-$suffix"))
            }
    }

fun normalizeContentId(value: String): String {
    var normalized = value.trim().lowercase(Locale.ROOT)
    while (normalized.startsWith("/")) {
        normalized = normalized.drop(1)
    }
    require(normalized.isNotEmpty()) { "内容标识不能为空" }
    return normalized
}

fun articleUrlOf(id: String): String = "$WikiBaseUrl/${normalizeContentId(id)}"

fun dayKey(date: LocalDate = LocalDate.now()): String = date.toString()

fun normalizeFontSize(value: Float): Float {
    if (!value.isFinite()) return ReadingSettingsRange.DefaultFontSize
    return round(max(ReadingSettingsRange.MinFontSize, min(ReadingSettingsRange.MaxFontSize, value)) * 100f) / 100f
}

fun normalizeLineHeight(value: Float): Float {
    if (!value.isFinite()) return ReadingSettingsRange.DefaultLineHeight
    return round(max(ReadingSettingsRange.MinLineHeight, min(ReadingSettingsRange.MaxLineHeight, value)) * 1000f) / 1000f
}

fun normalizeResearchDuration(value: Long): Long =
    if (value <= 0L) 0L else value

fun normalizeReadingOffset(value: Int): Int =
    value.coerceAtLeast(0)

fun normalizeReadingBlockCount(value: Int): Int =
    value.coerceAtLeast(0)

fun readingProgressPercent(entry: ReadingHistoryEntry): Float =
    if (entry.blockCount <= 1) {
        0f
    } else {
        entry.scrollOffset.toFloat()
            .div((entry.blockCount - 1).coerceAtLeast(1))
            .coerceIn(0f, 1f)
    }

fun deriveResearchProgress(
    segments: List<ResearchActivitySegment>,
    now: Long = System.currentTimeMillis(),
    zoneId: ZoneId = ZoneId.systemDefault()
): ResearchProgress {
    val normalizedSegments = segments
        .filter { it.activeMs > 0L }
        .map {
            it.copy(
                startedAt = normalizeResearchDuration(it.startedAt),
                endedAt = max(normalizeResearchDuration(it.startedAt), normalizeResearchDuration(it.endedAt)),
                activeMs = normalizeResearchDuration(it.activeMs),
                lastOffset = normalizeReadingOffset(it.lastOffset)
            )
        }
    val rawActiveMs = normalizedSegments.sumOf { it.activeMs }
    val credited = creditResearchSegments(normalizedSegments, zoneId)
    val creditedActiveMs = credited.sumOf { it.activeMs }
    val daily = credited
        .groupBy { it.day }
        .map { (day, slices) -> ResearchDailyProgress(day, slices.sumOf { it.activeMs }) }
        .sortedByDescending { it.day }
    val today = Instant.ofEpochMilli(normalizeResearchDuration(now)).atZone(zoneId).toLocalDate()
    val todayActiveMs = daily.firstOrNull { it.day == today }?.activeMs ?: 0L
    val contents = credited
        .groupBy { it.content.key }
        .map { (_, slices) ->
            val activeMs = slices.sumOf { it.activeMs }
            ResearchContentProgress(
                content = slices.first().content,
                activeMs = activeMs,
                researched = activeMs >= ResearchedContentMinMs
            )
        }
        .sortedWith(
            compareByDescending<ResearchContentProgress> { it.activeMs }
                .thenBy { it.content.key }
        )
    val researchedContentCount = contents.count { it.researched }
    val experience = ((creditedActiveMs / ResearchMinuteMs) + researchedContentCount * ResearchedContentReward)
        .coerceAtMost(Int.MAX_VALUE.toLong())
        .toInt()
    val level = researchLevelForExperience(experience)
    val levelThreshold = researchExperienceThreshold(level)
    val nextLevelThreshold = if (level >= ResearchMaxLevel) {
        levelThreshold
    } else {
        researchExperienceThreshold(level + 1)
    }
    return ResearchProgress(
        rawActiveMs = rawActiveMs,
        creditedActiveMs = creditedActiveMs,
        todayActiveMs = todayActiveMs,
        researchedContentCount = researchedContentCount,
        experience = experience,
        level = level,
        rankTitle = researchRankTitleForLevel(level),
        levelThreshold = levelThreshold,
        nextLevelThreshold = nextLevelThreshold,
        levelExperience = experience - levelThreshold,
        levelExperienceTarget = if (level >= ResearchMaxLevel) 0 else nextLevelThreshold - levelThreshold,
        daily = daily,
        contents = contents
    )
}

fun researchExperienceThreshold(level: Int): Int {
    val normalizedLevel = level.coerceIn(1, ResearchMaxLevel)
    return 8 * (normalizedLevel - 1) * (normalizedLevel - 1)
}

fun researchLevelForExperience(experience: Int): Int {
    val normalizedExperience = experience.coerceAtLeast(0)
    var level = 1
    for (candidate in 2..ResearchMaxLevel) {
        if (normalizedExperience < researchExperienceThreshold(candidate)) {
            break
        }
        level = candidate
    }
    return level
}

fun researchRankTitleForLevel(level: Int): ResearchRankTitle {
    val normalizedLevel = level.coerceIn(1, ResearchMaxLevel)
    return when {
        normalizedLevel >= 50 -> ResearchRankTitle.Archivist
        normalizedLevel >= 35 -> ResearchRankTitle.Researcher
        normalizedLevel >= 20 -> ResearchRankTitle.Cataloger
        normalizedLevel >= 10 -> ResearchRankTitle.Reader
        normalizedLevel >= 5 -> ResearchRankTitle.Retriever
        else -> ResearchRankTitle.Visitor
    }
}

private fun creditResearchSegments(
    segments: List<ResearchActivitySegment>,
    zoneId: ZoneId
): List<CreditedResearchSlice> {
    val usedByDay = mutableMapOf<LocalDate, Long>()
    return segments
        .flatMap { splitResearchSegmentByDay(it, zoneId) }
        .sortedWith(compareBy<ResearchDaySlice> { it.day }.thenBy { it.startedAt })
        .mapNotNull { slice ->
            val used = usedByDay[slice.day] ?: 0L
            val remaining = (ResearchDailyCapMs - used).coerceAtLeast(0L)
            val creditedMs = min(slice.activeMs, remaining)
            if (creditedMs <= 0L) {
                null
            } else {
                usedByDay[slice.day] = used + creditedMs
                CreditedResearchSlice(slice.content, slice.day, slice.startedAt, creditedMs)
            }
        }
}

private fun splitResearchSegmentByDay(
    segment: ResearchActivitySegment,
    zoneId: ZoneId
): List<ResearchDaySlice> {
    val activeMs = normalizeResearchDuration(segment.activeMs)
    if (activeMs == 0L) return emptyList()
    val startedAt = normalizeResearchDuration(segment.startedAt)
    val endedAt = max(startedAt, normalizeResearchDuration(segment.endedAt))
    val startDay = Instant.ofEpochMilli(startedAt).atZone(zoneId).toLocalDate()
    if (endedAt <= startedAt) {
        return listOf(ResearchDaySlice(segment.content, startDay, startedAt, endedAt, activeMs))
    }

    val wallSpan = endedAt - startedAt
    val slices = mutableListOf<ResearchDaySlice>()
    var cursor = startedAt
    var allocated = 0L
    while (cursor < endedAt) {
        val cursorDateTime = Instant.ofEpochMilli(cursor).atZone(zoneId)
        val day = cursorDateTime.toLocalDate()
        val nextDayStart = day.plusDays(1).atStartOfDay(zoneId).toInstant().toEpochMilli()
        val sliceEndAt = min(endedAt, nextDayStart)
        val isLast = sliceEndAt >= endedAt
        val sliceActiveMs = if (isLast) {
            activeMs - allocated
        } else {
            (activeMs * ((sliceEndAt - cursor).toDouble() / wallSpan)).toLong()
        }
        if (sliceActiveMs > 0L) {
            slices += ResearchDaySlice(segment.content, day, cursor, sliceEndAt, sliceActiveMs)
            allocated += sliceActiveMs
        }
        cursor = sliceEndAt
    }
    return slices
}
