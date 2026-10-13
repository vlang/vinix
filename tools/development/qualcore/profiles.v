// SPDX-License-Identifier: GPL-2.0-or-later
module qualcore

import os

const c_source = '#include <stdio.h>
#include <pthread.h>
static void *worker(void *p) { *(int *)p = 42; return 0; }
int main(void) {
    pthread_t thread; int answer = 0;
    if (pthread_create(&thread, 0, worker, &answer) || pthread_join(thread, 0)) return 1;
    FILE *file = fopen("project.data", "w"); if (!file) return 2;
    if (fprintf(file, "%d", answer) != 2 || fclose(file)) return 3;
    file = fopen("project.data", "r"); int readback = 0;
    if (!file || fscanf(file, "%d", &readback) != 1 || fclose(file) || readback != 42) return 4;
    puts("VINIX-TOOLCHAIN:PASS"); return 0;
}
'

const cpp_source = '#include <iostream>
#include <fstream>
#include <vector>
#include <thread>
int main() {
    std::vector<int> values{20, 22}; int answer = 0;
    std::thread worker([&]() { for (int x : values) answer += x; }); worker.join();
    { std::ofstream file("project.data"); file << answer; if (!file) return 1; }
    std::ifstream file("project.data"); int readback = 0; file >> readback;
    if (readback != 42) return 2; std::cout << "VINIX-TOOLCHAIN:PASS\\n";
}
'

const v_source = 'module main
import os
fn main() {
    values := [20, 22]
    mut answer := 0
    for value in values { answer += value }
    os.write_file("project.data", answer.str())!
    if os.read_file("project.data")! != "42" { exit(1) }
    println("VINIX-TOOLCHAIN:PASS")
}
'

const rust_source = 'use std::{fs, thread};
fn main() {
    let answer = thread::spawn(|| vec![20, 22].iter().sum::<i32>()).join().unwrap();
    fs::write("project.data", answer.to_string()).unwrap();
    assert_eq!(fs::read_to_string("project.data").unwrap(), "42");
    println!("VINIX-TOOLCHAIN:PASS");
}
'

const go_source = 'package main
import ("fmt"; "os")
func main() {
    channel := make(chan int); go func() { channel <- 20 + 22 }()
    if err := os.WriteFile("project.data", []byte(fmt.Sprint(<-channel)), 0600); err != nil { panic(err) }
    data, err := os.ReadFile("project.data"); if err != nil || string(data) != "42" { panic("readback") }
    fmt.Println("VINIX-TOOLCHAIN:PASS")
}
'

const java_source = 'import java.nio.file.*;
public class Project {
    public static void main(String[] args) throws Exception {
        final int[] answer = {0}; Thread worker = new Thread(() -> answer[0] = 42);
        worker.start(); worker.join(); Path path = Path.of("project.data");
        Files.writeString(path, Integer.toString(answer[0]));
        if (!Files.readString(path).equals("42")) throw new Exception("readback");
        System.out.println("VINIX-TOOLCHAIN:PASS");
    }
}
'

const node_source = 'const fs = require("node:fs");
const crypto = require("node:crypto");
fs.writeFileSync("project.data", "42", {mode: 0o600});
if (fs.readFileSync("project.data", "utf8") !== "42" || crypto.createHash("sha256").update("42").digest("hex").length !== 64) process.exit(1);
console.log("VINIX-TOOLCHAIN:PASS");
'

