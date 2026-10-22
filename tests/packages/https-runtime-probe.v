// SPDX-License-Identifier: GPL-2.0-or-later
module main

import os
import json2
import tlsruntime
import tools.packages.pkgcore
import tools.packages.pkgprotocol

$if track_heap ? {
	#include "@VMODROOT/../../desktop/tools/tests/heap_tracker.h"
}

fn C.vinix_heap_begin()
fn C.vinix_heap_end() u64

fn event(progress pkgprotocol.Progress) { progress.validate() or { panic(err) } }

fn reaped() {
	mut status := i32(0)
	assert C.vinix_package_waitpid(-1, unsafe { &status }, C.WNOHANG) == -1 && C.errno == C.ECHILD
}

fn check(f tlsruntime.Fixture, mode string) ! {
	assert mode in tlsruntime.modes()
	os.mkdir_all(f.work)!
	defer { os.rmdir_all(f.work) or { panic(err) } }
	for name in ['HTTPS_PROXY', 'https_proxy', 'HTTP_PROXY', 'http_proxy', 'ALL_PROXY', 'all_proxy']! {
		os.unsetenv(name)
	}
	os.setenv('NO_PROXY', '*', true)
	os.setenv('no_proxy', '*', true)
	os.setenv('CURL_HOME', f.work, true)
	os.write_file(f.work + '/.curlrc', 'insecure\n')!
	os.setenv('CURL_CA_BUNDLE', f.ca, true)
	root := f.work + '/store-' + mode
	store := pkgcore.state_directory(root)
	target := f.work + '/transfer.part'
	object := store + '/objects/' + f.payload.sha256
	part := object + '.part'
	current := store + '/current'
	base := (if mode.ends_with('-hostname') { f.wrong_host } else { f.base }) + '/' + mode
	route := if mode.ends_with('-fallback') || mode.ends_with('-corrupt') {
		'no-range' + if mode.ends_with('-corrupt') { '-corrupt' } else { '' }
	} else if mode.ends_with('-truncated') {
		'truncated'
	} else if mode.ends_with('-http') {
		'forbidden'
	} else if mode.ends_with('-redirect') {
		'insecure-redirect'
	} else if mode.ends_with('-size') {
		'oversized'
	} else {
		'ranges'
	}
	url := base + '/' + route
	service := pkgcore.Service{ root: root, progress: event }
	mut history := ''
	if !mode.starts_with('fetch-') {
		os.mkdir_all(root + '/etc/vinix-packages')!
		config := pkgcore.Config{
			architecture: f.architecture
			repositories: [pkgcore.Repository{ id: 'tls-runtime', public_key: f.key, url: f.base + '/' + mode + '/setup' }]
			policy:       pkgcore.Policy{ reserve_bytes: 0 }
		}
		os.write_file(root + '/etc/vinix-packages/config.json', json2.encode(config))!
		mut catalog := service.refresh()!
		catalog.close()
		history = os.read_file(store + '/trust-history.json')!
		repository := pkgcore.Repository{ ...config.repositories[0], url: url }
		os.write_file(root + '/etc/vinix-packages/config.json', json2.encode(pkgcore.Config{ ...config, repositories: [repository] }))!
		os.write_file(store + '/catalog.json', json2.encode([pkgcore.Snapshot{ repository: repository, text: f.index, signature: f.signature }]))!
	}
	cache := if mode.starts_with('refresh-') { os.read_file(store + '/catalog.json')! } else { '' }
	names := ['app']
	mut retained := u64(0)
	for pass in 0 .. 2 {
		loops := if pass == 0 { tlsruntime.warmups } else { tlsruntime.cycles }
		for _ in 0 .. loops {
			os.setenv('CURL_CA_BUNDLE', if mode.ends_with('-untrusted') {
				f.untrusted
			} else {
				f.ca
			}, true)
			prefix := if mode.ends_with('-bad-prefix') { 'x'.repeat(512) } else { f.text[..512] }
			if mode.starts_with('fetch-') { os.write_file(target, prefix)! }
			if mode.starts_with('install-') {
				C.remove(current.str)
				C.remove(object.str)
				C.remove(part.str)
				if os.exists(store + '/generations/1') { os.rmdir_all(store + '/generations/1')! }
				if mode !in ['install-fresh', 'install-untrusted', 'install-hostname']! {
					os.write_file(part, prefix)!
				}
			}
			$if track_heap ? {
				C.vinix_heap_begin()
			}
			mut refused := false
			mut message := ''
			if mode.starts_with('fetch-') {
				resource := if mode.ends_with('-http') || mode.ends_with('-redirect') {
					'/objects/' + f.payload.sha256
				} else {
					'/payload'
				}
				endpoint := url + resource
				pkgcore.fetch(endpoint, target, u64(f.text.len), mode != 'fetch-fresh' && mode != 'fetch-size', false) or {
					refused = true
					message = err.msg()
					unsafe { err.free() }
				}
				unsafe {
					endpoint.free()
					resource.free()
				}
			} else if mode.starts_with('refresh-') {
				mut catalog := service.refresh() or {
					refused = true
					message = err.msg()
					unsafe { err.free() }
					pkgcore.Catalog{}
				}
				catalog.close()
			} else {
				mut result := service.transact('install', names, pkgcore.TransactionOptions{}) or {
					refused = true
					message = err.msg()
					unsafe { err.free() }
					pkgcore.State{}
				}
				if !refused {
					assert result.generation == 1 && result.packages[0].package.files[0] == f.payload
				}
				result.close()
				result.close()
			}
			expected_failure := mode.ends_with('-untrusted') || mode.ends_with('-hostname') || mode.ends_with('-http')
				|| mode.ends_with('-redirect') || mode.ends_with('-size') || mode.ends_with('-truncated')
				|| mode.ends_with('-corrupt') || mode.ends_with('-signature')
			assert refused == expected_failure, mode + ': ' + message
			if refused {
				wanted := if mode.ends_with('-untrusted') || mode.ends_with('-hostname') {
					'download failed (60)'
				} else if mode.ends_with('-http') {
					'download failed (22)'
				} else if mode.ends_with('-redirect') {
					'download failed (1)'
				} else if mode.ends_with('-size') {
					'download failed (63)'
				} else if mode.ends_with('-truncated') {
					'download failed (18)'
				} else if mode.ends_with('-signature') {
					'signature verification failed'
				} else {
					'checksum or size mismatch'
				}
				assert message.contains(wanted), message
			}
			unsafe { message.free() }
			$if track_heap ? {
				bytes := C.vinix_heap_end()
				if pass == 1 { retained += bytes }
			}
			if mode.starts_with('refresh-') && refused {
				assert os.read_file(store + '/catalog.json')! == cache && os.read_file(store + '/trust-history.json')! == history
			}
			if mode.starts_with('install-') {
				assert os.exists(current) == !refused && !os.exists(store + '/generations/.stage-1')
				if !refused {
					assert os.read_file(object)! == f.text && os.read_file(current + '/apps/app/share/payload')! == f.text
				} else {
					assert !os.exists(store + '/generations/1')
				}
			}
			if mode.starts_with('fetch-') && !refused {
				assert os.read_file(target)! == f.text
			}
			if mode.ends_with('-truncated') {
				// Prove that the failed call retained exactly the interrupted prefix
				// before retrying the same destination without replacing its bytes.
				assert os.read_file(if mode.starts_with('fetch-') { target } else { part })! == f.text[..1536]
			}
			if mode.ends_with('-corrupt') {
				assert !os.exists(part)
			}
			if mode.ends_with('-http') || mode.ends_with('-redirect') || mode.starts_with('fetch-') && refused && !mode.ends_with('-truncated') {
				assert os.read_file(if mode.starts_with('fetch-') { target } else { part })! == prefix
			}
			// Every production child must already have been reaped by fetch.
			reaped()
			if mode.ends_with('-truncated') {
				$if track_heap ? {
					C.vinix_heap_begin()
				}
				if mode.starts_with('fetch-') {
					endpoint := url + '/payload'
					pkgcore.fetch(endpoint, target, u64(f.text.len), true, false)!
					unsafe { endpoint.free() }
				} else {
					mut result := service.transact('install', names, pkgcore.TransactionOptions{})!
					assert result.generation == 1 && result.packages[0].package.files[0] == f.payload
					result.close()
					result.close()
				}
				$if track_heap ? {
					bytes := C.vinix_heap_end()
					if pass == 1 { retained += bytes }
				}
				if mode.starts_with('fetch-') {
					assert os.read_file(target)! == f.text
				} else {
					assert os.exists(current) && !os.exists(part) && !os.exists(store + '/generations/.stage-1')
					assert os.read_file(object)! == f.text && os.read_file(current + '/apps/app/share/payload')! == f.text
				}
				reaped()
			}
		}
	}
	println('GUEST TLS ' + mode + ' retained ' + retained.str() + ' tracked bytes')
	assert retained == 0, mode
}

fn main() {
	assert os.args.len == 3, 'usage: https-runtime-probe FIXTURE_JSON CASE'
	f := json2.decode[tlsruntime.Fixture](os.read_file(os.args[1])!)!
	check(f, os.args[2]) or {
		eprintln(err)
		exit(1)
	}
}
