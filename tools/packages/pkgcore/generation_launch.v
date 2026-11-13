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
				return launchhold.run(launchhold.Command{program: launch.program, arguments: launch.arguments, directory: launch.directory}, lease)
			} $else { return error('owned Windows generation supervision is qualified only for x86_64') }
		}
	}
	return run_launch_process(launch)
}
