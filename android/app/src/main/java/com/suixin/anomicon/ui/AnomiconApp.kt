package com.suixin.anomicon.ui

import android.content.Context
import android.content.Intent
import android.net.Uri
import androidx.activity.compose.BackHandler
import androidx.compose.foundation.clickable
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.Image
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.ArrowBack
import androidx.compose.material.icons.automirrored.outlined.MenuBook
import androidx.compose.material.icons.automirrored.outlined.OpenInNew
import androidx.compose.material.icons.outlined.Bookmarks
import androidx.compose.material.icons.outlined.CloudDownload
import androidx.compose.material.icons.outlined.Explore
import androidx.compose.material.icons.outlined.Favorite
import androidx.compose.material.icons.outlined.FavoriteBorder
import androidx.compose.material.icons.outlined.Info
import androidx.compose.material.icons.outlined.Inventory2
import androidx.compose.material.icons.outlined.Refresh
import androidx.compose.material.icons.outlined.Search
import androidx.compose.material.icons.outlined.Settings
import androidx.compose.material.icons.outlined.ViewInAr
import androidx.compose.material3.AssistChip
import androidx.compose.material3.Button
import androidx.compose.material3.ElevatedCard
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Slider
import androidx.compose.material3.Surface
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.snapshotFlow
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.layout.ContentScale
import android.graphics.BitmapFactory
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import com.suixin.anomicon.core.data.AndroidLocalStore
import com.suixin.anomicon.core.data.AnomiconRepository
import com.suixin.anomicon.core.data.SeedData
import com.suixin.anomicon.core.model.AppSettings
import com.suixin.anomicon.core.model.ArticleBlock
import com.suixin.anomicon.core.model.ArticleDocument
import com.suixin.anomicon.core.model.ArchiveAsset
import com.suixin.anomicon.core.model.ArchiveAssetDelivery
import com.suixin.anomicon.core.model.CatalogEntry
import com.suixin.anomicon.core.model.ContentKind
import com.suixin.anomicon.core.model.ContentRef
import com.suixin.anomicon.core.model.ExploreContentItem
import com.suixin.anomicon.core.model.ExploreEntry
import com.suixin.anomicon.core.model.ExploreHomeData
import com.suixin.anomicon.core.model.LibrarySnapshot
import com.suixin.anomicon.core.model.ReadingSettingsRange
import com.suixin.anomicon.core.model.ReadingHistoryEntry
import com.suixin.anomicon.core.model.ResearchProgress
import com.suixin.anomicon.core.model.ScpSeriesDescriptors
import com.suixin.anomicon.core.model.TaleEntry
import com.suixin.anomicon.core.model.ThemeMode
import com.suixin.anomicon.core.model.articleUrlOf
import com.suixin.anomicon.core.model.deriveResearchProgress
import com.suixin.anomicon.core.model.readingProgressPercent
import com.suixin.anomicon.ui.theme.AnomiconTheme
import kotlinx.coroutines.launch
import kotlinx.coroutines.flow.distinctUntilChanged
import java.io.File
import java.text.DateFormat
import java.util.Date
import java.util.Locale

private enum class HomeTab(val title: String, val icon: ImageVector) {
    Explore("探索", Icons.Outlined.Explore),
    Catalog("图鉴", Icons.Outlined.Inventory2),
    Stories("故事", Icons.AutoMirrored.Outlined.MenuBook),
    Terminal("终端", Icons.Outlined.Bookmarks)
}

