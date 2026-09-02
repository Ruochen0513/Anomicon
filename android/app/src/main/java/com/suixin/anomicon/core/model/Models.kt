package com.suixin.anomicon.core.model

import java.time.LocalDate
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
    val scrollOffset: Int = 0
)

data class LibrarySnapshot(
    val favorites: List<ContentRef> = emptyList(),
    val history: List<ReadingHistoryEntry> = emptyList()
)

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
