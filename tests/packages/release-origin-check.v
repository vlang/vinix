// SPDX-License-Identifier: GPL-2.0-or-later
module main

import json2
import os
import time
import tools.packages.pkgcore
import tools.packages.pkgprotocol

const release_apps = ['org.ffmpeg.cli', 'org.ffmpeg.probe', 'org.neovim.editor', 'org.sqlite.cli',
	'org.vinix.counter', 'org.vinix.memo', 'org.vinix.package-hello']
const updated_runtime = 'org.vinix.sqlite-runtime'

struct Fixture {
	cli      string
	work     string
	baseline string
	update   string
	url      string
}

fn require(condition bool, reason string) ! {
	if !condition { return error(reason) }
}

fn command(log string, args []string, status int, diagnostic string) !string {
	result := os.exec(args)
	os.write_file(log + '.argv.json', json2.encode(args) + '\n')!
	os.write_file(log + '.log', result.output)!
	if result.exit_code != status || !result.output.contains(diagnostic) {
		return error('unexpected status or output for ${log}: ${result.exit_code}\n${result.output}')
	}
	return result.output
}

fn (fixture Fixture) run(arch string, step string, args []string, status int, diagnostic string) !string {
	return command(fixture.work + '/' + arch + '/' + step,
		[fixture.cli, '--root', fixture.work + '/' + arch + '/root', ...args], status, diagnostic)
}

fn (fixture Fixture) repository_review(arch string, step string, enroll []string) !pkgprotocol.RepositoryReview {
	return pkgprotocol.decode_repository_review(fixture.run(arch, step, ['repo-review', ...enroll], 0, '')!)
}

fn setup_image(root string, architecture string, configuration string, bundle string) !pkgcore.Config {
	mut plan := pkgcore.prepare_image_configuration(root, architecture, configuration)!
	defer { plan.close() }
	mut repositories := plan.prepare_repositories(bundle)!
	defer { repositories.close() }
	mut applications := plan.prepare_applications(&repositories, release_apps)!
	defer { applications.close() }
	require(repositories.publish()!, 'fresh image should publish its signed bundle')!
	require(plan.publish()!, 'fresh image should publish its reviewed configuration')!
	require(applications.publish(&repositories)!, 'fresh image should publish its application lock')!
	repositories.retire()!
	return json2.decode[pkgcore.Config](os.read_file(root + '/etc/vinix-packages/config.json')!)
}

fn changed_runtime_objects(previous pkgcore.State, current pkgcore.State) ![]string {
	require(current.requested == previous.requested && current.packages.len == previous.packages.len,
		'the update changed the installed closure')!
	mut previous_by_id := map[string]pkgcore.Installed{}
	mut cached := map[string]bool{}
	for installed in previous.packages {
		previous_by_id[installed.package.id] = installed
		for file in installed.package.files { cached[file.sha256] = true }
	}
	mut needed := map[string]bool{}
	for installed in current.packages {
		old := previous_by_id[installed.package.id] or { return error('unexpected updated package') }
		require(installed.repository == old.repository && installed.public_key == old.public_key,
			'installed publisher identity changed with its origin')!
		if installed.package.id == updated_runtime {
			require(installed.package.version != old.package.version && installed.sequence == 2,
				'upgrade did not activate the signed runtime update')!
			for file in installed.package.files {
				if file.sha256 !in cached { needed[file.sha256] = true }
			}
		} else {
			require(installed.package == old.package, 'unrelated package changed during upgrade')!
		}
	}
	require(needed.len > 0, 'the signed update must require a real download')!
	return needed.keys().sorted()
}