@Composable
fun AnomiconApp(
    repository: AnomiconRepository,
    localStore: AndroidLocalStore
) {
    var settings by remember { mutableStateOf(localStore.loadSettings()) }
    var library by remember { mutableStateOf(localStore.loadLibrary()) }
    var selectedTab by remember { mutableStateOf(HomeTab.Explore) }
    var activeContent by remember { mutableStateOf<ContentRef?>(null) }
    var activeArchive by remember { mutableStateOf<ArchiveAsset?>(null) }
    var showSettings by remember { mutableStateOf(false) }
    var showArchiveGallery by remember { mutableStateOf(false) }
    val systemDark = isSystemInDarkTheme()
    val darkTheme = when (settings.themeMode) {
        ThemeMode.System -> systemDark
        ThemeMode.Light -> false
        ThemeMode.Dark -> true
    }
    val hapticFeedback = rememberAndroidHapticFeedback()
    val androidView = currentAndroidView()
    val playSelection: () -> Unit = {
        hapticFeedback.playSelection(settings.hapticEnabled, androidView)
    }

    val openContent: (ContentRef) -> Unit = { content ->
        playSelection()
        library = localStore.recordRead(content)
        activeContent = content
    }
    val toggleFavorite: (ContentRef) -> Unit = { content ->
        playSelection()
        library = localStore.toggleFavorite(content)
    }
    val saveSettings: (AppSettings) -> Unit = { next ->
        val normalized = next.normalized()
        localStore.saveSettings(normalized)
        settings = normalized
    }

    AnomiconTheme(darkTheme = darkTheme) {
        ApplyAndroidSystemBars(
            immersiveMaterialEnabled = settings.immersiveMaterialEnabled,
            darkTheme = darkTheme
        )
        when {
            activeArchive != null -> ArchiveDetailScreen(
                asset = activeArchive!!,
                repository = repository,
                onBack = {
                    playSelection()
                    activeArchive = null
                },
                onOpenArticle = { openContent(activeArchive!!.contentRef) },
                onHaptic = playSelection
            )
            activeContent != null -> ArticleScreen(
                content = activeContent!!,
                settings = settings,
                repository = repository,
                localStore = localStore,
                favorite = library.favorites.any { it.key == activeContent!!.key },
                onBack = {
                    playSelection()
                    activeContent = null
                },
                onToggleFavorite = { toggleFavorite(activeContent!!) },
                onLibraryChanged = { library = it },
                onOpenArchive = { asset ->
                    playSelection()
                    activeArchive = asset
                },
                onHaptic = playSelection
            )
            showSettings -> SettingsScreen(
                settings = settings,
                onBack = {
                    playSelection()
                    showSettings = false
                },
                onSettingsChange = saveSettings,
                onHaptic = playSelection
            )
            showArchiveGallery -> ArchiveGalleryScreen(
                repository = repository,
                onBack = {
                    playSelection()
                    showArchiveGallery = false
                },
                onOpenAsset = { asset ->
                    playSelection()
                    activeArchive = asset
                },
                onOpenArticle = openContent,
                onHaptic = playSelection
            )
            else -> HomeScaffold(
                repository = repository,
                selectedTab = selectedTab,
                library = library,
                onSelectTab = {
                    playSelection()
                    selectedTab = it
                },
                onOpenSettings = {
                    playSelection()
                    showSettings = true
                },
                onOpenArchiveGallery = {
                    playSelection()
                    showArchiveGallery = true
                },
                onOpenContent = openContent,
                onToggleFavorite = toggleFavorite,
                onHaptic = playSelection
            )
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun HomeScaffold(
    repository: AnomiconRepository,
    selectedTab: HomeTab,
    library: LibrarySnapshot,
    onSelectTab: (HomeTab) -> Unit,
    onOpenSettings: () -> Unit,
    onOpenArchiveGallery: () -> Unit,
    onOpenContent: (ContentRef) -> Unit,
    onToggleFavorite: (ContentRef) -> Unit,
    onHaptic: () -> Unit
) {
    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(selectedTab.title) },
                actions = {
                    IconButton(onClick = onOpenArchiveGallery) {
                        Icon(Icons.Outlined.ViewInAr, contentDescription = "三维档案")
                    }
                    IconButton(onClick = onOpenSettings) {
                        Icon(Icons.Outlined.Settings, contentDescription = "设置")
                    }
                }
            )
        },
        bottomBar = {
            NavigationBar {
                HomeTab.entries.forEach { tab ->
                    NavigationBarItem(
                        selected = selectedTab == tab,
                        onClick = { onSelectTab(tab) },
                        icon = { Icon(tab.icon, contentDescription = tab.title) },
                        label = { Text(tab.title) }
                    )
                }
            }
        }
    ) { padding ->
        when (selectedTab) {
            HomeTab.Explore -> ExploreScreen(repository, padding, onOpenContent)
            HomeTab.Catalog -> CatalogScreen(repository, padding, onOpenContent, onHaptic)
            HomeTab.Stories -> StoriesScreen(repository, padding, onOpenContent)
            HomeTab.Terminal -> TerminalScreen(library, padding, onOpenContent, onToggleFavorite)
        }
    }
}

@Composable
private fun ExploreScreen(
    repository: AnomiconRepository,
    padding: PaddingValues,
    onOpenContent: (ContentRef) -> Unit
) {
    var data by remember { mutableStateOf(ExploreHomeData()) }
    var loading by remember { mutableStateOf(true) }
    val scope = rememberCoroutineScope()

    fun reload() {
        loading = true
        scope.launch {
            data = repository.loadExplore()
            loading = false
        }
    }

    LaunchedEffect(Unit) { reload() }

    LazyColumn(
        modifier = Modifier
            .fillMaxSize()
            .padding(padding),
        contentPadding = PaddingValues(horizontal = 16.dp, vertical = 12.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp)
    ) {
        item {
            SectionHeader(
                title = "今日推荐",
                subtitle = "随机 SCP 编号由官网页面验证；离线时回退到经典条目。",
                action = {
                    IconButton(onClick = { reload() }) {
                        Icon(Icons.Outlined.Refresh, contentDescription = "刷新")
                    }
                }
            )
        }
        if (loading) {
            item { LinearProgressIndicator(modifier = Modifier.fillMaxWidth()) }
        }
        item {
            LazyRow(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                items(data.recommendations) { entry ->
                    RecommendationCard(entry = entry, onOpenContent = onOpenContent)
                }
            }
        }
        item {
            EntrySection(
                title = "高评分",
                entries = data.topRated.take(10),
                onOpenContent = { entry ->
                    onOpenContent(ContentRef.create(ContentKind.Scp, entry.normalizedId, entry.title))
                }
            )
        }
        item {
            ContentItemSection(
                title = "最近更新",
                items = data.recent.take(10),
                onOpenContent = onOpenContent
            )
        }
        item {
            ContentItemSection(
                title = "轻松内容",
                items = data.jokes.take(10),
                onOpenContent = onOpenContent
            )
        }
    }
}

