# SPDX-License-Identifier: GPL-2.0-or-later
"""Standard-library operations for the native desktop benchmark workflow."""
import atexit
import builtins
import importlib.util
import operator
import os
from pathlib import Path
import shutil
import signal
import subprocess
import sys
import tempfile
import threading
import time

_HERE = Path(__file__).resolve().parent
_MAKE_TEMP = tempfile.mkdtemp
_WAITPID = os.waitpid
_MONOTONIC = time.monotonic


def _module(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    value = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(value)
    return value


_host = _module('desktop_workflow_transport', _HERE.parents[1] / 'build-support/native_host.py')
_wire = _module('desktop_workflow_values', _HERE.parents[1] / 'build-support/android/_boot_native.py')


class _Process(subprocess.Popen):
    def _try_wait(self, flags):
        try:
            return _WAITPID(self.pid, flags)
        except ChildProcessError:
            return self.pid, 0

    def _wait(self, timeout):
        if timeout is None:
            return super()._wait(timeout)
        deadline = _MONOTONIC() + timeout
        pause = threading.Event()
        while self.poll() is None:
            remaining = deadline - _MONOTONIC()
            if remaining <= 0:
                raise subprocess.TimeoutExpired(self.args, timeout)
            pause.wait(min(remaining, 0.05))
        return self.returncode


class _Controller(_host.Controller):
    def executable(self):
        with self.lock:
            if self.binary is None:
                override = os.environ.get(self.override)
                if override is not None:
                    self.binary = override
                else:
                    directory = _MAKE_TEMP(prefix='vinix-perf-workflow-')
                    try:
                        binary = str(Path(directory) / 'query')
                        command = [str(_HERE.parents[1] / 'build-support/run-v-tool.sh'),
                                   str(self.source), self.install, binary]
                        with _Process(command, stdout=subprocess.DEVNULL, env=os.environ) as child:
                            try:
                                status = child.wait()
                            except BaseException:
                                previous = signal.signal(signal.SIGINT, signal.SIG_IGN) if threading.current_thread() is threading.main_thread() else None
                                try:
                                    child.kill()
                                    child.wait()
                                finally:
                                    if previous is not None:
                                        signal.signal(signal.SIGINT, previous)
                                raise
                            if status:
                                raise subprocess.CalledProcessError(status, command)
                    except BaseException:
                        shutil.rmtree(directory)
                        raise
                    atexit.register(shutil.rmtree, directory)
                    self.binary = binary
            return self.binary


_controller = _Controller(_HERE / 'runner-query.v', 'VINIX_PERF_RUN_QUERY', process=lambda *args, **options: _Process(*args, start_new_session=True, **options))


def _snapshot(value):
    if isinstance(value, Path):
        return str(value)
    if isinstance(value, (list, tuple)):
        return [_snapshot(item) for item in value]
    return value


def _arguments(items):
    return [Path(value) if kind == 'path' else bytes.fromhex(value) if kind == 'bytes' else value
            for kind, value in items]


def _exit(manager, row, errors):
    if row is None:
        manager.__exit__(None, None, None)
        return False
    error = errors[row['binding_error']] if 'binding_error' in row else getattr(builtins, row['kind'])(row['message'])
    traceback = error.__traceback__
    try:
        raise error.with_traceback(traceback)
    except BaseException:
        try:
            return bool(manager.__exit__(type(error), error, traceback))
        finally:
            error.__traceback__ = traceback


def _primitive(operation, row, context, owners):
    args = _arguments(row.get('arguments', []))
    options = row.get('options', {})
    if operation == 'constant':
        return _snapshot(context[row['name']])
    if operation == 'argument':
        return _snapshot(getattr(owners['arguments'], row['name']))
    if operation == 'parser_error':
        if row.get('error') is not None:
            error = owners['errors'][row['error']['binding_error']]
            traceback = error.__traceback__
            try:
                raise error.with_traceback(traceback)
            except BaseException:
                try:
                    return owners['parser'].error(row['message'])
                finally:
                    error.__traceback__ = traceback
        return owners['parser'].error(row['message'])
    if operation == 'invoke':
        provider = context[row['module']] if row.get('module') else context
        function = getattr(provider, row['name']) if row.get('module') else provider[row['name']]
        result = function(*args, **options)
        if not row.get('module') and row['name'] == 'close_guest_fd' and 'guest' in owners:
            owners['guest']['closed'] = True
        return _snapshot(result)
    if operation == 'path':
        value = getattr(Path(row['path']), row['name'])
        return _snapshot(value(*args, **options) if callable(value) else value)
    if operation == 'join':
        return str(Path(row['parent']) / row['child'])
    if operation == 'python_version':
        return list(context['sys'].version_info[:2])
    if operation == 'sys_executable':
        return context['sys'].executable
    if operation == 'environ':
        return context['os'].environ.copy()
    if operation == 'strip':
        return row['value'].strip()
    if operation == 'operator':
        return getattr(operator, row['name'])(*args)
    if operation == 'str':
        return str(row['value'])
    if operation == 'print':
        return context.get('print', builtins.print)(row['message'], **({'file': context['sys'].stderr} if row.get('stderr') else options))
    if operation == 'hash':
        return context['hashlib'].sha256(row['value'].encode()).hexdigest()
    if operation == 'enter':
        manager = context[row['name']](*args, **options) if row['name'] != 'open' else Path(row['path']).open(*args, **options)
        entered = manager.__enter__()
        ident = str(id(manager))
        owners[ident] = (manager, entered)
        return {'id': ident, 'value': _snapshot(entered) if row['name'] != 'open' else None}
    if operation == 'exit':
        manager, _ = owners.pop(row['id'])
        return _exit(manager, row['error'], owners['errors'])
    if operation == 'read':
        return owners[row['id']][1].read(row['size']).hex()
    if operation == 'stat':
        return Path(row['path']).stat().st_size
    if operation == 'iterdir':
        return [str(value) for value in sorted(Path(row['path']).iterdir())]
    if operation == 'pointer':
        owners['pointer'] = context['Pointer'](row['path'])
        return None
    if operation == 'fork':
        pid, master = context['pty'].fork()
        if pid == 0:
            try:
                context['os'].chdir(Path(row['root']))
                context['os'].execve(row['command'][0], row['command'], row['environment'])
            finally:
                context['os']._exit(1)
        owners['guest'] = {'pid': pid, 'master': master, 'stopped': False, 'closed': False}
        owners['console'] = context['Console'](master)
        return [pid, master]
    if operation == 'line':
        try:
            return {'line': owners['console'].lines.get(timeout=row['timeout']).hex()}
        except context['queue'].Empty:
            return {'empty': True, 'closed': owners['console'].closed.is_set()}
    if operation == 'drive':
        driver = context['threading'].Thread(target=owners['pointer'].drive, daemon=True, args=(row['scenario'], float(row['seconds'])))
        owners['driver'] = driver
        driver.start()
        return None
    if operation == 'screendump':
        return owners['pointer'].screendump(Path(row['path']))
    if operation == 'stop':
        result = context['stop_child'](row['pid'], owners['console'])
        owners['guest']['stopped'] = True
        return result
    if operation == 'join_console':
        return owners['console'].thread.join(timeout=row['timeout'])
    if operation == 'transcript':
        return {'closed': owners['console'].closed.is_set(), 'data': bytes(owners['console'].transcript).hex()}
    if operation == 'match':
        found = context[row['name']].search(bytes.fromhex(row['data']))
        return [value.decode() for value in found.groups()] if found else None
    if operation == 'bytes_strip':
        return bytes.fromhex(row['data']).strip().hex()
    if operation == 'write_bytes':
        return Path(row['path']).write_bytes(bytes.fromhex(row['data']))
    raise RuntimeError('unknown desktop library primitive: ' + operation)


def _retire_contexts(managers):
    if managers:
        manager = managers.pop()
        try:
            manager.__exit__(*sys.exc_info())
        finally:
            _retire_contexts(managers)


def _retire_guest(context, owners):
    guest = owners.get('guest')
    if guest is None or owners.get('completed'):
        return
    console = owners.get('console')
    try:
        if not guest['stopped']:
            if console is not None:
                context['stop_child'](guest['pid'], console)
            else:
                try:
                    context['os'].killpg(guest['pid'], context['signal'].SIGKILL)
                except (ProcessLookupError, PermissionError):
                    pass
                try:
                    context['os'].waitpid(guest['pid'], 0)
                except ChildProcessError:
                    pass
    finally:
        try:
            if console is not None:
                console.thread.join(timeout=2)
        finally:
            try:
                if not guest['closed']:
                    context['close_guest_fd'](guest['master'])
            finally:
                if console is not None:
                    console.thread.join(timeout=1)


def call(operation, arguments, context, *, parser=None, options=None):
    errors = []
    owners = {'errors': errors, 'arguments': options, 'parser': parser}
    def cleanup():
        try:
            _retire_guest(context, owners)
        finally:
            _retire_contexts([value[0] for value in owners.values() if isinstance(value, tuple)])
    def unpack(value):
        row = _wire._unpack(value)
        if 'callback' not in row:
            owners['completed'] = True
        return row
    return _controller.call({'operation': operation, 'arguments': arguments},
        lambda operation, row: _primitive(operation, row, context, owners),
        pack=_wire._pack, unpack=unpack,
        exception=lambda row: getattr(builtins, row['kind'])(row['message']),
        cleanup=cleanup, errors=errors,
        error_fields=lambda error: {'dictionary_error': isinstance(error, (OSError, ValueError))})
