# agent-semaphore

Run a command while holding one of N machine-wide slots. Callers that don't get a slot wait in a queue.

Made for coding agents that would otherwise start heavy jobs (test suites, builds) all at once and exhaust the machine's memory.

```bash
agent-semaphore --name tests --count 2 'cd backend && npm test'
```

## Install

One bash script. Needs `flock` (part of util-linux on Linux; `brew install flock` on macOS).

```bash
git clone git@github.com:panta82/agent-semaphore.git
ln -s "$PWD/agent-semaphore/agent-semaphore" ~/.local/bin/agent-semaphore
```

## Usage

```
agent-semaphore --name NAME --count N [options] [--] COMMAND [ARGS...]
agent-semaphore --status [--name NAME]
```

| Option | Meaning |
| --- | --- |
| `-n, --name NAME` | Semaphore name. Each name is an independent set of slots. |
| `-c, --count N` | Number of slots, i.e. max concurrent commands. |
| `-t, --timeout SECS` | Give up after waiting this long and exit 75. Default: wait forever. |
| `-p, --poll SECS` | Delay between slot checks while waiting. Default: 2. |
| `-r, --report SECS` | Delay between "still waiting" messages. Default: 30. |
| `-q, --quiet` | Don't print waiting messages. |
| `-d, --dir DIR` | Lock directory. Default: `$AGENT_SEMAPHORE_DIR`, else `$XDG_RUNTIME_DIR/agent-semaphore`, else `/tmp/agent-semaphore-UID`. |
| `-s, --status` | Show slots and who holds them. |

A single `COMMAND` argument is run through `bash -c`, so a quoted command line works. Several arguments are executed directly.

The exit status is that of the command. Waiting messages go to stderr:

```
agent-semaphore[tests]: all 2 slots busy, waited 0s
agent-semaphore[tests]: all 2 slots busy, waited 30s
agent-semaphore[tests]: got slot 1/2, running
```

## Named wrappers

Give agents one short command per semaphore. Use a wrapper script, not a shell alias: agents run commands in non-interactive shells, which don't expand aliases.

```bash
#!/bin/sh
# ~/.local/bin/test-semaphore
exec agent-semaphore --name tests --count 2 "$@"
```

```bash
test-semaphore 'npm test'
test-semaphore npx jest src/foo.spec.ts
```

## Status

```
$ agent-semaphore --status
tests: 1/2 busy
  1  busy  pid 20841  2m5s  /home/me/project  npm test
  2  free
```

## Behaviour

1. **A slot is held until the command and every process it started have exited.** The slot is a file lock inherited by the command, so the kernel releases it when the last holder dies, including on crash or `kill -9`. There are no stale locks.
2. **Waiters queue.** They line up on a queue lock and only the one at the front polls the slots.
3. **Nesting is safe.** A command that already holds semaphore `NAME` and calls `agent-semaphore --name NAME` again runs immediately instead of queuing behind itself.
4. **The count belongs to the caller.** Callers that pass different counts for the same name each only look at their own first N slots.
5. **It is voluntary.** A command started without the wrapper isn't counted.

## Tests

```bash
./test.sh
```

## Credits

Queue and slot design borrowed from [timbunce/semaphoric](https://github.com/timbunce/semaphoric).