@Composable
private fun CatalogScreen(
    repository: AnomiconRepository,
    padding: PaddingValues,
    onOpenContent: (ContentRef) -> Unit,
    onHaptic: () -> Unit
) {
    var selectedSeriesId by remember { mutableStateOf(ScpSeriesDescriptors.first().id) }
    var query by remember { mutableStateOf("") }
    var entries by remember { mutableStateOf<List<CatalogEntry>>(emptyList()) }
    var loading by remember { mutableStateOf(false) }

    LaunchedEffect(selectedSeriesId) {
        loading = true
        entries = repository.loadCatalog(selectedSeriesId).getOrDefault(SeedData.fallbackCatalog)
        loading = false
    }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(padding)
    ) {
        LazyRow(
            contentPadding = PaddingValues(horizontal = 16.dp, vertical = 10.dp),
            horizontalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            items(ScpSeriesDescriptors) { series ->
                FilterChip(
                    selected = selectedSeriesId == series.id,
                    onClick = {
                        onHaptic()
                        selectedSeriesId = series.id
                    },
                    label = { Text(series.label) }
                )
            }
        }
        OutlinedTextField(
            value = query,
            onValueChange = { query = it },
            leadingIcon = { Icon(Icons.Outlined.Search, contentDescription = null) },
            label = { Text("搜索编号或标题") },
            singleLine = true,
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 16.dp)
        )
        if (loading) {
            LinearProgressIndicator(modifier = Modifier.fillMaxWidth())
        }
        val filtered = entries.filter {
            val normalizedQuery = query.trim().lowercase(Locale.ROOT)
            normalizedQuery.isEmpty() ||
                it.itemId.lowercase(Locale.ROOT).contains(normalizedQuery) ||
                it.title.lowercase(Locale.ROOT).contains(normalizedQuery)
        }
        LazyColumn(
            contentPadding = PaddingValues(16.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp)
        ) {
            items(filtered) { entry ->
                CatalogCard(entry = entry, onOpenContent = onOpenContent)
            }
        }
    }
}

@Composable
private fun StoriesScreen(
    repository: AnomiconRepository,
    padding: PaddingValues,
    onOpenContent: (ContentRef) -> Unit
) {
    var query by remember { mutableStateOf("") }
    var tales by remember { mutableStateOf<List<TaleEntry>>(emptyList()) }
    var loading by remember { mutableStateOf(true) }

    LaunchedEffect(Unit) {
        tales = repository.loadTales().getOrDefault(SeedData.fallbackTales)
        loading = false
    }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(padding)
    ) {
        OutlinedTextField(
            value = query,
            onValueChange = { query = it },
            leadingIcon = { Icon(Icons.Outlined.Search, contentDescription = null) },
            label = { Text("搜索故事") },
            singleLine = true,
            modifier = Modifier
                .fillMaxWidth()
                .padding(16.dp)
        )
        if (loading) {
            LinearProgressIndicator(modifier = Modifier.fillMaxWidth())
        }
        val filtered = tales.filter {
            val normalizedQuery = query.trim().lowercase(Locale.ROOT)
            normalizedQuery.isEmpty() ||
                it.id.lowercase(Locale.ROOT).contains(normalizedQuery) ||
                it.title.lowercase(Locale.ROOT).contains(normalizedQuery)
        }
        LazyColumn(
            contentPadding = PaddingValues(horizontal = 16.dp, vertical = 8.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp)
        ) {
            items(filtered) { tale ->
                ElevatedCard(
                    onClick = { onOpenContent(tale.contentRef) },
                    modifier = Modifier.fillMaxWidth()
                ) {
                    Column(Modifier.padding(16.dp)) {
                        Text(tale.title, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold)
                        Text(
                            tale.id,
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                    }
                }
            }
        }
    }
}

