// SPDX-License-Identifier: GPL-2.0-or-later
module main

import crypto.sha256
import json2
import net.urllib
import os

const x11 = 'vinix-x11-amd64.tar.gz'
const arm_x11 = 'vinix-x11-arm64.tar.gz'
const ios = 'vinix-ios-runtime-arm64'
const upload_changes = ['vinix-amd64.iso', x11, 'SHA256SUMS', 'RELEASE_NOTES.md']
const changed_during_upload = 'changed during upload\n'
const other_commit = '1234567890123456789012345678901234567890'
const release_url = 'https://example.invalid/fixture'
const draft_refusals = ['draft-tag-rebound', 'draft-wrong-upload-url',
	'tag-moved-during-upload', 'tag-removed-during-upload', 'draft-bad-digest',
	'draft-incomplete-asset', 'draft-missing-asset', 'draft-extra-asset', 'draft-changed', 'upload-interrupted']
const publish_refusals = ['publish-readback-lost', 'publish-still-draft',
	'publish-changed-asset', 'publish-tag-moved']

struct FixtureAsset {
	name string
	state string
	digest string
}

struct FixtureUpload {
	path string
	asset FixtureAsset
}

struct FixtureRelease {
	id u64
	tag_name string
	name string
	html_url string = release_url
	body string
	prerelease bool
	upload_url string
mut:
	draft bool = true
	assets []FixtureAsset
}

fn tag_file(remote string, tag string) string {
	return remote + '/' + sha256.hexhash(tag)
}

fn fixture_upload_endpoint(id string) string {
	return 'https://uploads.github.com/repos/local/fixture/releases/${id}/assets'
}

fn command(program string, args []string, root string, environment map[string]string) (int, string) {
	mut child := os.new_process(program)
	defer { child.close() }
	child.set_args(args)
	child.set_work_folder(root)
	child.set_environment(environment)
	child.set_redirect_stdio_merged()
	child.run()
	output := child.stdout_slurp()
	child.wait()
	return child.code, output
}

fn git(root string, args []string) ! {
	code, output := command(os.find_abs_path_of_executable('git')!, args, root, os.environ())
	if code != 0 { return error('fixture git: ' + output) }
}

fn checksum_line(path string) !string {
	return '${sha256.hexhash(os.read_file(path)!)}  ${os.file_name(path)}'
}

fn fixture_bundle(path string) ! {
	os.write_file(path, 'fixture bundle\n')!
	checksum := if os.getenv('VINIX_ASSET_TEST_CASE') == 'bad-build-sidecar' {
		'${'0'.repeat(64)}  ${os.file_name(path)}'
	} else { checksum_line(path)! }
	os.write_file(path + '.sha256', checksum + '\n')!
}

fn fixture_runtime() ! {
	path := os.getenv('VINIX_IOS_BUILD_DIR') + '/staging/usr/bin/run-ios'
	os.mkdir_all(os.dir(path))!
	mut header := []u8{len: 128}
	for index, byte in [u8(127), `E`, `L`, `F`, 2, 1, 1] { header[index] = byte }
	header[16] = 2 // ET_EXEC
	header[18] = 183 // EM_AARCH64
	header[20] = 1 // EV_CURRENT
	header[32] = 64 // Program table offset
	header[52] = 64 // ELF header size
	header[54] = 56 // Program header size
	header[56] = 1 // One program header
	header[64] = 1 // PT_LOAD
	os.write_file_array(path, header)!
	os.chmod(path, 0o755)!
}

fn workspace_contender(root string, phase string, environment map[string]string) (int, string) {
	tag := 'fixture-lock-' + phase
	mut env := environment.clone()
	env['VINIX_ASSET_TEST_OUT'] = root + '/build-release/' + tag
	env['VINIX_ASSET_TEST_CASE'] = 'workspace-contender'
	return command('/bin/bash', [root + '/scripts/deploy-iso.sh', '--tag=' + tag, '--arch=amd64',
		'--no-test', '--no-publish'], root, env)
}

fn reject_workspace_contender(out string, phase string) ! {
	root := os.getenv('VINIX_ASSET_TEST_ROOT')
	code, log := workspace_contender(root, phase, os.environ())
	os.write_file(out + '/fixture-contender-' + phase + '.log', log)!
	if code == 0 || !log.contains('another ISO release is using build-release/work')
		|| os.exists(root + '/build-release/fixture-lock-' + phase) {
		return error('competing release reached the ' + phase + ' workspace\n' + log)
	}
}

fn capture_public_output(out string, scenario string) ! {
	if scenario == 'workspace-lock' { reject_workspace_contender(out, 'upload')! }
	os.cp(out + '/SHA256SUMS', out + '/fixture-original-manifest')!
	os.cp(out + '/RELEASE_NOTES.md', out + '/fixture-original-notes')!
	if scenario == 'output-change-during-upload' {
		for name in upload_changes {
			os.write_file(out + '/' + name, changed_during_upload)!
		}
	}
}

