// SPDX-License-Identifier: GPL-2.0-or-later
module tlsruntime

import tools.packages.pkgcore

pub const cycles = 8
pub const warmups = 2

pub struct Fixture {
pub:
	base         string
	wrong_host   string
	architecture string
	work         string
	ca           string
	untrusted    string
	key          string
	text         string
	payload      pkgcore.Payload
	index        string
	signature    string
}

pub fn modes() []string {
	return ['fetch-fresh', 'fetch-resume', 'fetch-fallback', 'fetch-truncated', 'fetch-http',
		'fetch-redirect', 'fetch-untrusted', 'fetch-hostname', 'fetch-size', 'refresh-fresh',
		'refresh-untrusted', 'refresh-hostname', 'refresh-signature', 'install-fresh', 'install-resume',
		'install-fallback', 'install-bad-prefix', 'install-truncated', 'install-http',
		'install-redirect', 'install-corrupt', 'install-untrusted', 'install-hostname']
}

pub fn requests(mode string) int {
	if mode.ends_with('-untrusted') || mode.ends_with('-hostname') { return 0 }
	if mode.starts_with('refresh-') || mode.ends_with('-fallback')
		|| mode.ends_with('-bad-prefix') || mode.ends_with('-corrupt') || mode.ends_with('-truncated') {
		return 2
	}
	return 1
}
