// SPDX-License-Identifier: MIT
module emulatorbuild

import hosttest

fn replace_core(path string, before string, after string) ! {
	text := hosttest.module_read_text(path)!
	if text.count(before) != 1 { return error('pinned source patch did not match once: ' + path) }
	hosttest.module_write_text(path, text.replace(before, after))!
}

pub fn patch_n64(source string) ! {
	memory := source + '/mupen64plus-core/src/device/memory/m64p_memory.c'
	text := hosttest.module_read_text(memory)!
	first := text.index('void* init_mem_base(void)') or { return error('Missing memory patch start') }
	last := text[first..].index('void release_mem_base') or { return error('Missing memory patch end') }
	hosttest.module_write_text(memory, text[..first] + '/* Vinix uses the upstream compact mapping: 76 MiB rather than 512 MiB.\n * No JIT or external-memory GPU backend needs a full physical-address map. */\nvoid* init_mem_base(void)\n{\n    void* mem_base = malloc(MB_MAX_SIZE);\n    if (mem_base != NULL) SET_MEM_BASE_MODE(mem_base);\n    return mem_base;\n}\n\n' + text[first + last..])!
	replace_core(source + '/mupen64plus-core/src/device/r4300/pure_interp.c',
		'void InterpretOpcode(struct r4300_core* r4300)\n{',
		'void InterpretOpcode(struct r4300_core* r4300)\n{\n    if (vinix_n64_cpu_budget && !--vinix_n64_cpu_budget) {\n        vinix_n64_budget_exhausted(); return;\n    }')!
	replace_core(source + '/mupen64plus-rsp-cxd4/su.c', 'EX:\n#endif\n#ifdef SP_EXECUTE_LOG',
		'EX:\n#endif\n        if (vinix_n64_rsp_budget && !--vinix_n64_rsp_budget) {\n            vinix_n64_budget_exhausted(); goto RSP_halted_CPU_exit_point;\n        }\n#ifdef SP_EXECUTE_LOG')!
	replace_core(source + '/libretro/libretro.c', '   format_disk(saved_memory.disk);', '   /* Vinix: no 64DD disk. */')!
	replace_core(source + '/libretro/libretro.c', '#include <glsm/glsm.h>',
		'#if defined(HAVE_OPENGL) || defined(HAVE_OPENGLES)\n#include <glsm/glsm.h>\n#else\nenum glsm_state_ctl { GLSM_CTL_STATE_CONTEXT_DESTROY };\n#endif')!
	replace_core(source + '/libretro-common/vfs/vfs_implementation.c', '#if defined(__linux__)\n#include <linux/falloc.h>',
		'#if defined(__linux__) && !defined(VINIX_NO_FALLOC)\n#include <linux/falloc.h>')!
	replace_core(source + '/mupen64plus-core/src/device/r4300/r4300.h', '#if !defined(__arm64__) && !defined(__aarch64__)',
		'#if (!defined(__arm64__) && !defined(__aarch64__)) || !defined(NEW_DYNAREC)')!
	replace_core(source + '/mupen64plus-core/src/device/r4300/pure_interp.c', '   static int l_pi_started = 0;',
		'   extern int vinix_n64_pi_started;\n#define l_pi_started vinix_n64_pi_started')!
	replace_core(source + '/mupen64plus-core/src/main/main.c', '    static int l_setup_done = 0;',
		'    extern int vinix_n64_setup_done;\n#define l_setup_done vinix_n64_setup_done')!
	replace_core(source + '/libretro/libretro.c', '    first_time = 1;\n\n    EmuThreadStep();',
		'    first_time = 1;\n\n    /* Vinix closes devices between frame slices; do not execute another frame. */')!
}