fn read_uploaded_assets(out string, directory string, resumed bool) ![]FixtureAsset {
	mut names := os.ls(directory)!
	names.sort()
	mut uploads := []FixtureUpload{}
	for name in names {
		uploads << json2.decode[FixtureUpload](os.read_file(directory + '/' + name)!)!
	}
	if resumed { return uploads.map(it.asset) }
	if uploads.len == 0 { return error('draft has no recorded uploads') }
	files := uploads.map(it.path)
	stage := os.dir(files[0])
	if stage == out || files.any(os.dir(it) != stage) {
		return error('release handoff did not use a common private staging directory')
	}
	mut digests := uploads.map(it.asset.digest[7..] + '  ' + it.asset.name)
	digests << checksum_line(stage + '/RELEASE_NOTES.md')!
	os.write_file(out + '/fixture-upload-digests', digests.join('\n') + '\n')!
	os.write_file(out + '/fixture-upload', files.join('\n') + '\n')!
	return uploads.map(it.asset)
}

fn capture_boot(out string, scenario string) ! {
	if os.args.len < 3 || os.args[1] != '--out=' + out + '/test' {
		return error('unexpected boot test invocation')
	}
	images := os.args[2..]
	public_image := out + '/vinix-amd64.iso'
	if scenario == 'public-iso-during-boot' {
		original := os.read_file(public_image)!
		os.write_file(public_image, 'temporary public ISO\n')!
		digests := images.map(checksum_line(it)!)
		os.write_file(public_image, original)!
		os.write_file(out + '/fixture-boot-digests', digests.join('\n') + '\n')!
	} else {
		os.write_file(out + '/fixture-boot-digests', images.map(checksum_line(it)!).join('\n') + '\n')!
	}
	os.write_file(out + '/fixture-boot', images.join('\n') + '\n')!
	if scenario == 'boot-copy-changed' {
		replacement := os.dir(images[0]) + '/fixture-replacement'
		os.write_file(replacement, 'changed boot copy\n')!
		os.mv(replacement, images[0])!
	}
}

fn extract_iso(out string, scenario string) !int {
	args := os.args[1..]
	device := args.index('-indev')
	if device < 0 || device + 1 >= args.len { return error('unexpected fixture xorriso invocation') }
	images := out + '/fixture-receipt-isos'
	change_public := scenario == 'public-iso-during-receipt' && !os.exists(images)
	public_image := out + '/vinix-amd64.iso'
	mut original := ''
	if change_public {
		original = os.read_file(public_image)!
		os.write_file(public_image, 'temporary public ISO\n')!
	}
	code, output := command(os.getenv('VINIX_ASSET_TEST_XORRISO'), args, os.getwd(), os.environ())
	if change_public { os.write_file(public_image, original)! }
	mut file := os.open_file(images, 'a')!
	defer { file.close() }
	file.writeln(args[device + 1])!
	print(output)
	return code
}

