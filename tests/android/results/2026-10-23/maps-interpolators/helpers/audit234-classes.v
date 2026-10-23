import os

fn word(data []u8, at int) int {
	return int(u32(data[at]) | u32(data[at + 1]) << 8 | u32(data[at + 2]) << 16 | u32(data[at + 3]) << 24)
}

fn dex_type(data []u8, index int) string {
	mut at := word(data, word(data, 60) + word(data, word(data, 68) + index * 4) * 4)
	for data[at] & 128 != 0 { at++ }
	at++
	mut end := at
	for end < data.len && data[end] != 0 { end++ }
	return data[at..end].bytestr()
}

fn main() {
	work := 'build/android-maps/dex-refs'
	for name in os.ls(work)! {
		if !name.ends_with('.dex') { continue }
		data := os.read_bytes(work + '/' + name)!
		mut found := []string{}
		for i in 0 .. word(data, 96) {
			class_name := dex_type(data, word(data, word(data, 100) + i * 32))
			if class_name in os.args[1..] { found << class_name }
		}
		if found.len == 0 { continue }
		println(name + ': ' + found.join(','))
		result := os.exec(['/opt/homebrew/opt/openjdk@25/bin/java', '-cp', 'build/android-framework/tools/*', 'org.jf.baksmali.Main', 'disassemble', '--classes', found.join(','), '-o', 'build/android-maps/audit234-smali', work + '/' + name])
		if result.exit_code != 0 { panic(result.output) }
	}
}
