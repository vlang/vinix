// SPDX-License-Identifier: GPL-2.0-or-later
module main

import io
import json2
import os
import strconv
import tarcore
import tarstream
import time
import tools.packages.pkgcore
import tools.packages.pkgprotocol

const config = 'etc/vinix-packages/config.json'
const declaration = 'usr/share/vinix-packages/applications.json'
const repositories = 'usr/share/vinix-packages/repositories'

fn command(argv []string) (int, string) {
	mut child := os.new_process(argv[0])
	defer { child.close() }
	child.set_args(argv[1..])
	child.set_redirect_stdio_merged()
	child.run()
	output := child.stdout_slurp()
	child.wait()
	return child.code, output
}

fn checked(argv []string) ! {
	code, output := command(argv)
	if code != 0 { return error(argv[0] + ': ' + output) }
}

fn repair_checksum(mut header []u8) {
	for index in 148 .. 156 { header[index] = ` ` }
	mut sum := i64(0)
	for byte in header { sum += i64(byte) }
	text := strconv.format_int(sum, 8)
	for index in 148 .. 154 { header[index] = `0` }
	for index, byte in text { header[154 - text.len + index] = byte }
	header[154] = 0
}

fn append_link_members(mut writer tarcore.Writer, scenario string) ! {
	members := match scenario {
		'unrelated-hard-links' {
			[tarcore.Member{name: './ordinary-file'},
				tarcore.Member{name: './ordinary-link', kind: `1`, linkname: './ordinary-file'},
				tarcore.Member{name: './ordinary-chain', kind: `1`, linkname: '/ordinary-link'},
				tarcore.Member{name: './ordinary-symlink', kind: `2`, linkname: 'ordinary-file'}]
		}
		'package-hard-link' {
			[tarcore.Member{name: './package-copy', kind: `1`, linkname: '/' + config}]
		}
		'hard-link-directory' {
			[tarcore.Member{name: './ordinary-directory', kind: `5`},
				tarcore.Member{name: './directory-link', kind: `1`, linkname: 'ordinary-directory'}]
		}
		'hard-link-forward' {
			[tarcore.Member{name: './ordinary-link', kind: `1`, linkname: 'ordinary-file'},
				tarcore.Member{name: './ordinary-file'}]
		}
		'hard-link-symlink' {
			[tarcore.Member{name: './ordinary-file'},
				tarcore.Member{name: './ordinary-symlink', kind: `2`, linkname: 'ordinary-file'},
				tarcore.Member{name: './ordinary-link', kind: `1`, linkname: 'ordinary-symlink'}]
		}
		'symlink-parent' {
			[tarcore.Member{name: './ordinary-directory', kind: `5`},
				tarcore.Member{name: './ordinary-symlink', kind: `2`, linkname: 'ordinary-directory'},
				tarcore.Member{name: './ordinary-symlink/child'}]
		}
		else { return }
	}
	for member in members { writer.add(member, []u8{})! }
}

fn rewrite_archive(archive string, scenario string) ! {
	mut reader := tarstream.open_plain(archive)!
	defer { reader.close() }
	changed := archive + '.changed'
	mut writer := tarcore.create_stream(changed)!
	defer { writer.close() }
	mut parent := tarcore.Member{}
	for {
		mut member := reader.next() or {
			if err is tarstream.End { break }
			return err
		}
		if member.name == './etc/vinix-packages' && scenario in ['missing-parent', 'late-parent']! {
			parent = member
			continue
		}
		if member.name == './' + config {
			match scenario {
				'legacy-file' { member.kind = 0 }
				'contiguous-file' { member.kind = `7` }
				'pax-path' {
					field := ' path=${member.name}\n'
					line := (field.len + 2).str() + field
					writer.add(tarcore.Member{name: 'extended', kind: `x`, size: line.len}, line.bytes())!
					member.name = './ignored-config.json'
				}
				else {}
			}
		}
		mut header := tarcore.header(member)!
		if member.name == './' + config && scenario in ['non-ustar-header', 'spaced-size']! {
			if scenario == 'non-ustar-header' { header[257] = 0 }
			else { header[124] = ` ` }
			repair_checksum(mut header)
		}
		writer.write(header)!
		reader.copy_to(mut writer)!
		writer.padding(member.size)!
	}
	if scenario == 'late-parent' { writer.add(parent, []u8{})! }
	append_link_members(mut writer, scenario)!
	writer.finish()!
	writer.close_checked()!
	os.rename(changed, archive)!
}

fn copy_gzip_bytes(source string, destination string, mode string, count i64) ! {
	mut input := os.open(source)!
	defer { input.close() }
	mut output := os.open_file(destination, mode)!
	defer { output.close() }
	io.copy_n(mut output, mut input, count)!
}

