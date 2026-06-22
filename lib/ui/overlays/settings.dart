import 'package:flutter/material.dart';
import 'package:hermes/core/enums/diagnostics_visibility.dart';
import 'package:hermes/core/helpers/a11y.dart';
import 'package:hermes/core/models/compaction_settings.dart';
import 'package:hermes/core/models/task_system_settings.dart';
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
  TaskSystemSettings _taskSystemSettings = const TaskSystemSettings();

  final PreferencesService preferencesService = serviceProvider
      .get<PreferencesService>();

  void loadSettings() async {
    final llamaCppDir = await preferencesService.getLlamaCppDirectory();
    final modelsDir = await preferencesService.getModelsDirectory();
    final diagnosticsVisibility = await preferencesService
        .getDiagnosticsVisibility();
    final compactionSettings = await preferencesService.getCompactionSettings();
    final taskSystemSettings = await preferencesService.getTaskSystemSettings();
    if (!mounted) return;
    if (llamaCppDir is String && llamaCppDir.isNotEmpty) {
      _llamaCppDirCtrl.text = llamaCppDir;
    }
    if (modelsDir is String && modelsDir.isNotEmpty) {
      _modelsDirCtrl.text = modelsDir;
    }
    _diagnosticsVisibility = diagnosticsVisibility;
    _compactionSettings = compactionSettings;
    _taskSystemSettings = taskSystemSettings;
    setState(() {});
  }

  Future<void> _setCompactionSettings(CompactionSettings settings) async {
    final normalised = settings.normalised();
    setState(() => _compactionSettings = normalised);
    await preferencesService.setCompactionSettings(normalised);
  }

  Future<void> _setTaskSystemSettings(TaskSystemSettings settings) async {
    final normalised = settings.normalised();
    setState(() => _taskSystemSettings = normalised);
    await preferencesService.setTaskSystemSettings(normalised);
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
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: _SettingsContent(
          llamaCppDirCtrl: _llamaCppDirCtrl,
          modelsDirCtrl: _modelsDirCtrl,
          diagnosticsVisibility: _diagnosticsVisibility,
          compactionSettings: _compactionSettings,
          taskSystemSettings: _taskSystemSettings,
          onDiagnosticsChanged: (v) async {
            if (v == null) return;
            setState(() => _diagnosticsVisibility = v);
            await preferencesService.setDiagnosticsVisibility(v);
          },
          onCompactionChanged: _setCompactionSettings,
          onTaskSystemChanged: _setTaskSystemSettings,
          onSave: () async {
            final llamaCppDir = _llamaCppDirCtrl.text.trim();
            final modelsDir = _modelsDirCtrl.text.trim();

            await preferencesService.setLlamaCppDirectory(llamaCppDir);
            await preferencesService.setModelsDirectory(modelsDir);

            if (context.mounted) {
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(const SnackBar(content: Text('Saved')));
              setState(() {});
            }
          },
        ),
      ),
    );
  }
}

class _SettingsContent extends StatelessWidget {
  final TextEditingController llamaCppDirCtrl;
  final TextEditingController modelsDirCtrl;
  final DiagnosticsVisibility diagnosticsVisibility;
  final CompactionSettings compactionSettings;
  final TaskSystemSettings taskSystemSettings;
  final Future<void> Function(DiagnosticsVisibility?) onDiagnosticsChanged;
  final Future<void> Function(CompactionSettings) onCompactionChanged;
  final Future<void> Function(TaskSystemSettings) onTaskSystemChanged;
  final Future<void> Function() onSave;

  const _SettingsContent({
    required this.llamaCppDirCtrl,
    required this.modelsDirCtrl,
    required this.diagnosticsVisibility,
    required this.compactionSettings,
    required this.taskSystemSettings,
    required this.onDiagnosticsChanged,
    required this.onCompactionChanged,
    required this.onTaskSystemChanged,
    required this.onSave,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Settings',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 24),
        ..._pathsSection(),
        const SizedBox(height: 28),
        ..._diagnosticsSection(context),
        const SizedBox(height: 28),
        ..._compactionSection(context),
        const SizedBox(height: 28),
        ..._taskSystemSection(context),
        const SizedBox(height: 24),
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
  ];

  List<Widget> _taskSystemSection(BuildContext context) => [
    const Text(
      'Task System',
      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
    ),
    const SizedBox(height: 8),
    SwitchListTile(
      contentPadding: EdgeInsets.zero,
      title: const Text('Enable structured tasks'),
      value: taskSystemSettings.enabled,
      onChanged: (enabled) =>
          onTaskSystemChanged(taskSystemSettings.copyWith(enabled: enabled)),
    ),
    SwitchListTile(
      contentPadding: EdgeInsets.zero,
      title: const Text('Require approval before execution'),
      value: taskSystemSettings.requireApprovalBeforeExecution,
      onChanged: taskSystemSettings.enabled
          ? (enabled) => onTaskSystemChanged(
              taskSystemSettings.copyWith(
                requireApprovalBeforeExecution: enabled,
              ),
            )
          : null,
    ),
    SwitchListTile(
      contentPadding: EdgeInsets.zero,
      title: const Text('Require approval before file edits'),
      value: taskSystemSettings.requireApprovalBeforeFileEdits,
      onChanged: taskSystemSettings.enabled
          ? (enabled) => onTaskSystemChanged(
              taskSystemSettings.copyWith(
                requireApprovalBeforeFileEdits: enabled,
              ),
            )
          : null,
    ),
    SwitchListTile(
      contentPadding: EdgeInsets.zero,
      title: const Text('Show task messages in chat'),
      value: taskSystemSettings.showTaskMessagesInChat,
      onChanged: taskSystemSettings.enabled
          ? (enabled) => onTaskSystemChanged(
              taskSystemSettings.copyWith(showTaskMessagesInChat: enabled),
            )
          : null,
    ),
    SliderControl.integer(
      label: 'Max project tasks per run',
      value: taskSystemSettings.maxProjectTasksPerRun,
      min: 1,
      max: 25,
      step: 1,
      onChanged: (value) => onTaskSystemChanged(
        taskSystemSettings.copyWith(maxProjectTasksPerRun: value),
      ),
    ),
  ];
}
