// Validate the final merged amd64 root, without executing guest binaries.
import desktopimage
import os

if os.args.len != 2 {
	eprintln('Usage: check-desktop-firefox.v STAGING')
	exit(2)
}
reader := desktopimage.find_readelf() or {
	eprintln(err)
	exit(1)
}
desktopimage.validate(os.args[1], reader) or {
	eprintln('ERROR: Firefox desktop image: ${err}')
	exit(1)
}
println('Firefox desktop image: amd64 binaries, interpreter and runtime closure verified')
