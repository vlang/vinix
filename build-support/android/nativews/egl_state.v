// SPDX-License-Identifier: GPL-2.0-or-later
@[translated]
module atlframework

// The software WS Canvas never makes an EGL context current. These queries
// report that state using the EGL_NO_DISPLAY / EGL_NO_CONTEXT sentinel; they
// neither create a display nor load a window-system graphics provider.
@[export: 'eglGetCurrentDisplay']
pub fn ws_egl_current_display() voidptr { return unsafe { nil } }

@[export: 'eglGetCurrentContext']
pub fn ws_egl_current_context() voidptr { return unsafe { nil } }
