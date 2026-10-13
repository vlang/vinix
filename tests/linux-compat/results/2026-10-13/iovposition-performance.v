@[has_globals]
import os
import perfconsole
import perfrunner

fn execute(args []string) ! {
	// Shared cached images must not be pruned by this isolated qualification.
	if args[0].ends_with('/tools/prune-build-artifacts') {
		println('Qualification: preserving shared build archives'); return
	}
	perfrunner.command(args)!
}
fn main() {
	root := '/Users/alex/code/vinix'
	work := os.args[1]
	if os.exists(work) { panic('performance state must be fresh') }
	os.mkdir_all(work)!
	plan := perfrunner.parse(os.args[2..], root, root + '/tests/desktop-perf', '')!
	guard := perfconsole.own_commands(); defer { guard.close() }
	status := perfrunner.run_prepared(plan, work, execute) or { eprintln(err); exit(1) }
	exit(status)
}
