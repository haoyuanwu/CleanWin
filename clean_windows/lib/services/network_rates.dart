/// Interface counter deltas; never turn failures, reconnects or first reads into
/// zero-speed samples. Counters are per adapter to avoid aggregate reset spikes.
class NetworkRates {
  final Map<String, ({int rx, int tx})> _previous = {};
  int? _stamp;
  void reset() {
    _previous.clear();
    _stamp = null;
  }

  ({double? down, double? up, int adapters}) read(dynamic rows, dynamic ticks) {
    if (rows is! List || ticks is! num || !ticks.isFinite) {
      reset();
      return (down: null, up: null, adapters: 0);
    }
    final next = <String, ({int rx, int tx})>{};
    for (final row in rows.whereType<Map>()) {
      final id = row['Id'];
      final rx = row['Rx'];
      final tx = row['Tx'];
      if (id is! String ||
          id.isEmpty ||
          rx is! num ||
          tx is! num ||
          !rx.isFinite ||
          !tx.isFinite ||
          rx < 0 ||
          tx < 0) {
        continue;
      }
      next[id] = (rx: rx.toInt(), tx: tx.toInt());
    }
    final stamp = ticks.toInt();
    final elapsed = _stamp == null ? null : (stamp - _stamp!) / 10000000;
    double down = 0, up = 0;
    var matched = 0;
    if (elapsed != null && elapsed > 0 && elapsed <= 10) {
      for (final entry in next.entries) {
        final old = _previous[entry.key];
        if (old == null || entry.value.rx < old.rx || entry.value.tx < old.tx) {
          continue;
        }
        down += (entry.value.rx - old.rx) / elapsed;
        up += (entry.value.tx - old.tx) / elapsed;
        matched++;
      }
    }
    _previous
      ..clear()
      ..addAll(next);
    _stamp = stamp;
    return (
      down: matched == 0 ? null : down,
      up: matched == 0 ? null : up,
      adapters: next.length,
    );
  }
}
