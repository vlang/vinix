// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module asahipolicy

import cpythonapi as py
import time

type ModelDestructor = fn (py.Ref)
type ModelCallback = fn (py.Ref, py.Ref) py.Ref

struct Model {
mut:
	refs       int = 1
	kind       string
	text       string
	number     i64
	children   []py.Ref
	attributes map[string]py.Ref
	context    voidptr
	destructor fn (py.Ref) = unsafe { nil }
	method     &py.Method  = unsafe { nil }
}

__global (
	model_live          int
	model_none          py.Ref
	model_error         string
	model_fail_tuple    bool
	model_fail_append   bool
	model_fail_capsule  bool
	model_fail_function bool
	model_events        []string
	model_pending       []py.Ref
	model_shutdowns     [][]string
	model_delays        []i64
	model_calls         [][]py.Ref
)

fn object(kind string) py.Ref {
	model_live++
	return py.Ref(&Model{ kind: kind })
}

fn model_inc(reference py.Ref) {
	mut value := unsafe { &Model(reference) }
	assert value.refs > 0
	value.refs++
}

fn model_dec(reference py.Ref) {
	mut value := unsafe { &Model(reference) }
	assert value.refs > 0
	value.refs--
	if value.refs > 0 { return }
	for child in value.children { if child != unsafe { nil } { model_dec(child) } }
	if value.destructor != unsafe { nil } { value.destructor(reference) }
	model_live--
	unsafe { free(value) }
}

fn model_int(number i64) py.Ref {
	reference := object('integer')
	mut value := unsafe { &Model(reference) }
	value.number = number
	return reference
}

fn model_read_int(reference py.Ref) i64 { return unsafe { &Model(reference) }.number }

fn model_text(data &char, length isize) py.Ref {
	reference := object('unicode')
	mut value := unsafe { &Model(reference) }
	value.text = if length == 0 { '' } else { unsafe { tos(&u8(data), int(length)).clone() } }
	return reference
}

fn model_unicode(reference py.Ref, length &isize) &char {
	value := unsafe { &Model(reference) }
	unsafe { *length = value.text.len }
	return value.text.str
}

fn model_stringify(reference py.Ref) py.Ref {
	value := unsafe { &Model(reference) }
	return model_text(value.text.str, value.text.len)
}

fn model_tuple(length isize) py.Ref {
	reference := object('tuple')
	mut value := unsafe { &Model(reference) }
	value.children = []py.Ref{len: int(length), init: py.Ref(unsafe { nil })}
	return reference
}

fn model_put_tuple(reference py.Ref, index isize, child py.Ref) i32 {
	mut value := unsafe { &Model(reference) }
	if model_fail_tuple {
		model_fail_tuple = false
		model_dec(child)
		model_error = 'SDKFailure'
		return -1
	}
	assert value.refs == 1 && index >= 0 && index < value.children.len
	value.children[int(index)] = child // consumes the separately incremented reference
	return 0
}

fn model_item(reference py.Ref, index isize) py.Ref {
	value := unsafe { &Model(reference) }
	child := value.children[int(index)]
	model_inc(child)
	return child
}

fn model_list(_ isize) py.Ref { return object('list') }

fn model_append(reference py.Ref, child py.Ref) i32 {
	if model_fail_append {
		model_fail_append = false
		model_error = 'SDKFailure'
		return -1
	}
	mut value := unsafe { &Model(reference) }
	model_inc(child)
	value.children << child
	return 0
}

fn model_dict() py.Ref { return object('dict') }

fn model_dict_put(reference py.Ref, name &char, child py.Ref) i32 {
	mut value := unsafe { &Model(reference) }
	key := unsafe { name.vstring().clone() }
	value.attributes[key] = child
	return model_append(reference, child)
}

fn model_get(reference py.Ref, name &char) py.Ref {
	value := unsafe { &Model(reference) }
	return value.attributes[unsafe { name.vstring() }] or { py.Ref(unsafe { nil }) }
}

fn model_set(reference py.Ref, name &char, child py.Ref) i32 {
	return model_dict_put(reference, name, child)
}

fn model_restore(kind py.Ref, value py.Ref, trace py.Ref) {
	for reference in model_pending { if reference != unsafe { nil } { model_dec(reference) } }
	model_pending = [kind, value, trace]
	model_error = unsafe { &Model(kind) }.text
}

