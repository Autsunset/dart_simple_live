# Simple Live 1.12.0

本版基于原项目 `ba828e6783b176ea5709fcd09f0eb01dfaceeb51`，整理此前 Android 稳定性补丁，并修复本轮在线测试发现的分类接口问题。发布平台为 Android 手机/平板。

## 用户可见的改进

- 首页与分类记住同一个直播平台，点击或滑动切换后保持一致（移植 PR #878）。
- B 站分类改用可用的分类直播接口，修复空数据导致的异常；保留分页及封面回退（参考 PR #887）。
- 抖音分类适配 Pace/Next.js 页面数据，完整解析分类数组，支持游戏三级分区；搜索 API 使用用户已设置的 Cookie（参考 PR #901）。
- 高频聊天消息每 150 ms 批量更新一次，每批只发布一次列表变化；保留顺序、屏蔽规则、最新 200 条/查看历史时 500 条上限。预编译屏蔽正则，取消关闭/切房后的待处理消息。
- 上滑查看聊天后，手动滚回底部即可恢复自动跟随（参考 PR #887）。
- SC 按消息身份合并 API 与 WebSocket 数据，修复重复展示；卡片使用稳定 key，更新内容/到期时间后同步倒计时。画面最多显示三个 SC，15 秒展示结束后不会因其他消息更新反复出现。
- 刷新/搜索的新请求可覆盖旧请求，旧结果和旧错误不再覆盖新页面；页面关闭后停止更新并释放滚动资源。
- 斗鱼线路同时获取并保持服务端排序，某条 CDN 失败时仍保留其他可用线路；切换清晰度重新签名，原生签名运行时在异常时也正确释放。

## Android 稳定性

保留 [1.11.9 稳定性排查](stability-2026-10-03.md) 的播放器操作队列、原生回调释放防护、mpv 布尔属性内存宽度修复、Flutter SyncFence FD 修复、消息上限、有限次数重试和本地崩溃/健康日志。

App 和核心库的依赖锁文件纳入版本控制，固定本轮验证的依赖解析结果。构建过程中 Flutter 添加的 Android Kotlin/DSL 兼容配置纳入源码；vendored 播放依赖保留原 MIT 许可证与 `PATCHES.md`。日志默认在本机保存，可在设置中的日志列表导出。

## 上游审查（2026-10-05）

原项目 issue 功能已关闭；GitHub REST 与搜索 API 均没有返回历史 issue，无法声称完成了历史 issue 的全面审查。转而检查所有九个开放 PR、其引用的反馈，以及活跃 fork June6699 的公开问题。

