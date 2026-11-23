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
const repo_refusals = ['repo-foreign', 'repo-invalid', 'repo-dotdot']
const creation_refusals = ['create-delayed', 'create-no-draft']
const size_refusals = ['oversize-capture', 'oversize-no-test']
const release_list_refusals = ['release-list-failed', 'release-already-draft', 'release-already-published',
	'release-appears-before-create', 'release-list-fails-before-create']

struct FixtureAsset {
	name string
	state string
	digest string
}

struct FixtureUpload {
	path string
	asset FixtureAsset
}

struct FixtureCreation {
	id u64
	repo string
	tag string
	commit string
	prerelease bool
	notes string
	manifest string
}

struct FixtureVerifiedAsset {
	name   string
	bytes  u64
	sha256 string
}

struct FixturePreparedVerification {
	repo            string
	tag             string
	commit          string
	prerelease      bool
	manifest_sha256 string
	notes_sha256    string
	assets          []FixtureVerifiedAsset
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
	if resumed || uploads.len == 0 { return uploads.map(it.asset) }
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

fn github_release_api(args []string, remote string, path string, scenario string) !int {
	tag := os.getenv('VINIX_ASSET_TEST_TAG')
	commit := os.getenv('VINIX_ASSET_TEST_COMMIT')
	draft_id := os.getenv('VINIX_ASSET_TEST_DRAFT_ID')
	out := os.getenv('VINIX_ASSET_TEST_OUT')
	upload_endpoint := fixture_upload_endpoint(draft_id)
	local := remote + '/draft.json'
	if path == 'releases?per_page=100' {
		if args.len == 6 && args[3..5] == ['--paginate', '--jq']
			&& args[5].contains('expected a release list') {
			println('${tag}-other')
			after_build := os.exists(out + '/fixture-boot')
			if scenario == 'release-list-failed' || (after_build && scenario == 'release-list-fails-before-create') {
				eprintln('fixture GitHub release list failed after a partial page')
				return 1
			}
			reserved := remote + '/reserved-release.json'
			if os.exists(reserved) {
				existing := json2.decode[FixtureRelease](os.read_file(reserved)!)!
				println(existing.tag_name)
			}
			if after_build && scenario == 'release-appears-before-create' { println(tag) }
			return 0
		}
		if args[3..] != ['--paginate', '--jq', '.[] | select(.draft == true) | [.id, .tag_name] | @tsv'] {
			return error('expected paginated draft lookup')
		}
		println('99900\t${tag}-other')
		if os.exists(local) && scenario !in ['create-delayed', 'publish-prepared-delayed']! {
			println('${draft_id}\t${tag}')
			if scenario == 'resume-create-ambiguous' { println('99901\t${tag}') }
		}
		return 0
	}
	if path == 'releases' {
		if os.exists(remote + '/release-attempt') { return error('fixture second creation request') }
		os.write_file(remote + '/release-attempt', args[1..].join('\n') + '\n')!
		legacy := args.len == 19 && args[17..] == ['--jq', '.id']
		if (!legacy && args.len != 17) || !args[12].starts_with('body=@') {
			return error('expected releases POST with notes')
		}
		body := args[12]
		prerelease := scenario in ['draft-only', 'publish-prepared', 'publish-prepared-delayed']!
		if args[3..17] != ['--method', 'POST', '-f', 'tag_name=' + tag, '-f',
			'target_commitish=' + commit, '-f', 'name=Vinix ' + tag, '-F', body, '-F',
			'draft=true', '-F', 'prerelease=' + prerelease.str()]
			|| os.read_file(tag_file(remote, tag))! != commit {
			return error('draft created before checking the exact remote tag commit')
		}
		notes := os.read_file(body[6..])!
		manifest := os.read_file(out + '/SHA256SUMS')!
		intent_path := out + '/.draft-creation.json'
		intent := json2.decode[FixtureCreation](os.read_file(intent_path)!)!
		if intent.id != 0 || intent.repo != 'local/fixture' || intent.tag != tag || intent.commit != commit
			|| intent.prerelease != prerelease || intent.notes != notes || intent.manifest != manifest
			|| !notes.contains('<!-- Vinix release attempt: ')
			|| !notes.ends_with(' ${sha256.hexhash(manifest)} -->\n') {
			return error('creation request did not use saved release metadata')
		}
		os.cp(intent_path, remote + '/creation-record')!
		if scenario == 'create-no-draft' {
			eprintln('fixture refused creation before saving the draft')
			return 1
		}
		draft := FixtureRelease{
			id: draft_id.u64()
			tag_name: tag
			name: 'Vinix ' + tag
			body: notes
			prerelease: prerelease
			upload_url: if scenario == 'draft-wrong-upload-url' {
				fixture_upload_endpoint((draft_id.u64() + 1).str()) + '{?name,label}'
			} else { upload_endpoint + '{?name,label}' }
		}
		os.mkdir(remote + '/uploads')!
		os.write_file(local, json2.encode(draft))!
		if scenario in ['create-response-lost', 'create-delayed', 'publish-prepared-delayed']! {
			eprintln('fixture lost the creation response')
			return 1
		}
		println(if legacy { draft_id } else { json2.encode(draft) })
		return 0
	}
	if path != 'releases/' + draft_id { return error('unexpected draft release ID') }
	mut draft := json2.decode[FixtureRelease](os.read_file(local)!)!
	if args.len == 3 {
		if scenario == 'resume-publish' {
			work := os.getenv('VINIX_ASSET_TEST_ROOT') + '/build-release/work'
			if os.ls(work)!.any(it.starts_with('release-assets.') && os.is_dir(work + '/' + it + '/upload')) {
				return error('complete draft recovery created an upload staging directory')
			}
		}
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
		if scenario == 'resume-create-unrelated' {
			println(json2.encode(FixtureRelease{...draft, body: 'unrelated draft notes'}))
			return 0
		}
		os.write_file(local, json2.encode(draft))!
		println(json2.encode(draft))
		return 0
	}
	if !draft.draft || os.exists(remote + '/publish-attempt') {
		return error('unexpected draft publish request')
	}
	os.write_file(remote + '/publish-attempt', args[1..].join('\n') + '\n')!
	legacy := args[3..] == ['--method', 'PATCH', '-F', 'draft=false', '--jq',
		'select(.draft == false) | .html_url']
	if !legacy && args[3..] != ['--method', 'PATCH', '-F', 'draft=false', '--silent'] {
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

fn upload_fixture(args []string, out string, remote string, scenario string) !int {
	tag := os.getenv('VINIX_ASSET_TEST_TAG')
	if args.len != 12 { return error('unexpected draft upload request') }
	file := args[10]
	name := os.file_name(file)
	upload_endpoint := fixture_upload_endpoint(os.getenv('VINIX_ASSET_TEST_DRAFT_ID'))
	if args[2..] != [upload_endpoint, '--method', 'POST', '-H', 'Content-Type: application/octet-stream',
		'-f', 'name=' + name, '--input', file, '--silent'] {
		return error('unexpected draft upload request')
	}
	if scenario == 'draft-tag-rebound' {
		eprintln('fixture original draft upload URL no longer exists')
		return 1
	}
	draft := json2.decode[FixtureRelease](os.read_file(remote + '/draft.json')!)!
	if !draft.draft || draft.tag_name != tag { return error('upload does not target the draft') }
	if scenario == 'resume-complete-draft' && name == 'vinix-amd64.iso' {
		stage := os.dir(file)
		mut names := os.ls(stage)!
		names.sort()
		for asset in draft.assets {
			if asset.name in names {
				return error('resume copied an already uploaded asset: ' + asset.name)
			}
		}
		os.write_file(remote + '/resume-stage', names.join('\n') + '\n')!
	}
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

fn github_api(args []string, scenario string) !int {
	remote := os.getenv('VINIX_ASSET_TEST_REMOTE')
	commit := os.getenv('VINIX_ASSET_TEST_COMMIT')
	path := args[2]
	prefix := 'repos/local/fixture/'
	if path.starts_with('https://') {
		return upload_fixture(args, os.getenv('VINIX_ASSET_TEST_OUT'), remote, scenario)
	}
	if path.starts_with(prefix + 'releases') {
		return github_release_api(args, remote, path[prefix.len..], scenario)
	}
	if path == prefix + 'commits/' + commit && '--silent' in args {
		review := os.getenv('VINIX_ASSET_TEST_REVIEW')
		if scenario == 'publish-prepared' && review != '' {
			os.write_file(review, 'review changed after the driver captured it\n')!
		}
		return 0
	}
	if path.starts_with(prefix + 'git/matching-refs/tags/') && args[3..] == ['--jq', '.[].ref'] {
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
	if path.starts_with(prefix + 'commits/refs/tags/') && args[3..] == ['--jq', '.sha'] {
		tag := urllib.query_unescape(path.all_after('/commits/refs/tags/'))!
		println(os.read_file(tag_file(remote, tag))!)
		return 0
	}
	tag := os.getenv('VINIX_ASSET_TEST_TAG')
	if path != prefix + 'git/refs' || args[3..] != ['--method', 'POST', '-f',
		'ref=refs/tags/' + tag, '-f', 'sha=' + commit, '--silent'] {
		return error('unexpected fixture GitHub API invocation: ' + args[1..].join(' '))
	}
	file := tag_file(remote, tag)
	if os.exists(file) { return error('fixture attempted to create an existing tag') }
	os.write_file(remote + '/create-tag', args[2..].join('\n') + '\n')!
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
			bundle := os.getenv('VINIX_AMD64_X11_BUNDLE')
			fixture_bundle(bundle)!
			if scenario in size_refusals { os.truncate(bundle, u64(2147483648))! }
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
			if scenario in ['prepared', 'prepared-recovery']! || scenario.starts_with('verify-prepared') {
				remote := os.getenv('VINIX_ASSET_TEST_REMOTE')
				os.write_file(remote + '/unexpected-gh', os.args[1..].join('\n'))!
				return error('local prepared release operation invoked GitHub')
			}
			if os.args[1] == 'auth' {
				if os.args[2..] != ['status', '--hostname=github.com'] {
					return error('GitHub auth check did not select GitHub.com')
				}
				return 0
			}
			if os.args[1] == 'api' {
				if os.args[2] != '--hostname=github.com' {
					return error('GitHub API request did not select GitHub.com')
				}
				return github_api([os.args[0], os.args[1], ...os.args[3..]], scenario)
			}
			if os.args[1..] == ['repo', 'view', '--json', 'url', '--jq', '.url'] {
				repo_url := if scenario == 'repo-foreign' {
					'https://enterprise.invalid/local/fixture'
				} else { 'https://github.com/local/fixture' }
				remote := os.getenv('VINIX_ASSET_TEST_REMOTE')
				os.write_file(remote + '/repo-discovery', repo_url + '\n')!
				println(repo_url)
				return 0
			}
			upload := out + '/fixture-upload'
			if os.args[1..3] == ['release', 'view'] {
				if os.args[3..6] != ['--repo', 'github.com/local/fixture', '--'] {
					return error('release lookup did not select GitHub.com')
				}
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

fn verify_handoff(out string, with_packages bool, scenario string, published_notes string) ! {
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
		'${sha256.hexhash(published_notes)}  RELEASE_NOTES.md']
	if scenario != 'publish-prepared' && notes != published_notes {
		return error('release output notes differ from the published notes')
	}
	mut uploaded := os.read_lines(out + '/fixture-upload-digests')!
	listed.sort()
	uploaded.sort()
	if uploaded != listed { return error('release handoff bytes differ from the verified assets') }
	upload_images := os.read_lines(out + '/fixture-upload')!.filter(it.starts_with('/') && it.ends_with('.iso'))
	if with_packages && scenario != 'publish-prepared'
		&& os.read_lines(out + '/fixture-receipt-isos')! != upload_images {
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
	if scenario != 'publish-prepared' && os.read_lines(out + '/fixture-boot')! != upload_images {
		return error('boot test and uploader used different ISO copies')
	}
}

fn recovery_attempt(root string, work string, environment map[string]string, scenario string, options []string, expected_error string) ! {
	mut env := environment.clone()
	env['VINIX_ASSET_TEST_CASE'] = scenario
	mut args := [root + '/scripts/deploy-iso.sh', '--yes']
	args << options
	code, log := command('/bin/bash', args, root, env)
	os.write_file(work + '/' + scenario + '.log', log)!
	if (code == 0) != (expected_error == '') || !log.contains(expected_error)
		|| log.contains('Building the amd64 image') || log.contains('Boot-testing the images') {
		return error('unexpected recovery outcome for ${scenario}\n${log}')
	}
	println('ISO release assets ${scenario} PASS')
}

fn resume_attempt(root string, work string, environment map[string]string, scenario string, options []string, expected_error string) ! {
	args := ['--resume-draft=' + environment['VINIX_ASSET_TEST_DRAFT_ID'], ...options]
	recovery_attempt(root, work, environment, scenario, args, expected_error)!
}

fn check_creation_recovery(root string, work string, out string, remote string, environment map[string]string, scenario string) ! {
	id := environment['VINIX_ASSET_TEST_DRAFT_ID']
	tag := environment['VINIX_ASSET_TEST_TAG']
	intent_path := out + '/.draft-creation.json'
	recovery_path := root + '/build-release/work/draft-' + id + '.json'
	intent := os.read_file(intent_path)!
	attempt := os.read_file(remote + '/release-attempt')!
	if intent != os.read_file(remote + '/creation-record')! || os.exists(recovery_path)
		|| os.exists(remote + '/publish-attempt') {
		return error('interrupted creation did not retain exactly one creation record')
	}
	options := ['--resume-create=' + tag]
	if scenario == 'create-no-draft' {
		recovery_attempt(root, work, environment, 'resume-create-missing', options, 'no GitHub draft found')!
		if os.exists(remote + '/draft.json') || os.exists(recovery_path) || os.read_file(intent_path)! != intent {
			return error('recovery changed state for a missing draft')
		}
		return
	}
	recovery_attempt(root, work, environment, 'resume-create-protect-output', ['--tag=' + tag,
		'--repo=local/fixture'], 'draft creation record already exists')!
	recovery_attempt(root, work, environment, 'resume-create-ambiguous', options, 'multiple GitHub drafts use')!
	recovery_attempt(root, work, environment, 'resume-create-unrelated', options, 'GitHub draft metadata changed after creation')!
	iso := out + '/vinix-amd64.iso'
	original := os.read_file(iso)!
	os.write_file(iso, 'changed release ISO')!
	recovery_attempt(root, work, environment, 'resume-create-stale-local', options, 'release asset changed after verification') or {
		os.write_file(iso, original)!
		return err
	}
	os.write_file(iso, original)!
	if os.ls(remote + '/uploads')!.len != 0 || os.exists(recovery_path)
		|| os.read_file(intent_path)! != intent || os.exists(remote + '/publish-attempt') {
		return error('refused recovery changed the interrupted creation')
	}
	recovery_attempt(root, work, environment, 'resume-create-complete', [...options, '--draft'], '')!
	finished := json2.decode[FixtureRelease](os.read_file(remote + '/draft.json')!)!
	recovery := json2.decode[FixtureCreation](os.read_file(recovery_path)!)!
	if !finished.draft || finished.assets.len != os.read_lines(out + '/SHA256SUMS')!.len + 1
		|| os.exists(intent_path) || recovery.id.str() != id || recovery.notes != finished.body
		|| os.exists(remote + '/publish-attempt') || os.read_file(remote + '/release-attempt')! != attempt {
		return error('recovery did not complete the original draft')
	}
}

fn check_resume(root string, work string, out string, remote string, environment map[string]string) ! {
	id := environment['VINIX_ASSET_TEST_DRAFT_ID']
	record := root + '/build-release/work/draft-' + id + '.json'
	recovery := os.read_file(record)!
	created := os.read_file(remote + '/release-attempt')!
	mut before := os.ls(remote + '/uploads')!
	before.sort()
	uploaded := before.filter(it != 'SHA256SUMS')
	if uploaded.len == 0 { return error('interrupted draft has no retained payload') }
	for scenario, name in {'resume-stale-local': 'vinix-amd64.iso', 'resume-stale-uploaded': uploaded[0]} {
		file := out + '/' + name
		original := os.read_file(file)!
		os.write_file(file, 'changed release asset')!
		resume_attempt(root, work, environment, scenario, [], 'release asset changed after verification') or {
			os.write_file(file, original)!
			return err
		}
		os.write_file(file, original)!
	}
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
	if !finished.draft || finished.assets.len != expected || os.exists(remote + '/publish-attempt')
		|| !os.exists(remote + '/resume-stage') {
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

fn check_prepared_release(root string, work string, out string, remote string, environment map[string]string) ! {
	tag := environment['VINIX_ASSET_TEST_TAG']
	commit := environment['VINIX_ASSET_TEST_COMMIT']
	record_path := out + '/.prepared-release.json'
	record := os.read_file(record_path)!
	prepared := json2.decode[FixtureCreation](record)!
	if prepared.id != 0 || prepared.repo != 'local/fixture' || prepared.tag != tag
		|| prepared.commit != commit || !prepared.prerelease || os.ls(remote)!.len != 0
		|| prepared.notes != os.read_file(out + '/RELEASE_NOTES.md')!
		|| prepared.manifest != os.read_file(out + '/SHA256SUMS')!
		|| !prepared.notes.contains('### Tested before release') {
		return error('prepared release lost its verified metadata or contacted GitHub')
	}
	verification_args := ['--verify-prepared=' + tag]
	recovery_attempt(root, work, environment, 'verify-prepared', verification_args, '')!
	report := json2.decode[FixturePreparedVerification](os.read_file(work + '/verify-prepared.log')!)!
	if report.repo != prepared.repo || report.tag != tag || report.commit != commit
		|| report.prerelease != prepared.prerelease
		|| report.manifest_sha256 != sha256.hexhash(prepared.manifest)
		|| report.notes_sha256 != sha256.hexhash(prepared.notes) {
		return error('prepared verification report changed the recorded metadata')
	}
	mut checksums := map[string]string{}
	for line in prepared.manifest.split_into_lines() {
		checksums[line.all_after('  ')] = line.all_before('  ')
	}
	mut names := checksums.keys()
	names.sort()
	if report.assets.map(it.name) != names {
		return error('prepared verification did not report the exact asset set')
	}
	for asset in report.assets {
		if asset.sha256 != checksums[asset.name] || asset.bytes != os.file_size(out + '/' + asset.name) {
			return error('prepared verification changed an asset digest or size: ' + asset.name)
		}
	}
	recovery_attempt(root, work, environment, 'verify-prepared-repo',
		[...verification_args, '--repo=local/other'], 'belongs to local/fixture')!
	recovery_attempt(root, work, environment, 'prepared-rebuild', ['--tag=' + tag, '--prepare-only',
		'--repo=local/fixture'], 'prepared release record already exists')!
	mut wrong_tag := environment.clone()
	wrong_tag['VINIX_RELEASE'] = 'fixture-development'
	recovery_attempt(root, work, wrong_tag, 'prepared-embedded-tag', ['--tag=' + tag + '-other',
		'--prepare-only', '--repo=local/fixture'], 'prepared builds require VINIX_RELEASE to match the release tag')!
	args := ['--publish-prepared=' + tag]
	recovery_attempt(root, work, environment, 'prepared-wrong-repo', [...args, '--repo=local/other'],
		'belongs to local/fixture')!
	review_file := work + '/reviewed release.json'
	review_text := os.read_file(work + '/verify-prepared.log')!
	review_args := [...args, '--prepared-review=../reviewed release.json']
	os.write_file(review_file, json2.encode(FixturePreparedVerification{...report, commit: other_commit}) + '\n')!
	recovery_attempt(root, work, environment, 'prepared-review-wrong-commit', review_args,
		'prepared release differs from the reviewed verification report')!
	os.write_file(review_file, review_text)!
	recovery_attempt(root, work, environment, 'prepared-review-requires-publish',
		[...verification_args, '--prepared-review=../reviewed release.json'],
		'--prepared-review requires --publish-prepared')!

	iso := out + '/vinix-amd64.iso'
	original_iso := os.read_file(iso)!
	replacement := 'different prepared ISO'
	replacement_manifest := prepared.manifest.replace(sha256.hexhash(original_iso) + '  vinix-amd64.iso',
		sha256.hexhash(replacement) + '  vinix-amd64.iso')
	os.write_file(iso, replacement)!
	os.write_file(out + '/SHA256SUMS', replacement_manifest)!
	os.write_file(record_path, json2.encode(FixtureCreation{...prepared, manifest: replacement_manifest}) + '\n')!
	recovery_attempt(root, work, environment, 'prepared-review-replacement', review_args,
		'prepared release differs from the reviewed verification report')!
	os.write_file(iso, original_iso)!
	os.write_file(out + '/SHA256SUMS', prepared.manifest)!
	os.write_file(record_path, record)!

	for note, name in {'prepared-checksums-changed': 'SHA256SUMS',
		'prepared-notes-changed': 'RELEASE_NOTES.md', 'prepared-asset-changed': 'vinix-amd64.iso'} {
		file := out + '/' + name
		contents := os.read_file(file)!
		os.write_file(file, 'changed prepared output')!
		diagnostic := match name {
			'SHA256SUMS' { 'prepared SHA256SUMS changed' }
			'RELEASE_NOTES.md' { 'prepared release notes changed' }
			else { 'release asset changed after verification' }
		}
		recovery_attempt(root, work, environment, note, args, diagnostic) or {
			os.write_file(file, contents)!
			return err
		}
		recovery_attempt(root, work, environment, 'verify-' + note, verification_args, diagnostic) or {
			os.write_file(file, contents)!
			return err
		}
		os.write_file(file, contents)!
	}
	if os.ls(remote)!.len != 0
		|| os.exists(out + '/.draft-creation.json') || os.read_file(record_path)! != record {
		return error('refused publication changed the prepared release')
	}
	git(root, ['-c', 'user.name=Fixture', '-c', 'user.email=fixture@example.invalid',
		'-c', 'commit.gpgsign=false', '-c', 'core.hooksPath=/dev/null',
		'commit', '--allow-empty', '-qm', 'Advance HEAD after preparing the release'])!
	mut publishing := environment.clone()
	publishing['VINIX_ASSET_TEST_REVIEW'] = review_file
	recovery_attempt(root, work, publishing, 'publish-prepared', review_args, '')!
	published := json2.decode[FixtureRelease](os.read_file(remote + '/draft.json')!)!
	verify_handoff(out, true, 'publish-prepared', published.body)!
	recovery_attempt(root, work, environment, 'verify-prepared-published', verification_args, '')!
	if !published.prerelease || published.draft || !published.body.starts_with(prepared.notes)
		|| os.read_file(tag_file(remote, tag))! != commit || os.read_file(record_path)! != record
		|| os.read_file(out + '/fixture-original-notes')! != prepared.notes
		|| os.read_file(work + '/verify-prepared-published.log')! != review_text
		|| !os.exists(remote + '/publish-attempt')
		|| os.read_file(review_file)! != 'review changed after the driver captured it\n' {
		return error('publication did not use the prepared release metadata')
	}
}

fn check_prepared_recovery(root string, work string, out string, remote string, environment map[string]string) ! {
	tag := environment['VINIX_ASSET_TEST_TAG']
	id := environment['VINIX_ASSET_TEST_DRAFT_ID']
	verify := ['--verify-prepared=' + tag]
	recovery_attempt(root, work, environment, 'verify-prepared-before-recovery', verify, '')!
	review := work + '/verify-prepared-before-recovery.log'
	expected := os.read_file(review)!
	record_path := out + '/.prepared-release.json'
	record := os.read_file(record_path)!
	prepared := json2.decode[FixtureCreation](record)!
	intent_path := out + '/.draft-creation.json'
	recovery_path := root + '/build-release/work/draft-' + id + '.json'
	recovery_attempt(root, work, environment, 'publish-prepared-delayed', ['--publish-prepared=' + tag,
		'--prepared-review=' + review], 'no GitHub draft found')!
	intent := os.read_file(intent_path)!
	creation := json2.decode[FixtureCreation](intent)!
	if intent != os.read_file(remote + '/creation-record')! || os.exists(recovery_path)
		|| !creation.notes.starts_with(prepared.notes + '\n<!-- Vinix release attempt: ')
		|| os.ls(remote + '/uploads')!.len != 0 {
		return error('interrupted prepared publication lost its draft creation metadata')
	}
	attempt := os.read_file(remote + '/release-attempt')!
	recovery_attempt(root, work, environment, 'verify-prepared-interrupted', verify, '')!
	recovery_attempt(root, work, environment, 'resume-create-prepared', ['--resume-create=' + tag,
		'--draft'], '')!
	draft := json2.decode[FixtureRelease](os.read_file(remote + '/draft.json')!)!
	recovery := json2.decode[FixtureCreation](os.read_file(recovery_path)!)!
	if os.exists(intent_path) || !draft.draft || draft.id.str() != id || recovery.id != draft.id
		|| draft.body != creation.notes || recovery.notes != creation.notes
		|| draft.assets.len != os.read_lines(out + '/SHA256SUMS')!.len + 1
		|| os.exists(remote + '/publish-attempt') {
		return error('creation recovery did not retain the original prepared draft')
	}
	recovery_attempt(root, work, environment, 'verify-prepared-recovered-draft', verify, '')!
	resume_attempt(root, work, environment, 'resume-draft-prepared', [], '')!
	recovery_attempt(root, work, environment, 'verify-prepared-recovered-publication', verify, '')!
	published := json2.decode[FixtureRelease](os.read_file(remote + '/draft.json')!)!
	if published.draft || published.id != draft.id || published.body != creation.notes
		|| os.read_file(remote + '/release-attempt')! != attempt || !os.exists(remote + '/publish-attempt')
		|| os.read_file(record_path)! != record || os.read_file(out + '/RELEASE_NOTES.md')! != prepared.notes {
		return error('prepared recovery changed the original handoff or created another draft')
	}
	for phase in ['interrupted', 'recovered-draft', 'recovered-publication']! {
		if os.read_file(work + '/verify-prepared-' + phase + '.log')! != expected {
			return error('prepared verification changed after ' + phase)
		}
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
			|| symbol.starts_with('BASH_FUNC_') || symbol in ['BASH_ENV', 'VINIX_RELEASE']! {
			base.delete(symbol)
		}
	}
	base['PATH'] = root + '/fake-bin:' + os.getenv('PATH')
	base['GH_HOST'] = 'enterprise.invalid'
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
	mut scenarios := repo_refusals.clone()
	scenarios << release_list_refusals
	scenarios << size_refusals
	scenarios << creation_refusals
	scenarios << 'create-response-lost'
	scenarios << draft_refusals
	scenarios << publish_refusals
	scenarios << ['publish-response-lost', 'repo-inferred']
	scenarios << ['draft-only', 'tag-mismatch', 'tag-existing', 'tag-auto', 'tag-moved', 'tag-raced',
		'tag-raced-match', 'tag-create-failed', 'tag-read-failed', 'workspace-lock',
		'public-iso-during-receipt', 'public-iso-during-boot', 'legacy', 'packages', 'output-change-during-upload',
		'bad-build-sidecar', 'boot-copy-changed', 'x11-after-boot', 'ios-pair-after-boot',
		'receipt-after-boot', 'sidecar-at-handoff', 'manifest-at-handoff', 'build-only',
		'publish-no-test', 'packages-no-test', 'prepared', 'prepared-recovery']
	for index, scenario in scenarios {
		with_packages := scenario in ['packages', 'receipt-after-boot', 'output-change-during-upload',
			'public-iso-during-boot', 'public-iso-during-receipt', 'packages-no-test', 'prepared']!
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
			'create-delayed' { 'release/fixture-create-delayed' }
			'prepared' { 'release/fixture+prepared' }
			'tag-auto' { default_tag + '-3' }
			else { 'fixture-' + scenario }
		}
		remote := work + '/remote-' + scenario
		os.mkdir(remote)!
		match scenario {
			'tag-auto' {
				os.write_file(tag_file(remote, default_tag), other_commit)!
				environment['VINIX_ASSET_TEST_RESERVED_RELEASE'] = default_tag + '-2'
				os.write_file(remote + '/reserved-release.json',
					json2.encode(FixtureRelease{id: 1, tag_name: default_tag + '-2'}))!
			}
			'release-already-draft', 'release-already-published' {
				os.write_file(remote + '/reserved-release.json', json2.encode(FixtureRelease{
					id: 1
					tag_name: tag
					draft: scenario == 'release-already-draft'
				}))!
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
		mut args := [root + '/scripts/deploy-iso.sh', '--yes']
		match scenario {
			'repo-foreign', 'repo-inferred' {}
			'repo-invalid' { args << '--repo=enterprise.invalid/local/fixture' }
			'repo-dotdot' { args << '--repo=local/..' }
			else { args << '--repo=local/fixture' }
		}
		if scenario != 'tag-auto' { args << '--tag=' + tag }
		if scenario == 'draft-only' { args << ['--draft', '--prerelease'] }
		if scenario in ['prepared', 'prepared-recovery']! {
			args << ['--prepare-only', '--prerelease', '--ref=' + commit]
		}
		if scenario == 'build-only' { args << ['--arch=amd64', '--no-publish'] }
		if scenario in ['publish-no-test', 'packages-no-test', 'oversize-no-test']! { args << ['--no-test'] }
		code, log := command('/bin/bash', args, root, environment)
		os.write_file(work + '/' + scenario + '.log', log)!
		if os.ls(root + '/build-release/work')!.any(it.starts_with('release-assets.')) {
			return error('release left a private staging directory: ' + scenario)
		}
		draft_refusal := scenario in draft_refusals
		expect_create := draft_refusal || scenario in publish_refusals || scenario in creation_refusals
			|| scenario in ['create-response-lost', 'publish-response-lost', 'repo-inferred', 'draft-only', 'tag-auto', 'tag-raced', 'tag-raced-match', 'tag-create-failed',
			'workspace-lock', 'legacy', 'packages', 'output-change-during-upload', 'public-iso-during-boot',
			'public-iso-during-receipt', 'publish-no-test', 'packages-no-test']!
		if os.exists(remote + '/create-tag') != expect_create {
			return error('unexpected GitHub tag creation for ' + scenario + '\n' + log)
		}
		if scenario in ['workspace-lock', 'legacy', 'packages', 'output-change-during-upload', 'public-iso-during-boot',
			'public-iso-during-receipt', 'publish-no-test', 'packages-no-test', 'tag-existing', 'tag-auto',
			'tag-raced-match', 'draft-only', 'publish-response-lost', 'create-response-lost', 'repo-inferred']! {
			if code != 0 { return error('release fixture failed: ' + scenario + '\n' + log) }
			draft := json2.decode[FixtureRelease](os.read_file(remote + '/draft.json')!)!
			verify_handoff(out, with_packages, scenario, draft.body)!
			if draft.draft != (scenario == 'draft-only')
				|| os.exists(remote + '/publish-attempt') != (scenario != 'draft-only')
				|| os.exists(out + '/.draft-creation.json') {
				return error('unexpected final draft state: ' + scenario)
			}
			if scenario == 'workspace-lock' {
				retry_code, retry_log := workspace_contender(root, 'build', base)
				os.write_file(work + '/workspace-lock-retry.log', retry_log)!
				if retry_code != 0 || !os.is_file(root + '/build-release/fixture-lock-build/SHA256SUMS') {
					return error('release workspace retry failed\n' + retry_log)
				}
			}
		} else if scenario == 'prepared' {
			if code != 0 || !log.contains('Saved prepared release ' + tag) {
				return error('could not prepare a release\n' + log)
			}
			check_prepared_release(root, work, out, remote, environment)!
		} else if scenario == 'prepared-recovery' {
			if code != 0 || !log.contains('Saved prepared release ' + tag) {
				return error('could not prepare a release for recovery\n' + log)
			}
			check_prepared_recovery(root, work, out, remote, environment)!
		} else if scenario in release_list_refusals {
			after_build := scenario in ['release-appears-before-create', 'release-list-fails-before-create']!
			diagnostic := if scenario in ['release-list-failed', 'release-list-fails-before-create']! {
				'cannot list GitHub releases on local/fixture'
			} else { 'release ${tag} already exists on local/fixture' }
			if code == 0 || !log.contains(diagnostic) || os.exists(out) != after_build
				|| os.exists(out + '/fixture-boot') != after_build || os.exists(out + '/.draft-creation.json')
				|| os.exists(remote + '/release-attempt') || os.exists(remote + '/publish-attempt') {
				return error('unexpected release lookup outcome: ' + scenario + '\n' + log)
			}
		} else if scenario in size_refusals {
			bundle := out + '/' + x11
			length := os.file_size(bundle)
			// Keep the test evidence small even though the checked file is sparse.
			os.write_file(bundle, 'fixture bundle\n')!
			if code == 0 || length != u64(2147483648)
				|| !log.contains('GitHub release asset ${x11} is 2147483648 bytes')
				|| log.contains('Recording checksums for release assets') || os.exists(out + '/fixture-boot')
				|| os.ls(remote)!.len != 0 {
				return error('oversized release bundle reached verification or publication\n' + log)
			}
		} else if scenario in creation_refusals {
			if code == 0 || !log.contains('no GitHub draft found') {
				return error('unexpected creation recovery outcome: ' + scenario + '\n' + log)
			}
			check_creation_recovery(root, work, out, remote, environment, scenario)!
		} else if scenario in repo_refusals {
			diagnostic := if scenario == 'repo-foreign' {
				"the checkout's repository is on a different host"
			} else { 'expected a GitHub.com repository in OWNER/NAME form' }
			expected_files := if scenario == 'repo-foreign' { ['repo-discovery'] } else { []string{} }
			if code == 0 || !log.contains(diagnostic) || os.exists(out) || os.ls(remote)! != expected_files {
				return error('release preflight accepted an invalid repository: ' + scenario + '\n' + log)
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
			recovery_attempt(root, work, environment, 'prepared-record-required', ['--publish-prepared=' + tag],
				'cannot read release draft recovery record')!
			recovery_attempt(root, work, environment, 'verify-prepared-record-required', ['--verify-prepared=' + tag],
				'cannot read release draft recovery record')!
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
