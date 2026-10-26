module main

import crypto.sha256
import json2
import os
import strings
import time

#include <errno.h>
#include <fcntl.h>
#include <signal.h>
#include <sys/stat.h>
#include <sys/wait.h>
#define wine_estimate_waitpid waitpid
#define wine_estimate_read read
#define st_mtimensec st_mtimespec.tv_nsec
#define st_ctimensec st_ctimespec.tv_nsec

fn C.wine_estimate_waitpid(i32, &i32, i32) i32
fn C.wine_estimate_read(i32, voidptr, usize) isize

// Estimate only. This program has no archive-writing or removal operation.
const parent = '/Users/alex/Library/Caches/vinix-codex/section14'
const bundle_name = 'wine-source-2026-10-26'
const root = parent + '/' + bundle_name
const output = parent + '/wine-source-archive-estimate-01'
const checker = parent + '/wine-source-tools-2026-10-26/verify-seal'
const checker_source = parent + '/wine-source-tools-2026-10-26/verify-seal.v'
const manifest_hash = '62e077c7dcf05ff60b81b8ddc1303b1d8f867b73b93a27d7a47534cd570eab54'
const checker_hash = 'da18064873d8ce74526bbe9928e403c8bee58f38b509ccae48d9c22df01e55cc'
const checker_source_hash = '6fef256816a692ca962090657b238f33bd6bde68d44c748c25eeaf69915054e3'

struct Node {
	path       string
	kind       string
	dev        i32
	inode      u64
	links      u16
	mode       u16
	uid        u32
	gid        u32
	size       i64
	blocks     i64
	mtime      i64
	mtime_nsec i64
	ctime      i64
	ctime_nsec i64
	target     string
}

struct Inode {
	links  u16
	size   i64
	blocks i64
mut:
	names int
}

struct Summary {
	regular_names                 int
	directories                   int
	symlinks                      int
	unique_regular_inodes         int
	logical_bytes                 u64
	unique_inode_bytes            u64
	unique_inode_block_bytes      u64
	all_links_inside_inodes       int
	all_links_inside_block_bytes  u64
	externally_linked_inodes      int
	externally_linked_block_bytes u64
}

struct Run {
	executable           string
	argv                 []string
	environment          map[string]string
	raw_wait_status      i32
	stdout_bytes         u64
	stdout_sha256        string
	stdout_text          string
	stderr_text          string
	elapsed_milliseconds i64
}

fn sha(path string) !string {
	before := os.lstat(path)!
	if before.get_filetype() != .regular { return error('requires ordinary file: ' + path) }
	mut file := os.open(path)!
	defer { file.close() }
	mut hash := sha256.new()
	mut buffer := []u8{len: 65536}
	for {
		n := file.read(mut buffer) or {
			if err is os.Eof { break }
			return err
		}
		if n == 0 { break }
		hash.write(buffer[..n])!
	}
	after := os.lstat(path)!
	if before.dev != after.dev || before.inode != after.inode || before.size != after.size
		|| before.mtime != after.mtime || after.get_filetype() != .regular {
		return error('ordinary input changed while hashing: ' + path)
	}
	return hash.sum([]u8{}).hex()
}

fn pin(path string, expected string, mut pins map[string]string) ! {
	value := sha(path)!
	if expected != '' && value != expected { return error('reviewed input differs: ' + path) }
	pins[path] = value
}

fn node(path string, relative string) !Node {
	mut st := C.stat{}
	if C.lstat(path.str, &st) != 0 { return error('lstat failed: ' + path) }
	mode := st.st_mode & 0xf000
	kind := if mode == 0x8000 {
		'file'
	} else if mode == 0x4000 {
		'dir'
	} else if mode == 0xa000 {
		'link'
	} else {
		return error('unexpected special node: ' + path)
	}
	if relative.contains('\t') || relative.contains('\n') { return error('unrepresentable name') }
	target := if kind == 'link' { os.readlink(path)! } else { '' }
	if target.contains('\t') || target.contains('\n') { return error('unrepresentable target') }
	return Node{relative, kind, st.st_dev, st.st_ino, st.st_nlink, st.st_mode, st.st_uid, st.st_gid, st.st_size, st.st_blocks, st.st_mtime, st.st_mtimensec, st.st_ctime, st.st_ctimensec, target}
}

fn walk(path string, relative string, mut rows []Node) ! {
	if rows.len >= 50000 { return error('inventory bound exceeded') }
	row := node(path, relative)!
	rows << row
	if row.kind != 'dir' { return }
	mut names := os.ls(path)!
	names.sort()
	for name in names {
		walk(path + '/' + name, if relative == '.' { name } else { relative + '/' + name }, mut rows)!
	}
}

fn inventory() ![]Node {
	if os.real_path(root) != root { return error('root is not canonical') }
	mut rows := []Node{}
	walk(root, '.', mut rows)!
	if rows[0].kind != 'dir' { return error('root is not an ordinary directory') }
	return rows
}

