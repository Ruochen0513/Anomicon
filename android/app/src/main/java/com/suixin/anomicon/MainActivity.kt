package com.suixin.anomicon

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import com.suixin.anomicon.core.data.AndroidLocalStore
import com.suixin.anomicon.core.data.AnomiconRepository
import com.suixin.anomicon.ui.AnomiconApp

class MainActivity : ComponentActivity() {
    private val repository by lazy { AnomiconRepository() }
    private val localStore by lazy { AndroidLocalStore(this) }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        setContent {
            AnomiconApp(repository = repository, localStore = localStore)
        }
    }
}
