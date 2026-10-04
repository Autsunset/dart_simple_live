# Local auto_orientation_v2 patch

This directory contains `auto_orientation_v2` 2.4.6 with its example and tests
omitted. The application overrides the hosted dependency with this copy.

The Android Gradle configuration targets Java and Kotlin 17 consistently. The
hosted release can fail a release build because its Java task targets 1.8 while
the Kotlin task inherits JVM target 21 from the current build toolchain.

Remove this override after an upstream release configures matching JVM targets.
