/// Groups file paths into a collapsible folder tree for display.
library;

/// One visible row of a file tree: a folder ([item] is null) or a file.
class FileTreeRow<T> {
  const FileTreeRow.dir({
    required this.depth,
    required this.path,
    required this.label,
    required this.fileCount,
    required this.collapsed,
  }) : item = null;

  const FileTreeRow.file({
    required this.depth,
    required this.path,
    required this.label,
    required T this.item,
  }) : fileCount = 1,
       collapsed = false;

  /// Nesting level (0 = top level).
  final int depth;

  /// Full path: the folder path (no trailing slash) or the file path.
  final String path;

  /// Text to show: the folder name (compacted chains like `src/app`) or the
  /// file name.
  final String label;

  /// Files at any depth below this folder (1 for files).
  final int fileCount;
  final bool collapsed;
  final T? item;

  bool get isDir => item == null;
}

class _Node<T> {
  final dirs = <String, _Node<T>>{};
  final files = <(String, T)>[];
  int count = 0;
}

/// Builds the visible rows of a tree over [items], sorted folders first then
/// files, case-insensitively. Folder chains with a single subfolder and no
/// files are compacted into one row (`a/b/c`). Folders whose path is in
/// [collapsed] are shown without their contents.
List<FileTreeRow<T>> flattenFileTree<T>(
  Iterable<T> items,
  String Function(T) pathOf, {
  Set<String> collapsed = const {},
}) {
  final root = _Node<T>();
  for (final item in items) {
    final parts = pathOf(item).split('/');
    var node = root..count += 1;
    for (var i = 0; i < parts.length - 1; i++) {
      node = node.dirs.putIfAbsent(parts[i], _Node<T>.new)..count += 1;
    }
    node.files.add((parts.last, item));
  }

  int byName(String a, String b) {
    final c = a.toLowerCase().compareTo(b.toLowerCase());
    return c != 0 ? c : a.compareTo(b);
  }

  final rows = <FileTreeRow<T>>[];
  void emit(_Node<T> node, String prefix, int depth) {
    final dirNames = node.dirs.keys.toList()..sort(byName);
    for (final name in dirNames) {
      var child = node.dirs[name]!;
      var label = name;
      while (child.files.isEmpty && child.dirs.length == 1) {
        final only = child.dirs.entries.first;
        label = '$label/${only.key}';
        child = only.value;
      }
      final path = '$prefix$label';
      final isCollapsed = collapsed.contains(path);
      rows.add(
        FileTreeRow<T>.dir(
          depth: depth,
          path: path,
          label: label,
          fileCount: child.count,
          collapsed: isCollapsed,
        ),
      );
      if (!isCollapsed) emit(child, '$path/', depth + 1);
    }
    final files = node.files.toList()..sort((a, b) => byName(a.$1, b.$1));
    for (final (name, item) in files) {
      rows.add(
        FileTreeRow<T>.file(
          depth: depth,
          path: '$prefix$name',
          label: name,
          item: item,
        ),
      );
    }
  }

  emit(root, '', 0);
  return rows;
}

/// Items whose path lies inside folder [dir].
List<T> itemsUnder<T>(
  Iterable<T> items,
  String Function(T) pathOf,
  String dir,
) {
  final prefix = '$dir/';
  return [
    for (final i in items)
      if (pathOf(i).startsWith(prefix)) i,
  ];
}
