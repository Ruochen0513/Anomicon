package com.suixin.anomicon.core.data

import android.content.Context
import com.suixin.anomicon.core.model.AppSettings
import com.suixin.anomicon.core.model.ContentKind
import com.suixin.anomicon.core.model.ContentRef
import com.suixin.anomicon.core.model.LibrarySnapshot
import com.suixin.anomicon.core.model.ReadingHistoryEntry
import com.suixin.anomicon.core.model.ResearchActivitySegment
import com.suixin.anomicon.core.model.ThemeMode
import com.suixin.anomicon.core.model.normalizeReadingBlockCount
import com.suixin.anomicon.core.model.normalizeReadingOffset
import com.suixin.anomicon.core.model.normalizeResearchDuration
import org.json.JSONArray
import org.json.JSONObject
import kotlin.math.max
import kotlin.math.min

class AndroidLocalStore(context: Context) {
    private val prefs = context.getSharedPreferences("anomicon_android", Context.MODE_PRIVATE)

    private companion object {
        const val MaxHistoryEntries = 500
        const val MaxResearchSegments = 2_000
        const val ActiveReadIdleCapMs = 90_000L
    }

    fun loadSettings(): AppSettings =
        AppSettings(
            themeMode = ThemeMode.entries.firstOrNull { it.name == prefs.getString("themeMode", ThemeMode.System.name) }
                ?: ThemeMode.System,
            hapticEnabled = prefs.getBoolean("hapticEnabled", true),
            immersiveMaterialEnabled = prefs.getBoolean("immersiveMaterialEnabled", true),
            fontSize = prefs.getFloat("fontSize", 18f),
            lineHeightMultiple = prefs.getFloat("lineHeightMultiple", 1.6f)
        ).normalized()

    fun saveSettings(settings: AppSettings) {
        val normalized = settings.normalized()
        prefs.edit()
            .putString("themeMode", normalized.themeMode.name)
            .putBoolean("hapticEnabled", normalized.hapticEnabled)
            .putBoolean("immersiveMaterialEnabled", normalized.immersiveMaterialEnabled)
            .putFloat("fontSize", normalized.fontSize)
            .putFloat("lineHeightMultiple", normalized.lineHeightMultiple)
            .apply()
    }

    fun loadLibrary(): LibrarySnapshot {
        val favorites = decodeContentArray(prefs.getString("favorites", null))
        val history = decodeHistoryArray(prefs.getString("history", null))
        val activitySegments = decodeActivitySegments(prefs.getString("activitySegments", null))
        return LibrarySnapshot(
            favorites = favorites,
            history = history,
            activitySegments = activitySegments
        )
    }

    fun toggleFavorite(content: ContentRef): LibrarySnapshot {
        val current = loadLibrary()
        val favorites = if (current.favorites.any { it.key == content.key }) {
            current.favorites.filterNot { it.key == content.key }
        } else {
            listOf(content) + current.favorites
        }
        saveLibrary(current.copy(favorites = favorites))
        return loadLibrary()
    }

    fun recordRead(
        content: ContentRef,
        scrollOffset: Int? = null,
        blockCount: Int? = null,
        creditActiveTime: Boolean = false
    ): LibrarySnapshot {
        val now = System.currentTimeMillis()
        val current = loadLibrary()
        val existing = current.history.firstOrNull { it.content.key == content.key }
        val openedAt = existing?.openedAt ?: now
        val resolvedOffset = normalizeReadingOffset(scrollOffset ?: existing?.scrollOffset ?: 0)
        val resolvedBlockCount = max(
            normalizeReadingBlockCount(blockCount ?: existing?.blockCount ?: 0),
            if (resolvedOffset > 0) resolvedOffset + 1 else 0
        )
        val creditedMs = activeDelta(existing, now, creditActiveTime)
        val updated = ReadingHistoryEntry(
            content = content,
            openedAt = openedAt,
            lastReadAt = now,
            scrollOffset = resolvedOffset,
            blockCount = resolvedBlockCount,
            activeMs = normalizeResearchDuration((existing?.activeMs ?: 0L) + creditedMs)
        )
        val history = (listOf(updated) + current.history.filterNot { it.content.key == content.key })
            .take(MaxHistoryEntries)
        val activitySegments = appendActivitySegment(
            current.activitySegments,
            content,
            existing,
            now,
            creditedMs,
            resolvedOffset
        )
        saveLibrary(current.copy(history = history, activitySegments = activitySegments))
        return loadLibrary()
    }

    private fun saveLibrary(snapshot: LibrarySnapshot) {
        prefs.edit()
            .putString("favorites", encodeContentArray(snapshot.favorites).toString())
            .putString("history", encodeHistoryArray(snapshot.history).toString())
            .putString("activitySegments", encodeActivitySegments(snapshot.activitySegments).toString())
            .apply()
    }

