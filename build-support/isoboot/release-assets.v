// SPDX-License-Identifier: GPL-2.0-or-later
module main

import crypto.rand
import crypto.sha256
import json2
import os
import tools.packages.pkgcore

struct UploadedAsset {
	name   string
	state  string
	digest string
}

struct Release {
	id         u64
	tag_name   string
	name       string
	draft      bool @[required]
	prerelease bool @[required]
	body       string
	html_url   string
	upload_url string
	assets     []UploadedAsset
}

struct DraftRecovery {
	id         u64
	repo       string
	tag        string
	commit     string
	prerelease bool
	manifest   string
	notes      string
}

fn valid_asset_name(name string) bool {
	if name == '' || name[0] in [u8(`.`), `-`]! { return false }
	if name in ['SHA256SUMS', 'RELEASE_NOTES.md']! { return false }
	for byte in name {
		if !byte.is_alnum() && byte !in [u8(`.`), `-`, `_`]! { return false }
	}
	return true
}

fn read_manifest(path string) !map[string]string {
	text := pkgcore.read_metadata(path)!
	mut entries := map[string]string{}
	if text == '' { return entries }
	if !text.ends_with('\n') { return error('invalid release checksum manifest: ' + path) }
	for line in text[..text.len - 1].split('\n') {
		if line.len <= 66 || line[64..66] != '  ' || !pkgcore.digest_valid(line[..64]) {
			return error('invalid release checksum manifest: ' + path)
		}
		name := line[66..]
		if !valid_asset_name(name) || name in entries {
			return error('invalid or repeated release asset name: ' + name)
		}
		entries[name] = line[..64]
	}
	return entries
}

fn record_assets(directory string, pinned_path string, names []string) ! {
	pinned := read_manifest(pinned_path)!
	mut entries := map[string]string{}
	for name in names {
		if !valid_asset_name(name) || name in entries {
			return error('invalid or repeated release asset name: ' + name)
		}
		// ISO package verification has already captured these exact bytes.
		entries[name] = pinned[name] or { pkgcore.hash_file(os.join_path(directory, name))! }
	}
	for name, _ in pinned {
		if name !in entries { return error('verified package asset is missing from the release: ' + name) }
	}
	for name in names {
		if !name.ends_with('.sha256') { continue }
		payload := name[..name.len - '.sha256'.len]
		digest := entries[payload] or { return error('release checksum has no matching asset: ' + name) }
		text := pkgcore.read_metadata(os.join_path(directory, name))!
		if text != '${digest}  ${payload}\n' || sha256.hexhash(text) != entries[name] {
			return error('release bundle checksum differs from its payload: ' + name)
		}
	}
	for name in names { println('${entries[name]}  ${name}') }
}

fn check_assets(directory string, manifest string) ! {
	entries := read_manifest(manifest)!
	if entries.len == 0 { return error('release checksum manifest is empty') }
	for name, digest in entries {
		if pkgcore.hash_file(os.join_path(directory, name))! != digest {
			return error('release asset changed after verification: ' + name)
		}
	}
}

fn copy_asset(directory string, destination string, name string) !string {
	path := os.join_path(destination, name)
	pkgcore.copy_file(os.join_path(directory, name), path, 0, ~u64(0))!
	os.chmod(path, 0o400)!
	return path
}

fn capture_assets(directory string, destination string, names []string) ! {
	os.mkdir(destination, mode: 0o700)!
	mut seen := map[string]bool{}
	for name in names {
		if !valid_asset_name(name) || name in seen {
			return error('invalid or repeated release asset name: ' + name)
		}
		seen[name] = true
		copy_asset(directory, destination, name)!
	}
}

fn stage_assets(directory string, manifest string, destination string, uploaded []string) ! {
	entries := read_manifest(manifest)!
	if entries.len == 0 { return error('release checksum manifest is empty') }
	os.mkdir(destination, mode: 0o700)!
	for name, digest in entries {
		path := if name in uploaded { os.join_path(directory, name) } else {
			copy_asset(directory, destination, name)!
		}
		if pkgcore.hash_file(path)! != digest {
			return error('release asset changed after verification: ' + name)
		}
	}
}

fn upload_endpoint(release Release, repo string) !string {
	endpoint := 'https://uploads.github.com/repos/${repo}/releases/${release.id}/assets'
	if release.id == 0 || release.upload_url.to_lower() != endpoint.to_lower() + '{?name,label}' {
		return error('GitHub returned an invalid draft upload destination')
	}
	return endpoint
}

