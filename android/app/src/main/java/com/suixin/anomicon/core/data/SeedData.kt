package com.suixin.anomicon.core.data

import com.suixin.anomicon.core.model.ArchiveAsset
import com.suixin.anomicon.core.model.ArchiveAssetDelivery
import com.suixin.anomicon.core.model.ArchiveAssetSource
import com.suixin.anomicon.core.model.CatalogEntry
import com.suixin.anomicon.core.model.ExploreEntry
import com.suixin.anomicon.core.model.TaleEntry

object SeedData {
    private const val SourceRepository = "https://github.com/Yni-Viar/scp-unity-assets"
    private const val SourceCommit = "7fda38944f51db7ee3aeb4d9e5ca821263153da5"
    private const val AssetsRepository = "https://github.com/Yni-Viar/scp-assets"
    private const val AssetsCommit = "1265487d1978b60398ab71f366bc5a1ba4ce1d0d"
    private const val CcBySa30 = "CC BY-SA 3.0"
    private const val RepresentationNotice = "社区创作的视觉重建，不代表 SCP 官方形象或实体复原。"
    private const val MobileProcessingNotice =
        "移动端优化：从上游动画烘焙静态观察姿势，移除运行时动画，将内嵌贴图缩放至 1024px、清理未使用数据，并加入档案交互根节点。"
    private const val RemoteRuntimeNotice =
        "按需下载上游自包含 GLB；加载时仅采样命名待机动画，并由查看器添加居中与交互根节点，不改写原文件。"

    val fallbackCatalog: List<CatalogEntry> = listOf(
        CatalogEntry("SCP-049", "瘟疫医生", hasArchive3D = true),
        CatalogEntry("SCP-079", "旧 AI", hasArchive3D = true),
        CatalogEntry("SCP-096", "羞涩的人"),
        CatalogEntry("SCP-106", "恐怖老人", hasArchive3D = true),
        CatalogEntry("SCP-131", "眼豆", hasArchive3D = true),
        CatalogEntry("SCP-173", "雕像", hasArchive3D = true),
        CatalogEntry("SCP-178", "三维眼镜", hasArchive3D = true),
        CatalogEntry("SCP-650", "惊吓雕像", hasArchive3D = true),
        CatalogEntry("SCP-686", "传染性液体容器", hasArchive3D = true),
        CatalogEntry("SCP-939", "千喉之兽", hasArchive3D = true),
        CatalogEntry("SCP-3199", "人类，反驳！", hasArchive3D = true)
    )

    val fallbackTales: List<TaleEntry> = listOf(
        TaleEntry("about-the-foundation", "关于基金会"),
        TaleEntry("document-recovered-from-the-marianas-trench", "自马里亚纳海沟回收的文件"),
        TaleEntry("incident-096-1-a", "事故 096-1-A"),
        TaleEntry("the-things-dr-bright-is-not-allowed-to-do-at-the-foundation", "Bright 博士禁止事项")
    )

    val fallbackExplore: List<ExploreEntry> = listOf(
        ExploreEntry("scp-173", "SCP-173 - 雕像", 3200),
        ExploreEntry("scp-049", "SCP-049 - 瘟疫医生", 2900),
        ExploreEntry("scp-106", "SCP-106 - 恐怖老人", 2600),
        ExploreEntry("scp-939", "SCP-939 - 千喉之兽", 2100),
        ExploreEntry("scp-131", "SCP-131 - 眼豆", 1800),
        ExploreEntry("scp-079", "SCP-079 - 旧 AI", 1600)
    )

