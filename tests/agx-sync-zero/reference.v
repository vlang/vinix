// SPDX-License-Identifier: GPL-2.0-or-later
import crypto.sha256
import os

fn run(program string, args []string) !string {
	mut process := os.new_process(program)
	process.set_args(args)
	process.set_redirect_stdio_merged()
	process.run()
	output := process.stdout_slurp()
	process.wait()
	code := process.code
	process.close()
	if code != 0 { return error('${program}: ${code}: ${output}') }
	return output
}

fn main() {
	assert os.args.len == 3, 'usage: reference PINNED_LINUX FRESH_EXTERNAL_STATE'
	reference := os.abs_path(os.args[1])
	state := os.abs_path(os.args[2])
	assert !os.exists(state) && !state.starts_with(os.getwd() + '/')
	assert run('git', ['-C', reference, 'rev-parse', 'HEAD'])!.trim_space() ==
		'bed544bdf93a496ebf70ba180923bab12b6e01cf'
	os.mkdir_all(state)!
	for path in ['drivers/dma-buf/dma-fence-chain.c', 'rust/kernel/dma_fence.rs',
		'drivers/gpu/drm/asahi/file.rs'] {
		bytes := os.read_bytes(reference + '/' + path)!
		committed := run('git', ['-C', reference, 'show', 'HEAD:' + path])!
		assert sha256.sum(bytes) == sha256.sum(committed.bytes()), 'dirty reference: ' + path
		os.mkdir_all(os.dir(state + '/' + path))!
		os.write_file_array(state + '/' + path, bytes)!
		println(path + ' sha256 ' + sha256.sum(bytes).hex())
	}
	source := os.read_file(state + '/drivers/dma-buf/dma-fence-chain.c')!
	start := source.index('int dma_fence_chain_find_seqno(') or { panic('reference function missing') }
	end := source.index_after('\n}\n', start) or { panic('reference function end missing') }
	// Compile the unchanged upstream function. Nonzero-only helpers abort so
	// the oracle also proves that seqno zero neither walks nor puts a fence.
	oracle := '#include <assert.h>\n#include <errno.h>\n#include <stdint.h>\n#include <stdlib.h>\n' +
		'struct dma_fence { uint64_t context, seqno; };\n' +
		'struct dma_fence_chain { struct dma_fence base; uint64_t prev_seqno; };\n' +
		'static struct dma_fence_chain *to_dma_fence_chain(struct dma_fence *f) { (void)f; abort(); }\n' +
		'static void dma_fence_put(struct dma_fence *f) { (void)f; abort(); }\n' +
		'#define dma_fence_chain_for_each(iter, head) for ((iter) = (head); (iter); (iter) = NULL)\n' +
		source[start..end + 3] +
		'int main(void) { struct dma_fence f[3] = {{0, 0}, {17, 19}, {UINT64_MAX, UINT64_MAX}};\n' +
		'for (int n = 0; n < 1000; n++) { for (int i = 0; i < 4; i++) {\n' +
		'struct dma_fence *before = i == 3 ? NULL : &f[i]; struct dma_fence *p = before;\n' +
		'assert(dma_fence_chain_find_seqno(&p, 0) == 0); assert(p == before);\n} }\nreturn 0;\n}\n'
	os.write_file(state + '/oracle.c', oracle)!
	_ = run('cc', ['-std=c11', '-Wall', '-Wextra', '-Werror', '-fsanitize=address,undefined',
		'-fno-omit-frame-pointer', state + '/oracle.c', '-o', state + '/oracle'])!
	_ = run(state + '/oracle', [])!
	// The Rust wrapper converts the unchanged non-NULL pointer back to Some.
	// Keep its full source for inspection; this is not a compiled Rust oracle.
	rust := os.read_file(state + '/rust/kernel/dma_fence.rs')!
	assert rust.contains('bindings::dma_fence_chain_find_seqno(&mut ptr, seqno)')
	assert rust.contains('Ok(Some(unsafe { Fence::from_raw(ptr) }))')
	println('Pinned upstream C oracle: 4000 zero-point calls preserve the pointer without walking or releasing it; Rust wrapper source retained.')
}
