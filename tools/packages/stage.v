// SPDX-License-Identifier: GPL-2.0-or-later
module main

import json2
import os
import tools.packages.pkgcore

fn invoke(program string, arguments []string) ! {
	mut process := os.new_process(program)
	process.set_args(arguments)
	process.wait()
	code := process.code
	process.close()
	if code != 0 { return error('${program} failed (${code})') }
}

fn compile_image_tools(build &pkgcore.ImageToolBuild, architecture string, repository string, v string, cc string, compiler_args []string) ! {
	work := build.directory()!
	defer { unsafe { work.free() } }
	for pair in [['vinix-package', 'tools/packages/main.v'], ['vinix-session', 'tools/accounts/session.v'],
		['vinix-linux-runner', 'tools/packages/linux-runner.v']] {
		source := work + '/' + pair[0] + '.c'
		binary := work + '/' + pair[0]
		defer { unsafe { source.free(); binary.free() } }
		build.check()!
		invoke(v, ['-path', '@vlib|@vmodules|' + repository + '|' + repository + '/tools/accounts',
			'-enable-globals', '-gc', 'none', '-d', 'no_backtrace', '-d', 'no_segfault_handler', '-os', 'linux', '-arch',
			if architecture == 'aarch64' { 'arm64' } else { 'amd64' }, '-o', source, repository + '/' + pair[1]])!
		build.check()!
		invoke(cc, [...compiler_args[1..], '-static', '-O2', '-std=gnu11', '-D_GNU_SOURCE', source,
			'-o', binary, '-lm', '-lpthread'])!
		build.check()!
	}
	build.publish()!
}

fn stage() ! {
	mut architecture := ''
	mut staging := ''
	mut compiler := ''
	mut compiler_args := []string{}
	mut configuration := os.getenv('VINIX_PACKAGE_IMAGE_CONFIG')
	mut repositories := os.getenv('VINIX_PACKAGE_IMAGE_REPOSITORIES')
	mut check := false
	mut required_applications := []string{}
	mut applications := os.getenv('VINIX_PACKAGE_IMAGE_APPLICATIONS')
	mut applications_explicit := false
	mut deployment_output := ''
	mut arguments := os.args[1..].clone()
	for arguments.len > 0 {
		if arguments[0] == '--check' { check = true; arguments = arguments[1..].clone(); continue }
		if arguments.len < 2 {
			return error('usage: stage.v --arch aarch64|x86_64 --staging DIR [--check] [--cc COMPILER] [--config REVIEWED_CONFIG.json] [--repositories SIGNED_BUNDLE_DIRECTORY] [--applications REQUIREMENTS.json | --require-app ID...] [--export-deployment NEW_FILE]')
		}
		match arguments[0] {
			'--arch' { architecture = arguments[1] }
			'--staging' { staging = os.abs_path(arguments[1]) }
			'--cc' { compiler = arguments[1] }
			'--cc-argv' { compiler_args = json2.decode[[]string](arguments[1])! }
			'--require-app' {
				if applications_explicit { return error('--applications and --require-app are alternative application requirement inputs') }
				if required_applications.len == 4096 { return error('--require-app supports at most 4096 application IDs') }
				applications = '' // explicit IDs override an environment file
				required_applications << arguments[1]
			}
			'--applications' {
				if arguments[1] == '' { return error('--applications requires a reviewed application requirements file') }
				if required_applications.len > 0 { return error('--applications and --require-app are alternative application requirement inputs') }
				applications = arguments[1]
				applications_explicit = true
			}
			'--export-deployment' {
				if arguments[1] == '' { return error('--export-deployment requires a new output file') }
				deployment_output = arguments[1]
			}
			'--config' {
				if arguments[1] == '' { return error('--config requires a reviewed package configuration file') }
				configuration = arguments[1]
			}
			'--repositories' {
				if arguments[1] == '' { return error('--repositories requires a reviewed signed repository bundle directory') }
				repositories = arguments[1]
			}
			else { return error('unknown staging option: ${arguments[0]}') }
		}
		arguments = arguments[2..].clone()
	}
	if architecture !in ['aarch64', 'x86_64'] || staging == '' || staging == '/' || !os.is_dir(staging) {
		return error('staging needs an existing target directory and supported architecture')
	}
	if deployment_output != '' && (!check || (required_applications.len == 0 && applications == '')) {
		return error('--export-deployment requires --check and selected application requirements')
	}
	mut image_configuration := pkgcore.prepare_image_configuration(staging, architecture, configuration)!
	defer { image_configuration.close() }
	mut image_repositories := unsafe { &image_configuration }.prepare_repositories(repositories)!
	defer { image_repositories.close() }
	mut image_applications := pkgcore.ImageApplications{}
	defer { image_applications.close() }
	if check {
		report := if deployment_output != '' && applications != '' {
			unsafe { &image_configuration }.export_application_file(unsafe { &image_repositories }, applications, deployment_output)!
		} else if deployment_output != '' {
			unsafe { &image_configuration }.export_applications(unsafe { &image_repositories }, required_applications, deployment_output)!
		} else if applications != '' {
			unsafe { &image_configuration }.check_application_file(unsafe { &image_repositories }, applications)!
		} else if required_applications.len > 0 {
			unsafe { &image_configuration }.check_applications(unsafe { &image_repositories }, required_applications)!
		} else { unsafe { &image_configuration }.check_repositories(unsafe { &image_repositories })! }
		defer { unsafe { report.free() } }
		image_repositories.retire()!
		print(report); return
	} else if applications != '' {
		image_applications = unsafe { &image_configuration }.prepare_application_file(unsafe { &image_repositories }, applications)!
	} else if required_applications.len > 0 {
		image_applications = unsafe { &image_configuration }.prepare_applications(unsafe { &image_repositories }, required_applications)!
	}
	if compiler == '' { compiler = os.getenv('VINIX_MUSL_CC_' + architecture.to_upper()) }
	if compiler == '' { compiler = architecture + '-linux-musl-gcc' }
	// A compiler is an executable path, never shell text.
	if compiler_args.len == 0 { compiler_args = [compiler] }
	cc := os.find_abs_path_of_executable(compiler_args[0])!
	if !os.is_file(cc) || !os.is_executable(cc) { return error('target compiler is missing or not executable: ${cc}') }
	configured_v := os.getenv('V')
	compiler_v := if configured_v == '' { 'v' } else { configured_v }
	v := os.find_abs_path_of_executable(compiler_v)!
	repository := os.dir(os.dir(os.dir(@FILE)))
	mut integration := unsafe { &image_configuration }.prepare_integration(repository)!
	defer { integration.close() }
	mut tool_build := unsafe { &image_configuration }.prepare_tool_build()!
	defer { tool_build.close() }
	compile_image_tools(unsafe { &tool_build }, architecture, repository, v, cc, compiler_args) or { return tool_build.failure(err) }
	tool_build.retire()!
	unsafe { &integration }.publish()!
	if unsafe { &image_repositories }.publish()! { println('Published authenticated offline image repositories') }
	created := unsafe { &image_configuration }.publish()!
	println(if created { 'Initialized reviewed image package configuration' } else { 'Preserved existing image package configuration; release input was not applied' })
	if unsafe { &image_applications }.publish(unsafe { &image_repositories })! {
		println('Declared reviewed release applications for Software deployment review')
	}
	image_repositories.retire()!
	println('Staged signed package service and Software launcher (${architecture})')
}

fn main() {
	stage() or {
		eprintln('package staging: ${err}')
		exit(1)
	}
}
