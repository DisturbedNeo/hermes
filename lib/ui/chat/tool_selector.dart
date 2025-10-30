import 'package:flutter/material.dart';
import 'package:hermes/core/models/tool_definition.dart';

class ToolSelector extends StatefulWidget {
  final List<ToolDefinition> allTools;
  final Set<String> initiallySelectedIds;

  const ToolSelector({
    super.key,
    required this.allTools,
    required this.initiallySelectedIds,
  });

  @override
  State<ToolSelector> createState() => _ToolSelectorState();
}

class _ToolSelectorState extends State<ToolSelector> {
  late final TextEditingController _searchController;
  late Set<String> _selectedIds;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
    _selectedIds = {...widget.initiallySelectedIds};
    _searchController.addListener(() {
      setState(() {
        _query = _searchController.text.trim().toLowerCase();
      });
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _query.isEmpty
        ? widget.allTools
        : widget.allTools.where((t) {
            return t.name.toLowerCase().contains(_query) ||
                t.description.toLowerCase().contains(_query);
          }).toList();

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 42,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  const Text(
                    'Tools',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '${_selectedIds.length} selected',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                controller: _searchController,
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: 'Search tools…',
                  isDense: true,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: filtered.length,
                itemBuilder: (context, index) {
                  final tool = filtered[index];
                  final selected = _selectedIds.contains(tool.id);
                  return CheckboxListTile(
                    value: selected,
                    onChanged: (v) {
                      setState(() {
                        if (v == true) {
                          _selectedIds.add(tool.id);
                        } else {
                          _selectedIds.remove(tool.id);
                        }
                      });
                    },
                    title: Text(tool.name),
                    subtitle: tool.description.isNotEmpty
                        ? Text(
                            tool.description,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          )
                        : null,
                    controlAffinity: ListTileControlAffinity.leading,
                  );
                },
              ),
            ),
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  TextButton(
                    onPressed: () {
                      setState(() => _selectedIds.clear());
                    },
                    child: const Text('Clear'),
                  ),
                  const Spacer(),
                  FilledButton(
                    onPressed: () {
                      Navigator.of(context).pop<Set<String>>(_selectedIds);
                    },
                    child: const Text('Done'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
