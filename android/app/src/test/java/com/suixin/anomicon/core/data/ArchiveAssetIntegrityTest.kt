package com.suixin.anomicon.core.data

import com.suixin.anomicon.core.model.ArchiveAsset
import com.suixin.anomicon.core.model.ArchiveAssetDelivery
import com.suixin.anomicon.core.model.ArchiveAssetSource
import org.junit.After
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

class ArchiveAssetIntegrityTest {
    private val files = mutableListOf<File>()

    @After
    fun tearDown() {
        files.forEach { it.delete() }
    }

    @Test
    fun acceptsFileWithExpectedSizeAndSha256() {
        val file = temporaryFile("anomicon-glb", "verified model")
        val asset = assetFor(file.length(), ArchiveAssetIntegrity.sha256(file))

        assertTrue(ArchiveAssetIntegrity.isValid(asset, file))
    }

    @Test
    fun rejectsFileWithUnexpectedSize() {
        val file = temporaryFile("anomicon-glb", "verified model")
        val asset = assetFor(file.length() + 1, ArchiveAssetIntegrity.sha256(file))

        assertFalse(ArchiveAssetIntegrity.isValid(asset, file))
    }

    @Test
    fun rejectsFileWithUnexpectedSha256() {
        val file = temporaryFile("anomicon-glb", "verified model")
        val asset = assetFor(file.length(), "0".repeat(64))

        assertFalse(ArchiveAssetIntegrity.isValid(asset, file))
    }

    private fun temporaryFile(prefix: String, suffix: String): File =
        File.createTempFile(prefix, ".glb").also {
            it.writeText(suffix)
            files += it
        }

    private fun assetFor(byteLength: Long, sha256: String): ArchiveAsset = ArchiveAsset(
        assetId = "test-asset",
        contentId = "scp-999",
        resourcePath = "",
        source = ArchiveAssetSource.Remote,
        delivery = ArchiveAssetDelivery.OnDemand,
        version = "test",
        byteLength = byteLength,
        sha256 = sha256,
        license = "test",
        attribution = "test",
        contentAttribution = "test",
        sourceLabel = "test",
        sourceUrl = "https://example.com/source",
        downloadUrl = "https://example.com/model.glb",
        contentSourceUrl = "https://example.com/article",
        description = "test",
        objectClass = "SAFE",
        notice = "test",
        modificationNote = "test",
        estimatedTriangleCount = 1,
        renderTargetMaxPx = 768,
        initialScale = 1f
    )
}