fn inventory_text(rows []Node) !string {
	mut text := strings.new_builder(2 * 1024 * 1024)
	text.writeln('path\tkind\tdev\tinode\tnlink\tmode\tuid\tgid\tsize\tblocks512\tmtime\tmtime_nsec\tctime\tctime_nsec\tliteral_target')
	for row in rows {
		text.writeln('${row.path}\t${row.kind}\t${row.dev}\t${row.inode}\t${row.links}\t${row.mode}\t${row.uid}\t${row.gid}\t${row.size}\t${row.blocks}\t${row.mtime}\t${row.mtime_nsec}\t${row.ctime}\t${row.ctime_nsec}\t${row.target}')
		if text.len > 7 * 1024 * 1024 { return error('inventory text bound exceeded') }
	}
	return text.str()
}

fn summarize(rows []Node) !Summary {
	mut inodes := map[string]Inode{}
	mut regular := 0
	mut directories := 0
	mut links := 0
	mut logical := u64(0)
	for row in rows {
		if row.kind == 'dir' {
			directories++
			continue
		}
		if row.kind == 'link' {
			links++
			continue
		}
		if row.size < 0 || row.blocks < 0 { return error('negative size/block count') }
		regular++
		logical += u64(row.size)
		key := '${row.dev}:${row.inode}'
		if key in inodes {
			mut old := inodes[key]
			if old.links != row.links || old.size != row.size || old.blocks != row.blocks {
				return error('hardlink identity metadata disagrees')
			}
			old.names++
			inodes[key] = old
		} else {
			inodes[key] = Inode{row.links, row.size, row.blocks, 1}
		}
	}
	mut unique_bytes := u64(0)
	mut block_bytes := u64(0)
	mut inside := 0
	mut inside_blocks := u64(0)
	mut external := 0
	mut external_blocks := u64(0)
	for _, inode in inodes {
		if inode.names > int(inode.links) { return error('more names than recorded links') }
		unique_bytes += u64(inode.size)
		block_bytes += u64(inode.blocks) * 512
		if inode.names == int(inode.links) {
			inside++
			inside_blocks += u64(inode.blocks) * 512
		} else {
			external++
			external_blocks += u64(inode.blocks) * 512
		}
	}
	return Summary{regular, directories, links, inodes.len, logical, unique_bytes, block_bytes, inside, inside_blocks, external, external_blocks}
}

fn nonblocking(fd i32) ! {
	flags := C.fcntl(fd, C.F_GETFL, 0)
	if flags < 0 || C.fcntl(fd, C.F_SETFL, flags | C.O_NONBLOCK) < 0
		|| C.fcntl(fd, C.F_GETFL, 0) & C.O_NONBLOCK == 0 {
		return error('nonblocking pipe setup failed')
	}
}

fn run(executable string, argv []string, discard bool) !Run {
	env := {
		'PATH':             '/usr/bin:/bin'
		'HOME':             '/Users/alex'
		'LC_ALL':           'C'
		'LANG':             'C'
		'COPYFILE_DISABLE': '1'
	}
	mut child := os.new_process(executable)
	defer { child.close() }
	child.set_args(argv)
	child.set_environment(env)
	child.set_redirect_stdio()
	child.run()
	if child.pid <= 0 || child.status != .running { return error('spawn failed: ' + executable) }
	mut retired := false
	defer {
		if !retired {
			C.kill(i32(child.pid), C.SIGKILL)
			mut status := i32(0)
			for {
				result := C.wine_estimate_waitpid(i32(child.pid), &status, 0)
				if result >= 0 || C.errno != C.EINTR { break }
			}
			child.status = .exited
		}
	}
	C.close(i32(child.stdio_fd[0]))
	child.stdio_fd[0] = -1
	nonblocking(i32(child.stdio_fd[1]))!
	nonblocking(i32(child.stdio_fd[2]))!
	mut sink := os.open_file('/dev/null', 'w')!
	defer { sink.close() }
	mut hash := sha256.new()
	mut buffer := []u8{len: 65536}
	mut stdout := strings.new_builder(4096)
	mut stderr := strings.new_builder(4096)
	mut count := u64(0)
	mut eof := [false, false]!
	mut status := i32(0)
	started := time.sys_mono_now()
	for {
		if time.sys_mono_now() - started > u64(600 * time.second) {
			return error('child exceeded 600-second deadline')
		}
		mut progress := false
		for index in 0 .. 2 {
			if eof[index] { continue }
			n := C.wine_estimate_read(i32(child.stdio_fd[index + 1]), buffer.data, usize(buffer.len))
			if n == 0 {
				eof[index] = true
				continue
			}
			if n < 0 {
				if C.errno == C.EINTR || C.errno == C.EAGAIN { continue }
				return error('child pipe read failed')
			}
			progress = true
			bytes := unsafe { buffer[..int(n)] }
			if index == 0 {
				count += u64(n)
				if count > u64(8) * 1024 * 1024 * 1024 {
					return error('stdout byte bound exceeded')
				}
				hash.write(bytes)!
				if discard {
					if sink.write(bytes)! != bytes.len { return error('short /dev/null write') }
				} else {
					if count > 16384 { return error('checker stdout bound exceeded') }
					stdout.write(bytes)!
				}
			} else {
				if stderr.len + int(n) > 1024 * 1024 { return error('stderr bound exceeded') }
				stderr.write(bytes)!
			}
		}
		if !retired {
			result := C.wine_estimate_waitpid(i32(child.pid), &status, C.WNOHANG)
			if result == i32(child.pid) {
				retired = true
				child.status = .exited
			} else if result < 0 && C.errno != C.EINTR {
				return error('waitpid failed')
			}
		}
		if retired && eof[0] && eof[1] { break }
		if !progress { time.sleep(time.millisecond) }
	}
	receipt := Run{executable, argv, env, status, count, hash.sum([]u8{}).hex(), stdout.str(), stderr.str(), i64((time.sys_mono_now() - started) / u64(time.millisecond))}
	if status != 0 { return error('child raw wait status ${status}: ' + receipt.stderr_text) }
	return receipt
}

