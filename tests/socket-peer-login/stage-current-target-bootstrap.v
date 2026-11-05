// SPDX-License-Identifier: GPL-2.0-or-later
// Stage the fixed, reviewed bootstrap sources without sharing source inodes.
module main

import crypto.sha256
import json2
import os

const repository = '/Users/alex/code/vinix'
const state = '/Users/alex/Library/Caches/vinix-codex/section14/current-peer-frame-integration-20261105-01'
const setup = state + '/target-freeze-host-01'
const destination = setup + '/source'
const qualified = state + '/observer-host-01/source-03/tools/sourcecommand'

struct Source {
	path string
	relative string
	sha256 string
}

struct Identity {
	dev u64
	inode u64
	mode u32
	uid u32
	gid u32
	nlink u64
	size u64
	mtime i64
	ctime i64
	sha256 string
}

fn need(ok bool, message string) ! {
	if !ok { return error(message) }
}

fn exists(path string) bool {
	return os.exists(path) || os.is_link(path)
}

fn identity(path string) !Identity {
	before := os.lstat(path)!
	need(before.mode & 0o170000 == 0o100000 && before.nlink == 1
		&& before.uid == u32(os.getuid()) && before.size <= 256 * 1024,
		'requires an independent owned source file of at most 256KiB: ' + path)!
	hash := sha256.sum(os.read_bytes(path)!).hex()
	after := os.lstat(path)!
	need(before.dev == after.dev && before.inode == after.inode && before.mode == after.mode
		&& before.uid == after.uid && before.gid == after.gid && before.nlink == after.nlink
		&& before.size == after.size && before.mtime == after.mtime && before.ctime == after.ctime,
		'source metadata changed during capture: ' + path)!
	return Identity{before.dev, before.inode, before.mode, before.uid, before.gid,
		before.nlink, before.size, before.mtime, before.ctime, hash}
}

fn sources() []Source {
	return [
		Source{repository + '/tests/socket-peer-login/prepare-current-target-input.v',
			'tests/socket-peer-login/prepare-current-target-input.v',
			'c28b539f946627896dc16a61e2f6dc95b7d170cda139dbefea48d361089284eb'},
		Source{state + '/host-bootstrap-01/source/tests/software-hosted-x11/nativeguard/guard.v',
			'tests/software-hosted-x11/nativeguard/guard.v',
			'5aa9cea7b338b914f7548a9a63a86ae6874dabb373350a5605f068fa7f2858ce'},
		Source{state + '/host-bootstrap-01/source/tests/software-hosted-x11/diagnostics/recoveryguard/recoveryguard.v',
			'tests/software-hosted-x11/diagnostics/recoveryguard/recoveryguard.v',
			'924cf415fc8b73661700394f830dd56a421dac1f08fc3ca00421a561e520a154'},
		Source{qualified + '/abi.h', 'tools/sourcecommand/abi.h',
			'a816e3d27024ede2dfba4e04eeb473d81ee0f47f1381ada687edce51a6e32d23'},
		Source{qualified + '/core.v', 'tools/sourcecommand/core.v',
			'5b5ba4be07027e508ff881602a9a9f100491f0c65164607b39ee58e987117212'},
		Source{qualified + '/duplex.v', 'tools/sourcecommand/duplex.v',
			'c6b57a59aa570f208b7b8f17d775d6623ca8edf8a525f485039d101c27d97dc2'},
		Source{qualified + '/logged.v', 'tools/sourcecommand/logged.v',
			'c09ebbda5f9f76fd2cfc9a17c8ff66442efa16a2210a5bfb83c354b6fd9fcafa'},
		Source{qualified + '/pty.v', 'tools/sourcecommand/pty.v',
			'733cd8ebed8e1f358ba4616d9b97d0c0bcb399e1a809aba1ce523b534497fa18'},
		Source{qualified + '/pty_test.v', 'tools/sourcecommand/pty_test.v',
			'fde3a446ff0d242566f015d464210708d5ed7a66455dd63a9cc654571c75ccc3'},
		Source{qualified + '/reader.v', 'tools/sourcecommand/reader.v',
			'20c3b6a17589d65e59d6d8a31ce6af4276333757a1db78458d368f84fed38129'},
	]
}

fn stage() ! {
	need(os.args.len == 2 && os.args[1] == '--stage', 'requires exact --stage')!
	need(os.read_file(@FILE)! == $embed_file('stage-current-target-bootstrap.v').to_string(),
		'stager source differs from its compiled source')!
	parent := os.lstat(setup)!
	need(os.real_path(setup) == setup && parent.mode & 0o170000 == 0o040000
		&& parent.uid == u32(os.getuid()) && parent.mode & 0o022 == 0,
		'requires canonical owned bootstrap directory')!
	need(!exists(destination) && !exists(setup + '/source-stage.json'),
		'bootstrap source scope must be fresh; preserve failed stages')!
	mut inputs := map[string]Identity{}
	for source in sources() {
		value := identity(source.path)!
		need(value.sha256 == source.sha256 && value.mode & 0o7777 == 0o644,
			'reviewed source bytes or mode differ: ' + source.path)!
		inputs[source.path] = value
	}
	os.mkdir(destination)!
	mut copies := map[string]Identity{}
	for source in sources() {
		path := destination + '/' + source.relative
		os.mkdir_all(os.dir(path))!
		os.cp(source.path, path, fail_if_exists: true)!
		os.chmod(path, 0o644)!
		copy := identity(path)!
		original := inputs[source.path]
		need(copy.sha256 == source.sha256 && copy.mode & 0o7777 == 0o644
			&& copy.dev == parent.dev && copy.inode != original.inode,
			'independent source copy differs: ' + path)!
		copies[path] = copy
	}
	for path, before in inputs {
		need(identity(path)! == before, 'input changed during staging: ' + path)!
	}
	for path, before in copies {
		need(identity(path)! == before, 'captured source changed during staging: ' + path)!
	}
	os.write_file(setup + '/source-stage.json', json2.encode({
		'format': 'current-target-bootstrap-source-v1',
		'stager_source_sha256': sha256.hexhash($embed_file('stage-current-target-bootstrap.v').to_string()),
		'inputs': json2.encode(inputs), 'copies': json2.encode(copies),
		'scope': 'Ten fixed source copies, exact reviewed bytes and before/after identities. No compiler, input freeze, kernel build, process cleanup or runtime qualification.'
	}) + '\n')!
	println('CURRENT TARGET BOOTSTRAP SOURCE PASS 10')
}

fn main() {
	stage() or { eprintln(err); exit(1) }
}
