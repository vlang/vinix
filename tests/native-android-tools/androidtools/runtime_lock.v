// SPDX-License-Identifier: GPL-2.0-or-later
module androidtools

import androidhost as ah
import cachecli
import crypto.sha256
import hosttest
import os
import sourcecommand

const repositories = ['main', 'community', 'testing']
const root_packages = ['android-translation-layer', 'font-dejavu', 'font-noto', 'ca-certificates-bundle']
const mirror = 'https://dl-cdn.alpinelinux.org/alpine/edge'

fn source_run(argv []string, environment map[string]string) !int {
	return sourcecommand.run_preferred(argv, environment, cachecli.cancelled, '')!.status
}

pub fn calculator_metadata() ah.Value {
	return ah.Value({'filename': ah.Value('Arity-1.1.apk'), 'url': ah.Value('https://storage.googleapis.com/google-code-archive-source/v2/code.google.com/arity-calculator/source-archive.zip'), 'archive_member': ah.Value('arity-calculator/rel/Arity-1.1.apk'), 'archive_sha256': ah.Value('1b39e4f968e7d21602ea166f73a1b36c35213b78e9e3e06b74053cfdc98dfbe2'), 'sha256': ah.Value('1928e65ced8cbe78be2ff3cb4c321e9e75d138e8e30ea1368fbb772a86827d1d'), 'version': ah.Value('1.1'), 'license': ah.Value('Apache-2.0'), 'activity': ah.Value('calculator/Calculator')})
}

pub fn calculator_apk(downloads string) !string {
	metadata := calculator_metadata().object()
	apk := downloads + '/' + field_text(metadata, 'filename')
	if os.exists(apk) {
		if ah.digest(apk)! != field_text(metadata, 'sha256') { return error('calculator APK checksum mismatch: ' + apk) }
		return apk
	}
	archive := downloads + '/arity-calculator-source-archive.zip'
	package_download(field_text(metadata, 'url'), archive, field_text(metadata, 'archive_sha256'))!
	contents := ah.open_archive(archive)!.read(field_text(metadata, 'archive_member'))!
	if sha256.sum(contents).hex() != field_text(metadata, 'sha256') { return error('calculator APK checksum mismatch in official source archive') }
	os.write_file_array(apk, contents)!
	return apk
}

fn fetch_one(record ah.Value, downloads string, package_lock ah.Value) !string {
	filename := field_text(record.object(), 'filename')
	archive := downloads + '/' + filename
	url := field_text(package_lock.object(), 'mirror') + '/' + field_text(record.object(), 'repository') + '/' + field_text(package_lock.object(), 'architecture') + '/' + filename
	package_download(url, archive, field_text(record.object(), 'sha256'))!
	return archive
}

struct FetchResult {
	path string
	failure string
	index int
}

struct FetchJob {
	index int
	record ah.Value
}

fn fetch_worker(jobs chan FetchJob, results chan FetchResult, downloads string, package_lock ah.Value) {
	for {
		job := <-jobs or { break }
		path := fetch_one(job.record, downloads, package_lock) or {
			results <- FetchResult{failure: err.msg(), index: job.index}
			continue
		}
		results <- FetchResult{path: path, index: job.index}
	}
}

fn fetch_packages(package_lock ah.Value, downloads string) ![]string {
	packages := ah.field(package_lock.object(), 'packages').items()
	if packages.len == 0 { return []string{} }
	jobs := chan FetchJob{cap: packages.len}
	results := chan FetchResult{cap: packages.len}
	for index, record in packages { jobs <- FetchJob{index, record} }
	jobs.close()
	mut workers := []thread{}
	for _ in 0 .. if packages.len < 6 { packages.len } else { 6 } { workers << spawn fetch_worker(jobs, results, downloads, package_lock) }
	mut ordered := []FetchResult{len: packages.len}
	for _ in 0 .. packages.len { result := <-results; ordered[result.index] = result }
	workers.wait(); results.close()
	mut paths := []string{}
	// Retire every submitted task before propagating the first ordered error,
	// as the original ThreadPoolExecutor context manager did.
	for result in ordered { if result.failure != '' { return error(result.failure) }; paths << result.path }
	return paths
}