fn model_size(reference py.Ref) isize { return unsafe { &Model(reference) }.children.len }

fn model_truth(reference py.Ref) i32 {
	value := unsafe { &Model(reference) }
	if value.kind == 'bad' {
		model_error = 'SDKFailure'
		return -1
	}
	return match value.kind {
		'none' { 0 }
		'integer' {
			if value.number == 0 { 0 } else { 1 }
		}
		'unicode' {
			if value.text.len == 0 { 0 } else { 1 }
		}
		'tuple', 'list', 'dict' {
			if value.children.len == 0 { 0 } else { 1 }
		}
		else { 1 }
	}
}

fn model_compare(left py.Ref, right py.Ref, operation i32) i32 {
	assert operation == 2
	if unsafe { &Model(left) }.kind == 'bad' {
		model_error = 'SDKFailure'
		return -1
	}
	l, r := unsafe { &Model(left) }, unsafe { &Model(right) }
	return if left == right || (l.kind == r.kind && l.text == r.text && l.number == r.number) {
		1
	} else {
		0
	}
}

fn model_occurred() py.Ref {
	return if model_error == '' { py.Ref(unsafe { nil }) } else { model_none }
}

fn model_fetch(kind &py.Ref, value &py.Ref, trace &py.Ref) {
	if model_pending.len > 0 {
		unsafe {
			*kind = model_pending[0]
			*value = model_pending[1]
			*trace = model_pending[2]
		}
		model_pending = []py.Ref{}
		model_error = ''
		return
	}
	mut error_type := py.Ref(unsafe { nil })
	if model_error != '' {
		error_type = object('error')
		mut state := unsafe { &Model(error_type) }
		state.text = model_error
	}
	model_error = ''
	unsafe {
		*kind = error_type
		*value = nil
		*trace = nil
	}
}

fn model_set_error(_ py.Ref, _ &char) { model_error = 'RuntimeError' }

fn model_attr(reference py.Ref, name &char) py.Ref {
	owner := unsafe { &Model(reference) }
	if child := owner.attributes[unsafe { name.vstring() }] {
		model_inc(child)
		return child
	}
	if owner.kind == 'error' {
		assert unsafe { name.vstring() } == '__name__'
		return model_text(owner.text.str, owner.text.len)
	}
	result := object('method')
	mut value := unsafe { &Model(result) }
	value.text = unsafe { name.vstring().clone() }
	model_inc(reference)
	value.children << reference
	return result
}

fn model_call(reference py.Ref, args py.Ref, keywords py.Ref) py.Ref {
	value := unsafe { &Model(reference) }
	arguments := unsafe { &Model(args) }
	assert arguments.kind == 'tuple'
	if keywords != unsafe { nil } {
		assert unsafe { &Model(keywords) }.kind == 'dict'
	}
	if value.kind == 'function' {
		assert value.method.flags == 1 && value.children.len == 1
		method := unsafe { ModelCallback(value.method.function) }
		return method(value.children[0], args)
	}
	if value.kind == 'target' { return model_int(arguments.children.len) }
	assert value.kind == 'method'
	model_events << value.text
	for argument in arguments.children { model_inc(argument) }
	model_calls << arguments.children.clone()
	owner := unsafe { &Model(value.children[0]) }
	if value.text == 'keys' {
		result := object('list')
		for key in owner.attributes.keys() {
			item := model_text(key.str, key.len)
			model_append(result, item)
			model_dec(item)
		}
		return result
	}
	if value.text == 'list' {
		result := object('list')
		for child in unsafe { &Model(arguments.children[0]) }.children {
			model_append(result, child)
		}
		return result
	}
	if value.text == '__contains__' {
		for child in owner.children {
			if model_compare(child, arguments.children[0], 2) == 1 { return model_int(1) }
		}
		return model_int(0)
	}
	if value.text in ['get', '__getitem__'] {
		key := unsafe { &Model(arguments.children[0]) }.text
		if child := owner.attributes[key] {
			model_inc(child)
			return child
		}
		fallback := if arguments.children.len > 1 { arguments.children[1] } else { model_none }
		model_inc(fallback)
		return fallback
	}
	if value.text == 'ssize' {
		number := model_read_int(arguments.children[0]).str()
		return model_text(number.str, number.len)
	}
	if value.text == 'StubInstaller' { return object('stub-instance') }
	if value.text == 'wait' {
		assert arguments.children.len == 1 && model_read_int(arguments.children[0]) == 5
	}
	model_inc(model_none)
	return model_none
}

