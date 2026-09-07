import http.server
import os
import shutil
import subprocess


failures = []


def check(condition, description, detail=""):
    print("%-40s %s" % (description, "ok" if condition else "FAIL"), flush=True)
    if not condition:
        failures.append(description)
        if detail:
            print("  " + detail.replace("\n", "\n  "), flush=True)


def run(command, **kwargs):
    return subprocess.run(command, capture_output=True, text=True, **kwargs)


version = run(["codex", "--version"])
check(
    version.returncode == 0 and version.stdout.startswith("codex-cli "),
    "Codex CLI starts",
    version.stdout + version.stderr,
)
if version.stdout:
    print("  [info] " + version.stdout.strip(), flush=True)

help_result = run(["codex", "--help"])
check(
    help_result.returncode == 0
    and "Run Codex non-interactively" in help_result.stdout,
    "Codex help is available",
    help_result.stdout + help_result.stderr,
)

rg_result = run(["/usr/lib/codex/codex-path/rg", "--version"])
check(
    rg_result.returncode == 0 and "ripgrep" in rg_result.stdout,
    "bundled musl ripgrep starts",
    rg_result.stdout + rg_result.stderr,
)

zsh_result = run(["/usr/lib/codex/codex-resources/zsh/bin/zsh", "--version"])
check(
    zsh_result.returncode == 0 and "zsh" in zsh_result.stdout,
    "bundled musl zsh starts",
    zsh_result.stdout + zsh_result.stderr,
)


class ResponsesHandler(http.server.BaseHTTPRequestHandler):
    request_count = 0
    response_body = (
        "event: response.created\n"
        'data: {"type":"response.created","response":{"id":"resp-vinix"}}\n\n'
        "event: response.output_item.done\n"
        'data: {"type":"response.output_item.done","item":{"type":"message",'
        '"role":"assistant","id":"msg-vinix","content":[{"type":"output_text",'
        '"text":"VINIX CODEX LOOPBACK PASS"}]}}\n\n'
        "event: response.completed\n"
        'data: {"type":"response.completed","response":{"id":"resp-vinix",'
        '"usage":{"input_tokens":0,"input_tokens_details":null,"output_tokens":0,'
        '"output_tokens_details":null,"total_tokens":0}}}\n\n'
    ).encode()

    def do_POST(self):
        type(self).request_count += 1
        length = int(self.headers.get("content-length", "0"))
        if length:
            self.rfile.read(length)
        self.send_response(200)
        self.send_header("Content-Type", "text/event-stream")
        self.send_header("Content-Length", str(len(self.response_body)))
        self.send_header("Connection", "close")
        self.end_headers()
        self.wfile.write(self.response_body)

    def log_message(self, _format, *_args):
        pass


server = http.server.HTTPServer(("127.0.0.1", 0), ResponsesHandler)
server.timeout = 90

codex_home = "/root/.codex-smoke-home-%d" % os.getpid()
shutil.rmtree(codex_home, ignore_errors=True)
os.makedirs(codex_home)
environment = os.environ.copy()
environment["CODEX_HOME"] = codex_home
environment["OPENAI_API_KEY"] = "vinix-loopback-key"
provider = (
    'model_providers.vinix={name="Vinix loopback",'
    'base_url="http://127.0.0.1:%d/v1",env_key="OPENAI_API_KEY",'
    'wire_api="responses",request_max_retries=0,stream_max_retries=0}'
    % server.server_port
)

command = [
    "codex",
    "exec",
    "--skip-git-repo-check",
    "--dangerously-bypass-approvals-and-sandbox",
    "--ephemeral",
    "-C",
    "/tmp",
    "-m",
    "gpt-5.1",
    "-c",
    provider,
    "-c",
    'model_provider="vinix"',
    "Reply with the requested smoke-test phrase.",
]

agent_pid = os.fork()
if agent_pid == 0:
    # Keeping the HTTP server in the parent and immediately replacing this
    # child avoids relying on thread-plus-fork behavior in the test itself.
    server.server_close()
    try:
        os.execvpe(command[0], command, environment)
    except OSError as error:
        print("codex exec failed: %s" % error, flush=True)
        os._exit(127)

agent_status = None
agent_error = ""
try:
    # Leave Codex attached to the console so the model reply is visible in the
    # boot log and pipe I/O is not part of this network protocol test.
    server.handle_request()
    if ResponsesHandler.request_count == 0:
        agent_error = "codex did not reach the loopback server within 90 seconds"
        os.kill(agent_pid, 9)
    _, wait_status = os.waitpid(agent_pid, 0)
    agent_status = os.waitstatus_to_exitcode(wait_status)
except OSError as error:
    agent_error = str(error)
finally:
    server.server_close()
    shutil.rmtree(codex_home, ignore_errors=True)

check(
    agent_status == 0
    and ResponsesHandler.request_count > 0,
    "codex exec completes a model turn",
    agent_error if agent_status is None else "codex exit status %d" % agent_status,
)

print(
    "CODEX SMOKE %s (%d failures)"
    % ("FAIL" if failures else "PASS", len(failures)),
    flush=True,
)
if failures:
    print("failed: " + ", ".join(failures), flush=True)
    raise SystemExit(1)
