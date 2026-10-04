// SPDX-License-Identifier: GPL-2.0-or-later
package android.view;

import android.content.Context;
import java.lang.reflect.Field;
import sun.misc.Unsafe;

/** Tests production Java dispatch and owned MotionEvent snapshots without GTK.
 * Native capture state is an explicit observed double; the separate real-X11
 * C fixture tests actual native grabbing, motion, focus and release. */
public final class AndroidPointerCaptureProbe {
    private static final class ProbeView extends View {
        boolean captured;
        int fallbacks, notifications;
        private ProbeView(Context context) { super(context); }
        @Override public boolean hasPointerCapture() { return captured; }
        @Override public boolean onCapturedPointerEvent(MotionEvent event) { fallbacks++; return true; }
        @Override public void onPointerCaptureChange(boolean captured) { notifications++; }
        @Override protected void finalize() {} // This fixture creates no GTK object.
    }
    private static void require(boolean condition, String message) {
        if (!condition) throw new AssertionError(message);
    }
    public static void main(String[] args) throws Exception {
        Field allocatorField = Unsafe.class.getDeclaredField("theUnsafe");
        allocatorField.setAccessible(true);
        Unsafe allocator = (Unsafe) allocatorField.get(null);
        ProbeView view = (ProbeView) allocator.allocateInstance(ProbeView.class);
        final int[] calls = {0};
        MotionEvent move = new MotionEvent(InputDevice.SOURCE_MOUSE_RELATIVE,
            MotionEvent.ACTION_MOVE, 42, 12, -7, 12, -7, 0, 1, 3, 2, 12, -7);
        view.setOnCapturedPointerListener((target, event) -> {
            require(target == view && event == move, "listener receives original snapshot");
            calls[0]++;
            return true;
        });
        require(!view.dispatchCapturedPointerEvent(move) && calls[0] == 0, "no dispatch without capture");
        view.captured = true;
        require(view.dispatchCapturedPointerEvent(move) && calls[0] == 1 && view.fallbacks == 0,
            "consuming listener precedes fallback even on disabled view");
        view.setOnCapturedPointerListener((target, event) -> false);
        require(view.dispatchCapturedPointerEvent(move) && view.fallbacks == 1, "unhandled listener reaches fallback");
        view.setOnCapturedPointerListener(null);
        require(view.dispatchCapturedPointerEvent(move) && view.fallbacks == 2, "null listener preserves fallback");
        view.setOnCapturedPointerListener((target, event) -> { throw new IllegalStateException("fixture"); });
        try { view.dispatchCapturedPointerEvent(move); throw new AssertionError("listener exception swallowed"); }
        catch (IllegalStateException expected) { require(view.fallbacks == 2, "exception stops fallback"); }
        view.dispatchPointerCaptureChanged(true);
        require(view.notifications == 1, "capture change reaches overridable callback");
        require(move.getSource() == 0x20004 && move.getToolType(0) == MotionEvent.TOOL_TYPE_MOUSE,
            "real mouse source/tool metadata");
        require(move.getButtonState() == 3 && move.getActionButton() == 2, "real button metadata");
        require(move.getAxisValue(MotionEvent.AXIS_RELATIVE_X) == 12
            && move.getAxisValue(MotionEvent.AXIS_RELATIVE_Y, 0) == -7, "relative axes");
        require(move.getRawX() == move.getX() && move.getRawY() == move.getY(), "captured raw axes are relative");
        MotionEvent copy = MotionEvent.obtain(move);
        require(copy.getAxisValue(MotionEvent.AXIS_VSCROLL) == 1 && copy.getButtonState() == 3,
            "copy retains scroll and mouse metadata");
        move.coords[0] = 99;
        require(copy.getX() == 12 && copy.getY() == -7, "copy owns coordinate snapshot");
        copy.recycle();
        MotionEvent touch = MotionEvent.obtain(1, 2, MotionEvent.ACTION_MOVE, 3, 4, 0);
        require(touch.getActionButton() == 0 && touch.getAxisValue(MotionEvent.AXIS_RELATIVE_X) == 0
            && touch.getAxisValue(MotionEvent.AXIS_VSCROLL) == 0
            && touch.getToolType(0) == MotionEvent.TOOL_TYPE_FINGER,
            "pooled mouse metadata does not leak into touch event");
        touch.recycle();
        System.out.println("ANDROID-POINTER-CAPTURE-PASS listener=fallback source=mouse-relative metadata=owned pool=reset");
    }
}
