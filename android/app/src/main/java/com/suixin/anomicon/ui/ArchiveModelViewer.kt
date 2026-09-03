package com.suixin.anomicon.ui

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.CloudDownload
import androidx.compose.material.icons.outlined.ViewInAr
import androidx.compose.material3.AssistChip
import androidx.compose.material3.Button
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.suixin.anomicon.core.model.ArchiveAsset
import com.suixin.anomicon.core.model.ArchiveAssetDelivery
import com.suixin.anomicon.core.data.AnomiconRepository
import com.suixin.anomicon.core.data.ArchiveDownloadProgress
import com.google.android.filament.gltfio.FilamentInstance
import io.github.sceneview.SceneView
import io.github.sceneview.SurfaceType
import io.github.sceneview.math.Position
import io.github.sceneview.rememberCameraManipulator
import io.github.sceneview.rememberEngine
import io.github.sceneview.rememberModelInstance
import io.github.sceneview.rememberModelLoader
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.File

@Composable
fun ArchiveModelViewer(
    asset: ArchiveAsset,
    repository: AnomiconRepository,
    modifier: Modifier = Modifier
) {
    Surface(
        modifier = modifier,
        color = MaterialTheme.colorScheme.surfaceVariant,
        shape = RoundedCornerShape(8.dp),
        border = BorderStroke(1.dp, MaterialTheme.colorScheme.outlineVariant)
    ) {
        if (asset.delivery == ArchiveAssetDelivery.Bundled && asset.resourcePath.isNotBlank()) {
            BundledGlbScene(asset = asset)
        } else {
            RemoteGlbScene(asset = asset, repository = repository)
        }
    }
}

@Composable
private fun BundledGlbScene(asset: ArchiveAsset) {
    val engine = rememberEngine()
    val modelLoader = rememberModelLoader(engine)
    val modelInstance = rememberModelInstance(modelLoader, asset.resourcePath)

    Box(Modifier.fillMaxSize()) {
        if (modelInstance == null) {
            LoadingModelPlaceholder(asset = asset)
        } else {
            SceneView(
                modifier = Modifier.fillMaxSize(),
                surfaceType = SurfaceType.TextureSurface,
                engine = engine,
                modelLoader = modelLoader,
                autoFitContent = true,
                cameraManipulator = rememberCameraManipulator(orbitRadius = 3.2f)
            ) {
                ModelNode(
                    modelInstance = modelInstance,
                    autoAnimate = false,
                    scaleToUnits = asset.initialScale.coerceAtLeast(1f),
                    centerOrigin = Position(y = -1f)
                )
            }
        }
        AssistChip(
            modifier = Modifier
                .align(Alignment.TopStart)
                .padding(12.dp),
            onClick = {},
            leadingIcon = { Icon(Icons.Outlined.ViewInAr, contentDescription = null) },
            label = { Text("Filament GLB") }
        )
        Text(
            text = "单指旋转 · 双指缩放/平移",
            modifier = Modifier
                .align(Alignment.BottomCenter)
                .padding(12.dp),
            style = MaterialTheme.typography.labelMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )
    }
}

@Composable
private fun LoadingModelPlaceholder(asset: ArchiveAsset) {
    Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
        Column(horizontalAlignment = Alignment.CenterHorizontally) {
            Icon(Icons.Outlined.ViewInAr, contentDescription = null, modifier = Modifier.size(48.dp))
            Spacer(Modifier.height(8.dp))
            Text("正在加载 ${asset.title} GLB")
        }
    }
}

@Composable
private fun RemoteGlbScene(
    asset: ArchiveAsset,
    repository: AnomiconRepository
) {
    var modelFile by remember(asset.assetId) { mutableStateOf<File?>(null) }
    var downloading by remember(asset.assetId) { mutableStateOf(false) }
    var downloadProgress by remember(asset.assetId) { mutableStateOf<ArchiveDownloadProgress?>(null) }
    var errorMessage by remember(asset.assetId) { mutableStateOf<String?>(null) }
    val scope = rememberCoroutineScope()

    LaunchedEffect(asset.assetId) {
        modelFile = repository.installedArchiveAsset(asset).getOrNull()
    }

    val file = modelFile
    if (file != null) {
        Box(Modifier.fillMaxSize()) {
            LocalFileGlbScene(asset = asset, file = file)
            Row(
                modifier = Modifier
                    .align(Alignment.TopEnd)
                    .padding(12.dp),
                horizontalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                AssistChip(
                    onClick = {},
                    leadingIcon = { Icon(Icons.Outlined.ViewInAr, contentDescription = null) },
                    label = { Text("已安装") }
                )
                OutlinedButton(
                    onClick = {
                        scope.launch {
                            repository.deleteArchiveAsset(asset)
                            modelFile = null
                        }
                    }
                ) {
                    Text("删除")
                }
            }
        }
        return
    }

    RemoteAssetPlaceholder(
        asset = asset,
        downloading = downloading,
        progress = downloadProgress,
        errorMessage = errorMessage,
        onDownload = {
            if (!downloading) {
                scope.launch {
                    downloading = true
                    errorMessage = null
                    downloadProgress = null
                    repository.downloadArchiveAsset(asset) { progress ->
                        withContext(Dispatchers.Main.immediate) {
                            downloadProgress = progress
                        }
                    }.fold(
                        onSuccess = { modelFile = it },
                        onFailure = { errorMessage = it.message ?: "三维模型下载失败" }
                    )
                    downloading = false
                }
            }
        }
    )
}

