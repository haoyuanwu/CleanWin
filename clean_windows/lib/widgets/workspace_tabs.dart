import 'package:flutter/material.dart';

/// Lazy first mount, persistent pages after visiting; inactive polling is explicit.
class WorkspaceTabs extends StatefulWidget {
  const WorkspaceTabs({
    super.key,
    required this.active,
    required this.index,
    required this.onChanged,
    required this.tabs,
    required this.builder,
  });
  final bool active;
  final int index;
  final ValueChanged<int> onChanged;
  final List<({String label, IconData icon})> tabs;
  final Widget Function(int index, bool active) builder;
  @override
  State<WorkspaceTabs> createState() => _WorkspaceTabsState();
}

class _WorkspaceTabsState extends State<WorkspaceTabs> {
  final Set<int> _visited = {};
  @override
  Widget build(BuildContext context) {
    if (widget.active) _visited.add(widget.index);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (var i = 0; i < widget.tabs.length; i++)
                ChoiceChip(
                  key: ValueKey('workspace-tab-$i'),
                  avatar: Icon(widget.tabs[i].icon, size: 17),
                  label: Text(widget.tabs[i].label),
                  labelStyle: Theme.of(context).textTheme.labelLarge?.copyWith(
                    fontFamily: 'Segoe UI',
                    fontSize: 13,
                    color: widget.index == i
                        ? Theme.of(context).colorScheme.primary
                        : Theme.of(context).colorScheme.onSurface,
                  ),
                  showCheckmark: false,
                  selected: widget.index == i,
                  onSelected: (_) => widget.onChanged(i),
                ),
            ],
          ),
        ),
        Expanded(
          child: IndexedStack(
            index: widget.index,
            children: [
              for (var i = 0; i < widget.tabs.length; i++)
                TickerMode(
                  enabled: widget.active && widget.index == i,
                  child: _visited.contains(i)
                      ? widget.builder(i, widget.active && widget.index == i)
                      : const SizedBox.shrink(),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
