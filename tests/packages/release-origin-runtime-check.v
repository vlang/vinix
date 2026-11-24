// SPDX-License-Identifier: GPL-2.0-or-later
module main

import hwhost
import json2
import os
import plainiso
import time
import tools.packages.pkgcore

const release_apps = ['org.ffmpeg.cli', 'org.ffmpeg.probe', 'org.neovim.editor', 'org.sqlite.cli',
	'org.vinix.counter', 'org.vinix.memo', 'org.vinix.package-hello']

fn checked(args []string) !string {
	result := os.exec(args)
	if result.exit_code != 0 { return error('${args[0]} failed: ${result.output}') }
	return result.output
}

fn capture(source string, target string, mut pins map[string]string) ! {
	physical := os.real_path(source)
	if !os.is_file(physical) { return error('missing qualification input: ' + source) }
	pins[physical] = pkgcore.hash_file(physical)!
	os.mkdir_all(os.dir(target))!
	os.cp(physical, target)!
	if pkgcore.hash_file(target)! != pins[physical] {
		return error('input changed during capture: ' + source)
	}
}

fn capture_curl(root string, target string, arch string, mut pins map[string]string) ! {
	mut pending := ['usr/bin/curl', 'lib/ld-musl-${arch}.so.1']
	mut copied := map[string]bool{}
	readelf := arch + '-linux-musl-readelf'
	for i := 0; i < pending.len; i++ {
		path := pending[i]
		if path in copied { continue }
		capture(root + '/' + path, target + '/' + path, mut pins)!
		copied[path] = true
		text := checked([readelf, '-d', target + '/' + path])!
		for line in text.split_into_lines().filter(it.contains('(NEEDED)')) {
			name := line.all_after('[').all_before(']')
			if name == '' || name.contains('/') { return error('invalid curl dependency: ' + name) }
			if os.is_file(root + '/lib/' + name) {
				pending << 'lib/' + name
			} else {
				pending << 'usr/lib/' + name
			}
		}
	}
}

fn prepare_image(root string, arch string, source string, bundle string) !pkgcore.Repository {
	mut config := pkgcore.prepare_image_configuration(root, arch, source)!
	defer { config.close() }
	mut repositories := config.prepare_repositories(bundle)!
	defer { repositories.close() }
	mut applications := config.prepare_applications(&repositories, release_apps)!
	defer { applications.close() }
	repositories.publish()!
	config.publish()!
	applications.publish(&repositories)!
	repositories.retire()!
	settings := json2.decode[pkgcore.Config](os.read_file(root + '/etc/vinix-packages/config.json')!)!
	if settings.repositories.len != 1 || settings.policy.offline {
		return error('expected one bundled publisher and online maintenance policy')
	}
	return settings.repositories[0]
}

fn signed_index(root string, repository pkgcore.Repository) !pkgcore.Index {
	return pkgcore.verify_index(repository, os.read_file(root + '/index.json')!,
		os.read_file(root + '/index.sig')!, time.now().unix())
}

fn required_objects(arch string, baseline pkgcore.Index, update pkgcore.Index) ![]string {
	if baseline.sequence != 1 || update.sequence != 2 {
		return error('the fixture requires signed sequences 1 and 2')
	}
	mut cached := map[string]bool{}
	mut needed := map[string]bool{}
	for app in baseline.packages.filter(it.architecture in [arch, 'all']) {
		for file in app.files { cached[file.sha256] = true }
	}
	for app in update.packages.filter(it.architecture in [arch, 'all']) {
		for file in app.files {
			if file.sha256 !in cached { needed[file.sha256] = true }
		}
	}
	if needed.len == 0 { return error('the signed update must require a real download') }
	return needed.keys().sorted()
}

fn start_fixture(host hwhost.Host, root string, work string) !(&os.Process, string) {
	server := work + '/https-fixture'
	hwhost.run_tool([host.v, '-o', server, root + '/tests/packages/https-fixture.v'], map[string]string{},
		work + '/https-build.log', 120)!
	os.write_file(work + '/requests.log', '')!
	mut child := os.new_process(server)
	child.set_args([work + '/ca.pem', work + '/key.pem', work + '/served', work + '/ready',
		work + '/requests.log'])
	child.set_redirect_stdio_merged()
	child.run()
	for _ in 0 .. 500 {
		if os.exists(work + '/ready') {
			endpoint := os.read_file(work + '/ready') or { break }
			if endpoint.starts_with('https://127.0.0.1:') {
				return child, '10.0.2.2:' + endpoint.all_after('https://127.0.0.1:')
			}
			break
		}
		if !child.is_alive() { break }
		time.sleep(10 * time.millisecond)
	}
	stop_fixture(mut child, work)
	return error('loopback HTTPS fixture did not start')
}

