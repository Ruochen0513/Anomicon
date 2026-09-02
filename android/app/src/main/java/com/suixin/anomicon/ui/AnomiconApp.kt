package com.suixin.anomicon.ui

import android.annotation.SuppressLint
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.view.View
import android.webkit.WebView
import android.webkit.WebViewClient
import androidx.activity.compose.BackHandler
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.clickable
import androidx.compose.foundation.isSystemInDarkTheme
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
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import com.suixin.anomicon.core.data.AndroidLocalStore
import com.suixin.anomicon.core.data.AnomiconRepository
import com.suixin.anomicon.core.data.SeedData
import com.suixin.anomicon.core.model.AppSettings
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
import com.suixin.anomicon.core.model.ScpSeriesDescriptors
import com.suixin.anomicon.core.model.TaleEntry
import com.suixin.anomicon.core.model.ThemeMode
import com.suixin.anomicon.core.model.articleUrlOf
import com.suixin.anomicon.ui.theme.AnomiconTheme
import kotlinx.coroutines.launch
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

    val openContent: (ContentRef) -> Unit = { content ->
        library = localStore.recordRead(content)
        activeContent = content
    }
    val toggleFavorite: (ContentRef) -> Unit = { content ->
        library = localStore.toggleFavorite(content)
    }
    val saveSettings: (AppSettings) -> Unit = { next ->
        val normalized = next.normalized()
        localStore.saveSettings(normalized)
        settings = normalized
    }

    AnomiconTheme(darkTheme = darkTheme) {
        when {
            activeArchive != null -> ArchiveDetailScreen(
                asset = activeArchive!!,
                onBack = { activeArchive = null },
                onOpenArticle = { openContent(activeArchive!!.contentRef) }
            )
            activeContent != null -> ArticleScreen(
                content = activeContent!!,
                settings = settings,
                favorite = library.favorites.any { it.key == activeContent!!.key },
                onBack = { activeContent = null },
                onToggleFavorite = { toggleFavorite(activeContent!!) },
                onOpenArchive = { asset -> activeArchive = asset }
            )
            showSettings -> SettingsScreen(
                settings = settings,
                onBack = { showSettings = false },
                onSettingsChange = saveSettings
            )
            showArchiveGallery -> ArchiveGalleryScreen(
                onBack = { showArchiveGallery = false },
                onOpenAsset = { asset -> activeArchive = asset },
                onOpenArticle = openContent
            )
            else -> HomeScaffold(
                repository = repository,
                selectedTab = selectedTab,
                library = library,
                onSelectTab = { selectedTab = it },
                onOpenSettings = { showSettings = true },
                onOpenArchiveGallery = { showArchiveGallery = true },
                onOpenContent = openContent,
                onToggleFavorite = toggleFavorite
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
    onToggleFavorite: (ContentRef) -> Unit
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
            HomeTab.Catalog -> CatalogScreen(repository, padding, onOpenContent)
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
    onOpenContent: (ContentRef) -> Unit
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
                    onClick = { selectedSeriesId = series.id },
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
    LazyColumn(
        modifier = Modifier
            .fillMaxSize()
            .padding(padding),
        contentPadding = PaddingValues(16.dp),
        verticalArrangement = Arrangement.spacedBy(14.dp)
    ) {
        item {
            ElevatedCard(modifier = Modifier.fillMaxWidth()) {
                Column(Modifier.padding(18.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text("研究档案", style = MaterialTheme.typography.headlineSmall, fontWeight = FontWeight.Bold)
                    Text(
                        "收藏 ${library.favorites.size} 项 · 阅读记录 ${library.history.size} 条",
                        style = MaterialTheme.typography.bodyLarge
                    )
                    Text(
                        rankLabel(library.history.size, library.favorites.size),
                        style = MaterialTheme.typography.titleMedium,
                        color = MaterialTheme.colorScheme.primary
                    )
                }
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
        item { SectionHeader(title = "最近阅读", subtitle = "打开文章时自动记录。") }
        if (library.history.isEmpty()) {
            item { EmptyState("暂无阅读记录。") }
        } else {
            items(library.history.take(30)) { entry ->
                ContentRefRow(content = entry.content, onOpen = { onOpenContent(entry.content) })
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun ArticleScreen(
    content: ContentRef,
    settings: AppSettings,
    favorite: Boolean,
    onBack: () -> Unit,
    onToggleFavorite: () -> Unit,
    onOpenArchive: (ArchiveAsset) -> Unit
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
        ArticleWebView(
            url = articleUrlOf(content.id),
            settings = settings,
            modifier = Modifier
                .fillMaxSize()
                .padding(padding)
        )
    }
}

@SuppressLint("SetJavaScriptEnabled")
@Composable
private fun ArticleWebView(
    url: String,
    settings: AppSettings,
    modifier: Modifier = Modifier
) {
    AndroidView(
        modifier = modifier,
        factory = { context ->
            WebView(context).apply {
                webViewClient = WebViewClient()
                this.settings.javaScriptEnabled = true
                this.settings.domStorageEnabled = true
                this.settings.loadWithOverviewMode = true
                this.settings.useWideViewPort = true
                this.settings.textZoom = (settings.fontSize / ReadingSettingsRange.DefaultFontSize * 100f).toInt()
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    importantForAutofill = View.IMPORTANT_FOR_AUTOFILL_NO
                }
                loadUrl(url)
            }
        },
        update = { webView ->
            webView.settings.textZoom = (settings.fontSize / ReadingSettingsRange.DefaultFontSize * 100f).toInt()
            if (webView.url != url) {
                webView.loadUrl(url)
            }
        }
    )
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun SettingsScreen(
    settings: AppSettings,
    onBack: () -> Unit,
    onSettingsChange: (AppSettings) -> Unit
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
                        onClick = { onSettingsChange(settings.copy(themeMode = mode)) },
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
                onCheckedChange = { onSettingsChange(settings.copy(hapticEnabled = it)) }
            )
            SettingSwitch(
                title = "沉浸材质",
                subtitle = "Android MVP 先记录设置，后续可映射到动态色/模糊背景。",
                checked = settings.immersiveMaterialEnabled,
                onCheckedChange = { onSettingsChange(settings.copy(immersiveMaterialEnabled = it)) }
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
    onBack: () -> Unit,
    onOpenAsset: (ArchiveAsset) -> Unit,
    onOpenArticle: (ContentRef) -> Unit
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
                    FilterChip(selected = filter == null, onClick = { filter = null }, label = { Text("全部") })
                    FilterChip(selected = filter == ArchiveAssetDelivery.Bundled, onClick = { filter = ArchiveAssetDelivery.Bundled }, label = { Text("已内置") })
                    FilterChip(selected = filter == ArchiveAssetDelivery.OnDemand, onClick = { filter = ArchiveAssetDelivery.OnDemand }, label = { Text("按需") })
                }
            }
            items(visible) { asset ->
                ArchiveAssetCard(asset = asset, onOpenAsset = onOpenAsset, onOpenArticle = onOpenArticle)
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun ArchiveDetailScreen(
    asset: ArchiveAsset,
    onBack: () -> Unit,
    onOpenArticle: () -> Unit
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
                Surface(
                    modifier = Modifier
                        .fillMaxWidth()
                        .height(220.dp),
                    color = MaterialTheme.colorScheme.surfaceVariant,
                    shape = RoundedCornerShape(8.dp),
                    border = BorderStroke(1.dp, MaterialTheme.colorScheme.outlineVariant)
                ) {
                    Box(contentAlignment = Alignment.Center) {
                        Column(horizontalAlignment = Alignment.CenterHorizontally) {
                            Icon(Icons.Outlined.ViewInAr, contentDescription = null, modifier = Modifier.size(48.dp))
                            Spacer(Modifier.height(8.dp))
                            Text(
                                if (asset.delivery == ArchiveAssetDelivery.Bundled) {
                                    "GLB 已作为 Android assets 打包"
                                } else {
                                    "按需下载资源已保留来源信息"
                                }
                            )
                        }
                    }
                }
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
                    Button(onClick = onOpenArticle) {
                        Text("打开条目")
                    }
                    OutlinedButton(onClick = { openUrl(context, asset.sourceUrl) }) {
                        Icon(Icons.AutoMirrored.Outlined.OpenInNew, contentDescription = null)
                        Spacer(Modifier.width(6.dp))
                        Text("来源")
                    }
                }
            }
            if (asset.delivery == ArchiveAssetDelivery.OnDemand && asset.downloadUrl.isNotBlank()) {
                item {
                    AssistChip(
                        onClick = { openUrl(context, asset.downloadUrl) },
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
                Text(content.id, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
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
