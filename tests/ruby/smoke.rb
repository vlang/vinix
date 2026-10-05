# frozen_string_literal: true

failures = []

check = lambda do |condition, description|
  puts format('%-40s %s', description, condition ? 'ok' : 'FAIL')
  $stdout.flush
  failures << description unless condition
end

check.call(RUBY_VERSION.start_with?('3.'), 'interpreter is Ruby 3')
puts "  [info] #{RUBY_DESCRIPTION}"

# Filesystem operations used by require, RubyGems and Bundler.
workdir = "/tmp/ruby-smoke-#{Process.pid}"
Dir.mkdir(workdir)
path = File.join(workdir, 'file')
File.write(path, "hello\n" * 100)
check.call(File.size(path) == 600, 'write and stat a file')
check.call(File.readlines(path).length == 100, 'read it back')
File.rename(path, "#{path}2")
check.call(File.exist?("#{path}2") && !File.exist?(path), 'File.rename')
File.symlink('file2', File.join(workdir, 'link'))
check.call(File.readlink(File.join(workdir, 'link')) == 'file2', 'symlink and readlink')
check.call(Dir.children(workdir).sort == %w[file2 link], 'Dir.children')
File.truncate("#{path}2", 10)
check.call(File.size("#{path}2") == 10, 'File.truncate')

# fork/exec/wait and pipe EOF.
reader, writer = IO.pipe
pid = fork do
  reader.close
  writer.write('from the child')
  exit! 3
end
writer.close
data = reader.read
_, status = Process.wait2(pid)
check.call(data == 'from the child', 'fork and pipe')
check.call(status.exited? && status.exitstatus == 3, 'wait reports exit status')
reader.close

require 'open3'

stdout, stderr, status = Open3.capture3('/bin/busybox', 'echo', 'subprocess works')
check.call(status.success? && stdout.include?('subprocess works') && stderr.empty?, 'Open3.capture3')

# Native threads, TLS, mutexes and condition-variable wakeups.
seen = []
mutex = Mutex.new
threads = 8.times.map do |number|
  Thread.new { mutex.synchronize { seen << number } }
end
threads.each(&:join)
check.call(seen.sort == (0...8).to_a, 'eight threads with a mutex')

condition = ConditionVariable.new
ready = Queue.new
woken = false
thread = Thread.new do
  mutex.synchronize do
    ready << true
    condition.wait(mutex, 5)
    woken = true
  end
end
ready.pop
mutex.synchronize { condition.signal }
thread.join
check.call(woken, 'condition variable')

# select readiness and pipe EOF.
reader, writer = IO.pipe
check.call(IO.select([reader], [], [], 0).nil?, 'IO.select sees nothing ready')
writer.write('x')
check.call(IO.select([reader], [], [], 1).first == [reader], 'IO.select sees a readable pipe')
reader.read(1)
writer.close
check.call(IO.select([reader], [], [], 1).first == [reader] && reader.read == '', 'pipe EOF is readable')
reader.close

# Connected and pathname-based Unix sockets.
require 'socket'

left, right = Socket.pair(Socket::AF_UNIX, Socket::SOCK_STREAM, 0)
left.write('ping')
check.call(right.read(4) == 'ping', 'socketpair round trip')
left.close
right.close

socket_path = File.join(workdir, 'server.sock')
server = UNIXServer.new(socket_path)
client = UNIXSocket.new(socket_path)
connection = server.accept
client.write('over a unix socket')
check.call(connection.read(18) == 'over a unix socket', 'unix socket connect/accept')
client.close
connection.close
server.close
File.unlink(socket_path)
check.call(!File.exist?(socket_path), 'unlink unix socket path')

started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
sleep 0.3
elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
check.call(elapsed >= 0.25, 'sleep and monotonic clock')
check.call(Time.now.to_i > 1_000_000, 'wall clock')
check.call(Process.uid.zero? && Process.euid.zero?, 'process credentials')
check.call(Process.pid.positive?, 'process ID')
check.call(('x' * (1 << 20)).bytesize == 1 << 20, 'allocate a megabyte')
check.call(Random.urandom(32).bytesize == 32, 'Random.urandom')

# Native standard-library extensions and their shared dependencies.
%w[bigdecimal bundler digest fiddle json openssl psych rake readline rubygems zlib].each do |library|
  begin
    require library
    check.call(true, "require #{library}")
  rescue LoadError => error
    check.call(false, "require #{library} (#{error.class})")
  end
end

blob = 'vinix' * 1000
check.call(Zlib::Inflate.inflate(Zlib::Deflate.deflate(blob)) == blob, 'zlib round trip')
check.call(Digest::SHA256.hexdigest(blob).length == 64, 'SHA-256')
check.call(Psych.safe_load(Psych.dump({ 'ruby' => 3 })) == { 'ruby' => 3 }, 'Psych YAML round trip')

# Fibers use Ruby's aarch64 context-switching path.
fiber = Fiber.new do
  Fiber.yield('first')
  'second'
end
check.call(fiber.resume == 'first' && fiber.resume == 'second', 'Fiber context switching')

# Positioned I/O, seeking beyond EOF and sparse-file holes.
positioned_path = File.join(workdir, 'positioned-io')
File.open(positioned_path, File::RDWR | File::CREAT, 0o600) do |file|
  file.pwrite("Ruby positioned IO\0", 0)
  check.call(file.pread(19, 0) == "Ruby positioned IO\0", 'positioned file I/O')
  file.truncate(0)
  file.seek(24, IO::SEEK_SET)
  check.call(file.stat.size.zero? && file.read(1).nil?, 'seek/read beyond EOF')
  file.write('x')
  file.flush
  check.call(file.pread(25, 0) == ("\0" * 24) + 'x', 'zero-filled sparse write')
  check.call(file.flock(File::LOCK_EX | File::LOCK_NB), 'advisory file lock')
end

puts "RUBY SMOKE #{failures.empty? ? 'PASS' : 'FAIL'} (#{failures.length} failures)"
unless failures.empty?
  puts "failed: #{failures.join(', ')}"
  exit 1
end
