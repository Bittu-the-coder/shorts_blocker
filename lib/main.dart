import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

void main() {
  runApp(const ShortsBlockerApp());
}

class ShortsBlockerApp extends StatelessWidget {
  const ShortsBlockerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Focus Guard',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1F4D3F),
          brightness: Brightness.light,
        ),
        scaffoldBackgroundColor: const Color(0xFFF6F1E8),
        useMaterial3: true,
      ),
      home: const HomeScreen(),
    );
  }
}

enum AppCategory { waste, productive, neutral }

extension AppCategoryX on AppCategory {
  String get value => switch (this) {
    AppCategory.waste => 'waste',
    AppCategory.productive => 'productive',
    AppCategory.neutral => 'neutral',
  };

  String get label => switch (this) {
    AppCategory.waste => 'Time waste',
    AppCategory.productive => 'Learning/Productive',
    AppCategory.neutral => 'Neutral',
  };

  static AppCategory fromValue(String value) {
    return AppCategory.values.firstWhere(
      (category) => category.value == value,
      orElse: () => AppCategory.neutral,
    );
  }
}

class AppRule {
  const AppRule({
    required this.packageName,
    required this.label,
    required this.category,
    required this.blockShorts,
    this.isPreset = false,
  });

  final String packageName;
  final String label;
  final AppCategory category;
  final bool blockShorts;
  final bool isPreset;

  AppRule copyWith({
    String? packageName,
    String? label,
    AppCategory? category,
    bool? blockShorts,
    bool? isPreset,
  }) {
    return AppRule(
      packageName: packageName ?? this.packageName,
      label: label ?? this.label,
      category: category ?? this.category,
      blockShorts: blockShorts ?? this.blockShorts,
      isPreset: isPreset ?? this.isPreset,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'packageName': packageName,
      'label': label,
      'category': category.value,
      'blockShorts': blockShorts,
      'isPreset': isPreset,
    };
  }

  static AppRule fromJson(Map<String, dynamic> json) {
    return AppRule(
      packageName: (json['packageName'] as String? ?? '').trim(),
      label: (json['label'] as String? ?? '').trim(),
      category: AppCategoryX.fromValue(
        json['category'] as String? ?? 'neutral',
      ),
      blockShorts: json['blockShorts'] as bool? ?? false,
      isPreset: json['isPreset'] as bool? ?? false,
    );
  }
}

class DashboardData {
  const DashboardData({
    required this.shortsCount,
    required this.shortsLimit,
    required this.wasteSeconds,
    required this.productiveSeconds,
    required this.neutralSeconds,
    required this.isProtectionEnabled,
    required this.appUsage,
  });

  final int shortsCount;
  final int shortsLimit;
  final int wasteSeconds;
  final int productiveSeconds;
  final int neutralSeconds;
  final bool isProtectionEnabled;
  final List<AppUsageData> appUsage;

  static DashboardData fromJson(Map<String, dynamic> json) {
    final usageList = (json['appUsage'] as List<dynamic>? ?? [])
        .whereType<Map>()
        .map(
          (item) => AppUsageData.fromJson(
            Map<String, dynamic>.from(item.cast<String, dynamic>()),
          ),
        )
        .toList();

    return DashboardData(
      shortsCount: json['shortsCount'] as int? ?? 0,
      shortsLimit: json['shortsLimit'] as int? ?? 3,
      wasteSeconds: json['wasteSeconds'] as int? ?? 0,
      productiveSeconds: json['productiveSeconds'] as int? ?? 0,
      neutralSeconds: json['neutralSeconds'] as int? ?? 0,
      isProtectionEnabled: json['isProtectionEnabled'] as bool? ?? false,
      appUsage: usageList,
    );
  }
}

class AppUsageData {
  const AppUsageData({
    required this.packageName,
    required this.label,
    required this.category,
    required this.seconds,
  });

  final String packageName;
  final String label;
  final AppCategory category;
  final int seconds;