fn model_capsule(context voidptr, _ &char, destructor voidptr) py.Ref {
	if model_fail_capsule {
		model_fail_capsule = false
		model_error = 'SDKFailure'
		return py.Ref(unsafe { nil })
	}
	result := object('capsule')
	mut value := unsafe { &Model(result) }
	value.context = context
	value.destructor = unsafe { ModelDestructor(destructor) }
	return result
}

fn model_pointer(reference py.Ref, _ &char) voidptr { return unsafe { &Model(reference) }.context }

fn model_function(method &py.Method, capsule py.Ref, _ py.Ref) py.Ref {
	if model_fail_function {
		model_fail_function = false
		model_error = 'SDKFailure'
		return py.Ref(unsafe { nil })
	}
	result := object('function')
	mut value := unsafe { &Model(result) }
	value.method = unsafe { method }
	model_inc(capsule)
	value.children << capsule
	return result
}

fn api_model() py.Api {
	assert model_live == 0 && model_error == ''
	model_none = object('none')
	model_events = []string{}
	return py.Api{
		inc:             model_inc
		dec:             model_dec
		integer:         model_int
		boolean:         model_int
		as_integer:      model_read_int
		unicode:         model_text
		unicode_data:    model_unicode
		stringify:       model_stringify
		tuple:           model_tuple
		tuple_put:       model_put_tuple
		item:            model_item
		list:            model_list
		append:          model_append
		dict:            model_dict
		dict_put:        model_dict_put
		size:            model_size
		truth:           model_truth
		compare:         model_compare
		error_occurred:  model_occurred
		error_fetch:     model_fetch
		error_string:    model_set_error
		attribute:       model_attr
		attribute_set:   model_set
		dictionary_get:  model_get
		error_restore:   model_restore
		call:            model_call
		capsule_new:     model_capsule
		capsule_pointer: model_pointer
		function_new:    model_function
		none:            model_none
		runtime_error:   model_none
	}
}

fn release_model() {
	for call in model_calls {
		for argument in call { model_dec(argument) }
	}
	model_calls = [][]py.Ref{}
	model_dec(model_none)
	assert model_live == 0 && model_error == ''
}

fn test_shared_reference_fixture_starts_and_retires_cleanly() {
	_ = api_model()
	release_model()
}

fn test_retired_callbacks_do_not_touch_released_sdk_context() {
	active = unsafe { nil }
	for definition in methods() {
		callback := unsafe { Hook(definition.function) }
		assert callback(py.Ref(unsafe { nil }), py.Ref(unsafe { nil }), py.Ref(unsafe { nil })) == unsafe { nil }
	}
}

