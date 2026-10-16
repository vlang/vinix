module main
import os
fn main() {
	work := os.real_path(os.dir(@FILE))
	for name, arguments in {
		'list-aarch64': ['--arch', 'aarch64', '--list'],
		'list-x86_64': ['--arch', 'x86_64', '--list'],
		'refuse-inputs': ['--arch', 'aarch64', '--kernel', work + '/missing', '--state-dir', work + '/uncreated'],
		'refuse-existing': ['--arch', 'aarch64', '--kernel', os.real_path('build/package-software-persistence-work/kernel-arm/kernel/bin/vinix'), '--state-dir', work]
	} {
		mut child := os.new_process(work + '/controller'); child.set_args(arguments); child.set_redirect_stdio_merged()
		child.run(); output := child.stdout_slurp(); child.wait(); code := child.code; child.close()
		os.write_file(work + '/' + name + '.txt', output)!
		assert (code == 0) == name.starts_with('list-'), output
		if name.starts_with('list-') { assert output.contains('packages-import-capture') } else { assert output.contains('new --state-dir') }
		assert !os.exists(work + '/uncreated')
		println(name + ' PASS')
	}
}