  static AppUsageData fromJson(Map<String, dynamic> json) {
    return AppUsageData(
      packageName: json['packageName'] as String? ?? '',
      label: json['label'] as String? ?? '',
      category: AppCategoryX.fromValue(
        json['category'] as String? ?? 'neutral',
      ),
      seconds: json['seconds'] as int? ?? 0,
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  static const platform = MethodChannel(
    'com.experiment.shorts_blocker/service',
  );

  final TextEditingController _packageController = TextEditingController();
  final TextEditingController _labelController = TextEditingController();

  DashboardData _dashboard = const DashboardData(
    shortsCount: 0,
    shortsLimit: 3,
    wasteSeconds: 0,
    productiveSeconds: 0,
    neutralSeconds: 0,
    isProtectionEnabled: false,
    appUsage: [],
  );
  List<AppRule> _rules = const [];
  AppCategory _newRuleCategory = AppCategory.neutral;
  bool _newRuleBlocksShorts = false;
  bool _isLoading = true;
  bool _isSavingRules = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _loadData();
    _timer = Timer.periodic(const Duration(seconds: 4), (_) => _refresh());
  }

  @override
  void dispose() {
    _timer?.cancel();
    _packageController.dispose();
    _labelController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    try {
      final results = await Future.wait<dynamic>([
        platform.invokeMethod<String>('getDashboardData'),
        platform.invokeMethod<String>('getRules'),
      ]);

      final dashboardJson =
          jsonDecode(results[0] as String? ?? '{}') as Map<String, dynamic>;
      final rulesJson =
          jsonDecode(results[1] as String? ?? '[]') as List<dynamic>;

      final parsedRules =
          rulesJson
              .whereType<Map>()
              .map(
                (item) => AppRule.fromJson(
                  Map<String, dynamic>.from(item.cast<String, dynamic>()),
                ),
              )
              .toList()
            ..sort(
              (a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()),
            );

      if (!mounted) return;
      setState(() {
        _dashboard = DashboardData.fromJson(dashboardJson);
        _rules = parsedRules;
        _isLoading = false;
      });
    } on PlatformException catch (error) {
      debugPrint("Failed to load data: ${error.message}");
      if (!mounted) return;
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _refresh() async {
    await _loadData();
  }

  Future<void> _saveRules() async {
    setState(() {
      _isSavingRules = true;
    });

    try {
      final payload = jsonEncode(_rules.map((rule) => rule.toJson()).toList());
      await platform.invokeMethod('saveRules', {'rulesJson': payload});
      await _refresh();
    } on PlatformException catch (error) {
      debugPrint("Failed to save rules: ${error.message}");
    } finally {
      if (mounted) {
        setState(() {
          _isSavingRules = false;
        });
      }
    }
  }

  Future<void> _resetStats() async {
    try {
      await platform.invokeMethod('resetStats');
      await _refresh();
    } on PlatformException catch (error) {
      debugPrint("Failed to reset stats: ${error.message}");
    }
  }

  Future<void> _openSettings() async {
    try {
      await platform.invokeMethod('openAccessibilitySettings');
    } on PlatformException catch (error) {
      debugPrint("Failed to open settings: ${error.message}");
    }
  }

  void _addRule() {
    final packageName = _packageController.text.trim();
    final label = _labelController.text.trim();

    if (packageName.isEmpty || label.isEmpty) {
      return;
    }

    final existingIndex = _rules.indexWhere(
      (rule) => rule.packageName.toLowerCase() == packageName.toLowerCase(),
    );

    final newRule = AppRule(
      packageName: packageName,
      label: label,
      category: _newRuleCategory,
      blockShorts: _newRuleBlocksShorts,
    );

    setState(() {
      if (existingIndex >= 0) {
        _rules = List<AppRule>.from(_rules)..[existingIndex] = newRule;
      } else {
        _rules = List<AppRule>.from(_rules)..add(newRule);
      }
      _rules.sort(
        (a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()),
      );
      _packageController.clear();
      _labelController.clear();
      _newRuleCategory = AppCategory.neutral;
      _newRuleBlocksShorts = false;
    });

    _saveRules();
  }

  void _updateRule(AppRule updatedRule) {
    setState(() {
      _rules = _rules
          .map(
            (rule) => rule.packageName == updatedRule.packageName
                ? updatedRule
                : rule,
          )
          .toList();
    });
    _saveRules();
  }

  void _deleteRule(AppRule rule) {
    setState(() {
      _rules = _rules
          .where((item) => item.packageName != rule.packageName)
          .toList();
    });
    _saveRules();
  }

  String _formatDuration(int totalSeconds) {
    final hours = totalSeconds ~/ 3600;
    final minutes = (totalSeconds % 3600) ~/ 60;
    final seconds = totalSeconds % 60;

    if (hours > 0) return '${hours}h ${minutes}m';
    if (minutes > 0) return '${minutes}m ${seconds}s';
    return '${seconds}s';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final progress = (_dashboard.shortsCount / _dashboard.shortsLimit)
        .clamp(0, 1)
        .toDouble();
    final limitReached = _dashboard.shortsCount >= _dashboard.shortsLimit;

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Focus Guard'),
          centerTitle: true,
          backgroundColor: Colors.transparent,
          elevation: 0,
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Dashboard'),
              Tab(text: 'Rules'),
            ],
          ),
        ),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : TabBarView(
                children: [
                  RefreshIndicator(
                    onRefresh: _refresh,
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
                      children: [
                        _buildHeroCard(theme, progress, limitReached),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              child: _buildMetricCard(
                                context,
                                title: 'Shorts blocked',
                                value: '${_dashboard.shortsCount}',
                                subtitle:
                                    'Daily limit: ${_dashboard.shortsLimit}',
                                icon: Icons.block_rounded,
                                accent: const Color(0xFFC84C09),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _buildMetricCard(
                                context,
                                title: 'Time waste',
                                value: _formatDuration(_dashboard.wasteSeconds),
                                subtitle: 'Tracked in waste apps',
                                icon: Icons.timelapse_rounded,
                                accent: const Color(0xFF8B1E3F),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: _buildMetricCard(
                                context,
                                title: 'Productive',
                                value: _formatDuration(
                                  _dashboard.productiveSeconds,
                                ),
                                subtitle: 'Learning and focused apps',
                                icon: Icons.school_rounded,
                                accent: const Color(0xFF0F766E),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _buildMetricCard(
                                context,
                                title: 'Neutral',
                                value: _formatDuration(
                                  _dashboard.neutralSeconds,
                                ),
                                subtitle: 'Other phone usage',
                                icon: Icons.phone_android_rounded,
                                accent: const Color(0xFF475569),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        _buildStatusCard(theme),
                        const SizedBox(height: 16),
                        _buildUsageBreakdownCard(theme),
                        const SizedBox(height: 16),
                        _buildActionCard(theme),
                        const SizedBox(height: 16),
                        _buildHowItWorksCard(theme),
                      ],
                    ),
                  ),
                  ListView(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
                    children: [
                      _buildRuleIntroCard(theme),
                      const SizedBox(height: 16),
                      _buildAddRuleCard(theme),
                      const SizedBox(height: 16),
                      _buildRuleListCard(theme),
                    ],
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildHeroCard(ThemeData theme, double progress, bool limitReached) {
    final headline = _dashboard.isProtectionEnabled
        ? 'Browser and app protection is active'
        : 'Turn on accessibility protection';
    final description = _dashboard.isProtectionEnabled
        ? 'Focus Guard watches Shorts and Reels inside apps and browsers, and it keeps tracking how your phone time is spent.'
        : 'Enable the accessibility service once so the app can detect Shorts pages, browser feeds, and classify your usage.';

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: const LinearGradient(
          colors: [Color(0xFF17322B), Color(0xFF28544A)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              _dashboard.isProtectionEnabled
                  ? 'ACTIVE SHIELD'
                  : 'SETUP REQUIRED',
              style: theme.textTheme.labelLarge?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.1,
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            headline,
            style: theme.textTheme.headlineMedium?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            description,
            style: theme.textTheme.bodyLarge?.copyWith(
              color: Colors.white.withValues(alpha: 0.88),
              height: 1.45,
            ),
          ),
          const SizedBox(height: 22),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 10,
              backgroundColor: Colors.white.withValues(alpha: 0.15),
              valueColor: AlwaysStoppedAnimation<Color>(
                limitReached
                    ? const Color(0xFFFFB38A)
                    : const Color(0xFFF2D06B),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            limitReached
                ? 'The Shorts limit is reached, so the service should push you back out of short-form feeds.'
                : '${_dashboard.shortsLimit - _dashboard.shortsCount} more Shorts detections before blocking kicks in.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: Colors.white.withValues(alpha: 0.9),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetricCard(
    BuildContext context, {
    required String title,
    required String value,
    required String subtitle,
    required IconData icon,
    required Color accent,
  }) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: accent.withValues(alpha: 0.15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 22,
            backgroundColor: accent.withValues(alpha: 0.12),
            child: Icon(icon, color: accent),
          ),
          const SizedBox(height: 16),
          Text(
            title,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: theme.textTheme.headlineSmall?.copyWith(
              color: accent,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            style: theme.textTheme.bodySmall?.copyWith(
              color: const Color(0xFF5D6B66),
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusCard(ThemeData theme) {
    final statusColor = _dashboard.isProtectionEnabled
        ? const Color(0xFF2E7D32)
        : const Color(0xFFB45309);
    final statusText = _dashboard.isProtectionEnabled
        ? 'Accessibility protection is enabled. Shorts detection can run in supported apps and browser views.'
        : 'Accessibility protection is still off, so tracking and Shorts blocking cannot run yet.';

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 14,
            height: 14,
            margin: const EdgeInsets.only(top: 4),
            decoration: BoxDecoration(
              color: statusColor,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Service status',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  statusText,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: const Color(0xFF42534D),
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUsageBreakdownCard(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Usage breakdown',
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 12),
          if (_dashboard.appUsage.isEmpty)
            Text(
              'No tracked app usage yet. Open a few apps after enabling accessibility protection.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: const Color(0xFF5D6B66),
              ),
            ),
          for (final app in _dashboard.appUsage.take(8)) ...[
            Row(
              children: [
                Expanded(
                  child: Text(
                    app.label,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Text(
                  app.category.label,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: const Color(0xFF5D6B66),
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  _formatDuration(app.seconds),
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
          ],
        ],
      ),
    );
  }

  Widget _buildActionCard(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFFE7DCC9),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Actions',
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Use the rules tab to decide which apps count as waste, productive, or neutral. Turn on Shorts blocking only where you want it.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: const Color(0xFF4B5563),
              height: 1.4,
            ),
          ),
          const SizedBox(height: 18),
          ElevatedButton.icon(
            onPressed: _openSettings,
            icon: const Icon(Icons.shield_outlined),
            label: Text(
              _dashboard.isProtectionEnabled
                  ? 'Open Accessibility Settings'
                  : 'Enable Protection',
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1F4D3F),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _resetStats,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Reset Today\'s Stats'),
          ),
        ],
      ),
    );
  }

  Widget _buildHowItWorksCard(ThemeData theme) {
    const steps = [
      'Create rules for the apps you care about. Mark them as time waste, productive, or neutral.',
      'Turn on Shorts blocking for apps and browsers where short-form feeds should be stopped.',
      'The service watches visible text, descriptions, and browser URLs like youtube.com/shorts or reels pages.',
      'Phone usage is counted by category so you can compare wasted time against learning time.',
    ];

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'How it works',
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 14),
          for (final step in steps) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.only(top: 6),
                  child: Icon(Icons.circle, size: 8, color: Color(0xFF1F4D3F)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    step,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: const Color(0xFF42534D),
                      height: 1.45,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
          ],
        ],
      ),
    );
  }

  Widget _buildRuleIntroCard(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF16302B),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Rule system',
            style: theme.textTheme.headlineSmall?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Each rule controls two things: how the app counts in your daily usage, and whether Shorts or Reels should be blocked there. Browser rules can block short-form pages too.',
            style: theme.textTheme.bodyLarge?.copyWith(
              color: Colors.white.withValues(alpha: 0.88),
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAddRuleCard(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Add or update a rule',
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _labelController,
            decoration: const InputDecoration(
              labelText: 'App label',
              hintText: 'Chrome, YouTube, Coursera',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _packageController,
            decoration: const InputDecoration(
              labelText: 'Package name',
              hintText: 'com.android.chrome',
            ),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<AppCategory>(
            initialValue: _newRuleCategory,
            decoration: const InputDecoration(labelText: 'Category'),
            items: AppCategory.values
                .map(
                  (category) => DropdownMenuItem(
                    value: category,
                    child: Text(category.label),
                  ),
                )
                .toList(),
            onChanged: (value) {
              if (value == null) return;
              setState(() {
                _newRuleCategory = value;
              });
            },
          ),
          const SizedBox(height: 12),
          SwitchListTile(
            value: _newRuleBlocksShorts,
            contentPadding: EdgeInsets.zero,
            title: const Text('Block Shorts / Reels here'),
            subtitle: const Text(
              'Useful for YouTube, Instagram, and browsers where short-form pages appear.',
            ),
            onChanged: (value) {
              setState(() {
                _newRuleBlocksShorts = value;
              });
            },
          ),
          const SizedBox(height: 12),
          ElevatedButton.icon(
            onPressed: _addRule,
            icon: const Icon(Icons.add_rounded),
            label: const Text('Save rule'),
          ),
        ],
      ),
    );
  }

  Widget _buildRuleListCard(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Current rules',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              if (_isSavingRules)
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
            ],
          ),
          const SizedBox(height: 12),
          for (final rule in _rules) ...[
            Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFF8F4EE),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    rule.label,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    rule.packageName,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: const Color(0xFF5D6B66),
                    ),
                  ),
                  const SizedBox(height: 14),
                  DropdownButtonFormField<AppCategory>(
                    initialValue: rule.category,
                    decoration: const InputDecoration(labelText: 'Category'),
                    items: AppCategory.values
                        .map(
                          (category) => DropdownMenuItem(
                            value: category,
                            child: Text(category.label),
                          ),
                        )
                        .toList(),
                    onChanged: (value) {
                      if (value == null) return;
                      _updateRule(rule.copyWith(category: value));
                    },
                  ),
                  const SizedBox(height: 8),
                  SwitchListTile(
                    value: rule.blockShorts,
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Block Shorts / Reels'),
                    onChanged: (value) {
                      _updateRule(rule.copyWith(blockShorts: value));
                    },
                  ),
                  if (!rule.isPreset)
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton.icon(
                        onPressed: () => _deleteRule(rule),
                        icon: const Icon(Icons.delete_outline),
                        label: const Text('Delete rule'),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