fn test_keyword_binding_and_informational_callbacks_without_sdk_execution() {
	mut api := api_model()
	mut a := py.Arena{ api: &api }
	upstream := a.take(object('upstream')) or { panic(err) }
	builtins := a.take(object('builtins')) or { panic(err) }
	base := a.take(object('base')) or { panic(err) }
	active = &Context{
		api:         &api
		selected:    config('disk0', '32000000000') or { panic(err) }
		upstream:    upstream
		builtins:    builtins
		base:        base
		logging:     upstream
		value_error: model_none
		type_error:  model_none
		methods:     methods()
	}
	kwargs := a.take(api.dict()) or { panic(err) }
	arg := a.int(19) or { panic(err) }
	assert api.dict_put(kwargs, c'total', arg) == 0
	values := bound(mut a, a.tuple([a.text('New size') or { panic(err) }]) or { panic(err) }, kwargs,
		['prompt', 'default', 'min', 'max', 'total'], 1, false) or { panic(err) }
	assert values.len == 5 && values[4] == arg && values[1] == model_none
	duplicate := a.take(api.dict()) or { panic(err) }
	assert api.dict_put(duplicate, c'prompt', arg) == 0
	if _ := bound(mut a, a.tuple([arg]) or { panic(err) }, duplicate, ['prompt'], 1, false) {
		assert false
	}
	unknown := a.take(api.dict()) or { panic(err) }
	assert api.dict_put(unknown, c'wrong', arg) == 0
	if _ := bound(mut a, a.tuple([]) or { panic(err) }, unknown, ['prompt'], 1, false) {
		assert false
	}
	if _ := bound(mut a, a.tuple([]) or { panic(err) }, py.Ref(unsafe { nil }), ['prompt'], 1, false) {
		assert false
	}
	if _ := bound(mut a, a.tuple([arg, arg]) or { panic(err) }, py.Ref(unsafe { nil }), ['prompt'], 1, false) {
		assert false
	}
	self := a.take(object('instance')) or { panic(err) }
	empty := a.tuple([]) or { panic(err) }
	input := a.take(hook_input(self, empty, py.Ref(unsafe { nil }))) or { panic(err) }
	assert a.string(input) or { panic(err) } == ''
	yes := a.take(hook_yesno(self, a.tuple([a.text('Confirmed GUI selection') or { panic(err) }]) or { panic(err) }, py.Ref(unsafe { nil }))) or { panic(err) }
	assert a.integer(yes) or { panic(err) } == 1 && model_events.last() == 'p_info'
	version := a.take(hook_choice(self, a.tuple([a.text('Version') or { panic(err) },
		a.list([arg, arg, arg]) or { panic(err) }]) or { panic(err) }, py.Ref(unsafe { nil }))) or { panic(err) }
	assert a.integer(version) or { panic(err) } == 2
	for definition in active.methods {
		assert definition.flags == 3 && definition.function != unsafe { nil }
	}
	assert active.methods.len == 12
	active = unsafe { nil }
	a.close()
	release_model()
}

fn test_saved_sdk_errors_copy_and_restore_or_retire_each_reference_once() {
	base := api_model()
	api := py.Api{ ...base, error_factory: sdk_error }
	model_error = 'SDKFailure'
	failure := api.exception()
	assert model_live == 2 && model_error == ''
	if failure is SdkError {
		assert failure.saved.name == 'SDKFailure'
		copy := failure
		failure.restore()
		copy.close()
		assert model_live == 2 && model_error == 'SDKFailure'
		mut kind, value, trace := py.Ref(unsafe { nil }), py.Ref(unsafe { nil }), py.Ref(unsafe { nil })
		api.error_fetch(&kind, &value, &trace)
		assert kind != unsafe { nil } && value == unsafe { nil } && trace == unsafe { nil }
		api.dec(kind)
	} else {
		assert false
	}
	assert model_live == 1 && model_error == ''
	model_error = 'SDKFailure'
	second := api.exception()
	if second is SdkError {
		second.close()
		second.close()
	} else {
		assert false
	}
	assert model_live == 1 && model_error == ''
	release_model()
}

fn pretend_shutdown(arguments []string) int {
	model_shutdowns << arguments.clone()
	return 0
}

fn pretend_delay(duration time.Duration) { model_delays << i64(duration) }

