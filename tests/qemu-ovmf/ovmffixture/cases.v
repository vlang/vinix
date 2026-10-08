// SPDX-License-Identifier: GPL-2.0-only
module ovmffixture

import fixturehost
import os

pub fn run_case(name string) ! {
	check(name in case_names, 'unknown original case ' + name)!
	mut c := context(name)!
	defer { c.retire() or { panic(err) } }
	match name {
		'test_explicit_toolchain_takes_precedence_and_normalizes_prefix' {
			c.prepare_toolchain()!
			c.isolate_path()!
			compiler_bin := c.checkout + '/explicit-llvm/bin'
			for tool in ['clang', 'llvm-ar', 'llvm-objcopy', 'ld.lld'] {
				os.rm(c.commands + '/' + tool)!
				write_command(compiler_bin + '/' + tool, 'exit 0\n')!
			}
			write_command(c.commands + '/brew', 'echo /unavailable/homebrew\n')!
			for suffix in ['', '/'] {
				c.environment['CLANGDWARF_BIN'] = compiler_bin + suffix
				toolchain(c.builder()!, compiler_bin + '/clang', compiler_bin + '/ld.lld')!
			}
		}
		'test_missing_llvm_tools_stop_before_basetools' {
			fixturehost.write(c.driver, upstream)!
			c.isolate_path()!
			for tool in ['clang', 'llvm-ar', 'llvm-objcopy'] {
				executable := c.commands + '/' + tool
				os.rm(executable)!
				result := c.builder()!
				check(result.code == 1, result.stdout + result.stderr)!
				check(result.stderr.contains(tool), result.stderr)!
				check(result.stderr.contains('brew install llvm lld'), result.stderr)!
				check(!result.stdout.contains('Building edk2 BaseTools'), result.stdout)!
				write_command(executable, 'exit 0\n')!
			}
		}
		'test_missing_lld_reports_install_command_before_basetools' {
			fixturehost.write(c.driver, upstream)!
			c.isolate_path()!
			os.rm(c.commands + '/ld.lld')!
			result := c.builder()!
			check(result.code == 1, result.stdout + result.stderr)!
			check(result.stderr.contains('ld.lld'), result.stderr)!
			check(result.stderr.contains('brew install llvm lld'), result.stderr)!
			check(!result.stdout.contains('Building edk2 BaseTools'), result.stdout)!
		}
		'test_separate_lld_on_path_is_available_to_build' {
			c.prepare_toolchain()!
			c.isolate_path()!
			os.rm(c.commands + '/ld.lld')!
			linker_bin := c.checkout + '/linker-bin'
			write_command(linker_bin + '/ld.lld', 'exit 0\n')!
			c.environment['PATH'] += ':' + linker_bin
			toolchain(c.builder()!, c.commands + '/clang', linker_bin + '/ld.lld')!
		}
		'test_homebrew_discovers_llvm_and_separate_keg_only_lld' {
			c.prepare_toolchain()!
			c.isolate_path()!
			c.environment.delete('CLANGDWARF_BIN')
			llvm_prefix := c.checkout + '/homebrew/opt/llvm'
			lld_prefix := c.checkout + '/homebrew/opt/lld'
			for tool in ['clang', 'llvm-ar', 'llvm-objcopy'] {
				os.rm(c.commands + '/' + tool)!
				write_command(llvm_prefix + '/bin/' + tool, 'exit 0\n')!
			}
			os.rm(c.commands + '/ld.lld')!
			write_command(lld_prefix + '/bin/ld.lld', 'exit 0\n')!
			write_command(c.commands + '/brew', '\ncase "$*" in\n    \'--prefix llvm\') echo \'' + llvm_prefix + '\' ;;\n    \'--prefix lld\') echo \'' + lld_prefix + '\' ;;\n    *) exit 1 ;;\nesac\n')!
			toolchain(c.builder()!, llvm_prefix + '/bin/clang', lld_prefix + '/bin/ld.lld')!
		}
		'test_fresh_and_already_patched_checkouts' {
			for newline in ['\n', '\r\n'] {
				fixturehost.write(c.driver, upstream.replace('\n', newline))!
				reached(c.builder()!)!
				patched := fixturehost.read(c.driver)!
				check(patched.count('2048, // HorizontalResolution') == 1, patched)!
				check(patched.count('1536, // VerticalResolution') == 1, patched)!
				rerun := c.builder()!
				reached(rerun)!
				check(rerun.stdout.contains('patch is already applied'), rerun.stdout)!
				check(fixturehost.read(c.driver)! == patched, 'patched bytes changed')!
			}
		}
		'test_fresh_bootstrap_fetches_shallow_direct_submodules_only' {
			dependency := c.prepare_bootstrap()!
			reached(c.builder()!)!
			check(fixturehost.read(dependency + '/README')! == 'required first-level source\n', 'dependency readme')!
			for repository in [c.source, dependency] {
				check(c.git(repository, ['rev-parse', '--is-shallow-repository'])! == 'true', 'clone lost shallow depth')!
			}
			check(!os.exists(dependency + '/unused-tests/.git'), 'fetched unused recursive dependency')!
		}
		'test_existing_checkout_recovers_missing_submodules' {
			dependency := c.prepare_bootstrap()!
			c.git(c.checkout, ['clone', '--depth', '1', '--branch', 'edk2-stable202511', 'https://github.com/tianocore/edk2.git', c.source])!
			check(!os.exists(dependency + '/README'), 'unexpected initialized dependency')!
			reached(c.builder()!)!
			check(os.exists(dependency + '/README'), 'dependency did not recover')!
			check(!os.exists(dependency + '/unused-tests/.git'), 'fetched unused recursive dependency')!
		}
		'test_incomplete_mode_is_rejected' {
			fixturehost.write(c.driver, upstream)!
			reached(c.builder()!)!
			incomplete := fixturehost.read(c.driver)!.replace('1536, // VerticalResolution', '1535, // VerticalResolution')
			fixturehost.write(c.driver, incomplete)!
			rejected(c.builder()!)!
			check(fixturehost.read(c.driver)! == incomplete, 'rejected bytes changed')!
		}
		'test_incompatible_source_reports_git_diagnostic' {
			incompatible := upstream.replace('1024, // HorizontalResolution', '1280, // HorizontalResolution')
			fixturehost.write(c.driver, incompatible)!
			rejected(c.builder()!)!
			check(fixturehost.read(c.driver)! == incompatible, 'rejected bytes changed')!
		}
		'test_setup_accepts_unset_variables_and_restores_strict_mode' {
			c.prepare_setup(setup_optional)!
			result := c.builder()!
			check(result.code == sentinel, result.stdout + result.stderr)!
			check(result.stdout.contains('Building the AArch64 2048x1536 ramfb driver'), result.stdout)!
			check(result.stdout.contains('test: ramfb build -a AARCH64 -b RELEASE -t CLANGDWARF -p ArmVirtPkg/ArmVirtQemu.dsc -m OvmfPkg/QemuRamfbDxe/QemuRamfbDxe.inf -n 2'), result.stdout)!
		}
		'test_setup_failure_stops_before_driver_build' {
			c.prepare_setup(setup_failure)!
			result := c.builder()!
			check(result.code == 61, result.stdout + result.stderr)!
			check(result.stderr.contains('test: setup failed'), result.stderr)!
			check(!result.stdout.contains('test: unexpected ramfb build'), result.stdout)!
		}
		else { return error('Unknown original firmware case') }
	}
	c.save_observations(name)!
}
