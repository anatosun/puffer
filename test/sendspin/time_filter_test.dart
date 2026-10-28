import 'package:flutter_test/flutter_test.dart';
import 'package:puffer/sendspin/time_filter.dart';

void main() {
  test('measurement and max error follow the specification', () {
    // Client sends at 1000, server receives at 5600 and replies at 5700, client receives at 1500.
    expect(TimeFilter.measurementOf(1000, 5600, 5700, 1500), 4400);
    expect(TimeFilter.maxErrorOf(1000, 5600, 5700, 1500), 200);
  });

  test('converges on a constant offset and converts both ways', () {
    final filter = TimeFilter();
    const offset = 1234567;
    var t = 1000000;
    for (var i = 0; i < 50; i++) {
      // A symmetric round trip of 2 ms.
      filter.addExchange(t, t + offset + 1000, t + offset + 1100, t + 2100);
      t += 100000;
    }
    expect(filter.converged, isTrue);
    expect(filter.offset, closeTo(offset, 1));
    final server = filter.serverTime(t);
    expect(filter.clientTime(server), closeTo(t, 1));
  });

  test('discards out-of-order and zero-error measurements', () {
    final filter = TimeFilter()..update(10, 100, 1000);
    filter.update(99999, 100, 1000);
    filter.update(99999, 0, 2000);
    expect(filter.count, 1);
    expect(filter.offset, 10);
  });

  test('tracks drift', () {
    final filter = TimeFilter();
    // The server clock runs 50 ppm fast.
    for (var i = 0; i < 300; i++) {
      final t = 1000000 + i * 1000000;
      final offset = 5000 + (t * 50e-6).round();
      filter.update(offset, 500, t);
    }
    expect(filter.drift, closeTo(50e-6, 5e-6));
  });
}