fn (fixture Fixture) qualify(arch string, configuration string) ! {
	work := fixture.work + '/' + arch
	root := work + '/root'
	os.mkdir_all(root)!
	config := setup_image(root, arch, configuration, fixture.baseline)!
	require(config.repositories.len == 1 && !config.policy.offline, 'expected one release publisher with online updates enabled')!
	config_path := root + '/etc/vinix-packages/config.json'
	lock_path := root + pkgprotocol.image_applications_path
	declaration := os.read_file(lock_path)!
	repository := config.repositories[0]
	local_url := 'file://' + root + pkgcore.image_repositories_path + '/' + repository.id
	// An alternate host root does not rebase file URLs. Point only this test
	// configuration at the equivalent staged directory before first refresh.
	local := pkgcore.Repository{ ...repository, url: local_url }
	os.write_file(work + '/image-config.json', os.read_file(config_path)!)!
	os.write_file(config_path, json2.encode(pkgcore.Config{ ...config, repositories: [local] }) + '\n')!
	fixture.run(arch, 'offline-refresh', ['--offline', 'update'], 0, '')!
	initial_review := pkgprotocol.decode_review(fixture.run(arch, 'offline-review', [
		'--offline',
		'deployment-review',
		lock_path,
	], 0, '')!)!
	require(initial_review.requested == release_apps && initial_review.rows.len == 10,
		'the initial offline review did not resolve the complete advertised catalog')!
	fixture.run(arch, 'offline-install', ['--offline', 'deployment-apply', initial_review.fingerprint,
		lock_path], 0, '')!
	baseline := json2.decode[pkgcore.State](fixture.run(arch, 'baseline', ['--json', 'verify'], 0, '')!)!
	require(baseline.generation == 1 && baseline.packages.len == 10 && baseline.requested == release_apps,
		'initial offline deployment differs from the selected catalog')!
	fixture.run(arch, 'baseline-audit', ['--json', 'deployment-audit', lock_path], 0, '')!
	directory := pkgcore.state_directory(root)
	history_path := directory + '/trust-history.json'
	cache_path := directory + '/catalog.json'
	old_history := os.read_file(history_path)!
	old_cache := os.read_file(cache_path)!
	old_config := os.read_file(config_path)!
	// Use the same URL for review/apply. Change only the fixture's content so
	// approval for the old signed index cannot authorize the new one.
	active := fixture.work + '/served/' + arch
	os.cp_all(fixture.baseline + '/' + repository.id, active, false)!
	url := fixture.url + '/' + arch + '/' + arch
	enroll := ['enroll', repository.id, url, repository.public_key]
	first := fixture.repository_review(arch, 'review-baseline-origin', enroll)!
	require(first.sequence == 1 && first.remembered_sequence == 1 && first.previous_url == local_url
		&& first.previous_public_key == repository.public_key && first.url == url, 'review did not disclose the old and new origins')!
	os.mv(active, fixture.work + '/served/' + arch + '-old')!
	os.cp_all(fixture.update + '/' + repository.id, active, false)!
	fixture.run(arch, 'stale-origin-apply', ['repo-apply', first.fingerprint, ...enroll], 1, 'repository review is stale')!
	require(os.read_file(config_path)! == old_config && os.read_file(cache_path)! == old_cache
		&& os.read_file(history_path)! == old_history, 'stale approval changed publisher state')!
	approved := fixture.repository_review(arch, 'review-update-origin', enroll)!
	require(approved.sequence == 2 && approved.remembered_sequence == 1 && approved.index_sha256 != first.index_sha256,
		'fresh review did not identify the publisher update')!
	fixture.run(arch, 'apply-update-origin', ['repo-apply', approved.fingerprint, ...enroll], 0, '')!
	live := pkgcore.Repository{ ...repository, url: url }
	require(json2.decode[pkgcore.Config](os.read_file(config_path)!)! == pkgcore.Config{ ...config, repositories: [live] },
		'origin migration changed other trust or organization policy')!
	require(os.read_file(cache_path)! == old_cache, 'enrollment implicitly refreshed the catalog')!
	after_enroll := json2.decode[pkgcore.State](fixture.run(arch, 'verify-after-enroll', [
		'--json',
		'verify',
	], 0, '')!)!
	require(after_enroll == baseline, 'repository enrollment changed the installed generation')!
	fixture.run(arch, 'update', ['update'], 0, '')!
	upgrade := pkgprotocol.decode_review(fixture.run(arch, 'upgrade-review', ['review', 'upgrade'], 0, '')!)!
	require(upgrade.rows.filter(it.action == 'update').map(it.id) == [updated_runtime], 'review must show only the runtime update')!
	fixture.run(arch, 'upgrade', ['apply', upgrade.fingerprint, 'upgrade'], 0, '')!
	current := json2.decode[pkgcore.State](fixture.run(arch, 'upgraded', ['--json', 'verify'], 0, '')!)!
	needed := changed_runtime_objects(baseline, current)!
	requests := os.read_file(fixture.work + '/requests.log')!.split_into_lines()
	objects := requests.filter(it.starts_with(arch + ' ' + arch + '/objects/'))
	require(objects.map(it.all_after('/objects/').all_before(' ')).sorted() == needed,
		'HTTPS did not supply exactly the new authenticated runtime objects')!
	audit := pkgprotocol.decode_deployment_audit(fixture.run(arch, 'updated-audit',
		['--json', 'deployment-audit', lock_path], 3, '')!)!
	require(audit.generation == current.generation && audit.rows.len == 10
		&& audit.rows.filter(it.status != 'match').map(it.id) == [updated_runtime],
		'deployment audit did not isolate the changed runtime')!
	updated_history := os.read_file(history_path)!
	updated_cache := os.read_file(cache_path)!
	updated_config := os.read_file(config_path)!
	rollback := pkgprotocol.decode_review(fixture.run(arch, 'rollback-review', [
		'review',
		'rollback',
	], 0, '')!)!
	fixture.run(arch, 'rollback', ['apply', rollback.fingerprint, 'rollback'], 0, '')!
	restored := json2.decode[pkgcore.State](fixture.run(arch, 'restored', ['--json', 'verify'], 0, '')!)!
	require(restored.generation > current.generation && restored.packages == baseline.packages
		&& restored.requested == baseline.requested, 'rollback did not restore the exact baseline packages')!
	fixture.run(arch, 'restored-audit', ['--json', 'deployment-audit', lock_path], 0, '')!
	// A local package rollback must not permit an HTTPS index rollback.
	replay := fixture.url + '/replay/' + arch + '-old'
	fixture.run(arch, 'replayed-origin', ['repo-review', 'enroll', repository.id, replay,
		repository.public_key],
		1, 'repository rollback or sequence equivocation refused')!
	status := json2.decode[pkgcore.RepositoryStatus](fixture.run(arch, 'repository-status', [
		'--json',
		'repo-list',
	], 0, '')!)!
	require(status.repositories == [live] && status.history.len == 1 && status.history[0].sequence == 2
		&& status.history[0].index_sha256 == approved.index_sha256, 'the original publisher floor was not retained after rollback')!
	require(os.read_file(history_path)! == updated_history && os.read_file(cache_path)! == updated_cache
		&& os.read_file(config_path)! == updated_config && os.read_file(lock_path)! == declaration,
		'rollback or refused replay changed trust, cache or the release declaration')!
	println('RELEASE ORIGIN ${arch} seven roots, ten packages, HTTPS objects fetched ${needed.len}, exact rollback and replay refusal PASS')
}