pub fn make_package_lock(downloads string, selected_mirror string) !ah.Value {
	mut indexes := []ah.Value{}
	for repository in repositories {
		archive := downloads + '/' + repository + '_APKINDEX.tar.gz'
		if os.exists(archive) { os.rm(archive)! }
		checksum := package_download(selected_mirror + '/' + repository + '/aarch64/APKINDEX.tar.gz', archive, '')!
		extract_member(archive, 'APKINDEX', downloads + '/' + repository + '_APKINDEX')!
		indexes << ah.Value({'repository': ah.Value(repository), 'sha256': ah.Value(checksum)})
	}
	mut command := [root() + '/build-support/alpine-resolve']
	for repository in repositories { command << ['--index', repository, downloads + '/' + repository + '_APKINDEX'] }
	command << root_packages
	output := probe_command(command, true, '')!
	mut records := []ah.Value{}
	for line in output.split_into_lines() {
		fields := line.split('\t')
		if fields.len != 2 { return error('invalid package resolver record') }
		filename := fields[1]
		if filename.len < 4 { return error('invalid resolved package filename') }
		stem := filename[..filename.len - 4]
		parts := stem.split('-')
		if parts.len < 3 { return error('invalid resolved package filename') }
		records << ah.Value({'repository': ah.Value(fields[0]), 'filename': ah.Value(filename), 'name': ah.Value(parts[..parts.len - 2].join('-')), 'version': ah.Value(parts[parts.len - 2..].join('-'))})
	}
	package_lock := ah.Value({'format': ah.Value(1), 'architecture': ah.Value('aarch64'), 'mirror': ah.Value(selected_mirror), 'root_packages': ah.Value(root_packages.map(ah.Value(it))), 'indexes': ah.Value(indexes), 'packages': ah.Value(records)})
	paths := fetch_packages(package_lock, downloads)!
	mut pinned := []ah.Value{}
	for index, record in records {
		mut copy := record.object().clone()
		copy['sha256'] = ah.digest(paths[index])!
		pinned << ah.Value(copy)
	}
	mut result := package_lock.object().clone(); result['packages'] = ah.Value(pinned)
	return ah.Value(result)
}

pub fn runtime_cli(argv []string) !int {
	args := parse_arguments(argv, ['--build-dir', '--art-runtime', '--bionic-runtime', '--atl-runtime', '--mirror'], []string{}, ['--with-calculator', '--update-lock'], 0, 0, 'usage: Android build [--build-dir DIR --art-runtime DIR --bionic-runtime DIR --atl-runtime DIR --with-calculator --update-lock --mirror URL]')!
	build := hosttest.module_resolve(args.value('--build-dir', os.getenv_opt('VINIX_ANDROID_BUILD_DIR') or { root() + '/build-aarch64-android/aarch64' }))!
	options := RuntimeOptions{build_dir: build, art_runtime: hosttest.module_resolve(args.value('--art-runtime', os.getenv_opt('VINIX_ANDROID_ART_RUNTIME') or { build + '/art-runtime' }))!, bionic_runtime: hosttest.module_resolve(args.value('--bionic-runtime', os.getenv_opt('VINIX_ANDROID_BIONIC_RUNTIME') or { build + '/bionic-runtime' }))!, atl_runtime: hosttest.module_resolve(args.value('--atl-runtime', os.getenv_opt('VINIX_ANDROID_ATL_RUNTIME') or { build + '/atl-runtime' }))!, with_calculator: '--with-calculator' in args.options}
	downloads := build + '/downloads'; posix_parents(downloads)!
	lock_path := root() + '/build-support/android/packages.lock.json'
	package_lock := if '--update-lock' in args.options { make_package_lock(downloads, args.value('--mirror', os.getenv_opt('ALPINE_MIRROR') or { mirror }).trim_right('/'))! } else { read_value(lock_path)! }
	if '--update-lock' in args.options { write_receipt(lock_path, package_lock)! }
	if field_text(package_lock.object(), 'architecture') != 'aarch64' { return error('package lock architecture does not match requested runtime') }
	stage_runtime(options, package_lock, downloads)!
	return 0
}