fn github_release_api(remote string, path string, scenario string) !int {
	tag := os.getenv('VINIX_ASSET_TEST_TAG')
	commit := os.getenv('VINIX_ASSET_TEST_COMMIT')
	draft_id := os.getenv('VINIX_ASSET_TEST_DRAFT_ID')
	upload_endpoint := fixture_upload_endpoint(draft_id)
	local := remote + '/draft.json'
	if path == 'releases' {
		os.write_file(remote + '/release-attempt', os.args[1..].join('\n') + '\n')!
		legacy := os.args.len == 19 && os.args[17..] == ['--jq', '.id']
		if (!legacy && os.args.len != 17) || !os.args[12].starts_with('body=@') {
			return error('expected releases POST with notes')
		}
		body := os.args[12]
		prerelease := scenario == 'draft-only'
		if os.args[3..17] != ['--method', 'POST', '-f', 'tag_name=' + tag, '-f',
			'target_commitish=' + commit, '-f', 'name=Vinix ' + tag, '-F', body, '-F',
			'draft=true', '-F', 'prerelease=' + prerelease.str()]
			|| os.read_file(tag_file(remote, tag))! != commit {
			return error('draft created before checking the exact remote tag commit')
		}
		draft := FixtureRelease{
			id: draft_id.u64()
			tag_name: tag
			name: 'Vinix ' + tag
			body: os.read_file(body[6..])!
			prerelease: prerelease
			upload_url: if scenario == 'draft-wrong-upload-url' {
				fixture_upload_endpoint((draft_id.u64() + 1).str()) + '{?name,label}'
			} else { upload_endpoint + '{?name,label}' }
		}
		os.mkdir(remote + '/uploads')!
		os.write_file(local, json2.encode(draft))!
		println(if legacy { draft_id } else { json2.encode(draft) })
		return 0
	}
	if path != 'releases/' + draft_id { return error('unexpected draft release ID') }
	mut draft := json2.decode[FixtureRelease](os.read_file(local)!)!
	if os.args.len == 3 {
		if !draft.draft && scenario == 'publish-readback-lost' {
			eprintln('fixture could not read published release')
			return 1
		}
		draft.assets = read_uploaded_assets(os.getenv('VINIX_ASSET_TEST_OUT'), remote + '/uploads',
			scenario.starts_with('resume-'))!
		first := if draft.assets.len > 0 { draft.assets[0] } else { FixtureAsset{} }
		match scenario {
			'draft-bad-digest', 'resume-bad-remote' { draft.assets[0] = FixtureAsset{...first, digest: 'sha256:' + '0'.repeat(64)} }
			'draft-incomplete-asset' { draft.assets[0] = FixtureAsset{...first, state: 'starter'} }
			'draft-missing-asset' { draft.assets.delete(0) }
			'draft-extra-asset' { draft.assets << FixtureAsset{...first, name: 'extra.iso'} }
			else {}
		}
		if !draft.draft && scenario in ['publish-changed-asset', 'resume-published-bad-digest']! {
			draft.assets[0] = FixtureAsset{...first, digest: 'sha256:' + '0'.repeat(64)}
		}
		if scenario == 'draft-changed' { draft = FixtureRelease{...draft, tag_name: tag + '-changed'} }
		os.write_file(local, json2.encode(draft))!
		println(json2.encode(draft))
		return 0
	}
	if !draft.draft || os.exists(remote + '/publish-attempt') {
		return error('unexpected draft publish request')
	}
	os.write_file(remote + '/publish-attempt', os.args[1..].join('\n') + '\n')!
	legacy := os.args[3..] == ['--method', 'PATCH', '-F', 'draft=false', '--jq',
		'select(.draft == false) | .html_url']
	if !legacy && os.args[3..] != ['--method', 'PATCH', '-F', 'draft=false', '--silent'] {
		return error('unexpected draft publish request')
	}
	if scenario == 'publish-still-draft' {
		if legacy { println(release_url) }
		return 0
	}
	draft.draft = false
	os.write_file(local, json2.encode(draft))!
	if scenario == 'publish-tag-moved' { os.write_file(tag_file(remote, tag), other_commit)! }
	if scenario == 'publish-response-lost' {
		eprintln('fixture lost the publish response')
		return 1
	}
	if legacy { println(release_url) }
	return 0
}

fn upload_fixture(out string, remote string, scenario string) !int {
	tag := os.getenv('VINIX_ASSET_TEST_TAG')
	if os.args.len != 12 { return error('unexpected draft upload request') }
	file := os.args[10]
	name := os.file_name(file)
	upload_endpoint := fixture_upload_endpoint(os.getenv('VINIX_ASSET_TEST_DRAFT_ID'))
	if os.args[2..] != [upload_endpoint, '--method', 'POST', '-H', 'Content-Type: application/octet-stream',
		'-f', 'name=' + name, '--input', file, '--silent'] {
		return error('unexpected draft upload request')
	}
	if scenario == 'draft-tag-rebound' {
		eprintln('fixture original draft upload URL no longer exists')
		return 1
	}
	draft := json2.decode[FixtureRelease](os.read_file(remote + '/draft.json')!)!
	if !draft.draft || draft.tag_name != tag { return error('upload does not target the draft') }
	if name == 'vinix-amd64.iso' && !scenario.starts_with('resume-') {
		capture_public_output(out, scenario)!
		match scenario {
			'tag-moved-during-upload' { os.write_file(tag_file(remote, tag), other_commit)! }
			'tag-removed-during-upload' { os.rm(tag_file(remote, tag))! }
			'upload-interrupted' {
				eprintln('fixture upload interrupted')
				return 1
			}
			else {}
		}
	}
	target := remote + '/uploads/' + name
	if os.exists(target) { return error('fixture duplicate upload: ' + name) }
	digest := checksum_line(file)![..64]
	os.write_file(target, json2.encode(FixtureUpload{
		path: file
		asset: FixtureAsset{name: name, state: 'uploaded', digest: 'sha256:' + digest}
	}))!
	return 0
}