fn test_disk_size_profile_and_completion_callbacks_keep_original_sdk_calls() {
	mut api := api_model()
	mut a := py.Arena{ api: &api }
	upstream := a.take(object('upstream')) or { panic(err) }
	builtins := a.take(object('builtins')) or { panic(err) }
	base := a.take(object('base')) or { panic(err) }
	for key, value in {
		'MIN_FREE_OS': minimum_macos_free
		'MIN_FREE':    minimum_other_free
	} {
		a.set_attr(upstream, key, a.int(value) or { panic(err) }) or { panic(err) }
	}
	a.set_attr(upstream, 'stub', a.take(object('stub-module')) or { panic(err) }) or { panic(err) }
	active = &Context{
		api:         &api
		selected:    config('disk0', '32000000000') or { panic(err) }
		upstream:    upstream
		builtins:    builtins
		base:        base
		logging:     upstream
		value_error: model_none
		type_error:  model_none
		methods:     methods()
		shutdown:    pretend_shutdown
		delay:       pretend_delay
	}
	self := a.take(object('instance')) or { panic(err) }
	a.set_attr(self, 'cur_disk', a.text('disk0') or { panic(err) }) or { panic(err) }
	a.set_attr(self, 'sys_disk', a.text('disk0') or { panic(err) }) or { panic(err) }
	part := a.take(object('partition')) or { panic(err) }
	a.set_attr(part, 'free', a.boolean(true) or { panic(err) }) or { panic(err) }
	a.set_attr(part, 'size', a.int(32_000_000_000) or { panic(err) }) or { panic(err) }
	a.set_attr(self, 'parts', a.list([part]) or { panic(err) }) or { panic(err) }
	choice := a.take(hook_choice(self, a.tuple([a.text('Action') or { panic(err) },
		a.list([a.text('f') or { panic(err) }, a.text('r') or { panic(err) }]) or { panic(err) }]) or { panic(err) }, py.Ref(unsafe { nil }))) or { panic(err) }
	assert a.string(choice) or { panic(err) } == 'f'
	installed := a.take(object('os')) or { panic(err) }
	a.set_attr(installed, 'version', a.text('13.5') or { panic(err) }) or { panic(err) }
	a.set_attr(part, 'os', a.list([installed]) or { panic(err) }) or { panic(err) }
	margin := a.take(hook_min_free(self, a.tuple([part]) or { panic(err) }, py.Ref(unsafe { nil }))) or { panic(err) }
	assert a.integer(margin) or { panic(err) } == minimum_macos_free
	a.set_attr(self, 'cur_os', installed) or { panic(err) }
	a.take(hook_resize(self, a.tuple([a.list([part]) or { panic(err) }]) or { panic(err) }, py.Ref(unsafe { nil }))) or { panic(err) }
	assert model_events.last() == 'action_resize'
	assert model_calls.last()[0] == self
	assert unsafe { &Model(model_calls.last()[1]) }.children == [part]
	kwargs := a.take(api.dict()) or { panic(err) }
	assert api.dict_put(kwargs, c'total', a.int(500_000_000_000) or { panic(err) }) == 0
	assert api.dict_put(kwargs, c'min', a.int(38_000_000_000) or { panic(err) }) == 0
	new_size := a.take(hook_size(self, a.tuple([a.text('New size') or { panic(err) }]) or { panic(err) }, kwargs)) or { panic(err) }
	assert a.integer(new_size) or { panic(err) } == active.selected.macos_size(500_000_000_000, i64(38_000_000_000)) or { panic(err) }
	profile := a.take(api.dict()) or { panic(err) }
	assert api.dict_put(profile, c'name', a.text('Vinix') or { panic(err) }) == 0
	data := a.take(api.dict()) or { panic(err) }
	assert api.dict_put(data, c'os_list', a.list([profile]) or { panic(err) }) == 0
	a.set_attr(self, 'data', data) or { panic(err) }
	assert a.take(hook_os(self, a.tuple([]) or { panic(err) }, py.Ref(unsafe { nil }))) or { panic(err) } == profile
	for name in ['osins', 'sysinfo', 'dutil', 'osinfo', 'ins'] {
		a.set_attr(self, name, a.take(object(name)) or { panic(err) }) or { panic(err) }
	}
	template := a.take(api.dict()) or { panic(err) }
	partition := a.take(hook_os_size(self, a.tuple([
		a.int(64_000_000_000) or { panic(err) },
		a.int(16_000_000_000) or { panic(err) },
		template,
	]) or { panic(err) }, py.Ref(unsafe { nil }))) or { panic(err) }
	assert a.integer(partition) or { panic(err) } == 32_000_000_000 - stub_bytes
	assert model_events.last() == 'load_ipsw'
	model_shutdowns = [][]string{}
	model_delays = []i64{}
	a.take(hook_shutdown(self, a.tuple([]) or { panic(err) }, py.Ref(unsafe { nil }))) or { panic(err) }
	a.take(hook_restart(self, a.tuple([]) or { panic(err) }, py.Ref(unsafe { nil }))) or { panic(err) }
	assert model_shutdowns == [['shutdown', '-h', 'now'], ['shutdown', '-r', 'now']]
	assert model_delays == [i64(time.second), i64(time.second)]
	assert model_events.contains('prepare_for_step2') && model_events.contains('install_info') && model_events.contains('input_prompt')
	active = unsafe { nil }
	a.close()
	release_model()
}

