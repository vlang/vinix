// SPDX-License-Identifier: GPL-2.0-or-later
module pkgcore

// curl's local exit status survives the administrator-service boundary even
// when its stderr belongs to the daemon. Keep explanations independent of
// server text; they do not change transport policy or decide whether to retry.
fn https_failure_reason(code int) string {
	return match code {
		1 { 'HTTPS or redirect protocol is unsupported; check the repository URL and HTTPS support in curl' }
		2, 4, 48 { 'HTTPS transport could not initialize a required feature; repair or update the installed curl tool' }
		3 { 'repository URL is malformed; ask an administrator to correct the repository configuration' }
		5 { 'proxy hostname could not be resolved; check proxy settings and DNS' }
		6 { 'repository hostname could not be resolved; check the network connection, DNS and repository URL' }
		7 { 'cannot connect to the repository; check the network connection, proxy settings and server availability' }
		16, 92, 95, 96 { 'HTTPS protocol connection failed; check the repository or proxy and retry' }
		18 { 'repository ended the transfer before all bytes arrived; retry to resume the retained partial download' }
		22 { 'repository returned an HTTP error; check repository access and availability, then refresh its catalog' }
		23 { 'HTTPS transport could not deliver downloaded bytes; check the I/O diagnostic, storage and available disk space' }
		27 { 'HTTPS transport ran out of memory; close other applications and retry' }
		28 { 'HTTPS transfer timed out; check the network connection or proxy and retry to resume retained data' }
		33, 36 { 'repository could not resume the requested byte range; check the repository or proxy and refresh its catalog' }
		35 { 'TLS handshake failed; check the repository and proxy TLS configuration' }
		47 { 'repository redirected too many times; ask an administrator to correct its URL or redirect configuration' }
		52 { 'repository returned no response; check server availability and retry' }
		55, 56 { 'network transfer was interrupted; check the connection or proxy and retry to resume retained data' }
		58, 98 { 'HTTPS client certificate is missing or unusable; ask an administrator to check client certificate configuration' }
		59 { 'TLS cipher configuration is unsupported; ask an administrator to check the repository and HTTPS transport configuration' }
		60 { 'repository certificate or hostname could not be verified; check the system clock, repository hostname and trusted CA certificates' }
		63 { 'repository response exceeds the allowed download size; refresh the catalog or contact the publisher' }
		67, 94 { 'repository authentication failed; ask an administrator to check repository access configuration' }
		77 { 'trusted CA certificates could not be read; ask an administrator to repair the CA bundle path, contents or permissions' }
		80 { 'TLS connection did not close correctly; check the connection and retry' }
		82, 83, 90, 91 { 'repository TLS identity or certificate status was rejected; ask an administrator to verify the repository and certificate trust configuration' }
		97 { 'proxy handshake failed; ask an administrator to check proxy access and configuration' }
		else {
			if code >= 128 { 'HTTPS transport terminated unexpectedly; check system diagnostics and retry' }
			else { 'HTTPS transport failed; inspect the transport diagnostic and check repository and network settings' }
		}
	}
}

fn https_transport_failure(code int, url string, program string) IError {
	number := code.str()
	defer { unsafe { number.free() } }
	message := if code == 126 || code == 127 {
		'download failed (' + number + '): cannot start HTTPS transport ' + program + '; ask an administrator to repair the installed transport; retained partial data for retry: ' + url
	} else {
		'download failed (' + number + '): ' + https_failure_reason(code) + '; retained partial data for retry: ' + url
	}
	return error(message)
}