fn github_api(scenario string) !int {
	remote := os.getenv('VINIX_ASSET_TEST_REMOTE')
	commit := os.getenv('VINIX_ASSET_TEST_COMMIT')
	path := os.args[2]
	prefix := 'repos/local/fixture/'
	if path.starts_with('https://') {
		return upload_fixture(os.getenv('VINIX_ASSET_TEST_OUT'), remote, scenario)
	}
	if path.starts_with(prefix + 'releases') {
		return github_release_api(remote, path[prefix.len..], scenario)
	}
	if path == prefix + 'commits/' + commit && '--silent' in os.args { return 0 }
	if path.starts_with(prefix + 'git/matching-refs/tags/') && os.args[3..] == ['--jq', '.[].ref'] {
		if scenario == 'tag-read-failed' {
			eprintln('fixture GitHub tag lookup failed')
			return 1
		}
		tag := urllib.query_unescape(path.all_after('/git/matching-refs/tags/'))!
		if os.exists(tag_file(remote, tag)) { println('refs/tags/' + tag) }
		// A prefix match is present even when the exact tag is absent.
		println('refs/tags/' + tag + '-another')
		return 0
	}
	if path.starts_with(prefix + 'commits/refs/tags/') && os.args[3..] == ['--jq', '.sha'] {
		tag := urllib.query_unescape(path.all_after('/commits/refs/tags/'))!
		println(os.read_file(tag_file(remote, tag))!)
		return 0
	}
	tag := os.getenv('VINIX_ASSET_TEST_TAG')
	if path != prefix + 'git/refs' || os.args[3..] != ['--method', 'POST', '-f',
		'ref=refs/tags/' + tag, '-f', 'sha=' + commit, '--silent'] {
		return error('unexpected fixture GitHub API invocation: ' + os.args[1..].join(' '))
	}
	file := tag_file(remote, tag)
	if os.exists(file) { return error('fixture attempted to create an existing tag') }
	os.write_file(remote + '/create-tag', os.args[2..].join('\n') + '\n')!
	if scenario == 'tag-create-failed' {
		eprintln('fixture tag creation failed')
		return 1
	}
	os.write_file(file, if scenario == 'tag-raced' { other_commit } else { commit })!
	if scenario in ['tag-raced', 'tag-raced-match']! {
		eprintln('fixture concurrent tag creation')
		return 1
	}
	return 0
}

fn run_stub(name string) !int {
	out := os.getenv('VINIX_ASSET_TEST_OUT')
	scenario := os.getenv('VINIX_ASSET_TEST_CASE')
	match name {
		'xorriso' { return extract_iso(out, scenario) }
		'get-deps' {
			if scenario == 'workspace-lock' { reject_workspace_contender(out, 'build')! }
		}
		'build-aarch64.sh' {}
		'build-desktop-amd64.sh' {
			os.cp(os.getenv('VINIX_ASSET_TEST_AMD64_ISO'), os.getenv('VINIX_AMD64_DESKTOP_ISO'))!
			fixture_bundle(os.getenv('VINIX_AMD64_X11_BUNDLE'))!
		}
		'build-desktop-aarch64.sh' { fixture_bundle(os.getenv('VINIX_X11_BUNDLE'))! }
		'build-ios-aarch64.sh' { fixture_runtime()! }
		'build-aarch64-iso.sh' {
			os.cp(os.getenv('VINIX_ASSET_TEST_ARM64_ISO'), os.getenv('VINIX_AARCH64_ISO'))!
		}
		'test-iso.sh' {
			capture_boot(out, scenario)!
			match scenario {
				'tag-moved' {
					os.write_file(tag_file(os.getenv('VINIX_ASSET_TEST_REMOTE'),
						os.getenv('VINIX_ASSET_TEST_TAG')), other_commit)!
				}
				'x11-after-boot' { os.write_file(out + '/' + x11, 'changed X11 fixture\n')! }
				'ios-pair-after-boot' {
					path := out + '/' + ios
					os.write_file(path, 'changed iOS fixture\n')!
					os.write_file(path + '.sha256', checksum_line(path)! + '\n')!
				}
				'receipt-after-boot' { os.write_file(out + '/vinix-packages-amd64.json', 'changed receipt\n')! }
				else {}
			}
			println('  PASS  qemu-amd64-bios')
		}
		'human-size' {
			if scenario == 'sidecar-at-handoff' {
				os.write_file(out + '/' + x11 + '.sha256', 'changed sidecar\n')!
			} else if scenario == 'manifest-at-handoff' {
				os.write_file(out + '/SHA256SUMS', 'changed checksum list\n')!
			}
			println('fixture size')
		}
		'gh' {
			if os.args[1] == 'auth' { return 0 }
			if os.args[1] == 'api' { return github_api(scenario) }
			upload := out + '/fixture-upload'
			if os.args[1..3] == ['release', 'view'] {
				reserved := os.getenv('VINIX_ASSET_TEST_RESERVED_RELEASE')
				if reserved != '' && os.args.last() == reserved { return 0 }
				if !os.exists(upload) { return 1 }
				println('https://example.invalid/fixture')
			} else if os.args[1..3] == ['release', 'upload'] && scenario == 'draft-tag-rebound' {
				os.write_file(os.getenv('VINIX_ASSET_TEST_REMOTE') + '/replacement-upload',
					'tag lookup uploaded to a replacement release\n')!
				return error('fixture tag lookup reached a replacement draft')
			} else { return error('unexpected fixture gh invocation') }
		}
		else { return error('unknown release fixture program: ' + name) }
	}
	return 0
}

