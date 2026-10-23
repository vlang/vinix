import os
import crypto.sha256

fn main() {
	source := 'build/android-maps/libnative229.so'
	assert sha256.sum(os.read_bytes(source)!).hex() == '1370bbfebd982d5597c4ccf9d2dd37df02d34a57b5b22afbaad008c1a158e3c6'
	target := 'build/android-maps/outline228/native-fixed/libvinix-android-native.so'
	os.rm(target)!
	os.symlink(os.abs_path(source), target)!
	println('OUTLINE-FIXED native2291370bbfe; signed APK unchanged; framework228 unchanged')
}
