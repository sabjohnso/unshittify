---
description: Compile and run C++ code with the Clang/GCC sanitizers — AddressSanitizer (ASan), UndefinedBehaviorSanitizer (UBSan), ThreadSanitizer (TSan), MemorySanitizer (MSan), and LeakSanitizer (LSan) — including which sanitizers can be combined, the flags each needs, runtime options, CMake integration, and how to read a sanitizer's crash report. Use when the user asks to build with sanitizers, diagnose a memory error, data race, or undefined-behavior bug, or interpret ASan/UBSan/TSan output.
---

# Compiling and running with sanitizers

Sanitizers are compiler-inserted runtime checks: the compiler instruments
every memory access, arithmetic operation, or thread synchronization point
and aborts with a detailed report the moment a check fails, instead of
letting the bug corrupt memory silently or produce a data race that only
shows up under load. They trade runtime overhead (roughly 2x for ASan, 5x
or more for MSan/TSan) for precise, first-failure diagnostics — always
prefer a sanitizer over guessing from a crash's symptoms.

## Which sanitizer for which bug

| Sanitizer                          | Flag                                    | Catches                                                                                                                                         |
|------------------------------------|-----------------------------------------|-------------------------------------------------------------------------------------------------------------------------------------------------|
| AddressSanitizer (ASan)            | `-fsanitize=address`                    | heap/stack/global buffer overflow, use-after-free, use-after-return, double-free                                                                |
| UndefinedBehaviorSanitizer (UBSan) | `-fsanitize=undefined`                  | signed integer overflow, null-pointer dereference, misaligned access, invalid enum values, out-of-bounds array index (with `-fsanitize=bounds`) |
| ThreadSanitizer (TSan)             | `-fsanitize=thread`                     | data races, lock-order inversions                                                                                                               |
| MemorySanitizer (MSan)             | `-fsanitize=memory`                     | reads of uninitialized memory (Clang only)                                                                                                      |
| LeakSanitizer (LSan)               | `-fsanitize=leak`, or bundled into ASan | memory leaks                                                                                                                                    |

## Compiling

Build with debug info and low optimization so reports show real source
locations and variable names, and keep a frame pointer so stack traces are
accurate:

```sh
clang++ -g -O1 -fno-omit-frame-pointer -fsanitize=address,undefined -o app app.cpp
```

`-fsanitize=address` links in LeakSanitizer automatically on Linux, so a
plain ASan build already reports leaks at process exit; add
`-fsanitize=leak` on its own only when you want leak detection without the
rest of ASan's checks.

## Which sanitizers combine

- **ASan + UBSan** combine freely — this is the default pairing for day-to-day
  bug-hunting and costs one build.
- **TSan** cannot be combined with ASan or MSan; each instruments memory
  differently and the runtimes conflict. Build a separate TSan binary.
- **MSan** cannot be combined with ASan or TSan, and requires that
  *every* linked library — including the C++ standard library — be built
  with MSan instrumentation, or it reports false positives on uninstrumented
  code. It is the most expensive sanitizer to adopt for this reason.
- Build one sanitized binary per sanitizer family (`asan+ubsan`, `tsan`,
  `msan`) rather than trying to fit them into a single executable.

## Running and runtime options

Each sanitizer reads its own environment variable
(`ASAN_OPTIONS`, `UBSAN_OPTIONS`, `TSAN_OPTIONS`, `MSAN_OPTIONS`), a
colon-separated list of `key=value` pairs:

```sh
ASAN_OPTIONS=halt_on_error=0:detect_leaks=1 ./app
UBSAN_OPTIONS=print_stacktrace=1 ./app
TSAN_OPTIONS=halt_on_error=1 ./app
```

Common options worth setting:

- `halt_on_error=0` — keep running after the first error to collect every
  distinct failure in one run, instead of stopping at the first.
- `print_stacktrace=1` (UBSan) — print a stack trace, not just the source
  location of the failure.
- `suppressions=file` with `*_OPTIONS=suppressions=path/to/file` — silence
  known, unfixable reports (e.g. in a third-party library) by pattern.

## Reading a report

An ASan report names the error class, the access that triggered it, and
both the faulting stack trace and the allocation/free stack trace:

```
ERROR: AddressSanitizer: heap-use-after-free on address 0x...
READ of size 4 at 0x... thread T0
    #0 0x... in main app.cpp:12
freed by thread T0 here:
    #0 0x... in operator delete(void*)
    #1 0x... in main app.cpp:10
previously allocated by thread T0 here:
    #0 0x... in operator new(unsigned long)
    #1 0x... in main app.cpp:8
```

Read bottom-up within each stack: the innermost frame closest to `main` (or
the relevant call site) is where the bug actually lives; frames inside the
sanitizer runtime or `operator new`/`delete` are noise. If a report shows a
raw address instead of a symbol name, the binary is missing debug info or a
symbolizer (`llvm-symbolizer` for Clang, on `PATH` or pointed to via
`ASAN_SYMBOLIZER_PATH`) is not installed.

## CMake integration

Add the flags as both compile and link options — sanitizer runtimes must be
linked in, not just compiled in — scoped to a dedicated build type or target
rather than the whole project's default flags:

```cmake
option(ENABLE_ASAN "Build with AddressSanitizer + UBSan" OFF)
if(ENABLE_ASAN)
  add_compile_options(-fsanitize=address,undefined -fno-omit-frame-pointer -g -O1)
  add_link_options(-fsanitize=address,undefined)
endif()
```

Configure a separate build directory per sanitizer (`build-asan`,
`build-tsan`) so switching sanitizers is a directory switch, not a
reconfigure.

## Rules that prevent rework

- **Always build with `-g -O1` (or `-Og`), never `-O0` or `-O3`.** `-O0`
  is slow enough to make ASan/TSan overhead compound painfully on large
  test suites; `-O3`'s inlining and reordering can make stack traces point
  at the wrong line. `-O1`/`-Og` keeps traces accurate while still running
  fast enough to use in a normal test loop.
- **Never combine TSan or MSan with ASan.** The runtimes conflict; build a
  separate binary per sanitizer family instead of trying to save a build.
- **Set `halt_on_error=0` when hunting for every bug in a test suite,
  `halt_on_error=1` (the default) when bisecting one specific failure.**
  The former finds more in one run; the latter keeps a stack trace pinned
  to a single root cause.
- **Adopt MSan only when every dependency, including libc++/libstdc++, is
  MSan-instrumented.** A partial MSan build reports false positives on
  every uninstrumented call, which looks identical to a real bug until
  investigated.
