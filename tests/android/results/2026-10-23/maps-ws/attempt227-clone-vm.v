import os

fn main() {
	dest := 'build/android-maps/maps-live-vm'
	os.mkdir_all(dest)!
	for name in ['boot.img', 'efivars.fd'] {
		assert !os.exists(dest + '/' + name), name
		r := os.exec(['cp', '-c', 'build/android-native-ws/vm/' + name, dest + '/' + name])
		assert r.exit_code == 0, r.output
	}
	println('MAPS-LIVE-VM-CLONE PASS ' + os.abs_path(dest))
}