fn prepare_driver(repository string, root string) ! {
	for directory in ['scripts', 'build-support/isoboot', 'build-support/init-aarch64', 'kernel',
		'ui2', 'fake-bin', 'build-amd64-x11/staging', 'build-amd64-network-tools/staging',
		'build-aarch64-userland/staging', 'build-aarch64-x11/staging', 'build-aarch64-network-tools/staging']! {
		os.mkdir_all(root + '/' + directory)!
	}
	for path in ['scripts/deploy-iso.sh', 'build-support/find-v.sh', 'build-support/isoboot/release-assets.v',
		'build-support/isoboot/package-receipt.v', 'build-support/isoboot/release-lock.v',
		'build-support/isoboot/release-tag.v']! {
		os.cp(repository + '/' + path, root + '/' + path)!
	}
	os.write_file(root + '/ui2/v.mod', 'module fixture')!
	os.write_file(root + '/build-support/init-aarch64/initramfs.tar', 'fixture input')!
	for path in ['tools', 'build-support/tarstream', 'build-support/tarcore']! {
		os.symlink(repository + '/' + path, root + '/' + path)!
	}
	for path in ['kernel/get-deps', 'build-support/human-size', 'fake-bin/gh', 'fake-bin/xorriso', 'scripts/build-desktop-amd64.sh',
		'scripts/build-desktop-aarch64.sh', 'scripts/build-aarch64.sh', 'scripts/build-ios-aarch64.sh',
		'build-support/build-aarch64-iso.sh', 'scripts/test-iso.sh']! {
		os.symlink(os.executable(), root + '/' + path)!
	}
	git(root, ['init', '-q'])!
	git(root, ['add', 'scripts', 'build-support', 'kernel'])!
	git(root, ['-c', 'user.name=Fixture', '-c', 'user.email=fixture@example.invalid', '-c', 'commit.gpgsign=false',
		'-c', 'core.hooksPath=/dev/null', 'commit', '-qm', 'Release fixture'])!
}

fn verify_handoff(out string, with_packages bool, scenario string) ! {
	mutated := scenario == 'output-change-during-upload'
	mut names := ['vinix-amd64.iso', 'vinix-arm64.iso', x11, x11 + '.sha256', arm_x11,
		arm_x11 + '.sha256', ios, ios + '.sha256']
	if with_packages { names << ['vinix-packages-amd64.json', 'vinix-packages-arm64.json'] }
	manifest := os.read_file(out + '/fixture-original-manifest')!
	notes := os.read_file(out + '/fixture-original-notes')!
	mut listed := manifest.trim_right('\n').split('\n')
	mut listed_names := listed.map(it.all_after('  '))
	listed_names.sort()
	names.sort()
	if listed_names != names { return error('release checksum list names the wrong assets') }
	for line in listed {
		name := line.all_after('  ')
		if mutated && name in upload_changes { continue }
		if line != checksum_line(out + '/' + name)! {
			return error('release checksum differs from its asset: ' + name)
		}
	}
	if mutated {
		for name in upload_changes {
			if os.read_file(out + '/' + name)! != changed_during_upload {
				return error('release output was not changed during upload: ' + name)
			}
		}
	}
	listed << ['${sha256.hexhash(manifest)}  SHA256SUMS',
		'${sha256.hexhash(notes)}  RELEASE_NOTES.md']
	mut uploaded := os.read_lines(out + '/fixture-upload-digests')!
	listed.sort()
	uploaded.sort()
	if uploaded != listed { return error('release handoff bytes differ from the verified assets') }
	upload_images := os.read_lines(out + '/fixture-upload')!.filter(it.starts_with('/') && it.ends_with('.iso'))
	if with_packages && os.read_lines(out + '/fixture-receipt-isos')! != upload_images {
		return error('package verifier and uploader used different ISO copies')
	}
	if scenario in ['publish-no-test', 'packages-no-test']! {
		if os.exists(out + '/fixture-boot') || notes.contains('### Tested before release') {
			return error('release booted images with --no-test')
		}
		return
	}
	mut boot_digests := os.read_lines(out + '/fixture-boot-digests')!
	boot_digests.sort()
	if boot_digests != uploaded.filter(it.ends_with('.iso')) {
		return error('boot test read different ISO bytes from the uploader')
	}
	if os.read_lines(out + '/fixture-boot')! != upload_images {
		return error('boot test and uploader used different ISO copies')
	}
}

