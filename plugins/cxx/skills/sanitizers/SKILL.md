---
description: Compile and run C++ code with the Clang and GCC sanitizers (AddressSanitizer (ASan), UndefinedBehaviorSanitizer (UBSan), ThreadSanitizer (TSan), MemorySanitizer (MSan), and LeakSanitizer (LSan)). Covers which sanitizers can combine, the flags that each one needs, the runtime options, the CMake integration, and how to read the crash report of a sanitizer. Use when the user asks you to build with sanitizers, to diagnose a memory error, a data race, or an undefined-behavior bug, or to interpret ASan, UBSan, or TSan output.
---

# Compile and run with sanitizers

Goal: pick the sanitizer that catches the bug at hand, build and run with the flags that it needs, and read its report down to the frame where the bug is. This is a reference to read at each of those points, not a procedure to run from start to end, so it has no numbered steps.

A sanitizer is a set of runtime checks that the compiler inserts. The
compiler instruments every memory access, arithmetic operation, or thread
synchronization point. It aborts with a detailed report the moment that a
check fails. The bug does not corrupt the memory with no message, and a data
race does not show up only under load. The sanitizers trade runtime overhead
(about 2x for ASan, 5x or more for MSan and TSan) for precise diagnostics at
the first failure. Always prefer a sanitizer over a guess from the symptoms
of a crash.

## Which sanitizer for which bug

| Sanitizer                          | Flag                                    | Catches                                                                                                                                         |
|------------------------------------|-----------------------------------------|-------------------------------------------------------------------------------------------------------------------------------------------------|
| AddressSanitizer (ASan)            | `-fsanitize=address`                    | heap, stack, or global buffer overflow, use after free, use after return, double free                                                          |
| UndefinedBehaviorSanitizer (UBSan) | `-fsanitize=undefined`                  | signed integer overflow, null-pointer dereference, misaligned access, invalid enum values, out-of-bounds array index (with `-fsanitize=bounds`) |
| ThreadSanitizer (TSan)             | `-fsanitize=thread`                     | data races, lock-order inversions                                                                                                               |
| MemorySanitizer (MSan)             | `-fsanitize=memory`                     | reads of uninitialized memory (Clang only)                                                                                                      |
| LeakSanitizer (LSan)               | `-fsanitize=leak`, or bundled into ASan | memory leaks                                                                                                                                    |

## The compile

Build with debug information and low optimization, so the reports show real
source locations and variable names. Keep a frame pointer, so the stack
traces are accurate:

```sh
clang++ -g -O1 -fno-omit-frame-pointer -fsanitize=address,undefined -o app app.cpp
```

`-fsanitize=address` links LeakSanitizer in automatically on Linux. So a
plain ASan build already reports the leaks at process exit. Add
`-fsanitize=leak` on its own only when you want leak detection without the
rest of the ASan checks.

## Which sanitizers combine

- **ASan + UBSan** combine freely. This is the default pair for the daily
  bug hunt, and it costs one build.
- **TSan** cannot combine with ASan or MSan. Each one instruments the memory
  differently, and the runtimes conflict. Build a separate TSan binary.
- **MSan** cannot combine with ASan or TSan. It requires that *every* linked
  library, with the C++ standard library, is built with MSan
  instrumentation. Otherwise it reports false positives on the code with no
  instrumentation. For this reason, it is the most expensive sanitizer to
  adopt.
- Build one sanitized binary per sanitizer family (`asan+ubsan`, `tsan`,
  `msan`). Do not try to fit them into a single executable.

## The run and the runtime options

Each sanitizer reads its own environment variable (`ASAN_OPTIONS`,
`UBSAN_OPTIONS`, `TSAN_OPTIONS`, `MSAN_OPTIONS`). The value is a list of
`key=value` pairs with colons between them:

```sh
ASAN_OPTIONS=halt_on_error=0:detect_leaks=1 ./app
UBSAN_OPTIONS=print_stacktrace=1 ./app
TSAN_OPTIONS=halt_on_error=1 ./app
```

Common options that are worth a set:

- `halt_on_error=0`. Continue after the first error, to collect every
  distinct failure in one run. Do not stop at the first one.
- `print_stacktrace=1` (UBSan). Print a stack trace, not only the source
  location of the failure.
- `suppressions=path/to/file`. Silence known reports that you cannot fix
  (for example in a third-party library) by pattern.

## How to read a report

An ASan report names the error class, the access that triggered it, the
faulting stack trace, and the stack trace of the allocation or the free:

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

Read each stack from the bottom up. The deepest frame in your own code (for
example `app.cpp:12`) is where the bug is. The frames inside the sanitizer
runtime or `operator new` and `delete` are noise. If a report shows a raw
address instead of a symbol name, the binary has no debug information, or no
symbolizer is installed (`llvm-symbolizer` for Clang, on `PATH` or named by
`ASAN_SYMBOLIZER_PATH`).

## The CMake integration

Add the flags as both compile options and link options. The sanitizer
runtimes must be linked in, not only compiled in. Limit the scope to a
dedicated build type or target, not to the default flags of the whole
project:

```cmake
option(ENABLE_ASAN "Build with AddressSanitizer + UBSan" OFF)
if(ENABLE_ASAN)
  add_compile_options(-fsanitize=address,undefined -fno-omit-frame-pointer -g -O1)
  add_link_options(-fsanitize=address,undefined)
endif()
```

Configure a separate build directory per sanitizer (`build-asan`,
`build-tsan`). Then a switch of the sanitizer is a switch of the directory,
not a new configure.

## Rules that prevent rework

- **Always build with `-g -O1` (or `-Og`), never with `-O0` or `-O3`.**
  `-O0` is so slow that the ASan or TSan overhead becomes painful on a large
  test suite. The inline expansion and the reorder of `-O3` can make a stack
  trace point at the wrong line. `-O1` or `-Og` keeps the traces accurate and
  runs fast enough for a normal test loop.
- **Never combine TSan or MSan with ASan.** The runtimes conflict. Build a
  separate binary per sanitizer family. Do not try to save a build.
- **Set `halt_on_error=0` when you hunt for every bug in a test suite. Set
  `halt_on_error=1` (the default) when you bisect one specific failure.** The
  first finds more in one run. The second keeps a stack trace pinned to a
  single root cause.
- **Adopt MSan only when every dependency, with libc++ or libstdc++, is
  MSan-instrumented.** A partial MSan build reports false positives on every
  call with no instrumentation, and those look identical to a real bug until
  you investigate.
