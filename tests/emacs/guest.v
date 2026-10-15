// SPDX-License-Identifier: GPL-2.0-or-later
module main

import os
import time

fn main() {
	for path in ['/tmp', '/run/user/0', '/root', '/dev/shm', '/var/log', '/var/lib/xkb',
		'/tmp/.X11-unix'] { os.mkdir_all(path)! }
	for path in ['/tmp', '/dev/shm', '/tmp/.X11-unix'] { os.chmod(path, 0o1777)! }
	os.setenv('HOME', '/root', true)
	os.setenv('PATH', '/usr/bin:/bin:/usr/sbin:/sbin', true)
	os.setenv('TERM', 'linux', true)
	os.setenv('LD_LIBRARY_PATH', '/usr/lib:/lib:/usr/lib/xorg/modules', true)
	os.write_file('/root/.vinix-user', 'version=1\nname=56696e6978\nkdf=scrypt\nn=16384\nr=8\np=1\nsalt=00112233445566778899aabbccddeeff\nhash=00112233445566778899aabbccddeeff00112233445566778899aabbccddeeff\n')!
	os.chmod('/root/.vinix-user', 0o600)!
	// Also exercise the portable dump, Lisp evaluator and real guest file I/O.
	mut check := os.new_process('/usr/bin/run-emacs')
	check.set_args(['--batch', '-Q', '--eval', '(progn (with-temp-file "/root/emacs-check.txt" (insert "Emacs on Vinix\\n")) (with-temp-buffer (insert-file-contents "/root/emacs-check.txt") (unless (equal (buffer-string) "Emacs on Vinix\\n") (kill-emacs 2))) (message "EMACS CHECK: Lisp evaluation and file round trip PASS"))'])
	check.run()
	check.wait()
	assert check.code == 0
	check.close()
	os.write_file('/root/hello.el', ";; GNU Emacs running on Vinix\n;; Native ARM64 / musl, in a Vinix desktop window.\n\n(defun hello-vinix ()\n  (interactive)\n  (message \"Hello from Emacs on Vinix!\"))\n\n(hello-vinix)\n")!
	os.write_file('/root/.emacs', '(setq inhibit-startup-screen t initial-scratch-message nil)\n(tool-bar-mode -1)\n(setq default-frame-alist (quote ((width . 100) (height . 36) (font . "DejaVu Sans Mono-13"))))\n(find-file "/root/hello.el")\n')!
	println('EMACS GUEST: starting Vinix desktop with Emacs')
	mut desktop := os.new_process('/usr/bin/vinix-desktop')
	desktop.set_args(['--open=Emacs'])
	desktop.run()
	mut seen := map[string]int{}
	mut saved := false
	for {
		time.sleep(time.second)
		for name in os.ls('/tmp') or { []string{} } {
			if !name.starts_with('vinix-emacs-') || !name.ends_with('.log') { continue }
			path := '/tmp/${name}'
			log := os.read_file(path) or { continue }
			if log.len > seen[path] {
				println('EMACS HOST LOG:\n' + log[seen[path]..])
				seen[path] = log.len
			}
		}
		if !saved && (os.read_file('/root/hello.el') or { '' }).contains('Keyboard editing and saving work.') {
			println('EMACS CHECK: GUI keyboard edit and save PASS')
			saved = true
		}
	}
}
