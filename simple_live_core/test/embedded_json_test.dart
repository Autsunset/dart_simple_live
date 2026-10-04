import 'dart:convert';
import 'dart:io';
import 'package:simple_live_core/src/common/embedded_json.dart';
import 'package:test/test.dart';

void main() {
  test(
    'captured Pace category payload parses without surrounding metadata',
    () {
      final html = File(
        'test/fixtures/douyin_categories.html',
      ).readAsStringSync();
      final categories = extractNextDataArray(html, 'categoryData');
      expect(categories.length, greaterThan(5));
      expect(categories.any((c) => c['partition']['title'] == '游戏'), isTrue);
    },
  );

  test('category array is isolated from following flight records', () {
    final categories = [
      {
        'partition': {'title': 'game [test] "quoted" \\ path', 'id_str': '1'},
        'sub_partition': [
          {
            'partition': {'title': '英雄联盟'},
            'sub_partition': [],
          },
        ],
      },
    ];
    final data =
        '1:${jsonEncode({'pathname': '/', 'categoryData': categories})},"\$undefined"]}\n';
    final html = '<script>self.__next_f.push([1,${jsonEncode(data)}])</script>';
    expect(extractNextDataArray(html, 'categoryData'), categories);
  });
  test('plain JSON and multiple flight chunks work', () {
    expect(
      extractNextDataArray('{"categoryData" : [1,[2,3]]}', 'categoryData'),
      [
        1,
        [2, 3],
      ],
    );
    final html =
        '<script>self.__next_f.push([1,"irrelevant"])</script>'
        '<script>self.__next_f.push([1,${jsonEncode('{"categoryData":[]}')}])</script>';
    expect(extractNextDataArray(html, 'categoryData'), isEmpty);
  });
  test('missing and truncated category data fail clearly', () {
    expect(
      () => extractNextDataArray('<html></html>', 'categoryData'),
      throwsFormatException,
    );
    expect(
      () => extractNextDataArray(
        '{"categoryData":[{"title":"]"}',
        'categoryData',
      ),
      throwsFormatException,
    );
  });
}
