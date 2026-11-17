// SPDX-License-Identifier: GPL-2.0-or-later
module g13contract

import g13layout

fn check_gem_advice(api string, helper string, table string) ! {
	code := section(api, 'pub fn (mut f GpuFile) ioctl_modern_gem_madvise(', 'pub fn (mut f GpuFile) ioctl_modern_gem_bind_object(', 'GEM advice transaction')!
	require_order(code, ['data.pad != 0 || data.madv > 1', 'f.lock.acquire()', 'f.objects.get_ref(data.handle)',
		'f.lock.release()', 'defer { gem.unref(object) }', 'gem.advise_private(object, data.madv == 1)', 'request.retained = retained'], 'Validate before lookup, owned pin across unlock, exact cleanup before output')!
	require_order(helper, ['object.vm_private_identity == 0 || object.external', 'owned.lock.acquire()',
		'defer { owned.lock.release() }', 'owned.advice_dontneed = dontneed', 'return 1'], 'Private resident advice under object lock')!
	require(!helper.contains('memory.') && !helper.contains('free(') && !helper.contains('pmm_'), 'Advice must not release or mutate backing')!
	require(table.contains('cmd: asahi.gem_madvise, size: u32(sizeof(asahi.GemMadvise)), direction: drm.ioctl_write | drm.ioctl_read, handler: modern_gem_madvise_handler, abi: modern_ioctl_abi, extensible: true'), 'Registered canonical modern advice endpoint')!
}

fn test_gem_advice_transaction_and_resident_policy() {
	r := g13layout.repo_root()
	a := read(r + '/kernel/gpu/agx/file/modern.v')!; h := read(r + '/kernel/drm/gem/advice.v')!; t := read(r + '/kernel/gpu/agx/file/file.v')!
	check_gem_advice(a, h, t)!
	for token in ['data.pad != 0 || data.madv > 1', 'defer { gem.unref(object) }', 'request.retained = retained'] {
		if _ := check_gem_advice(a.replace(token, ''), h, t) { assert false, token }
	}
	if _ := check_gem_advice(a, h.replace('object.vm_private_identity == 0 || object.external', 'false'), t) { assert false }
	if _ := check_gem_advice(a, h.replace('owned.advice_dontneed = dontneed', ''), t) { assert false }
	if _ := check_gem_advice(a, h, t.replace('cmd: asahi.gem_madvise,', 'cmd: asahi.submit,')) { assert false }
}