@Composable
private fun TerminalScreen(
    library: LibrarySnapshot,
    padding: PaddingValues,
    onOpenContent: (ContentRef) -> Unit,
    onToggleFavorite: (ContentRef) -> Unit
) {
    val researchProgress = remember(library.activitySegments) {
        deriveResearchProgress(library.activitySegments)
    }
    val resumeEntry = library.history.firstOrNull { it.scrollOffset > 0 }
    val resumeKey = resumeEntry?.content?.key
    val recentEntries = library.history
        .filter { it.content.key != resumeKey }
        .take(30)
    LazyColumn(
        modifier = Modifier
            .fillMaxSize()
            .padding(padding),
        contentPadding = PaddingValues(16.dp),
        verticalArrangement = Arrangement.spacedBy(14.dp)
    ) {
        item {
            ResearchProfileSummaryCard(
                progress = researchProgress,
                favoriteCount = library.favorites.size,
                historyCount = library.history.size
            )
        }
        item { SectionHeader(title = "继续阅读", subtitle = "优先显示仍有阅读进度的最近条目。") }
        if (resumeEntry == null) {
            item { EmptyState("暂无可继续的条目。读到正文中段后会自动出现在这里。") }
        } else {
            item {
                ReadingHistoryRow(
                    entry = resumeEntry,
                    onOpen = { onOpenContent(resumeEntry.content) }
                )
            }
        }
        item { SectionHeader(title = "活跃阅读", subtitle = "按已计分阅读时长排序，1 分钟以上计入已研读。") }
        if (researchProgress.contents.isEmpty()) {
            item { EmptyState("还没有可计分的阅读活动。打开文章并阅读片刻即可生成档案。") }
        } else {
            items(researchProgress.contents.take(5)) { contentProgress ->
                ContentRefRow(
                    content = contentProgress.content,
                    subtitle = "${formatDuration(contentProgress.activeMs)} · ${if (contentProgress.researched) "已研读" else "浏览中"}",
                    onOpen = { onOpenContent(contentProgress.content) }
                )
            }
        }
        item { SectionHeader(title = "收藏", subtitle = "保存在本机 SharedPreferences。") }
        if (library.favorites.isEmpty()) {
            item { EmptyState("还没有收藏。打开任意条目后可点星标保存。") }
        } else {
            items(library.favorites) { content ->
                ContentRefRow(
                    content = content,
                    trailing = {
                        IconButton(onClick = { onToggleFavorite(content) }) {
                            Icon(Icons.Outlined.Favorite, contentDescription = "取消收藏")
                        }
                    },
                    onOpen = { onOpenContent(content) }
                )
            }
        }
        item { SectionHeader(title = "最近阅读", subtitle = "打开文章时自动记录位置、进度和活跃时长。") }
        if (recentEntries.isEmpty()) {
            item { EmptyState("暂无阅读记录。") }
        } else {
            items(recentEntries) { entry ->
                ReadingHistoryRow(entry = entry, onOpen = { onOpenContent(entry.content) })
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun ArticleScreen(
    content: ContentRef,
    settings: AppSettings,
    repository: AnomiconRepository,
    localStore: AndroidLocalStore,
    favorite: Boolean,
    onBack: () -> Unit,
    onToggleFavorite: () -> Unit,
    onLibraryChanged: (LibrarySnapshot) -> Unit,
    onOpenArchive: (ArchiveAsset) -> Unit,
    onHaptic: () -> Unit
) {
    BackHandler(onBack = onBack)
    val archiveAsset = SeedData.archiveAssetFor(content.id)
    Scaffold(
        topBar = {
            TopAppBar(
                title = {
                    Text(content.title, maxLines = 1, overflow = TextOverflow.Ellipsis)
                },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Outlined.ArrowBack, contentDescription = "返回")
                    }
                },
                actions = {
                    if (archiveAsset != null) {
                        IconButton(onClick = { onOpenArchive(archiveAsset) }) {
                            Icon(Icons.Outlined.ViewInAr, contentDescription = "三维档案")
                        }
                    }
                    IconButton(onClick = onToggleFavorite) {
                        Icon(
                            if (favorite) Icons.Outlined.Favorite else Icons.Outlined.FavoriteBorder,
                            contentDescription = if (favorite) "取消收藏" else "收藏"
                        )
                    }
                }
            )
        }
    ) { padding ->
        NativeArticleReader(
            content = content,
            settings = settings,
            repository = repository,
                localStore = localStore,
                onLibraryChanged = onLibraryChanged,
                onHaptic = onHaptic,
                modifier = Modifier
                    .fillMaxSize()
                    .padding(padding)
        )
    }
}

@Composable
private fun NativeArticleReader(
    content: ContentRef,
    settings: AppSettings,
    repository: AnomiconRepository,
    localStore: AndroidLocalStore,
    onLibraryChanged: (LibrarySnapshot) -> Unit,
    onHaptic: () -> Unit,
    modifier: Modifier = Modifier
) {
    var document by remember(content.key) { mutableStateOf<ArticleDocument?>(null) }
    var errorMessage by remember(content.key) { mutableStateOf<String?>(null) }
    var loading by remember(content.key) { mutableStateOf(true) }
    var previewFile by remember(content.key) { mutableStateOf<File?>(null) }
    var retryToken by remember(content.key) { mutableStateOf(0) }
    val listState = rememberLazyListState()
    val context = LocalContext.current

    LaunchedEffect(content.key, retryToken) {
        loading = true
        repository.loadArticle(content).fold(
            onSuccess = {
                document = it
                errorMessage = null
                val checkpoint = localStore.loadLibrary().history
                    .firstOrNull { entry -> entry.content.key == content.key }
                    ?.scrollOffset
                    ?.coerceIn(0, (it.blocks.size - 1).coerceAtLeast(0))
                    ?: 0
                if (it.blocks.isNotEmpty() && checkpoint > 0) {
                    listState.scrollToItem(checkpoint)
                }
                onLibraryChanged(
                    localStore.recordRead(
                        content = content,
                        scrollOffset = checkpoint,
                        blockCount = it.blocks.size
                    )
                )
            },
            onFailure = { errorMessage = it.message ?: "文章加载失败" }
        )
        loading = false
    }

    LaunchedEffect(content.key, listState) {
        snapshotFlow { listState.firstVisibleItemIndex }
            .distinctUntilChanged()
            .collect { index ->
                onLibraryChanged(
                    localStore.recordRead(
                        content = content,
                        scrollOffset = index,
                        blockCount = document?.blocks?.size,
                        creditActiveTime = true
                    )
                )
            }
    }

    DisposableEffect(content.key) {
        onDispose {
            onLibraryChanged(
                localStore.recordRead(
                    content = content,
                    scrollOffset = listState.firstVisibleItemIndex,
                    blockCount = document?.blocks?.size,
                    creditActiveTime = true
                )
            )
        }
    }

    Box(modifier) {
        when {
            loading && document == null -> {
                Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                    LinearProgressIndicator(modifier = Modifier.fillMaxWidth(0.7f))
                }
            }
            document == null -> {
                Column(
                    modifier = Modifier
                        .fillMaxSize()
                        .padding(24.dp),
                    horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.spacedBy(12.dp, Alignment.CenterVertically)
                ) {
                    Text(errorMessage ?: "文章暂时不可用", style = MaterialTheme.typography.titleMedium)
                    Text(
                        "联网后重试，或打开 Wiki 原文。",
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        Button(onClick = {
                            onHaptic()
                            loading = true
                            errorMessage = null
                            retryToken += 1
                        }) {
                            Text("重试")
                        }
                        OutlinedButton(onClick = {
                            onHaptic()
                            openUrl(context, articleUrlOf(content.id))
                        }) {
                            Icon(Icons.AutoMirrored.Outlined.OpenInNew, contentDescription = null)
                            Spacer(Modifier.width(6.dp))
                            Text("原文")
                        }
                    }
                }
            }
            else -> {
                val currentDocument = document!!
                val progress = if (currentDocument.blocks.size <= 1) {
                    1f
                } else {
                    listState.firstVisibleItemIndex.toFloat() /
                        (currentDocument.blocks.lastIndex).coerceAtLeast(1)
                }
                LazyColumn(
                    state = listState,
                    modifier = Modifier.fillMaxSize(),
                    contentPadding = PaddingValues(horizontal = 18.dp, vertical = 16.dp),
                    verticalArrangement = Arrangement.spacedBy(12.dp)
                ) {
                    item {
                        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                            LinearProgressIndicator(
                                progress = { progress.coerceIn(0f, 1f) },
                                modifier = Modifier.fillMaxWidth()
                            )
                            Text(
                                text = "原生阅读 · ${currentDocument.blocks.size} 个内容块",
                                style = MaterialTheme.typography.labelMedium,
                                color = MaterialTheme.colorScheme.onSurfaceVariant
                            )
                        }
                    }
                    itemsIndexed(
                        items = currentDocument.blocks,
                        key = { index, _ -> "${currentDocument.content.key}:$index" }
                    ) { _, block ->
                        ArticleBlockView(
                            block = block,
                            settings = settings,
                            repository = repository,
                            onImageLoaded = { previewFile = it },
                            onHaptic = onHaptic
                        )
                    }
                    item {
                        Text(
                            "内容来自 SCP Wiki 缓存；图片按需缓存到本机。",
                            style = MaterialTheme.typography.labelSmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                    }
                }
            }
        }

        if (loading && document != null) {
            LinearProgressIndicator(
                modifier = Modifier
                    .fillMaxWidth()
                    .align(Alignment.TopCenter)
            )
        }
    }

    previewFile?.let { file ->
        val bitmap = remember(file) { BitmapFactory.decodeFile(file.path)?.asImageBitmap() }
        Dialog(
            onDismissRequest = { previewFile = null },
            properties = DialogProperties(usePlatformDefaultWidth = false)
        ) {
            Surface(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(18.dp),
                shape = RoundedCornerShape(8.dp),
                color = MaterialTheme.colorScheme.surface
            ) {
                if (bitmap != null) {
                    Image(
                        bitmap = bitmap,
                        contentDescription = "文章图片预览",
                        contentScale = ContentScale.Fit,
                        modifier = Modifier
                            .fillMaxWidth()
                            .clickable {
                                onHaptic()
                                previewFile = null
                            }
                            .padding(12.dp)
                    )
                } else {
                    Text("图片无法解码", modifier = Modifier.padding(24.dp))
                }
            }
        }
    }
}

