package com.suixin.anomicon.core.data

import android.content.Context
import com.suixin.anomicon.core.model.AppSettings
import com.suixin.anomicon.core.model.ContentKind
import com.suixin.anomicon.core.model.ContentRef
import com.suixin.anomicon.core.model.LibrarySnapshot
import com.suixin.anomicon.core.model.ReadingHistoryEntry
import com.suixin.anomicon.core.model.ThemeMode
import org.json.JSONArray
import org.json.JSONObject

class AndroidLocalStore(context: Context) {
    private val prefs = context.getSharedPreferences("anomicon_android", Context.MODE_PRIVATE)

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
        return LibrarySnapshot(favorites = favorites, history = history)
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

    fun recordRead(content: ContentRef, scrollOffset: Int = 0): LibrarySnapshot {
        val now = System.currentTimeMillis()
        val current = loadLibrary()
        val existing = current.history.firstOrNull { it.content.key == content.key }
        val openedAt = existing?.openedAt ?: now
        val updated = ReadingHistoryEntry(content, openedAt, now, scrollOffset.coerceAtLeast(0))
        val history = (listOf(updated) + current.history.filterNot { it.content.key == content.key }).take(500)
        saveLibrary(current.copy(history = history))
        return loadLibrary()
    }

    private fun saveLibrary(snapshot: LibrarySnapshot) {
        prefs.edit()
            .putString("favorites", encodeContentArray(snapshot.favorites).toString())
            .putString("history", encodeHistoryArray(snapshot.history).toString())
            .apply()
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
                    scrollOffset = item.optInt("scrollOffset", 0)
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
                )
            }
        }
}
