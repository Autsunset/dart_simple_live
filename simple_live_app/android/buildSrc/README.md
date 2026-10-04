# Flutter Android SyncFence backport

Flutter 3.44.0's two texture consumers call `Image.getFence()` and wait on it,
but leave the resulting `SyncFence` open until Java GC. Live video can exhaust
the process file descriptor limit before GC runs. Our Android release test
showed approximately 1,500 extra `sync_file` descriptors per minute.

[Flutter PR #188313](https://github.com/flutter/flutter/pull/188313) fixes this
with try-with-resources. It merged on 2026-06-24, after our SDK release.

`CloseSyncFenceVisitorFactory` uses AGP's dependency instrumentation to replace
only `waitOnFence(Image)` in the two affected Flutter embedding classes. The
replacement calls the app's `SyncFenceFix.waitOnFence`, which implements the
upstream fix. All other engine code and the rendering path remain unchanged.
No SDK files, cached dependencies, or prebuilt engine binaries are modified.

The transform checks the method signature and fails the build if a selected
class no longer matches. When upgrading Flutter, confirm that both methods in
`FlutterRenderer.java` close their fences, then remove the factory, helper,
and the `androidComponents` registration in `app/build.gradle.kts`. Verify
continuous video playback, FD counts, background/resume, and room disposal on
Android release builds before removing the backport.