@Composable
private fun ArticleBlockView(
    block: ArticleBlock,
    settings: AppSettings,
    repository: AnomiconRepository,
    onImageLoaded: (File) -> Unit,
    onHaptic: () -> Unit
) {
    val bodyStyle = MaterialTheme.typography.bodyLarge.copy(
        fontSize = settings.fontSize.sp,
        lineHeight = (settings.fontSize * settings.lineHeightMultiple).sp
    )
    when (block) {
        is ArticleBlock.Heading -> Text(
            text = block.text,
            style = when (block.level) {
                1 -> MaterialTheme.typography.headlineSmall
                2 -> MaterialTheme.typography.titleLarge
                else -> MaterialTheme.typography.titleMedium
            },
            fontWeight = FontWeight.Bold,
            modifier = Modifier.padding(top = if (block.level <= 2) 10.dp else 4.dp)
        )
        is ArticleBlock.Paragraph -> Text(block.text, style = bodyStyle)
        is ArticleBlock.Quote -> Surface(
            color = MaterialTheme.colorScheme.surfaceVariant,
            shape = RoundedCornerShape(8.dp),
            modifier = Modifier.fillMaxWidth()
        ) {
            Text(block.text, style = bodyStyle, modifier = Modifier.padding(14.dp))
        }
        is ArticleBlock.ListBlock -> Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
            block.items.forEachIndexed { index, item ->
                Text(
                    text = if (block.ordered) "${index + 1}. $item" else "• $item",
                    style = bodyStyle,
                    modifier = Modifier.padding(start = 8.dp)
                )
            }
        }
        is ArticleBlock.Image -> CachedArticleImage(
            image = block,
            repository = repository,
            onImageLoaded = onImageLoaded,
            onHaptic = onHaptic
        )
        ArticleBlock.Divider -> HorizontalDivider()
    }
}

