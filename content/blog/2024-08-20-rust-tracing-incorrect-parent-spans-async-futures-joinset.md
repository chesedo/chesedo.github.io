+++
title = "Fixing Incorrect Tracing Parent Spans with Futures and JoinSet in Rust"
description = "Learn how to solve incorrect tracing parent spans in Rust async code when using Futures and JoinSet. Discover the cause and implement effective solutions."
[taxonomies]
tags = ["Rust", "Advanced Rust", "async", "tracing"]
+++

I recently had a client who experienced issues with their `tracing` events not being connected with the correct parent events.
I immediately understood the problem on the call, but there were a few details that still confused me.
So I thought it would be great to fully understand those details.
And to share the knowledge gained with the wider Rust community.

{% warning() %}
This post assumes intermediate Rust knowledge, including familiarity with tracing, async programming, and tokio.
It focuses on solving a specific issue with tracing spans in asynchronous contexts.
{% end %}

The following code snippet is a minimal example of the issue.

```rust
use std::future::Future;

use tokio::task::JoinSet;
use tracing::{info, instrument};
use tracing_subscriber::fmt;

#[tokio::main]
async fn main() {
    // A custom tracing setup to aid in the explanations for this post
    fmt()
        .pretty()
        .with_thread_ids(true)
        .with_target(false)
        .with_line_number(true)
        .init();

    info!("in main");

    work().await
}

#[instrument]
async fn work() {
    info!("starting work");

    // Using a [JoinSet] for a dynamic number of subtasks
    let mut set = JoinSet::new();

    set.spawn(sub_task());

    // Wait for all the tasks to be done
    while let Some(_) = set.join_next().await {}
}

#[instrument]
fn sub_task() -> impl Future<Output = ()> {
    info!("making sub task");

    async {
        info!("performing task");
    }
}
```