@Composable
private fun LocalFileGlbScene(asset: ArchiveAsset, file: File) {
    val engine = rememberEngine()
    val modelLoader = rememberModelLoader(engine)
    val modelInstance by produceState<FilamentInstance?>(initialValue = null, file, modelLoader) {
        value = withContext(Dispatchers.Main.immediate) {
            modelLoader.createModelInstance(file)
        }
    }
    val loadedInstance = modelInstance

    Box(Modifier.fillMaxSize()) {
        if (loadedInstance == null) {
            LoadingModelPlaceholder(asset = asset)
        } else {
            SceneView(
                modifier = Modifier.fillMaxSize(),
                surfaceType = SurfaceType.TextureSurface,
                engine = engine,
                modelLoader = modelLoader,
                autoFitContent = true,
                cameraManipulator = rememberCameraManipulator(orbitRadius = 3.2f)
            ) {
                ModelNode(
                    modelInstance = loadedInstance,
                    autoAnimate = false,
                    scaleToUnits = asset.initialScale.coerceAtLeast(1f),
                    centerOrigin = Position(y = -1f)
                )
            }
        }
        AssistChip(
            modifier = Modifier
                .align(Alignment.TopStart)
                .padding(12.dp),
            onClick = {},
            leadingIcon = { Icon(Icons.Outlined.ViewInAr, contentDescription = null) },
            label = { Text("Filament GLB") }
        )
        Text(
            text = "单指旋转 · 双指缩放/平移",
            modifier = Modifier
                .align(Alignment.BottomCenter)
                .padding(12.dp),
            style = MaterialTheme.typography.labelMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )
    }
}

@Composable
private fun RemoteAssetPlaceholder(
    asset: ArchiveAsset,
    downloading: Boolean,
    progress: ArchiveDownloadProgress?,
    errorMessage: String?,
    onDownload: () -> Unit
) {
    Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
        Column(
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(8.dp),
            modifier = Modifier.padding(20.dp)
        ) {
            Icon(Icons.Outlined.CloudDownload, contentDescription = null, modifier = Modifier.size(48.dp))
            Text(asset.title, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold)
            Spacer(Modifier.height(2.dp))
            Text(
                text = if (downloading) {
                    progress?.let { "正在下载 ${formatDownloadProgress(it)}" } ?: "正在准备下载..."
                } else {
                    "按需下载后保存到应用私有缓存，并校验大小与 SHA-256。"
                },
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
            if (downloading) {
                androidx.compose.material3.LinearProgressIndicator(
                    progress = { progress?.fraction ?: 0f },
                    modifier = Modifier.size(width = 220.dp, height = 4.dp)
                )
            } else {
                Button(onClick = onDownload, enabled = asset.downloadUrl.isNotBlank()) {
                    Icon(Icons.Outlined.CloudDownload, contentDescription = null)
                    Spacer(Modifier.size(8.dp))
                    Text("下载并查看")
                }
            }
            errorMessage?.let {
                Text(it, color = MaterialTheme.colorScheme.error, style = MaterialTheme.typography.bodySmall)
                OutlinedButton(onClick = onDownload) { Text("重试") }
            }
        }
    }
}

private fun formatDownloadProgress(progress: ArchiveDownloadProgress): String {
    val fraction = progress.fraction
    return if (fraction == null) {
        "${formatBytes(progress.downloadedBytes)}"
    } else {
        "${(fraction * 100).toInt()}% · ${formatBytes(progress.downloadedBytes)} / ${formatBytes(progress.totalBytes)}"
    }
}

private fun formatBytes(bytes: Long): String = when {
    bytes < 1024L -> "$bytes B"
    bytes < 1024L * 1024L -> "%.1f KB".format(bytes / 1024.0)
    else -> "%.1f MB".format(bytes / (1024.0 * 1024.0))
}