@Composable
private fun CachedArticleImage(
    image: ArticleBlock.Image,
    repository: AnomiconRepository,
    onImageLoaded: (File) -> Unit,
    onHaptic: () -> Unit
) {
    var imageFile by remember(image.url) { mutableStateOf<File?>(null) }
    var failed by remember(image.url) { mutableStateOf(false) }
    LaunchedEffect(image.url) {
        repository.loadImageFile(image.url).fold(
            onSuccess = {
                imageFile = it
                onImageLoaded(it)
            },
            onFailure = { failed = true }
        )
    }
    val bitmap = remember(imageFile) {
        imageFile?.let { BitmapFactory.decodeFile(it.path)?.asImageBitmap() }
    }
    when {
        bitmap != null -> Image(
            bitmap = bitmap,
            contentDescription = image.alt.ifBlank { "文章图片" },
            contentScale = ContentScale.FillWidth,
                modifier = Modifier
                    .fillMaxWidth()
                .clickable {
                    onHaptic()
                    imageFile?.let(onImageLoaded)
                }
        )
        failed -> Text(
            text = image.alt.ifBlank { "图片暂时不可用" },
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )
        else -> Box(
            modifier = Modifier
                .fillMaxWidth()
                .height(160.dp),
            contentAlignment = Alignment.Center
        ) {
            LinearProgressIndicator(modifier = Modifier.fillMaxWidth(0.6f))
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun SettingsScreen(
    settings: AppSettings,
    onBack: () -> Unit,
    onSettingsChange: (AppSettings) -> Unit,
    onHaptic: () -> Unit
) {
    BackHandler(onBack = onBack)
    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("设置") },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Outlined.ArrowBack, contentDescription = "返回")
                    }
                }
            )
        }
    ) { padding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding)
                .verticalScroll(rememberScrollState())
                .padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(18.dp)
        ) {
            Text("主题", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold)
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                ThemeMode.entries.forEach { mode ->
                    FilterChip(
                        selected = settings.themeMode == mode,
                        onClick = {
                            onHaptic()
                            onSettingsChange(settings.copy(themeMode = mode))
                        },
                        label = {
                            Text(
                                when (mode) {
                                    ThemeMode.System -> "跟随系统"
                                    ThemeMode.Light -> "浅色"
                                    ThemeMode.Dark -> "深色"
                                }
                            )
                        }
                    )
                }
            }
            SettingSwitch(
                title = "触感反馈",
                subtitle = "保留 HarmonyOS 版本中的触感开关语义。",
                checked = settings.hapticEnabled,
                onCheckedChange = {
                    onHaptic()
                    onSettingsChange(settings.copy(hapticEnabled = it))
                }
            )
            SettingSwitch(
                title = "沉浸材质",
                subtitle = "Android MVP 先记录设置，后续可映射到动态色/模糊背景。",
                checked = settings.immersiveMaterialEnabled,
                onCheckedChange = {
                    onHaptic()
                    onSettingsChange(settings.copy(immersiveMaterialEnabled = it))
                }
            )
            SettingSlider(
                title = "阅读字号",
                value = settings.fontSize,
                range = ReadingSettingsRange.MinFontSize..ReadingSettingsRange.MaxFontSize,
                label = "${settings.fontSize.toInt()}sp",
                onValueChange = { onSettingsChange(settings.copy(fontSize = it)) }
            )
            SettingSlider(
                title = "阅读行距",
                value = settings.lineHeightMultiple,
                range = ReadingSettingsRange.MinLineHeight..ReadingSettingsRange.MaxLineHeight,
                label = String.format(Locale.ROOT, "%.1fx", settings.lineHeightMultiple),
                onValueChange = { onSettingsChange(settings.copy(lineHeightMultiple = it)) }
            )
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun ArchiveGalleryScreen(
    repository: AnomiconRepository,
    onBack: () -> Unit,
    onOpenAsset: (ArchiveAsset) -> Unit,
    onOpenArticle: (ContentRef) -> Unit,
    onHaptic: () -> Unit
) {
    BackHandler(onBack = onBack)
    var filter by remember { mutableStateOf<ArchiveAssetDelivery?>(ArchiveAssetDelivery.Bundled) }
    val visible = SeedData.archiveAssets.filter { asset ->
        filter == null || asset.delivery == filter
    }
    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("三维档案馆") },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Outlined.ArrowBack, contentDescription = "返回")
                    }
                }
            )
        }
    ) { padding ->
        LazyColumn(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding),
            contentPadding = PaddingValues(16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            item {
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    FilterChip(
                        selected = filter == null,
                        onClick = {
                            onHaptic()
                            filter = null
                        },
                        label = { Text("全部") }
                    )
                    FilterChip(
                        selected = filter == ArchiveAssetDelivery.Bundled,
                        onClick = {
                            onHaptic()
                            filter = ArchiveAssetDelivery.Bundled
                        },
                        label = { Text("已内置") }
                    )
                    FilterChip(
                        selected = filter == ArchiveAssetDelivery.OnDemand,
                        onClick = {
                            onHaptic()
                            filter = ArchiveAssetDelivery.OnDemand
                        },
                        label = { Text("按需") }
                    )
                }
            }
            items(visible) { asset ->
                ArchiveAssetCard(
                    asset = asset,
                    onOpenAsset = onOpenAsset,
                    onOpenArticle = onOpenArticle
                )
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun ArchiveDetailScreen(
    asset: ArchiveAsset,
    repository: AnomiconRepository,
    onBack: () -> Unit,
    onOpenArticle: () -> Unit,
    onHaptic: () -> Unit
) {
    BackHandler(onBack = onBack)
    val context = LocalContext.current
    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(asset.title) },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Outlined.ArrowBack, contentDescription = "返回")
                    }
                }
            )
        }
    ) { padding ->
        LazyColumn(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding),
            contentPadding = PaddingValues(16.dp),
            verticalArrangement = Arrangement.spacedBy(14.dp)
        ) {
            item {
                ArchiveModelViewer(
                    asset = asset,
                    repository = repository,
                    modifier = Modifier
                        .fillMaxWidth()
                        .height(260.dp)
                )
            }
            item {
                ElevatedCard(modifier = Modifier.fillMaxWidth()) {
                    Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                        Text(asset.description, style = MaterialTheme.typography.bodyLarge)
                        MetadataRow("对象等级", asset.objectClass)
                        MetadataRow("交付方式", if (asset.delivery == ArchiveAssetDelivery.Bundled) "随应用内置" else "按需下载")
                        MetadataRow("资源大小", formatBytes(asset.byteLength))
                        MetadataRow("三角面估计", "%,d".format(asset.estimatedTriangleCount))
                        MetadataRow("许可证", asset.license)
                        MetadataRow("归因", asset.attribution)
                    }
                }
            }
            item {
                Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    Button(onClick = {
                        onHaptic()
                        onOpenArticle()
                    }) {
                        Text("打开条目")
                    }
                    OutlinedButton(onClick = {
                        onHaptic()
                        openUrl(context, asset.sourceUrl)
                    }) {
                        Icon(Icons.AutoMirrored.Outlined.OpenInNew, contentDescription = null)
                        Spacer(Modifier.width(6.dp))
                        Text("来源")
                    }
                }
            }
            if (asset.delivery == ArchiveAssetDelivery.OnDemand && asset.downloadUrl.isNotBlank()) {
                item {
                    AssistChip(
                        onClick = {
                            onHaptic()
                            openUrl(context, asset.downloadUrl)
                        },
                        leadingIcon = { Icon(Icons.Outlined.CloudDownload, contentDescription = null) },
                        label = { Text("打开按需资源下载地址") }
                    )
                }
            }
            item {
                Text(
                    asset.notice,
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
        }
    }
}

