#!/usr/bin/env python3
"""Check cohort coverage/grace; optionally reject the reproduced slabinfo leak."""
import argparse
from pathlib import Path
import re
import importlib.util as _loader
import sys as _sys
_namespace, _frame = globals, _sys._getframe
_LITERAL_CACHE = {}
_SLOT_KEYS = {name: _sys.intern(name) for name in ('join','count','findall','search','splitlines','strip','startswith','get','items','group')}
_ATTRIBUTE, _TRUTH, _ITER = getattr, bool, iter
_spec = _loader.spec_from_file_location('churn_check_binding', Path(__file__).with_name('_native.py'))
_library = _loader.module_from_spec(_spec)
_spec.loader.exec_module(_library)


def _native(operation, *arguments):
    try:
        return _library.call(operation, _namespace(), _frame(1).f_builtins, *arguments)
    finally:
        arguments = None


def _tuple(*items):
    return (*items,)


def _raise(error):
    try:
        raise error
    finally:
        error = None


def _FORMAT(value):
    try:
        return f"{value}"
    finally:
        value = None


_PREFIXES = ("CHURN MEASURE ", "CHURN GRACE ", "CHURN CLASS ", "CHURN WORK ", "PERF-SITE ")


def _cohort_names(mode):
    return {"exec": ("true", "sleep", "curl", "awk"), "slabinfo": ("slabinfo",),
            "waits": ("idle_control", "nanosleep", "clock_nanosleep", "fork_reap"),
            "directories": ("mkdir_tmpfs", "mkdir_ext2"), "pipes": ("pipe",),
            "sampling": ("sampling",), "select": ("select_ready", "pselect_ready")}[mode]


def _failures(cell):
    return (marker in cell[0] for marker in
            ("PROCESS CHURN: FAIL", "KERNEL PANIC", "FATAL EXCEPTION", "ERROR:"))


def _expected(names):
    return {(name, cohort) for name in names for cohort in (1, 2, 3)}


def _zero(names):
    return {(name, 0) for name in names}


def _classes_outside(classes, expected):
    return (key[:2] not in expected for key in classes)


def _short_work(work):
    return (work[(name, cohort)] < 300_000_000 for name in ("nanosleep", "clock_nanosleep")
            for cohort in (1, 2, 3))


def _unsettled(last):
    return (last[key] != 0 for key in ("slab_delta_kib", "large_pages_delta"))


def _class_key(identity, size):
    return (*identity, size)


def _small_mode(mode):
    return mode in ("waits", "select")


def _identity(value):
    return value


def _pin_scope(pins, scope):
    try:
        pins.insert(0, scope)
    finally:
        pins = scope = None


def fields(line):
    scope = {'line': line, 'result': None, 'key': None, 'value': None}
    line = None
    try:
        return _native('fields', scope)
    finally:
        scope = None


_ORDER = ('source','mode','flat_slabinfo','flat_small','names','measurements',
          'grace','live','classes','filesystems','starts','done','raw','row',
          'identity','key','count','size','match','expected_grace','cohort',
          'checked','marker','name','maximum','expected','last','line','work')


def inspect(source, mode, flat_slabinfo, flat_small=False):
    scope = {name: None for name in _ORDER}
    scope.update(source=source, mode=mode, flat_slabinfo=flat_slabinfo,
                 flat_small=flat_small)
    source = mode = flat_slabinfo = flat_small = None
    try:
        return _native('inspect', scope)
    finally:
        scope = None


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("log", type=Path)
    parser.add_argument("--mode", choices=("exec", "slabinfo", "waits", "directories", "pipes", "sampling", "select"), default="exec")
    parser.add_argument("--expect-flat-slabinfo", action="store_true")
    parser.add_argument("--expect-flat-small", action="store_true")
    args = parser.parse_args()
    try:
        measurements, live = inspect(args.log.read_text(errors="replace"), args.mode,
                                     args.expect_flat_slabinfo, args.expect_flat_small)
    except (ValueError, KeyError) as error:
        parser.exit(1, f"FAIL: {error}\n")
    for (program, cohort), row in measurements.items():
        print(f"{program} cohort={cohort}: used={row['used_delta_kib']} KiB, "
              f"slab={row['slab_delta_kib']} KiB, tracked_live={live[(program, cohort)]}")
    print("PASS: complete cohorts, real grace, intact tracking" +
          (", slabinfo descriptor counts flat" if args.expect_flat_slabinfo else ""))


if __name__ == "__main__":
    main()