fn read_release(response string, id string, tag string, notes string, prerelease bool) !Release {
	release := json2.decode[Release](pkgcore.read_metadata(response)!)!
	if release.id == 0 || (id != '' && release.id.str() != id)
		|| release.tag_name != tag || release.name != 'Vinix ' + tag || release.body != notes
		|| release.prerelease != prerelease || release.html_url == '' {
		return error('GitHub draft metadata changed after creation')
	}
	return release
}

fn creation_path(output string) string {
	return os.join_path(output, '.draft-creation.json')
}

fn prepare_creation(output string, directory string, repo string, tag string, commit string, prerelease bool) ! {
	manifest := pkgcore.read_metadata(os.join_path(directory, 'SHA256SUMS'))!
	notes_path := os.join_path(directory, 'RELEASE_NOTES.md')
	original_notes := pkgcore.read_metadata(notes_path)!
	marker := rand.bytes(16)!.hex()
	notes := original_notes + '\n<!-- Vinix release attempt: ${marker} ${sha256.hexhash(manifest)} -->\n'
	os.write_file(notes_path, notes)!
	pkgcore.atomic_write_new(creation_path(output), json2.encode(DraftRecovery{
		repo: repo
		tag: tag
		commit: commit
		prerelease: prerelease
		manifest: manifest
		notes: notes
	}) + '\n')!
}

fn read_recovery(path string) !DraftRecovery {
	recovery := json2.decode[DraftRecovery](pkgcore.read_metadata(path) or {
		return error('cannot read release draft recovery record: ${err}')
	})!
	if recovery.repo == '' || recovery.tag == ''
		|| recovery.commit.len != 40 || recovery.commit.bytes().any(it !in '0123456789abcdef'.bytes())
		|| [recovery.repo, recovery.tag].any(it.contains_any('\t\r\n')) {
		return error('invalid release draft recovery record: ' + path)
	}
	return recovery
}

fn read_creation(output string, tag string) !DraftRecovery {
	path := creation_path(output)
	creation := read_recovery(path)!
	if creation.id != 0 || creation.tag != tag
		|| !creation.notes.ends_with(' ${sha256.hexhash(creation.manifest)} -->\n') {
		return error('invalid release draft creation record: ' + path)
	}
	return creation
}

fn record_draft(work string, output string, response string, tag string, id string) !u64 {
	creation := read_creation(output, tag)!
	draft := read_release(response, id, tag, creation.notes, creation.prerelease)!
	if !draft.draft { return error('GitHub did not create a draft release') }
	upload_endpoint(draft, creation.repo)!
	if draft.assets.len != 0 { return error('new GitHub draft already contains assets') }
	path := os.join_path(work, 'draft-${draft.id}.json')
	record := json2.encode(DraftRecovery{...creation, id: draft.id}) + '\n'
	if os.exists(path) {
		// The earlier conversion may have stopped after writing the record.
		if pkgcore.read_metadata(path)! != record {
			return error('conflicting recovery record for GitHub draft ${draft.id}')
		}
	} else {
		pkgcore.atomic_write_new(path, record)!
	}
	os.rm(creation_path(output)) or {
		return error('draft ${draft.id} recorded. Resume with --resume-draft=${draft.id}: ${err}')
	}
	return draft.id
}

fn restore_metadata(recovery DraftRecovery, directory string) ! {
	os.write_file(os.join_path(directory, 'SHA256SUMS'), recovery.manifest)!
	os.write_file(os.join_path(directory, 'RELEASE_NOTES.md'), recovery.notes)!
	println('${recovery.repo}\t${recovery.tag}\t${recovery.commit}\t${recovery.prerelease}')
}

fn restore_draft(work string, id string, directory string) ! {
	if id == '' || id.bytes().any(!it.is_digit()) { return error('invalid draft recovery ID') }
	path := os.join_path(work, 'draft-${id}.json')
	recovery := read_recovery(path)!
	if recovery.id.str() != id { return error('invalid release draft recovery record: ' + path) }
	restore_metadata(recovery, directory)!
}

fn missing_assets(directory string, assets []UploadedAsset) ![]string {
	manifest := os.join_path(directory, 'SHA256SUMS')
	mut expected := read_manifest(manifest)!
	if expected.len == 0 { return error('release checksum manifest is empty') }
	expected['SHA256SUMS'] = pkgcore.hash_file(manifest)!
	for asset in assets {
		digest := expected[asset.name] or { return error('unexpected GitHub draft asset: ' + asset.name) }
		if asset.state != 'uploaded' || asset.digest != 'sha256:' + digest {
			return error('GitHub draft asset differs from the verified upload: ' + asset.name)
		}
		expected.delete(asset.name)
	}
	return expected.keys()
}