@Composable
private fun RecommendationCard(
    entry: ExploreEntry,
    onOpenContent: (ContentRef) -> Unit
) {
    ElevatedCard(
        onClick = { onOpenContent(ContentRef.create(ContentKind.Scp, entry.normalizedId, entry.title)) },
        modifier = Modifier.width(230.dp)
    ) {
        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Text(entry.normalizedId.uppercase(Locale.ROOT), color = MaterialTheme.colorScheme.primary)
            Text(entry.title, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold, maxLines = 2)
            Text("进入阅读", style = MaterialTheme.typography.bodySmall)
        }
    }
}

@Composable
private fun EntrySection(
    title: String,
    entries: List<ExploreEntry>,
    onOpenContent: (ExploreEntry) -> Unit
) {
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        SectionHeader(title = title)
        entries.forEach { entry ->
            ElevatedCard(onClick = { onOpenContent(entry) }, modifier = Modifier.fillMaxWidth()) {
                Row(Modifier.padding(14.dp), verticalAlignment = Alignment.CenterVertically) {
                    Column(Modifier.weight(1f)) {
                        Text(entry.title, style = MaterialTheme.typography.titleMedium, maxLines = 1, overflow = TextOverflow.Ellipsis)
                        Text(entry.normalizedId.uppercase(Locale.ROOT), style = MaterialTheme.typography.bodySmall)
                    }
                    if (entry.score >= 0) {
                        Text("+${entry.score}", color = MaterialTheme.colorScheme.primary, fontWeight = FontWeight.Bold)
                    }
                }
            }
        }
    }
}

@Composable
private fun ContentItemSection(
    title: String,
    items: List<ExploreContentItem>,
    onOpenContent: (ContentRef) -> Unit
) {
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        SectionHeader(title = title)
        items.forEach { item ->
            ElevatedCard(onClick = { onOpenContent(item.contentRef) }, modifier = Modifier.fillMaxWidth()) {
                Column(Modifier.padding(14.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                    Text(item.entry.title, style = MaterialTheme.typography.titleMedium, maxLines = 1, overflow = TextOverflow.Ellipsis)
                    Text("${item.sourceLabel} · ${item.entry.normalizedId}", style = MaterialTheme.typography.bodySmall)
                }
            }
        }
    }
}

@Composable
private fun CatalogCard(
    entry: CatalogEntry,
    onOpenContent: (ContentRef) -> Unit
) {
    ElevatedCard(onClick = { onOpenContent(entry.contentRef) }, modifier = Modifier.fillMaxWidth()) {
        Row(
            modifier = Modifier.padding(16.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Text(entry.itemId, color = MaterialTheme.colorScheme.primary, fontWeight = FontWeight.Bold)
                Text(entry.displayTitle, style = MaterialTheme.typography.titleMedium)
            }
            if (entry.hasArchive3D) {
                AssistChip(
                    onClick = { onOpenContent(entry.contentRef) },
                    leadingIcon = { Icon(Icons.Outlined.ViewInAr, contentDescription = null) },
                    label = { Text("3D") }
                )
            }
        }
    }
}

@Composable
private fun ArchiveAssetCard(
    asset: ArchiveAsset,
    onOpenAsset: (ArchiveAsset) -> Unit,
    onOpenArticle: (ContentRef) -> Unit
) {
    ElevatedCard(onClick = { onOpenAsset(asset) }, modifier = Modifier.fillMaxWidth()) {
        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Column(Modifier.weight(1f)) {
                    Text(asset.title, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold)
                    Text(asset.objectClass, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.primary)
                }
                AssistChip(
                    onClick = { onOpenAsset(asset) },
                    label = { Text(if (asset.delivery == ArchiveAssetDelivery.Bundled) "内置" else "按需") }
                )
            }
            Text(asset.description, style = MaterialTheme.typography.bodyMedium, maxLines = 2, overflow = TextOverflow.Ellipsis)
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                TextButton(onClick = { onOpenAsset(asset) }) { Text("详情") }
                TextButton(onClick = { onOpenArticle(asset.contentRef) }) { Text("条目") }
            }
        }
    }
}

