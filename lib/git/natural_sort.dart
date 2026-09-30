/// Compares [a] and [b] with runs of digits compared as numbers, so
/// `ticket-2` sorts before `ticket-10`. Case-insensitive, ties broken by
/// plain comparison.
int compareNatural(String a, String b) {
  final digits = RegExp(r'\d+|\D+');
  final pa = digits.allMatches(a.toLowerCase()).map((m) => m[0]!).toList();
  final pb = digits.allMatches(b.toLowerCase()).map((m) => m[0]!).toList();
  for (var i = 0; i < pa.length && i < pb.length; i++) {
    final x = pa[i], y = pb[i];
    final nx = int.tryParse(x), ny = int.tryParse(y);
    final c = nx != null && ny != null
        ? (nx != ny ? nx.compareTo(ny) : x.length.compareTo(y.length))
        : x.compareTo(y);
    if (c != 0) return c;
  }
  final c = pa.length.compareTo(pb.length);
  return c != 0 ? c : a.compareTo(b);
}
