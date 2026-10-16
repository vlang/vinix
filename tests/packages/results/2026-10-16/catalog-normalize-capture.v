module main
import crypto.sha256
import json2
import os
struct Pin { path string bytes u64 sha256 string }
fn pin(path string) !Pin { b := os.read_bytes(path)!; return Pin{ path: path, bytes: u64(b.len), sha256: sha256.sum(b).hex() } }
fn main() {
	work := os.real_path(os.dir(@FILE))
	mut pins := []Pin{}
	for source in ['catalog.v', 'release.v', 'model.v', 'resolve_search.v', 'catalog_normalize_test.v'] {
		path := 'tools/packages/pkgcore/' + source
		os.cp(path, work + '/baseline-' + source)!
		pins << pin(work + '/baseline-' + source)!
	}
	pins << pin(work + '/baseline')!
	mut child := os.new_process(work + '/baseline'); child.set_args(['--catalog-normalize-baseline']); child.set_redirect_stdio_merged()
	child.run(); output := child.stdout_slurp(); child.wait(); code := child.code; child.close()
	os.write_file(work + '/baseline.txt', output)!; assert code == 0, output
	pins << pin(work + '/baseline.txt')!
	os.write_file(work + '/baseline.json', json2.encode(pins) + '\n')!; print(output)
}
