// SPDX-License-Identifier: MIT
module n64build

import androidhost as ah

fn patch(source string) ! {
	memory := join(source, 'mupen64plus-core/src/device/memory/m64p_memory.c')!
	data := method(memory, 'read_text', [], {})!
	first := method(data, 'index', [v(ah.Value('void* init_mem_base(void)'))], {})!
	last := method(data, 'index', [v(ah.Value('void release_mem_base')), o(first)], {})!
	prefix := slice(data, null()!, first)!
	suffix := slice(data, last, null()!)!
	replacement := call('operator.add', o(call('operator.add', o(prefix), v(ah.Value('/* Vinix uses the upstream compact mapping: 76 MiB rather than 512 MiB.\n * No JIT or external-memory GPU backend needs a full physical-address map. */\nvoid* init_mem_base(void)\n{\n    void* mem_base = malloc(MB_MAX_SIZE);\n    if (mem_base != NULL) SET_MEM_BASE_MODE(mem_base);\n    return mem_base;\n}\n\n')))!), o(suffix))!
	method(memory, 'write_text', [o(replacement)], {})!
	public('replace', [
		join(source, 'mupen64plus-core/src/device/r4300/pure_interp.c')!,
		lit('void InterpretOpcode(struct r4300_core* r4300)\n{')!,
		lit('void InterpretOpcode(struct r4300_core* r4300)\n{\n    if (vinix_n64_cpu_budget && !--vinix_n64_cpu_budget) {\n        vinix_n64_budget_exhausted(); return;\n    }')!,
	], {})!
	public('replace', [join(source, 'mupen64plus-rsp-cxd4/su.c')!,
		lit('EX:\n#endif\n#ifdef SP_EXECUTE_LOG')!,
		lit('EX:\n#endif\n        if (vinix_n64_rsp_budget && !--vinix_n64_rsp_budget) {\n            vinix_n64_budget_exhausted(); goto RSP_halted_CPU_exit_point;\n        }\n#ifdef SP_EXECUTE_LOG')!], {})!
	public('replace', [join(source, 'libretro/libretro.c')!,
		lit('   format_disk(saved_memory.disk);')!, lit('   /* Vinix: no 64DD disk. */')!], {})!
	public('replace', [join(source, 'libretro/libretro.c')!, lit('#include <glsm/glsm.h>')!,
		lit('#if defined(HAVE_OPENGL) || defined(HAVE_OPENGLES)\n#include <glsm/glsm.h>\n#else\nenum glsm_state_ctl { GLSM_CTL_STATE_CONTEXT_DESTROY };\n#endif')!], {})!
	public('replace', [join(source, 'libretro-common/vfs/vfs_implementation.c')!,
		lit('#if defined(__linux__)\n#include <linux/falloc.h>')!,
		lit('#if defined(__linux__) && !defined(VINIX_NO_FALLOC)\n#include <linux/falloc.h>')!], {})!
	public('replace', [join(source, 'mupen64plus-core/src/device/r4300/r4300.h')!,
		lit('#if !defined(__arm64__) && !defined(__aarch64__)')!,
		lit('#if (!defined(__arm64__) && !defined(__aarch64__)) || !defined(NEW_DYNAREC)')!], {})!
	public('replace', [
		join(source, 'mupen64plus-core/src/device/r4300/pure_interp.c')!,
		lit('   static int l_pi_started = 0;')!,
		lit('   extern int vinix_n64_pi_started;\n#define l_pi_started vinix_n64_pi_started')!,
	], {})!
	public('replace', [join(source, 'mupen64plus-core/src/main/main.c')!,
		lit('    static int l_setup_done = 0;')!,
		lit('    extern int vinix_n64_setup_done;\n#define l_setup_done vinix_n64_setup_done')!], {})!
	public('replace', [join(source, 'libretro/libretro.c')!,
		lit('    first_time = 1;\n\n    EmuThreadStep();')!,
		lit('    first_time = 1;\n\n    /* Vinix closes devices between frame slices; do not execute another frame. */')!], {})!
}
