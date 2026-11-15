// SPDX-License-Identifier: GPL-2.0-or-later
module mapsaccountstage

import json2
import modulestream
import os

const browser_engine_path = '/opt/vinix-google-browser/bin/webview-engine'

pub fn browser_engine_manifest(original string, previous string, selected string) !string {
	for sum in [previous, selected] {
		if sum.len != 64 || !sum.bytes().all((it >= `0` && it <= `9`) || (it >= `a` && it <= `f`)) {
			return error('canonical browser engine digest required')
		}
	}
	old := 'file\t' + previous + '\tbin/webview-engine\n'
	if !original.starts_with('vinix-android-browser-launch-v1\n')
		|| original.count('root\t/opt/vinix-google-browser\n') != 1
		|| original.count('engine\tbin/webview-engine\n') != 1 || original.count(old) != 1
		|| original.split_into_lines().filter(it.starts_with('file\t') && it.ends_with('\tbin/webview-engine')).len != 1 {
		return error('unique canonical browser engine manifest entry required')
	}
	return original.replace(old, 'file\t' + selected + '\tbin/webview-engine\n')
}

// Override one engine and its two admission manifests. The original closure,
// principal attestation, helper pins and sandbox policy remain byte-identical.
// Producer/API/ABI qualification is required separately, as for the ART input.
pub fn stage_browser_engine(source string, boot_image string, payload string, baseline string,
	mut inputs map[string]json2.Any, mut deployment map[string]json2.Any) ! {
	info := os.lstat(source)!
	if info.get_filetype() != .regular || info.size <= 0 || info.size > 16 * 1024 * 1024 {
		return error('browser engine must be a bounded regular executable')
	}
	bytes := os.read_bytes(source)!
	defer { unsafe { bytes.free() } }
	if bytes.len != info.size { return error('browser engine size changed during read') }
	elf := inspect_elf(bytes)!
	if u16_at(bytes, 16) != 2 || elf.needed != ['libc.so']
		|| elf.interpreter != '/lib/ld-musl-aarch64.so.1' || elf.runpath != '' || elf.soname != '' {
		return error('browser engine musl executable contract differs')
	}
	mut sum := new_host_sha256()!
	defer { sum.close() }
	sum.update(bytes)!
	selected := sum.finish()!
	previous := inputs[browser_engine_path]!.str()
	if os.exists(baseline) || os.is_link(baseline) { return error('fresh browser baseline extraction required') }
	os.mkdir_all(baseline)!
	paths := ['opt/vinix-maps-account/browser/maps.manifest', 'opt/vinix-maps-account/browser/gms.manifest',
		browser_engine_path.trim_left('/')]
	status := modulestream.extract_members(boot_image, 'maps-account.tar', baseline, paths)!
	if status.producer != 0 || status.consumer != 0 { return error('browser baseline extraction failed') }
	old_source := baseline + browser_engine_path
	if os.lstat(old_source)!.get_filetype() != .regular || digest(old_source)! != previous {
		return error('baseline browser engine differs from deployment')
	}
	mut references := deployment['browser_manifests']!.as_map()
	mut hashes := map[string]string{}
	for uid, name in {'10012': 'maps', '10013': 'gms'} {
		relative := '/opt/vinix-maps-account/browser/' + name + '.manifest'
		reference := references[uid]!.as_map()
		old_path := baseline + relative
		if reference['path']!.str() != relative || os.lstat(old_path)!.get_filetype() != .regular
			|| digest(old_path)! != reference['sha256']!.str() || digest(old_path)! != inputs[relative]!.str() {
			return error('baseline browser principal manifest differs')
		}
		original := os.read_file(old_path)!
		updated := browser_engine_manifest(original, previous, selected)!
		target := payload + relative
		if os.exists(target) || os.is_link(target) { return error('fresh browser manifest destination required') }
		os.mkdir_all(os.dir(target))!
		os.write_file(target, updated)!
		os.chmod(target, 0o444)!
		if os.read_file(target)! != updated { return error('browser manifest readback differs') }
		hash := digest(target)!
		inputs[relative] = json2.Any(hash)
		references[uid] = json2.Any({'path': json2.Any(relative), 'sha256': json2.Any(hash)})
		hashes[name] = hash
	}
	target := payload + browser_engine_path
	if os.exists(target) || os.is_link(target) { return error('fresh browser engine destination required') }
	os.mkdir_all(os.dir(target))!
	os.cp(source, target)!
	os.chmod(target, 0o555)!
	if digest(target)! != selected || digest(source)! != selected { return error('browser engine changed during staging') }
	inputs[browser_engine_path] = json2.Any(selected)
	deployment['browser_manifests'] = json2.Any(references)
	deployment['current_browser_engine'] = json2.Any({
		'source': json2.Any(os.real_path(source)), 'sha256': json2.Any(selected),
		'baseline_sha256': json2.Any(previous), 'maps_manifest_sha256': json2.Any(hashes['maps']!),
		'gms_manifest_sha256': json2.Any(hashes['gms']!)
	})
}
