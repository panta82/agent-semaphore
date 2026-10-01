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
| `-c, --count N` | Number of slots. |
| `-w, --weight N` | Slots this command takes. Default: 1. A weight above the count is lowered to the count, so the command runs alone. |
| `-t, --timeout SECS` | Give up after waiting this long and exit 75. Default: wait forever. |
| `-p, --poll SECS` | Delay between slot checks while waiting. Default: 2. |
| `-r, --report SECS` | Delay between "still waiting" messages. Default: 30. |
| `-q, --quiet` | Don't print waiting messages. |
| `-d, --dir DIR` | Lock directory. Default: `$AGENT_SEMAPHORE_DIR`, else `$XDG_RUNTIME_DIR/agent-semaphore`, else `/tmp/agent-semaphore-UID`. |
| `-s, --status` | Show slots and who holds them. |

A single `COMMAND` argument is run through `bash -c`, so a quoted command line works. Several arguments are executed directly.

The exit status is that of the command. Waiting messages go to stderr:

```
agent-semaphore[tests]: need 1 of 2 slots, 0 free, waited 0s
agent-semaphore[tests]: need 1 of 2 slots, 0 free, waited 30s
agent-semaphore[tests]: got 1 of 2 slots, running
```

## Weights

Give heavy commands a weight so they count for more than light ones:

```bash
agent-semaphore -n tests -c 6 -w 4 'npm test'             # full suite, 4 workers
agent-semaphore -n tests -c 6 npx jest src/foo.spec.ts    # one spec, weight 1
```

With 6 slots that allows one full run plus two single specs, or six single specs, but never two full runs.

## Recommended setup

The semaphore limits how many heavy commands run. On Linux with systemd, three more pieces decide who suffers when memory runs short anyway. The files are in [examples/](examples).

### 1. One wrapper command for agents

Agents should not type the name and count themselves: one that passes a different count sees a different set of slots. Put them in a wrapper script. Use a script, not a shell alias, because agents run commands in non-interactive shells, which don't expand aliases.

[examples/run-tests](examples/run-tests) queues on the `tests` semaphore with 6 slots and then runs the command inside `tests.slice`:

```bash
install -m 755 examples/run-tests ~/.local/bin/run-tests

run-tests 'npx jest src/foo.spec.ts'
run-tests --weight 4 'npm test'
```

Without a systemd user session it prints a warning and runs under the semaphore only.

### 2. A memory ceiling for tests

Commands started by an agent live in the agent's cgroup, so their memory is billed to the agent host. Under memory pressure `systemd-oomd` kills whole cgroups, and the agent host is then the biggest candidate.

[examples/tests.slice](examples/tests.slice) gives tests their own cgroup with a ceiling for all runs together:

```bash
cp examples/tests.slice ~/.config/systemd/user/
systemctl --user daemon-reload
```

Tests are throttled above `MemoryHigh`. Past `MemoryMax` the kernel kills a process inside the slice, typically a test worker, and nothing outside it. Size the limits to roughly `count x memory per slot`.

### 3. Protect the apps that must survive

[examples/oom-protect.conf](examples/oom-protect.conf) marks a service as one `systemd-oomd` should avoid and keeps part of its memory out of swap. Install it as a drop-in for the agent host and the IDE:

```bash
mkdir -p ~/.config/systemd/user/my-agent-host.service.d
cp examples/oom-protect.conf ~/.config/systemd/user/my-agent-host.service.d/
systemctl --user daemon-reload
```

The drop-in applies on the next start of the service. To apply it to a running one without a restart:

```bash
systemctl --user set-property --runtime my-agent-host.service MemoryLow=2G ManagedOOMPreference=avoid
```

Apps started from a desktop launcher run as `app-<name>@<id>.service`. For those, put the drop-in in `app-<name>@.service.d/`; `systemctl --user list-units 'app-*'` shows the names.

### 4. Tell the agents

In the instructions file your agents read on this machine (`AGENTS.md`, `CLAUDE.md`):

````markdown
There's only so many tests this computer can run. When running tests, always do it like this:

```bash
run-tests '<your tests command>'
```

This applies to every test command, including a single test file.

If the test suite you're running spawns multiple workers, add the `--weight <N>` argument, where N is the number of workers it will spawn. Eg.

```bash
run-tests --weight 4 'npm run test'
```

If the slots are busy, the command waits and prints "need N of 6 slots". This is normal: don't cancel or retry. The wait can be long, so run it in the background or with a long timeout.

A test worker killed with SIGKILL means the memory limit was hit, not that the test is broken. Run it again once before debugging.
````

## Status

```
$ agent-semaphore --status
tests: 1/2 busy
  1  busy  pid 20841  2m5s  /home/me/project  npm test
  2  free
```

## Behaviour

1. **Slots are held until the command and every process it started have exited.** Each slot is a file lock inherited by the command, so the kernel releases it when the last holder dies, including on crash or `kill -9`. There are no stale locks.
2. **Waiters queue.** They line up on a queue lock and only the one at the front polls the slots.
3. **Nesting is safe.** A command that already holds semaphore `NAME` and calls `agent-semaphore --name NAME` again runs immediately instead of queuing behind itself.
4. **Weighted commands take all their slots or none.** A heavy command at the front of the queue holds up lighter ones behind it until enough slots are free, so it can't be starved.
5. **The count belongs to the caller.** Callers that pass different counts for the same name each only look at their own first N slots.
6. **It is voluntary.** A command started without the wrapper isn't counted.

## Tests

```bash
./test.sh
```

## Credits

Queue and slot design borrowed from [timbunce/semaphoric](https://github.com/timbunce/semaphoric).

## License

MIT
