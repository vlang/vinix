module main
import crypto.sha256
import json2
import os
struct Pin { path string bytes u64 sha256 string }
fn pin(path string) !Pin { b := os.read_bytes(path)!; defer { unsafe { b.free() } }; return Pin{ path: path, bytes: u64(b.len), sha256: sha256.sum(b).hex() } }
fn run(binary string, log string) ! {
	mut child := os.new_process(binary); child.set_redirect_stdio_merged()
	child.run(); output := child.stdout_slurp(); child.wait(); code := child.code; child.close()
	os.write_file(log, output)!; assert code == 0, output; print(output)
}
fn main() {
	work := os.real_path(os.dir(@FILE)); mut pins := []Pin{}
	for source in ['composition.v', 'composition_ownership_test.v', 'catalog.v', 'release.v'] {
		os.cp('tools/packages/pkgcore/' + source, work + '/baseline-' + source)!
		pins << pin(work + '/baseline-' + source)!
	}
	pins << pin(work + '/baseline')!
	os.unsetenv('VINIX_COMPOSITION_GOLDEN')
	run(work + '/baseline', work + '/baseline.txt')!
	os.mkdir(work + '/golden')!
	os.setenv('VINIX_COMPOSITION_GOLDEN', work + '/golden', true)
	run(work + '/baseline', work + '/golden-run.txt')!
	pins << pin(work + '/baseline.txt')!
	for name in os.ls(work + '/golden')! { pins << pin(work + '/golden/' + name)! }
	os.write_file(work + '/baseline.json', json2.encode(pins) + '\n')!
}
