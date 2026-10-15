// Reuse frozen ELF/object bytes; this deliberately does not invoke a C compiler.
import crypto.sha256
import json2
import os
const area = '/Users/alex/.cache/vinix-linux-compat/randomsignal-20261015'
fn digest(path string) string { return sha256.sum(os.read_bytes(path) or { panic(err) }).hex() }
fn main() {
	if os.args.len == 2 && os.args[1] == 'freeze' {
		assert !os.exists(area + '/replay-inputs.json')
		mut pins := map[string]string{}
		for name in ['randomsignal','runtime','randomrange'] {
			state := area + '/states/' + if name == 'randomsignal' { 'p1-before-arm' } else { 'p1-after-arm' }
			for file in ['fixture.c','serial.c','fixture.o','serial.o','init'] { pins[state + '/' + name + '/' + file] = digest(state + '/' + name + '/' + file) }
			path := state + '/sources/' + name + 'fixture/core.v'; pins[path] = digest(path)
		}
		os.write_file(area + '/replay-inputs.json', json2.encode(pins, prettify:true) + '\n')!; return
	}
	pins := json2.decode[json2.Any](os.read_file(area + '/replay-inputs.json')!)!.as_map_of_strings()
	assert pins.len == 18
	for path, hash in pins { assert digest(path) == hash, path }
	output_arg := os.args.index('-o'); assert output_arg > 0 && output_arg + 1 < os.args.len
	output := os.args[output_arg + 1]
	assert output.starts_with(area + '/states/p3-after-arm/')
	name := os.file_name(os.dir(output)); assert name in ['randomsignal','runtime','randomrange']
	kind := os.file_name(output); assert kind in ['fixture.o','serial.o','init']
	frozen := area + '/states/' + if name == 'randomsignal' { 'p1-before-arm' } else { 'p1-after-arm' }
	probe := frozen + '/' + name
	new_probe := os.dir(output)
	source := os.dir(new_probe) + '/sources/' + name + 'fixture/core.v'
	assert digest(source) == pins[frozen + '/sources/' + name + 'fixture/core.v']
	mut evidence := {'source':digest(source), 'frozen':probe + '/' + kind, 'input':pins[probe + '/' + kind]}
	assert '--target=aarch64-linux-musl' in os.args
	if kind != 'init' {
		input_arg := os.args.index('-c'); assert input_arg > 0 && input_arg + 1 < os.args.len
		generated := os.args[input_arg + 1]
		assert generated == new_probe + '/' + kind.all_before_last('.') + '.c'
		assert digest(generated) == pins[probe + '/' + os.file_name(generated)]
		evidence['generated_c'] = digest(generated)
	} else {
		assert '-static' in os.args && '-c' !in os.args
		for file in ['fixture.c','serial.c','fixture.o','serial.o'] {
			assert digest(new_probe + '/' + file) == pins[probe + '/' + file]
			evidence[file] = digest(new_probe + '/' + file)
		}
		assert new_probe + '/fixture.o' in os.args && new_probe + '/serial.o' in os.args
	}
	bytes := os.read_bytes(probe + '/' + kind)!; os.write_file_array(output, bytes)!
	assert digest(output) == pins[probe + '/' + kind]
	evidence['output'] = digest(output)
	evidence['argv'] = json2.encode(os.args[1..])
	os.write_file(area + '/replay-' + name + '-' + kind + '.json', json2.encode(evidence, prettify:true) + '\n')!
	println('REPLAY frozen bytes: ' + probe + '/' + kind + ' -> ' + output)
}