fn check() ! {
	if os.args.len != 8 {
		return error('usage: release-origin-check VINIX_PACKAGE HTTPS_FIXTURE BASELINE_BUNDLE UPDATE_BUNDLE CONFIG_ARM CONFIG_X86 NEW_WORK')
	}
	work := os.abs_path(os.args[7])
	os.mkdir(work)!
	os.mkdir(work + '/served')!
	os.write_file(work + '/requests.log', '')!
	certificate := work + '/ca.pem'
	key := work + '/tls-key.pem'
	command(work + '/certificate', ['openssl', 'req', '-new', '-x509', '-newkey', 'rsa:2048', '-nodes',
		'-days', '1', '-subj', '/CN=Vinix release origin fixture', '-addext',
		'subjectAltName=IP:127.0.0.1', '-keyout', key, '-out', certificate], 0, '')!
	os.chmod(key, 0o600)!
	defer { os.rm(key) or {} }
	os.setenv('CURL_CA_BUNDLE', certificate, true)
	os.setenv('NO_PROXY', '127.0.0.1', true)
	os.setenv('no_proxy', '127.0.0.1', true)
	mut server := os.new_process(os.abs_path(os.args[2]))
	server.set_args([certificate, key, work + '/served', work + '/ready', work + '/requests.log'])
	server.set_redirect_stdio_merged()
	server.run()
	defer {
		if server.is_alive() { server.signal_kill() }
		server.wait()
		os.write_file(work + '/server.log', server.stdout_slurp()) or {}
		server.close()
	}
	for _ in 0 .. 500 {
		if os.exists(work + '/ready') { break }
		require(server.is_alive(), 'HTTPS fixture exited before binding')!
		time.sleep(10 * time.millisecond)
	}
	url := os.read_file(work + '/ready')!
	port := url.all_after('https://127.0.0.1:')
	require(url.starts_with('https://127.0.0.1:') && port != '' && port.bytes().all(it >= `0` && it <= `9`),
		'HTTPS fixture must listen on loopback')!
	fixture := Fixture{
		cli:      os.abs_path(os.args[1])
		work:     work
		baseline: os.abs_path(os.args[3])
		update:   os.abs_path(os.args[4])
		url:      url
	}
	fixture.qualify('aarch64', os.abs_path(os.args[5]))!
	fixture.qualify('x86_64', os.abs_path(os.args[6]))!
}

fn main() {
	check() or {
		eprintln(err)
		exit(1)
	}
}