    val archiveAssets: List<ArchiveAsset> = listOf(
        bundled(
            assetId = "scp-106-mobile-v1",
            contentId = "scp-106",
            resourcePath = "models/scp-106.glb",
            version = "1.0.0-mobile-pose",
            byteLength = 8662380,
            sha256 = "b4141e5b4ca03cce7da388a28d0d18d25a8dbb9d88545e79028ebd965fd0d23b",
            attribution = "Aruspice（模型/贴图）、Shakles（绑定/动画）、PixelPuffin（概念设计）",
            contentAttribution = "条目来源：SCP Wiki / SCP-106",
            sourceLabel = "Yni-Viar/scp-unity-assets · Rigged-Ready/Scp106",
            sourceUrl = unitySourceUrl("Scp106", "Scp106"),
            contentSourceUrl = "https://scp-wiki.wikidot.com/scp-106",
            description = "腐蚀性实体的视觉重建档案。警示：仅呈现外观；不模拟腐蚀性接触、口袋空间或收容失效。",
            objectClass = "KETER",
            estimatedTriangleCount = 16404,
            initialScale = 1.05f
        ),
        bundled(
            assetId = "scp-049-mobile-v2",
            contentId = "scp-049",
            resourcePath = "models/scp-049.glb",
            version = "2.1.0-mobile-pose",
            byteLength = 6947368,
            sha256 = "7d9fd347d38e67ed2e3b8465b62d27674cacfeeb15c4e31b953fef19e97ef962",
            attribution = "Aruspice（模型/贴图）、Shakles（绑定/动画）、PixelPuffin（概念设计）",
            contentAttribution = "条目作者：Gabriel Jade；重写：djkaktus、Gabriel Jade",
            sourceLabel = "Yni-Viar/scp-unity-assets · Rigged-Ready/Scp049",
            sourceUrl = unitySourceUrl("Scp049", "Scp049"),
            contentSourceUrl = "https://scp-wiki.wikidot.com/scp-049",
            description = "瘟疫医生形象的视觉重建档案。警示：仅呈现外观；不模拟接触感染或异常行为。",
            objectClass = "EUCLID",
            estimatedTriangleCount = 12720,
            initialScale = 1.09f
        ),
        bundled(
            assetId = "scp-173-mobile-v2",
            contentId = "scp-173",
            resourcePath = "models/scp-173.glb",
            version = "2.1.0-mobile-pose",
            byteLength = 3969944,
            sha256 = "f89aefe1f7cf116dc8c12e9c5d554278217afe4744e49e14ab52840ca91f256d",
            attribution = "Aruspice（模型/贴图）、Shakles（绑定/动画）、PixelPuffin（概念设计）",
            contentAttribution = "条目作者：Moto42",
            sourceLabel = "Yni-Viar/scp-unity-assets · Rigged-Ready/Scp173",
            sourceUrl = unitySourceUrl("Scp173", "Scp173"),
            contentSourceUrl = "https://scp-wiki.wikidot.com/scp-173",
            description = "具备观测依赖特征的雕像视觉重建档案。警示：仅呈现静态模型；不模拟眨眼、视线中断或移动事件。",
            objectClass = "EUCLID",
            estimatedTriangleCount = 16104,
            initialScale = 1.04f
        ),
        bundled(
            assetId = "scp-939-mobile-v2",
            contentId = "scp-939",
            resourcePath = "models/scp-939.glb",
            version = "2.1.0-mobile-pose",
            byteLength = 3209604,
            sha256 = "cd243a640bcba5379609957ebb94beea3c31c2bd8a6e7e8a53e605abe4a33767",
            attribution = "Apocryphos（模型）、Shadowscale（贴图）、Shakles（绑定/动画）",
            contentAttribution = "条目作者：Adam Smascher、EchoFourDelta",
            sourceLabel = "Yni-Viar/scp-unity-assets · Rigged-Ready/Scp939",
            sourceUrl = unitySourceUrl("Scp939", "Scp939"),
            contentSourceUrl = "https://scp-wiki.wikidot.com/scp-939",
            description = "拟态掠食者的视觉重建档案。警示：仅呈现外观；不包含声音拟态、群体行为或感知效果。",
            objectClass = "KETER",
            estimatedTriangleCount = 10368,
            initialScale = 1.32f
        ),
        remote("scp-131-orange-mobile-v1", "scp-131", 12429448, "5e01d45bcb75bff4465f3b6418169919ea35ece79346e0e540d085b704a0a32a", "Scp131", "Scp131Orange", "友善眼状实体 SCP-131-A 的视觉重建档案。", "SAFE", 4104, 10.8f),
        remote("scp-3199-mobile-v1", "scp-3199", 51054324, "c83d9cf29b7282827c94924e1ccd6983c8c94a175b1e0df9a9d7a7e9a76800e1", "Scp3199", "Scp3199", "鸟类特征异常生物的视觉重建档案。", "KETER", 16002, 1.03f),
        remote("scp-650-mobile-v1", "scp-650", 8180984, "62bf92f0cd131fc0f71268a264c79eb02b9387c360dc60fe88c89226c5620c44", "Scp650", "Scp650", "会改变观察位置的雕像视觉重建档案。", "EUCLID", 8640, 1.19f),
        remote(
            assetId = "scp-079-cb-v1",
            contentId = "scp-079",
            byteLength = 2771372,
            sha256 = "6cd62bd301387cfbedaa848c93fbad06cab8c1730702816a94e88b34593a5e83",
            folder = "GFX/SCP-CB/EditedByYni/scp079/079",
            fileName = "Scp079",
            description = "早期自适应计算机实体的视觉重建档案。",
            objectClass = "EUCLID",
            estimatedTriangleCount = 13228,
            initialScale = 4.8f,
            assetsRepository = true
        ),
        remote(
            assetId = "scp-178-cb-v1",
            contentId = "scp-178",
            byteLength = 2330788,
            sha256 = "9a2eb124b43470a8208c1235d52a528c9be1ced0c4c2fa509a06e57bbbc62f1e",
            folder = "GFX/SCP-CB/Characters/Scp178-1",
            fileName = "Scp178-1",
            description = "SCP-178 相关三维实体的视觉重建档案。",
            objectClass = "SAFE",
            estimatedTriangleCount = 27958,
            initialScale = 1.12f,
            assetsRepository = true
        ),
        remote(
            assetId = "scp-686-icard-v1",
            contentId = "scp-686",
            byteLength = 129020,
            sha256 = "2b90bc9eb186054dc8ed6200a1195b9444c526460ba4699baead9def1cb8f207",
            folder = "GFX/By_Pop_Pop_Icard/Items/Scp686",
            fileName = "Scp686",
            description = "感染性乳状液体容器的视觉重建档案。",
            objectClass = "SAFE",
            estimatedTriangleCount = 2242,
            initialScale = 8.8f,
            assetsRepository = true
        )
    )

