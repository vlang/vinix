// SPDX-License-Identifier: GPL-2.0-or-later
module dictionaryfixture

import dictionarycore as dict
import encoding.binary
import os
import sourcecommand
import tarcore

#include <fcntl.h>

fn fd_count() int {
	mut count := 0
	for fd in 0 .. 1024 { if C.fcntl(fd, C.F_GETFD) >= 0 { count++ } }
	return count
}

fn value(data []u8, at int) int { return int(binary.little_endian_u32(data[at..at + 4])) }

fn records(data []u8) [][]string {
	assert data[..8].bytestr() == 'VNXDICT1'
	count, key_size, definition_size, reserved := value(data, 8), value(data, 12), value(data, 16), value(data, 20)
	assert reserved == 0 && data.len == 24 + count * 16 + key_size + definition_size
	keys := data[24 + count * 16..24 + count * 16 + key_size]
	definitions := data[24 + count * 16 + key_size..]
	mut result := [][]string{}
	for i in 0 .. count {
		at := 24 + i * 16
		key_at, key_len, text_at, text_len := value(data, at), value(data, at + 4), value(data, at + 8), value(data, at + 12)
		result << [keys[key_at..key_at + key_len].bytestr(), definitions[text_at..text_at + text_len].bytestr()]
	}
	return result
}

fn archive(path string, license_kind u8, license_size int, omitted string, repeated bool) ! {
	mut writer := tarcore.create_gzip(path)!
	defer { writer.close() }
	license := 'Fixture license\n'.bytes()
	writer.add(tarcore.Member{name: 'WordNet-3.0/LICENSE', kind: license_kind, size: license_size}, []u8{len: license_size, init: if index < license.len { license[index] } else { u8(`x`) }})!
	for kind in ['noun', 'verb', 'adj', 'adv'] {
		if kind == omitted { continue }
		line := if kind == 'adj' { '00000001 00 a 03 Good(a) 0 Good(p) 0 fine(ip) 0 000 | useful  \n' } else { '00000001 00 n 02 Computer 0 computer 0 000 | A machine.\n' }
		body := ('  Copyright header\n\n' + line + if repeated { line } else { '' }).bytes()
		writer.add(tarcore.Member{name: 'WordNet-3.0/dict/data.' + kind, size: body.len}, body)!
	}
	writer.finish()!
}

pub fn run() ! {
	work := sourcecommand.temporary('vinix-dictionary-fixture')!
	defer { os.rmdir_all(work) or {} }
	assert records(dict.encode({'zebra': 'last\nline', 'café': 'first', 'computer': 'middle'})!) == [['café', 'first'], ['computer', 'middle'], ['zebra', 'last\nline']]
	one := dict.encode({'é': 'emoji 😀', 'a': 'line\nnext'})!
	assert one == dict.encode({'a': 'line\nnext', 'é': 'emoji 😀'})!
	for entries in [map[string]string{}, {'': 'text'}, {'word': ''}, {'bad\tkey': 'text'},
		{'bad\u0085key': 'text'}, {'word': 'bad\x00text'}, {'word': 'bad\u0085text'},
		{'word': 'x'.repeat(dict.max_definition + 1)}, {'é'.repeat(65): 'too long'}] {
		if _ := dict.encode(entries) { return error('invalid lexicon accepted') }
	}
	path := work + '/dictionary.vnd'
	assert !dict.verified_archive(work + '/missing.tar.gz')
	os.write_file(work + '/wrong.tar.gz', 'wrong archive')!
	assert !dict.verified_archive(work + '/wrong.tar.gz')
	assert dict.cli(['--destination', work + '/never-staged', '--cache', work + '/cache', '--archive', work + '/wrong.tar.gz'], work) == 2
	assert !os.exists(work + '/never-staged')
	dict.atomic_write(path, 'first'.bytes())!
	dict.atomic_write(path, 'second'.bytes())!
	assert os.read_file(path)! == 'second' && os.stat(path)!.mode & 0o777 == 0o444
	assert os.ls(work)!.filter(it.starts_with('dictionary.vnd')) == ['dictionary.vnd']
	os.mkdir(work + '/target-directory')!
	if _ := dict.atomic_write(work + '/target-directory', 'cannot replace directory'.bytes()) { return error('failed publication accepted') }
	assert os.is_dir(work + '/target-directory') && os.ls(work)!.filter(it.starts_with('target-directory')) == ['target-directory']
	baseline := fd_count()
	for _ in 0 .. 100 { dict.atomic_write(path, 'complete'.bytes())! }
	assert fd_count() == baseline
	println('PASS five original dictionary contracts, publication failure cleanup and 100 flat descriptor cycles')
	archive(work + '/fixture.tar.gz', `0`, 16, '', true)!
	lexicon := dict.parse_wordnet(work + '/fixture.tar.gz')!
	assert lexicon.entries.len == 3
	assert lexicon.entries['computer'] == '[noun] A machine.\nRelated: computer\n\n[verb] A machine.\nRelated: computer\n\n[adverb] A machine.\nRelated: computer'
	assert lexicon.entries['good'] == '[adjective] useful\nRelated: good, fine'
	assert lexicon.entries['fine'] == lexicon.entries['good']
	assert lexicon.license == 'Fixture license\n'.bytes()
	for kind in ['linked', 'oversized', 'missing'] {
		archive(work + '/invalid.tar.gz', if kind == 'linked' { `2` } else { `0` }, if kind == 'oversized' { 16385 } else { 16 }, if kind == 'missing' { 'adv' } else { '' }, false)!
		if _ := dict.parse_wordnet(work + '/invalid.tar.gz') { return error('invalid WordNet member accepted') }
	}
	println('PASS compressed WordNet members, sense ordering/deduplication, adjective markers and unchanged license bytes')
}
