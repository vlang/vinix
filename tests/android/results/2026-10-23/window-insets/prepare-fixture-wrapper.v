import os

fn main() {
	prepare := os.read_file('build/android-maps/prepare-insets238.v')!.replace('insets238', 'insets239').replace('INSETS238', 'INSETS239').replace('framework238-insets', 'framework239-insets').replace('to238', 'to239')
	os.write_file('build/android-maps/prepare-insets239-actual.v', prepare)!
	compiler := '/Users/alex/code/v/v_old'
	r := os.exec([compiler, '-nocache', '-cc', 'cc', 'run', 'build/android-maps/prepare-insets239-actual.v'])
	print(r.output)
	assert r.exit_code == 0
	proof := os.read_file('build/android-maps/prepare-insets-proof238.v')!.replace('insets238', 'insets239').replace('framework238-insets', 'framework239-insets')
	os.write_file('build/android-maps/prepare-insets-proof239.v', proof)!
}
