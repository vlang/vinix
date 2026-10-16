module main
import json2
import os
struct Check { name string status int }
fn check(name string, args []string, status int, expected string, work string) !Check {
	mut child := os.new_process(work + '/controller'); child.set_args(args); child.set_redirect_stdio_merged()
	child.run(); output := child.stdout_slurp(); child.wait(); code := child.code; child.close()
	os.write_file(work + '/' + name + '.txt', output)!
	assert code == status && (expected == '' || output.contains(expected)), output
	if expected == '' { assert output.trim_space() == '' }
	println(name + ' PASS')
	return Check{ name: name, status: code }
}
fn main() {
	work := os.real_path(os.dir(@FILE)); mut results := []Check{}
	results << check('list-aarch64', ['--list', '--arch', 'aarch64'], 0, 'packages-apple', work)!
	results << check('list-x86_64', ['--list', '--arch', 'x86_64'], 0, '', work)!
	results << check('reject-x86_64', ['--arch', 'x86_64', '--kernel', work + '/absent'], 2, 'only on AArch64', work)!
	os.unsetenv('VINIX_HWTEST_TCG'); os.unsetenv('VINIX_APPLE_SANDBOX')
	results << check('reject-inputs', ['--arch', 'aarch64', '--kernel', work + '/absent'], 2, 'provide VINIX_HWTEST_TCG=1', work)!
	os.write_file(work + '/controller.json', json2.encode(results) + '\n')!
}