fn (mut runner Runner) profile(name string) ! {
	match name {
		'c' {
			runner.write('main.c', c_source)!
			runner.command('cc', ['-g', '-pthread', '-o', 'project', 'main.c'])!
			runner.verify_binary('project')!
		}
		'cpp' {
			runner.write('main.cpp', cpp_source)!
			runner.command('c++', ['-std=c++17', '-g', '-pthread', '-o', 'project', 'main.cpp'])!
			runner.verify_binary('project')!
		}
		'v' {
			runner.write('main.v', v_source)!
			mut v_args := ['-gc', 'none', '-cc', tool('cc')!, '-o', 'project', 'main.v']
			kernel := os.uname()
			if kernel.sysname.to_lower() == 'vinix' {
				// Match the installed native compiler's defaults without requiring
				// a shell wrapper. Keep V3 workers serial and make failures final.
				v_args.prepend(['-new-compiler', '-no-retry-compilation', '-no-parallel',
					'-no-memory-limit', '-os', 'vinix', '-arch',
					if kernel.machine == 'aarch64' { 'arm64' } else { 'amd64' }, '-musl'])
			}
			runner.command('v', v_args)!
			runner.verify_binary('project')!
		}
		'rust' {
			runner.write('main.rs', rust_source)!
			runner.command('rustc', ['--edition=2021', '-g', '-o', 'project', 'main.rs'])!
			runner.verify_binary('project')!
		}
		'cargo' {
			os.mkdir(runner.work + '/src')!
			runner.write('src/main.rs', rust_source)!
			runner.write('Cargo.toml', '[package]\nname = "vinix-project"\nversion = "0.1.0"\nedition = "2021"\n')!
			runner.command('cargo', ['build', '--offline'])!
			runner.verify_binary('target/debug/vinix-project')!
		}
		'go' {
			runner.write('main.go', go_source)!
			runner.command('go', ['build', '-trimpath', '-buildvcs=false', '-o', 'project', 'main.go'])!
			runner.verify_binary('project')!
		}
		'java' {
			for program in ['java', 'javac', 'jar'] { runner.command(program, ['--version'])! }
			runner.write('Project.java', java_source)!
			runner.command('javac', ['Project.java'])!
			runner.command('jar', ['--create', '--date=2023-11-14T22:13:20Z', '--file', 'project.jar', '--main-class', 'Project',
				'Project.class'])!
			if runner.command('java', ['-jar', 'project.jar'])!.trim_space() != marker {
				return error('Java archive execution failed')
			}
		}
		'node' {
			runner.write('project.js', node_source)!
			if runner.command('node', ['project.js'])!.trim_space() != marker {
				return error('Node project failed')
			}
		}
		'typescript' {
			runner.write('project.ts', 'const answer: number = [20, 22].reduce((a: number, b: number) => a + b);\nif (answer !== 42) throw new Error("answer");\nconsole.log("VINIX-TOOLCHAIN:PASS");\n')!
			runner.command('tsc', ['--strict', '--target', 'ES2020', 'project.ts'])!
			if runner.command('node', ['project.js'])!.trim_space() != marker {
				return error('TypeScript output failed')
			}
		}
		'make', 'cmake', 'ninja' { runner.build_system(name)! }
		'npm' { runner.npm_project()! }
		'gdb' {
			runner.write('main.c', c_source)!
			runner.command('cc', ['-g', '-O0', '-pthread', '-o', 'project', 'main.c'])!
			output := runner.command('gdb', ['--batch', '--nx', '-ex', 'break main', '-ex', 'run',
				'-ex', 'bt', '-ex', 'continue', 'project'])!
			if !output.contains(marker) || !output.contains('#0') || !output.contains('main.c:') {
				return error('debugger failed to stop, unwind and continue the project')
			}
		}
		'sqlite' {
			runner.command('sqlite3', ['project.db',
				'CREATE TABLE answer(n INTEGER); BEGIN; INSERT INTO answer VALUES(42); COMMIT; BEGIN; INSERT INTO answer VALUES(7); ROLLBACK;'])!
			if runner.command('sqlite3', ['project.db', 'PRAGMA integrity_check; SELECT n FROM answer;'])!.trim_space() != 'ok\n42' {
				return error('database transaction, reopen or integrity check failed')
			}
		}
		'http' { runner.http_project()! }
		else { return error('unknown profile') }
	}
}

fn (mut runner Runner) build_system(name string) ! {
	runner.write('main.c', c_source)!
	compiler := tool('cc')!
	match name {
		'make' {
			runner.write('Makefile', 'project: main.c\n\t$(CC) -pthread -o project main.c\n')!
			runner.command('make', ['CC=' + compiler])!
			runner.verify_binary('project')!
		}
		'cmake' {
			tool('ninja')!
			runner.write('CMakeLists.txt', 'cmake_minimum_required(VERSION 3.10)\nproject(vinix_project C)\nfind_package(Threads REQUIRED)\nadd_executable(project main.c)\ntarget_link_libraries(project PRIVATE Threads::Threads)\n')!
			runner.command('cmake', ['-S', '.', '-B', 'build', '-G', 'Ninja',
				'-DCMAKE_C_COMPILER=' + compiler])!
			runner.command('cmake', ['--build', 'build'])!
			runner.verify_binary('build/project')!
		}
		else {
			// Ninja file syntax treats dollars and spaces specially. The
			// compiler is resolved by the process's existing PATH instead.
			runner.write('build.ninja', 'rule compile\n  command = cc -pthread -o project main.c\nbuild project: compile main.c\n')!
			runner.command('ninja', [])!
			runner.verify_binary('project')!
		}
	}
}

fn (mut runner Runner) npm_project() ! {
	os.mkdir(runner.work + '/dependency')!
	runner.write('dependency/package.json', '{"name":"vinix-local-dependency","version":"1.0.0","main":"index.js"}\n')!
	runner.write('dependency/index.js', 'module.exports = 42;\n')!
	runner.write('package.json', '{"name":"vinix-local-project","version":"1.0.0","private":true}\n')!
	runner.command('npm', ['pack', './dependency', '--offline', '--ignore-scripts'])!
	runner.command('npm', ['install', './vinix-local-dependency-1.0.0.tgz', '--offline',
		'--ignore-scripts', '--no-audit', '--no-fund'])!
	runner.write('project.js', 'if (require("vinix-local-dependency") !== 42) process.exit(1);\nconsole.log("VINIX-TOOLCHAIN:PASS");\n')!
	if runner.command('node', ['project.js'])!.trim_space() != marker {
		return error('offline package installation failed')
	}
}
