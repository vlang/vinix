import os

fn section(source string, start string, end string) !string {
	begin := source.index(start) or { return error('missing ' + start) }
	finish := source.index_after(end, begin + start.len) or { return error('missing ' + end) }
	return source[begin..finish]
}

fn main() {
	os.setenv('V_C_ERROR_BUG_REPORT_DISABLED', '1', true)
	mut overlays := map[string]string{}
	mut index := 1
	for index < os.args.len {
		key := os.args[index]
		assert key in ['--gem-source', '--bo-source', '--ram-source'] && index + 1 < os.args.len
		overlays[key] = os.args[index + 1]; index += 2
	}
	repo := os.real_path(os.join_path(os.dir(@FILE), '../..'))
	scratch := os.join_path(os.temp_dir(), 'vinix-agx-cpu-cache-${os.getpid()}')
	os.mkdir_all(scratch)!
	defer { os.rmdir_all(scratch) or { panic(err) } }
	os.cp_all(repo + '/tests/agx-cpu-cache/fixture', scratch, false)!
	os.cp_all(repo + '/tests/agx-file-close/fixture/klock', scratch + '/klock', false)!
	os.cp_all(repo + '/tests/agx-file-close/fixture/memory/mmap', scratch + '/memory/mmap', false)!
	os.mkdir_all(scratch + '/gpu/agx/bo')!
	os.cp(overlays['--bo-source'] or { repo + '/kernel/gpu/agx/bo/bo.v' }, scratch + '/gpu/agx/bo/bo.v')!
	os.cp(overlays['--gem-source'] or { repo + '/kernel/drm/gem/gem.v' }, scratch + '/drm/gem/gem.v')!
	os.cp(overlays['--ram-source'] or { repo + '/kernel/memory/ram_cache_arm64.v' }, scratch + '/memory/ram_cache.v')!
	drm := os.read_file(repo + '/kernel/drm/drm.v')!
	os.write_file(scratch + '/drm/prime.v', 'module drm\nimport memory.mmap\n' +
		section(drm, 'fn (mut this GemPrimeResource) mapping_attributes(', 'fn (mut this GemPrimeResource) read(')!)!
	virtual := os.read_file(repo + '/kernel/memory/virtual_arm64.v')!
	os.write_file(scratch + '/memory/bbm.v', 'module memory\nimport aarch64.cpu\n' +
		section(virtual, 'fn install_arm64_pte(', 'pub fn (mut pagemap Pagemap) map_page(')!)!
	cache := os.read_file(repo + '/kernel/aarch64/cpu/data_cache.v')!
	start := cache.index('pub fn clean_invalidate_data_cache_to_poc(') or { panic('cache range loop') }
	os.write_file(scratch + '/aarch64/cpu/range.v', 'module cpu\n' + cache[start..])!
	os.cp(repo + '/tests/agx-cpu-cache/test.v', scratch + '/main.v')!
	mut flags := ['-nocache', '-no-parallel', '-cc', 'cc', '-enable-globals', '-gc', 'none',
		'-path', '${scratch}|@vlib|@vmodules', '-cflags', '-fsanitize=address,undefined -fno-omit-frame-pointer',
		'-ldflags', '-fsanitize=address,undefined', '-o', scratch + '/test', scratch + '/main.v']
	mut build := os.new_process(os.getenv_opt('V') or { 'v' })
	build.set_args(flags); build.run(); build.wait()
	if build.code != 0 { exit(build.code) }
	if output := os.getenv_opt('AGX_CPU_CACHE_C') {
		assert output.ends_with('.c')
		flags[flags.len - 2] = output
		mut c := os.new_process(os.getenv_opt('V') or { 'v' })
		c.set_args(flags); c.run(); c.wait()
		if c.code != 0 { exit(c.code) }
	}
	if output := os.getenv_opt('AGX_CPU_CACHE_BINARY') { os.cp(scratch + '/test', output)! }
	mut check := os.new_process(scratch + '/test')
	check.run(); check.wait(); exit(check.code)
}
