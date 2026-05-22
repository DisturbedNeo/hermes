import 'package:flutter/material.dart';
import 'package:hermes/core/enums/diagnostics_visibility.dart';
import 'package:hermes/core/helpers/a11y.dart';
import 'package:hermes/core/helpers/responsive.dart';
import 'package:hermes/core/models/compaction_settings.dart';
import 'package:hermes/core/models/job_system_settings.dart';
import 'package:hermes/core/services/preferences_service.dart';
import 'package:hermes/core/services/service_provider.dart';
import 'package:hermes/ui/model_configuration/slider_control.dart';

class Settings extends StatefulWidget {
  const Settings({super.key});
  @override
  State<Settings> createState() => _SettingsState();
}

class _SettingsState extends State<Settings> {
  late final TextEditingController _llamaCppDirCtrl;
  late final TextEditingController _modelsDirCtrl;
  DiagnosticsVisibility _diagnosticsVisibility = DiagnosticsVisibility.off;
  CompactionSettings _compactionSettings = const CompactionSettings();
  JobSystemSettings _jobSystemSettings = const JobSystemSettings();

  final PreferencesService preferencesService = serviceProvider
      .get<PreferencesService>();

  void loadSettings() async {
    final llamaCppDir = await preferencesService.getLlamaCppDirectory();
    final modelsDir = await preferencesService.getModelsDirectory();
    final diagnosticsVisibility = await preferencesService
        .getDiagnosticsVisibility();
    final compactionSettings = await preferencesService.getCompactionSettings();
    final jobSystemSettings = await preferencesService.getJobSystemSettings();
    if (!mounted) return;
    if (llamaCppDir is String && llamaCppDir.isNotEmpty) {
      _llamaCppDirCtrl.text = llamaCppDir;
    }
    if (modelsDir is String && modelsDir.isNotEmpty) {
      _modelsDirCtrl.text = modelsDir;
    }
    _diagnosticsVisibility = diagnosticsVisibility;
    _compactionSettings = compactionSettings;
    _jobSystemSettings = jobSystemSettings;
    setState(() {});
  }

  Future<void> _setCompactionSettings(CompactionSettings settings) async {
    final normalised = settings.normalised();
    setState(() => _compactionSettings = normalised);
    await preferencesService.setCompactionSettings(normalised);
  }

  Future<void> _setJobSystemSettings(JobSystemSettings settings) async {
    final normalised = settings.normalised();
    setState(() => _jobSystemSettings = normalised);
    await preferencesService.setJobSystemSettings(normalised);
  }

  @override
  void initState() {
    super.initState();
    _llamaCppDirCtrl = TextEditingController(text: '');
    _modelsDirCtrl = TextEditingController(text: '');

    loadSettings();
  }

