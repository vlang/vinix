import os
import crypto.sha256

fn main() {
	b := 'build/android-maps/'
	os.mv(b + 'native228', b + 'native228-initial')!
	os.mv(b + 'libnative228.so', b + 'libnative228-initial.so')!
	r := os.exec([b + 'build-native228'])
	os.write_file(b + 'native228-build.log', r.output)!
	print(r.output)
	assert r.exit_code == 0, r.output
	hash := sha256.sum(os.read_bytes(b + 'libnative228.so')!).hex()
	os.write_file(b + 'native228-identity.txt', hash + '\n')!
	prepare := b + 'prepare228.v'
	os.write_file(prepare, os.read_file(prepare)!.replace('d688d0d93f38d0b8672eef361987ac4195e329d03b7d4da8ad89327918519182', hash))!
}
