import os
import json2
import crypto.sha256
fn hash(path string) !string { return sha256.sum(os.read_bytes(path)!).hex() }
fn main() {
	root := '/Users/alex/code/vinix-maps-priority'
	assert os.read_file(root+'/kernel/netcore/core.v')! == os.read_file('kernel/netcore/core.v')!
	base := os.exec(['git','-C',root,'show','HEAD:kernel/c/lwipopts.h'])
	assert base.exit_code == 0
	assert os.read_file(root+'/kernel/c/lwipopts.h')! in [base.output, os.read_file('kernel/c/lwipopts.h')!]
	os.cp('kernel/c/lwipopts.h',root+'/kernel/c/lwipopts.h')!
	mut receipt := map[string]json2.Any{}
	receipt['worktree_base_commit'] = os.exec(['git','-C',root,'rev-parse','HEAD']).output.trim_space()
	receipt['compiler'] = os.exec(['/Users/alex/code/v/v_old','version']).output.trim_space()
	receipt['compiler_sha256'] = hash('/Users/alex/code/v/v_old')!
	for arch in ['aarch64','x86_64'] {
		// The baseline makefile shares C objects between architectures.
		os.rmdir_all(root+'/kernel/obj')!
		out := 'build/android-maps/arp-kernel-'+arch
		os.mkdir_all(out+'/bin')!
		r := os.exec(['make','-C',root+'/kernel','-j4','ARCH='+arch,'V=/Users/alex/code/v/v_old','LD_X86_64=/opt/homebrew/bin/ld.lld'])
		os.write_file(out+'/build.log',r.output)!
		assert r.exit_code == 0,r.output
		os.cp(root+'/kernel/bin/vinix',out+'/bin/vinix')!
		os.write_file(out+'/source.patch',os.exec(['git','-C',root,'diff','--','kernel']).output)!
		mut row := map[string]json2.Any{}
		for name,path in {'kernel':out+'/bin/vinix','generated_c':root+'/kernel/obj/blob.c','source_patch':out+'/source.patch','build_log':out+'/build.log','lwipopts':root+'/kernel/c/lwipopts.h'} {
			row[name+'_sha256'] = hash(path)!
		}
		receipt[arch] = json2.Any(row)
		os.write_file('build/android-maps/arp-kernels.json',json2.encode(receipt,prettify:true)+'\n')!
		println('ARP-KERNEL '+arch+' '+row['kernel_sha256']!.str())
	}
}
