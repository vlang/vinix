module main
import crypto.sha256
import json2
import os
struct Pin { path string bytes u64 sha256 string }
fn main() {
	work := os.real_path(os.dir(@FILE)); mut pins := []Pin{}
	for name in ['catalog.v', 'catalog_plan_test.v'] { os.cp('tools/packages/pkgcore/' + name, work + '/baseline-' + name)! }
	mut child := os.new_process(work + '/baseline'); child.set_redirect_stdio_merged(); child.run()
	output := child.stdout_slurp(); child.wait(); code := child.code; child.close(); assert code == 0, output
	os.write_file(work + '/baseline.txt', output)!; print(output)
	for name in ['baseline-catalog.v', 'baseline-catalog_plan_test.v', 'baseline', 'baseline.txt'] {
		path := work + '/' + name; bytes := os.read_bytes(path)!
		pins << Pin{ path: path, bytes: u64(bytes.len), sha256: sha256.sum(bytes).hex() }
	}
	os.write_file(work + '/baseline.json', json2.encode(pins) + '\n')!
}
