import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:simple_live_app/modules/live_room/player/player_operation_queue.dart';

void main() {
  test('disposal waits for active work and discards pending and new work',
      () async {
    final queue = PlayerOperationQueue();
    final started = Completer<void>();
    final release = Completer<void>();
    final calls = <String>[];
    final active = queue.run(() async {
      calls.add('open');
      started.complete();
      await release.future;
      calls.add('opened');
    });
    await started.future;
    final pending = queue.run(() async => calls.add('jump'));
    final disposed = queue.close(() async => calls.add('dispose'));
    final duplicate = queue.close(() async => calls.add('dispose again'));
    await queue.run(() async => calls.add('after close'));
    expect(calls, ['open']);
    release.complete();
    await Future.wait([active, pending, disposed, duplicate]);
    expect(calls, ['open', 'opened', 'dispose']);
  });

  test('failed operation does not poison later work or disposal', () async {
    final queue = PlayerOperationQueue();
    await expectLater(queue.run(() async => throw StateError('open failed')),
        throwsStateError);
    final calls = <String>[];
    await queue.run(() async => calls.add('next'));
    await queue.close(() async => calls.add('dispose'));
    expect(calls, ['next', 'dispose']);
  });

  test('room generation is checked when queued work actually starts', () async {
    final queue = PlayerOperationQueue();
    final release = Completer<void>();
    final started = Completer<void>();
    var generation = 1;
    final calls = <String>[];
    final active = queue.run(() async {
      started.complete();
      await release.future;
    });
    await started.future;
    final stale = queue.run(() async => calls.add('old room'),
        isCurrent: () => generation == 1);
    generation++;
    final current = queue.run(() async => calls.add('new room'),
        isCurrent: () => generation == 2);
    release.complete();
    await Future.wait([active, stale, current]);
    expect(calls, ['new room']);
    await queue.close(() async {});
  });
}
