// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module asahipolicy

import cpythonapi as py
import os
import time

@[heap]
struct Context {
	api         &py.Api
	selected    Config
	upstream    py.Ref
	base        py.Ref
	builtins    py.Ref
	logging     py.Ref
	value_error py.Ref
	type_error  py.Ref
	methods     []py.Method
	shutdown    fn ([]string) int  = os.system_args
	delay       fn (time.Duration) = time.sleep
}

__global (
	active &Context = unsafe { nil }
)

type Hook = fn (py.Ref, py.Ref, py.Ref) py.Ref

fn bound(mut a py.Arena, args py.Ref, keywords py.Ref, names []string, required int, boolean_default bool) ![]py.Ref {
	count := a.length(args)!
	if count > names.len {
		return Failure{ kind: 'TypeError', description: 'Too many installer callback arguments' }
	}
	if keywords != unsafe { nil } {
		keys := a.method(active.builtins, 'list', [a.method(keywords, 'keys', [], {})!], {})!
		for index in 0 .. a.length(keys)! {
			name := a.string(a.item(keys, index)!)!
			if name !in names {
				return Failure{ kind: 'TypeError', description: 'Unexpected installer keyword: ' + name }
			}
		}
	}
	mut values := []py.Ref{}
	for index, name in names {
		found, value := a.dictionary_value(keywords, name)!
		if index < count {
			if found {
				return Failure{ kind: 'TypeError', description: 'Duplicate installer callback argument: ' + name }
			}
			values << a.item(args, index)!
		} else if found {
			values << value
		} else if index < required {
			return Failure{ kind: 'TypeError', description: 'Missing installer callback argument: ' + name }
		} else {
			values << if boolean_default { a.boolean(false)! } else { a.borrow(a.api.none)! }
		}
	}
	return values
}

fn super_call(mut a py.Arena, self py.Ref, name string, args []py.Ref) !py.Ref {
	mut values := [self]
	values << args
	return a.call(a.attr(active.base, name)!, values, {})!
}

fn say(mut a py.Arena, name string, text string) ! {
	a.method(active.upstream, name, [a.text(text)!], {})!
}

fn size_text(mut a py.Arena, value i64) !string {
	return a.string(a.method(active.upstream, 'ssize', [a.int(value)!], {})!)!
}

fn invoke(name string, self py.Ref, args py.Ref, keywords py.Ref) py.Ref {
	// Finalization may run SDK destructors. Retired callbacks must never touch
	// context references after the owning root arena has released them.
	if active == unsafe { nil } { return py.Ref(unsafe { nil }) }
	mut a := py.Arena{ api: active.api }
	defer { a.close() }
	result := dispatch(mut a, name, self, args, keywords) or {
		if err is SdkError {
			err.restore()
		} else {
			kind := if err is Failure { err.kind } else { 'RuntimeError' }
			class := if kind == 'ValueError' {
				active.value_error
			} else if kind == 'TypeError' {
				active.type_error
			} else {
				active.api.runtime_error
			}
			active.api.error_string(class, err.msg().str)
		}
		return py.Ref(unsafe { nil })
	}
	a.api.inc(result)
	return result
}

fn hook_init(self py.Ref, args py.Ref, kwargs py.Ref) py.Ref {
	return invoke('__init__', self, args, kwargs)
}

fn hook_input(self py.Ref, args py.Ref, kwargs py.Ref) py.Ref {
	return invoke('input', self, args, kwargs)
}

fn hook_yesno(self py.Ref, args py.Ref, kwargs py.Ref) py.Ref {
	return invoke('yesno', self, args, kwargs)
}

fn hook_min_free(self py.Ref, args py.Ref, kwargs py.Ref) py.Ref {
	return invoke('get_min_free_space', self, args, kwargs)
}

fn hook_choice(self py.Ref, args py.Ref, kwargs py.Ref) py.Ref {
	return invoke('choice', self, args, kwargs)
}

fn hook_select(self py.Ref, args py.Ref, kwargs py.Ref) py.Ref {
	return invoke('action_select_disk', self, args, kwargs)
}

fn hook_resize(self py.Ref, args py.Ref, kwargs py.Ref) py.Ref {
	return invoke('action_resize', self, args, kwargs)
}

fn hook_size(self py.Ref, args py.Ref, kwargs py.Ref) py.Ref {
	return invoke('get_size', self, args, kwargs)
}

fn hook_os(self py.Ref, args py.Ref, kwargs py.Ref) py.Ref {
	return invoke('choose_os', self, args, kwargs)
}

fn hook_os_size(self py.Ref, args py.Ref, kwargs py.Ref) py.Ref {
	return invoke('get_os_size_and_info', self, args, kwargs)
}

