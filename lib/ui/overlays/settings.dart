import 'package:flutter/material.dart';
import 'package:hermes/core/services/preferences_service.dart';
import 'package:hermes/core/services/service_provider.dart';

class Settings extends StatefulWidget {
  const Settings({super.key});
  @override
  State<Settings> createState() => _SettingsState();
}

class _SettingsState extends State<Settings> {
  late final TextEditingController _llamaCppDirCtrl;
  late final TextEditingController _modelsDirCtrl;

  final PreferencesService preferencesService =
      serviceProvider.get<PreferencesService>();

  void loadSettings() async {
    final llamaCppDir = await preferencesService.getLlamaCppDirectory();
    final modelsDir = await preferencesService.getModelsDirectory();
    if (!mounted) return;
    if (llamaCppDir is String && llamaCppDir.isNotEmpty) {
      _llamaCppDirCtrl.text = llamaCppDir;
    }
    if (modelsDir is String && modelsDir.isNotEmpty) {
      _modelsDirCtrl.text = modelsDir;
    }
    setState(() {});
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
            const Text('Settings',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
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

            FilledButton(
              onPressed: () async {
                final llamaCppDir = _llamaCppDirCtrl.text.trim();
                final modelsDir = _modelsDirCtrl.text.trim();

                await preferencesService.setLlamaCppDirectory(llamaCppDir);
                await preferencesService.setModelsDirectory(modelsDir);

                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Saved')),
                  );
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