fn check(label string) ! {
	result := run(checker, []string{}, false)!
	os.write_file(output + '/' + label + '.json', json2.encode(result))!
	if result.stdout_text != 'Verified ordinary files: 12305\nVerified symbolic links and special objects: 5\nSHA256SUMS sha256: ' + manifest_hash + '\n' || result.stderr_text != '' {
		return error('original checker receipt differs')
	}
}

fn estimate() ! {
	if os.exists(output) || os.is_link(output) { return error('output already exists') }
	os.mkdir(output)!
	mut pins := map[string]string{}
	pin(checker, checker_hash, mut pins)!
	pin(checker_source, checker_source_hash, mut pins)!
	pin(root + '/SHA256SUMS', manifest_hash, mut pins)!
	pin(root + '/objects.json', 'fd04ab1b6c4118b49069aacb7d71d0682898435d1c54e04082bccfc41c55abf9', mut pins)!
	pin(root + '/capture-report.json', '154c03524bfd87d49f82a306b746a6937c5cd056eb1641cb216bef9167cfdbc2', mut pins)!
	pin('/usr/bin/bsdtar', '', mut pins)!
	pin(os.executable(), '', mut pins)!
	pin(@FILE, '', mut pins)!
	check('original-before')!
	before := inventory()!
	text := inventory_text(before)!
	os.write_file(output + '/inventory.tsv', text)!
	summary := summarize(before)!
	if summary.regular_names != 12306 || summary.symlinks != 5 {
		return error('inventory counts differ')
	}
	os.write_file(output + '/summary.json', json2.encode(summary))!
	os.write_file(output + '/pins.json', json2.encode(pins))!
	// This is the complete, unchanged root. It includes its original manifest.
	// A future wrapper manifest adds a small separately budgeted overhead.
	argv := ['--format=pax', '--no-xattrs', '--no-acls', '--no-fflags', '-czf', '-', '-C', parent,
		bundle_name]
	result := run('/usr/bin/bsdtar', argv, true)!
	os.write_file(output + '/stream-count.json', json2.encode(result))!
	after := inventory()!
	if before != after { return error('root metadata/inode inventory changed') }
	check('original-after')!
	for path, expected in pins {
		if sha(path)! != expected { return error('selected input changed: ' + path) }
	}
	os.write_file(output + '/completed.json', json2.encode({
		'scope':                 'raw-complete-root-compressed-estimate-only'
		'inventory_sha256':      sha(output + '/inventory.tsv')!
		'summary_sha256':        sha(output + '/summary.json')!
		'stream_receipt_sha256': sha(output + '/stream-count.json')!
		'pins_sha256':           sha(output + '/pins.json')!
		'root':                  root
		'compressed_bytes':      result.stdout_bytes.str()
		'storage_limit':         '10 MiB observed output-state ceiling; not an enforced filesystem quota'
		'allocation_limit':      'st_blocks and nlink count ordinary inode ownership; APFS sharing/snapshots can reduce physical space recovered'
		'qualification_limit':   'no archive retained, no strict archive qualification, no removal; historical reruns require original absolute root restored'
	}))!
	println('PASS complete-root compressed estimate: ${result.stdout_bytes} bytes; no archive retained')
}

fn main() {
	if os.exists(output) || os.is_link(output) {
		eprintln('output already exists')
		exit(1)
	}
	estimate() or {
		if os.is_dir(output) { os.write_file(output + '/refused.txt', err.msg() + '\n') or {} }
		eprintln(err)
		exit(1)
	}
}
