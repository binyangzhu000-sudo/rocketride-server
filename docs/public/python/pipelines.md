---
title: Running Pipelines
sidebar_position: 3
---

# Running Pipelines

Start a pipeline, watch its progress, and stop it. Method tables live in the
[API reference](/clients/python/reference#pipeline-execution); this page covers the
workflow.

## Start with `use()`

`use()` starts a pipeline from a file or an in-memory config and returns a dict whose
`'token'` identifies the running task — every data and control call takes it.

```python
result = await client.use(filepath='pipeline.pipe')
token = result['token']
```

Beyond `filepath`/`pipeline`, `use()` accepts `token` (a custom task token; the
server generates one when omitted), `source`, `threads`, `use_existing`,
`args`, `ttl`, `pipelineTraceLevel` (trace verbosity for the
[run log](/clients/python/logs)), `name` (a display name for the task), and `env`
(per-run variable overrides). Pass the pipeline config **as-is** — the client sends it
to the server, which resolves `${ROCKETRIDE_*}` variables from its merged
environment.

**Running the same pipeline more than once at a time.** Without a custom `token`,
the server names the task after its owner, `project_id` and source, so a second
`use()` of the same pipe fails with `Pipeline is already running.` Give each
instance its own `token` and they run side by side. Use an unguessable value that
keeps the `tk_` prefix, `tk_` plus a UUID for example. The value you choose is
the run's [private token](/operate/security#endpoint-authentication): full
control of the run for anyone who presents it, so treat it as a secret; a token
without the prefix cannot serve as one on webhook or dropper endpoints; and
tokens share one namespace across every user of the server, so a predictable
value collides with other people's tasks. Keep the tokens you chose: both
instances get the same `pk_` public authorization key (webhook calls and dropper
upload URLs carry it), and `get_task_token()` is keyed by the pipe's `project_id` and
source, so each resolves to only one of the instances. Monitor subscriptions are
keyed the same way: both instances' events arrive in one subscription that the
SDK's documented fields cannot tell apart, and a few minutes after one instance
ends, when the server removes it from its registry, the shared subscription is
dropped and the surviving instance's events stop arriving (resubscribe). The
run log is written per identity and is not built for two instances at once, so
treat a forked run's log as unreliable.

**Check `reused` before trusting the result.** `use_existing` returns the
instance that is already running under that token rather than starting the one
you submitted, and the result's `reused` flag is `True` when that happened. A
reused instance keeps the configuration it was created with — the pipeline in
this call is ignored, edits included — along with whatever state it has
accumulated. Benchmarks and A/B comparisons are where an unnoticed reuse costs
the most. Call `restart()` to apply new configuration to a live token.

**Why a token:** the server runs each pipeline as a separate task. The token targets
`send()`, `send_files()`, `pipe()`, `chat()`, `get_task_status()`, and `terminate()`
at the correct pipeline.

## Watch progress

Poll `get_task_status(token)` — it returns `completedCount`, `totalCount`,
`completed`, `state`, `exitCode`, and more:

```python
while True:
    status = await client.get_task_status(token)
    print(f'Progress: {status.get("completedCount", 0)}/{status.get("totalCount", 0)}')
    if status.get('completed'):
        break
    await asyncio.sleep(2)
```

### Events

For push-style progress instead of polling, add a monitor subscription; events
arrive at your [`on_event` callback](/clients/python/configuration#callbacks):

```python
await client.add_monitor({'token': token}, ['apaevt_status_upload', 'apaevt_status_processing'])
# ... later:
await client.remove_monitor({'token': token}, ['apaevt_status_upload', 'apaevt_status_processing'])
```

`add_monitor(key, types)` / `remove_monitor(key, types)` are reference-counted —
adding the same key merges types, removing unsubscribes a type only when its count
reaches zero. The key is `{'token': ...}` for a running task, or
`{'project_id': ..., 'source': ...}` (optionally with `'pipe_id'` and/or
`'team_id'` — a team ID addresses that team's deployed run). The older
`set_events(token, event_types, pipe_id=None)` still works but is deprecated in
favor of the monitor pair.

## Validate before you run

`validate(pipeline, source=None)` checks a pipeline config server-side without
starting it and returns errors and warnings — cheap insurance before `use()`.

## Stop with `terminate()`

`terminate(token)` stops the pipeline and frees server resources. Long-lived tasks
without a `ttl` run until terminated.

## Discover services

`get_services()` returns lightweight **summaries** of every service the server
supports (plus a deduplicated icon table and the server version). For a full
definition — config schema included — fetch one by name with `get_service(name)`.
Note `get_service` **raises** on failure (`ValueError` for an empty name,
`RuntimeError` for an unknown service); it never returns `None`.

```python
services = await client.get_services()
ocr = await client.get_service('ocr')  # raises if unknown
```

## Liveness

`ping()` performs a liveness check against the server and raises on failure.

> Deploying a pipeline so it persists server-side and runs on a schedule is a
> separate surface — see [Deployments](/clients/python/deploy).
