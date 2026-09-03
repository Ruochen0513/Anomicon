package com.suixin.anomicon.core.data

import android.content.Context
import java.io.File
import java.security.MessageDigest

data class CachedContent(
    val body: String,
    val fetchedAt: Long
)

/** Small file cache for content that should remain available without a network. */
class AndroidContentCache(context: Context) {
    private val root = File(context.filesDir, "content-cache").apply { mkdirs() }

    fun read(key: String, extension: String): CachedContent? {
        val bodyFile = fileFor(key, extension)
        val metadataFile = fileFor(key, "$extension.meta")
        if (!bodyFile.isFile || !metadataFile.isFile) return null
        return runCatching {
            CachedContent(bodyFile.readText(), metadataFile.readText().trim().toLong())
        }.getOrNull()
    }

    fun write(key: String, extension: String, body: String, fetchedAt: Long = System.currentTimeMillis()) {
        val bodyFile = fileFor(key, extension)
        val metadataFile = fileFor(key, "$extension.meta")
        runCatching {
            writeAtomically(bodyFile, body)
            writeAtomically(metadataFile, fetchedAt.toString())
        }
    }

    fun clear() {
        root.listFiles()?.forEach { it.delete() }
    }

    private fun fileFor(key: String, extension: String): File =
        File(root, "${sha256(key)}.$extension")

    private fun writeAtomically(target: File, body: String) {
        val temporary = File(target.parentFile, "${target.name}.tmp")
        temporary.writeText(body)
        if (!temporary.renameTo(target)) {
            target.delete()
            check(temporary.renameTo(target)) { "无法写入缓存文件：${target.name}" }
        }
    }

    private fun sha256(value: String): String {
        val digest = MessageDigest.getInstance("SHA-256").digest(value.toByteArray())
        return digest.joinToString("") { byte -> "%02x".format(byte) }
    }
}
