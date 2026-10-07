module g17plan

import traceanalysis { Value }
import crypto.sha256

pub fn compile_plan(abi map[string]Value, command []u8, descriptor []u8, gpu u64) !map[string]Value {
	channels := obj(abi, 'channels')
	layout := obj(channels, 'command_3d_register_lists')
	codec := obj(channels, 'register_entry_codec')
	cfg := obj(channels, 'register_emission_cfg')
	g := obj(obj(cfg, 'producers'), '3D')
	if !truth(val(layout, 'record_framing_resolved')) {
		return error('3D register-list framing is incomplete')
	}
	if !truth(val(cfg, 'machine_order_complete')) {
		return error('register emission graph is incomplete')
	}
	if !truth(val(g, 'predicates_complete')) {
		return error('3D register predicates are incomplete')
	}
	bytes := field(layout, 'command_bytes', 'command bytes')!
	if command.len < bytes {
		return error('command has 0x${command.len:x} bytes; need 0x${bytes:x}')
	}
	if descriptor.len < descriptor_bytes {
		return error('descriptor has 0x${descriptor.len:x} bytes; need 0x${descriptor_bytes:x}')
	}
	if gpu == 0 { return error('command GPU address must be a nonzero u64') }
	passes := field(layout, 'passes', 'register passes')!
	stride := field(layout, 'stride', 'register stride')!
	stream := field(layout, 'stream_offset', 'stream offset')!
	capacity := field(layout, 'stream_bytes', 'stream bytes')!
	address := field(layout, 'gpu_address_offset', 'GPU address offset')!
	count := field(layout, 'entry_count_offset', 'entry count offset')!
	length := field(layout, 'byte_length_offset', 'byte length offset')!
	entry_bytes := field(layout, 'entry_bytes', 'entry bytes')!
	summary := required_obj(layout, 'descriptor_summary')!
	selector_mask := masked_integer(required(codec, 'selector_mask')!, 'selector mask')!
	mode_mask := masked_integer(required(codec, 'mode_mask')!, 'mode mask')!
	template_mask := masked_integer(required(codec, 'preserved_template_mask')!, 'template mask')!
	value_offset := field(codec, 'value_offset', 'value offset')!
	if entry_bytes != field(codec, 'entry_bytes', 'codec entry bytes')! {
		return error('layout and codec entry sizes disagree')
	}
	if entry_bytes <= 0 || passes < 0 { return error('invalid register layout') }
	events := catalog(abi, '3D')!
	mut writes := []Value{}
	mut pass_records := []Value{}
	mut recovered := 0
	mut external := 0
	for pass_index in 0 .. passes {
		base := pass_index * stride
		encoded := load(command, base + address, 8, false)!
		entries := load(command, base + count, 2, false)!
		byte_length := load(command, base + length, 2, false)!
		delta := u64(base + stream)
		expected := gpu + delta
		if expected < gpu || encoded != expected {
			expected_text := if expected < gpu { '0x1${expected:016x}' } else { '0x${expected:x}' }
			return error('pass ${pass_index}: stream GPU address 0x${encoded:x} != ${expected_text}')
		}
		if byte_length > u64(capacity) || byte_length % u64(entry_bytes) != 0 || entries != byte_length / u64(entry_bytes) {
			return error('pass ${pass_index}: invalid entry/byte counters')
		}
		summary_offset := field(summary, 'offset', 'summary offset')! + pass_index * field(summary, 'stride', 'summary stride')!
		summary_address := load(descriptor, summary_offset, 8, false)!
		summary_count := load(descriptor, summary_offset + 8, 2, false)!
		if summary_offset < 0 || summary_offset > descriptor.len - 16 {
			return error('pass ${pass_index}: descriptor summary mismatch')
		}
		if summary_address != encoded || summary_count != entries || descriptor[summary_offset + 10..summary_offset + 16].any(it != 0) {
			return error('pass ${pass_index}: descriptor summary mismatch')
		}
		mut observations := []map[string]Value{}
		for index in 0 .. int(entries) {
			entry := base + stream + index * entry_bytes
			word := load(command, entry, 4, false)!
			observations << {
				'selector':      Value(word & selector_mask)
				'mode':          Value(word & mode_mask)
				'selector_word': Value(word)
				'value':         Value(load(command, entry + value_offset, 8, false)!)
			}
		}
		path := match_path(g, events, observations, descriptor, command)!
		for index, offset in path {
			event := events[offset]
			observation := observations[index]
			mut value_mask := word_mask
			mut reason := ''
			expected_value := evaluate(required(event, 'value_source')!, descriptor, command) or {
				if err.code() != unresolved_code { return err }
				value_mask = 0
				reason = err.msg()
				val(observation, 'value').u64()
			}
			if value_mask != 0 { recovered++ } else { external++ }
			if value_mask != 0 && val(observation, 'value').u64() != expected_value {
				return error('pass ${pass_index} event ${hex_offset(offset)}: value 0x${val(observation, 'value').u64():x} != recovered 0x${expected_value:x}')
			}
			mut record := map[string]Value{
				'pass':              Value(pass_index)
				'entry':             Value(index)
				'producer_offset':   Value(offset)
				'form':              val(event, 'form')
				'selector':          val(event, 'selector')
				'mode':              val(event, 'mode')
				'template_bits':     Value(val(observation, 'selector_word').u64() & template_mask)
				'template_mask':     Value(0)
				'value':             Value(expected_value)
				'value_mask':        Value(value_mask)
				'address_alignment': Value(0)
				'flags':             Value(0)
				'value_status':      Value(if value_mask != 0 { 'recovered' } else { 'external' })
			}
			if reason != '' { record['unresolved_reason'] = Value(reason) }
			writes << record
		}
		pass_records << map[string]Value{
			'pass':               Value(pass_index)
			'stream_gpu_address': Value(encoded)
			'entry_count':        Value(entries)
			'producer_offsets':   Value(number_array(path))
		}
	}
	return {
		'schema':              Value('vinix.fake-g17-plan.v1')
		'producer':            Value('3D')
		'source':              Value(map[string]Value{
			'driver_uuid':       val(abi, 'driver_uuid')
			'firmware_uuid':     val(abi, 'firmware_uuid')
			'abi_schema':        val(abi, 'schema')
			'command_sha256':    Value(sha256.sum(command[..bytes]).hex())
			'descriptor_sha256': Value(sha256.sum(descriptor[..descriptor_bytes]).hex())
		})
		'command_gpu_address': Value(gpu)
		'command_bytes':       Value(bytes)
		'descriptor_bytes':    Value(descriptor_bytes)
		'passes':              Value(pass_records)
		'writes':              Value(writes)
		'coverage':            Value(map[string]Value{
			'total_writes':     Value(writes.len)
			'recovered_values': Value(recovered)
			'external_values':  Value(external)
			'ordering':         Value('recovered-cfg')
			'template_bits':    Value('observed-unconstrained')
		})
	}
}
