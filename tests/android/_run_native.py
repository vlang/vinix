"""Synchronous stdlib bindings for the native Android runner policy."""
import atexit
import importlib
import importlib.util
import json
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
_BINARY = None
_LOCK = threading.RLock()
_WAITPID = os.waitpid
_MONOTONIC = time.monotonic
_spec = importlib.util.spec_from_file_location('android_runner_wire', _HERE.parents[1] / 'build-support/android/_boot_native.py')
_wire = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_wire)


class _Controller(subprocess.Popen):
    def _try_wait(self, wait_flags):
        try:
            return _WAITPID(self.pid, wait_flags)
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


def _binary():
    global _BINARY
    if _BINARY is None:
        override = os.environ.get('VINIX_ANDROID_RUN_QUERY')
        if override:
            _BINARY = override
        else:
            owner = tempfile.TemporaryDirectory(prefix='vinix-android-run-controller-')
            try:
                binary = str(Path(owner.name) / 'query')
                command = [str(_HERE.parents[1] / 'build-support/run-v-tool.sh'),
                           str(_HERE / 'run-query.v'), '--install-query', binary]
                with _Controller(command, stdout=subprocess.DEVNULL, env=os.environ) as child:
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
                owner.cleanup()
                raise
            atexit.register(owner.cleanup)
            _BINARY = binary
    return _BINARY


def _snapshot(value):
    if isinstance(value, Path):
        return str(value)
    if isinstance(value, (list, tuple, set)):
        return [_snapshot(item) for item in value]
    if isinstance(value, dict):
        return {key: _snapshot(item) for key, item in value.items()}
    return value


def _exception(row, context, resources):
    if row is None:
        return (None, None, None)
    if 'binding_error' in row:
        error = resources['errors'][row['binding_error']]
    elif 'message' in row:
        error = {'SystemExit': SystemExit, 'RuntimeError': RuntimeError}[row['kind']](row['message'])
    else:
        try:
            context['_native']._response(row)
        except BaseException as error:
            return type(error), error, error.__traceback__
    return type(error), error, error.__traceback__


def _exit(owner, exception):
    if exception[1] is None:
        owner.__exit__(*exception)
        return False
    error, traceback = exception[1:]
    try:
        raise error.with_traceback(traceback)
    except BaseException:
        try:
            return bool(owner.__exit__(*exception))
        finally:
            error.__traceback__ = traceback


def _primitive(operation, row, context, resources):
    path = Path(row['path']) if 'path' in row else None
    if operation == 'path':
        method = row['method']
        if method in ('name', 'parent', 'suffix', 'parts'):
            result = getattr(path, method)
        else:
            result = getattr(path, method)(*row.get('arguments', []), **row.get('options', {}))
        return _snapshot(result)
    if operation in ('iterdir', 'glob', 'rglob'):
        return [str(item) for item in getattr(path, operation)(*row.get('arguments', []))]
    if operation == 'join':
        result = Path(row['parts'][0])
        for item in row['parts'][1:]:
            result /= item
        return str(result)
    if operation == 'stat':
        result = path.stat()
        return {name: getattr(result, name) for name in row['fields']}
    if operation in ('rmtree', 'copy2'):
        return _snapshot(getattr(context['shutil'], operation)(*[Path(item) for item in row['arguments']]))
    if operation in ('link', 'readlink'):
        return getattr(context['os'], operation)(*[Path(item) for item in row['arguments']])
    if operation == 'inode_contains':
        return tuple(row['key']) in resources['inodes']
    if operation == 'inode_reset':
        resources['inodes'] = {}
        return None
    if operation == 'inode_link':
        return context['os'].link(resources['inodes'][tuple(row['key'])], path)
    if operation == 'inode_set':
        resources['inodes'][tuple(row['key'])] = path
        return None
    if operation == 'length':
        return len(row['data'])
    if operation == 'read_bytes':
        return path.read_bytes().hex()
    if operation == 'open_read':
        stream = path.open('rb')
        entered = stream.__enter__()
        ident = len(resources['handles'])
        resources['handles'].append((stream, entered))
        return ident
    if operation == 'read_handle':
        return resources['handles'][row['id']][1].read(row['limit']).hex()
    if operation == 'exit_handle':
        stream, _ = resources['handles'][row['id']]
        resources['handles'][row['id']] = None
        return _exit(stream, _exception(row.get('error'), context, resources))
    if operation == 'json_loads':
        return context['json'].loads(row['data'])
    if operation == 'json_dumps':
        return context['json'].dumps(row['data'], **row.get('options', {}))
    if operation == 'bytes_decode':
        return bytes.fromhex(row['data']).decode(**row.get('options', {}))
    if operation == 'bytes_int':
        return int(bytes.fromhex(row['data']))
    if operation == 'type_name':
        return type(row['value']).__name__
    if operation == 'attribute':
        return _snapshot(getattr(resources['args'], row['name']))
    if operation == 'attribute_bytes':
        return getattr(resources['args'], row['name']).read_bytes().hex()
    if operation == 'str_attribute':
        value = getattr(resources['args'], row['name'])
        return str(value[row['index']] if 'index' in row else value)
    if operation == 'function':
        result = context[row['name']](*[Path(item) if kind == 'path' else item
                                        for kind, item in row.get('arguments', [])])
        return _snapshot(result)
    if operation == 'run':
        return context['subprocess'].run(row['arguments'], check=True)
    if operation == 'which':
        return context['shutil'].which(row['name'])
    if operation == 'environ':
        return context['os'].environ.copy()
    if operation == 'platform':
        return context['platform'].system()
    if operation == 'strip':
        return row['data'].strip()
    if operation == 'import':
        importlib.import_module(row['name'])
        return None
    if operation == 'api':
        result = context[row['name']](resources['args'], *[Path(item) if kind == 'path' else item
                                                         for kind, item in row.get('arguments', [])])
        return {'value': _snapshot(result), 'args': _snapshot(vars(resources['args']))}
    if operation == 'args_set':
        value = row['value']
        if row['kind'] == 'path':
            value = Path(value) if value is not None else None
        elif row['kind'] == 'paths':
            value = [Path(item) for item in value]
        setattr(resources['args'], row['name'], value)
        return None
    if operation == 'args_item':
        getattr(resources['args'], row['name'])[row['key']] = row['value']
        return None
    if operation == 'args_append':
        getattr(resources['args'], row['name']).append(row['value'])
        return None
    if operation == 'parser_error':
        return resources['parser'].error(row['message'])
    if operation == 'print':
        print(row['data'], file=context['sys'].stderr if row.get('stderr') else context['sys'].stdout)
        return None
    if operation == 'roblox_validate':
        spec = context['importlib'].util.spec_from_file_location('vinix_roblox_builder', Path(row['source']))
        assert spec and spec.loader
        module = context['importlib'].util.module_from_spec(spec)
        spec.loader.exec_module(module)
        return module.validate_stage(Path(row['staging']), Path(row['runtime']))
    if operation == 'tar_open':
        archive = context['tarfile'].open(path, row['mode'], **row.get('options', {}))
        entered = archive.__enter__()
        ident = len(resources['archives'])
        resources['archives'].append((archive, entered))
        resources['iterators'][ident] = iter(entered)
        return ident
    if operation == 'tar_next':
        member = next(resources['iterators'][row['id']], None)
        return None if member is None else member.name
    if operation == 'tar_extract':
        resources['archives'][row['id']][1].extractall(path)
        return None
    if operation == 'tar_info':
        info = resources['archives'][row['id']][1].gettarinfo(str(path), arcname=row['name'])
        ident = len(resources['infos'])
        resources['infos'].append(info)
        return {'id': ident, 'regular': info.isreg(), 'size': info.size, 'mode': info.mode}
    if operation == 'tar_add':
        archive, info = resources['archives'][row['id']][1], resources['infos'][row['info']]
        for key, value in row.get('fields', {}).items():
            setattr(info, key, value.encode('ascii') if key == 'type' else value)
        if path is None:
            archive.addfile(info)
        else:
            with path.open('rb') as stream:
                archive.addfile(info, stream)
        return None
    if operation == 'tar_exit':
        archive, _ = resources['archives'][row['id']]
        resources['archives'][row['id']] = None
        resources['iterators'].pop(row['id'])
        return _exit(archive, _exception(row.get('error'), context, resources))
    raise RuntimeError('unknown Android runner primitive ' + operation)


