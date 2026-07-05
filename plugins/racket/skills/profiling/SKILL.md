---
description: Profile and time Racket code — time/time-apply for quick cpu/real/gc numbers, the statistical profiler (profile, profile-thunk, raco profile) to find hot spots, contract-profile for contract overhead, and current-memory-use for allocation. Use when code is slow and you need evidence of where time goes before optimizing, reading a profiler report, or measuring contract/GC cost.
---

# Profiling Racket

Measure before optimizing. A guess about the hot spot is usually wrong; a
profile tells you where time actually goes, so you change the one place that
matters and leave the rest simple. Work from cheap to detailed: `time` for a
single number, the statistical `profile` for a breakdown, `contract-profile`
when contracts are suspect.

## Quick timing

`time` prints cpu / real / gc milliseconds for one expression and returns its
value; `time-apply` returns the result plus the three numbers as values:

```racket
(time (work))                         ; cpu time: 76 real time: 80 gc time: 8
(let-values ([(results cpu real gc) (time-apply work '())])
  (printf "cpu=~a gc=~a\n" cpu gc))
```

Read the **gc** column: a large gc share means the answer is *allocation*,
not computation — reduce consing before micro-optimizing the arithmetic. Run
`time` two or three times; the first includes JIT/expansion warmup.

## The statistical profiler

`profile` samples the stack on a timer, so it shows where time concentrates
without instrumenting every call. Wrap an expression with the macro, or a
thunk with `profile-thunk`:

```racket
(require profile)
(profile (work) #:delay 0.002 #:repeat 5 #:order 'self)

(profile-thunk (lambda () (work)) #:order 'total)
```

Key options:

- **`#:delay`** — seconds between samples (default `0.05`); lower it for
  short runs to collect more samples.
- **`#:repeat`** — run the body N times for more samples and to amortize
  warmup.
- **`#:order`** — `'topological` (default, groups by call structure),
  `'self`, or `'total`.
- **`#:use-errortrace?`** — line-precise attribution (see below).

### Reading the report

```
Total cpu time observed: 76ms (out of 80ms)
Number of samples taken: 38 (once every 2ms)
...
[1]  42(55.6%)  42(55.6%)  slow-fib /tmp/work.rkt:4:0
```

- **Total** = time in this function *and everything it called*. **Self** =
  time in this function's own code. Optimize the node with the largest
  **Self** percentage — that is where the CPU actually sat.
- **Samples taken** is the trust meter. Two samples prove nothing; aim for
  dozens to hundreds. Too few → raise `#:repeat`, lower `#:delay`, or profile
  a bigger workload.
- The caller/callee lines around each entry show who called it and where its
  total time went — follow them to find which path feeds a hot function.

## raco profile

Profile a whole module from the command line — no edits to the file:

```
raco profile file.rkt
raco profile --self file.rkt          # order by self time
raco profile --total file.rkt         # order by total time
raco profile --delay 0.001 --repeat 5 file.rkt
raco profile --use-errortrace file.rkt
```

The ordering flags are `--self` / `--total` / `--topological` (default) —
there is no `--order`. `raco profile` runs the module's `main` submodule if
present.

## errortrace mode — precision vs cost

`#:use-errortrace?` (or `--use-errortrace`) attributes time to exact source
positions instead of whole functions, at a large slowdown and with
tail-call behavior changed (errortrace disables some tail-call optimization,
so the call structure you see is not the optimized one). Use it to localize
*within* a function the sampler flagged, not as the default.

## contract overhead

If a profile is dominated by contract wrappers, measure it directly.
`contract-profile` reports what fraction of run time is spent checking
contracts and which contracts cost the most:

```racket
(require contract-profile)
(contract-profile (run-workload))     ; => "Running time is 23% contracts"
```

A high percentage means the boundary is too hot — move the contract outward,
relax it on an internal path, or drop to `define/contract`-free code there
(see [[contracts]]). Confirm with evidence before removing any check.

## Memory

`(current-memory-use)` returns bytes currently reachable; sample it before
and after a phase to estimate retained memory. `time`'s gc column and
`(current-gc-milliseconds)` measure collection time. For finer counters,
`vector-set-performance-stats!` fills a vector with GC counts, thread stats,
and more.

## Rules that prevent rework

- **Profile a realistic workload.** A toy input finishes before the sampler
  collects enough samples and exercises different paths than production —
  size the input so the run lasts well over a second.
- **Trust the sample count, not one run.** Check "samples taken"; if it is
  small the percentages are noise. Raise `#:repeat`/lower `#:delay` until the
  ranking is stable across runs.
- **Optimize the dominant self-time node, then re-measure.** Fixing anything
  else moves a number you cannot feel. After each change, re-profile —
  the hot spot shifts.
- **Keep the simple reference implementation.** Per project standards, a
  nontrivial optimization needs benchmark/profile evidence that it is
  necessary, and the clear version should remain alongside it for
  documentation and comparison.
- **Separate allocation from computation.** A big gc column points at
  consing; reducing allocation often beats tuning the inner arithmetic.
- **Measure contract cost before deleting contracts.** Use `contract-profile`
  to prove a boundary is the bottleneck rather than removing safety on a hunch
  ([[contracts]]).
