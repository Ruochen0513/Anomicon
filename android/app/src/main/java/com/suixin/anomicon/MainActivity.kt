package com.suixin.anomicon

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Bookmarks
import androidx.compose.material.icons.outlined.Explore
import androidx.compose.material.icons.outlined.Inventory2
import androidx.compose.material.icons.outlined.MenuBook
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import com.suixin.anomicon.ui.theme.AnomiconTheme

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        setContent {
            AnomiconTheme {
                AnomiconApp()
            }
        }
    }
}

private enum class HomeTab(val title: String, val icon: ImageVector) {
    Explore("探索", Icons.Outlined.Explore),
    Catalog("图鉴", Icons.Outlined.Inventory2),
    Stories("故事", Icons.Outlined.MenuBook),
    Terminal("终端", Icons.Outlined.Bookmarks)
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun AnomiconApp() {
    var selectedTab by remember { mutableStateOf(HomeTab.Explore) }

    Scaffold(
        topBar = {
            TopAppBar(title = { Text(selectedTab.title) })
        },
        bottomBar = {
            NavigationBar {
                HomeTab.entries.forEach { tab ->
                    NavigationBarItem(
                        selected = selectedTab == tab,
                        onClick = { selectedTab = tab },
                        icon = { Icon(tab.icon, contentDescription = tab.title) },
                        label = { Text(tab.title) }
                    )
                }
            }
        }
    ) { contentPadding ->
        Box(
            modifier = Modifier
                .fillMaxSize()
                .padding(contentPadding)
        ) {
            Text(
                text = "Anomicon Android migration baseline",
                style = MaterialTheme.typography.bodyLarge
            )
        }
    }
}
