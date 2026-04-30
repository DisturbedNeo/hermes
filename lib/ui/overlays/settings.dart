import 'package:flutter/material.dart';
import 'package:hermes/core/enums/diagnostics_visibility.dart';
import 'package:hermes/core/models/compaction_settings.dart';
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

  final PreferencesService preferencesService = serviceProvider
      .get<PreferencesService>();

  void loadSettings() async {
    final llamaCppDir = await preferencesService.getLlamaCppDirectory();
    final modelsDir = await preferencesService.getModelsDirectory();
    final diagnosticsVisibility = await preferencesService
        .getDiagnosticsVisibility();
    final compactionSettings = await preferencesService.getCompactionSettings();
    if (!mounted) return;
    if (llamaCppDir is String && llamaCppDir.isNotEmpty) {
      _llamaCppDirCtrl.text = llamaCppDir;
    }
    if (modelsDir is String && modelsDir.isNotEmpty) {
      _modelsDirCtrl.text = modelsDir;
    }
    _diagnosticsVisibility = diagnosticsVisibility;
    _compactionSettings = compactionSettings;
    setState(() {});
  }

  Future<void> _setCompactionSettings(CompactionSettings settings) async {
    final normalised = settings.normalised();
    setState(() => _compactionSettings = normalised);
    await preferencesService.setCompactionSettings(normalised);
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
      child: Padding(
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
            DropdownButtonFormField<DiagnosticsVisibility>(
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
                await preferencesService.setDiagnosticsVisibility(visibility);
              },
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
                    hardLimitThreshold: _compactionSettings.hardLimitThreshold
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

            FilledButton(
              onPressed: () async {
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
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }
}
