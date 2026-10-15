import 'package:flutter_test/flutter_test.dart';
import 'package:overlap_app/core/network/async_request_gate.dart';

void main() {
  test('request gate never exceeds configured concurrency and releases after errors', () async {
    const limit = 3;
    final gate = AsyncRequestGate(limit);
    var active = 0;
    var peak = 0;
    final tasks = List.generate(
      11,
      (index) => gate.run(() async {
        active++;
        if (active > peak) peak = active;
        await Future<void>.delayed(const Duration(milliseconds: 2));
        active--;
        if (index == 7) throw StateError('mock');
        return index;
      }),
    );
    final results = await Future.wait(
      tasks.map((task) async {
        try {
          return await task;
        } on StateError {
          return -1;
        }
      }),
    );
    expect(peak, lessThanOrEqualTo(limit));
    expect(results, hasLength(11));
    expect(active, 0);
  });
}
