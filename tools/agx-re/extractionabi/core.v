module main

import imageextract as image
import g17decode
import g17power
import math.big
import strconv
import sync.stdatomic as atom
import traceanalysis as j

#include <string.h>
#include <gc/gc.h>

struct C.GC_stack_base {
	mem_base voidptr
}

fn C.GC_thread_is_registered() i32
fn C.GC_get_stack_base(&C.GC_stack_base) i32
fn C.GC_register_my_thread(&C.GC_stack_base) i32
fn C.GC_unregister_my_thread() i32
fn C.GC_gcollect()
fn C.GC_get_heap_size() usize
fn C.GC_get_free_bytes() usize
fn C.strdup(&char) &char

__global owned_output_count i64

// Foreign inputs remain borrowed until this synchronous call returns. The
// response and optional binary output use libc malloc, never collector-owned
// memory; the import adapter copies each output and calls release exactly once.
@[export: 'vinix_agx_extract_query']
pub fn query(data &u8, byte_count usize, operation &char, options &char) &char {
	mut registered := false
	if C.GC_thread_is_registered() == 0 {
		mut stack := C.GC_stack_base{}
		if C.GC_get_stack_base(&stack) != 0 || C.GC_register_my_thread(&stack) != 0 {
			return owned_duplicate(c'{"error":"cannot register native extraction thread"}')
		}
		registered = true
	}
	defer { if registered { C.GC_unregister_my_thread() } }
	if byte_count > usize(max_int) {
		return owned_duplicate(c'{"error":"input exceeds the host array size"}')
	}
	if byte_count != 0 && data == unsafe { nil } {
		return owned_duplicate(c'{"error":"null native extraction input"}')
	}
	op := unsafe { cstring_to_vstring(operation) }
	request := j.object(j.decode(unsafe { cstring_to_vstring(options) }) or {
		return allocated_json({
			'error': j.Value(err.msg())
		})
	}) or {
		return allocated_json({
			'error': j.Value(err.msg())
		})
	}
	input := unsafe { data.vbytes(int(byte_count)) }
	result := dispatch(input, op, request) or {
		return allocated_json({
			'error': j.Value(err.msg())
		})
	}
	response := allocated_json(result.payload)
	if response == unsafe { nil } && result.binary != unsafe { nil } {
		release(result.binary)
	}
	return response
}

@[export: 'vinix_agx_extract_release']
pub fn release(pointer voidptr) {
	if pointer == unsafe { nil } { return }
	unsafe { C.free(pointer) }
	atom.add_i64(&owned_output_count, -1)
}

fn allocated_json(payload map[string]j.Value) &char {
	encoded := j.encode(j.Value(payload), false)
	return owned_duplicate(unsafe { &char(encoded.str) })
}

fn owned_duplicate(source &char) &char {
	result := unsafe { C.strdup(source) }
	if result != unsafe { nil } { atom.add_i64(&owned_output_count, 1) }
	return result
}

struct Response {
	payload map[string]j.Value
	binary  voidptr
}

fn scalar(value j.Value) Response {
	return Response{
		payload: {
			'result': value
		}
	}
}

fn span_value(span image.Span) j.Value {
	return j.Value(map[string]j.Value{
		'start': j.Value(span.start)
		'end':   j.Value(span.end)
	})
}

fn binary_result(data []u8) !Response {
	// malloc(0) is implementation-dependent, so give the empty result one byte.
	bytes := if data.len == 0 { 1 } else { data.len }
	pointer := unsafe { C.malloc(usize(bytes)) }
	if pointer == unsafe { nil } { return error('cannot allocate native extraction output') }
	atom.add_i64(&owned_output_count, 1)
	if data.len != 0 { unsafe { C.memcpy(pointer, data.data, usize(data.len)) } }
	return Response{
		payload: {
			'result': j.Value(map[string]j.Value{
				'pointer': j.Value(u64(pointer))
				'bytes':   j.Value(data.len)
			})
		}
		binary:  pointer
	}
}

fn parameter(request map[string]j.Value, name string, fallback int) !int {
	if name !in request { return fallback }
	text := j.string_value(j.value(request, name))
	return strconv.atoi(text)
}

fn signed_integer(value j.Value) !big.Integer {
	if value is bool { return big.integer_from_int(if value { 1 } else { 0 }) }
	return big.integer_from_string(j.string_value(value))
}

