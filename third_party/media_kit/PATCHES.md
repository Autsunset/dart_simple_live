# Local media_kit patch

This directory contains `media_kit` 1.2.6 (MIT licensed), with its example,
tests, and screenshots omitted. The application overrides its hosted dependency
with this copy.

The disposal change follows [media-kit PR #1424](https://github.com/media-kit/media-kit/pull/1424):
on player disposal, the `NativeCallable` remains alive until
`mpv_terminate_destroy` has stopped the mpv thread. The upstream release closes
it first and can abort an Android release process when an in-flight wakeup
arrives afterward ([issue #1443](https://github.com/media-kit/media-kit/issues/1443)).

The event loop also checks that its original lock is still registered before
each native event read. This prevents a queued or suspended callback from
reading a destroyed (or reused) mpv handle after disposal.

`MPV_FORMAT_FLAG` writes now allocate a C `int` (`Int32`) instead of a one-byte
`Bool`, as required by the bundled libmpv bindings. The old allocation causes
a four-byte read from a one-byte region, reported in
[issue #1420](https://github.com/media-kit/media-kit/issues/1420).
The remaining flag read uses `Int32` as well.

Remove the dependency override when an upstream release includes an equivalent
fix. Retest player disposal on Android before doing so.
