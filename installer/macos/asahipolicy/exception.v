// SPDX-License-Identifier: GPL-2.0-or-later
module asahipolicy

import cpythonapi as py

@[heap]
struct SavedException {
	api         &py.Api
	kind        py.Ref
	value       py.Ref
	trace       py.Ref
	name        string
	description string
mut:
	retired bool
}

struct SdkError {
	saved &SavedException
}

fn (failure SdkError) msg() string { return failure.saved.description }

fn (failure SdkError) code() int { return 1 }

fn (failure SdkError) close() {
	mut saved := unsafe { failure.saved }
	if saved.retired { return }
	saved.retired = true
	for reference in [saved.kind, saved.value, saved.trace] {
		if reference != unsafe { nil } { saved.api.dec(reference) }
	}
}

fn (failure SdkError) restore() {
	mut saved := unsafe { failure.saved }
	if saved.retired { return }
	saved.retired = true
	// PyErr_Restore consumes the references, including a null traceback.
	saved.api.error_restore(saved.kind, saved.value, saved.trace)
}

fn raw_text(api &py.Api, reference py.Ref) string {
	if reference == unsafe { nil } { return '' }
	mut length := isize(0)
	data := api.unicode_data(reference, &length)
	if data == unsafe { nil } || length < 0 || length > 64 * 1024 * 1024 { return '' }
	return unsafe { tos(&u8(data), int(length)).clone() }
}

fn sdk_error(kind py.Ref, value py.Ref, trace py.Ref, api &py.Api) IError {
	for reference in [kind, value, trace] { if reference != unsafe { nil } { api.inc(reference) } }
	mut name := 'RuntimeError'
	mut description := 'CPython SDK operation failed'
	if kind != unsafe { nil } {
		label := api.attribute(kind, c'__name__')
		if label != unsafe { nil } {
			name = raw_text(api, label)
			api.dec(label)
		}
	}
	if value != unsafe { nil } {
		label := api.stringify(value)
		if label != unsafe { nil } {
			description = raw_text(api, label)
			api.dec(label)
		}
	}
	if api.error_occurred() != unsafe { nil } {
		mut extra_kind, extra_value, extra_trace := py.Ref(unsafe { nil }), py.Ref(unsafe { nil }), py.Ref(unsafe { nil })
		api.error_fetch(&extra_kind, &extra_value, &extra_trace)
		for reference in [extra_kind, extra_value, extra_trace] {
			if reference != unsafe { nil } { api.dec(reference) }
		}
	}
	return SdkError{ saved: &SavedException{ api: api, kind: kind, value: value, trace: trace, name: name, description: description } }
}