| PR | 当前状态 | 本版处理 |
| --- | --- | --- |
| [#878](https://github.com/xiaoyaocz/dart_simple_live/pull/878) | 开放、未合并 | 移植首页/分类共享平台 TabController，补点击/滑动及释放验证 |
| [#877](https://github.com/xiaoyaocz/dart_simple_live/pull/877) | 开放、未合并 | App 的恢复弹幕逻辑已包含于此前稳定性补丁，继续保留 |
| [#887](https://github.com/xiaoyaocz/dart_simple_live/pull/887) | 开放、未合并；1180 个文件 | 参考聊天合帧、滚动恢复、SC 去重、B站分类及斗鱼签名刷新；按本地生命周期防护重新实现相关部分 |
| [#901](https://github.com/xiaoyaocz/dart_simple_live/pull/901) | 开放、未合并 | 移植分类解析/三级分区与搜索 Cookie 的相关修复；增强外层字符串解码，兼容当前 Pace 页面 |
| [#881](https://github.com/xiaoyaocz/dart_simple_live/pull/881) | 开放、未合并 | 观看历史快捷切换可用作后续功能，本版优先修复播放与分类故障 |
| [#898](https://github.com/xiaoyaocz/dart_simple_live/pull/898) | 开放、未合并 | Windows 多实例/后台纯音频需 Windows 运行验证，留待桌面版处理 |
| [#876](https://github.com/xiaoyaocz/dart_simple_live/pull/876) | 开放、未合并 | iOS 快捷指令及深度链接需各平台原生入口验证，留待专项版本 |
| [#900](https://github.com/xiaoyaocz/dart_simple_live/pull/900) / [#895](https://github.com/xiaoyaocz/dart_simple_live/pull/895) | 开放、未合并 | CI 提案缺少本 fork 的签名、SDK和补丁验证；本版通过本机构建发布 |

[June6699 issue #137](https://github.com/June6699/dart_simple_live/issues/137) 提供了高热直播间 UI 掉帧线索。本版验证了消息发布次数下降，尚未在其反馈的华为设备上测量实际 FPS，不能认定完全解决该反馈。

[June6699 issue #138](https://github.com/June6699/dart_simple_live/issues/138) 的斗鱼高档清晰度/帧率问题继续列为未解决。匿名在线探测中，服务器列出「原画1080P60」，实际流为 960×540、25 fps；请求保留了所选 rate，仍不能保证服务端返回标签标示的画质。问题中 6657 房间的房间信息接口本轮还返回 HTML；不能以推荐房间的成功代替该房间的验证。

## 验证结果

- App 回归 14 项通过：播放任务顺序/释放、过期任务、重试合并与取消、聊天突发批量发布/过滤/关闭、滚动恢复、SC 合并/更新/不重播、刷新竞态、共享平台点击/滑动及释放。
- 核心离线回归 16 项通过：WebSocket 本地服务测试、斗鱼并发线路/失败隔离/签名更新、分类错误与分页、真实页面脱敏分类 fixture、转义与嵌套数组、搜索 Cookie 保留。
- 在线核心全套初次运行：32/36 通过；失败为 B站分类、抖音分类、其依赖的分类列表和匿名抖音搜索。修复后重跑四项分类测试，4/4 通过。匿名抖音搜索仍返回空结果，未宣称该项通过；App 保留原有网页搜索入口。
- 修改的核心库及测试静态检查通过；App 静态检查无错误/警告，保留原有三条 `onReorder` 弃用提示。
- Android release 三种 ABI 均构建成功，APK 签名验证通过，每包包含对应 ABI 的 QuickJS 原生库。签名证书 SHA-256 与本 fork 1.11.9 一致：`b6bff70c0d93b6c3cf9e621103152c6d0976c3b48ca20aa21493df27f83a2a6f`。
- Android 16 / x86_64 Redroid 最终 APK：B站、斗鱼实际画面与弹幕正常；4分钟、每30秒采样一次，覆盖持续播放、后台/恢复、刷新、退出并切到斗鱼，进程 PID 全程为 38163，FD 164–194、`sync_file` 13–35，RSS 约 313–444 MiB。采样后退出原因记录未新增 native crash；属于有限时长容器验证。

首次 1.12.0 容器测试出现 AMD/Mesa `libgallium_dri.so` SIGABRT；该环境在之前版本也出现过同类崩溃，不能认定为小米设备的故障原因，也不能宣称图形驱动问题已解决。ARM64 包尚未在小米平板 5 Pro 上完成长期验证。

## 安装包

| 架构 | 文件 | 大小 |
| --- | --- | --- |
| ARM64（多数手机、平板） | `SimpleLive-1.12.0-android-arm64-v8a-selfsigned.apk` | 41,144,429 bytes |
| ARMv7 | `SimpleLive-1.12.0-android-armeabi-v7a-selfsigned.apk` | 38,686,297 bytes |
| x86_64 | `SimpleLive-1.12.0-android-x86_64-selfsigned.apk` | 46,131,171 bytes |

与此前本地 selfsigned 版本可覆盖安装；最低 Android 7.0/API 24。
下载地址：https://github.com/Autsunset/dart_simple_live/releases/tag/android-v1.12.0
校验值见发布附件 `SimpleLive-1.12.0-SHA256SUMS.txt`。

## 本地复现构建

环境：Flutter 3.44.0 / Dart 3.12.0、Android SDK 36 / NDK 28.2.13676358、可用的 Java、Android 签名配置 `android/key.properties`（只在本机保存）。

```sh
cd simple_live_app
flutter pub get
flutter test
flutter analyze --no-fatal-infos
flutter build apk --release --split-per-abi
```

Linux 上运行 Dart/Flutter 测试需要 host C 编译器供 QuickJS native-assets hook 使用。本轮使用 NDK 中默认目标为 `x86_64-unknown-linux-gnu` 的 clang，通过临时 PATH 添加工具目录；未修改全局编译器或 Flutter SDK。在线测试需要能正常访问对应直播平台，与离线回归分开记录。