fn change_gzip(path string, scenario string) ! {
	match scenario {
		'concatenated-gzip-prefix', 'concatenated-gzip-suffix' {
			extra := path + '.extra'
			prefix := scenario == 'concatenated-gzip-prefix'
			os.write_file(extra, if prefix { '' } else { 'second gzip member' })!
			checked(['gzip', '-n', extra])!
			second := extra + '.gz'
			input_path := if prefix { path } else { second }
			copy_gzip_bytes(input_path, if prefix { second } else { path }, 'a',
				i64(os.file_size(input_path)))!
			if prefix { os.rename(second, path)! } else { os.rm(second)! }
		}
		'trailing-gzip-bytes' {
			mut file := os.open_file(path, 'a')!
			defer { file.close() }
			file.write_string('trailing bytes')!
		}
		'bad-gzip-crc', 'bad-gzip-size' {
			offset := if scenario == 'bad-gzip-crc' { i64(-8) } else { i64(-4) }
			mut file := os.open_file(path, 'r+')!
			defer { file.close() }
			file.seek(offset, .end)!
			mut byte := []u8{len: 1}
			if file.read(mut byte)! != 1 { return error('cannot read gzip fixture trailer') }
			byte[0] ^= 1
			file.seek(offset, .end)!
			if file.write(byte)! != 1 { return error('cannot change gzip fixture trailer') }
		}
		'truncated-gzip-trailer' {
			short := path + '.short'
			copy_gzip_bytes(path, short, 'w', i64(os.file_size(path)) - 4)!
			os.rename(short, path)!
		}
		else {}
	}
}

fn append_case_shadow(archive string, root string, work string, scenario string) ! {
	publisher := os.ls(root + '/' + repositories)!
	if publisher.len != 1 { return error('case-shadow fixture requires one signed repository') }
	repository := repositories + '/' + publisher[0]
	mut original := repository + '/index.json'
	mut shadow := repository + '/Index.json'
	if scenario == 'case-shadow-object' {
		objects := os.ls(root + '/' + repository + '/objects')!
		hash := objects.filter(it != it.to_upper())[0] or {
			return error('case-shadow fixture requires an object digest with letters')
		}
		original = repository + '/objects/' + hash
		shadow = repository + '/objects/' + hash.to_upper()
	}
	// A separate source directory keeps the two tar spellings distinct even
	// when the filesystem used to assemble the fixture folds case.
	aliases := work + '/aliases'
	path := aliases + '/' + shadow
	os.mkdir_all(os.dir(path))!
	os.cp(root + '/' + original, path)!
	os.chmod(path, 0o644)!
	checked(['tar', '-rf', archive, '-C', aliases, './' + shadow])!
}

fn make_iso(root string, work string, scenario string) !string {
	tree := work + '/iso'
	os.mkdir_all(tree + '/boot')!
	archive := work + '/initramfs.tar'
	checked(['tar', '--format=ustar', '-cf', archive, '-C', root, '.'])!
	if scenario == 'duplicate' { checked(['tar', '-rf', archive, '-C', root, config])! }
	if scenario in ['case-shadow-index', 'case-shadow-object']! {
		append_case_shadow(archive, root, work, scenario)!
	}
	if scenario in ['missing-parent', 'late-parent', 'legacy-file', 'contiguous-file', 'pax-path',
		'non-ustar-header', 'spaced-size', 'unrelated-hard-links', 'package-hard-link',
		'hard-link-directory', 'hard-link-forward', 'hard-link-symlink', 'symlink-parent']! {
		rewrite_archive(archive, scenario)!
	}
	if scenario == 'wrong-compression' { checked(['bzip2', '-z', archive])! }
	else { checked(['gzip', '-n', archive])! }
	if scenario == 'nested-compression' {
		os.rename(archive + '.gz', archive)!
		checked(['gzip', '-n', archive])!
	}
	change_gzip(archive + '.gz', scenario)!
	suffix := if scenario == 'wrong-compression' { '.bz2' } else { '.gz' }
	os.rename(archive + suffix, tree + '/boot/initramfs.tar.gz')!
	iso := work + '/image.iso'
	checked(['xorriso', '-as', 'mkisofs', '-R', '-o', iso, tree])!
	return iso
}

