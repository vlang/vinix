module g13contract

import g13layout
import os

fn test_order_accepts_repeated_tokens() {
	require_order('flush reprotect flush unmap flush', ['flush', 'flush', 'flush'], 'sample')!
}

fn test_order_rejects_a_reversed_contract() {
	if _ := require_order('unmap flush reprotect', ['reprotect', 'unmap'], 'sample') {
		assert false
	} else {
		assert err.msg().contains('out-of-order')
	}
}

fn test_integer_constant_accepts_v_casts_and_separators() {
	assert integer_constant('pub const aperture = u64(0xffff_ffae_1000_0000)', 'aperture', 'sample')! == u64(0xffffffae10000000)
}

fn test_checked_in_g13_contract_matches_local_m1n1() {
	if !os.is_dir(g13layout.default_m1n1()) { return }
	results := check_m1n1(g13layout.default_m1n1())!
	assert 'retry-safe reprotect/invalidate/unmap/invalidate teardown' in results
	assert 'TX ring entry barrier before write-pointer publication' in results
}

fn test_section_distinguishes_missing_start_and_terminator() {
	assert section('before START body END after', 'START', 'END', 'sample')! == 'START body '
	if _ := section('absent', 'START', 'END', 'sample') {
		assert false
	} else {
		assert err.msg() == "sample: missing 'START'"
	}
	if _ := section('START only', 'START', 'END', 'sample') {
		assert false
	} else {
		assert err.msg() == "sample: missing terminator 'END'"
	}
}

fn test_integer_constant_observes_word_boundaries_and_errors() {
	assert integer_constant('other_aperture = 0x12\naperture = 0x34', 'aperture', 'sample')! == 0x34
	if _ := integer_constant('aperture = value', 'aperture', 'sample') {
		assert false
	} else {
		assert err.msg() == 'sample: cannot find numeric constant aperture'
	}
}

fn test_asahi_contract_requires_teardown_and_publication_order() {
	fixture := os.join_path(os.temp_dir(), 'vinix-g13-contract-' + os.getpid().str())
	defer { os.rmdir_all(fixture) or { panic(err) } }
	directory := os.join_path(fixture, 'drivers/gpu/drm/asahi')
	os.mkdir_all(directory)!
	mmu := 'impl Drop for KernelMapping\nis_cached_noncoherent remap_uncached_and_flush unmap_pages tlbi_range\n/// Shared UAT global'
	channel := '    pub(crate) fn put\nself.ring.ring[self.wptr as usize] = *msg mem::sync() T::set_wptr\n    /// Wait for'
	os.write_file(os.join_path(directory, 'mmu.rs'), mmu)!
	os.write_file(os.join_path(directory, 'channel.rs'), channel)!
	assert check_asahi(fixture)! == ['Asahi KernelMapping cache-safe teardown order',
		'Asahi TX ring barrier before write-pointer publication']
	os.write_file(os.join_path(directory, 'mmu.rs'), mmu.replace('unmap_pages tlbi_range', 'tlbi_range unmap_pages'))!
	if _ := check_asahi(fixture) {
		assert false
	} else {
		assert err.msg() == "Asahi cache-safe unmap: missing or out-of-order 'tlbi_range'"
	}
	os.write_file(os.join_path(directory, 'mmu.rs'), mmu)!
	os.write_file(os.join_path(directory, 'channel.rs'), channel.replace('mem::sync() T::set_wptr', 'T::set_wptr mem::sync()'))!
	if _ := check_asahi(fixture) {
		assert false
	} else {
		assert err.msg() == "Asahi TX channel publication: missing or out-of-order 'T::set_wptr'"
	}
}

fn test_unknown_checkout_revision_is_bounded_unknown() {
	assert git_revision('/nonexistent/vinix-g13-contract') == 'unknown'
}