fn stop_fixture(mut child os.Process, work string) {
	if child.is_alive() { child.signal_kill() }
	child.wait()
	os.write_file(work + '/server.log', child.stdout_slurp()) or {}
	child.close()
}

fn verify_requests(work string, objects []string, preconfigured bool) ! {
	metadata := ['origin online/index.json -', 'origin online/index.sig -']
	replay := ['origin older/index.json -', 'origin older/index.sig -']
	requests := os.read_file(work + '/requests.log')!.split_into_lines()
	prefix := if preconfigured { metadata } else { [...metadata, ...metadata, ...metadata] }
	suffix := [...replay, ...replay]
	if requests.len != prefix.len + objects.len + suffix.len || requests[..prefix.len] != prefix
		|| requests[requests.len - suffix.len..] != suffix
		|| requests[prefix.len..requests.len - suffix.len].sorted() != objects.map('origin online/objects/' + it + ' -') {
		return error('unexpected HTTPS requests; see ' + work + '/requests.log')
	}
}

fn check() ! {
	preconfigured := os.args.len == 9 && os.args[8] == '--bundled-https'
	if (os.args.len != 8 && !preconfigured) || os.args[1] !in ['aarch64', 'x86_64'] {
		return error('usage: release-origin-runtime-check ARCH KERNEL CURL_ROOT BASELINE_BUNDLE UPDATE_BUNDLE CONFIG NEW_WORK [--bundled-https]')
	}
	arch := os.args[1]
	kernel := os.abs_path(os.args[2])
	work := os.abs_path(os.args[7])
	os.mkdir(work)!
	root := hwhost.find_root(@FILE)!
	host := hwhost.find_host(root, arch, '')!
	os.setenv('VEXE', host.v, true)
	os.setenv('V_MACOS_V3_CALLER_VEXE_PRESENT', '1', true)
	os.setenv('V_MACOS_V3_CALLER_VEXE', host.v, true)
	os.setenv('V_MACOS_V3_CALLER_VCHILD_PRESENT', '0', true)
	os.setenv('V_MACOS_V3_NO_FALLBACK', '1', true)
	os.setenv('V_C_ERROR_BUG_REPORT_DISABLED', '1', true)
	mut pins := map[string]string{}
	for path in [@FILE, kernel, host.v, host.qemu, host.firmware, os.abs_path(os.args[6])] {
		physical := os.real_path(path)
		pins[physical] = pkgcore.hash_file(physical)!
	}
	key := work + '/key.pem'
	defer { os.rm(key) or {} }
	hwhost.run_tool(['openssl', 'req', '-new', '-x509', '-newkey', 'rsa:2048', '-nodes', '-days',
		'1', '-subj', '/CN=Vinix installed release origin', '-addext', 'subjectAltName=IP:10.0.2.2',
		'-keyout', key, '-out', work + '/ca.pem'], map[string]string{}, work + '/certificate.log', 60)!
	os.chmod(key, 0o600)!
	os.mkdir(work + '/served')!
	mut server, endpoint := start_fixture(host, root, work)!
	defer { stop_fixture(mut server, work) }
	mut configuration := os.abs_path(os.args[6])
	if preconfigured {
		settings := json2.decode[pkgcore.Config](os.read_file(configuration)!)!
		if settings.repositories.len != 1 { return error('bundle requires one reviewed publisher') }
		repository := pkgcore.Repository{ ...settings.repositories[0], url: 'https://' + endpoint + '/origin/online' }
		configuration = work + '/https-config.json'
		os.write_file(configuration, json2.encode(pkgcore.Config{ ...settings, repositories: [repository] }) + '\n')!
	}
	boot := work + '/boot'
	target := boot + '/rootfs'
	os.mkdir_all(target)!
	repo := prepare_image(target, arch, configuration, os.abs_path(os.args[4]))!
	installed_bundle := target + pkgcore.image_repositories_path + '/' + repo.id
	baseline := signed_index(installed_bundle, repo)!
	served := work + '/served/online'
	update := os.abs_path(os.args[5]) + '/' + repo.id
	for leaf in ['index.json', 'index.sig']! {
		capture(update + '/' + leaf, served + '/' + leaf, mut pins)!
		capture(installed_bundle + '/' + leaf, work + '/served/older/' + leaf, mut pins)!
	}
	objects := required_objects(arch, baseline, signed_index(served, repo)!)!
	for hash in objects {
		capture(update + '/objects/' + hash, served + '/objects/' + hash, mut pins)!
	}
	capture_curl(os.abs_path(os.args[3]), target, arch, mut pins)!
	guest_source := work + '/guest.v'
	capture(root + '/tests/packages/release-origin-guest/main.v', guest_source, mut pins)!
	guest := hwhost.build_program_with_flags(host, guest_source, work + '/guest-build', 'init', ['.'], ['-prod'])!
	cli := hwhost.build_program_with_flags(host, root + '/tools/packages/main.v', work + '/cli-build',
		'vinix-package', ['.', 'tools/accounts'], ['-prod', '-manualfree', '-enable-globals'])!
	os.cp(cli, target + '/usr/bin/vinix-package')!
	os.chmod(target + '/usr/bin/vinix-package', 0o755)!
	os.chmod(target + '/usr/bin/curl', 0o755)!
	fixture := target + '/usr/share/release-origin'
	os.mkdir_all(fixture)!
	os.cp(work + '/ca.pem', fixture + '/ca.pem')!
	os.write_file(fixture + '/endpoint', endpoint + '\n')!
	if preconfigured { os.write_file(fixture + '/bundled-https', '')! }
	os.write_file(target + '/.vinix-image-id', 'vinix-release-origin-installed-1\n')!
	os.write_file(work + '/inputs.json', json2.encode(pins) + '\n')!
	result := hwhost.run_scenario(if arch == 'x86_64' {
		hwhost.Host{ ...host, root: plainiso.prepare(root, work)! }
	} else {
		host
	},
		hwhost.Scenario{
			name:         'installed release origin'
			arches:       [arch]
			cmdline:      'vinix.disk=auto'
			disks:        [hwhost.Disk{ name: 'system.vjfs', size_mib: 4096 }]
			qemu_aarch64: ['-drive', 'if=none,id=packages,format=raw,file={state}/system.vjfs',
				'-device', 'virtio-blk-device,drive=packages', '-device', 'e1000,netdev=repo',
				'-netdev', 'user,id=repo']
			qemu_x86_64:  ['-drive', 'if=ide,format=raw,file={state}/system.vjfs', '-nic',
				'user,model=e1000']
			reboots:      [hwhost.Reboot{}, hwhost.Reboot{}]
			ending:       .poweroff
			required:     [
				'HWTEST PASS seven release roots installed offline on a clean disk',
				'HWTEST PASS HTTPS origin has the same publisher, updates SQLite and refuses replay after rollback',
				'HWTEST PASS restored release and HTTPS trust survived cold boot',
				...if preconfigured {
					['HWTEST PASS bundled HTTPS publisher retained configuration and refused an offline replay']
				} else {
					[]string{}
				},
			]
			forbidden:    ['HWTEST FAIL', 'Kernel panic', 'running from memory',
				'sysdisk: updating the system on']
		}, hwhost.Run{ kernel: kernel, guest: guest, state: boot, timeout: 1800, memory_mib: 2048, keep: true })
	os.write_file(work + '/result.json', json2.encode(result) + '\n')!
	if !result.passed { return error(result.reason) }
	verify_requests(work, objects, preconfigured)!
	for path, expected in pins {
		if pkgcore.hash_file(path)! != expected {
			return error('qualification input changed: ' + path)
		}
	}
	println('INSTALLED RELEASE ORIGIN ${arch} three cold boots and ${objects.len} authenticated HTTPS objects PASS')
}

fn main() {
	if plainiso.requested() {
		plainiso.build() or {
			eprintln(err)
			exit(1)
		}
		return
	}
	check() or {
		eprintln(err)
		exit(1)
	}
}
