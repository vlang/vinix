import os
fn command(args []string) !string {
	mut p := os.new_process('tar'); p.set_args(args); p.set_redirect_stdio(); p.run()
	output := p.stdout_slurp(); diagnostic := p.stderr_slurp(); p.wait(); code := p.code; p.close()
	if code != 0 { return error(diagnostic) }; return output
}
fn main() {
	area := '/tmp/vinix-iovposition-1013/'
	archive := '/Users/alex/code/vinix/build-support/init-aarch64/initramfs-desktop.tar'
	names := command(['-tf', archive])!.split_into_lines().filter(it.trim_left('./') == 'usr/bin/vinix-desktop')
	assert names.len == 1
	os.write_file(area + 'vinix-desktop', command(['-xOf', archive, names[0]])!)!
	os.chmod(area + 'vinix-desktop', 0o755)!
	os.mkdir_all(area + 'perf-before-kernel/bin')!
	os.cp(area + 'before-arm.kernel', area + 'perf-before-kernel/bin/vinix')!
	println('Extracted the cached image desktop and froze its baseline kernel')
}
