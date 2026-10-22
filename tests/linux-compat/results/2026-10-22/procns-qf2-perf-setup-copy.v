import os

fn main() {
	area := '/Users/alex/.cache/vinix-linux-compat/procns-resume-20261022'
	target := area + '/qf2-perf-setup.v'
	assert !os.exists(target)
	text := os.read_file(area + '/qf-perf-setup.v')!
	os.write_file(target, text.replace("area + '/qf-perf-inputs.sha256'", "area + '/qf2-perf-inputs.sha256'").replace("area + '/qf-perf-setup.v'", "area + '/qf2-perf-setup.v'"))!
}
