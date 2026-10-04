# Local media_kit_video patch

Based on hosted `media_kit_video` 2.0.1 (MIT licensed). Examples and upstream
tests are omitted; runtime sources and platform implementations are retained.

Backports the disposal guards from unmerged
[media-kit PR #1356](https://github.com/media-kit/media-kit/pull/1356).
Android surface updates and native video size callbacks queued behind the
controller lock must stop once disposal starts. Also checks after asynchronous
boundaries, before each player property write, and on late platform messages.
The native player's disposed flag covers the interval before video cleanup runs.

Remove this override when a released version includes equivalent protections.
Android release testing on affected hardware is still required for native crashes.