  @override
  void dispose() {
    _llamaCppDirCtrl.dispose();
    _modelsDirCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isWide = Responsive.hasWideViewport(context);

    return SafeArea(
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (isWide) {
            return Row(
              children: [
                // Left sidebar with category navigation
                SizedBox(
                  width: 200,
                  child: _SettingsSidebar(
                    categories: const [
                      _SettingsCategory('paths', 'Paths'),
                      _SettingsCategory('diagnostics', 'Diagnostics'),
                      _SettingsCategory('compaction', 'Context Compaction'),
                      _SettingsCategory('jobs', 'Job System'),
                    ],
                    selectedCategory: _currentCategory,
                    onSelect: (cat) => setState(() => _currentCategory = cat),
                  ),
                ),
                const VerticalDivider(width: 1),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(24),
                    child: _SettingsContent(
                      selectedCategory: _currentCategory,
                      llamaCppDirCtrl: _llamaCppDirCtrl,
                      modelsDirCtrl: _modelsDirCtrl,
                      diagnosticsVisibility: _diagnosticsVisibility,
                      compactionSettings: _compactionSettings,
                      jobSystemSettings: _jobSystemSettings,
                      onDiagnosticsChanged: (v) async {
                        if (v == null) return;
                        setState(() => _diagnosticsVisibility = v);
                        await preferencesService.setDiagnosticsVisibility(v);
                      },
                      onCompactionChanged: _setCompactionSettings,
                      onJobSystemChanged: _setJobSystemSettings,
                      onSave: () async {
                        final llamaCppDir = _llamaCppDirCtrl.text.trim();
                        final modelsDir = _modelsDirCtrl.text.trim();

                        await preferencesService.setLlamaCppDirectory(
                          llamaCppDir,
                        );
                        await preferencesService.setModelsDirectory(modelsDir);

                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Saved')),
                          );
                          setState(() {});
                        }
                      },
                    ),
                  ),
                ),
              ],
            );
          }

          // Narrow layout: single-column scrollable list
          return Padding(
            padding: const EdgeInsets.all(16),
            child: ListView(
              children: [
                const Text(
                  'Settings',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 12),

                // llama.cpp Directory
                TextField(
                  controller: _llamaCppDirCtrl,
                  decoration: const InputDecoration(
                    labelText: 'llama.cpp Directory',
                    hintText: '/home/you/dev/llama.cpp',
                    prefixIcon: Icon(Icons.folder),
                  ),
                ),
                const SizedBox(height: 12),

                // Models Directory
                TextField(
                  controller: _modelsDirCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Models Directory',
                    hintText: '/home/you/Models',
                    prefixIcon: Icon(Icons.folder),
                  ),
                ),
                const SizedBox(height: 16),

                const Text(
                  'Diagnostics',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                AccessibleWidget(
                  label: 'Session diagnostics',
                  child: DropdownButtonFormField<DiagnosticsVisibility>(
                    initialValue: _diagnosticsVisibility,
                    decoration: const InputDecoration(
                      labelText: 'Session diagnostics',
                      prefixIcon: Icon(Icons.monitor_heart_outlined),
                      border: OutlineInputBorder(),
                    ),
                    items: DiagnosticsVisibility.values.map((visibility) {
                      return DropdownMenuItem(
                        value: visibility,
                        child: Text(visibility.label),
                      );
                    }).toList(),
                    onChanged: (visibility) async {
                      if (visibility == null) return;
                      setState(() => _diagnosticsVisibility = visibility);
                      await preferencesService.setDiagnosticsVisibility(
                        visibility,
                      );
                    },
                  ),
                ),
                const SizedBox(height: 16),

                const Text(
                  'Context Compaction',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Enable context compaction'),
                  value: _compactionSettings.enabled,
                  onChanged: (enabled) => _setCompactionSettings(
                    _compactionSettings.copyWith(enabled: enabled),
                  ),
                ),
                SliderControl.integer(
                  label: 'Compaction threshold (%)',
                  value: (_compactionSettings.triggerThreshold * 100).round(),
                  min: 60,
                  max: 90,
                  step: 5,
                  onChanged: (value) {
                    final trigger = value / 100;
                    _setCompactionSettings(
                      _compactionSettings.copyWith(
                        triggerThreshold: trigger,
                        hardLimitThreshold: _compactionSettings
                            .hardLimitThreshold
                            .clamp(trigger, 0.99)
                            .toDouble(),
                      ),
                    );
                  },
                ),
                SliderControl.integer(
                  label: 'Recent window size',
                  value: _compactionSettings.recentWindowUnits,
                  min: 2,
                  max: 10,
                  step: 1,
                  onChanged: (value) => _setCompactionSettings(
                    _compactionSettings.copyWith(recentWindowUnits: value),
                  ),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Emergency payload truncation'),
                  value: _compactionSettings.allowEmergencyPayloadTruncation,
                  onChanged: (enabled) => _setCompactionSettings(
                    _compactionSettings.copyWith(
                      allowEmergencyPayloadTruncation: enabled,
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                const Text(
                  'Job System',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Enable structured jobs'),
                  value: _jobSystemSettings.enabled,
                  onChanged: (enabled) => _setJobSystemSettings(
                    _jobSystemSettings.copyWith(enabled: enabled),
                  ),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Require approval before file edits'),
                  value: _jobSystemSettings.requireApprovalBeforeFileEdits,
                  onChanged: _jobSystemSettings.enabled
                      ? (enabled) => _setJobSystemSettings(
                          _jobSystemSettings.copyWith(
                            requireApprovalBeforeFileEdits: enabled,
                          ),
                        )
                      : null,
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Show job messages in chat'),
                  value: _jobSystemSettings.showJobMessagesInChat,
                  onChanged: _jobSystemSettings.enabled
                      ? (enabled) => _setJobSystemSettings(
                          _jobSystemSettings.copyWith(
                            showJobMessagesInChat: enabled,
                          ),
                        )
                      : null,
                ),
                const SizedBox(height: 16),

                AccessibleWidget(
                  label: 'Save settings',
                  isButton: true,
                  child: FilledButton(
                    onPressed: () async {
                      final llamaCppDir = _llamaCppDirCtrl.text.trim();
                      final modelsDir = _modelsDirCtrl.text.trim();

                      await preferencesService.setLlamaCppDirectory(
                        llamaCppDir,
                      );
                      await preferencesService.setModelsDirectory(modelsDir);

                      if (context.mounted) {
                        ScaffoldMessenger.of(
                          context,
                        ).showSnackBar(const SnackBar(content: Text('Saved')));
                        setState(() {});
                      }
                    },
                    child: const Text('Save'),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  String _currentCategory = 'paths';
}

class _SettingsCategory {
  final String id;
  final String label;
  const _SettingsCategory(this.id, this.label);
}

class _SettingsSidebar extends StatelessWidget {
  final List<_SettingsCategory> categories;
  final String selectedCategory;
  final ValueChanged<String> onSelect;

  const _SettingsSidebar({
    required this.categories,
    required this.selectedCategory,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: categories.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final cat = categories[index];
        final isSelected = cat.id == selectedCategory;
        return ListTile(
          title: Text(cat.label),
          selected: isSelected,
          selectedTileColor: theme.colorScheme.primaryContainer.withValues(
            alpha: 0.3,
          ),
          onTap: () => onSelect(cat.id),
        );
      },
    );
  }
}

class _SettingsContent extends StatelessWidget {
  final TextEditingController llamaCppDirCtrl;
  final TextEditingController modelsDirCtrl;
  final DiagnosticsVisibility diagnosticsVisibility;
  final CompactionSettings compactionSettings;
  final JobSystemSettings jobSystemSettings;
  final String selectedCategory;
  final Future<void> Function(DiagnosticsVisibility?) onDiagnosticsChanged;
  final Future<void> Function(CompactionSettings) onCompactionChanged;
  final Future<void> Function(JobSystemSettings) onJobSystemChanged;
  final Future<void> Function() onSave;

  const _SettingsContent({
    required this.selectedCategory,
    required this.llamaCppDirCtrl,
    required this.modelsDirCtrl,
    required this.diagnosticsVisibility,
    required this.compactionSettings,
    required this.jobSystemSettings,
    required this.onDiagnosticsChanged,
    required this.onCompactionChanged,
    required this.onJobSystemChanged,
    required this.onSave,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Paths section
        if (selectedCategory == 'paths' || selectedCategory == 'all')
          ..._pathsSection(),
        // Diagnostics section
        if (selectedCategory == 'diagnostics' || selectedCategory == 'all')
          ..._diagnosticsSection(context),
        // Compaction section
        if (selectedCategory == 'compaction' || selectedCategory == 'all')
          ..._compactionSection(context),
        // Job System section
        if (selectedCategory == 'jobs' || selectedCategory == 'all')
          ..._jobSystemSection(context),
        const SizedBox(height: 16),
        AccessibleWidget(
          label: 'Save settings',
          isButton: true,
          child: FilledButton(onPressed: onSave, child: const Text('Save')),
        ),
      ],
    );
  }

  List<Widget> _pathsSection() => [
    const Text(
      'Paths',
      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
    ),
    const SizedBox(height: 12),
    TextField(
      controller: llamaCppDirCtrl,
      decoration: const InputDecoration(
        labelText: 'llama.cpp Directory',
        hintText: '/home/you/dev/llama.cpp',
        prefixIcon: Icon(Icons.folder),
      ),
    ),
    const SizedBox(height: 12),
    TextField(
      controller: modelsDirCtrl,
      decoration: const InputDecoration(
        labelText: 'Models Directory',
        hintText: '/home/you/Models',
        prefixIcon: Icon(Icons.folder),
      ),
    ),
    const SizedBox(height: 16),
  ];

  List<Widget> _diagnosticsSection(BuildContext context) => [
    const Text(
      'Diagnostics',
      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
    ),
    const SizedBox(height: 8),
    AccessibleWidget(
      label: 'Session diagnostics',
      child: DropdownButtonFormField<DiagnosticsVisibility>(
        initialValue: diagnosticsVisibility,
        decoration: const InputDecoration(
          labelText: 'Session diagnostics',
          prefixIcon: Icon(Icons.monitor_heart_outlined),
          border: OutlineInputBorder(),
        ),
        items: DiagnosticsVisibility.values.map((visibility) {
          return DropdownMenuItem(
            value: visibility,
            child: Text(visibility.label),
          );
        }).toList(),
        onChanged: onDiagnosticsChanged,
      ),
    ),
    const SizedBox(height: 16),
  ];

  List<Widget> _compactionSection(BuildContext context) => [
    const Text(
      'Context Compaction',
      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
    ),
    const SizedBox(height: 8),
    SwitchListTile(
      contentPadding: EdgeInsets.zero,
      title: const Text('Enable context compaction'),
      value: compactionSettings.enabled,
      onChanged: (enabled) =>
          onCompactionChanged(compactionSettings.copyWith(enabled: enabled)),
    ),
    SliderControl.integer(
      label: 'Compaction threshold (%)',
      value: (compactionSettings.triggerThreshold * 100).round(),
      min: 60,
      max: 90,
      step: 5,
      onChanged: (value) {
        final trigger = value / 100;
        onCompactionChanged(
          compactionSettings.copyWith(
            triggerThreshold: trigger,
            hardLimitThreshold: compactionSettings.hardLimitThreshold
                .clamp(trigger, 0.99)
                .toDouble(),
          ),
        );
      },
    ),
    SliderControl.integer(
      label: 'Recent window size',
      value: compactionSettings.recentWindowUnits,
      min: 2,
      max: 10,
      step: 1,
      onChanged: (value) => onCompactionChanged(
        compactionSettings.copyWith(recentWindowUnits: value),
      ),
    ),
    SwitchListTile(
      contentPadding: EdgeInsets.zero,
      title: const Text('Emergency payload truncation'),
      value: compactionSettings.allowEmergencyPayloadTruncation,
      onChanged: (enabled) => onCompactionChanged(
        compactionSettings.copyWith(allowEmergencyPayloadTruncation: enabled),
      ),
    ),
    const SizedBox(height: 16),
  ];

  List<Widget> _jobSystemSection(BuildContext context) => [
    const Text(
      'Job System',
      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
    ),
    const SizedBox(height: 8),
    SwitchListTile(
      contentPadding: EdgeInsets.zero,
      title: const Text('Enable structured jobs'),
      value: jobSystemSettings.enabled,
      onChanged: (enabled) =>
          onJobSystemChanged(jobSystemSettings.copyWith(enabled: enabled)),
    ),
    SwitchListTile(
      contentPadding: EdgeInsets.zero,
      title: const Text('Require approval before file edits'),
      value: jobSystemSettings.requireApprovalBeforeFileEdits,
      onChanged: jobSystemSettings.enabled
          ? (enabled) => onJobSystemChanged(
              jobSystemSettings.copyWith(
                requireApprovalBeforeFileEdits: enabled,
              ),
            )
          : null,
    ),
    SwitchListTile(
      contentPadding: EdgeInsets.zero,
      title: const Text('Show job messages in chat'),
      value: jobSystemSettings.showJobMessagesInChat,
      onChanged: jobSystemSettings.enabled
          ? (enabled) => onJobSystemChanged(
              jobSystemSettings.copyWith(showJobMessagesInChat: enabled),
            )
          : null,
    ),
    const SizedBox(height: 16),
  ];
}