@Composable
private fun ContentRefRow(
    content: ContentRef,
    subtitle: String? = null,
    trailing: @Composable (() -> Unit)? = null,
    onOpen: () -> Unit
) {
    ElevatedCard(modifier = Modifier.fillMaxWidth()) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .clickable(onClick = onOpen)
                .padding(14.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Icon(Icons.Outlined.Info, contentDescription = null)
            Spacer(Modifier.width(12.dp))
            Column(Modifier.weight(1f)) {
                Text(content.title, style = MaterialTheme.typography.titleMedium, maxLines = 1, overflow = TextOverflow.Ellipsis)
                Text(
                    subtitle ?: content.id,
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
            trailing?.invoke()
        }
    }
}

@Composable
private fun SectionHeader(
    title: String,
    subtitle: String? = null,
    action: @Composable (() -> Unit)? = null
) {
    Row(verticalAlignment = Alignment.CenterVertically) {
        Column(Modifier.weight(1f)) {
            Text(title, style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold)
            if (subtitle != null) {
                Text(subtitle, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }
        action?.invoke()
    }
}

@Composable
private fun SettingSwitch(
    title: String,
    subtitle: String,
    checked: Boolean,
    onCheckedChange: (Boolean) -> Unit
) {
    Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.fillMaxWidth()) {
        Column(Modifier.weight(1f)) {
            Text(title, style = MaterialTheme.typography.titleMedium)
            Text(subtitle, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
        Switch(checked = checked, onCheckedChange = onCheckedChange)
    }
}

@Composable
private fun SettingSlider(
    title: String,
    value: Float,
    range: ClosedFloatingPointRange<Float>,
    label: String,
    onValueChange: (Float) -> Unit
) {
    Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
            Text(title, style = MaterialTheme.typography.titleMedium)
            Text(label, color = MaterialTheme.colorScheme.primary)
        }
        Slider(value = value, onValueChange = onValueChange, valueRange = range)
    }
}

@Composable
private fun MetadataRow(label: String, value: String) {
    Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
        Text(label, style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
        Text(value, style = MaterialTheme.typography.bodyMedium)
        HorizontalDivider()
    }
}

@Composable
private fun EmptyState(text: String) {
    Surface(
        modifier = Modifier.fillMaxWidth(),
        color = MaterialTheme.colorScheme.surfaceVariant,
        shape = RoundedCornerShape(8.dp)
    ) {
        Text(text, modifier = Modifier.padding(16.dp), color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}

private fun rankLabel(historyCount: Int, favoriteCount: Int): String {
    val score = historyCount + favoriteCount * 2
    return when {
        score >= 80 -> "典藏者"
        score >= 40 -> "考据者"
        score >= 18 -> "编目者"
        score >= 6 -> "研读者"
        score >= 1 -> "检索者"
        else -> "初访者"
    }
}

@Composable
private fun ResearchProfileSummaryCard(
    progress: ResearchProgress,
    favoriteCount: Int,
    historyCount: Int
) {
    ElevatedCard(modifier = Modifier.fillMaxWidth()) {
        Column(
            modifier = Modifier.padding(18.dp),
            verticalArrangement = Arrangement.spacedBy(14.dp)
        ) {
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(14.dp)
            ) {
                Column(
                    modifier = Modifier
                        .size(58.dp),
                    horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.Center
                ) {
                    Text("LV", style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.primary)
                    Text("${progress.level}", style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold)
                }
                Column(Modifier.weight(1f)) {
                    Text("档案阅历", style = MaterialTheme.typography.labelLarge, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    Text(progress.rankTitle.label, style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold)
                    Text("${progress.experience} XP", style = MaterialTheme.typography.bodySmall)
                }
            }
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                Text(
                    if (progress.levelExperienceTarget <= 0) "已达最高等级"
                    else "距 Lv.${progress.level + 1}",
                    style = MaterialTheme.typography.labelMedium
                )
                Text(
                    if (progress.levelExperienceTarget <= 0) "等级上限"
                    else "${progress.levelExperience} / ${progress.levelExperienceTarget} XP",
                    style = MaterialTheme.typography.labelMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
            LinearProgressIndicator(
                progress = { progress.levelProgressPercent },
                modifier = Modifier.fillMaxWidth()
            )
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                ResearchStat(
                    value = formatDuration(progress.creditedActiveMs),
                    label = "计分阅读",
                    modifier = Modifier.weight(1f)
                )
                ResearchStat(
                    value = progress.researchedContentCount.toString(),
                    label = "已研读",
                    modifier = Modifier.weight(1f)
                )
                ResearchStat(
                    value = favoriteCount.toString(),
                    label = "收藏",
                    modifier = Modifier.weight(1f)
                )
                ResearchStat(
                    value = historyCount.toString(),
                    label = "记录",
                    modifier = Modifier.weight(1f)
                )
            }
        }
    }
}

@Composable
private fun ResearchStat(
    value: String,
    label: String,
    modifier: Modifier = Modifier
) {
    Column(
        modifier = modifier,
        verticalArrangement = Arrangement.spacedBy(4.dp)
    ) {
        Text(value, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold)
        Text(label, style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}

@Composable
private fun ReadingHistoryRow(
    entry: ReadingHistoryEntry,
    onOpen: () -> Unit
) {
    val progress = readingProgressPercent(entry)
    ElevatedCard(onClick = onOpen, modifier = Modifier.fillMaxWidth()) {
        Column(
            modifier = Modifier.padding(14.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Column(Modifier.weight(1f)) {
                    Text(
                        entry.content.title,
                        style = MaterialTheme.typography.titleMedium,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis
                    )
                    Text(entry.content.id, style = MaterialTheme.typography.bodySmall)
                }
                Text(
                    if (progress > 0f) "${(progress * 100).toInt()}%" else "开始阅读",
                    style = MaterialTheme.typography.labelMedium,
                    color = MaterialTheme.colorScheme.primary
                )
            }
            LinearProgressIndicator(
                progress = { progress },
                modifier = Modifier.fillMaxWidth()
            )
            Text(
                "${formatDuration(entry.activeMs)} · ${formatLastReadAt(entry.lastReadAt)}",
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
        }
    }
}

private fun formatDuration(activeMs: Long): String {
    val minutes = (activeMs / 60_000L).toInt()
    return when {
        minutes <= 0 && activeMs > 0L -> "不足 1 分钟"
        minutes < 60 -> "${minutes} 分钟"
        else -> "${minutes / 60} 小时 ${minutes % 60} 分钟"
    }
}

private fun formatLastReadAt(timestamp: Long): String {
    if (timestamp <= 0L) return "尚无时间记录"
    return DateFormat.getDateTimeInstance(
        DateFormat.SHORT,
        DateFormat.SHORT,
        Locale.getDefault()
    ).format(Date(timestamp))
}

private fun formatBytes(byteLength: Long): String =
    if (byteLength < 1024L * 1024L) {
        String.format(Locale.ROOT, "%.1f KB", byteLength / 1024.0)
    } else {
        String.format(Locale.ROOT, "%.1f MB", byteLength / (1024.0 * 1024.0))
    }

private fun openUrl(context: Context, url: String) {
    if (url.isBlank()) return
    val intent = Intent(Intent.ACTION_VIEW, Uri.parse(url))
    context.startActivity(intent)
}
