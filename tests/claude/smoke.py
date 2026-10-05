import http.server
import glob
import os
import shutil
import subprocess
import time


failures = []


def check(condition, description, detail=""):
    print("%-40s %s" % (description, "ok" if condition else "FAIL"), flush=True)
    if not condition:
        failures.append(description)
        if detail:
            print("  " + detail.replace("\n", "\n  "), flush=True)


def run(command, **kwargs):
    return subprocess.run(command, capture_output=True, text=True, **kwargs)


version = run(["claude", "--version"])
check(
    version.returncode == 0 and "Claude Code" in version.stdout,
    "Claude Code CLI starts",
    version.stdout + version.stderr,
)
if version.stdout:
    print("  [info] " + version.stdout.strip(), flush=True)

help_result = run(["claude", "--help"])
check(
    help_result.returncode == 0
    and "--print" in help_result.stdout,
    "Claude Code help is available",
    help_result.stdout + help_result.stderr,
)

rg_result = run(["rg", "--version"])
check(
    rg_result.returncode == 0 and "ripgrep" in rg_result.stdout,
    "system musl ripgrep starts",
    rg_result.stdout + rg_result.stderr,
)


class MessagesHandler(http.server.BaseHTTPRequestHandler):
    request_count = 0
    request_path = ""
    response_body = (
        "event: message_start\n"
        'data: {"type":"message_start","message":{"id":"msg_vinix",'
        '"type":"message","role":"assistant","model":"claude-sonnet-4-5",'
        '"content":[],"stop_reason":null,"stop_sequence":null,'
        '"usage":{"input_tokens":1,"output_tokens":1}}}\n\n'
        "event: content_block_start\n"
        'data: {"type":"content_block_start","index":0,'
        '"content_block":{"type":"text","text":""}}\n\n'
        "event: content_block_delta\n"
        'data: {"type":"content_block_delta","index":0,'
        '"delta":{"type":"text_delta","text":"VINIX CLAUDE LOOPBACK PASS"}}\n\n'
        "event: content_block_stop\n"
        'data: {"type":"content_block_stop","index":0}\n\n'
        "event: message_delta\n"
        'data: {"type":"message_delta","delta":{"stop_reason":"end_turn",'
        '"stop_sequence":null},"usage":{"output_tokens":7}}\n\n'
        "event: message_stop\n"
        'data: {"type":"message_stop"}\n\n'
    ).encode()

    def send_hello(self, include_body):
        body = b'{"message":"hello"}'
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Connection", "close")
        self.end_headers()
        if include_body:
            self.wfile.write(body)

    def do_HEAD(self):
        if self.path == "/api/hello":
            self.send_hello(False)
        else:
            self.send_error(404)

    def do_GET(self):
        if self.path == "/api/hello":
            self.send_hello(True)
        else:
            self.send_error(404)

    def do_POST(self):
        type(self).request_count += 1
        type(self).request_path = self.path
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


server = http.server.HTTPServer(("127.0.0.1", 0), MessagesHandler)
server.timeout = 90

claude_home = "/tmp/claude-smoke-home-%d" % os.getpid()
claude_stdout_path = "/tmp/claude-smoke-stdout-%d" % os.getpid()
claude_stderr_path = "/tmp/claude-smoke-stderr-%d" % os.getpid()
shutil.rmtree(claude_home, ignore_errors=True)
os.makedirs(claude_home)
environment = os.environ.copy()
environment["HOME"] = claude_home
environment["ANTHROPIC_API_KEY"] = "vinix-loopback-key"
environment["ANTHROPIC_BASE_URL"] = "http://127.0.0.1:%d" % server.server_port
environment["CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC"] = "1"
environment["DISABLE_AUTOUPDATER"] = "1"

command = [
    "claude",
    "--print",
    "--bare",
    "--debug",
    "--model",
    "claude-sonnet-4-5",
    "--max-turns",
    "1",
    "--no-session-persistence",
    "Reply with the requested smoke-test phrase.",
]

agent_pid = os.fork()
if agent_pid == 0:
    server.server_close()
    try:
        stdout_fd = os.open(
            claude_stdout_path, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600
        )
        stderr_fd = os.open(
            claude_stderr_path, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600
        )
        os.dup2(stdout_fd, 1)
        os.dup2(stderr_fd, 2)
        os.close(stdout_fd)
        os.close(stderr_fd)
        os.execvpe(command[0], command, environment)
    except OSError as error:
        print("claude failed: %s" % error, flush=True)
        os._exit(127)

agent_status = None
agent_error = ""
agent_stdout = ""
agent_stderr = ""
agent_debug = ""
try:
    deadline = time.monotonic() + 90
    while agent_status is None:
        server.timeout = min(1, max(0, deadline - time.monotonic()))
        server.handle_request()
        completed_pid, wait_status = os.waitpid(agent_pid, os.WNOHANG)
        if completed_pid:
            agent_status = os.waitstatus_to_exitcode(wait_status)
        if agent_status is None and time.monotonic() >= deadline:
            agent_error = "claude did not complete the loopback turn within 90 seconds"
            os.kill(agent_pid, 9)
            _, wait_status = os.waitpid(agent_pid, 0)
            agent_status = os.waitstatus_to_exitcode(wait_status)
except OSError as error:
    agent_error = str(error)
finally:
    server.server_close()
    for path, destination in [
        (claude_stdout_path, "stdout"),
        (claude_stderr_path, "stderr"),
    ]:
        try:
            contents = open(path).read()
            if destination == "stdout":
                agent_stdout = contents
            else:
                agent_stderr = contents
        except OSError:
            pass
        try:
            os.unlink(path)
        except OSError:
            pass
    debug_files = glob.glob(claude_home + "/.claude/debug/*.txt")
    if debug_files:
        try:
            agent_debug = open(max(debug_files, key=os.path.getmtime)).read()
        except OSError:
            pass
    shutil.rmtree(claude_home, ignore_errors=True)

if agent_stdout:
    print(agent_stdout.rstrip(), flush=True)

check(
    agent_status == 0
    and MessagesHandler.request_count > 0
    and MessagesHandler.request_path.startswith("/v1/messages")
    and "VINIX CLAUDE LOOPBACK PASS" in agent_stdout,
    "claude print completes a model turn",
    "%sclaude exit status %s, request path %s\nstdout:\n%s\nstderr:\n%s\ndebug:\n%s"
    % (
        (agent_error + "\n") if agent_error else "",
        agent_status,
        MessagesHandler.request_path,
        agent_stdout,
        agent_stderr,
        agent_debug,
    ),
)

print(
    "CLAUDE SMOKE %s (%d failures)"
    % ("FAIL" if failures else "PASS", len(failures)),
    flush=True,
)
if failures:
    print("failed: " + ", ".join(failures), flush=True)
    raise SystemExit(1)
