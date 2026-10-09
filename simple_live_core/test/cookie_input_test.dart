import 'package:simple_live_core/simple_live_core.dart';
import 'package:test/test.dart';

void main() {
  final now = DateTime.utc(2026, 1, 1);
  final api = Uri.parse('https://www.douyu.com/lapi/live/getH5Play/1');
  const future = 4102444800;
  const header = '# Netscape HTTP Cookie File\n';

  test('keeps encoded values, host variants and HttpOnly records intact', () {
    const signed = r'token%2F%2B+raw==/$value';
    final input = [
      '# Netscape HTTP Cookie File',
      '.douyu.com\tTRUE\t/\tFALSE\t$future\tdy_did\tdevice',
      'www.douyu.com\tFALSE\t/\tFALSE\t$future\tacf_did\tdevice',
      'www.douyu.com\tFALSE\t/\tFALSE\t$future\tdy_did\tdevice',
      '#HttpOnly_www.douyu.com\tFALSE\t/\tTRUE\t$future\tacf_auth\t$signed',
      '.douyin.com\tTRUE\t/\tTRUE\t$future\tsessionid\tother-platform-secret',
    ].join('\n');
    final saved = CookieInput.normalizeForStorage(
      input,
      domain: 'douyu.com',
      now: now,
    );
    expect(saved, startsWith(header));
    expect(saved, contains('#HttpOnly_www.douyu.com\tFALSE\t/\tTRUE'));
    expect(saved, isNot(contains('other-platform-secret')));
    expect(
      CookieInput.headerFor(saved, api, now: now),
      'dy_did=device; acf_did=device; dy_did=device; acf_auth=$signed',
    );
  });

  test(
    'supports BOM, CRLF, comments, session expiry and an empty final value',
    () {
      final input =
          '\uFEFF# Netscape HTTP Cookie File\r\n'
          '# export comment\r\n\r\n'
          'www.douyu.com\tFALSE\t/\tFALSE\t0\tacf_did\tdevice\r\n'
          'www.douyu.com\tFALSE\t/\tFALSE\t0\tempty\t';
      final saved = CookieInput.normalizeForStorage(
        input,
        domain: 'douyu.com',
        now: now,
      );
      expect(
        CookieInput.headerFor(saved, api, now: now),
        'acf_did=device; empty=',
      );
    },
  );

  test(
    'recognizes files without a header and case-insensitive domain/flags',
    () {
      final input = 'WWW.DOUYU.COM\tfalse\t/\ttrue\t$future\ta\tb';
      expect(CookieInput.isNetscape(input), isTrue);
      expect(CookieInput.headerFor(input, api, now: now), 'a=b');
    },
  );

  test(
    'enforces exact domains, subdomain flags, path boundaries and secure',
    () {
      final input = [
        header.trim(),
        'douyu.com\tFALSE\t/\tFALSE\t0\tapex\tonly',
        '.douyu.com\tTRUE\t/\tFALSE\t0\tparent\tall',
        'www.douyu.com\tFALSE\t/\tTRUE\t0\tsecure\tyes',
        'www.douyu.com\tFALSE\t/lapi\tFALSE\t0\tpath\tyes',
        'www.douyu.com\tFALSE\t/lapi/live\tFALSE\t0\tspecific\tyes',
        'passport.douyu.com\tFALSE\t/\tFALSE\t0\tpassport\tprivate',
      ].join('\n');
      expect(
        CookieInput.headerFor(input, api, now: now),
        'specific=yes; path=yes; parent=all; secure=yes',
      );
      expect(
        CookieInput.headerFor(
          input,
          Uri.parse('http://www.douyu.com/lapi2'),
          now: now,
        ),
        'parent=all',
      );
      expect(
        CookieInput.headerFor(
          input,
          Uri.parse('https://m.douyu.com/'),
          now: now,
        ),
        'parent=all',
      );
      expect(
        CookieInput.headerFor(
          input,
          Uri.parse('https://douyu.com.evil.invalid/'),
          now: now,
        ),
        '',
      );
      expect(
        CookieInput.headerFor(
          input,
          Uri.parse('https://evildouyu.com/'),
          now: now,
        ),
        '',
      );
      expect(
        CookieInput.headerFor(
          input,
          Uri.parse('https://douyucdn.cn/'),
          now: now,
        ),
        '',
      );
    },
  );

  test('ignores expired entries both at import and at request time', () {
    final expires = now.millisecondsSinceEpoch ~/ 1000 + 5;
    final input =
        '$header'
        '.douyu.com\tTRUE\t/\tFALSE\t1\told\told-secret\n'
        '.douyu.com\tTRUE\t/\tFALSE\t0\tsession\tactive\n'
        '.douyu.com\tTRUE\t/\tFALSE\t$expires\tshort\tshort-secret\n';
    final saved = CookieInput.normalizeForStorage(
      input,
      domain: 'douyu.com',
      now: now,
    );
    expect(saved, isNot(contains('old-secret')));
    expect(
      CookieInput.headerFor(saved, api, now: now),
      'session=active; short=short-secret',
    );
    expect(
      CookieInput.headerFor(
        saved,
        api,
        now: now.add(const Duration(seconds: 5)),
      ),
      'session=active',
    );
  });

  test('last exact-scope entry wins, including an expired deletion', () {
    final input =
        '$header'
        '.douyu.com\tTRUE\t/\tFALSE\t0\ta\told\n'
        'www.douyu.com\tFALSE\t/\tFALSE\t0\ta\thost\n'
        '.douyu.com\tTRUE\t/\tFALSE\t0\ta\tnew\n'
        '.douyu.com\tTRUE\t/\tFALSE\t0\tgone\told\n'
        '.douyu.com\tTRUE\t/\tFALSE\t1\tgone\tdeleted\n';
    final saved = CookieInput.normalizeForStorage(
      input,
      domain: 'douyu.com',
      now: now,
    );
    expect(CookieInput.headerFor(input, api, now: now), 'a=host; a=new');
    expect(CookieInput.headerFor(saved, api, now: now), 'a=host; a=new');
  });

  test('secure cookies also apply to secure websocket URLs only', () {
    final input = '.douyin.com\tTRUE\t/webcast\tTRUE\t0\tsessionid\tfake';
    expect(
      CookieInput.headerFor(
        input,
        Uri.parse('wss://webcast3-ws-web-lq.douyin.com/webcast/im/push/v2/'),
        now: now,
      ),
      'sessionid=fake',
    );
    expect(
      CookieInput.headerFor(
        input,
        Uri.parse('ws://webcast3-ws-web-lq.douyin.com/webcast/im/push/v2/'),
        now: now,
      ),
      '',
    );
  });

  test('retains compatibility with ordinary Cookie request headers', () {
    expect(
      CookieInput.headerFor(
        ' Cookie: acf_did=device;\r\nacf_auth=a%2Fb+==; ',
        api,
      ),
      'acf_did=device; acf_auth=a%2Fb+==',
    );
    expect(CookieInput.normalizeForStorage('', domain: 'douyu.com'), '');
    expect(CookieInput.headerFor('', api), '');
    expect(
      CookieInput.headerFor('Cookie:\tacf_did=device;\tacf_auth=a==', api),
      'acf_did=device; acf_auth=a==',
    );
  });

  test(
    'wrong-platform and fully expired files do not turn into a clear operation',
    () {
      for (final input in [
        '$header.douyin.com\tTRUE\t/\tFALSE\t0\tttwid\tother-secret',
        '$header.douyu.com.evil.invalid\tTRUE\t/\tFALSE\t0\tacf_did\tevil',
        '$header.douyu.com\tTRUE\t/\tFALSE\t1\tacf_did\texpired',
        '$header# comments only\n',
      ]) {
        expect(
          () => CookieInput.normalizeForStorage(
            input,
            domain: 'douyu.com',
            now: now,
          ),
          throwsFormatException,
        );
      }
    },
  );

  test(
    'rejects malformed records without exposing credentials in exceptions',
    () {
      for (final input in [
        '.douyu.com TRUE / FALSE 0 acf_auth secret-value',
        '$header.douyu.com\tTRUE\t/\tFALSE\t0\tmissing-value-column',
        '$header.douyu.com\tTRUE\t/\tFALSE\tinvalid\tacf_auth\tsecret-value',
        '$header.douyu.com\tTRUE\t/\tINVALID\t0\tacf_auth\tsecret-value',
        '$header.douyu.com\tTRUE\t/\tFALSE\t0\tbad name\tsecret-value',
        '$header.douyu.com\tTRUE\t/\tFALSE\t0\tacf_auth\tsecret-value; injected=1',
        '$header.douyu.com\tTRUE\t/\tFALSE\t0\tacf_auth\tsecret-value\u0000',
      ]) {
        try {
          CookieInput.normalizeForStorage(input, domain: 'douyu.com', now: now);
          fail('Invalid file was accepted');
        } on FormatException catch (error) {
          expect(error.source, isNull);
          expect(error.toString(), isNot(contains('secret-value')));
        }
      }
    },
  );

  test('oversized pasted input is rejected before parsing', () {
    expect(
      () => CookieInput.normalizeForStorage(
        'a' * (CookieInput.maxLength + 1),
        domain: 'douyu.com',
      ),
      throwsFormatException,
    );
  });
}
