import array
import hashlib
import os
import resource
import select
import socket
import subprocess
import sys
import threading
import time


failures = []


def check(condition, description):
    print("%-40s %s" % (description, "ok" if condition else "FAIL"), flush=True)
    if not condition:
        failures.append(description)


check(sys.version_info.major == 3, "interpreter is Python 3")
print("  [info] %s" % sys.version.replace("\n", " "), flush=True)

# Filesystem operations used by the import machinery and package installers.
workdir = "/tmp/python3-smoke-%d" % os.getpid()
os.makedirs(workdir, exist_ok=True)
path = os.path.join(workdir, "file")
with open(path, "w") as output:
    output.write("hello\n" * 100)
check(os.path.getsize(path) == 600, "write and stat a file")
with open(path) as source:
    check(len(source.readlines()) == 100, "read it back")
os.rename(path, path + "2")
check(os.path.exists(path + "2") and not os.path.exists(path), "os.rename")
os.symlink("file2", os.path.join(workdir, "link"))
check(os.readlink(os.path.join(workdir, "link")) == "file2", "symlink and readlink")
check(sorted(os.listdir(workdir)) == ["file2", "link"], "os.listdir")
os.truncate(path + "2", 10)
check(os.path.getsize(path + "2") == 10, "os.truncate")
check(os.statvfs("/tmp").f_bsize > 0, "os.statvfs")

# fork/exec/wait and pipe EOF are the foundation of subprocess.
read_fd, write_fd = os.pipe()
pid = os.fork()
if pid == 0:
    os.close(read_fd)
    os.write(write_fd, b"from the child")
    os._exit(3)
os.close(write_fd)
data = os.read(read_fd, 64)
_, status = os.waitpid(pid, 0)
check(data == b"from the child", "fork and pipe")
check(os.WIFEXITED(status) and os.WEXITSTATUS(status) == 3, "waitpid exit status")
os.close(read_fd)

result = subprocess.run(
    ["/bin/busybox", "echo", "subprocess works"],
    capture_output=True,
    text=True,
)
check(result.returncode == 0 and "subprocess works" in result.stdout, "subprocess.run")

# clone(CLONE_THREAD), TLS and futex wakeups.
seen = []
seen_lock = threading.Lock()


def worker(number):
    with seen_lock:
        seen.append(number)


threads = [threading.Thread(target=worker, args=(number,)) for number in range(8)]
for thread in threads:
    thread.start()
for thread in threads:
    thread.join()
check(sorted(seen) == list(range(8)), "eight threads with a lock")

wake = threading.Event()


def waiter():
    wake.wait(5)
    seen.append("woken")


thread = threading.Thread(target=waiter)
thread.start()
time.sleep(0.2)
wake.set()
thread.join()
check("woken" in seen, "threading.Event")

# select, poll and epoll readiness.
read_fd, write_fd = os.pipe()
check(select.select([read_fd], [], [], 0) == ([], [], []), "select sees nothing ready")
os.write(write_fd, b"x")
check(select.select([read_fd], [], [], 1)[0] == [read_fd], "select sees a readable pipe")
poller = select.poll()
poller.register(read_fd, select.POLLIN)
check(poller.poll(1000)[0][0] == read_fd, "select.poll")
if hasattr(select, "epoll"):
    epoll = select.epoll()
    epoll.register(read_fd, select.EPOLLIN)
    check(len(epoll.poll(1)) == 1, "select.epoll")
    epoll.close()
os.close(read_fd)
os.close(write_fd)

# Connected and pathname-based Unix sockets.
left, right = socket.socketpair()
left.send(b"ping")
check(right.recv(16) == b"ping", "socketpair round trip")
left.close()
right.close()

# Stream ancillary data is a barrier: recvmsg returns preceding bytes and the
# descriptor-bearing sendmsg together, but leaves later bytes for the next
# receive. Firefox IPC relies on this association remaining intact.
left, right = socket.socketpair()
passed_fd = os.open("/dev/null", os.O_RDONLY)
left.sendall(b"before")
left.sendmsg(
    [b"rights"],
    [(socket.SOL_SOCKET, socket.SCM_RIGHTS, array.array("i", [passed_fd]))],
)
left.sendall(b"after")
payload, ancillary, message_flags, _ = right.recvmsg(
    64, socket.CMSG_SPACE(array.array("i").itemsize)
)
received_fds = array.array("i")
for level, kind, data in ancillary:
    if level == socket.SOL_SOCKET and kind == socket.SCM_RIGHTS:
        received_fds.frombytes(data[: len(data) - len(data) % received_fds.itemsize])
check(payload == b"beforerights", "SCM_RIGHTS stream boundary")
check(message_flags == 0 and len(received_fds) == 1, "SCM_RIGHTS descriptor delivery")
check(right.recv(64) == b"after", "SCM_RIGHTS leaves following bytes")
for received_fd in received_fds:
    os.close(received_fd)
os.close(passed_fd)
left.close()
right.close()

