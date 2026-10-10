"""Synchronous stdlib bindings for the native Android runner policy."""
import atexit
import builtins
import ctypes
import operator
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
_host_spec = importlib.util.spec_from_file_location('android_runner_transport', _HERE.parents[1] / 'build-support/native_host.py')
_host = importlib.util.module_from_spec(_host_spec)
_host_spec.loader.exec_module(_host)


_LIBRARY = None
_TAKE = None
_LIBRARY_LOCK = threading.Lock()
_boot_pair = _wire._boot_pair
_LIBRARY_SUPPORT = (os.environ, Path, str, tempfile.mkdtemp, shutil.rmtree,
                    subprocess.run, subprocess.DEVNULL, sys.executable,
                    sys.platform, ctypes.PyDLL, atexit.register, ctypes.c_char_p,
                    ctypes.py_object, ctypes.c_int, globals, BaseException)


def _entry(operation, *arguments):
    global _LIBRARY, _TAKE
    (environ, library_Path, text, make, remove, run, quiet, executable, platform,
     load, retire, char_pointer, python_object, c_int, namespace, error_type) = _LIBRARY_SUPPORT
    with _LIBRARY_LOCK:
        if _LIBRARY is None:
            library_path = environ.get('VINIX_ANDROID_RUN_LIBRARY')
            if library_path is None:
                directory = make(prefix='vinix-android-run-sdk-')
                try:
                    library_path = text(library_Path(directory) / ('library.dylib' if platform == 'darwin' else 'library.so'))
                    run([text(_HERE.parents[1] / 'build-support/build-v-host-library.sh'),
                                    text(_HERE / 'run_sdk_library.v'), library_path,
                                    '-d', 'cpython_boot', '-d', 'cpython_android_run', '-d', 'use_bundled_libgc'],
                                   check=True, stdout=quiet,
                                   env={**environ, 'VINIX_HOST_PYTHON': executable})
                    library = load(library_path)
                except error_type:
                    remove(directory)
                    raise
                retire(remove, directory)
            else:
                library = load(library_path)
            target = library.vinix_android_run_sdk
            target.argtypes = (char_pointer, python_object, python_object, python_object)
            target.restype = python_object
            take = library.vinix_android_run_take
            take.argtypes = (python_object, c_int)
            take.restype = python_object
            _TAKE = take
            _LIBRARY = target
    pins = []
    try:
        return _LIBRARY(operation, namespace(), arguments, pins)
    finally:
        arguments = None


def _run_take(token, index):
    try:
        return _TAKE(token, index)
    finally:
        token = None


def _run_apply(token):
    try:
        return _run_take(token, 0)(*_run_take(token, 1), **_run_take(token, 2))
    finally:
        token = None


def _run_print(token):
    try:
        return _run_take(token, 0)(_run_take(token, 1), file=_run_take(token, 2), **_run_take(token, 3))
    finally:
        token = None


def _run_callback(operation, context, resources):
    return lambda operation=operation: call(operation, {}, context, args=resources['args'], group=resources['group'])



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
    with _LOCK:
        return _install_binary()


def _install_binary():
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
        replay = error.__traceback__
        error.__traceback__ = traceback
        try:
            return bool(owner.__exit__(*exception))
        finally:
            if error.__traceback__ is replay:
                error.__traceback__ = traceback


def _arguments(items, context, resources):
    return _entry(b"arguments", items, context, resources)


def _invoke(row, context, resources):
    return _entry(b"invoke", row, context, resources)


def _retire_contexts(contexts):
    if contexts:
        manager = contexts.pop()
        try:
            if manager is not None:
                manager[0].__exit__(*sys.exc_info())
        finally:
            _retire_contexts(contexts)


