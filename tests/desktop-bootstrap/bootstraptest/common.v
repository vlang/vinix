// SPDX-License-Identifier: GPL-2.0-only
module bootstraptest

import hosttest
import json2
import os
import tarcore
import tarstream

pub struct Event {
pub:
	builder        string
	base_only      string
	args           []string
	init_published bool
}

pub fn write(path string, contents string, executable bool) ! {
	os.mkdir_all(os.dir(path))!
	os.write_file(path, contents)!
	if executable { os.chmod(path, 0o755)! }
}

pub fn record(root string, event Event) ! {
	mut file := os.open_file(root + '/events.jsonl', 'a')!
	defer { file.close() }
	file.write_string(json2.encode(event, escape_unicode: true, time_as_unix: true) + '\n')!
}

pub fn events(root string) ![]Event {
	contents := os.read_file(root + '/events.jsonl') or {
		if !os.exists(root + '/events.jsonl') { return []Event{} }
		return err
	}
	mut result := []Event{}
	for line in contents.split_into_lines() { result << json2.decode[Event](line)! }
	return result
}

pub fn clear(root string) ! {
	if os.exists(root + '/events.jsonl') { os.rm(root + '/events.jsonl')! }
}

pub fn environment() map[string]string {
	mut env := map[string]string{}
	for key, value in os.environ() {
		if !key.starts_with('VINIX_') && !key.starts_with('ALPINE_') { env[key] = value }
	}
	return env
}

fn tree(mut writer tarcore.Writer, directory string, relative string) ! {
	mut names := os.ls(directory)!
	names.sort()
	for name in names {
		path := directory + '/' + name
		member := relative + '/' + name
		assert !os.is_link(path)
		state := os.stat(path)!
		if os.is_dir(path) {
			writer.add(tarcore.Member{ name: member, mode: i64(state.mode & 0o777), kind: `5` }, []u8{})!
			tree(mut writer, path, member)!
		} else {
			data := os.read_bytes(path)!
			writer.add(tarcore.Member{ name: member, mode: i64(state.mode & 0o777), size: data.len }, data)!
		}
	}
}

pub fn pack(stage string, output string) ! {
	os.mkdir_all(os.dir(output))!
	mut writer := tarcore.create_stream(output)!
	defer { writer.close() }
	writer.add(tarcore.Member{ name: '.', kind: `5`, mode: 0o755 }, []u8{})!
	tree(mut writer, stage, '.')!
	writer.finish()!
	writer.close_checked()!
}

pub fn omit(output string, name string) ! {
	mut reader := tarstream.open_plain(output)!
	defer { reader.close() }
	mut writer := tarcore.create_stream(output + '.tmp')!
	defer { writer.close() }
	for {
		member := reader.next() or {
			if err is tarstream.End { break }
			return err
		}
		if member.name == name { continue }
		writer.write(tarcore.header(member)!)!
		reader.copy_to(mut writer)!
		writer.padding(member.size)!
	}
	writer.finish()!
	writer.close_checked()!
	reader.close()
	os.rename(output + '.tmp', output)!
}

pub fn archive_files(output string) ![]string {
	result := hosttest.capture(['tar', '-tf', output], '', 30, os.environ())!
	assert result.code == 0, result.stderr
	return result.stdout.trim_space().split_into_lines()
}
