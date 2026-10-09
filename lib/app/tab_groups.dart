/// A named, colored group of repository tabs. Its tabs sit next to each
/// other in the tab strip; collapsed, only its chip shows.
class TabGroup {
  TabGroup({
    required this.id,
    this.name = '',
    this.color = 0,
    this.collapsed = false,
  });

  /// Stable across sessions (the settings refer to it).
  final String id;
  String name;

  /// Index into [groupColors].
  int color;
  bool collapsed;

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'color': color,
    'collapsed': collapsed,
  };

  static TabGroup? fromJson(Object? j) {
    if (j is! Map || j['id'] is! String) return null;
    return TabGroup(
      id: j['id'] as String,
      name: j['name'] is String ? j['name'] as String : '',
      color: j['color'] is num ? (j['color'] as num).toInt() : 0,
      collapsed: j['collapsed'] == true,
    );
  }
}

/// Names of the group colors, in [AppPalette.groups] order.
const groupColorNames = [
  'Blue',
  'Green',
  'Yellow',
  'Orange',
  'Red',
  'Pink',
  'Purple',
  'Cyan',
  'Grey',
];
