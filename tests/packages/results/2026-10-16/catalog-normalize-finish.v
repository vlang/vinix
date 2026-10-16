module main
import os
fn task(name string, argv []string, work string, expected int, marker string) ! {
	mut child := os.new_process(argv[0]); child.set_args(argv[1..]); child.set_redirect_stdio_merged()
	child.run(); output := child.stdout_slurp(); child.wait(); code := child.code; child.close()
	os.write_file(work + '/' + name + '.txt', output)!
	assert code == expected && output.contains(marker), output
	println(name + ' PASS')
}
fn main() {
	work := os.real_path(os.dir(@FILE)); controller := work + '/controller'
	for arch in ['aarch64', 'x86_64']! { task('list-' + arch, [controller, '--arch', arch, '--list'], work, 0, 'packages-catalog-normalize')! }
	os.unsetenv('VINIX_HWTEST_TCG')
	task('refuse-inputs', [controller, '--arch', 'aarch64', '--kernel', work + '/absent'], work, 2, 'VINIX_HWTEST_TCG=1')!
	os.setenv('VINIX_HWTEST_TCG', '1', true)
	task('refuse-existing', [controller, '--arch', 'aarch64', '--kernel', os.real_path('build/pcn-arm-2/kernel'),
		'--state-dir', os.real_path('build/pcn-arm-2')], work, 2, 'new --state-dir')!
}
