---
description: Run a long command as a background job that reports its own death, and read the heartbeat of that job. The wrapper script writes a beat at a fixed interval and the exit status at the end. The watcher script exits when a job ends or its heartbeat stops, and the harness then starts the model. Use before you start a command in the background, when a PreToolUse hook denied a command with the operator &, nohup, or disown, or when you must decide if a background job is alive, idle, or dead.
argument-hint: "[command to run in the background]"
allowed-tools: Read, Bash
---

# Run a background job that reports its death

Goal: start long work so that its death always reaches the model, and never wait for work that does not run.

This skill grants a bare `Bash` and not an argument-scoped pattern. The wrapper runs the command that the user gives, and that command is unknown when the skill is written.

## What tracks a job

| Route                                                | What tells the model that the job ended                 |
|------------------------------------------------------|---------------------------------------------------------|
| The foreground, with a long `timeout` parameter      | The Bash call returns.                                  |
| `make a & make b & wait` in one call                 | The Bash call returns.                                  |
| The wrapper with the `run_in_background` parameter   | The harness, the watcher, and the report hook.          |
| A bare `&`, `nohup`, `disown`, or `coproc`           | Nothing. `deny-untracked-background.sh` denies it.      |

A `wait` collects the `&` operators before it only when the `wait` has no argument and no redirection. `a & b & wait -n` is denied. When only a quoted string that an interpreter executes holds the `&`, as in `bash -c "server &"`, the hook asks the user and does not deny.

## How to read a beat

A beat holds two facts and no verdict. `cpu_ms` is the processor time that the job and all its descendants used since the last beat. `log_bytes` is the size of the log.

| `cpu_ms`  | `log_bytes` | What it can mean                                              |
|-----------|-------------|---------------------------------------------------------------|
| high      | grows       | The job works.                                                |
| high      | constant    | A computation with no output, or an endless loop.             |
| near zero | grows       | The job waits on a different system and prints the results.   |
| near zero | constant    | The job waits on a different system, or the job is hung.      |

The class of a job is one of three. `alive` means that the wrapper wrote a beat in the last three intervals. `ended <status>` means that the job ended with that exit status. `stale` means that the heartbeat stopped. The wrapper is probably dead, and then nothing can report the status of the job. If the heartbeat only paused, a second report gives the exit status later.

## Steps

1. Decide the route. If the work ends in less than ten minutes, run it in the foreground with a `timeout` parameter of sufficient length. For parallel work that ends in one call, put `wait` after the last `&`. For all other work, continue with step 2.
2. Find the scripts. Run `jq -r '.hooks.PreToolUse[]?.hooks[]?.command | select(test("deny-untracked-background"))' ~/.claude/settings.json`. The result is `bash <repository>/hooks/deny-untracked-background.sh`. The scripts are in `<repository>/scripts/`. If the result is empty, tell the user that the hooks are not wired, and stop.
3. Start the job. Run `<repository>/scripts/background-run.sh <command> [argument ...]` with the `run_in_background` parameter of the Bash tool. For a command with shell operators, give `bash -c '<command>'` as the command. Do not add `&`.
4. Start the watcher. Run `<repository>/scripts/background-watch.sh` with the `run_in_background` parameter, from the same directory. Start one watcher. It watches each job of the directory. You can send steps 3 and 4 in one message, because the watcher waits for one interval when it finds no job.
5. Continue with other work, or end the turn. Do not poll the job, and do not sleep.
6. When the wrapper or the watcher exits, read the report. Read the log file that the report names. Tell the user the class of the job and what the log shows.
7. If the class is `stale`, tell the user that the wrapper died and that the status of the job is unknown. Find the process of the job with the `pid` in the start record before you start the job again.
8. If jobs remain after a report, start the watcher again. The watcher exits after each report. The registry keeps the log of a job for one day after its last activity.
9. Before you tell the user that a job still runs, make sure that its log grows. Run `tail -n 3 <job directory>/log`. The wrapper printed the job directory when it started.
