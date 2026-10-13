// SPDX-License-Identifier: GPL-2.0-or-later
module qualcore

import os
import sourcecommand

fn test_http_status_and_header_framing_reject_truncated_or_invalid_responses() {
	parsed := response('HTTP/1.0 200 OK\r\nContent-Length: 2\r\n\r\n42')!
	assert parsed.status == 200 && parsed.length == 2 && parsed.body == '42'
	for invalid in ['', 'HTTP/1.0 200 OK\r\nContent-Length: 2', 'HTTP/1.0 two OK\r\n\r\n', 'SMTP 200 OK\r\n\r\n'] {
		if _ := response(invalid) { assert false, 'invalid HTTP response accepted' }
	}
	if _ := expect_http(HttpResponse{200, 0, ''}, 401, '', false) {
		assert false, 'unauthorized success accepted'
	}
}

fn test_http_artifact_creation_refuses_existing_files_and_symlink_aliases() {
	root := sourcecommand.temporary('vinix-http-private')!
	defer { os.rmdir_all(root) or {} }
	write_private_http(root + '/token', 'sentinel')!
	assert os.stat(root + '/token')!.mode & 0o777 == 0o600
	if _ := write_private_http(root + '/token', 'overwrite') { assert false, 'existing private file overwritten' }
	os.symlink('token', root + '/alias')!
	if _ := write_private_http(root + '/alias', 'overwrite') { assert false, 'private file alias followed' }
	assert os.read_file(root + '/token')! == 'sentinel'
}
