// SPDX-License-Identifier: GPL-2.0-or-later
module referencecore
import json2
import tools.development.devcore

fn test_http_receipt_requires_loopback_private_paths_cgi_pin_and_owned_retirement() {
	work := '/home/developer/reference-a/work'
	project := work + '/qualification/http'
	runner := 'a'.repeat(64)
	server := 'b'.repeat(64)
	tools := {'busybox': devcore.Pin{'/opt/reference/bin/busybox', server}}
	command := Command{argv: ['/opt/reference/bin/busybox', 'httpd', '-f', '-p', '127.0.0.1:45678',
		'-h', project + '/www', '-c', project + '/server.conf'], executable_sha256: server,
		exit_code: -15, log: project + '/command-0.log'}
	report := Report{schema: 1, kernel: 'Vinix', architecture: 'aarch64', uid: 1000, context: 'vinix-native',
		runner_sha256: runner, requested: ['http'], command_timeout_seconds: 600, complete: true,
		all_selected_passed: true, results: [Verdict{profile: 'http', status: 'passed', commands: [command]}]}
	mut outputs := {'qualification/http/www/cgi-bin/api': runner, 'qualification/http/www/index.html': 'c'.repeat(64),
		'qualification/http/server.json': 'd'.repeat(64), 'qualification/http/project.data': 'e'.repeat(64)}
	verify_report(json2.encode(report), 'aarch64', ['http'], runner, tools, work, outputs)!
	for address in ['0.0.0.0:45678', '127.0.0.1:80', '127.0.0.1:65536', '127.0.0.1:12x'] {
		mut argv := command.argv.clone()
		argv[4] = address
		changed := Report{...report, results: [Verdict{...report.results[0], commands: [Command{...command, argv: argv}]}]}
		if _ := verify_report(json2.encode(changed), 'aarch64', ['http'], runner, tools, work, outputs) {
			assert false, 'unapproved HTTP bind accepted'
		}
	}
	for replacement in [Command{...command, exit_code: 0},
		Command{...command, argv: ['/opt/reference/bin/busybox', '--help']},
		Command{...command, environment_overrides: {'VINIX_ALLOW_WX': '1'}}] {
		changed := Report{...report, results: [Verdict{...report.results[0], commands: [replacement]}]}
		if _ := verify_report(json2.encode(changed), 'aarch64', ['http'], runner, tools, work, outputs) {
			assert false, 'server workflow substituted or JIT requested'
		}
	}
	outputs['qualification/http/www/cgi-bin/api'] = 'f'.repeat(64)
	if _ := verify_report(json2.encode(report), 'aarch64', ['http'], runner, tools, work, outputs) {
		assert false, 'unrecorded CGI executable accepted'
	}
}

fn test_http_proof_refuses_missing_authentication_or_retirement() {
	proof := HttpProof{1, 1000, 401, 401, 200, 200, 404, 404, 400, 200, 16, true}
	verify_http_proof(json2.encode(proof))!
	for changed in [HttpProof{...proof, unauthenticated: 200}, HttpProof{...proof, wrong_password: 200},
		HttpProof{...proof, traversal: 200}, HttpProof{...proof, uid: 0}, HttpProof{...proof, group_retired: false}] {
		if _ := verify_http_proof(json2.encode(changed)) { assert false, 'failing HTTP proof accepted' }
	}
}
