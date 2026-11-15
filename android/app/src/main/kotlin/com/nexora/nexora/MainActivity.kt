package com.nexora.nexora

import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    // CI smoke test: `am start ... --es route /nx-home` -> Flutter initial route (test hooks in lib/app/shell.dart)
    override fun getInitialRoute(): String? = intent?.getStringExtra("route") ?: super.getInitialRoute()
}
