// SPDX-License-Identifier: GPL-2.0-or-later
module main

import crypto.rand
import crypto.sha256
import json2
import os
import tools.packages.pkgcore

const github_asset_limit = u64(2) * 1024 * 1024 * 1024
const attempt_marker_prefix = '\n<!-- Vinix release attempt: '
const attempt_marker_bytes = 16

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

struct PreparedAsset {
	name   string
	bytes  u64
	sha256 string
}

struct PreparedVerification {
	repo            string
	tag             string
	commit          string
	prerelease      bool
	manifest_sha256 string
	notes_sha256    string
	assets          []PreparedAsset
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
	return parse_manifest(pkgcore.read_metadata(path)!, path)
}

fn parse_manifest(text string, path string) !map[string]string {
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

fn copy_asset(directory string, destination string, name string, maximum u64) !string {
	path := os.join_path(destination, name)
	pkgcore.copy_file(os.join_path(directory, name), path, 0, maximum)!
	os.chmod(path, 0o400)!
	return path
}

fn require_staging_space(directory string, needed u64) ! {
	if needed == 0 { return }
	available := pkgcore.free_bytes(directory)!
	if needed > available {
		return error('insufficient disk space for release staging in ${directory} (${needed} bytes needed, ${available} bytes available)')
	}
}

fn asset_sizes(directory string, names []string, github bool) !map[string]u64 {
	mut sizes := map[string]u64{}
	for name in names {
		if !valid_asset_name(name) || name in sizes {
			return error('invalid or repeated release asset name: ' + name)
		}
		path := os.join_path(directory, name)
		info := os.lstat(path) or { return error('cannot inspect release asset ${path}: ${err}') }
		if info.get_filetype() != .regular { return error('release asset must be a regular file: ' + path) }
		if github && info.size >= github_asset_limit {
			return error('GitHub release asset ${name} is ${info.size} bytes. It must be smaller than 2 GiB.')
		}
		sizes[name] = info.size
	}
	return sizes
}

fn prepare_staging(directory string, destination string, names []string, metadata_bytes u64, github bool) !map[string]u64 {
	sizes := asset_sizes(directory, names, github)!
	mut needed := metadata_bytes
	for _, size in sizes {
		if size > ~u64(0) - needed { return error('release staging size overflows') }
		needed += size
	}
	require_staging_space(os.dir(destination), needed)!
	os.mkdir(destination, mode: 0o700)!
	return sizes
}

fn capture_assets(directory string, destination string, names []string, github bool) ! {
	sizes := prepare_staging(directory, destination, names, 0, github)!
	for name in names {
		copy_asset(directory, destination, name, sizes[name])!
	}
}

fn stage_assets(directory string, entries map[string]string, destination string, uploaded []string, metadata_bytes u64) ! {
	if entries.len == 0 { return error('release checksum manifest is empty') }
	sizes := prepare_staging(directory, destination, entries.keys().filter(it !in uploaded),
		metadata_bytes, true)!
	for name, digest in entries {
		path := if size := sizes[name] {
			copy_asset(directory, destination, name, size)!
		} else {
			os.join_path(directory, name)
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

fn release_metadata(directory string, repo string, tag string, commit string, prerelease bool) !DraftRecovery {
	return DraftRecovery{
		repo: repo
		tag: tag
		commit: commit
		prerelease: prerelease
		manifest: pkgcore.read_metadata(os.join_path(directory, 'SHA256SUMS'))!
		notes: pkgcore.read_metadata(os.join_path(directory, 'RELEASE_NOTES.md'))!
	}
}

fn save_prepared(output string, directory string, repo string, tag string, commit string, prerelease bool) ! {
	metadata := release_metadata(directory, repo, tag, commit, prerelease)!
	pkgcore.atomic_write_new(os.join_path(output, '.prepared-release.json'),
		json2.encode(metadata) + '\n')!
}

fn attempt_marker_suffix(manifest string) string {
	return ' ${sha256.hexhash(manifest)} -->\n'
}

fn prepare_creation(output string, directory string, repo string, tag string, commit string, prerelease bool) ! {
	metadata := release_metadata(directory, repo, tag, commit, prerelease)!
	marker := rand.bytes(attempt_marker_bytes)!.hex()
	notes := metadata.notes + attempt_marker_prefix + marker + attempt_marker_suffix(metadata.manifest)
	record := json2.encode(DraftRecovery{...metadata, notes: notes}) + '\n'
	os.write_file(os.join_path(directory, 'RELEASE_NOTES.md'), notes)!
	os.write_file(creation_path(directory), record)!
	pkgcore.atomic_write_new(creation_path(output), record)!
}

fn read_recovery_text(path string) !string {
	return pkgcore.read_metadata(path) or {
		return error('cannot read release draft recovery record: ${err}')
	}
}

fn parse_recovery(text string, path string) !DraftRecovery {
	recovery := json2.decode[DraftRecovery](text)!
	if recovery.repo == '' || recovery.tag == ''
		|| recovery.commit.len != 40 || recovery.commit.bytes().any(it !in '0123456789abcdef'.bytes())
		|| [recovery.repo, recovery.tag].any(it.contains_any('\t\r\n')) {
		return error('invalid release draft recovery record: ' + path)
	}
	return recovery
}

fn read_recovery(path string) !DraftRecovery {
	return parse_recovery(read_recovery_text(path)!, path)
}

fn parse_creation(text string, path string, tag string) !DraftRecovery {
	creation := parse_recovery(text, path)!
	if creation.id != 0 || creation.tag != tag
		|| !creation.notes.ends_with(attempt_marker_suffix(creation.manifest)) {
		return error('invalid release draft creation record: ' + path)
	}
	return creation
}

fn restore_creation(output string, tag string, directory string) ! {
	path := creation_path(output)
	text := read_recovery_text(path)!
	creation := parse_creation(text, path, tag)!
	os.write_file(creation_path(directory), text)!
	restore_metadata(creation, directory)!
}

fn record_draft(work string, output string, directory string, response string, tag string, id string) !u64 {
	intent := creation_path(output)
	captured := creation_path(directory)
	text := read_recovery_text(captured)!
	if read_recovery_text(intent)! != text { return error('draft creation record changed during publication') }
	creation := parse_creation(text, captured, tag)!
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
	current := read_recovery_text(intent) or {
		return error('draft ${draft.id} recorded. Cannot recheck the creation record: ${err}')
	}
	if current != text {
		return error('draft ${draft.id} recorded. The creation record changed before retirement')
	}
	os.rm(intent) or {
		return error('draft ${draft.id} recorded. Resume with --resume-draft=${draft.id}: ${err}')
	}
	return draft.id
}

fn restore_metadata(recovery DraftRecovery, directory string) ! {
	os.write_file(os.join_path(directory, 'SHA256SUMS'), recovery.manifest)!
	os.write_file(os.join_path(directory, 'RELEASE_NOTES.md'), recovery.notes)!
	println('${recovery.repo}\t${recovery.tag}\t${recovery.commit}\t${recovery.prerelease}')
}

fn matches_prepared_notes(notes string, metadata DraftRecovery, allow_legacy_marker bool) bool {
	if notes == metadata.notes { return true }
	if !allow_legacy_marker { return false }
	prefix := metadata.notes + attempt_marker_prefix
	suffix := attempt_marker_suffix(metadata.manifest)
	marker_end := prefix.len + attempt_marker_bytes * 2
	return notes.len == marker_end + suffix.len && notes.starts_with(prefix) && notes.ends_with(suffix)
		&& notes[prefix.len..marker_end].bytes().all(it in '0123456789abcdef'.bytes())
}

fn read_prepared(output string, tag string, repo string, allow_legacy_marker bool) !DraftRecovery {
	path := os.join_path(output, '.prepared-release.json')
	metadata := read_recovery(path)!
	if metadata.id != 0 || metadata.tag != tag { return error('invalid prepared release record: ' + path) }
	if repo != '' && repo != metadata.repo { return error('release ${tag} belongs to ${metadata.repo}') }
	if pkgcore.read_metadata(os.join_path(output, 'SHA256SUMS'))! != metadata.manifest {
		return error('prepared SHA256SUMS changed')
	}
	notes := pkgcore.read_metadata(os.join_path(output, 'RELEASE_NOTES.md'))!
	if !matches_prepared_notes(notes, metadata, allow_legacy_marker) {
		return error('prepared release notes changed')
	}
	return metadata
}

fn restore_prepared(output string, tag string, directory string, review string) ! {
	metadata := read_prepared(output, tag, '', false)!
	if review != '' {
		text := pkgcore.read_metadata(review)!
		os.write_file(os.join_path(directory, 'prepared-review.json'), text)!
	}
	restore_metadata(metadata, directory)!
}

fn prepared_report(directory string, metadata DraftRecovery, entries map[string]string) !PreparedVerification {
	if entries.len == 0 { return error('release checksum manifest is empty') }
	mut names := entries.keys()
	names.sort()
	sizes := asset_sizes(directory, names, true)!
	mut assets := []PreparedAsset{cap: names.len}
	for name in names {
		assets << PreparedAsset{name: name, bytes: sizes[name], sha256: entries[name]}
	}
	return PreparedVerification{
		repo: metadata.repo
		tag: metadata.tag
		commit: metadata.commit
		prerelease: metadata.prerelease
		manifest_sha256: sha256.hexhash(metadata.manifest)
		notes_sha256: sha256.hexhash(metadata.notes)
		assets: assets
	}
}

fn verify_prepared(output string, tag string, repo string) !PreparedVerification {
	metadata := read_prepared(output, tag, repo, true)!
	entries := parse_manifest(metadata.manifest, os.join_path(output, 'SHA256SUMS'))!
	report := prepared_report(output, metadata, entries)!
	for asset in report.assets {
		if !pkgcore.verified_file(os.join_path(output, asset.name),
			pkgcore.Payload{bytes: asset.bytes, sha256: asset.sha256}) {
			return error('release asset changed after verification: ' + asset.name)
		}
	}
	return report
}

fn stage_reviewed(output string, directory string, stage string, repo string, tag string, commit string, prerelease bool) ! {
	metadata := release_metadata(directory, repo, tag, commit, prerelease)!
	entries := parse_manifest(metadata.manifest, os.join_path(directory, 'SHA256SUMS'))!
	stage_assets(output, entries, stage, [], 0)!
	report := prepared_report(stage, metadata, entries)!
	review := pkgcore.read_metadata(os.join_path(directory, 'prepared-review.json'))!
	if review != json2.encode(report) + '\n' {
		return error('prepared release differs from the reviewed verification report')
	}
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
	manifest := os.join_path(directory, 'SHA256SUMS')
	if names.len == 0 {
		if original != '' { check_assets(original, manifest)! }
		return
	}
	upload_manifest := 'SHA256SUMS' in names
	checksum_bytes := if upload_manifest { os.lstat(manifest)!.size } else { u64(0) }
	metadata_bytes := u64(notes.len) + checksum_bytes
	if original != '' {
		stage_assets(original, read_manifest(manifest)!, stage, draft.assets.map(it.name), metadata_bytes)!
	} else {
		asset_sizes(stage, names.filter(it != 'SHA256SUMS'), true)!
		require_staging_space(stage, metadata_bytes)!
	}
	if upload_manifest { copy_asset(directory, stage, 'SHA256SUMS', checksum_bytes)! }
	copy_asset(directory, stage, 'RELEASE_NOTES.md', u64(notes.len))!
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
	if os.args.len >= 5 && os.args[1] in ['capture', 'capture-upload']! {
		return capture_assets(os.args[2], os.args[3], os.args[4..], os.args[1] == 'capture-upload')
	}
	if os.args.len >= 4 && os.args[1] == 'check-upload-sizes' {
		asset_sizes(os.args[2], os.args[3..], true)!
		return
	}
	if os.args.len == 4 && os.args[1] == 'check' {
		return check_assets(os.args[2], os.args[3])
	}
	if os.args.len == 5 && os.args[1] == 'stage' {
		return stage_assets(os.args[2], read_manifest(os.args[3])!, os.args[4], [], 0)
	}
	if os.args.len == 8 && os.args[1] == 'save-prepared' {
		return save_prepared(os.args[2], os.args[3], os.args[4], os.args[5], os.args[6], os.args[7] == 'true')
	}
	if os.args.len in [5, 6]! && os.args[1] == 'restore-prepared' {
		review := if os.args.len == 6 { os.args[5] } else { '' }
		return restore_prepared(os.args[2], os.args[3], os.args[4], review)
	}
	if os.args.len == 5 && os.args[1] == 'verify-prepared' {
		println(json2.encode(verify_prepared(os.args[2], os.args[3], os.args[4])!))
		return
	}
	if os.args.len == 9 && os.args[1] == 'stage-reviewed' {
		return stage_reviewed(os.args[2], os.args[3], os.args[4], os.args[5], os.args[6], os.args[7],
			os.args[8] == 'true')
	}
	if os.args.len == 8 && os.args[1] == 'prepare-creation' {
		return prepare_creation(os.args[2], os.args[3], os.args[4], os.args[5], os.args[6], os.args[7] == 'true')
	}
	if os.args.len == 5 && os.args[1] == 'restore-creation' {
		return restore_creation(os.args[2], os.args[3], os.args[4])
	}
	if os.args.len == 8 && os.args[1] == 'record-draft' {
		println(record_draft(os.args[2], os.args[3], os.args[4], os.args[5], os.args[6], os.args[7])!)
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
	return error('usage: release-assets record | capture | capture-upload | check-upload-sizes | check | stage | save-prepared | restore-prepared | verify-prepared | stage-reviewed | prepare-creation | restore-creation | record-draft | restore-draft | upload-draft | release-state | verify-release')
}

fn main() {
	run() or { eprintln(err); exit(1) }
}
