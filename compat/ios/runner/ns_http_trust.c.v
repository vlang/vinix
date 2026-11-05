// SPDX-License-Identifier: GPL-2.0-or-later
module main

fn C.lstat(&char, &C.stat) int

// System-owned bundle locations used by GNU Linux distributions. Preserve an
// existing cert.pem installation before trying Debian, Fedora/RHEL or SUSE
// locations. Environment variables never select or replace application trust.
const data_http_linux_ca_files = [
	'/etc/ssl/cert.pem',
	'/etc/ssl/certs/ca-certificates.crt',
	'/etc/pki/tls/certs/ca-bundle.crt',
	'/etc/ssl/ca-bundle.pem',
	'/etc/pki/ca-trust/extracted/pem/tls-ca-bundle.pem',
]

// The result borrows a candidate string. Only a missing path permits fallback:
// a broken symlink, unreadable file or non-file blocks selection. Certificate
// parsing remains in secure(), so malformed selected bundles also fail closed.
fn data_http_select_ca_file(candidates []string) string {
	for path in candidates {
		mut entry := C.stat{}
		if C.lstat(path.str, &entry) != 0 {
			if C.errno == C.ENOENT { continue }
			return ''
		}
		if int(entry.st_mode) & C.S_IFMT !in [C.S_IFREG, C.S_IFLNK]! { return '' }
		fd := C.open(path.str, C.O_RDONLY | C.O_CLOEXEC | C.O_NONBLOCK)
		if fd < 0 { return '' }
		mut info := C.stat{}
		regular := C.fstat(fd, &info) == 0 && int(info.st_mode) & C.S_IFMT == C.S_IFREG
		closed := C.close(fd) == 0
		if !regular || !closed { return '' }
		return path
	}
	return ''
}

fn data_http_system_ca_file() string {
	$if linux {
		$if glibc ? { return data_http_select_ca_file(data_http_linux_ca_files) }
	}
	// Vinix's musl image and the existing macOS profile retain their path.
	return '/etc/ssl/cert.pem'
}
