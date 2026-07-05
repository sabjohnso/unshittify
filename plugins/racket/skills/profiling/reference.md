# Profiling Reference — exact signatures

Companion to SKILL.md. Source: docs.racket-lang.org/profile/ , the Reference
"Time" / "Performance Hints" sections, and the contract-profile package.
Checked against Racket v9.1 [cs].

## Statistical profiler (require profile)

```racket
(profile body ...+
         [#:delay secs]               ; sample interval, default 0.05
         [#:repeat n]                 ; run body n times (default 1)
         [#:threads all?]             ; profile all threads, not just current
         [#:order sym]                ; 'topological (default) | 'self | 'total
         [#:use-errortrace? bool]     ; line-precise, slower, alters tail calls
         [#:render renderer]          ; default: profile/render-text's render
         [#:periodic-renderer pr]     ; live updates during the run
         [#:use-sampler sampler])
   -> the value(s) of the last body form

(profile-thunk thunk
               [#:delay ...] [#:repeat ...] [#:threads ...] [#:order ...]
               [#:use-errortrace? ...] [#:render ...] [#:periodic-renderer ...])
   thunk : (-> any)
   -> the thunk's result
```

`#:order` values: `'topological` groups by the call graph; `'self` ranks by
time in each function's own code; `'total` ranks by time including callees.

## Analyzer / renderers

```racket
(require profile/analyzer)
(analyze-samples sample-data) -> profile?   ; sample-data from a sampler

(require profile/render-text)
(render profile-result [#:hide-self %] [#:hide-subs %] [#:truncate-source n])
   ; prints the textual table (the default renderer)

(require profile/render-json)
(profile->json profile-result) -> jsexpr    ; serialize a profile result
(json->profile jsexpr)         -> profile?  ; read one back
```

Low-level sampling (build custom tooling):

```racket
(require profile/sampler)
(create-sampler control-thread delay [super-cust] [additional-data])
   -> sampler   ; call (sampler 'stop) then (sampler 'get-snapshots)
```

## raco profile

```
raco profile [options] file.rkt [arg ...]
  --delay <n>          sampling interval in seconds
  --repeat <n>         number of iterations
  --all-threads        profile every thread
  --use-errortrace     errortrace mode (line-precise, slower)
  --self               order by self time
  --total              order by total time
  --topological        order by call structure (DEFAULT)
```

The ordering flags are mutually exclusive; there is no `--order`. The module
is run (its `main` submodule too) under the sampler.

## Timing primitives (racket/base)

```racket
(time body ...+)                  ; prints "cpu time: real time: gc time:"; returns value
(time-apply proc arg-list)
   -> (values result-list cpu-ms real-ms gc-ms)
(current-process-milliseconds [scope])
   ; total CPU ms; scope: #f (whole process, default), a thread, or 'subprocesses
(current-gc-milliseconds)         ; ms spent in GC so far
(current-inexact-milliseconds)    ; wall clock, flonum, may go backwards
(current-inexact-monotonic-milliseconds)  ; monotonic wall clock, flonum
(current-milliseconds)            ; integer wall clock
```

There is no `current-cpu-milliseconds`; use `current-process-milliseconds`
for CPU time.

## Memory and performance counters

```racket
(current-memory-use [mode]) -> exact-nonnegative-integer?   ; bytes reachable
(dump-memory-stats arg ...)                                 ; debugging dump
(vector-set-performance-stats! vec [thread])
   ; fills vec (length up to ~12 global / ~10 thread) with GC counts, bytes
   ; allocated, thread scheduling stats, etc.
(collect-garbage [request])       ; force a (major) GC before measuring
```

## Contract profiling (require contract-profile)

```racket
(contract-profile body ...+
                  [#:report-space-efficient? bool]
                  [#:module-graph-view-file path]
                  [#:boundary-view-file path]
                  [#:boundary-view-key-file path])
   -> value(s) of body
(contract-profile-thunk thunk #:keyword ...) -> thunk's result
```

Prints the percentage of run time spent checking contracts and a breakdown by
contract and boundary. Pair with the statistical profiler when contract
wrappers show up as hot. See the contracts skill for moving/relaxing the
offending boundary.
