import crypto.sha256
import json2
import os

struct DedupRecord {
	path string
	canonical string
	sha256 string
	bytes u64
	action string
}

fn read_chunk(mut file os.File, mut buffer []u8) !int {
	return file.read(mut buffer) or {
		if err is os.Eof { return 0 }
		return err
	}
}

fn digest(path string) !string {
	mut file := os.open(path)!
	defer { file.close() }
	mut hash := sha256.new()
	mut buffer := []u8{len: 1024 * 1024}
	for {
		n := read_chunk(mut file, mut buffer)!
		if n == 0 { break }
		hash.write(buffer[..n])!
	}
	return hash.sum([]u8{}).hex()
}

fn identical(left string, right string) !bool {
	mut a := os.open(left)!
	defer { a.close() }
	mut b := os.open(right)!
	defer { b.close() }
	mut x := []u8{len: 1024 * 1024}
	mut y := []u8{len: 1024 * 1024}
	for {
		na := read_chunk(mut a, mut x)!
		nb := read_chunk(mut b, mut y)!
		if na != nb { return false }
		if na == 0 { return true }
		if x[..na] != y[..nb] { return false }
	}
	return true
}

fn main() {
	area := '/Users/alex/.cache/vinix-linux-compat/procns-resume-20261022'
	mut records := []DedupRecord{}
	mut canonicals := map[string]string{}
	mut logical_saved := u64(0)
	for group in ['states/final-before-arm', 'states/final-after-arm', 'states/final-before-x86', 'states/final-after-x86', 'states/final2-before-arm', 'states/final2-after-arm', 'states/final2-before-x86', 'states/final2-after-x86', 'states/final3-before-x86', 'states/final3-after-x86', 'ra', 'rx', 'rp', 'regressions-arm', 'regressions-x86', 'regressions-arm-plain', 'regressions-x86-plain'] {
		mut files := os.walk_ext(area + '/' + group, '')
		files.sort()
		for path in files {
			if os.is_link(path) || !os.is_file(path) || os.file_size(path) < 1024 * 1024 { continue }
			info := os.inode(path)
			hash := digest(path)!
			key := '${info.size}:${info.bitmask()}:${hash}'
			if key !in canonicals {
				canonicals[key] = path
				records << DedupRecord{path: path, canonical: path, sha256: hash, bytes: info.size, action: 'retained canonical'}
				continue
			}
			canonical := canonicals[key]
			if !identical(canonical, path)! { panic('SHA match but byte mismatch') }
			temporary := path + '.dedup-link'
			if os.exists(temporary) { panic('unexpected dedup temporary: ' + temporary) }
			os.link(canonical, temporary)!
			os.rename(temporary, path)!
			if digest(path)! != hash { panic('post-link hash mismatch') }
			logical_saved += info.size
			records << DedupRecord{path: path, canonical: canonical, sha256: hash, bytes: info.size, action: 'verified SHA256 and byte equality, replaced atomically with hardlink'}
			os.write_file(area + '/native-dedup-records.json', json2.encode(records, prettify: true) + '\n')!
			println('hardlinked ${info.size} bytes: ${path} -> ${canonical}')
		}
	}
	os.write_file(area + '/native-dedup-records.json', json2.encode(records, prettify: true) + '\n')!
	println('Logical duplicate bytes linked: ${logical_saved}; APFS physical recovery may differ where clones already shared extents. Every file path and byte retained.')
}