fn resume_attempt(root string, work string, environment map[string]string, scenario string, options []string, expected_error string) ! {
	mut env := environment.clone()
	env['VINIX_ASSET_TEST_CASE'] = scenario
	mut args := [root + '/scripts/deploy-iso.sh', '--yes',
		'--resume-draft=' + env['VINIX_ASSET_TEST_DRAFT_ID']]
	args << options
	code, log := command('/bin/bash', args, root, env)
	os.write_file(work + '/' + scenario + '.log', log)!
	if (code == 0) != (expected_error == '') || !log.contains(expected_error)
		|| log.contains('Building the amd64 image') || log.contains('Boot-testing the images') {
		return error('unexpected recovery outcome for ${scenario}\n${log}')
	}
	println('ISO release assets ${scenario} PASS')
}

fn check_resume(root string, work string, out string, remote string, environment map[string]string) ! {
	id := environment['VINIX_ASSET_TEST_DRAFT_ID']
	record := root + '/build-release/work/draft-' + id + '.json'
	recovery := os.read_file(record)!
	created := os.read_file(remote + '/release-attempt')!
	mut before := os.ls(remote + '/uploads')!
	before.sort()
	iso := out + '/vinix-amd64.iso'
	original := os.read_file(iso)!
	os.write_file(iso, 'changed release ISO')!
	resume_attempt(root, work, environment, 'resume-stale-local', [], 'release asset changed after verification') or {
		os.write_file(iso, original)!
		return err
	}
	os.write_file(iso, original)!
	resume_attempt(root, work, environment, 'resume-bad-remote', [], 'GitHub draft asset differs from the verified upload')!
	resume_attempt(root, work, environment, 'resume-wrong-repo', ['--repo=local/other'], 'belongs to local/fixture')!
	mut after_refusals := os.ls(remote + '/uploads')!
	after_refusals.sort()
	if after_refusals != before || os.exists(remote + '/publish-attempt') {
		return error('refused recovery changed the draft')
	}
	expected := os.read_lines(out + '/SHA256SUMS')!.len + 1
	// The saved metadata is authoritative even if someone changes the public copy.
	os.write_file(out + '/SHA256SUMS', 'changed public checksum list')!
	resume_attempt(root, work, environment, 'resume-complete-draft', ['--draft'], '')!
	finished := json2.decode[FixtureRelease](os.read_file(remote + '/draft.json')!)!
	if !finished.draft || finished.assets.len != expected || os.exists(remote + '/publish-attempt') {
		return error('recovery did not complete the retained draft')
	}
	resume_attempt(root, work, environment, 'resume-publish', [], '')!
	resume_attempt(root, work, environment, 'resume-already-published', [], '')!
	resume_attempt(root, work, environment, 'resume-published-with-draft', ['--draft'], 'is already published')!
	resume_attempt(root, work, environment, 'resume-published-bad-digest', [], 'GitHub draft asset differs from the verified upload')!
	published := json2.decode[FixtureRelease](os.read_file(remote + '/draft.json')!)!
	if published.draft || !os.exists(remote + '/publish-attempt')
		|| os.read_file(record)! != recovery || os.read_file(remote + '/release-attempt')! != created {
		return error('recovery did not publish the original draft')
	}
}

