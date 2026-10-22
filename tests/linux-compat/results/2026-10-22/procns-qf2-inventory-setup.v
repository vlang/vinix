import os

fn main() {
	area := '/Users/alex/.cache/vinix-linux-compat/procns-resume-20261022'
	path := area + '/qf2-inventory.v'
	assert !os.exists(path)
	text := os.read_file(area + '/qf-inventory.v')!
	os.write_file(path, text.replace('qf-', 'qf2-'))!
}
