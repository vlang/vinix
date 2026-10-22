// SPDX-License-Identifier: GPL-2.0-or-later
@[translated]
module atlframework

// Vinix WS has no Android trace session or trace_marker sink. The NDK API
// therefore reports tracing disabled and discards events, as Android does
// when the application's tracing tag is disabled. Do not retain names or
// allocate per-thread section stacks while tracing is off.
@[export: 'ATrace_isEnabled']
pub fn ws_trace_enabled() bool {
	return false
}

@[export: 'ATrace_beginSection']
pub fn ws_trace_begin(name &char) {}

@[export: 'ATrace_endSection']
pub fn ws_trace_end() {}

@[export: 'ATrace_beginAsyncSection']
pub fn ws_trace_async_begin(name &char, cookie i32) {}

@[export: 'ATrace_endAsyncSection']
pub fn ws_trace_async_end(name &char, cookie i32) {}

@[export: 'ATrace_setCounter']
pub fn ws_trace_counter(name &char, value i64) {}
