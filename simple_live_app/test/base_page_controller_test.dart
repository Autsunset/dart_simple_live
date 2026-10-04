import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:simple_live_app/app/controller/base_controller.dart';

class _Page extends BasePageController<int> {
  final requests = <({int page, Completer<List<int>> result})>[];
  final errors = <Object>[];
  @override
  Future<List<int>> getData(int page, int pageSize) {
    final result = Completer<List<int>>();
    requests.add((page: page, result: result));
    return result.future;
  }

  @override
  void handleError(Object exception, {bool showPageError = false}) {
    errors.add(exception);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('refresh supersedes a slower load and keeps pagination correct',
      () async {
    final page = _Page();
    final old = page.loadData();
    final fresh = page.refreshData();
    expect(page.requests.map((r) => r.page), [1, 1]);
    page.requests[0].result.complete([1]);
    await old;
    expect(page.list, isEmpty);
    expect(page.loadding, isTrue);
    page.requests[1].result.complete([2]);
    await fresh;
    expect(page.list, [2]);
    final more = page.loadData();
    expect(page.requests.last.page, 2);
    page.requests.last.result.complete([3]);
    await more;
    expect(page.list, [2, 3]);
    page.onDelete();
  });
  test('stale errors and completion after disposal cannot mutate the page',
      () async {
    final page = _Page();
    final old = page.loadData();
    final fresh = page.refreshData();
    page.requests[0].result.completeError(StateError('stale'));
    await old;
    expect(page.errors, isEmpty);
    expect(page.loadding, isTrue);
    page.onDelete();
    page.requests[1].result.complete([2]);
    await fresh;
    expect(page.list, isEmpty);
    expect(page.currentPage, 1);
  });
}
