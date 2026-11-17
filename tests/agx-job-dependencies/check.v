// SPDX-License-Identifier: GPL-2.0-or-later
import crypto.sha256
import os

fn body(source string, name string) string {
	for line in source.split_into_lines() {
		if line == '' || line[0].is_space() || !line.contains(' ' + name + '(') || !line.ends_with(' {') { continue }
		start := source.index(line) or { panic(name) }
		end := source.index_after('\n}\n', start) or { panic(name) }
		return source[start..end + 3]
	}
	panic('missing C function ' + name)
}

fn normalize(source string) string {
	mut result := []u8{cap: source.len}
	mut index := 0
	for index < source.len {
		mut skip := false
		for prefix in ['__discard_', '__or_opt_', '__or_val_', '_sa', '_t'] {
			if !source[index..].starts_with(prefix) { continue }
			mut end := index + prefix.len
			if end >= source.len || !source[end].is_digit() { continue }
			for end < source.len && source[end].is_digit() { end++ }
			result << (prefix + 'N').bytes(); index = end; skip = true; break
		}
		if !skip { result << source[index]; index++ }
	}
	return result.bytestr()
}

fn ordered(source string, tokens []string) {
	mut offset := 0
	for token in tokens { offset = (source.index_after(token, offset) or { panic(token) }) + token.len }
}

fn no_hidden(code string) {
 for token in ['memdup(', 'v_malloc(', 'v_calloc(', '__esc_', '__new_array_', 'array_clone(', 'string__substr(', 'int__str(', 'u64__str('] { assert !code.contains(token), token }
}
fn main() {
 assert os.args.len == 3
 for arch in ['aarch64', 'x86_64'] {
  old := os.read_file(os.args[1] + '/blob-' + arch + '.c')!
  assert sha256.sum(old.bytes()).hex() == if arch == 'aarch64' { '5cc4d62891d77643397c070c3dc61145a5f4f8266e457e51be9845ed2a1836b9' } else { '232550a13e56a4760bb091eca9d2a602d28a7eb71f349d4cec3f9cb50ff8b23f' }
  current := os.read_file(os.args[2] + '/blob-' + arch + '.c')!
  mut unchanged := 0
  for name in ['submission__copy_sync_array', 'submission__release_sync_array', 'submission__stage_packet_syncs', 'submission__stage_sync_array',
   'submission__install_output_syncs', 'gpu__agx__file__g13_dependencies_ready', 'gpu__agx__file__process_pending_submissions',
   'gpu__agx__file__poll_g13_pending', 'gpu__agx__file__GpuFile__ioctl_modern_submit', 'gpu__agx__file__finish_g13_submit',
   'gpu__agx__file__g13_compute_completed', 'gpu__agx__file__g13_render_completed', 'gpu__agx__file__GpuFile__close',
   'syncobj__queue_dependency_ready', 'drm__ioctl_syncobj_transfer'] {
   if arch == 'x86_64' && (name.starts_with('submission__') || name.starts_with('gpu__agx__') || name == 'syncobj__queue_dependency_ready') {
    assert !old.contains(name + '(') && !current.contains(name + '('); continue
   }
   assert normalize(body(old, name)) == normalize(body(current, name)), name
   unchanged++
  }
  if arch == 'aarch64' {
   copy := body(current, 'submission__copy_job_dependencies')
   no_hidden(copy)
   assert !copy.contains('memory__') && !copy.contains('&copied')
   ordered(copy, ['submission__copy_sync_array(source)', 'if (code != 0)', 'source->count', 'submission__SyncArray__item(source,', 'if (incoming.fence == NULL)', 'previous->context != incoming.fence->context', 'incoming.fence->seqno > previous->seqno', 'if (!replace)', '(copied.items)[target] = incoming', 'copied.count = count', '0, copied'])
   for dir in ['host-complete', 'measure-fixed', 'trace-reviewed'] { assert normalize(copy) == normalize(body(os.read_file(os.args[2] + '/' + dir + '/host.c')!, 'submission__copy_job_dependencies')), dir }
   name := 'gpu__agx__file__GpuFile__submit_g13_staged'
   submit := body(current, name)
   assert submit.count('submission__copy_job_dependencies(input_syncs)') == 1
   assert normalize(body(old, name)) == normalize(submit.replace('submission__copy_job_dependencies(input_syncs)', 'submission__copy_sync_array(input_syncs)'))
   println(arch + ': copied header stays on stack, no hidden/new allocation or metadata release, latest unsigned selection and stable order; host/measure/trace C match. Submit changes only the private-copy call.')
  } else { assert !current.contains('submission__copy_job_dependencies('); println(arch + ': AGX dependency reducer pruned.') }
  println(arch + ': ' + unchanged.str() + ' shared capture/poll/completion/lifetime/transfer bodies unchanged.')
 }
}
