// SPDX-License-Identifier: GPL-2.0-or-later
module pkgcore

import tools.packages.launchhold

// Opt-in counterpart to the SDK's owned entrypoint. Keep holder creation out
// of the shared caller: only the private holder may reap arbitrary descendants.
// The caller owns the verified lease throughout; holder SIGKILL remains outside
// this guarantee. Non-Windows and default builds keep their original behavior.
fn run_generation_launch(launch Launch, windows bool, lease int) !int {
	$if wine_owned_manager ? {
		if windows {
			$if amd64 {
				mut held := lease
				if lease >= 0 && lease < 3 {
					flags := C.fcntl(lease, C.F_GETFD)
					if flags < 0 || flags & C.FD_CLOEXEC == 0 { return error('owned Windows generation lease must be close-on-exec') }
					held = C.fcntl(lease, C.F_DUPFD_CLOEXEC, 3)
					if held < 3 { return error('cannot retain Windows generation lease above standard streams') }
				}
				// Duplicate the same open description, never unlock/reopen it. The
				// borrowed low descriptor stays CLOEXEC and remains the caller's.
				defer { if held != lease { C.close(held) } }
				return launchhold.run(launchhold.Command{program: launch.program, arguments: launch.arguments, directory: launch.directory}, held)
			} $else { return error('owned Windows generation supervision is qualified only for x86_64') }
		}
	}
	return run_launch_process(launch)
}
