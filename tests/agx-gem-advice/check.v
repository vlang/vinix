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

fn no_allocations(source string) {
 for token in ['memdup(', 'v_malloc(', 'v_calloc(', '__esc_', '__new_array_', 'array_clone(', 'string__substr(', 'int__str(', 'u64__str(', 'memory__', 'pmm_'] { assert !source.contains(token), token }
}
fn main() {
 assert os.args.len == 3
 for arch in ['aarch64', 'x86_64'] {
  old := os.read_file(os.args[1] + '/blob-' + arch + '.c')!
  assert sha256.sum(old.bytes()).hex() == if arch == 'aarch64' { '382a70164add9bbf3fcaf24a88f0405fb7d95941dd5e7e4934110c22c4072620' } else { 'c169809640036572701ee7eeb3920a46119959e90161b15137a3556b14ed8a64' }
  current := os.read_file(os.args[2] + '/blob-' + arch + '.c')!
  mut unchanged := 0
  for name in ['gem__create_object', 'gem__destroy', 'gem__unref', 'gem__ref_obj', 'bo__Table__get_ref', 'bo__Table__remove',
   'gpu__agx__file__GpuFile__close', 'gpu__agx__file__GpuFile__ioctl_gem_create', 'gpu__agx__file__GpuFile__ioctl_gem_bind',
   'gpu__agx__file__GpuFile__ioctl_modern_vm_bind', 'gpu__agx__file__GpuFile__ioctl_modern_submit',
   'gpu__agx__file__finish_g13_submit', 'gpu__agx__file__process_pending_submissions', 'drm__ioctl_syncobj_transfer'] {
   if arch == 'x86_64' && (name.starts_with('gpu__agx__') || name.starts_with('bo__')) {
    assert !old.contains(name + '(') && !current.contains(name + '('); continue
   }
   assert normalize(body(old, name)) == normalize(body(current, name)), name
   unchanged++
  }
  if arch == 'aarch64' {
   helper := body(current, 'gem__advise_private')
   api := body(current, 'gpu__agx__file__GpuFile__ioctl_modern_gem_madvise')
   handler := body(current, 'gpu__agx__file__modern_gem_madvise_handler')
   no_allocations(helper); no_allocations(api); no_allocations(handler)
   ordered(helper, ['object->vm_private_identity == 0', 'object->external', 'klock__Lock__acquire(&owned->lock)', 'owned->advice_dontneed = dontneed', '.value =', 'klock__Lock__release(&owned->lock)'])
   ordered(api, ['data->pad != 0', 'data->madv > 1', 'klock__Lock__acquire(&f->lock)', 'bo__Table__get_ref(', 'klock__Lock__release(&f->lock)', 'return -2', 'klock__Lock__release(&f->lock)', 'gem__advise_private(', '-22;', 'gem__unref(object)', 'request->retained = retained', 'gem__unref(object)'])
   for directory in ['host-reviewed', 'measure-reviewed', 'trace'] {
    host := os.read_file(os.args[2] + '/' + directory + '/host.c')!
    assert normalize(helper) == normalize(body(host, 'gem__advise_private'))
    if directory == 'trace' { assert !host.contains('GpuFile__ioctl_modern_gem_madvise('); continue }
    candidate := body(host, 'file__GpuFile__ioctl_modern_gem_madvise').replace('file__Objects__get_ref', 'bo__Table__get_ref').replace('file__GpuFile', 'gpu__agx__file__GpuFile')
    assert normalize(api) == normalize(candidate), directory + ': caller differs'
    if directory == 'host-reviewed' {
     for fixture in ['file__run_advice_checks', 'file__check_advice_transport', 'file__measure_advice'] {
      if fixture == 'file__measure_advice' { continue }
      code := body(host, fixture)
      assert !code.contains('memdup(') && !code.contains('__esc_'), fixture
     }
    }
   }
   println(arch + ': advice/helper/handler have no hidden allocations or backing operations; get_ref under file lock, exact put after object unlock on success/refusal, output order and host/measure/trace C match verified.')
  } else { assert !current.contains('gem__advise_private('); println(arch + ': advice and AGX backend pruned.') }
  println(arch + ': ' + unchanged.str() + ' shared GEM/BO/lifetime/submit/transfer bodies match the pinned baseline.')
 }
}
