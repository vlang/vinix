import desktopimage
import os

fn main() {
	if os.args.len != 3 {
		eprintln('usage: archive-x11-bundle SOURCE TEMPORARY_ARCHIVE')
		exit(2)
	}
	desktopimage.bundle_archive(os.args[1], os.args[2]) or {
		eprintln(err.msg())
		exit(1)
	}
}
