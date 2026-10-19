# Profiling Reference: exact signatures

This file accompanies SKILL.md. Sources: docs.racket-lang.org/profile/ , the
"Time" and "Performance Hints" sections of the Reference, and the
contract-profile package. This file was checked against Racket v9.1 [cs].

## Statistical profiler (require profile)

```racket
(profile body ...+
         [#:delay secs]               ; sample interval, default 0.05
         [#:repeat n]                 ; run body n times (default 1)
         [#:threads all?]             ; profile all threads, not only the current thread
         [#:order sym]                ; 'topological (default) | 'self | 'total
         [#:use-errortrace? bool]     ; gives line precision, is slower, changes tail calls
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

`#:order` values: `'topological` groups the results by the call graph. `'self`
ranks by the time in the own code of each function. `'total` ranks by the time
that includes the callees.

## Analyzer / renderers

```racket
(require profile/analyzer)
(analyze-samples sample-data) -> profile?   ; sample-data comes from a sampler

(require profile/render-text)
(render profile-result [#:hide-self %] [#:hide-subs %] [#:truncate-source n])
   ; prints the text table (this is the default renderer)

(require profile/render-json)
(profile->json profile-result) -> jsexpr    ; write a profile result as a jsexpr
(json->profile jsexpr)         -> profile?  ; read a profile result from a jsexpr
```

Low-level sampling, to build custom tools:

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

The ordering flags exclude each other. There is no `--order` flag. The sampler
runs the module and its `main` submodule.

## Timing primitives (racket/base)

```racket
(time body ...+)                  ; prints "cpu time: real time: gc time:" and returns the value
(time-apply proc arg-list)
   -> (values result-list cpu-ms real-ms gc-ms)
(current-process-milliseconds [scope])
   ; total CPU milliseconds. The scope is #f (whole process, default), a thread, or 'subprocesses
(current-gc-milliseconds)         ; milliseconds spent in GC so far
(current-inexact-milliseconds)    ; wall clock, flonum. The value can decrease
(current-inexact-monotonic-milliseconds)  ; monotonic wall clock, flonum
(current-milliseconds)            ; integer wall clock
```

There is no `current-cpu-milliseconds`. Use `current-process-milliseconds` to
get the CPU time.

## Memory and performance counters

```racket
(current-memory-use [mode]) -> exact-nonnegative-integer?   ; bytes that are reachable
(dump-memory-stats arg ...)                                 ; memory dump to help find faults
(vector-set-performance-stats! vec [thread])
   ; puts the GC counts, the bytes allocated, the thread schedule statistics,
   ; and more into vec (length up to ~12 global / ~10 thread)
(collect-garbage [request])       ; forces a major GC before the measurement
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

This form prints the percentage of run time that the program spends on contract
checks, and a breakdown by contract and boundary. If contract wrappers show as
hot, use it together with the statistical profiler. To move or relax the
offending boundary, see the contracts skill.