def call(operation, arguments, context, args=None, parser=None, inodes=None):
    with _LOCK:
        resources = {'args': args, 'parser': parser, 'archives': [], 'iterators': {}, 'infos': [], 'handles': [],
                     'inodes': {} if inodes is None else inodes}
        errors = []
        resources['errors'] = errors
        process = _Controller([_binary()], stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                              text=True, encoding='utf-8', env=os.environ)
        try:
            process.stdin.write(json.dumps(_wire._pack({'operation': operation, 'arguments': _snapshot(arguments),
                                                       'root': str(context['ROOT'])})) + '\n')
            process.stdin.flush()
            while True:
                line = process.stdout.readline()
                if not line:
                    raise RuntimeError('native Android runner ended before returning a result')
                row = _wire._unpack(json.loads(line))
                if 'callback' not in row:
                    if 'error' in row:
                        error = row['error']
                        if 'binding_error' in error:
                            raise errors[error['binding_error']]
                        if 'kind' in error and 'message' in error:
                            raise {'SystemExit': SystemExit, 'RuntimeError': RuntimeError}[error['kind']](error['message'])
                        context['_native']._response(error)
                    return row['value']
                try:
                    response = {'value': _primitive(row['callback'], row['arguments'], context, resources)}
                except BaseException as error:
                    errors.append(error)
                    response = {'error': {'binding_error': len(errors)-1, 'kind': type(error).__name__, 'message': str(error)}}
                process.stdin.write(json.dumps(_wire._pack(response)) + '\n')
                process.stdin.flush()
        finally:
            previous = None
            if threading.current_thread() is threading.main_thread():
                previous = signal.signal(signal.SIGINT, signal.SIG_IGN)
            try:
                try:
                    try:
                        process.stdin.close()
                    finally:
                        try:
                            process.wait(timeout=5)
                        except subprocess.TimeoutExpired:
                            process.kill()
                            process.wait()
                        except BaseException:
                            process.kill()
                            process.wait()
                            raise
                finally:
                    try:
                        process.stdout.close()
                    finally:
                        try:
                            for handle in resources['handles']:
                                if handle is not None:
                                    handle[0].__exit__(*sys.exc_info())
                        finally:
                            for archive in resources['archives']:
                                if archive is not None:
                                    archive[0].__exit__(*sys.exc_info())
            finally:
                if previous is not None:
                    signal.signal(signal.SIGINT, previous)