    fun hasArchiveAsset(itemId: String): Boolean =
        archiveAssets.any { it.contentId.equals(itemId.trim().lowercase(), ignoreCase = true) }

    fun archiveAssetFor(itemId: String): ArchiveAsset? =
        archiveAssets.firstOrNull { it.contentId.equals(itemId.trim().lowercase(), ignoreCase = true) }

    private fun bundled(
        assetId: String,
        contentId: String,
        resourcePath: String,
        version: String,
        byteLength: Long,
        sha256: String,
        attribution: String,
        contentAttribution: String,
        sourceLabel: String,
        sourceUrl: String,
        contentSourceUrl: String,
        description: String,
        objectClass: String,
        estimatedTriangleCount: Int,
        initialScale: Float
    ): ArchiveAsset = ArchiveAsset(
        assetId = assetId,
        contentId = contentId,
        resourcePath = resourcePath,
        source = ArchiveAssetSource.Bundled,
        delivery = ArchiveAssetDelivery.Bundled,
        version = version,
        byteLength = byteLength,
        sha256 = sha256,
        license = CcBySa30,
        attribution = attribution,
        contentAttribution = contentAttribution,
        sourceLabel = sourceLabel,
        sourceUrl = sourceUrl,
        downloadUrl = "",
        contentSourceUrl = contentSourceUrl,
        description = description,
        objectClass = objectClass,
        notice = "$RepresentationNotice $description",
        modificationNote = MobileProcessingNotice,
        estimatedTriangleCount = estimatedTriangleCount,
        renderTargetMaxPx = 768,
        initialScale = initialScale
    )

    private fun remote(
        assetId: String,
        contentId: String,
        byteLength: Long,
        sha256: String,
        folder: String,
        fileName: String,
        description: String,
        objectClass: String,
        estimatedTriangleCount: Int,
        initialScale: Float,
        assetsRepository: Boolean = false
    ): ArchiveAsset {
        val path = "$folder/$fileName.glb"
        val sourceUrl = if (assetsRepository) assetsSourceUrl(path) else unitySourceUrl(folder, fileName)
        val rawUrl = if (assetsRepository) assetsRawUrl(path) else unityRawUrl(folder, fileName)
        val sourceLabel = if (assetsRepository) {
            "Yni-Viar/scp-assets · $path"
        } else {
            "Yni-Viar/scp-unity-assets · Rigged-Ready/$folder/$fileName"
        }
        return ArchiveAsset(
            assetId = assetId,
            contentId = contentId,
            resourcePath = "",
            source = ArchiveAssetSource.Remote,
            delivery = ArchiveAssetDelivery.OnDemand,
            version = "1.0.0-upstream",
            byteLength = byteLength,
            sha256 = sha256,
            license = CcBySa30,
            attribution = "社区三维资源作者，详见来源仓库",
            contentAttribution = "条目来源：SCP Wiki / ${contentId.uppercase()}",
            sourceLabel = sourceLabel,
            sourceUrl = sourceUrl,
            downloadUrl = rawUrl,
            contentSourceUrl = "https://scp-wiki.wikidot.com/$contentId",
            description = description,
            objectClass = objectClass,
            notice = "$RepresentationNotice $description",
            modificationNote = RemoteRuntimeNotice,
            estimatedTriangleCount = estimatedTriangleCount,
            renderTargetMaxPx = 768,
            initialScale = initialScale
        )
    }

    private fun unitySourceUrl(folder: String, fileName: String): String =
        "$SourceRepository/blob/$SourceCommit/Rigged-Ready/$folder/$fileName.glb"

    private fun unityRawUrl(folder: String, fileName: String): String =
        "https://raw.githubusercontent.com/Yni-Viar/scp-unity-assets/$SourceCommit/Rigged-Ready/$folder/$fileName.glb"

    private fun assetsSourceUrl(path: String): String =
        "$AssetsRepository/blob/$AssetsCommit/$path"

    private fun assetsRawUrl(path: String): String =
        "https://raw.githubusercontent.com/Yni-Viar/scp-assets/$AssetsCommit/$path"
}
