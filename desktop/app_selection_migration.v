// SPDX-License-Identifier: GPL-2.0-or-later
module main

import desktop.packagecore

const first_run_release_review_action = 'software.release-review'

struct FirstRunReleaseRoute {
	root string = '/'
	owner u32
	architecture string
	enqueue fn () ! = first_run_enqueue_release_review
}

fn first_run_enqueue_release_review() ! {
	reply := session_call('action', [first_run_release_review_action])!
	defer { unsafe { reply.free() } }
	if reply != 'ok' { return error('Software release review is unavailable') }
}

fn first_run_signed_release_required(name string, route FirstRunReleaseRoute) !bool {
	architecture := if route.architecture != '' { route.architecture } else { $if arm64 { 'aarch64' } $else { 'x86_64' } }
	for app in first_run_apps {
		if app.package_name == name && app.signed_package_id != '' {
			return packagecore.release_requirement_at(route.root, route.owner, architecture, app.signed_package_id)
		}
	}
	return false
}

fn first_run_redirect_release(name string, route FirstRunReleaseRoute) !bool {
	if !first_run_signed_release_required(name, route)! { return false }
	(route.enqueue)()!
	return true
}

// Claim-time filtering is repeated by the explicit installer at execution:
// replacing the request/configuration cannot resurrect an Alpine Neovim path.
fn first_run_install_command_with_release(request string, route FirstRunReleaseRoute) string {
	words := request.fields()
	defer { unsafe { words.free() } }
	mut kept := []string{cap: first_run_apps.len}
	defer { unsafe { kept.free() } }
	mut redirected := false
	for word in words {
		for app in first_run_apps {
			if word != app.package_name || app.package_name in kept { continue }
			if app.signed_package_id != '' {
				required := first_run_signed_release_required(word, route) or {
					eprint('Setup ')
					eprint(word)
					eprint(': ')
					eprintln(err.msg())
					unsafe { err.free() }
					continue
				}
				if required {
					if !redirected {
						(route.enqueue)() or {
							eprint('Setup ')
							eprint(word)
							eprint(': ')
							eprintln(err.msg())
							unsafe { err.free() }
						}
						redirected = true
					}
					continue
				}
			}
			kept << app.package_name.clone()
		}
	}
	filtered := kept.join(' ')
	defer { unsafe { filtered.free() } }
	return first_run_install_command(filtered)
}