fn hook_shutdown(self py.Ref, args py.Ref, kwargs py.Ref) py.Ref {
	return invoke('step2_indirect', self, args, kwargs)
}

fn hook_restart(self py.Ref, args py.Ref, kwargs py.Ref) py.Ref {
	return invoke('step2_completed', self, args, kwargs)
}

fn methods() []py.Method {
	return [
		py.Method{ name: c'__init__', function: voidptr(hook_init), flags: 3 },
		py.Method{ name: c'input', function: voidptr(hook_input), flags: 3 },
		py.Method{ name: c'yesno', function: voidptr(hook_yesno), flags: 3 },
		py.Method{ name: c'get_min_free_space', function: voidptr(hook_min_free), flags: 3 },
		py.Method{ name: c'choice', function: voidptr(hook_choice), flags: 3 },
		py.Method{ name: c'action_select_disk', function: voidptr(hook_select), flags: 3 },
		py.Method{ name: c'action_resize', function: voidptr(hook_resize), flags: 3 },
		py.Method{ name: c'get_size', function: voidptr(hook_size), flags: 3 },
		py.Method{ name: c'choose_os', function: voidptr(hook_os), flags: 3 },
		py.Method{ name: c'get_os_size_and_info', function: voidptr(hook_os_size), flags: 3 },
		py.Method{ name: c'step2_indirect', function: voidptr(hook_shutdown), flags: 3 },
		py.Method{ name: c'step2_completed', function: voidptr(hook_restart), flags: 3 },
	]
}