fn prepare_fixture(architecture string, out string, hosted bool) ! {
	if architecture !in ['aarch64', 'x86_64']! { return error('unsupported fixture architecture') }
	os.mkdir(out, mode: 0o700)!
	root := out + '/staged'
	os.mkdir(root, mode: 0o755)!
	os.mkdir(out + '/bundle', mode: 0o755)!
	os.mkdir_all(out + '/payload/bin')!
	os.write_file(out + '/payload/bin/fixture', 'structural package fixture\n')!
	os.chmod(out + '/payload/bin/fixture', 0o755)!
	manifest := out + '/manifest.json'
	os.write_file(manifest, json2.encode(pkgcore.Package{id: 'receipt-fixture', version: '1.0.0',
		architecture: architecture, kind: 'native', name: 'Receipt fixture', license: 'MIT',
		entrypoint: 'bin/fixture'}))!
	pkgcore.pack(manifest, out + '/payload', out + '/publisher')!
	seed := out + '/fixture-seed'
	key := pkgcore.keygen(seed)!
	defer { os.rm(seed) or {} }
	mut release := pkgcore.publish_release(out + '/publisher', 'fixture', seed, 1,
		time.now().unix() + 86_400, out + '/bundle/fixture')!
	defer { release.close() }
	origin := if hosted { 'https://packages.example.invalid/release/' } else { '' }
	pin := release.repository + ' ' + release.index_sha256
	os.write_file(out + '/indexes.txt', pin + (if hosted { ' ' + origin } else { '' }) + '\n')!
	input := out + '/config.json'
	os.write_file(input, json2.encode(pkgcore.Config{architecture: architecture,
		repositories: [pkgcore.Repository{id: 'fixture', public_key: key,
			url: if hosted { origin } else { 'file:///' + repositories + '/fixture' }}]}))!
	mut configuration := pkgcore.prepare_image_configuration(root, architecture, input)!
	defer { configuration.close() }
	mut bundle := configuration.prepare_repositories_for_index_file(out + '/bundle', out + '/indexes.txt', out)!
	defer { bundle.close() }
	mut applications := configuration.prepare_applications(&bundle, ['receipt-fixture'])!
	defer { applications.close() }
	bundle.publish()!
	configuration.publish()!
	applications.publish(&bundle)!
	bundle.retire()!
}

fn check_origin_notes(tool string, receipt string, work string, arch string, id string, origin string) ! {
	digest := pkgcore.hash_file(receipt)!
	code, output := command([tool, 'origins', receipt, digest])
	expected := if origin == '' { '' } else { '- `${id}` on ${arch} uses `${origin}`\n' }
	if code != 0 || output != expected { return error('unexpected reviewed origins: ' + output) }
	os.write_file(work + '/origin-notes.md', output)!
	code_bad, output_bad := command([tool, 'origins', receipt, '0'.repeat(64)])
	if code_bad == 0 || !output_bad.contains('package receipt changed before release notes') {
		return error('origin renderer accepted a different receipt digest: ' + output_bad)
	}
	os.write_file(work + '/origin-digest-refusal.log', output_bad)!
	if origin == '' { return }

	changed := work + '/origin-rendering.json'
	original := os.read_file(receipt)!
	markdown_url := 'https://packages.example.invalid/cat``alog/<file>'
	os.write_file(changed, original.replace(origin, markdown_url))!
	code_span, output_span := command([tool, 'origins', changed, pkgcore.hash_file(changed)!])
	if code_span != 0 || output_span != '- `${id}` on ${arch} uses ``` ${markdown_url} ```\n' {
		return error('origin Markdown code span did not preserve the exact URL: ' + output_span)
	}
	os.write_file(work + '/origin-markdown.md', output_span)!
	os.write_file(changed, original.replace(origin, 'file:///local/origin'))!
	code_url, output_url := command([tool, 'origins', changed, pkgcore.hash_file(changed)!])
	if code_url == 0 || !output_url.contains('invalid reviewed HTTPS origin') {
		return error('origin notes accepted an invalid HTTPS URL: ' + output_url)
	}
	os.write_file(work + '/origin-url-refusal.log', output_url)!
}

fn check_published_receipt(tool string, iso string, receipt string, work string, origin string) ! {
	original := os.read_file(receipt)!
	code, output := command([tool, 'verify-receipt', iso, receipt])
	os.write_file(work + '/published-verifier.log', output)!
	if code != 0 || output != original { return error('published receipt did not reproduce: ' + output) }

	changed := work + '/changed-receipt.json'
	mut fields := json2.decode[json2.Any](original)!.as_map()
	for key, diagnostic in {
		'iso_sha256': 'ISO SHA-256 differs from the package receipt'
		'configuration_sha256': 'ISO package configuration differs from the preflight selection'
		'deployment_sha256': 'ISO application declaration differs from the preflight selection'
	} {
		actual := fields[key]!
		fields[key] = json2.Any('0'.repeat(64))
		os.write_file(changed, json2.encode(fields))!
		refused, reason := command([tool, 'verify-receipt', iso, changed])
		os.write_file(work + '/published-' + key + '-refusal.log', reason)!
		if refused == 0 || !reason.contains(diagnostic) {
			return error('published receipt accepted a different ${key}: ' + reason)
		}
		fields[key] = actual
	}
	if origin != '' {
		os.write_file(changed, original.replace(origin, origin + 'changed'))!
		refused, reason := command([tool, 'verify-receipt', iso, changed])
		os.write_file(work + '/published-origin-refusal.log', reason)!
		if refused == 0 || !reason.contains('ISO package URL differs from the reviewed HTTPS origin') {
			return error('published receipt accepted a different reviewed origin: ' + reason)
		}
	}
	fields['format'] = json2.Any(2)
	os.write_file(changed, json2.encode(fields))!
	refused, reason := command([tool, 'verify-receipt', iso, changed])
	os.write_file(work + '/published-format-refusal.log', reason)!
	if refused == 0 || !reason.contains('invalid ISO package receipt') {
		return error('unsupported published receipt format was accepted: ' + reason)
	}
}

