package com.experiment.shorts_blocker

import android.accessibilityservice.AccessibilityService
import android.content.Context
import android.util.Log
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo

class ShortsBlockerService : AccessibilityService() {

    private val tag = "ShortsBlockerService"
    private val prefsName = "ShortsBlockerPrefs"
    private val shortsCountKey = "shorts_count"
    private val shortsLimitKey = "shorts_limit"
    private val lastIncrementKey = "last_increment"
    private val ruleStore = RuleStore()
    private val browserPackages = setOf(
        "com.android.chrome",
        "com.sec.android.app.sbrowser",
        "org.mozilla.firefox",
        "com.microsoft.emmx",
        "com.brave.browser",
        "com.opera.browser",
        "com.opera.mini.native",
        "com.vivaldi.browser"
    )
    private val genericShortSignals = listOf(
        "youtube.com/shorts",
        "m.youtube.com/shorts",
        "/shorts/",
        " shorts ",
        "shorts",
        "reels",
        "reel",
        "short videos",
        "watch short",
        "explore short videos",
        "ytm shorts",
        "youtube shorts"
    )
    private val xSignals = listOf(
        "x.com",
        "twitter.com",
        "x/twitter",
        "immersive media viewer",
        "/i/status/",
        "/status/",
        "/video/",
        "video player",
        "watch full video",
        "for you",
        "following"
    )
    private val browserShortUrlSignals = listOf(
        "youtube.com/shorts",
        "m.youtube.com/shorts",
        "instagram.com/reel",
        "instagram.com/reels",
        "facebook.com/reel",
        "facebook.com/reels",
        "x.com/i/status",
        "twitter.com/i/status",
        "x.com/",
        "twitter.com/"
    )

    private var lastTrackedTime: Long = 0
    private var activePackageName: String? = null

    override fun onAccessibilityEvent(event: AccessibilityEvent) {
        val packageName = event.packageName?.toString() ?: return
        val currentTime = System.currentTimeMillis()

        updateTrackedUsage(packageName, currentTime)

        if (
            event.eventType == AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED ||
            event.eventType == AccessibilityEvent.TYPE_WINDOW_CONTENT_CHANGED ||
            event.eventType == AccessibilityEvent.TYPE_VIEW_SCROLLED ||
            event.eventType == AccessibilityEvent.TYPE_VIEW_TEXT_CHANGED
        ) {
            val rule = ruleStore.getRuleForPackage(this, packageName) ?: return
            if (!rule.blockShorts) return

            val rootNode = rootInActiveWindow ?: return
            if (containsShortsSignal(packageName, event, rootNode)) {
                incrementAndMaybeBlock()
            }
        }
    }

    override fun onInterrupt() {}

    override fun onServiceConnected() {
        super.onServiceConnected()
        lastTrackedTime = System.currentTimeMillis()
    }

    private fun updateTrackedUsage(packageName: String, currentTime: Long) {
        val previousPackage = activePackageName
        val elapsedSeconds =
            if (lastTrackedTime == 0L) 0 else ((currentTime - lastTrackedTime) / 1000L).toInt()

        if (!previousPackage.isNullOrBlank() && elapsedSeconds > 0) {
            val previousRule = ruleStore.getRuleForPackage(this, previousPackage)
            val category = previousRule?.category ?: "neutral"
            ruleStore.addUsage(this, previousPackage, category, elapsedSeconds.coerceAtMost(15))
        }

        activePackageName = packageName
        lastTrackedTime = currentTime
    }

    private fun containsShortsSignal(
        packageName: String,
        event: AccessibilityEvent,
        rootNode: AccessibilityNodeInfo
    ): Boolean {
        val eventSignals = buildEventSignals(event)
        if (eventSignals.any { containsBlockedKeyword(packageName, it) }) {
            return true
        }

        val queue = ArrayDeque<AccessibilityNodeInfo>()
        queue.add(rootNode)
        var scannedNodes = 0

        while (queue.isNotEmpty() && scannedNodes < 140) {
            val node = queue.removeFirst()
            scannedNodes += 1

            val candidateTexts = listOfNotNull(
                node.text?.toString(),
                node.contentDescription?.toString(),
                node.hintText?.toString(),
                node.viewIdResourceName,
                node.paneTitle?.toString(),
                node.tooltipText?.toString(),
                node.stateDescription?.toString(),
                node.containerTitle?.toString()
            )

            if (candidateTexts.any { containsBlockedKeyword(packageName, it) }) {
                return true
            }

            for (index in 0 until node.childCount) {
                val child = node.getChild(index) ?: continue
                queue.add(child)
            }
        }

        return false
    }

    private fun buildEventSignals(event: AccessibilityEvent): List<String> {
        return buildList {
            addAll(event.text.mapNotNull { it?.toString() })
            add(event.contentDescription?.toString())
            add(event.className?.toString())
            add(event.packageName?.toString())
            add(event.beforeText?.toString())
        }.filterNotNull()
    }

    private fun containsBlockedKeyword(packageName: String, value: String): Boolean {
        val normalized = value.lowercase()
        if (genericShortSignals.any { normalized.contains(it) }) {
            return true
        }

        if (packageName == "com.twitter.android") {
            return containsXShortVideoSignal(normalized)
        }

        if (packageName in browserPackages) {
            return containsBrowserShortSignal(normalized)
        }

        return false
    }

    private fun containsBrowserShortSignal(normalized: String): Boolean {
        if (browserShortUrlSignals.any { normalized.contains(it) }) {
            return true
        }

        val mentionsYouTubeShorts =
            normalized.contains("youtube") && (
                normalized.contains("shorts") ||
                    normalized.contains("/shorts/")
                )
        val mentionsInstagramReels =
            normalized.contains("instagram") && normalized.contains("reel")
        val mentionsFacebookReels =
            normalized.contains("facebook") && normalized.contains("reel")
        val mentionsXVideoStatus =
            (normalized.contains("x.com") || normalized.contains("twitter.com")) &&
                containsXShortVideoSignal(normalized)

        return mentionsYouTubeShorts ||
            mentionsInstagramReels ||
            mentionsFacebookReels ||
            mentionsXVideoStatus
    }

    private fun containsXShortVideoSignal(normalized: String): Boolean {
        val hasXHost = normalized.contains("x.com") || normalized.contains("twitter.com")
        val hasXStatusPath = normalized.contains("/i/status/") || normalized.contains("/status/")
        val hasVideoLanguage =
            normalized.contains("video") ||
                normalized.contains("media viewer") ||
                normalized.contains("watch full video") ||
                normalized.contains("immersive")

        return xSignals.any { normalized.contains(it) } &&
            ((hasXHost && hasVideoLanguage) || (hasXStatusPath && hasVideoLanguage))
    }

    private fun incrementAndMaybeBlock() {
        val prefs = getSharedPreferences(prefsName, Context.MODE_PRIVATE)
        val currentCount = prefs.getInt(shortsCountKey, 0)
        val limit = prefs.getInt(shortsLimitKey, 3)
        val now = System.currentTimeMillis()
        val lastIncrement = prefs.getLong(lastIncrementKey, 0)

        if (now - lastIncrement < 8000) {
            return
        }

        val newCount = currentCount + 1
        prefs.edit()
            .putInt(shortsCountKey, newCount)
            .putLong(lastIncrementKey, now)
            .apply()

        if (newCount >= limit) {
            Log.d(tag, "Shorts limit reached, triggering back action.")
            performGlobalAction(GLOBAL_ACTION_BACK)
        }
    }
}