socket_path = os.path.join(workdir, "server.sock")
server = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
server.bind(socket_path)
server.listen(1)
client = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
client.connect(socket_path)
connection, _ = server.accept()
client.sendall(b"over a unix socket")
check(connection.recv(64) == b"over a unix socket", "unix socket connect/accept")
client.close()
connection.close()
server.close()
os.unlink(socket_path)
check(not os.path.exists(socket_path), "unlink unix socket path")

started = time.monotonic()
time.sleep(0.3)
check(time.monotonic() - started >= 0.25, "time.sleep and monotonic")
check(time.time() > 1_000_000, "time.time")
check(os.getuid() == 0 and os.geteuid() == 0, "process credentials")
check(os.getpid() > 0, "process ID")
check(len(bytearray(1 << 20)) == 1 << 20, "allocate a megabyte")
check(len(os.urandom(32)) == 32 and os.urandom(32) != os.urandom(32), "os.urandom")

# Native extension modules and their shared-library dependencies.
for module_name in (
    "bz2",
    "ctypes",
    "datetime",
    "decimal",
    "hashlib",
    "lzma",
    "math",
    "sqlite3",
    "ssl",
    "struct",
    "zlib",
):
    try:
        __import__(module_name)
        check(True, "import " + module_name)
    except Exception as error:
        check(False, "import %s (%s)" % (module_name, type(error).__name__))

import zlib

blob = b"vinix" * 1000
check(zlib.decompress(zlib.compress(blob)) == blob, "zlib round trip")
check(len(hashlib.sha256(blob).hexdigest()) == 64, "sha256")

# Positioned I/O, seeking beyond EOF and sparse-file holes.
positioned_path = os.path.join(workdir, "positioned-io")
fd = os.open(positioned_path, os.O_CREAT | os.O_RDWR, 0o600)
os.pwrite(fd, b"SQLite format 3\0", 0)
check(os.pread(fd, 16, 0) == b"SQLite format 3\0", "positioned file I/O")
original_position = os.lseek(fd, 7, os.SEEK_SET)
check(os.pwritev(fd, [b"vector", b" write"], 32) == 12, "positioned vector write")
first = bytearray(6)
second = bytearray(6)
check(
    os.preadv(fd, [first, second], 32) == 12
    and bytes(first + second) == b"vector write"
    and os.lseek(fd, 0, os.SEEK_CUR) == original_position,
    "positioned vector read preserves offset",
)
os.posix_fallocate(fd, 0, 128)
check(os.fstat(fd).st_size >= 128, "posix_fallocate")
os.posix_fadvise(fd, 0, 0, os.POSIX_FADV_NORMAL)
check(True, "posix_fadvise")
os.ftruncate(fd, 0)
os.lseek(fd, 24, os.SEEK_SET)
check(os.fstat(fd).st_size == 0 and os.read(fd, 1) == b"", "seek/read beyond EOF")
os.write(fd, b"x")
check(os.pread(fd, 25, 0) == b"\0" * 24 + b"x", "zero-filled sparse write")
os.close(fd)

# Descriptor-oriented primitives used by contemporary event loops and servers.
event_fd = os.eventfd(0, os.EFD_NONBLOCK | os.EFD_CLOEXEC)
event_poller = select.epoll()
event_poller.register(event_fd, select.EPOLLIN)
check(event_poller.poll(0) == [], "eventfd starts unreadable")
os.eventfd_write(event_fd, 7)
check(len(event_poller.poll(1)) == 1 and os.eventfd_read(event_fd) == 7, "eventfd and epoll")
event_poller.close()
os.close(event_fd)

sendfile_source = os.path.join(workdir, "sendfile-source")
sendfile_target = os.path.join(workdir, "sendfile-target")
with open(sendfile_source, "wb") as output:
    output.write(b"0123456789")
with open(sendfile_source, "rb") as source, open(sendfile_target, "wb") as target:
    source.seek(8)
    check(os.sendfile(target.fileno(), source.fileno(), 2, 5) == 5, "sendfile")
    check(source.tell() == 8, "sendfile explicit offset is positioned")
with open(sendfile_target, "rb") as copied:
    check(copied.read() == b"23456", "sendfile contents")

soft_limit, hard_limit = resource.getrlimit(resource.RLIMIT_NOFILE)
check(soft_limit > 0 and hard_limit >= soft_limit, "getrlimit")
if hasattr(os, "sched_getcpu"):
    check(os.sched_getcpu() >= 0, "getcpu")
if hasattr(os, "sched_rr_get_interval"):
    check(os.sched_rr_get_interval(0) > 0, "sched_rr_get_interval")
check(os.uname().machine == "aarch64", "uname Linux layout")

import sqlite3

database_path = os.path.join(workdir, "database.sqlite")
database = sqlite3.connect(database_path)
database.execute("create table rows (number int, text text)")
database.executemany(
    "insert into rows values (?, ?)",
    [(number, "row%d" % number) for number in range(100)],
)
database.commit()
check(database.execute("select count(*) from rows").fetchone()[0] == 100, "sqlite3 insert and select")
database.close()

print(
    "PYTHON3 SMOKE %s (%d failures)" % ("FAIL" if failures else "PASS", len(failures)),
    flush=True,
)
if failures:
    print("failed: " + ", ".join(failures), flush=True)
    raise SystemExit(1)
