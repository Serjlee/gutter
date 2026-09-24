import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../repo/repo_tab_controller.dart';

const _imageExtensions = {
  'png', 'jpg', 'jpeg', 'gif', 'webp', 'bmp', 'ico', //
};
const _maxTextBytes = 2 * 1024 * 1024;

/// Shows the full file content (text with line numbers, or an image).
class FilePreview extends StatefulWidget {
  const FilePreview({super.key, required this.tab, this.version});
  final RepoTabController tab;

  /// Reloads when this changes identity (e.g. the diff was refreshed).
  final Object? version;

  @override
  State<FilePreview> createState() => _FilePreviewState();
}

class _FilePreviewState extends State<FilePreview> {
  late Future<Uint8List?> _bytes = widget.tab.previewBytes();
  bool _forceText = false;

  @override
  void didUpdateWidget(FilePreview old) {
    super.didUpdateWidget(old);
    if (!identical(old.version, widget.version)) {
      _bytes = widget.tab.previewBytes();
    }
  }

  @override
  Widget build(BuildContext context) {
    final path = widget.tab.diffTarget?.path ?? '';
    final ext = path.contains('.') ? path.split('.').last.toLowerCase() : '';
    return FutureBuilder<Uint8List?>(
      future: _bytes,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        final bytes = snap.data;
        if (bytes == null) {
          return const Center(
            child: Text(
              'File does not exist in this version',
              style: TextStyle(color: AppColors.textDim),
            ),
          );
        }
        if (_imageExtensions.contains(ext)) {
          return Container(
            color: AppColors.background,
            alignment: Alignment.center,
            padding: const EdgeInsets.all(16),
            child: InteractiveViewer(
              maxScale: 8,
              child: Image.memory(
                bytes,
                errorBuilder: (_, _, _) => const Text('Cannot decode image'),
              ),
            ),
          );
        }
        final binary = bytes.take(8000).contains(0);
        if ((binary || bytes.length > _maxTextBytes) && !_forceText) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  binary
                      ? 'Binary file (${_size(bytes.length)})'
                      : 'Large file (${_size(bytes.length)})',
                  style: const TextStyle(color: AppColors.textDim),
                ),
                if (!binary) ...[
                  const SizedBox(height: 8),
                  FilledButton(
                    onPressed: () => setState(() => _forceText = true),
                    child: const Text('Show anyway'),
                  ),
                ],
              ],
            ),
          );
        }
        final lines = const LineSplitter().convert(
          utf8.decode(bytes, allowMalformed: true),
        );
        final numWidth = '${lines.length}'.length * 8.0 + 16;
        return Container(
          color: AppColors.background,
          child: SelectionArea(
            child: ListView.builder(
              itemExtent: 19,
              itemCount: lines.length,
              itemBuilder: (context, i) => Row(
                children: [
                  SizedBox(
                    width: numWidth,
                    child: Text(
                      '${i + 1}',
                      textAlign: TextAlign.right,
                      style: monoStyle(size: 11.5, color: AppColors.textFaint),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      lines[i].replaceAll('\t', '    '),
                      maxLines: 1,
                      softWrap: false,
                      overflow: TextOverflow.fade,
                      style: monoStyle(size: 12.5),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  static String _size(int n) {
    if (n < 1024) return '$n B';
    if (n < 1024 * 1024) return '${(n / 1024).toStringAsFixed(1)} KB';
    return '${(n / 1024 / 1024).toStringAsFixed(1)} MB';
  }
}
