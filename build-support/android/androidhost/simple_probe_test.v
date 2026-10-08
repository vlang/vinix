module androidhost

import encoding.hex
import json2
import os

fn test_original_simple_archive_bytes_and_fixture_logger() {
	gold := json2.decode[Value](os.read_file(path_join(os.dir(@FILE), 'testdata/simple-probes.json'))!)!.object()
	root := simple_probe_temporary(os.temp_dir(), 'vinix-simple-golden-')!
	defer { retire_simple_probe(root) or { panic(err) } }
	classes := path_join(root, 'classes')
	mkdir_parents(classes)!
	for value in field(gold, 'files').items() {
		row := value.object()
		path := path_join(classes, field(row, 'name').text())
		mkdir_parents(path_parent(path))!
		os.write_file_array(path, hex.decode(field(row, 'data').text())!)!
	}
	archive := path_join(root, 'classes.jar')
	archive_simple_classes(classes, archive)!
	assert os.read_bytes(archive)!.hex() == field(gold, 'archive').text()
	assert simple_layout_logger == field(gold, 'logger').text()
}

fn test_failed_simple_pipeline_retires_scratch_and_descriptors() {
	root := simple_probe_temporary(os.temp_dir(), 'vinix-simple-retirement-')!
	defer { retire_simple_probe(root) or { panic(err) } }
	input := path_join(root, 'input.jar')
	os.write_file(input, 'fixture compiler input')!
	checksum := digest(input)!
	output := path_join(root, 'output/probe.jar')
	mut row := map[string]Value{}
	for key in ['r8', 'core_classes', 'framework_classes', 'stub_classes'] {
		row[key] = Value(input)
	}
	row['kind'] = Value('pointer-capture')
	row['output'] = Value(output)
	row['helper'] = Value(path_join(root, 'fixture.py'))
	row['javac'] = Value('/usr/bin/false')
	row['java'] = Value('/usr/bin/false')
	before := os.ls('/dev/fd')!.len
	for _ in 0 .. 100 {
		mut failed := false
		build_simple_probe_with_pins(row, checksum, checksum) or {
			assert err is ProbeCommandError
			assert err.status == 1
			failed = true
		}
		assert failed
		assert os.ls(path_parent(output))! == []string{}
	}
	assert os.ls('/dev/fd')!.len == before
}

fn test_simple_pin_sequence_and_unique_temporary_names() {
	root := simple_probe_temporary(os.temp_dir(), 'vinix-simple-order-')!
	defer { retire_simple_probe(root) or { panic(err) } }
	input := path_join(root, 'input.jar')
	os.write_file(input, 'fixture compiler input')!
	row := map[string]Value{
		'kind':         Value('layout-focus')
		'r8':           Value(input)
		'core_classes': Value(input)
	}
	assert build_simple_probe_with_pins(row, digest(input)!, '0'.repeat(64))! == input
	mut seen := map[string]bool{}
	for _ in 0 .. 100 {
		path := simple_probe_temporary(root, 'layout-focus-')!
		assert path !in seen
		seen[path] = true
		retire_simple_probe(path)!
	}
}