fn check_archive_receipt(tool string, iso string, receipt string, work string) ! {
	release_time := time.now().unix() - 1
	code, output := command([tool, 'verify-archive', iso, receipt, release_time.str()])
	os.write_file(work + '/archive-verifier.log', output)!
	if code != 0 { return error('archive receipt failed verification: ' + output) }
	expected := '{"release_time":${release_time},"receipt":' + os.read_file(receipt)!.trim_space() + '}\n'
	if output != expected {
		return error('archive verification changed the receipt or release time: ' + output)
	}
	for value in ['0', '-1', 'yesterday', (time.now().unix() + 3600).str()] {
		refused, reason := command([tool, 'verify-archive', iso, receipt, value])
		if refused == 0 || !reason.contains('valid past Unix release time') {
			return error('archive verifier accepted an invalid release time: ' + reason)
		}
	}
	refused, reason := command([tool, 'verify-archive', iso, work + '/changed-receipt.json', release_time.str()])
	if refused == 0 || !reason.contains('invalid ISO package receipt') {
		return error('archive verifier accepted an unsupported receipt format: ' + reason)
	}
}

fn check_export_deployment(tool string, iso string, receipt string, work string, architecture string) !string {
	embedded := os.read_file(work + '/root/' + declaration)!
	path := work + '/release lock é; literal.json'
	args := [tool, 'export-deployment', iso, receipt]
	code, output := command([...args, path])
	os.write_file(work + '/export-verifier.log', output)!
	if code != 0 { return error('verified release lock export failed: ' + output) }
	result := json2.decode[json2.Any](output)!.as_map()
	assert result['format']!.int() == 1 && result['architecture']!.str() == architecture
	assert result['destination']!.str() == path && result['iso_sha256']!.str() == pkgcore.hash_file(iso)!
	assert result['sha256']!.str() == pkgcore.hash_file(path)! && os.read_file(path)! == embedded
	assert os.lstat(path)!.mode & 0o777 == 0o644

	occupied, occupied_text := command([...args, path])
	assert occupied == 1 && occupied_text.contains('already exists') && os.read_file(path)! == embedded
	alias := work + '/release-lock-alias.json'
	os.symlink('absent.json', alias)!
	refused, refused_text := command([...args, alias])
	assert refused == 1 && refused_text.contains('already exists') && os.is_link(alias)
	assert !os.exists(work + '/absent.json')

	wrong := work + '/wrong-export-receipt.json'
	mut receipt_fields := json2.decode[json2.Any](os.read_file(receipt)!)!.as_map()
	receipt_fields['iso_sha256'] = json2.Any('0'.repeat(64))
	os.write_file(wrong, json2.encode(receipt_fields))!
	absent := work + '/no-export.json'
	bad_iso, bad_iso_text := command([tool, 'export-deployment', iso, wrong, absent])
	assert bad_iso == 1 && bad_iso_text.contains('ISO SHA-256 differs') && !os.exists(absent)
	bad_time, _ := command([...args, absent, '0'])
	assert bad_time == 1 && !os.exists(absent)

	historical := work + '/historical-lock.json'
	release_time := time.now().unix() - 1
	old_code, old_output := command([...args, historical, release_time.str()])
	os.write_file(work + '/export-archive-verifier.log', old_output)!
	assert old_code == 0 && os.read_file(historical)! == embedded
	assert json2.decode[json2.Any](old_output)!.as_map()['release_time']!.i64() == release_time
	return path
}

