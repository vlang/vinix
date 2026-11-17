import gpu
import fake
import os

fn main() {
	selected := if os.args.len == 2 { os.args[1] } else { '' }
	if selected != 'fake' { gpu.check_workers(selected) }
	if selected == '' || selected == 'fake' { fake.check_waits() }
}