{% terminal_output() %}
  [2m2024-08-20T12:37:48.092480Z[0m [32m INFO[0m  [32min main[0m
    [2;3mat[0m src/main.rs:17 [2;3mon[0m ThreadId(1)

  [2m2024-08-20T12:37:48.092622Z[0m [32m INFO[0m  [32mstarting work[0m
    [2;3mat[0m src/main.rs:24 [2;3mon[0m ThreadId(1)
    [2;3min[0m [1mwork[0m

  [2m2024-08-20T12:37:48.092641Z[0m [32m INFO[0m  [32mmaking sub task[0m
    [2;3mat[0m src/main.rs:37 [2;3mon[0m ThreadId(1)
    [2;3min[0m [1mwork[0m

  [2m2024-08-20T12:37:48.092780Z[0m [32m INFO[0m  [32mperforming task[0m
    [2;3mat[0m src/main.rs:40 [2;3mon[0m ThreadId(17)
    [2;3min[0m [1msub_task[0m
{% end %}

In `main()` we are logging "in main" which is correctly not associated with any tracing span.
Then there is a "starting work" log which is also correctly associated with the `work` span.

But then the issues start.
The next "making sub task" is not associated with the `work -> sub_task` span hierarchy.
Nor is "performing task" associated with the `work -> sub_task` span hierarchy.

## Understanding the Causes
So what is happening here?
Well, let's first focus on the "making sub task" log.

### #[instrument] issues
From the [`instrument` documentation](https://docs.rs/tracing-attributes/latest/tracing_attributes/attr.instrument.html) we see the macro also works with async functions which uses `async-trait`.
The [documentation for `async-trait`](https://docs.rs/async-trait/latest/async_trait/#explanation) explains how it transforms async functions to return a pinned boxed future.
But wait, our `sub_task` also returns a future. 🤔

By looking at the `tracing::instrument` code, I see it eventually calls [this function](https://github.com/tokio-rs/tracing/blob/527b4f66a604e7a6baa6aa7536428e3a303ba3c8/tracing-attributes/src/expand.rs#L550) to determine whether the macro annotated function implements a manual async or not.
According to the function's documentation, it should only detect pin boxed futures.
But it will also [check if the last statement in the function is an async expression](https://github.com/tokio-rs/tracing/blob/527b4f66a604e7a6baa6aa7536428e3a303ba3c8/tracing-attributes/src/expand.rs#L571-L590).
So it seems the `instrument` macro is messing up the expanded block.
Let's confirm this by changing the function to not have an async statement as the last item in the function.

```rust
#[instrument]
fn sub_task() -> impl Future<Output = ()> {
    info!("making sub task");

    let fut = async {
        info!("performing task");
    };

    fut
}
```

{% terminal_output() %}
  [2m2024-08-20T12:39:12.663662Z[0m [32m INFO[0m  [32min main[0m
    [2;3mat[0m src/main.rs:17 [2;3mon[0m ThreadId(1)

  [2m2024-08-20T12:39:12.663753Z[0m [32m INFO[0m  [32mstarting work[0m
    [2;3mat[0m src/main.rs:24 [2;3mon[0m ThreadId(1)
    [2;3min[0m [1mwork[0m

  [2m2024-08-20T12:39:12.663786Z[0m [32m INFO[0m  [32mmaking sub task[0m
    [2;3mat[0m src/main.rs:37 [2;3mon[0m ThreadId(1)
    [2;3min[0m [1msub_task[0m
    [2;3min[0m [1mwork[0m

  [2m2024-08-20T12:39:12.663851Z[0m [32m INFO[0m  [32mperforming task[0m
    [2;3mat[0m src/main.rs:40 [2;3mon[0m ThreadId(17)
{% end %}

Nice, the "making sub task" is now correctly in the `work -> sub_task` hierarchy.
The "performing task" is also technically in the correct hierarchy of nothing.
But I'm getting ahead of myself.

This is also not the fix for this problem.
We just confirmed what the problem is.

The correct way to do this will be to create a manual span and enter it like so:

```rust
// The [instrument] macro is removed in favour of a manual span
fn sub_task() -> impl Future<Output = ()> {
    let _span = tracing::info_span!("sub_task").entered();

    info!("making sub task");

    async {
        info!("performing task");
    }
}
```

{% terminal_output() %}
  [2m2024-08-20T12:39:46.292346Z[0m [32m INFO[0m  [32min main[0m
    [2;3mat[0m src/main.rs:17 [2;3mon[0m ThreadId(1)

  [2m2024-08-20T12:39:46.292396Z[0m [32m INFO[0m  [32mstarting work[0m
    [2;3mat[0m src/main.rs:24 [2;3mon[0m ThreadId(1)
    [2;3min[0m [1mwork[0m

  [2m2024-08-20T12:39:46.292409Z[0m [32m INFO[0m  [32mmaking sub task[0m
    [2;3mat[0m src/main.rs:38 [2;3mon[0m ThreadId(1)
    [2;3min[0m [1msub_task[0m
    [2;3min[0m [1mwork[0m

  [2m2024-08-20T12:39:46.292460Z[0m [32m INFO[0m  [32mperforming task[0m
    [2;3mat[0m src/main.rs:41 [2;3mon[0m ThreadId(17)
{% end %}

### Why no parent span?
Now we can get to the issue I want to address in this article.
The issue my client called me in to address.
Why does "performing task" not have any parent spans while it is in the `work -> sub_task` hierarchy?

Well, that question makes an incorrect assumption.
Since async functions & futures in Rust are not started immediately, only the **creation** of the "performing task" future is in the `work -> sub_task` hierarchy.
For all we know that future can be awaited in the `work()` function.
Or the `work()` function might return it to `main()` where it is awaited.

Let's await it in work to better show what I mean:

```rust
#[instrument]
async fn work() {
    info!("starting work");

    // Remember `sub_task` is not marked as async
    // But it does return a future we can await
    sub_task().await;
}
```

{% terminal_output() %}
  [2m2024-08-20T12:40:16.513251Z[0m [32m INFO[0m  [32min main[0m
    [2;3mat[0m src/main.rs:17 [2;3mon[0m ThreadId(1)

  [2m2024-08-20T12:40:16.513299Z[0m [32m INFO[0m  [32mstarting work[0m
    [2;3mat[0m src/main.rs:24 [2;3mon[0m ThreadId(1)
    [2;3min[0m [1mwork[0m

  [2m2024-08-20T12:40:16.513312Z[0m [32m INFO[0m  [32mmaking sub task[0m
    [2;3mat[0m src/main.rs:32 [2;3mon[0m ThreadId(1)
    [2;3min[0m [1msub_task[0m
    [2;3min[0m [1mwork[0m

  [2m2024-08-20T12:40:16.513333Z[0m [32m INFO[0m  [32mperforming task[0m
    [2;3mat[0m src/main.rs:35 [2;3mon[0m ThreadId(1)
    [2;3min[0m [1mwork[0m

{% end %}

Great, the log is now correctly linked with the `work` parent where it "executed".
So why did it not have the correct parent when a `JoinSet` was used?

Well, did you notice that the "performing task" log had a different thread id than the other logs this whole time?
It is only with this last code change that it no longer does.
Scroll up and check if you missed it.

### Manual spawn

While I've never used `JoinSet`s before, I knew from a recent YouTube video of Jon Gjengset [decrusting the tokio crate](https://www.youtube.com/watch?v=o2ob8zkeq2s) that the `JoinSet` will start tokio spawns under the hood.
So we can create the same effect by also starting our future on a spawn.

```rust
#[instrument]
async fn work() {
    info!("starting work");

    let _result = tokio::spawn(sub_task()).await;
}
```

{% terminal_output() %}
  [2m2024-08-20T12:40:55.952528Z[0m [32m INFO[0m  [32min main[0m
    [2;3mat[0m src/main.rs:17 [2;3mon[0m ThreadId(1)

  [2m2024-08-20T12:40:55.952591Z[0m [32m INFO[0m  [32mstarting work[0m
    [2;3mat[0m src/main.rs:24 [2;3mon[0m ThreadId(1)
    [2;3min[0m [1mwork[0m

  [2m2024-08-20T12:40:55.952603Z[0m [32m INFO[0m  [32mmaking sub task[0m
    [2;3mat[0m src/main.rs:32 [2;3mon[0m ThreadId(1)
    [2;3min[0m [1msub_task[0m
    [2;3min[0m [1mwork[0m

  [2m2024-08-20T12:40:55.952674Z[0m [32m INFO[0m  [32mperforming task[0m
    [2;3mat[0m src/main.rs:35 [2;3mon[0m ThreadId(16)
{% end %}

Now it is "incorrect" again and has a different thread ID just like the `JoinSet`.
This confirms starting a manual spawn does the same as a `JoinSet`.

If you think about it, then "performing task" not having a parent is actually correct.
Since we spawned it on a new thread, that thread no longer has the `work -> sub_task` span hierarchy.
In fact, the "performing task" future is at the root of that thread and therefore correctly does not have any span parents in the logs.

The span documentation already mentions the core of the issue when talking about an [entered span being held across an `.await` point](https://docs.rs/tracing/latest/tracing/span/struct.Span.html#in-asynchronous-code).
The documentation explains that an issue might arise when another future is started / makes progress at an `.await` point.
So it's clear that every future has its own "span context" - for lack of a better term.
And when our future executes on a new thread, it simply does not have any "span context" for its parent.

## The Solution
The core of the issue lies in how futures and spawned tasks handle tracing contexts.
When a future is spawned on a new thread, it loses its original tracing context.
To maintain the correct span hierarchy across thread boundaries, we need to explicitly instrument our futures.

The span documentation also states that an `.instrument()` is the way to fix this instead.

```rust
#[instrument]
async fn work() {
    info!("starting work");

    let _result = tokio::spawn(
            sub_task().instrument(tracing::info_span!("spawned sub_task"))
        ).await;
}
```

{% terminal_output() %}
  [2m2024-08-20T12:41:43.699116Z[0m [32m INFO[0m  [32min main[0m
    [2;3mat[0m src/main.rs:17 [2;3mon[0m ThreadId(1)

  [2m2024-08-20T12:41:43.699189Z[0m [32m INFO[0m  [32mstarting work[0m
    [2;3mat[0m src/main.rs:24 [2;3mon[0m ThreadId(1)
    [2;3min[0m [1mwork[0m

  [2m2024-08-20T12:41:43.699201Z[0m [32m INFO[0m  [32mmaking sub task[0m
    [2;3mat[0m src/main.rs:34 [2;3mon[0m ThreadId(1)
    [2;3min[0m [1msub_task[0m
    [2;3min[0m [1mwork[0m

  [2m2024-08-20T12:41:43.699251Z[0m [32m INFO[0m  [32mperforming task[0m
    [2;3mat[0m src/main.rs:37 [2;3mon[0m ThreadId(17)
    [2;3min[0m [1mspawned sub_task[0m
    [2;3min[0m [1mwork[0m
{% end %}

The `work -> spawned sub_task` span hierarchy might seem unexpected, but it's correct.

Here's why:
1. We instrument the future with the "spawned sub_task" span, making it the direct parent of any logs within the future.
1. This instrumentation happens before the future is spawned on a new thread, where it would have a new context, so it captures `work` as its parent "span context".
1. When the future executes, it carries this constructed span information with it, maintaining the correct hierarchy even on a different thread.

This approach effectively bridges the span context across thread boundaries.

Just to more clearly show the `spawned sub_task` span is created on thread ID 1, the code can be refactored as follow:

```rust
#[instrument]
async fn work() {
    info!("starting work");

    let future = sub_task().instrument(tracing::info_span!("spawned sub_task"));
    let _result = tokio::spawn(future).await;
}
```

The instrumented future is clearly created in the `work` context.

### `JoinSet` again
If we now switch the code back to a `JoinSet` then everything is still fine.

```rust
#[instrument]
async fn work() {
    info!("starting work");

    let mut set = JoinSet::new();

    let future = sub_task().instrument(tracing::info_span!("spawned sub_task"));
    set.spawn(future);

    while let Some(_) = set.join_next().await {}
}
```

{% terminal_output() %}
  [2m2024-08-20T12:42:47.327459Z[0m [32m INFO[0m  [32min main[0m
    [2;3mat[0m src/main.rs:17 [2;3mon[0m ThreadId(1)

  [2m2024-08-20T12:42:47.327669Z[0m [32m INFO[0m  [32mstarting work[0m
    [2;3mat[0m src/main.rs:24 [2;3mon[0m ThreadId(1)
    [2;3min[0m [1mwork[0m

  [2m2024-08-20T12:42:47.327713Z[0m [32m INFO[0m  [32mmaking sub task[0m
    [2;3mat[0m src/main.rs:37 [2;3mon[0m ThreadId(1)
    [2;3min[0m [1msub_task[0m
    [2;3min[0m [1mwork[0m

  [2m2024-08-20T12:42:47.327852Z[0m [32m INFO[0m  [32mperforming task[0m
    [2;3mat[0m src/main.rs:40 [2;3mon[0m ThreadId(17)
    [2;3min[0m [1mspawned sub_task[0m
    [2;3min[0m [1mwork[0m
{% end %}

## Conclusion
This article addressed a specific issue where tracing events were not correctly associated with their parent spans when using futures and JoinSet in Rust.
We explored the root cause: the loss of tracing context when futures are executed on different threads.

The solution lies in using the `.instrument()` method to explicitly attach spans to futures before they're spawned.
This ensures that the correct span hierarchy is maintained across thread boundaries, resulting in accurate and meaningful tracing logs.

When working with asynchronous code in Rust that uses `spawn` or `JoinSet`, remember to manually instrument your futures to maintain proper tracing context.
