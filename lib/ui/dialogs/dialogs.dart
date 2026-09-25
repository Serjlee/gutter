import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/theme.dart';

/// [showDialog] without the open/close animation: dialogs appear instantly.
Future<T?> showAppDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
}) => showDialog<T>(
  context: context,
  builder: builder,
  animationStyle: AnimationStyle.noAnimation,
);

/// Asks for confirmation. Returns true if confirmed.
Future<bool> confirm(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'OK',
  bool danger = false,
}) async {
  final r = await showAppDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title, style: const TextStyle(fontSize: 17)),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Text(message, style: const TextStyle(color: AppColors.textDim)),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          autofocus: true,
          style: danger
              ? FilledButton.styleFrom(backgroundColor: AppColors.danger)
              : null,
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return r ?? false;
}

class FieldSpec {
  const FieldSpec(
    this.label, {
    this.initial = '',
    this.hint,
    this.multiline = false,
    this.optional = false,
  });
  final String label;
  final String initial;
  final String? hint;
  final bool multiline;
  final bool optional;
}

/// Prompts for one or more text values. Returns null if cancelled.
Future<List<String>?> promptFields(
  BuildContext context, {
  required String title,
  required List<FieldSpec> fields,
  String confirmLabel = 'OK',
  Widget? extra,
  String? Function(List<String>)? validate,
}) {
  return showAppDialog<List<String>>(
    context: context,
    builder: (ctx) => _PromptDialog(
      title: title,
      fields: fields,
      confirmLabel: confirmLabel,
      extra: extra,
      validate: validate,
    ),
  );
}

Future<String?> promptText(
  BuildContext context, {
  required String title,
  required String label,
  String initial = '',
  String confirmLabel = 'OK',
  String? hint,
  bool optional = false,
}) async {
  final r = await promptFields(
    context,
    title: title,
    fields: [
      FieldSpec(label, initial: initial, hint: hint, optional: optional),
    ],
    confirmLabel: confirmLabel,
  );
  return r?.first;
}

class _PromptDialog extends StatefulWidget {
  const _PromptDialog({
    required this.title,
    required this.fields,
    required this.confirmLabel,
    this.extra,
    this.validate,
  });

  final String title;
  final List<FieldSpec> fields;
  final String confirmLabel;
  final Widget? extra;
  final String? Function(List<String>)? validate;

  @override
  State<_PromptDialog> createState() => _PromptDialogState();
}

class _PromptDialogState extends State<_PromptDialog> {
  late final controllers = [
    for (final f in widget.fields) TextEditingController(text: f.initial),
  ];
  String? error;

  @override
  void dispose() {
    for (final c in controllers) {
      c.dispose();
    }
    super.dispose();
  }

  void _submit() {
    final values = controllers.map((c) => c.text).toList();
    for (var i = 0; i < values.length; i++) {
      if (!widget.fields[i].optional && values[i].trim().isEmpty) {
        setState(() => error = '${widget.fields[i].label} is required');
        return;
      }
    }
    final e = widget.validate?.call(values);
    if (e != null) {
      setState(() => error = e);
      return;
    }
    Navigator.pop(context, values);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title, style: const TextStyle(fontSize: 17)),
      content: SizedBox(
        width: 440,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < widget.fields.length; i++) ...[
              if (i > 0) const SizedBox(height: 12),
              CallbackShortcuts(
                bindings: {
                  const SingleActivator(
                    LogicalKeyboardKey.enter,
                    control: true,
                  ): _submit,
                  const SingleActivator(LogicalKeyboardKey.enter, meta: true):
                      _submit,
                },
                child: TextField(
                  controller: controllers[i],
                  autofocus: i == 0,
                  minLines: widget.fields[i].multiline ? 3 : 1,
                  maxLines: widget.fields[i].multiline ? 6 : 1,
                  onSubmitted: widget.fields[i].multiline
                      ? null
                      : (_) => _submit(),
                  decoration: InputDecoration(
                    labelText:
                        widget.fields[i].label +
                        (widget.fields[i].optional ? ' (optional)' : ''),
                    hintText: widget.fields[i].hint,
                  ),
                ),
              ),
            ],
            if (widget.extra != null) ...[
              const SizedBox(height: 12),
              widget.extra!,
            ],
            if (error != null) ...[
              const SizedBox(height: 10),
              Text(error!, style: const TextStyle(color: AppColors.danger)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: Text(widget.confirmLabel)),
      ],
    );
  }
}

/// Picks one of several options. Returns the chosen value or null.
Future<T?> chooseOption<T>(
  BuildContext context, {
  required String title,
  String? message,
  required List<(T, String, String)> options,
}) {
  return showAppDialog<T>(
    context: context,
    builder: (ctx) => SimpleDialog(
      title: Text(title, style: const TextStyle(fontSize: 17)),
      children: [
        if (message != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
            child: Text(
              message,
              style: const TextStyle(color: AppColors.textDim),
            ),
          ),
        for (final (value, label, description) in options)
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, value),
            child: SizedBox(
              width: 400,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    description,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textDim,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    ),
  );
}

String? validateRefName(String name) {
  final n = name.trim();
  if (n.isEmpty) return 'Name is required';
  if (RegExp(r'[\s~^:?*\[\\]').hasMatch(n) ||
      n.contains('..') ||
      n.startsWith('-') ||
      n.endsWith('/') ||
      n.endsWith('.lock') ||
      n.contains('@{')) {
    return 'Invalid name';
  }
  return null;
}
