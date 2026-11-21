import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import 'ticket_api.dart';
import 'ticket_ui.dart';

const maxAttachments = 5;
const maxAttachmentBytes = 15 * 1024 * 1024;

class AttachmentPicker extends StatefulWidget {
  const AttachmentPicker({
    super.key,
    required this.files,
    required this.onChanged,
    required this.enabled,
  });

  final List<PendingAttachment> files;
  final ValueChanged<List<PendingAttachment>> onChanged;
  final bool enabled;

  @override
  State<AttachmentPicker> createState() => _AttachmentPickerState();
}

class _AttachmentPickerState extends State<AttachmentPicker> {
  bool _selecting = false;
  String? _error;

  Future<void> _pick() async {
    if (_selecting) return;
    setState(() {
      _selecting = true;
      _error = null;
    });
    try {
      final selected = await openFiles();
      if (!mounted || !widget.enabled || selected.isEmpty) return;
      if (selected.length + widget.files.length > maxAttachments) {
        setState(() => _error = 'Attach up to 5 files per message.');
        return;
      }

      final added = <PendingAttachment>[];
      for (final file in selected) {
        final size = await file.length();
        if (!mounted || !widget.enabled) return;
        if (size > maxAttachmentBytes) {
          setState(() => _error = '${file.name} exceeds the 15 MB limit.');
          return;
        }
        added.add(PendingAttachment(file, size));
      }
      widget.onChanged([...widget.files, ...added]);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Could not read the selected files.');
      }
    } finally {
      if (mounted) setState(() => _selecting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final error = _error;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            TextButton.icon(
              onPressed:
                  widget.enabled &&
                      !_selecting &&
                      widget.files.length < maxAttachments
                  ? _pick
                  : null,
              icon: const Icon(Icons.attach_file),
              label: const Text('Attach files'),
            ),
            Text(
              '${widget.files.length}/5 files · 15 MB each',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
        if (widget.files.isNotEmpty)
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final item in widget.files)
                InputChip(
                  label: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 200),
                    child: Text(
                      item.file.name,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  onDeleted: widget.enabled && !_selecting
                      ? () {
                          setState(() => _error = null);
                          widget.onChanged(
                            widget.files.where((file) => file != item).toList(),
                          );
                        }
                      : null,
                  deleteButtonTooltipMessage: 'Remove ${item.file.name}',
                ),
            ],
          ),
        if (error != null) TicketErrorText(error),
      ],
    );
  }
}