fn upload_draft(stage string, directory string, response string, repo string, id string, tag string, prerelease bool, original string) ! {
	notes := pkgcore.read_metadata(os.join_path(directory, 'RELEASE_NOTES.md'))!
	draft := read_release(response, id, tag, notes, prerelease)!
	if !draft.draft { return error('GitHub release is already published') }
	endpoint := upload_endpoint(draft, repo)!
	names := missing_assets(directory, draft.assets)!
	if original != '' {
		manifest := os.join_path(directory, 'SHA256SUMS')
		if names.len == 0 { return check_assets(original, manifest) }
		stage_assets(original, manifest, stage, draft.assets.map(it.name))!
	}
	if names.len == 0 { return }
	if 'SHA256SUMS' in names { copy_asset(directory, stage, 'SHA256SUMS')! }
	copy_asset(directory, stage, 'RELEASE_NOTES.md')!
	gh := os.find_abs_path_of_executable('gh')!
	eprintln('Uploading assets to GitHub draft ${draft.id}')
	for start := 0; start < names.len; start += 5 {
		end := if start + 5 < names.len { start + 5 } else { names.len }
		batch := names[start..end]
		mut children := []&os.Process{cap: batch.len}
		for name in batch {
			mut child := os.new_process(gh)
			child.set_args(['api', '--hostname=github.com', endpoint, '--method', 'POST', '-H',
				'Content-Type: application/octet-stream', '-f', 'name=' + name, '--input',
				os.join_path(stage, name), '--silent'])
			child.run()
			children << child
		}
		mut failed := []string{}
		for index, mut child in children {
			if child.pid > 0 { child.wait() }
			if child.code != 0 || child.pid <= 0 { failed << batch[index] }
			child.close()
		}
		if failed.len > 0 { return error('upload failed for GitHub draft ${draft.id}: ' + failed.join(', ')) }
	}
}

fn verify_release(directory string, response string, repo string, id string, tag string, prerelease bool, published bool) !string {
	notes := pkgcore.read_metadata(os.join_path(directory, 'RELEASE_NOTES.md'))!
	release := read_release(response, id, tag, notes, prerelease)!
	if published && release.draft { return error('GitHub release ${id} is still a draft') }
	if !published && !release.draft { return error('GitHub release ${id} is already published') }
	upload_endpoint(release, repo)!
	missing := missing_assets(directory, release.assets)!
	if missing.len > 0 { return error('missing GitHub draft assets: ' + missing.join(', ')) }
	return release.html_url
}

fn run() ! {
	if os.args.len >= 5 && os.args[1] == 'record' {
		return record_assets(os.args[2], os.args[3], os.args[4..])
	}
	if os.args.len >= 5 && os.args[1] == 'capture' {
		return capture_assets(os.args[2], os.args[3], os.args[4..])
	}
	if os.args.len == 4 && os.args[1] == 'check' {
		return check_assets(os.args[2], os.args[3])
	}
	if os.args.len == 5 && os.args[1] == 'stage' {
		return stage_assets(os.args[2], os.args[3], os.args[4], [])
	}
	if os.args.len == 8 && os.args[1] == 'prepare-creation' {
		return prepare_creation(os.args[2], os.args[3], os.args[4], os.args[5], os.args[6], os.args[7] == 'true')
	}
	if os.args.len == 5 && os.args[1] == 'restore-creation' {
		return restore_metadata(read_creation(os.args[2], os.args[3])!, os.args[4])
	}
	if os.args.len == 7 && os.args[1] == 'record-draft' {
		println(record_draft(os.args[2], os.args[3], os.args[4], os.args[5], os.args[6])!)
		return
	}
	if os.args.len == 5 && os.args[1] == 'restore-draft' {
		return restore_draft(os.args[2], os.args[3], os.args[4])
	}
	if os.args.len == 10 && os.args[1] == 'upload-draft' {
		upload_draft(os.args[2], os.args[3], os.args[4], os.args[5], os.args[6], os.args[7],
			os.args[8] == 'true', os.args[9])!
		return
	}
	if os.args.len == 3 && os.args[1] == 'release-state' {
		release := json2.decode[Release](pkgcore.read_metadata(os.args[2])!)!
		println(if release.draft { 'draft' } else { 'published' })
		return
	}
	if os.args.len == 9 && os.args[1] == 'verify-release' && os.args[7] in ['true', 'false']!
		&& os.args[8] in ['draft', 'published']! {
		println(verify_release(os.args[2], os.args[3], os.args[4], os.args[5], os.args[6],
			os.args[7] == 'true', os.args[8] == 'published')!)
		return
	}
	return error('usage: release-assets record | capture | check | stage | prepare-creation | restore-creation | record-draft | restore-draft | upload-draft | release-state | verify-release')
}

fn main() {
	run() or { eprintln(err); exit(1) }
}