def _primitive(operation, row, context, resources):
    path = Path(row['path']) if 'path' in row else None
    selected, native = _entry(b"select", operation)
    if selected == 'invoke':
        return _snapshot(_invoke(row, context, resources))
    if selected == 'error_attribute':
        return _snapshot(getattr(resources['errors'][row['error']['binding_error']], row['name']))
    if selected == 'group_get':
        return _snapshot(resources['group'][row['name']])
    if selected == 'group_method':
        return _snapshot(getattr(resources['group'][row['name']], row['method'])(*_arguments(row.get('arguments', []), context, resources), **row.get('options', {})))
    if selected == 'path':
        method = row['method']
        if method in ('name', 'parent', 'suffix', 'parts'):
            result = getattr(path, method)
        else:
            result = getattr(path, method)(*row.get('arguments', []), **row.get('options', {}))
        return _snapshot(result)
    if selected == 'attribute':
        return _snapshot(getattr(resources['args'], row['name']))
    if selected == 'function':
        result = context[row['name']](*_arguments(row.get('arguments', []), context, resources),
                                     *(getattr(resources['args'], row['star_attribute']) if 'star_attribute' in row else []),
                                     **row.get('options', {}))
        return _snapshot(result)
    if selected == 'api':
        result = context[row['name']](resources['args'], *[Path(item) if kind == 'path' else item
                                                         for kind, item in row.get('arguments', [])])
        return {'value': _snapshot(result), 'args': _snapshot(vars(resources['args']))}
    if native:
        return _entry(b"primitive", selected, operation, row, context, resources, path)
    if selected == 'group_bytes':
        return bytes(resources['group'][row['name']][slice(*row.get('slice', [None, None]))]).hex()
    if selected == 'thread_start':
        worker = context['threading'].Thread(target=resources['workers'][row['worker']], daemon=True)
        resources['group'][row['name']] = worker
        return worker.start()
    if selected == 'enter_context':
        manager = _invoke(row, context, resources)
        entered = manager.__enter__()
        ident = len(resources['contexts'])
        resources['contexts'].append((manager, entered))
        return ident
    if selected == 'exit_context':
        manager, _ = resources['contexts'][row['id']]
        resources['contexts'][row['id']] = None
        return _exit(manager, _exception(row.get('error'), context, resources))
    if selected == 'load_source':
        spec = context['importlib'].util.spec_from_file_location(row['module'], Path(row['source']))
        module = context['importlib'].util.module_from_spec(spec)
        spec.loader.exec_module(module)
        resources['modules'][row['module']] = module
        return None
    if selected == 'slice':
        return _snapshot(row['value'][row['start']:row['stop']])
    if selected == 'python_version':
        return list(sys.version_info[:2])
    if selected == 'raise':
        raise getattr(builtins, row['kind'])(*row['arguments'])
    if selected == 'exception_is':
        return isinstance(resources['errors'][row['error']['binding_error']],
                          tuple(getattr(builtins, name) for name in row['kinds']))
    if selected == 'join':
        result = Path(row['parts'][0])
        for item in row['parts'][1:]:
            result /= item
        return str(result)
    if selected == 'stat':
        result = path.stat()
        return {name: getattr(result, name) for name in row['fields']}
    if selected in ('rmtree', 'copy2'):
        return _snapshot(getattr(context['shutil'], operation)(*[Path(item) for item in row['arguments']]))
    if selected in ('link', 'readlink'):
        return getattr(context['os'], operation)(*[Path(item) for item in row['arguments']])
    if selected == 'inode_contains':
        return tuple(row['key']) in resources['inodes']
    if selected == 'inode_reset':
        resources['inodes'] = {}
        return None
    if selected == 'inode_link':
        return context['os'].link(resources['inodes'][tuple(row['key'])], path)
    if selected == 'inode_set':
        resources['inodes'][tuple(row['key'])] = path
        return None
    if selected == 'open_read':
        stream = path.open('rb')
        entered = stream.__enter__()
        ident = len(resources['handles'])
        resources['handles'].append((stream, entered))
        return ident
    if selected == 'exit_handle':
        stream, _ = resources['handles'][row['id']]
        resources['handles'][row['id']] = None
        return _exit(stream, _exception(row.get('error'), context, resources))
    if selected == 'roblox_validate':
        spec = context['importlib'].util.spec_from_file_location('vinix_roblox_builder', Path(row['source']))
        assert spec and spec.loader
        module = context['importlib'].util.module_from_spec(spec)
        spec.loader.exec_module(module)
        return module.validate_stage(Path(row['staging']), Path(row['runtime']))
    if selected == 'tar_open':
        archive = context['tarfile'].open(path, row['mode'], **row.get('options', {}))
        entered = archive.__enter__()
        ident = len(resources['archives'])
        resources['archives'].append((archive, entered))
        resources['iterators'][ident] = iter(entered)
        return ident
    if selected == 'tar_next':
        member = next(resources['iterators'][row['id']], None)
        return None if member is None else member.name
    if selected == 'tar_extract':
        resources['archives'][row['id']][1].extractall(path)
        return None
    if selected == 'tar_info':
        info = resources['archives'][row['id']][1].gettarinfo(str(path), arcname=row['name'])
        ident = len(resources['infos'])
        resources['infos'].append(info)
        return {'id': ident, 'regular': info.isreg(), 'size': info.size, 'mode': info.mode}
    if selected == 'tar_add':
        archive, info = resources['archives'][row['id']][1], resources['infos'][row['info']]
        for key, value in row.get('fields', {}).items():
            setattr(info, key, value.encode('ascii') if key == 'type' else value)
        if path is None:
            archive.addfile(info)
        else:
            with path.open('rb') as stream:
                archive.addfile(info, stream)
        return None
    if selected == 'tar_exit':
        archive, _ = resources['archives'][row['id']]
        resources['archives'][row['id']] = None
        resources['iterators'].pop(row['id'])
        return _exit(archive, _exception(row.get('error'), context, resources))
    raise RuntimeError('unknown Android runner primitive ' + operation)


class _Transport(_host.Controller):
    def executable(self):
        return _binary()


_transport = _Transport(_HERE / 'run-query.v', 'VINIX_ANDROID_RUN_QUERY',
                        process=lambda *args, **options: _Controller(*args, start_new_session=True, **options),
                        eof_message='native Android runner ended before returning a result')


def call(operation, arguments, context, args=None, parser=None, inodes=None, observed=None, group=None, workers=None):
    resources = {'args': args, 'parser': parser, 'archives': [], 'iterators': {}, 'infos': [], 'handles': [],
                 'inodes': {} if inodes is None else inodes, 'contexts': [], 'modules': {}, 'observed': observed, 'group': group, 'workers': workers}
    errors = []
    resources['errors'] = errors
    def cleanup():
        try:
            for handle in resources['handles']:
                if handle is not None:
                    handle[0].__exit__(*sys.exc_info())
        finally:
            try:
                for archive in resources['archives']:
                    if archive is not None:
                        archive[0].__exit__(*sys.exc_info())
            finally:
                _retire_contexts(resources['contexts'])
    return _transport.call({'operation': operation, 'arguments': _snapshot(arguments),
                            'root': str(context['ROOT'])},
        lambda operation, row: _primitive(operation, row, context, resources),
        pack=_wire._pack, unpack=_wire._unpack,
        exception=lambda row: _exception(row, context, resources)[1],
        cleanup=cleanup, errors=errors)