fn check_installed_receipt(tool string, iso string, receipt string, work string, roots []string) ! {
	root := work + '/root'
	// A host fixture mounts the image under an alternate root. Map local
	// file URLs to that root while keeping the signed publisher identity.
	config_path := root + '/' + config
	configuration := pkgcore.load_config(root)!
	repository := configuration.repositories[0]
	if repository.url.starts_with('file://') {
		os.write_file(config_path, json2.encode(pkgcore.Config{ ...configuration,
			repositories: [pkgcore.Repository{ ...repository, url: 'file://' + root + '/' + repositories + '/' + repository.id }] }))!
	}
	service := pkgcore.Service{ root: root, offline: true }
	mut catalog := service.refresh()!
	catalog.close()
	mut state := service.transact('install', roots, pkgcore.TransactionOptions{})!
	defer { state.close() }
	snapshot := work + '/installed.json'
	saved_path := work + '/snapshot-receipt.json'
	mut saved := service.save_deployment_snapshot(snapshot, [])!
	defer { saved.close() }
	os.write_file(saved_path, json2.encode(saved) + '\n')!
	args := [tool, 'verify-installed', iso, receipt]
	code, output := command([...args, snapshot, saved_path])
	os.write_file(work + '/installed-verifier.log', output)!
	if code != 0 { return error('saved release coverage refused: ' + output) }
	report := json2.decode[json2.Any](output)!.as_map()
	coverage := report['coverage']!.as_map()
	assert report['format']!.int() == 1 && report['snapshot_sha256']!.str() == saved.sha256
	assert output.contains('"receipt":' + os.read_file(receipt)!.trim_space() + ',')
	assert coverage['architecture']!.str() == saved.architecture
	assert coverage['deployment_sha256']!.str() == report['receipt']!.as_map()['deployment_sha256']!.str()
	assert coverage['generation']!.u64() == state.generation && coverage['matches']!.bool()
	assert coverage['rows']!.as_array().len == int(saved.packages)

	release_time := time.now().unix() - 1
	historical_code, historical_output := command([...args, snapshot, saved_path, release_time.str()])
	os.write_file(work + '/installed-archive-verifier.log', historical_output)!
	assert historical_code == 0
	assert json2.decode[json2.Any](historical_output)!.as_map()['release_time']!.i64() == release_time
	invalid_time, _ := command([...args, snapshot, saved_path, '0'])
	assert invalid_time == 1

	// Keep the installed proof intact and construct independent refusal inputs.
	before := os.read_file(snapshot)!
	changed_snapshot := work + '/changed-snapshot.json'
	os.write_file(changed_snapshot, before + ' ')!
	bad_digest, bad_digest_text := command([...args, changed_snapshot, saved_path])
	assert bad_digest == 1 && bad_digest_text.contains('snapshot SHA-256 differs')
	alias := work + '/snapshot-alias.json'
	os.symlink(snapshot, alias)!
	bad_alias, bad_alias_text := command([...args, alias, saved_path])
	assert bad_alias == 1 && bad_alias_text.contains('bounded regular file')
	changed_saved := work + '/changed-snapshot-receipt.json'
	os.write_file(changed_saved, json2.encode(pkgprotocol.DeploymentSnapshotSaved{ ...saved, packages: saved.packages + 1 }))!
	bad_count, bad_count_text := command([...args, snapshot, changed_saved])
	assert bad_count == 1 && bad_count_text.contains('snapshot counts differ')
	os.write_file(changed_saved, json2.encode(pkgprotocol.DeploymentSnapshotSaved{ ...saved,
		architecture: if saved.architecture == 'aarch64' { 'x86_64' } else { 'aarch64' } }))!
	bad_arch, bad_arch_text := command([...args, snapshot, changed_saved])
	assert bad_arch == 1 && bad_arch_text.contains('snapshot architecture differs')
	mut document := pkgprotocol.decode_deployment_document(before)!
	defer { document.close() }
	mut bad_roots := document.packages.clone()
	bad_roots[0] = 'absent-snapshot-root'
	os.write_file(changed_snapshot, (pkgprotocol.DeploymentDocument{ ...document, packages: bad_roots }).encode()!)!
	os.write_file(changed_saved, json2.encode(pkgprotocol.DeploymentSnapshotSaved{ ...saved,
		sha256: pkgcore.hash_file(changed_snapshot)! }))!
	bad_root, bad_root_text := command([...args, changed_snapshot, changed_saved])
	assert bad_root == 1 && bad_root_text.contains('installed snapshot root is absent')
	bad_iso, bad_iso_text := command([tool, 'verify-installed', iso, work + '/changed-receipt.json', snapshot, saved_path])
	assert bad_iso == 1 && bad_iso_text.contains('invalid ISO package receipt')
	assert os.read_file(snapshot)! == before && pkgcore.hash_file(snapshot)! == saved.sha256
	assert service.state()! == state

	mut removed := service.transact('remove', roots, pkgcore.TransactionOptions{})!
	defer { removed.close() }
	empty_snapshot := work + '/after-removal.json'
	mut empty := service.save_deployment_snapshot(empty_snapshot, [])!
	defer { empty.close() }
	empty_receipt := work + '/after-removal-receipt.json'
	os.write_file(empty_receipt, json2.encode(empty) + '\n')!
	drift, drift_text := command([...args, empty_snapshot, empty_receipt])
	os.write_file(work + '/installed-drift.log', drift_text)!
	assert drift == 3
	result := json2.decode[json2.Any](drift_text)!.as_map()
	reported_drift := result['coverage']!.as_map()
	assert !reported_drift['matches']!.bool()
	assert result['snapshot_sha256']!.str() == empty.sha256
	rows := reported_drift['rows']!.as_array()
	assert rows.len == int(saved.packages)
	for row in rows { assert row.as_map()['status']!.str() == 'missing' }
	println('ISO installed coverage exact receipt, saved snapshot, archive time, drift and input refusals PASS')

	release_lock := check_export_deployment(tool, iso, receipt, work, saved.architecture)!
	mut proposal := service.review_deployment_additions(release_lock)!
	defer { proposal.close() }
	assert proposal.operation == 'deploy-add' && proposal.requested == state.requested
	assert proposal.rows.len == state.packages.len && proposal.rows.all(it.action == 'install')
	assert service.state()! == removed
	mut repaired := service.apply_deployment_additions(release_lock, proposal.fingerprint)!
	defer { repaired.close() }
	assert repaired.requested == state.requested && repaired.packages == state.packages
	println('ISO deployment export exact lock, exclusive publication, historical read and reviewed recovery PASS')
	check_offline_export(tool, iso, receipt, work, state)!
}