    private fun activeDelta(existing: ReadingHistoryEntry?, now: Long, creditActiveTime: Boolean): Long {
        if (!creditActiveTime || existing == null || existing.lastReadAt <= 0L) {
            return 0L
        }
        val delta = now - existing.lastReadAt
        if (delta <= 0L) {
            return 0L
        }
        return min(delta, ActiveReadIdleCapMs)
    }

    private fun appendActivitySegment(
        current: List<ResearchActivitySegment>,
        content: ContentRef,
        existing: ReadingHistoryEntry?,
        now: Long,
        activeMs: Long,
        lastOffset: Int
    ): List<ResearchActivitySegment> {
        if (activeMs <= 0L) {
            return current
        }
        val startedAt = max(0L, now - activeMs)
        val segment = ResearchActivitySegment(
            segmentId = "${content.key}:$now:${current.size}",
            content = content,
            startedAt = startedAt,
            endedAt = now,
            activeMs = activeMs,
            lastOffset = lastOffset
        )
        val last = current.lastOrNull()
        val merged = if (
            existing != null &&
            last != null &&
            last.content.key == content.key &&
            startedAt <= last.endedAt + 1_000L
        ) {
            current.dropLast(1) + last.copy(
                endedAt = now,
                activeMs = normalizeResearchDuration(last.activeMs + activeMs),
                lastOffset = lastOffset
            )
        } else {
            current + segment
        }
        return merged.takeLast(MaxResearchSegments)
    }

    private fun decodeContentArray(raw: String?): List<ContentRef> {
        if (raw.isNullOrBlank()) return emptyList()
        return runCatching {
            val array = JSONArray(raw)
            List(array.length()) { index ->
                val item = array.getJSONObject(index)
                ContentRef.create(
                    kind = ContentKind.valueOf(item.getString("kind")),
                    id = item.getString("id"),
                    title = item.optString("title", item.getString("id"))
                )
            }
        }.getOrDefault(emptyList())
    }

    private fun decodeHistoryArray(raw: String?): List<ReadingHistoryEntry> {
        if (raw.isNullOrBlank()) return emptyList()
        return runCatching {
            val array = JSONArray(raw)
            List(array.length()) { index ->
                val item = array.getJSONObject(index)
                ReadingHistoryEntry(
                    content = ContentRef.create(
                        kind = ContentKind.valueOf(item.getString("kind")),
                        id = item.getString("id"),
                        title = item.optString("title", item.getString("id"))
                    ),
                    openedAt = item.optLong("openedAt", 0L),
                    lastReadAt = item.optLong("lastReadAt", 0L),
                    scrollOffset = item.optInt("scrollOffset", 0),
                    blockCount = item.optInt("blockCount", 0),
                    activeMs = item.optLong("activeMs", 0L)
                )
            }
        }.getOrDefault(emptyList())
    }

    private fun decodeActivitySegments(raw: String?): List<ResearchActivitySegment> {
        if (raw.isNullOrBlank()) return emptyList()
        return runCatching {
            val array = JSONArray(raw)
            List(array.length()) { index ->
                val item = array.getJSONObject(index)
                ResearchActivitySegment(
                    segmentId = item.optString("segmentId", "legacy:$index"),
                    content = ContentRef.create(
                        kind = ContentKind.valueOf(item.getString("kind")),
                        id = item.getString("id"),
                        title = item.optString("title", item.getString("id"))
                    ),
                    startedAt = item.optLong("startedAt", 0L),
                    endedAt = item.optLong("endedAt", 0L),
                    activeMs = item.optLong("activeMs", 0L),
                    lastOffset = item.optInt("lastOffset", 0)
                )
            }
        }.getOrDefault(emptyList())
    }

    private fun encodeContentArray(items: List<ContentRef>): JSONArray =
        JSONArray().also { array ->
            items.forEach { content ->
                array.put(
                    JSONObject()
                        .put("kind", content.kind.name)
                        .put("id", content.id)
                        .put("title", content.title)
                )
            }
        }

    private fun encodeHistoryArray(items: List<ReadingHistoryEntry>): JSONArray =
        JSONArray().also { array ->
            items.forEach { entry ->
                array.put(
                    JSONObject()
                        .put("kind", entry.content.kind.name)
                        .put("id", entry.content.id)
                        .put("title", entry.content.title)
                        .put("openedAt", entry.openedAt)
                        .put("lastReadAt", entry.lastReadAt)
                        .put("scrollOffset", entry.scrollOffset)
                        .put("blockCount", entry.blockCount)
                        .put("activeMs", entry.activeMs)
                )
            }
        }

    private fun encodeActivitySegments(items: List<ResearchActivitySegment>): JSONArray =
        JSONArray().also { array ->
            items.forEach { segment ->
                array.put(
                    JSONObject()
                        .put("segmentId", segment.segmentId)
                        .put("kind", segment.content.kind.name)
                        .put("id", segment.content.id)
                        .put("title", segment.content.title)
                        .put("startedAt", segment.startedAt)
                        .put("endedAt", segment.endedAt)
                        .put("activeMs", segment.activeMs)
                        .put("lastOffset", segment.lastOffset)
                )
            }
        }
}
