package com.xycz.simple_live;

import android.hardware.SyncFence;
import android.media.Image;
import androidx.annotation.RequiresApi;
import java.io.IOException;

/** flutter/flutter#188313, applied without replacing the application's SDK. */
public final class SyncFenceFix {
    private SyncFenceFix() {}

    @RequiresApi(33)
    public static void waitOnFence(Image image) {
        try (SyncFence fence = image.getFence()) {
            fence.awaitForever();
        } catch (IOException ignored) {
            // Matches Flutter: unavailable fences do not prevent rendering.
        }
    }
}