fn check_offline_export(tool string, iso string, receipt string, work string, expected pkgcore.State) ! {
	media := work + '/offline-media'
	root := work + '/root'
	args := [tool, 'export-offline', iso, receipt]
	code, output := command([...args, media])
	os.write_file(work + '/offline-media-export.log', output)!
	if code != 0 { return error('offline media export failed: ' + output) }
	report := json2.decode[json2.Any](output)!.as_map()
	assert report['format']!.int() == 1 && report['destination']!.str() == media
	assert output.contains('"receipt":' + os.read_file(receipt)!.trim_space() + '}')
	deployment := media + '/' + pkgprotocol.deployment_mirror_filename
	assert os.read_file(deployment)! == os.read_file(root + '/' + declaration)!
	assert os.lstat(deployment)!.mode & 0o7777 == 0o644
	assert os.lstat(media)!.mode & 0o7777 == 0o755
	mut config_document := pkgcore.load_config(root)!
	defer { config_document.close() }
	repository := config_document.repositories[0]
	assert os.ls(media)!.sorted() == [pkgprotocol.deployment_mirror_filename, repository.id].sorted()
	original := root + '/' + repositories + '/' + repository.id
	exported := media + '/' + repository.id
	for metadata in ['index.json', 'index.sig'] {
		assert os.read_file(exported + '/' + metadata)! == os.read_file(original + '/' + metadata)!
	}
	objects := os.ls(original + '/objects')!.sorted()
	assert os.ls(exported + '/objects')!.sorted() == objects
	for object in objects { assert pkgcore.hash_file(exported + '/objects/' + object)! == object }

	occupied, _ := command([...args, media])
	assert occupied == 1
	assert os.read_file(deployment)! == os.read_file(root + '/' + declaration)!
	dangling := work + '/offline-dangling'
	os.symlink(work + '/missing-media', dangling)!
	alias, _ := command([...args, dangling])
	assert alias == 1 && os.is_link(dangling) && !os.exists(work + '/missing-media')
	bad_receipt := work + '/offline-wrong-iso-receipt.json'
	os.write_file(bad_receipt, os.read_file(receipt)!.replace(pkgcore.hash_file(iso)!, '0'.repeat(64)))!
	missing := work + '/offline-refused'
	wrong_digest, message := command([tool, 'export-offline', iso, bad_receipt, missing])
	assert wrong_digest == 1 && message.contains('ISO SHA-256 differs') && !os.exists(missing)
	assert !os.ls(work)!.any(it.starts_with('.vinix-iso-offline-'))

	// Exercise the copied media from an empty store with only the original key
	// and the new local URL. Local enrollment and deployment each need a review.
	fresh := work + '/offline-clean-root'
	os.mkdir_all(os.dir(fresh + '/' + config))!
	os.write_file(fresh + '/' + config, json2.encode(pkgcore.Config{ architecture: config_document.architecture }))!
	local := pkgcore.Repository{ ...repository, url: 'file://' + exported }
	trust := pkgcore.review_repository(fresh, 'enroll', local, true)!
	assert trust.index_sha256 == pkgcore.hash_file(original + '/index.json')!
	mut enrolled := pkgcore.enroll_repository_reviewed(fresh, local, true, trust.fingerprint)!
	defer { enrolled.close() }
	service := pkgcore.Service{ root: fresh, offline: true }
	mut catalog := service.refresh()!
	catalog.close()
	mut review := service.review_deployment_additions(deployment)!
	defer { review.close() }
	assert service.state()!.packages.len == 0
	mut installed := service.apply_deployment_additions(deployment, review.fingerprint)!
	defer { installed.close() }
	assert installed.requested == expected.requested && installed.packages == expected.packages
	println('ISO offline media preserves signed repositories and lock, refuses replacements and restores through reviewed enrollment and deployment on a clean offline root PASS')
}