fn dispatch(mut a py.Arena, name string, self py.Ref, args py.Ref, kwargs py.Ref) !py.Ref {
	selected := active.selected
	match name {
		'__init__' {
			values := bound(mut a, args, kwargs, ['version'], 1, false)!
			super_call(mut a, self, name, values)!
			a.set_attr(self, 'target_disk', a.text(selected.disk)!)!
			a.set_attr(self, 'allocation', a.int(selected.allocation)!)!
			return a.borrow(a.api.none)!
		}
		'input' {
			bound(mut a, args, kwargs, [], 0, false)!
			return a.text('')!
		}
		'yesno' {
			values := bound(mut a, args, kwargs, ['prompt', 'default'], 1, true)!
			say(mut a, 'p_info', '  Confirmed in Vinix Installer: ' + a.string(values[0])!)!
			return a.boolean(true)!
		}
		'get_min_free_space' {
			values := bound(mut a, args, kwargs, ['part'], 1, false)!
			installed := a.attr(values[0], 'os')!
			mut has_os := false
			if a.truth(installed)! {
				for index in 0 .. a.length(installed)! {
					if a.truth(a.attr(a.item(installed, index)!, 'version')!)! {
						has_os = true
						break
					}
				}
			}
			return a.attr(active.upstream, if has_os { 'MIN_FREE_OS' } else { 'MIN_FREE' })!
		}
		'choice' {
			values := bound(mut a, args, kwargs, ['prompt', 'options', 'default'], 2, false)!
			prompt := a.string(values[0])!
			if prompt == 'Version' { return a.int(newest_version(a.length(values[1])!))! }
			if prompt != 'Action' { return super_call(mut a, self, name, values)! }
			mut choices := []string{}
			for option in ['d', 'w', 'f', 'r'] {
				if a.truth(a.method(values[1], '__contains__', [a.text(option)!], {})!)! {
					choices << option
				}
			}
			current_ref, system_ref := a.attr(self, 'cur_disk')!, a.attr(self, 'sys_disk')!
			current := if current_ref == a.api.none { '' } else { a.string(current_ref)! }
			system := if system_ref == a.api.none { '' } else { a.string(system_ref)! }
			mut free_sizes := []i64{}
			if current == selected.disk && current == system {
				parts := a.attr(self, 'parts')!
				for index in 0 .. a.length(parts)! {
					part := a.item(parts, index)!
					if a.truth(a.attr(part, 'free')!)! {
						free_sizes << a.integer(a.attr(part, 'size')!)!
					}
				}
			}
			choice := selected.action(current, system, choices, free_sizes) or {
				if current == selected.disk && current == system {
					return Failure{ description: 'No APFS container on ' + selected.disk + ' can safely provide ' + size_text(mut a, selected.allocation)! }
				}
				return err
			}
			return a.text(choice)!
		}
		'action_select_disk' {
			bound(mut a, args, kwargs, [], 0, false)!
			external := a.attr(self, 'external_disks')!
			mut eligible := []string{}
			if a.truth(external)! {
				for index in 0 .. a.length(external)! {
					eligible << a.string(a.method(a.item(external, index)!, '__getitem__', [a.text('DeviceIdentifier')!], {})!)!
				}
			}
			selected.select_external(eligible)!
			a.set_attr(self, 'cur_disk', a.text(selected.disk)!)!
			return a.boolean(true)!
		}
		'action_resize' {
			values := bound(mut a, args, kwargs, ['resizable'], 1, false)!
			current := a.attr(self, 'cur_os')!
			mut matches := []bool{}
			for index in 0 .. a.length(values[0])! {
				installed := a.attr(a.item(values[0], index)!, 'os')!
				matches << if a.truth(installed)! {
					a.truth(a.method(installed, '__contains__', [current], {})!)!
				} else {
					false
				}
			}
			index := resize_candidate(matches)!
			return super_call(mut a, self, name, [a.list([a.item(values[0], index)!])!])!
		}
		'get_size' {
			values := bound(mut a, args, kwargs, ['prompt', 'default', 'min', 'max', 'total'], 1, false)!
			if a.string(values[0])! != 'New size' || values[4] == a.api.none {
				return super_call(mut a, self, name, values)!
			}
			total := a.integer(values[4])!
			mut minimum := ?i64(none)
			if values[2] != a.api.none { minimum = a.integer(values[2])! }
			new_size := selected.macos_size(total, minimum) or {
				if boundary := minimum {
					return Failure{ description: 'Allocating ' + size_text(mut a, selected.allocation)! + ' would leave macOS below its safe minimum of ' + size_text(mut a, boundary)! }
				}
				return err
			}
			return a.int(new_size)!
		}
		'choose_os' {
			bound(mut a, args, kwargs, [], 0, false)!
			list := a.method(a.attr(self, 'data')!, 'get', [a.text('os_list')!, a.list([])!], {})!
			if a.length(list)! != 1 {
				return Failure{ description: 'The signed Vinix installer profile is missing' }
			}
			profile := a.item(list, 0)!
			label := a.method(profile, 'get', [a.text('name')!], {})!
			if !a.equal(label, a.text('Vinix')!)! {
				return Failure{ description: 'The signed Vinix installer profile is missing' }
			}
			return profile
		}
		'get_os_size_and_info' {
			values := bound(mut a, args, kwargs, ['free_size', 'min_size', 'template'], 3, false)!
			free_size, minimum := a.integer(values[0])!, a.integer(values[1])!
			partition := selected.os_partition(free_size, minimum) or {
				return Failure{
					description: if selected.allocation < minimum {
						'Vinix needs ' + size_text(mut a, minimum)! + ' on this disk'
					} else {
						'Only ' + size_text(mut a, free_size)! + ' of contiguous space is available'
					}
				}
			}
			a.set_attr(a.attr(self, 'osins')!, 'name', a.text('Vinix')!)!
			say(mut a, 'p_message', 'Vinix will be allocated ' + size_text(mut a, selected.allocation)! + '.')!
			supported := a.method(values[2], 'get', [a.text('supported_fw')!, a.borrow(a.api.none)!], {})!
			ipsw := a.method(self, 'choose_ipsw', [supported], {})!
			a.method(active.logging, 'info', [a.text('Chosen IPSW version: %s')!,
				a.attr(ipsw, 'version')!], {})!
			stub := a.attr(active.upstream, 'stub')!
			instance := a.method(stub, 'StubInstaller', [a.attr(self, 'sysinfo')!,
				a.attr(self, 'dutil')!, a.attr(self, 'osinfo')!], {})!
			a.set_attr(self, 'ins', instance)!
			a.method(instance, 'load_ipsw', [ipsw], {})!
			// The selected upstream constants are checked before the SDK starts.
			return a.int(partition)!
		}
		'step2_indirect', 'step2_completed' {
			values := bound(mut a, args, kwargs, ['report'], 0, true)!
			recovery := name == 'step2_completed'
			if !recovery { a.method(a.attr(self, 'ins')!, 'prepare_for_step2', [], {})! }
			a.method(self, 'install_info', values, {})!
			println('')
			for index, message in completion(recovery) {
				say(mut a, if index == 0 { 'p_success' } else { 'p_message' }, message)!
			}
			if !recovery { println('') }
			a.method(active.upstream, 'input_prompt', [a.text(if recovery {
				'Press Enter to restart: '
			} else {
				'Press Enter to shut down: '
			})!], {})!
			active.delay(time.second)
			result := active.shutdown(['shutdown', if recovery { '-r' } else { '-h' }, 'now'])
			_ = result
			return a.borrow(a.api.none)!
		}
		else { return Failure{ description: 'Unknown native installer callback' } }
	}
}