fn dispatch(data []u8, operation string, request map[string]j.Value) !Response {
	if operation == 'g17:recover_g17_linear_power_transfer_tables' {
		code := j.bytes_fromhex(j.string_value(j.value(request, 'code')))!
		return scalar(j.Value(g17power.recover_linear_power_transfer_tables(data, code)!))
	}
	if operation.starts_with('g17:') {
		return scalar(g17decode.query(data, operation[4..], request)!)
	}
	match operation {
		'default_entries' {
			mut entries := []j.Value{}
			for entry in image.default_entries { entries << j.Value(entry) }
			return scalar(j.Value(entries))
		}
		'align_up' {
			value := signed_integer(j.value(request, 'value'))!
			alignment := signed_integer(j.value(request, 'alignment'))!
			return scalar(j.Value(j.Number{image.align_up_integer(value, alignment).str()}))
		}
		'safe_filename' {
			return scalar(j.Value(j.string_value(j.value(request, 'identifier')).trim_string_left('com.apple.') + '.macho'))
		}
		'der_encode' {
			return binary_result(image.der_encode(u8(parameter(request, 'tag', 0)!), data))
		}
		'allocation_stats' {
			C.GC_gcollect()
			return scalar(j.Value(map[string]j.Value{
				'owned_outputs':     j.Value(atom.load_i64(&owned_output_count))
				'gc_heap_bytes':     j.Value(u64(C.GC_get_heap_size()))
				'gc_retained_bytes': j.Value(u64(C.GC_get_heap_size() - C.GC_get_free_bytes()))
			}))
		}
		'der_length' {
			length, next := image.der_length(data, parameter(request, 'offset', 0)!)!
			return scalar(j.Value([j.Value(length), j.Value(next)]))
		}
		'der_item' {
			span, next := image.der_item(data, parameter(request, 'offset', 0)!, u8(parameter(request, 'tag', 0)!))!
			return scalar(j.Value(map[string]j.Value{
				'span': span_value(span)
				'next': j.Value(next)
			}))
		}
		'unwrap_im4p' {
			container := image.unwrap_im4p(data)!
			return scalar(j.Value(map[string]j.Value{
				'image_type': span_value(container.image_type)
				'payload':    span_value(container.payload)
				'extra':      j.Value(container.extra)
			}))
		}
		'im4p_sequence' { return scalar(span_value(image.im4p_sequence(data)!)) }
		'find_source' {
			return scalar(j.Value(image.find_source(j.string_value(j.value(request, 'preboot')), j.string_value(j.value(request, 'mode')), j.string_value(j.value(request, 'platform')))!))
		}
		'select_variant' {
			tag, selected := image.select_variant(j.string_value(j.value(request, 'container')), j.string_value(j.value(request, 'variant')))!
			response := binary_result(selected)!
			mut result := j.value(response.payload, 'result').as_map()
			result['tag'] = j.Value(tag)
			return Response{
				payload: {
					'result': j.Value(result)
				}
				binary:  response.binary
			}
		}
		'im4p_payload' { return scalar(span_value(image.im4p_payload(data)!)) }
		'kernel_im4p_payload' { return scalar(span_value(image.kernel_im4p_payload(data)!)) }
		'pmp_payload' { return scalar(span_value(image.pmp_payload(data)!)) }
		'firmware_entries' {
			mut entries := []j.Value{}
			for entry in image.firmware_entries(data)! {
				entries << j.Value(map[string]j.Value{
					'tag':   j.Value(entry.tag)
					'image': span_value(entry.image)
				})
			}
			return scalar(j.Value(entries))
		}
		'image_variant' { return scalar(j.Value(image.image_variant(data)!)) }
		'macho_metadata' { return scalar(j.Value(image.macho_metadata(data)!)) }
		'macho_identity' { return scalar(j.Value(image.macho_identity(data)!)) }
		'load_commands' {
			mut commands := []j.Value{}
			for command in image.load_commands(data, parameter(request, 'header_offset', 0)!)! {
				commands << j.Value(map[string]j.Value{
					'command': j.Value(command.command)
					'offset':  j.Value(command.offset)
					'size':    j.Value(command.size)
				})
			}
			return scalar(j.Value(commands))
		}
		'parse_segment' {
			segment := image.parse_segment(data, image.LoadCommand{u32(parameter(request, 'command', 0)!), parameter(request, 'offset', 0)!, parameter(request, 'size', 0)!})!
			return scalar(j.Value(map[string]j.Value{
				'command_offset':  j.Value(segment.command_offset)
				'name':            j.Value(segment.name)
				'virtual_address': j.Value(segment.virtual_address)
				'virtual_size':    j.Value(segment.virtual_size)
				'file_offset':     j.Value(segment.file_offset)
				'file_size':       j.Value(segment.file_size)
				'section_count':   j.Value(segment.section_count)
			}))
		}
		'fileset_entries' {
			mut entries := map[string]j.Value{}
			for name, entry in image.fileset_entries(data)! {
				entries[name] = j.Value([j.Value(entry.virtual_address), j.Value(entry.file_offset)])
			}
			return scalar(j.Value(entries))
		}
		'extract_entry' {
			return binary_result(image.extract_entry(data, parameter(request, 'entry_offset', 0)!)!)
		}
		'pmp_command_summary' { return scalar(j.Value(image.pmp_command_summary(data)!)) }
		'decompress_kernel' {
			if data.len >= 4 && image.u32_at(data, 0) == image.macho_magic_64 {
				return scalar(j.Value(map[string]j.Value{
					'unchanged': j.Value(true)
				}))
			}
			capacity := strconv.parse_int(j.string_value(j.value(request, 'initial_capacity')), 10, 64)!
			if capacity < 0 { return error('Array length must be >= 0, not ${capacity}') }
			return binary_result(image.decompress_kernel(data, u64(capacity))!)
		}
		else { return error('unknown native extraction operation ${operation}') }
	}
}