fn run() ! {
	if os.args.len == 4 && os.args[1] in ['fixture', 'hosted-fixture']! {
		return prepare_fixture(os.args[2], os.abs_path(os.args[3]), os.args[1] == 'hosted-fixture')
	}
	if os.args.len != 5 {
		return error('usage: iso-package-receipt-check fixture|hosted-fixture ARCH NEW_INPUTS | RECEIPT_TOOL STAGED_PACKAGE_ROOT PLAN.json NEW_WORK')
	}
	tool := os.abs_path(os.args[1])
	source := os.abs_path(os.args[2])
	plan := os.abs_path(os.args[3])
	out := os.abs_path(os.args[4])
	if os.exists(out) || os.is_link(out) { return error('expected a new output directory') }
	os.mkdir(out, mode: 0o700)!
	os.setenv('COPYFILE_DISABLE', '1', true)
	plan_document := json2.decode[json2.Any](os.read_file(plan)!)!.as_map()
	planned_publisher := plan_document['publishers']!.as_array()[0]!.as_map()
	origin := (planned_publisher['reviewed_origin'] or { json2.Any('') }).str()
	mut scenarios := ['match', 'wrong-configuration', 'missing-declaration', 'wrong-object', 'wrong-signature', 'stale-index',
		'alias', 'duplicate', 'blocked-parent', 'search-only-parent', 'missing-parent', 'late-parent', 'legacy-file',
		'contiguous-file', 'pax-path', 'non-ustar-header', 'spaced-size', 'wrong-compression', 'nested-compression',
		'concatenated-gzip-prefix', 'concatenated-gzip-suffix', 'trailing-gzip-bytes', 'bad-gzip-crc',
		'bad-gzip-size', 'truncated-gzip-trailer', 'case-shadow-index', 'case-shadow-object',
		'unrelated-hard-links', 'package-hard-link', 'hard-link-directory', 'hard-link-forward',
		'hard-link-symlink', 'symlink-parent']
	if origin != '' { scenarios << ['wrong-reviewed-origin', 'wrong-hosted-configuration'] }
	for scenario in scenarios {
		work := out + '/' + scenario
		root := work + '/root'
		os.mkdir_all(root)!
		checked(['cp', '-Rp', source + '/.', root])!
		bundle := root + '/' + repositories
		ids := os.ls(bundle)!
		if ids.len != 1 { return error('fixture requires one signed repository') }
		repository := bundle + '/' + ids[0]
		mut selection := plan
		mut diagnostic := ''
		match scenario {
			'wrong-configuration' {
				value := json2.decode[pkgcore.Config](os.read_file(root + '/' + config)!)!
				os.write_file(root + '/' + config, json2.encode(pkgcore.Config{...value, launch_user: 'receipt-check'}))!
				diagnostic = 'configuration differs'
			}
			'missing-declaration' {
				os.rm(root + '/' + declaration)!
				diagnostic = 'application declaration differs'
			}
			'wrong-object' {
				objects := os.ls(repository + '/objects')!
				if objects.len == 0 { return error('test release has no payloads') }
				os.write_file(repository + '/objects/' + objects[0], 'changed fixture object')!
				diagnostic = 'object'
			}
			'wrong-signature' {
				os.write_file(repository + '/index.sig', '0'.repeat(128) + '\n')!
				diagnostic = 'signature'
			}
			'stale-index' {
				mut record := json2.decode[json2.Any](os.read_file(plan)!)!.as_map()
				mut publisher := record['publishers']!.as_array()[0].as_map()
				publisher['sequence'] = json2.Any(publisher['sequence']!.int() + 1)
				record['publishers'] = json2.Any([json2.Any(publisher)])
				selection = work + '/stale-plan.json'
				os.write_file(selection, json2.encode(record))!
				diagnostic = 'signed repositories differ'
			}
			'wrong-reviewed-origin', 'wrong-hosted-configuration' {
				mut record := json2.decode[json2.Any](os.read_file(plan)!)!.as_map()
				different := origin.trim_right('/') + '/changed'
				if scenario == 'wrong-reviewed-origin' {
					mut publisher := record['publishers']!.as_array()[0].as_map()
					publisher['reviewed_origin'] = json2.Any(different)
					record['publishers'] = json2.Any([json2.Any(publisher)])
				} else {
					path := root + '/' + config
					os.write_file(path, os.read_file(path)!.replace(origin, different))!
					record['configuration_sha256'] = json2.Any(pkgcore.hash_file(path)!)
				}
				selection = work + '/changed-plan.json'
				os.write_file(selection, json2.encode(record))!
				diagnostic = 'ISO package URL differs from the reviewed HTTPS origin'
			}
			'alias' {
				original := root + '/' + config
				os.rename(original, original + '.saved')!
				os.symlink('config.json.saved', original)!
				diagnostic = 'invalid ISO package file'
			}
			'duplicate' { diagnostic = 'duplicate ISO package member' }
			'blocked-parent' {
				os.chmod(root + '/etc/vinix-packages', 0o700)!
				diagnostic = 'invalid ISO package directory'
			}
			'search-only-parent' {
				os.chmod(root + '/usr/share/vinix-packages', 0o711)!
				diagnostic = 'invalid ISO package directory'
			}
			'missing-parent', 'late-parent' { diagnostic = 'ISO package directory must precede its members' }
			'legacy-file', 'contiguous-file', 'pax-path' { diagnostic = 'unsupported boot USTAR member type' }
			'non-ustar-header' { diagnostic = 'ISO initramfs requires POSIX USTAR headers' }
			'spaced-size' { diagnostic = 'invalid boot USTAR mode or size' }
			'wrong-compression' { diagnostic = 'ISO initramfs must be gzip-compressed' }
			'nested-compression' { diagnostic = 'ISO initramfs requires POSIX USTAR headers' }
			'concatenated-gzip-prefix', 'concatenated-gzip-suffix', 'trailing-gzip-bytes' {
				diagnostic = 'data follows the ISO initramfs gzip member'
			}
			'bad-gzip-crc', 'bad-gzip-size' { diagnostic = 'invalid ISO initramfs gzip stream' }
			'truncated-gzip-trailer' { diagnostic = 'truncated ISO initramfs gzip stream' }
			'case-shadow-index', 'case-shadow-object' { diagnostic = 'invalid ISO repository member' }
			'package-hard-link' { diagnostic = 'ISO hard link targets a package member' }
			'hard-link-directory', 'hard-link-forward', 'hard-link-symlink' {
				diagnostic = 'ISO hard link requires an earlier regular file'
			}
			'symlink-parent' { diagnostic = 'ISO initramfs member traverses a symbolic link' }
			else {}
		}
		iso := make_iso(root, work, scenario)!
		code, output := command([tool, 'verify', iso, selection])
		os.write_file(work + '/verifier.log', output)!
		if scenario in ['match', 'unrelated-hard-links']! {
			if code != 0 { return error('matching ISO refused: ' + output) }
			report := json2.decode[json2.Any](output)!.as_map()
			mut document := pkgprotocol.decode_deployment_document(os.read_file(root + '/' + declaration)!)!
			defer { document.close() }
			if report['iso_sha256']!.str() != pkgcore.hash_file(iso)!
				|| report['architecture']!.str() != document.architecture
				|| report['applications']!.as_array().map(it.str()) != document.packages
				|| report['publishers']!.as_array().len != 1 {
				return error('ISO receipt differs from the embedded inputs')
			}
			publisher := report['publishers']!.as_array()[0].as_map()
			if (publisher['reviewed_origin'] or { json2.Any('') }).str() != origin {
				return error('ISO receipt differs from the reviewed HTTPS origin')
			}
			if origin != '' && scenario == 'match' {
				capture := work + '/private'
				os.mkdir(capture, mode: 0o700)!
				captured_iso := capture + '/image.iso'
				os.cp(iso, captured_iso)!
				os.chmod(captured_iso, 0o400)!
				private_code, private_output := command([tool, 'verify-staged', captured_iso, selection])
				os.write_file(work + '/private-verifier.log', private_output)!
				if private_code != 0 || private_output != output {
					return error('private ISO receipt differs from the copied ISO receipt')
				}
			}
			receipt := work + '/receipt.json'
			os.write_file(receipt, output)!
			arch := if document.architecture == 'aarch64' { 'arm64' } else { 'amd64' }
			checksums := '${pkgcore.hash_file(iso)!}  vinix-${arch}.iso\n' +
				'${pkgcore.hash_file(receipt)!}  vinix-packages-${arch}.json\n'
			check_code, check_output := command([tool, 'checksums', receipt])
			if check_code != 0 || check_output != checksums {
				return error('release checksums differ from the verified ISO and receipt: ' + check_output)
			}
			if scenario == 'match' {
				check_origin_notes(tool, receipt, work, arch, publisher['id']!.str(), origin)!
				check_published_receipt(tool, iso, receipt, work, origin)!
				check_archive_receipt(tool, iso, receipt, work)!
				check_installed_receipt(tool, iso, receipt, work, document.packages)!
			}
		} else {
			if code == 0 || !output.contains(diagnostic) {
				return error('unexpected ISO verification outcome for ${scenario}: ${output}')
			}
			if scenario == 'wrong-object' {
				valid := os.read_file(out + '/match/receipt.json')!
				changed := work + '/media-receipt.json'
				os.write_file(changed, valid.replace(pkgcore.hash_file(out + '/match/image.iso')!, pkgcore.hash_file(iso)!))!
				media := work + '/offline-media'
				refused, reason := command([tool, 'export-offline', iso, changed, media])
				os.write_file(work + '/offline-media-refusal.log', reason)!
				assert refused == 1 && reason.contains(diagnostic) && !os.exists(media)
				assert !os.ls(work)!.any(it.starts_with('.vinix-iso-offline-'))
			}
		}
		println('ISO package receipt ${scenario} PASS')
	}
}

fn main() {
	run() or { eprintln(err); exit(1) }
}
