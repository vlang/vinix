module main
import os
fn main() {
	dir := os.getwd() + '/build/android-maps/path228'
	out := dir + '/raw-huge'
	os.mkdir_all(out)!
	for name in ['path_clipping.v', 'actual_support.v', 'main.v'] {
		mut source := os.read_file(dir + '/raw/' + name)!
		if name == 'main.v' {
			source = source.replace('\tunsafe { C.free(host_draw) }', os.read_file(dir + '/huge_case.v.txt')! + '\n\tunsafe { C.free(host_draw) }')
		}
		os.write_file(out + '/' + name, source)!
	}
}
