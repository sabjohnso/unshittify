---
description: Profile and time Racket code. Covers time and time-apply for quick cpu, real, and gc numbers, the statistical profiler (profile, profile-thunk, raco profile) to find the hot spots, contract-profile for the contract overhead, and current-memory-use for the allocation. Use when code is slow and you need evidence of where the time goes before you optimize, when you read a profiler report, or when you measure the contract or GC cost.
allowed-tools: Bash(racket:*), Bash(raco:*), Read, Grep, Glob
---

# Profile Racket

Measure before you optimize. A guess about the hot spot is usually wrong. A
profile tells you where the time goes, so you change the one place that
matters and leave the rest simple. Work from the cheap tool to the detailed
tool: `time` for a single number, the statistical `profile` for a
breakdown, and `contract-profile` when you suspect the contracts.

For the exact signatures of the profiler, the renderer options, and the
timing and memory primitives, read `reference.md` in this skill directory.

## Quick timing

`time` prints the cpu, real, and gc milliseconds for one expression and
returns its value. `time-apply` returns the result plus the three numbers as
values:

```racket
(time (work))                         ; cpu time: 76 real time: 80 gc time: 8
(let-values ([(results cpu real gc) (time-apply work '())])
  (printf "cpu=~a gc=~a\n" cpu gc))
```

Read the **gc** column. A large gc share means that the answer is
*allocation*, not computation. Reduce the consing before you micro-optimize
the arithmetic. Run `time` two or three times. The first run includes the
JIT and expansion warmup.

## The statistical profiler

`profile` samples the stack on a timer. So it shows where the time
concentrates, with no instrumentation of every call. Wrap an expression with
the macro, or a thunk with `profile-thunk`:

```racket
(require profile)
(profile (work) #:delay 0.002 #:repeat 5 #:order 'self)

(profile-thunk (lambda () (work)) #:order 'total)
```

The key options:

- **`#:delay`**: the seconds between samples (the default is `0.05`). Lower
  it for a short run, to collect more samples.
- **`#:repeat`**: run the body N times, for more samples and to amortize the
  warmup.
- **`#:order`**: `'topological` (the default, in groups by call structure),
  `'self`, or `'total`.
- **`#:use-errortrace?`**: attribution per line (see below).

### How to read the report

```
Total cpu time observed: 76ms (out of 80ms)
Number of samples taken: 38 (once every 2ms)
...
[1]  42(55.6%)  42(55.6%)  slow-fib /tmp/work.rkt:4:0
```

- **Total** is the time in this function *and in all that it called*.
  **Self** is the time in the own code of this function. Optimize the node
  with the largest **Self** percentage. That is where the CPU sat.
- **Samples taken** tells you how much to trust the percentages. Two samples
  show nothing. Aim for dozens to hundreds. If there are too few, raise
  `#:repeat`, lower `#:delay`, or profile a larger workload.
- The caller and callee lines around each entry show who called it and
  where its total time went. Follow them to find the path that feeds a hot
  function.

## raco profile

Profile a whole module from the command line, with no edit of the file:

```
raco profile file.rkt
raco profile --self file.rkt          # order by self time
raco profile --total file.rkt         # order by total time
raco profile --delay 0.001 --repeat 5 file.rkt
raco profile --use-errortrace file.rkt
```

The order flags are `--self`, `--total`, and `--topological` (the default).
There is no `--order`. `raco profile` runs the `main` submodule of the
module if it is present.

## The errortrace mode: precision against cost

`#:use-errortrace?` (or `--use-errortrace`) attributes the time to exact
source positions instead of whole functions. The cost is a large slowdown
and a changed tail-call behavior. errortrace disables some tail-call
optimization, so the call structure that you see is not the optimized one.
Use it to locate the hot spot *inside* a function that the sampler flagged,
not as the default.

## The contract overhead

If contract wrappers dominate a profile, measure them directly.
`contract-profile` reports the fraction of the run time that the contract
checks take, and which contracts cost the most:

```racket
(require contract-profile)
(contract-profile (run-workload))     ; => "Running time is 23% contracts"
```

A high percentage means that the boundary is too hot. Move the contract
outward, relax it on an internal path, or remove `define/contract` from the
code there (see [contracts](../contracts/SKILL.md)). Confirm with evidence
before you remove a check.

## Memory

`(current-memory-use)` returns the bytes that are reachable now. Sample it
before and after a phase to estimate the retained memory. The gc column of
`time` and `(current-gc-milliseconds)` measure the collection time. For
finer counters, `vector-set-performance-stats!` fills a vector with GC
counts, thread statistics, and more.

## Rules that prevent rework

- **Profile a realistic workload.** A toy input finishes before the sampler
  collects enough samples, and it exercises different paths from
  production. Size the input so the run lasts well over a second.
- **Trust the sample count, not one run.** Check "samples taken". If it is
  small, the percentages are noise. Raise `#:repeat` or lower `#:delay`
  until the ranking is stable across runs.
- **Optimize the dominant self-time node, then measure again.** A fix at
  any other place gives an improvement that is too small to see. After each
  change, profile again. The hot spot moves.
- **Keep the simple reference implementation.** Per the project standards, a
  nontrivial optimization needs benchmark or profile evidence that it is
  necessary, and the clear version must stay beside it for documentation
  and comparison.
- **Separate the allocation from the computation.** A large gc column points
  at consing. A reduction of the allocation often beats a tune of the inner
  arithmetic.
- **Measure the contract cost before you delete contracts.** Use
  `contract-profile` to show that a boundary is the bottleneck. Do not
  remove safety on a guess ([contracts](../contracts/SKILL.md)).