fn test_external_selection_fallback_and_sdk_traceback_ownership() {
	base_api := api_model()
	mut api := py.Api{ ...base_api, error_factory: sdk_error }
	mut a := py.Arena{ api: &api }
	upstream := a.take(object('upstream')) or { panic(err) }
	active = &Context{
		api:         &api
		selected:    config('disk4', '32000000000') or { panic(err) }
		upstream:    upstream
		builtins:    upstream
		base:        upstream
		logging:     upstream
		value_error: model_none
		type_error:  model_none
		methods:     methods()
	}
	self := a.take(object('instance')) or { panic(err) }
	disk := a.take(api.dict()) or { panic(err) }
	assert api.dict_put(disk, c'DeviceIdentifier', a.text('disk4') or { panic(err) }) == 0
	a.set_attr(self, 'external_disks', a.list([disk]) or { panic(err) }) or { panic(err) }
	empty := a.tuple([]) or { panic(err) }
	assert a.truth(a.take(hook_select(self, empty, py.Ref(unsafe { nil }))) or { panic(err) }) or { panic(err) }
	assert a.string(a.attr(self, 'cur_disk') or { panic(err) }) or { panic(err) } == 'disk4'
	choice_args := a.tuple([a.text('Partition') or { panic(err) }, a.list([disk]) or { panic(err) }]) or { panic(err) }
	a.take(hook_choice(self, choice_args, py.Ref(unsafe { nil }))) or { panic(err) }
	assert model_events.last() == 'choice' && model_calls.last()[0] == self
	assert model_calls.last().len == 4 && model_calls.last().last() == model_none
	a.set_attr(self, 'external_disks', a.list([]) or { panic(err) }) or { panic(err) }
	assert hook_select(self, empty, py.Ref(unsafe { nil })) == unsafe { nil }
	failure := api.exception()
	if failure is SdkError {
		failure.close()
	} else {
		assert false
	}
	active = unsafe { nil }
	a.close()
	release_model()
}

fn test_saved_error_retains_value_and_trace_until_restoration() {
	base := api_model()
	api := py.Api{ ...base, error_factory: sdk_error }
	kind := object('error')
	mut kind_state := unsafe { &Model(kind) }
	kind_state.text = 'KeyboardInterrupt'
	value := model_text(c'interrupted', 11)
	trace := object('traceback')
	model_restore(kind, value, trace)
	failure := api.exception()
	assert model_live == 4 && model_pending.len == 0
	if failure is SdkError {
		assert failure.saved.name == 'KeyboardInterrupt' && failure.msg() == 'interrupted'
		failure.restore()
		failure.close()
	} else {
		assert false
	}
	assert model_pending == [kind, value, trace]
	second := api.exception()
	if second is SdkError {
		second.close()
	} else {
		assert false
	}
	release_model()
}

fn test_error_reporting_preserves_interrupt_exit_and_diagnostic_paths() {
	base := api_model()
	mut api := py.Api{ ...base, error_factory: sdk_error }
	mut a := py.Arena{ api: &api }
	upstream := a.take(object('upstream')) or { panic(err) }
	active = &Context{
		api:         &api
		selected:    config('disk0', '32000000000') or { panic(err) }
		upstream:    upstream
		builtins:    upstream
		base:        upstream
		logging:     upstream
		value_error: model_none
		type_error:  model_none
		methods:     methods()
	}
	for name in ['KeyboardInterrupt', 'SystemExit', 'RuntimeError'] {
		kind := object('error')
		mut state := unsafe { &Model(kind) }
		state.text = name
		value := object('exception')
		assert api.attribute_set(value, c'code', a.int(7) or { panic(err) }) == 0
		model_restore(kind, value, py.Ref(unsafe { nil }))
		failure := api.exception()
		status := report_error(mut a, failure) or { panic(err) }
		assert status == if name == 'KeyboardInterrupt' {
			130
		} else if name == 'SystemExit' {
			7
		} else {
			1
		}
	}
	assert model_events.contains('p_warning') && model_events.contains('error')
	active = unsafe { nil }
	a.close()
	release_model()
}
