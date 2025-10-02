import 'package:flutter/material.dart';

class Settings extends StatefulWidget {
  const Settings({super.key});
  @override
  State<Settings> createState() => _SettingsState();
}

class _SettingsState extends State<Settings> {
  late final TextEditingController _urlCtrl;
  late final TextEditingController _keyCtrl;
  late final TextEditingController _modelCtrl;

  @override
  void initState() {
    super.initState();
    _urlCtrl = TextEditingController(text: '');
    _keyCtrl = TextEditingController(text: '');
    _modelCtrl = TextEditingController(text: '');
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: ListView(
          children: [
            const Text('Settings', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
            const SizedBox(height: 12),
            TextField(
              controller: _urlCtrl,
              decoration: const InputDecoration(
                labelText: 'Base URL',
                hintText: 'http://localhost:8080',
                prefixIcon: Icon(Icons.link),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _keyCtrl,
              decoration: const InputDecoration(
                labelText: 'API Key (optional)',
                prefixIcon: Icon(Icons.vpn_key),
              ),
              obscureText: true,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _modelCtrl,
              decoration: const InputDecoration(
                labelText: 'Default model id',
                hintText: 'llama-3.1-8b-instruct',
                prefixIcon: Icon(Icons.memory),
              ),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () async {
                /*await configService.save(
                  baseUrl: _urlCtrl.text.trim(),
                  apiKey: _keyCtrl.text.trim(),
                  defaultModel: _modelCtrl.text.trim(),
                );*/
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Saved')));
                  setState(() {}); // refresh labels if needed
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
