package com.suixin.anomicon.core.data

import android.content.Context
import com.suixin.anomicon.core.model.ArchiveAsset
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.withContext
import java.io.File
import java.io.IOException
import java.security.MessageDigest
import kotlin.coroutines.coroutineContext
import kotlinx.coroutines.Dispatchers
import okhttp3.OkHttpClient
import okhttp3.Request

data class ArchiveDownloadProgress(
    val downloadedBytes: Long,
    val totalBytes: Long
) {
    val fraction: Float?
        get() = totalBytes.takeIf { it > 0L }?.let {
            (downloadedBytes.toFloat() / it.toFloat()).coerceIn(0f, 1f)
        }
}

object ArchiveAssetIntegrity {
    fun isValid(asset: ArchiveAsset, file: File): Boolean {
        if (!file.isFile || (asset.byteLength > 0L && file.length() != asset.byteLength)) return false
        return asset.sha256.isBlank() || sha256(file) == asset.sha256.lowercase()
    }

    fun sha256(file: File): String {
        val digest = MessageDigest.getInstance("SHA-256")
        file.inputStream().buffered().use { input ->
            val buffer = ByteArray(DEFAULT_BUFFER_SIZE)
            while (true) {
                val read = input.read(buffer)
                if (read < 0) break
                digest.update(buffer, 0, read)
            }
        }
        return digest.digest().joinToString("") { byte -> "%02x".format(byte) }
    }
}

/** Owns verified on-demand GLB files and never exposes a partially written file. */
class AndroidArchiveAssetStore(
    context: Context,
    private val client: OkHttpClient = OkHttpClient.Builder().build()
) {
    private val root = File(context.filesDir, "archive3d/v1/objects")

    suspend fun installedFile(asset: ArchiveAsset): File? = withContext(Dispatchers.IO) {
        val target = fileFor(asset)
        when {
            ArchiveAssetIntegrity.isValid(asset, target) -> target
            target.exists() -> {
                target.delete()
                null
            }
            else -> null
        }
    }

    suspend fun download(
        asset: ArchiveAsset,
        onProgress: suspend (ArchiveDownloadProgress) -> Unit = {}
    ): File = withContext(Dispatchers.IO) {
        require(asset.downloadUrl.isNotBlank()) { "三维模型没有可用下载地址" }
        root.mkdirs()
        val target = fileFor(asset)
        if (ArchiveAssetIntegrity.isValid(asset, target)) {
            onProgress(ArchiveDownloadProgress(target.length(), target.length()))
            return@withContext target
        }

        val temporary = File(target.parentFile, "${target.name}.download")
        temporary.delete()
        val request = Request.Builder()
            .url(asset.downloadUrl)
            .header("User-Agent", "Anomicon-Android-Migration/1.0")
            .build()
        try {
            client.newCall(request).execute().use { response ->
                if (!response.isSuccessful) throw IOException("HTTP ${response.code}: ${asset.downloadUrl}")
                val body = response.body ?: throw IOException("三维模型响应为空")
                val totalBytes = asset.byteLength.takeIf { it > 0L } ?: body.contentLength()
                var downloadedBytes = 0L
                body.byteStream().buffered().use { input ->
                    temporary.outputStream().buffered().use { output ->
                        val buffer = ByteArray(DEFAULT_BUFFER_SIZE)
                        while (true) {
                            coroutineContext.ensureActive()
                            val read = input.read(buffer)
                            if (read < 0) break
                            output.write(buffer, 0, read)
                            downloadedBytes += read
                            onProgress(ArchiveDownloadProgress(downloadedBytes, totalBytes))
                        }
                    }
                }
            }
            if (!ArchiveAssetIntegrity.isValid(asset, temporary)) {
                throw IOException("三维模型校验失败：大小或 SHA-256 不匹配")
            }
            if (!temporary.renameTo(target)) {
                target.delete()
                check(temporary.renameTo(target)) { "无法安装三维模型缓存" }
            }
            target
        } finally {
            temporary.delete()
        }
    }

    suspend fun delete(asset: ArchiveAsset): Boolean = withContext(Dispatchers.IO) {
        val target = fileFor(asset)
        val temporary = File(target.parentFile, "${target.name}.download")
        temporary.delete()
        target.delete()
    }

    private fun fileFor(asset: ArchiveAsset): File {
        val hash = asset.sha256.trim().lowercase()
        require(hash.matches(Regex("[0-9a-f]{64}"))) { "三维模型清单 SHA-256 无效" }
        return File(root, "${hash.take(2)}/$hash.glb").also { it.parentFile?.mkdirs() }
    }
}
