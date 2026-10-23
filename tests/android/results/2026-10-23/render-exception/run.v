import os

fn main() {
 assert os.args.len == 2 && os.args[1] in ['baseline', 'fixed']
 mode := os.args[1]
 b := 'build/android-maps/'
 // The suite cannot restage its extracted /sbin/init symlink in place, and
 // an old serial log would make the interactor observe a previous exit.
 output_dir := b + 'render230/run-' + mode
 if os.exists(output_dir) { os.rmdir_all(output_dir)! }
 mut runner := os.new_process(b + 'suite159')
 runner.set_args([b + 'render230/' + mode + '.json'])
 runner.set_redirect_stdio()
 runner.run()
 mut input := os.new_process(b + 'interact-render230')
 input.set_args([mode])
 input.set_redirect_stdio()
 input.run()
 runner.wait()
 input.wait()
 output := runner.stdout_slurp() + runner.stderr_slurp()
 os.write_file(b + 'render230/' + mode + '-harness.log', output)!
 print(output)
 interaction := input.stdout_slurp() + input.stderr_slurp()
 os.write_file(b + 'render230/' + mode + '-interaction.log', interaction)!
 print(interaction)
 assert runner.code == 0 && input.code == 0
}
