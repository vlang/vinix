fn main() {
	$if tinyc {
		println('V runs natively on Vinix')
	} $else {
		eprintln('V did not use Alpine TCC')
		exit(1)
	}
}
