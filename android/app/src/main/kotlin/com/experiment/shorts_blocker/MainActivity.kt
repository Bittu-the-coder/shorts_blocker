package com.experiment.shorts_blocker

import android.accessibilityservice.AccessibilityServiceInfo
import android.content.Context
import android.content.Intent
import android.provider.Settings
import android.view.accessibility.AccessibilityManager
import androidx.annotation.NonNull
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import org.json.JSONArray
import org.json.JSONObject

class MainActivity : FlutterActivity() {
    private val channel = "com.experiment.shorts_blocker/service"
    private val prefsName = "ShortsBlockerPrefs"
    private val ruleStore = RuleStore()

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channel).setMethodCallHandler {
            call, result ->
            val prefs = getSharedPreferences(prefsName, Context.MODE_PRIVATE)

            when (call.method) {
                "getShortsCount" -> result.success(prefs.getInt("shorts_count", 0))
                "getTimeWaste" -> result.success(prefs.getInt("waste_seconds", 0))
                "isProtectionEnabled" -> result.success(isAccessibilityServiceEnabled())
                "getRules" -> {
                    result.success(ruleStore.rulesToJson(ruleStore.loadRules(this)))
                }
                "saveRules" -> {
                    val rulesJson = call.argument<String>("rulesJson").orEmpty()
                    ruleStore.saveRules(this, rulesJson)
                    result.success(true)
                }
                "getDashboardData" -> {
                    result.success(ruleStore.buildDashboardJson(this, isAccessibilityServiceEnabled()))
                }
                "resetStats" -> {
                    ruleStore.resetStats(this)
                    result.success(true)
                }
                "openAccessibilitySettings" -> {
                    val intent = Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS)
                    intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    startActivity(intent)
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun isAccessibilityServiceEnabled(): Boolean {
        val manager = getSystemService(Context.ACCESSIBILITY_SERVICE) as AccessibilityManager
        val enabledServices = manager.getEnabledAccessibilityServiceList(
            AccessibilityServiceInfo.FEEDBACK_ALL_MASK
        )

        return enabledServices.any { service ->
            service.resolveInfo.serviceInfo.packageName == packageName &&
                service.resolveInfo.serviceInfo.name == "$packageName.ShortsBlockerService"
        }
    }
}

data class AppRule(
    val packageName: String,
    val label: String,
    val category: String,
    val blockShorts: Boolean,
    val isPreset: Boolean = false
)

class RuleStore {
    private val prefsName = "ShortsBlockerPrefs"
    private val rulesKey = "rules_json"
    private val shortsCountKey = "shorts_count"
    private val shortsLimitKey = "shorts_limit"
    private val wasteSecondsKey = "waste_seconds"
    private val productiveSecondsKey = "productive_seconds"
    private val neutralSecondsKey = "neutral_seconds"
    private val appUsageKey = "app_usage_json"

    fun loadRules(context: Context): List<AppRule> {
        val prefs = context.getSharedPreferences(prefsName, Context.MODE_PRIVATE)
        val rawJson = prefs.getString(rulesKey, null)
        val parsed = parseRules(rawJson)

        if (parsed.isNotEmpty()) {
            return parsed
        }

        val defaults = defaultRules()
        saveRules(context, rulesToJson(defaults))
        return defaults
    }

    fun saveRules(context: Context, rulesJson: String) {
        val rules = parseRules(rulesJson)
        val normalized = if (rules.isEmpty()) defaultRules() else rules
        context.getSharedPreferences(prefsName, Context.MODE_PRIVATE)
            .edit()
            .putString(rulesKey, rulesToJson(normalized))
            .apply()
    }

    fun rulesToJson(rules: List<AppRule>): String {
        val array = JSONArray()
        rules.forEach { rule ->
            array.put(
                JSONObject().apply {
                    put("packageName", rule.packageName)
                    put("label", rule.label)
                    put("category", rule.category)
                    put("blockShorts", rule.blockShorts)
                    put("isPreset", rule.isPreset)
                }
            )
        }
        return array.toString()
    }

    fun buildDashboardJson(context: Context, isProtectionEnabled: Boolean): String {
        val prefs = context.getSharedPreferences(prefsName, Context.MODE_PRIVATE)
        val rulesByPackage = loadRules(context).associateBy { it.packageName.lowercase() }
        val appUsage = parseUsageMap(prefs.getString(appUsageKey, null))

        val usageArray = JSONArray()
        appUsage.entries
            .sortedByDescending { it.value }
            .forEach { entry ->
                val rule = rulesByPackage[entry.key.lowercase()]
                usageArray.put(
                    JSONObject().apply {
                        put("packageName", entry.key)
                        put("label", rule?.label ?: entry.key)
                        put("category", rule?.category ?: "neutral")
                        put("seconds", entry.value)
                    }
                )
            }

        return JSONObject().apply {
            put("shortsCount", prefs.getInt(shortsCountKey, 0))
            put("shortsLimit", prefs.getInt(shortsLimitKey, 3))
            put("wasteSeconds", prefs.getInt(wasteSecondsKey, 0))
            put("productiveSeconds", prefs.getInt(productiveSecondsKey, 0))
            put("neutralSeconds", prefs.getInt(neutralSecondsKey, 0))
            put("isProtectionEnabled", isProtectionEnabled)
            put("appUsage", usageArray)
        }.toString()
    }

    fun resetStats(context: Context) {
        context.getSharedPreferences(prefsName, Context.MODE_PRIVATE)
            .edit()
            .putInt(shortsCountKey, 0)
            .putInt(wasteSecondsKey, 0)
            .putInt(productiveSecondsKey, 0)
            .putInt(neutralSecondsKey, 0)
            .putLong("last_increment", 0)
            .putString(appUsageKey, JSONObject().toString())
            .apply()
    }

    fun getRuleForPackage(context: Context, packageName: String): AppRule? {
        return loadRules(context).firstOrNull {
            it.packageName.equals(packageName, ignoreCase = true)
        }
    }

    fun addUsage(context: Context, packageName: String, category: String, seconds: Int) {
        if (seconds <= 0) return

        val prefs = context.getSharedPreferences(prefsName, Context.MODE_PRIVATE)
        val usageMap = parseUsageMap(prefs.getString(appUsageKey, null))
        usageMap[packageName] = (usageMap[packageName] ?: 0) + seconds

        val wasteSeconds = prefs.getInt(wasteSecondsKey, 0)
        val productiveSeconds = prefs.getInt(productiveSecondsKey, 0)
        val neutralSeconds = prefs.getInt(neutralSecondsKey, 0)

        val editor = prefs.edit().putString(appUsageKey, usageMapToJson(usageMap))
        when (category) {
            "waste" -> editor.putInt(wasteSecondsKey, wasteSeconds + seconds)
            "productive" -> editor.putInt(productiveSecondsKey, productiveSeconds + seconds)
            else -> editor.putInt(neutralSecondsKey, neutralSeconds + seconds)
        }
        editor.apply()
    }

    private fun parseRules(rawJson: String?): List<AppRule> {
        if (rawJson.isNullOrBlank()) {
            return emptyList()
        }

        return try {
            val array = JSONArray(rawJson)
            buildList {
                for (index in 0 until array.length()) {
                    val item = array.optJSONObject(index) ?: continue
                    val packageName = item.optString("packageName").trim()
                    val label = item.optString("label").trim()
                    if (packageName.isBlank() || label.isBlank()) continue

                    add(
                        AppRule(
                            packageName = packageName,
                            label = label,
                            category = item.optString("category", "neutral"),
                            blockShorts = item.optBoolean("blockShorts", false),
                            isPreset = item.optBoolean("isPreset", false)
                        )
                    )
                }
            }
        } catch (_: Exception) {
            emptyList()
        }
    }

    private fun parseUsageMap(rawJson: String?): MutableMap<String, Int> {
        val result = mutableMapOf<String, Int>()
        if (rawJson.isNullOrBlank()) return result

        return try {
            val json = JSONObject(rawJson)
            json.keys().forEach { key ->
                result[key] = json.optInt(key, 0)
            }
            result
        } catch (_: Exception) {
            mutableMapOf()
        }
    }

    private fun usageMapToJson(usageMap: Map<String, Int>): String {
        val json = JSONObject()
        usageMap.forEach { (pkg, seconds) ->
            json.put(pkg, seconds)
        }
        return json.toString()
    }

    private fun defaultRules(): List<AppRule> {
        return listOf(
            AppRule("com.google.android.youtube", "YouTube", "waste", true, true),
            AppRule("com.android.chrome", "Chrome", "neutral", true, true),
            AppRule("com.sec.android.app.sbrowser", "Samsung Internet", "neutral", true, true),
            AppRule("org.mozilla.firefox", "Firefox", "neutral", true, true),
            AppRule("com.microsoft.emmx", "Edge", "neutral", true, true),
            AppRule("com.brave.browser", "Brave", "neutral", true, true),
            AppRule("com.opera.browser", "Opera", "neutral", true, true),
            AppRule("com.opera.mini.native", "Opera Mini", "neutral", true, true),
            AppRule("com.vivaldi.browser", "Vivaldi", "neutral", true, true),
            AppRule("com.instagram.android", "Instagram", "waste", true, true),
            AppRule("com.facebook.katana", "Facebook", "waste", true, true),
            AppRule("com.twitter.android", "X", "waste", true, true),
            AppRule("org.coursera.android", "Coursera", "productive", false, true),
            AppRule("com.google.android.apps.classroom", "Google Classroom", "productive", false, true)
        )
    }
}