fn run() ! {
	if os.args.len != 5 { return error('usage: iso-release-assets-check VINIX_REPO NEW_STATE AMD64_MATCH_CASE ARM64_MATCH_CASE') }
	repository := os.real_path(os.args[1])
	work := os.abs_path(os.args[2])
	am := os.real_path(os.args[3])
	arm := os.real_path(os.args[4])
	os.mkdir(work, mode: 0o700)!
	root := work + '/driver'
	prepare_driver(repository, root)!
	mut base := os.environ()
	for symbol in base.keys() {
		if symbol.starts_with('VINIX_PACKAGE_IMAGE_') || symbol.starts_with('VINIX_IOS_RELEASE_RUNTIME')
			|| symbol.starts_with('BASH_FUNC_') || symbol == 'BASH_ENV' {
			base.delete(symbol)
		}
	}
	base['PATH'] = root + '/fake-bin:' + os.getenv('PATH')
	base['VINIX_ASSET_TEST_XORRISO'] = os.find_abs_path_of_executable('xorriso')!
	base['VINIX_ASSET_TEST_ROOT'] = root
	base['VINIX_UI2_SOURCE'] = root + '/ui2'
	base['VINIX_ASSET_TEST_AMD64_ISO'] = am + '/image.iso'
	base['VINIX_ASSET_TEST_ARM64_ISO'] = arm + '/image.iso'
	commit_code, commit_output := command(os.find_abs_path_of_executable('git')!, ['rev-parse', 'HEAD'],
		root, base)
	if commit_code != 0 { return error('cannot resolve fixture commit: ' + commit_output) }
	commit := commit_output.trim_space()
	base['VINIX_ASSET_TEST_COMMIT'] = commit
	date_code, date_output := command('/bin/date', ['+%Y-%m-%d'], root, base)
	if date_code != 0 { return error('cannot resolve fixture date: ' + date_output) }
	default_tag := 'iso-' + date_output.trim_space()
	mut scenarios := draft_refusals.clone()
	scenarios << publish_refusals
	scenarios << 'publish-response-lost'
	scenarios << ['draft-only', 'tag-mismatch', 'tag-existing', 'tag-auto', 'tag-moved', 'tag-raced',
		'tag-raced-match', 'tag-create-failed', 'tag-read-failed', 'workspace-lock',
		'public-iso-during-receipt', 'public-iso-during-boot', 'legacy', 'packages', 'output-change-during-upload',
		'bad-build-sidecar', 'boot-copy-changed', 'x11-after-boot', 'ios-pair-after-boot',
		'receipt-after-boot', 'sidecar-at-handoff', 'manifest-at-handoff', 'build-only',
		'publish-no-test', 'packages-no-test']
	for index, scenario in scenarios {
		with_packages := scenario in ['packages', 'receipt-after-boot', 'output-change-during-upload',
			'public-iso-during-boot', 'public-iso-during-receipt', 'packages-no-test']!
		mut environment := base.clone()
		if with_packages {
			for arch, dir in {'X86_64': am, 'AARCH64': arm} {
				environment['VINIX_PACKAGE_IMAGE_CONFIG_' + arch] = dir + '/root/etc/vinix-packages/config.json'
				environment['VINIX_PACKAGE_IMAGE_REPOSITORIES_' + arch] = dir + '/root/usr/share/vinix-packages/repositories'
				environment['VINIX_PACKAGE_IMAGE_APPLICATIONS_' + arch] = dir + '/root/usr/share/vinix-packages/applications.json'
			}
		}
		tag := match scenario {
			'tag-existing' { 'release/fixture-tag+existing' }
			'tag-auto' { default_tag + '-3' }
			else { 'fixture-' + scenario }
		}
		remote := work + '/remote-' + scenario
		os.mkdir(remote)!
		match scenario {
			'tag-auto' {
				os.write_file(tag_file(remote, default_tag), other_commit)!
				environment['VINIX_ASSET_TEST_RESERVED_RELEASE'] = default_tag + '-2'
			}
			'tag-mismatch' { os.write_file(tag_file(remote, tag), other_commit)! }
			'tag-existing', 'tag-moved' { os.write_file(tag_file(remote, tag), commit)! }
			else {}
		}
		out := root + '/build-release/' + tag
		environment['VINIX_ASSET_TEST_TAG'] = tag
		environment['VINIX_ASSET_TEST_REMOTE'] = remote
		environment['VINIX_ASSET_TEST_DRAFT_ID'] = (71439 + index).str()
		environment['VINIX_ASSET_TEST_OUT'] = out
		environment['VINIX_ASSET_TEST_CASE'] = scenario
		mut args := [root + '/scripts/deploy-iso.sh', '--yes',
			'--repo=local/fixture']
		if scenario != 'tag-auto' { args << '--tag=' + tag }
		if scenario == 'draft-only' { args << ['--draft', '--prerelease'] }
		if scenario == 'build-only' { args << ['--arch=amd64', '--no-publish'] }
		if scenario in ['publish-no-test', 'packages-no-test']! { args << ['--no-test'] }
		code, log := command('/bin/bash', args, root, environment)
		os.write_file(work + '/' + scenario + '.log', log)!
		if os.ls(root + '/build-release/work')!.any(it.starts_with('release-assets.')) {
			return error('release left a private staging directory: ' + scenario)
		}
		draft_refusal := scenario in draft_refusals
		expect_create := draft_refusal || scenario in publish_refusals || scenario in ['publish-response-lost', 'draft-only', 'tag-auto', 'tag-raced', 'tag-raced-match', 'tag-create-failed',
			'workspace-lock', 'legacy', 'packages', 'output-change-during-upload', 'public-iso-during-boot',
			'public-iso-during-receipt', 'publish-no-test', 'packages-no-test']!
		if os.exists(remote + '/create-tag') != expect_create {
			return error('unexpected GitHub tag creation for ' + scenario + '\n' + log)
		}
		if scenario in ['workspace-lock', 'legacy', 'packages', 'output-change-during-upload', 'public-iso-during-boot',
			'public-iso-during-receipt', 'publish-no-test', 'packages-no-test', 'tag-existing', 'tag-auto',
			'tag-raced-match', 'draft-only', 'publish-response-lost']! {
			if code != 0 { return error('release fixture failed: ' + scenario + '\n' + log) }
			verify_handoff(out, with_packages, scenario)!
			draft := json2.decode[FixtureRelease](os.read_file(remote + '/draft.json')!)!
			if draft.draft != (scenario == 'draft-only')
				|| os.exists(remote + '/publish-attempt') != (scenario != 'draft-only') {
				return error('unexpected final draft state: ' + scenario)
			}
			if scenario == 'workspace-lock' {
				retry_code, retry_log := workspace_contender(root, 'build', base)
				os.write_file(work + '/workspace-lock-retry.log', retry_log)!
				if retry_code != 0 || !os.is_file(root + '/build-release/fixture-lock-build/SHA256SUMS') {
					return error('release workspace retry failed\n' + retry_log)
				}
			}
		} else if scenario in publish_refusals {
			diagnostic := match scenario {
				'publish-readback-lost' { 'retry with --resume-draft=' + environment['VINIX_ASSET_TEST_DRAFT_ID'] }
				'publish-still-draft' { 'is still a draft' }
				'publish-changed-asset' { 'GitHub draft asset differs from the verified upload' }
				else { 'points to ${other_commit}, expected ${commit}' }
			}
			if code == 0 || !log.contains(diagnostic) || log.contains('==> Published')
				|| !os.exists(remote + '/publish-attempt') {
				return error('invalid publication reported as successful: ' + scenario + '\n' + log)
			}
			if scenario == 'publish-readback-lost' {
				resume_attempt(root, work, environment, 'resume-confirm-readback', [], '')!
			}
		} else if scenario == 'build-only' {
			if code != 0 || os.exists(out + '/fixture-upload') || !os.exists(out + '/RELEASE_NOTES.md') {
				return error('build-only fixture failed\n' + log)
			}
			expected := ['vinix-amd64.iso', x11, x11 + '.sha256'].map(checksum_line(out + '/' + it)!)
			if expected != os.read_lines(out + '/SHA256SUMS')! {
				return error('build-only checksums differ from the output assets')
			}
		} else {
			diagnostic := match scenario {
				'bad-build-sidecar' { 'release bundle checksum differs from its payload' }
				'manifest-at-handoff' { 'SHA256SUMS changed after verification' }
				'tag-mismatch', 'tag-moved', 'tag-raced', 'tag-moved-during-upload' { 'points to ${other_commit}, expected ${commit}' }
				'tag-read-failed' { 'cannot read GitHub tag: fixture GitHub tag lookup failed' }
				'tag-create-failed' { 'could not verify the created GitHub tag' }
				'draft-tag-rebound' { 'fixture original draft upload URL no longer exists' }
				'draft-wrong-upload-url' { 'GitHub returned an invalid draft upload destination' }
				'tag-removed-during-upload' { 'is missing before publication' }
				'draft-bad-digest', 'draft-incomplete-asset' { 'GitHub draft asset differs from the verified upload' }
				'draft-missing-asset' { 'missing GitHub draft assets' }
				'draft-extra-asset' { 'unexpected GitHub draft asset' }
				'draft-changed' { 'GitHub draft metadata changed after creation' }
				'upload-interrupted' { 'fixture upload interrupted' }
				else { 'release asset changed after verification' }
			}
			if code == 0 || !log.contains(diagnostic) || os.exists(remote + '/publish-attempt')
				|| os.exists(remote + '/release-attempt') != draft_refusal {
				return error('release refusal fixture failed: ' + scenario + '\n' + log)
			}
			if draft_refusal && !json2.decode[FixtureRelease](os.read_file(remote + '/draft.json')!)!.draft {
				return error('release refusal did not retain its draft: ' + scenario)
			}
			if scenario in ['draft-tag-rebound', 'draft-wrong-upload-url']! {
				if os.exists(remote + '/replacement-upload') || os.ls(remote + '/uploads')!.len != 0 {
					return error('refused upload modified another draft: ' + scenario)
				}
			}
			early := scenario in ['tag-mismatch', 'tag-read-failed']!
			if early && os.exists(out) { return error('GitHub tag preflight wrote release output') }
			if os.exists(out + '/fixture-boot') != (!early && scenario != 'bad-build-sidecar') {
				return error('unexpected boot test handoff: ' + scenario)
			}
			if scenario == 'upload-interrupted' { check_resume(root, work, out, remote, environment)! }
		}
		println('ISO release assets ${scenario} PASS')
	}
}

fn main() {
	name := os.file_name(os.args[0])
	if name in ['get-deps', 'human-size', 'gh', 'xorriso', 'test-iso.sh', 'build-desktop-amd64.sh',
		'build-desktop-aarch64.sh', 'build-aarch64.sh', 'build-ios-aarch64.sh', 'build-aarch64-iso.sh']! {
		exit(run_stub(name) or { eprintln(err); 2 })
	}
	run() or { eprintln(err); exit(1) }
}
