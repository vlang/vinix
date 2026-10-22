import crypto.sha256
import json2
import os

struct Cleanup {
	path string
	bytes u64
	sha256 string
	archive string
	kernel string
	reason string
}

fn digest(path string) !string {
	return sha256.sum(os.read_bytes(path)!).hex()
}

fn main() {
	area := '/Users/alex/.cache/vinix-linux-compat/procns-resume-20261022'
	keep := area + '/du'
	kept := json2.decode[map[string]string](os.read_file(keep + '/receipt.json')!)!
	if digest(keep + '/vm/test.iso')! != kept['iso_sha256'] || digest(keep + '/initramfs.tar')! != kept['archive_sha256'] { panic('retained exact ISO/archive pin mismatch') }
	mut records := []Cleanup{}
	for group in ['desktop-x86', 'ds'] {
		work := area + '/' + group
		receipt := json2.decode[map[string]string](os.read_file(work + '/receipt.json')!)!
		path := work + '/vm/test.iso'
		hash := digest(path)!
		if hash != receipt['iso_sha256'] { panic('scratch ISO pin mismatch') }
		if digest(work + '/initramfs.tar')! != receipt['archive_sha256'] || digest(work + '/kernel/bin/vinix')! != receipt['kernel_sha256'] { panic('retained rebuild inputs do not match receipt') }
		records << Cleanup{path: path, bytes: os.file_size(path), sha256: hash, archive: work + '/initramfs.tar', kernel: work + '/kernel/bin/vinix', reason: 'Removed hashed reproducible VM scratch ISO to make disk space for queue-buffer followup. Retained all raw logs, receipts, ELF/source/archive inputs and du exact ISO/archive. Rebuild with desktop-iso.v; ISO creation timestamps may change.'}
		os.write_file(area + '/desktop-scratch-cleanup-records.json', json2.encode(records, prettify: true) + '\n')!
		os.rm(path)!
		println('Removed hashed scratch ISO ${path} sha256=${hash}')
	}
}
