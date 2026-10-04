# Android 播放稳定性排查（2026-10-03）

反馈：小米平板 5 Pro，各平台在无人操作、持续播放时随机退出；暂无该设备崩溃堆栈。
本次修复可确认的代码缺陷，但不能据此认定已定位或彻底解决该设备的闪退。

## 上游核查

- 原项目 master 与本地基线同为 `ba828e6783`。
- [PR #887](https://github.com/xiaoyaocz/dart_simple_live/pull/887)：未合并，包含后台恢复、消息内存清理等改动，同时涉及大量功能扩展。本次仅参考其风险点，没有整体合并。
- [PR #898](https://github.com/xiaoyaocz/dart_simple_live/pull/898)：未合并，解决 Windows 多实例数据库锁问题，与此次 Android 场景不符。
- [media-kit PR #1356](https://github.com/media-kit/media-kit/pull/1356)：未合并，视频控制器释放后排队的回调仍访问播放器。本次移植防护并补充异步等待后的检查。
- [media-kit PR #1424](https://github.com/media-kit/media-kit/pull/1424)：已关闭但未合并，本地先前已采用其延后关闭 NativeCallable 的补丁，继续保留。
- [media-kit issue #1420](https://github.com/media-kit/media-kit/issues/1420)：原生属性调用越界读取。检查本地 1.2.6 源码确认 `MPV_FORMAT_FLAG` 分配了单字节 `Bool`，而 libmpv 要求 C `int`；本次改为 `Int32` 并保证释放。
- [media-kit issue #1391](https://github.com/media-kit/media-kit/issues/1391)：部分 Android 设备播放时文件描述符泄漏。评论修正了最初的 ImageReader 推测，不能直接认定是小米平板的根因；本次记录 FD 数量供设备复测判断，没有盲目改换播放器二进制或解码器。
- [Flutter issue #188161](https://github.com/flutter/flutter/issues/188161) / [PR #188313](https://github.com/flutter/flutter/pull/188313)：引擎每帧获取 `SyncFence` 后未显式关闭，可能在 Java GC 前耗尽文件描述符。修复已于 2026-06-24 合并，但当前 Flutter 3.44.0 源码仍缺失。本次 Android release 实测复现了对应的 FD 增长。

## 本地修复

- mpv 布尔属性使用正确的原生内存宽度；事件回调失效后不再读取原生句柄。
- 视频控制器停止执行释放后排队的属性更新、画面尺寸回调及平台消息。
- 使用 Android Gradle 的类变换接口，在 APK 构建中将 Flutter 两处 `waitOnFence` 替换为上游同等的 try-with-resources 实现，等待后立即关闭栅栏；保留原有 ImageReader 视频输出，不修改全局 SDK。具体实现与移除条件见 `simple_live_app/android/buildSrc/README.md`。
- Android 使用 Skia 兼容渲染。测试容器使用 Impeller 时另外复现了 AMD/Mesa 驱动 GPU page fault / SIGABRT，堆栈落在 `libgallium_dri.so`；这和栅栏 FD 积压是两个不同的问题，也不能认定与小米的 Adreno 驱动相同。[Flutter 官方提供关闭 Impeller 的配置](https://docs.flutter.dev/perf/impeller#android)。
- 播放器打开、停止、切换和销毁按顺序执行；关闭后拒绝新任务，过期直播间请求不再执行。
- 合并同一次故障的 error/completed 事件，延时重试，每条线路最多重试两次；换房间、清晰度、线路或退出时取消旧重试。
- 聊天自动滚动时最多 200 条，上滑后最多 500 条，SC 最多 100 条且移除过期项；合并滚动回调并响应系统内存压力。
- WebSocket 握手、回调和重连使用连接代次隔离；关闭后不再复活，连接错误从握手开始即被接收，重试有上限。
- 退出时释放滚动控制器、定时器和订阅；后台返回时恢复弹幕动画。

## 闪退记录

默认在本机保存，不上传：

- `crash.log`：Dart/Flutter 未捕获异常，以及 Android 11+ 提供的最近五次进程退出原因、信号状态和退出时内存数据。
- `playback-health.log`：直播间打开期间每 60 秒记录进程 RSS、FD 数量、消息数量和播放状态，不记录 Cookie 或播放 URL。
- 每类文件最多 256 KiB，保留一个 `.previous.log`，总计最多约 1 MiB。

如再次退出，重新打开应用，在「设置 → 其他设置 → 日志列表」导出这两类日志即可。
不需要预先启用详细日志。原生崩溃的完整堆栈仍可能需要 adb logcat/tombstone；
Android 退出原因属于系统提供的诊断信息，不保证每次都有完整记录。

## 验证

- 核心 WebSocket 回归测试 6 项通过，使用本地 HTTP/WebSocket 服务，不依赖直播网站。
- App 回归测试 7 项通过，覆盖任务顺序、过期任务、失败后清理、消息上限和重试取消。
- 核心修改静态检查通过；App 静态检查仅剩原有 3 条 `onReorder` 弃用提示。
- Android release 构建通过；在 Android 16 / x86_64 Redroid 容器中确认 B 站、斗鱼播放和弹幕正常，退出后重新进入直播间进程仍存活。
- 回补引擎栅栏修复前，斗鱼 release 连续播放约 11 分钟，FD 曾从 1,355 增至 2,831、2,640 增至 4,139，约每分钟新增 1,500 个，主要为 `anon_inode:sync_file`；Java GC 会周期性降回较低值，内存并非单调增长。这里未实际触发崩溃，但确认了有耗尽 FD 风险的代码路径。
- 回补后，同一环境 0–150 秒每 30 秒采样，FD 均为 184，`sync_file` 均为 28；后台降至 152 / 11，恢复后为 186 / 31。已检查变换后的两个引擎类与 release 混淆映射，确认修复实际进入 APK。后续出现的容器 GPU 驱动崩溃促使切换 Skia。
- 已验证重启后 `crash.log` 正确记录 native crash（reason=5、status=6）及手动停止（reason=10），无需开启详细日志。

本地测试没有小米平板 5 Pro，也没有复现用户这次随机退出。ARM64 安装包仍需在该平板持续观看验证。

## 最终安装包验证

最终 Skia + 引擎栅栏修复版本在同一 Android 16 容器中完成 4 分钟、每 30 秒一次的 FD 采样，覆盖持续播放、后台恢复和连续 3 次退出/重新进入直播间，进程 PID 全程不变，无新增 native crash 或未捕获 Flutter 异常。前台 FD 为 182–193，后台为 152–153；`sync_file` 为 10–37，没有再出现修复前约 1,500 个/分钟的累积。

这属于有限时长的容器验证，不等同于小米平板 5 Pro 的长期稳定性验证。

安装包：`dist/SimpleLive-1.11.9-android-arm64-v8a-selfsigned.apk`，约 41.1 MB。
与本地上一版 1.11.8 使用相同签名，版本号递增，可覆盖安装。

SHA-256：`c91e348b25929b9a7a4d2279c9e6c64e6a5e3db5c7150d4c7749e643c3a105f3`
