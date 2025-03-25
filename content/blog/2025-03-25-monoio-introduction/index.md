+++
title = "Introduction to Monoio: A High-Performance Rust Runtime"
description = "An in-depth look at Monoio, a high-performance Rust async runtime based on io_uring"
[taxonomies]
tags = ["Rust", "Async Runtime", "io_uring", "Performance"]
categories = ["Monoio Proxy Series"]
+++

## Background

Several months ago, a potential client approached me with a request to build "the fastest HTTP proxy in Rust using the Monoio runtime."
This led me into several days of research to determine if Monoio was mature enough for an HTTP proxy implementation and what such an implementation might look like.

While the client ultimately decided not to move the project forward, I found very limited documentation on Monoio.
I believe documenting my findings could benefit others interested in this promising runtime.
Now that I've had some time, I'm sharing what I discovered.
Spoiler alert: the performance results are breathtaking.

In this post, I'll introduce Monoio and explain the technical advantages it offers over other Rust async runtimes.
This will be the first in a series of posts where I'll progressively build and benchmark increasingly complex examples using Monoio.

## What is Monoio?

Monoio is an asynchronous runtime for Rust, similar to the popular Tokio runtime.
However, it is designed with a different set of priorities and architecture to Tokio.
Created by ByteDance (the company behind TikTok), Monoio is specifically built as a thread-per-core runtime that leverages [io\_uring](https://man7.org/linux/man-pages/man7/io_uring.7.html) on Linux for maximum performance.

Unlike Tokio, which is designed to be a general-purpose runtime with work-stealing schedulers that distribute tasks across threads, Monoio follows a thread-per-core model where tasks are pinned to specific threads.
This approach eliminates the need for synchronization between threads, potentially offering significant performance benefits for certain workloads.
I think it is important to repeat that Monoio should not be used for everything.
It only has performance benefits for specific workloads which I cover below.

## What Makes Monoio Different?

There are several key differences that distinguish Monoio from other Rust async runtimes:

### 1. Thread-per-core Architecture

Monoio is designed with a thread-per-core model, where:

- Each thread executes only its own tasks without work stealing
- The task queue is thread-local, eliminating locks and contention
- Cross-thread operations are minimized, optimizing cache performance
- Tasks on a thread never move to another thread

This approach is similar to how high-performance servers are designed, including:
- [NGINX](http://nginx.org/en/docs/ngx_core_module.html#worker_cpu_affinity) with its `worker_cpu_affinity` directive
- [HAProxy](http://cbonte.github.io/haproxy-dconv/1.8/configuration.html#cpu-map) through its `cpu-map` option
- [Envoy](https://blog.envoyproxy.io/envoy-threading-model-a8d44b922310), which has an in-depth explanation of their threading model

While it may not fully utilize CPU resources when workloads are unevenly distributed, it excels at network-heavy workloads with predictable patterns.

### 2. io\_uring Integration

Monoio was designed from the start to leverage io\_uring, a relatively new [Linux kernel interface introduced in 2019](https://kernel.dk/io_uring.pdf) that provides a more efficient way to perform I/O operations.
This matters because io\_uring significantly reduces syscall overhead and context switches, resulting in better performance for I/O-heavy workloads.

Instead of using traditional epoll-based I/O, Monoio prioritizes io\_uring while maintaining fallback support for epoll (Linux) and kqueue (macOS).

### 3. Unique I/O Abstraction

To fully utilize io\_uring's capabilities, Monoio implements a different I/O abstraction than what is found in Tokio or the standard library.
The key difference lies in buffer ownership:

- **In Tokio/std**: You provide a reference to a buffer during I/O operations, and maintain ownership
- **In Monoio**: You give ownership of the buffer to the runtime (known as "rent"), which returns it to you once the operation completes

This ownership model is necessary because when using io\_uring, the kernel needs direct access to your buffers, so the runtime must ensure those buffers remain valid throughout the operation.

## What is io\_uring and Why Does it Matter?

The io\_uring interface was [introduced in Linux 5.1](https://www.phoronix.com/news/Linux-io_uring-Fast-Efficient) and represents a significant advancement in how applications interact with the kernel for I/O operations.

### Traditional I/O vs. io\_uring

In traditional asynchronous I/O models like epoll:

1. Applications must first check if an I/O resource is ready (e.g., via epoll_wait)
2. Once ready, they make separate system calls to perform the actual I/O
3. This requires at least two context switches per I/O operation

With io\_uring, applications:

1. Submit I/O requests to a submission queue that is shared with the kernel
2. The kernel processes these requests asynchronously. Ie the application does not make a separate system call to perform the I/O.
3. Results appear in a completion queue

The key advantages include:

- **Reduced context switches**: Applications can submit multiple I/O operations with a single system call
- **Batched operations**: Multiple operations can be processed in batches
- **True asynchronous file I/O**: Unlike traditional interfaces, io\_uring enables genuinely asynchronous file operations
- **Zero-copy operation**: The kernel can directly access application buffers

## When is Monoio Faster?

Let's visualize the difference between a thread-per-core model and a work-stealing model with a simple example.
Imagine we have an application with two threads and five tasks:

{% excalidraw() %}
{
  "type": "excalidraw",
  "version": 2,
  "source": "https://excalidraw.com",
  "elements": [
    {
      "id": "NzNm-wa_XySrWPvtBO1ht",
      "type": "text",
      "x": 334,
      "y": 339,
      "width": 87.18333435058594,
      "height": 25,
      "angle": 0,
      "strokeColor": "#1e1e1e",
      "backgroundColor": "transparent",
      "fillStyle": "solid",
      "strokeWidth": 2,
      "strokeStyle": "solid",
      "roughness": 1,
      "opacity": 100,
      "groupIds": [],
      "frameId": null,
      "index": "a0",
      "roundness": null,
      "seed": 570152665,
      "version": 31,
      "versionNonce": 1153250711,
      "isDeleted": false,
      "boundElements": null,
      "updated": 1742892720152,
      "link": null,
      "locked": false,
      "text": "Thread 1",
      "fontSize": 20,
      "fontFamily": 1,
      "textAlign": "left",
      "verticalAlign": "top",
      "containerId": null,
      "originalText": "Thread 1",
      "autoResize": true,
      "lineHeight": 1.25
    },
    {
      "id": "-zZvlQ8kZEz_mKPIZuMb5",
      "type": "text",
      "x": 334,
      "y": 384.5,
      "width": 92.6500015258789,
      "height": 25,
      "angle": 0,
      "strokeColor": "#1e1e1e",
      "backgroundColor": "transparent",
      "fillStyle": "solid",
      "strokeWidth": 2,
      "strokeStyle": "solid",
      "roughness": 1,
      "opacity": 100,
      "groupIds": [],
      "frameId": null,
      "index": "a1",
      "roundness": null,
      "seed": 347755095,
      "version": 60,
      "versionNonce": 965537431,
      "isDeleted": false,
      "boundElements": null,
      "updated": 1742892722535,
      "link": null,
      "locked": false,
      "text": "Thread 2",
      "fontSize": 20,
      "fontFamily": 1,
      "textAlign": "left",
      "verticalAlign": "top",
      "containerId": null,
      "originalText": "Thread 2",
      "autoResize": true,
      "lineHeight": 1.25
    },
    {
      "id": "DACdMeoABp1oKCdzjDUkt",
      "type": "rectangle",
      "x": 451,
      "y": 336.5,
      "width": 37.999999999999986,
      "height": 30,
      "angle": 0,
      "strokeColor": "#1e1e1e",
      "backgroundColor": "#ffc94d",
      "fillStyle": "hachure",
      "strokeWidth": 1,
      "strokeStyle": "solid",
      "roughness": 1,
      "opacity": 100,
      "groupIds": [],
      "frameId": null,
      "index": "a2",
      "roundness": null,
      "seed": 1289145719,
      "version": 166,
      "versionNonce": 135730455,
      "isDeleted": false,
      "boundElements": [
        {
          "type": "text",
          "id": "XsYMaplN-p1VqZAH4K79i"
        }
      ],
      "updated": 1742892687796,
      "link": null,
      "locked": false
    },
    {
      "id": "XsYMaplN-p1VqZAH4K79i",
      "type": "text",
      "x": 466.5833332538605,
      "y": 341.5,
      "width": 6.833333492279053,
      "height": 20,
      "angle": 0,
      "strokeColor": "#1e1e1e",
      "backgroundColor": "#f08c00",
      "fillStyle": "hachure",
      "strokeWidth": 1,
      "strokeStyle": "solid",
      "roughness": 1,
      "opacity": 100,
      "groupIds": [],
      "frameId": null,
      "index": "a2G",
      "roundness": null,
      "seed": 437809913,
      "version": 3,
      "versionNonce": 118049177,
      "isDeleted": false,
      "boundElements": null,
      "updated": 1742892688344,
      "link": null,
      "locked": false,
      "text": "1",
      "fontSize": 16,
      "fontFamily": 1,
      "textAlign": "center",
      "verticalAlign": "middle",
      "containerId": "DACdMeoABp1oKCdzjDUkt",
      "originalText": "1",
      "autoResize": true,
      "lineHeight": 1.25
    },
    {
      "id": "GejSxhZ0cD7hqmnL4EsTF",
      "type": "rectangle",
      "x": 489,
      "y": 336.5,
      "width": 23.716666221618652,
      "height": 30,
      "angle": 0,
      "strokeColor": "#1e1e1e",
      "backgroundColor": "#ffd980",
      "fillStyle": "hachure",
      "strokeWidth": 1,
      "strokeStyle": "solid",
      "roughness": 1,
      "opacity": 100,
      "groupIds": [],
      "frameId": null,
      "index": "a2V",
      "roundness": null,
      "seed": 2028107447,
      "version": 198,
      "versionNonce": 1943854359,
      "isDeleted": false,
      "boundElements": [
        {
          "type": "text",
          "id": "pZQcm7LeljK8_TCFppWLc"
        }
      ],
      "updated": 1742892730802,
      "link": null,
      "locked": false
    },
    {
      "id": "pZQcm7LeljK8_TCFppWLc",
      "type": "text",
      "x": 495.9916663169861,
      "y": 341.5,
      "width": 9.733333587646484,
      "height": 20,
      "angle": 0,
      "strokeColor": "#1e1e1e",
      "backgroundColor": "#f08c00",
      "fillStyle": "hachure",
      "strokeWidth": 1,
      "strokeStyle": "solid",
      "roughness": 1,
      "opacity": 100,
      "groupIds": [],
      "frameId": null,
      "index": "a2d",
      "roundness": null,
      "seed": 1212032057,
      "version": 12,
      "versionNonce": 2022646327,
      "isDeleted": false,
      "boundElements": null,
      "updated": 1742892730802,
      "link": null,
      "locked": false,
      "text": "3",
      "fontSize": 16,
      "fontFamily": 1,
      "textAlign": "center",
      "verticalAlign": "middle",
      "containerId": "GejSxhZ0cD7hqmnL4EsTF",
      "originalText": "3",
      "autoResize": true,
      "lineHeight": 1.25
    },
    {
      "id": "mW2eaK9PUOvgOSQEiMWVR",
      "type": "rectangle",
      "x": 512.716666,
      "y": 336.5,
      "width": 55.999999999999964,
      "height": 30,
      "angle": 0,
      "strokeColor": "#1e1e1e",
      "backgroundColor": "#b38300",
      "fillStyle": "hachure",
      "strokeWidth": 1,
      "strokeStyle": "solid",
      "roughness": 1,
      "opacity": 100,
      "groupIds": [],
      "frameId": null,
      "index": "a2l",
      "roundness": null,
      "seed": 35505433,
      "version": 251,
      "versionNonce": 270486425,
      "isDeleted": false,
      "boundElements": [
        {
          "type": "text",
          "id": "7ZjJH93xgiOhB84DJraVE"
        }
      ],
      "updated": 1742892818602,
      "link": null,
      "locked": false
    },
    {
      "id": "7ZjJH93xgiOhB84DJraVE",
      "type": "text",
      "x": 535.7749993969117,
      "y": 341.5,
      "width": 9.883333206176758,
      "height": 20,
      "angle": 0,
      "strokeColor": "#1e1e1e",
      "backgroundColor": "#f08c00",
      "fillStyle": "hachure",
      "strokeWidth": 1,
      "strokeStyle": "solid",
      "roughness": 1,
      "opacity": 100,
      "groupIds": [],
      "frameId": null,
      "index": "a2t",
      "roundness": null,
      "seed": 2018227897,
      "version": 29,
      "versionNonce": 88371321,
      "isDeleted": false,
      "boundElements": null,
      "updated": 1742892818602,
      "link": null,
      "locked": false,
      "text": "5",
      "fontSize": 16,
      "fontFamily": 1,
      "textAlign": "center",
      "verticalAlign": "middle",
      "containerId": "mW2eaK9PUOvgOSQEiMWVR",
      "originalText": "5",
      "autoResize": true,
      "lineHeight": 1.25
    },
    {
      "id": "mxHN7M9ikdD8s3IECN3XL",
      "type": "rectangle",
      "x": 451,
      "y": 382,
      "width": 54.00000000000001,
      "height": 30,
      "angle": 0,
      "strokeColor": "#1e1e1e",
      "backgroundColor": "#e6a600",
      "fillStyle": "hachure",
      "strokeWidth": 1,
      "strokeStyle": "solid",
      "roughness": 1,
      "opacity": 100,
      "groupIds": [],
      "frameId": null,
      "index": "a3",
      "roundness": null,
      "seed": 1438844375,
      "version": 166,
      "versionNonce": 823297625,
      "isDeleted": false,
      "boundElements": [
        {
          "type": "text",
          "id": "UWRpdfxQC0YmOVXfIwwhG"
        },
        {
          "id": "Pc5IWlNLJbqSo6A9_7Eoh",
          "type": "arrow"
        }
      ],
      "updated": 1742893326819,
      "link": null,
      "locked": false
    },
    {
      "id": "UWRpdfxQC0YmOVXfIwwhG",
      "type": "text",
      "x": 472.40000009536743,
      "y": 387,
      "width": 11.199999809265137,
      "height": 20,
      "angle": 0,
      "strokeColor": "#1e1e1e",
      "backgroundColor": "#f08c00",
      "fillStyle": "hachure",
      "strokeWidth": 1,
      "strokeStyle": "solid",
      "roughness": 1,
      "opacity": 100,
      "groupIds": [],
      "frameId": null,
      "index": "a3G",
      "roundness": null,
      "seed": 206394103,
      "version": 30,
      "versionNonce": 1344635929,
      "isDeleted": false,
      "boundElements": null,
      "updated": 1742893326820,
      "link": null,
      "locked": false,
      "text": "2",
      "fontSize": 16,
      "fontFamily": 1,
      "textAlign": "center",
      "verticalAlign": "middle",
      "containerId": "mxHN7M9ikdD8s3IECN3XL",
      "originalText": "2",
      "autoResize": true,
      "lineHeight": 1.25
    },
    {
      "id": "Ho7YOJB4MUuggKp5keOp5",
      "type": "rectangle",
      "x": 544,
      "y": 382,
      "width": 70,
      "height": 30,
      "angle": 0,
      "strokeColor": "#1e1e1e",
      "backgroundColor": "#e6a600",
      "fillStyle": "hachure",
      "strokeWidth": 1,
      "strokeStyle": "solid",
      "roughness": 1,
      "opacity": 100,
      "groupIds": [],
      "frameId": null,
      "index": "a3l",
      "roundness": null,
      "seed": 87640791,
      "version": 279,
      "versionNonce": 1641103575,
      "isDeleted": false,
      "boundElements": [
        {
          "id": "tW0LDhTpIm5DouK-HrvGa",
          "type": "text"
        },
        {
          "id": "doyVYaOdALUpH-vXgn082",
          "type": "arrow"
        }
      ],
      "updated": 1742893348135,
      "link": null,
      "locked": false
    },
    {
      "id": "tW0LDhTpIm5DouK-HrvGa",
      "type": "text",
      "x": 573.4000000953674,
      "y": 387,
      "width": 11.199999809265137,
      "height": 20,
      "angle": 0,
      "strokeColor": "#1e1e1e",
      "backgroundColor": "#f08c00",
      "fillStyle": "hachure",
      "strokeWidth": 1,
      "strokeStyle": "solid",
      "roughness": 1,
      "opacity": 100,
      "groupIds": [],
      "frameId": null,
      "index": "a3t",
      "roundness": null,
      "seed": 2113319449,
      "version": 142,
      "versionNonce": 1958199383,
      "isDeleted": false,
      "boundElements": null,
      "updated": 1742893337855,
      "link": null,
      "locked": false,
      "text": "2",
      "fontSize": 16,
      "fontFamily": 1,
      "textAlign": "center",
      "verticalAlign": "middle",
      "containerId": "Ho7YOJB4MUuggKp5keOp5",
      "originalText": "2",
      "autoResize": true,
      "lineHeight": 1.25
    },
    {
      "id": "vckpdQ3tdWhLTaxNgXAZa",
      "type": "rectangle",
      "x": 687,
      "y": 382,
      "width": 94,
      "height": 30,
      "angle": 0,
      "strokeColor": "#1e1e1e",
      "backgroundColor": "#e6a600",
      "fillStyle": "hachure",
      "strokeWidth": 1,
      "strokeStyle": "solid",
      "roughness": 1,
      "opacity": 100,
      "groupIds": [],
      "frameId": null,
      "index": "a3v",
      "roundness": null,
      "seed": 1795974841,
      "version": 326,
      "versionNonce": 984325495,
      "isDeleted": false,
      "boundElements": [
        {
          "id": "73xP5nmO9_uZojlbta3tc",
          "type": "text"
        }
      ],
      "updated": 1742893337855,
      "link": null,
      "locked": false
    },
    {
      "id": "73xP5nmO9_uZojlbta3tc",
      "type": "text",
      "x": 728.4000000953674,
      "y": 387,
      "width": 11.199999809265137,
      "height": 20,
      "angle": 0,
      "strokeColor": "#1e1e1e",
      "backgroundColor": "#f08c00",
      "fillStyle": "hachure",
      "strokeWidth": 1,
      "strokeStyle": "solid",
      "roughness": 1,
      "opacity": 100,
      "groupIds": [],
      "frameId": null,
      "index": "a3x",
      "roundness": null,
      "seed": 1734163799,
      "version": 189,
      "versionNonce": 208066199,
      "isDeleted": false,
      "boundElements": null,
      "updated": 1742893337855,
      "link": null,
      "locked": false,
      "text": "2",
      "fontSize": 16,
      "fontFamily": 1,
      "textAlign": "center",
      "verticalAlign": "middle",
      "containerId": "vckpdQ3tdWhLTaxNgXAZa",
      "originalText": "2",
      "autoResize": true,
      "lineHeight": 1.25
    },
    {
      "id": "SIzTwHv6kBdPap-mZ-wbs",
      "type": "rectangle",
      "x": 505,
      "y": 382,
      "width": 38.99999999999999,
      "height": 30,
      "angle": 0,
      "strokeColor": "#1e1e1e",
      "backgroundColor": "#805e00",
      "fillStyle": "hachure",
      "strokeWidth": 1,
      "strokeStyle": "solid",
      "roughness": 1,
      "opacity": 100,
      "groupIds": [],
      "frameId": null,
      "index": "a4",
      "roundness": null,
      "seed": 389769239,
      "version": 247,
      "versionNonce": 815655863,
      "isDeleted": false,
      "boundElements": [
        {
          "type": "text",
          "id": "iympUCwJwzDnKwjEIUWAr"
        },
        {
          "id": "doyVYaOdALUpH-vXgn082",
          "type": "arrow"
        }
      ],
      "updated": 1742893337855,
      "link": null,
      "locked": false
    },
    {
      "id": "iympUCwJwzDnKwjEIUWAr",
      "type": "text",
      "x": 519.8166666030884,
      "y": 387,
      "width": 9.366666793823242,
      "height": 20,
      "angle": 0,
      "strokeColor": "#1e1e1e",
      "backgroundColor": "#f08c00",
      "fillStyle": "hachure",
      "strokeWidth": 1,
      "strokeStyle": "solid",
      "roughness": 1,
      "opacity": 100,
      "groupIds": [],
      "frameId": null,
      "index": "a5",
      "roundness": null,
      "seed": 2134762873,
      "version": 80,
      "versionNonce": 594894039,
      "isDeleted": false,
      "boundElements": null,
      "updated": 1742893337855,
      "link": null,
      "locked": false,
      "text": "4",
      "fontSize": 16,
      "fontFamily": 1,
      "textAlign": "center",
      "verticalAlign": "middle",
      "containerId": "SIzTwHv6kBdPap-mZ-wbs",
      "originalText": "4",
      "autoResize": true,
      "lineHeight": 1.25
    },
    {
      "id": "jBTQWzelo0XEPe4SPfxsB",
      "type": "rectangle",
      "x": 614,
      "y": 382,
      "width": 73,
      "height": 30,
      "angle": 0,
      "strokeColor": "#1e1e1e",
      "backgroundColor": "#805e00",
      "fillStyle": "hachure",
      "strokeWidth": 1,
      "strokeStyle": "solid",
      "roughness": 1,
      "opacity": 100,
      "groupIds": [],
      "frameId": null,
      "index": "a6",
      "roundness": null,
      "seed": 223302615,
      "version": 306,
      "versionNonce": 482824983,
      "isDeleted": false,
      "boundElements": [
        {
          "id": "WwP3O6MB37a6jDSqArOzf",
          "type": "text"
        },
        {
          "id": "k4n5tLCKm8gxFW0xWtD5l",
          "type": "arrow"
        }
      ],
      "updated": 1742893337855,
      "link": null,
      "locked": false
    },
    {
      "id": "WwP3O6MB37a6jDSqArOzf",
      "type": "text",
      "x": 645.8166666030884,
      "y": 387,
      "width": 9.366666793823242,
      "height": 20,
      "angle": 0,
      "strokeColor": "#1e1e1e",
      "backgroundColor": "#f08c00",
      "fillStyle": "hachure",
      "strokeWidth": 1,
      "strokeStyle": "solid",
      "roughness": 1,
      "opacity": 100,
      "groupIds": [],
      "frameId": null,
      "index": "a7",
      "roundness": null,
      "seed": 820099353,
      "version": 141,
      "versionNonce": 1220204599,
      "isDeleted": false,
      "boundElements": null,
      "updated": 1742893337855,
      "link": null,
      "locked": false,
      "text": "4",
      "fontSize": 16,
      "fontFamily": 1,
      "textAlign": "center",
      "verticalAlign": "middle",
      "containerId": "jBTQWzelo0XEPe4SPfxsB",
      "originalText": "4",
      "autoResize": true,
      "lineHeight": 1.25
    },
    {
      "id": "RIZxJFmf-UZ12vO-aOeY8",
      "type": "rectangle",
      "x": 781,
      "y": 382,
      "width": 40,
      "height": 30,
      "angle": 0,
      "strokeColor": "#1e1e1e",
      "backgroundColor": "#805e00",
      "fillStyle": "hachure",
      "strokeWidth": 1,
      "strokeStyle": "solid",
      "roughness": 1,
      "opacity": 100,
      "groupIds": [],
      "frameId": null,
      "index": "a7G",
      "roundness": null,
      "seed": 2080482935,
      "version": 371,
      "versionNonce": 1856861815,
      "isDeleted": false,
      "boundElements": [
        {
          "id": "nU9ONrE0AQrFEiuiSuIlb",
          "type": "text"
        }
      ],
      "updated": 1742893337855,
      "link": null,
      "locked": false
    },
    {
      "id": "nU9ONrE0AQrFEiuiSuIlb",
      "type": "text",
      "x": 796.3166666030884,
      "y": 387,
      "width": 9.366666793823242,
      "height": 20,
      "angle": 0,
      "strokeColor": "#1e1e1e",
      "backgroundColor": "#f08c00",
      "fillStyle": "hachure",
      "strokeWidth": 1,
      "strokeStyle": "solid",
      "roughness": 1,
      "opacity": 100,
      "groupIds": [],
      "frameId": null,
      "index": "a7V",
      "roundness": null,
      "seed": 2066440313,
      "version": 206,
      "versionNonce": 1959104407,
      "isDeleted": false,
      "boundElements": null,
      "updated": 1742893337855,
      "link": null,
      "locked": false,
      "text": "4",
      "fontSize": 16,
      "fontFamily": 1,
      "textAlign": "center",
      "verticalAlign": "middle",
      "containerId": "RIZxJFmf-UZ12vO-aOeY8",
      "originalText": "4",
      "autoResize": true,
      "lineHeight": 1.25
    },
    {
      "id": "xEYg8eeNty3H6oPgbZy6L",
      "type": "text",
      "x": 492,
      "y": 494,
      "width": 97.83333587646484,
      "height": 20,
      "angle": 0,
      "strokeColor": "#1e1e1e",
      "backgroundColor": "#f08c00",
      "fillStyle": "hachure",
      "strokeWidth": 1,
      "strokeStyle": "solid",
      "roughness": 1,
      "opacity": 100,
      "groupIds": [],
      "frameId": null,
      "index": "a9",
      "roundness": null,
      "seed": 96502713,
      "version": 154,
      "versionNonce": 2069553047,
      "isDeleted": false,
      "boundElements": [
        {
          "id": "Pc5IWlNLJbqSo6A9_7Eoh",
          "type": "arrow"
        },
        {
          "id": "doyVYaOdALUpH-vXgn082",
          "type": "arrow"
        },
        {
          "id": "k4n5tLCKm8gxFW0xWtD5l",
          "type": "arrow"
        }
      ],
      "updated": 1742893105325,
      "link": null,
      "locked": false,
      "text": "Await points",
      "fontSize": 16,
      "fontFamily": 1,
      "textAlign": "left",
      "verticalAlign": "top",
      "containerId": null,
      "originalText": "Await points",
      "autoResize": true,
      "lineHeight": 1.25
    },
    {
      "id": "Pc5IWlNLJbqSo6A9_7Eoh",
      "type": "arrow",
      "x": 514.4702127305671,
      "y": 481.6136702956422,
      "width": 9.803496992520252,
      "height": 53.61367029564224,
      "angle": 0,
      "strokeColor": "#1e1e1e",
      "backgroundColor": "#f08c00",
      "fillStyle": "hachure",
      "strokeWidth": 1,
      "strokeStyle": "solid",
      "roughness": 1,
      "opacity": 100,
      "groupIds": [],
      "frameId": null,
      "index": "aA",
      "roundness": {
        "type": 2
      },
      "seed": 991124473,
      "version": 717,
      "versionNonce": 272742071,
      "isDeleted": false,
      "boundElements": null,
      "updated": 1742893346273,
      "link": null,
      "locked": false,
      "points": [
        [
          0,
          0
        ],
        [
          -5.470212730567141,
          -23.61367029564218
        ],
        [
          -9.803496992520252,
          -53.61367029564224
        ]
      ],
      "lastCommittedPoint": null,
      "startBinding": {
        "elementId": "xEYg8eeNty3H6oPgbZy6L",
        "focus": -0.4149761504375015,
        "gap": 12.38632970435782
      },
      "endBinding": {
        "elementId": "mxHN7M9ikdD8s3IECN3XL",
        "focus": -0.7607659657124602,
        "gap": 15.999999999999943
      },
      "startArrowhead": null,
      "endArrowhead": "arrow",
      "elbowed": false
    },
    {
      "id": "doyVYaOdALUpH-vXgn082",
      "type": "arrow",
      "x": 556.8756443470178,
      "y": 482.1961524227066,
      "width": 11.92587797457395,
      "height": 54.87833135943026,
      "angle": 0,
      "strokeColor": "#1e1e1e",
      "backgroundColor": "#f08c00",
      "fillStyle": "hachure",
      "strokeWidth": 1,
      "strokeStyle": "solid",
      "roughness": 1,
      "opacity": 100,
      "groupIds": [],
      "frameId": null,
      "index": "aC",
      "roundness": {
        "type": 2
      },
      "seed": 1263729591,
      "version": 167,
      "versionNonce": 274318329,
      "isDeleted": false,
      "boundElements": null,
      "updated": 1742893353644,
      "link": null,
      "locked": false,
      "points": [
        [
          0,
          0
        ],
        [
          4.124355652982217,
          -26.196152422706575
        ],
        [
          -7.801522321591733,
          -54.87833135943026
        ]
      ],
      "lastCommittedPoint": null,
      "startBinding": {
        "elementId": "xEYg8eeNty3H6oPgbZy6L",
        "focus": 0.24808640776232757,
        "gap": 11.803847577293425
      },
      "endBinding": {
        "elementId": "Ho7YOJB4MUuggKp5keOp5",
        "focus": 1.0314023553121747,
        "gap": 15.317821063276313
      },
      "startArrowhead": null,
      "endArrowhead": "arrow",
      "elbowed": false
    },
    {
      "id": "k4n5tLCKm8gxFW0xWtD5l",
      "type": "arrow",
      "x": 593.501268998349,
      "y": 482.2567052435537,
      "width": 19.733176914335445,
      "height": 56.64361588937186,
      "angle": 0,
      "strokeColor": "#1e1e1e",
      "backgroundColor": "#f08c00",
      "fillStyle": "hachure",
      "strokeWidth": 1,
      "strokeStyle": "solid",
      "roughness": 1,
      "opacity": 100,
      "groupIds": [],
      "frameId": null,
      "index": "aD",
      "roundness": {
        "type": 2
      },
      "seed": 1688757465,
      "version": 306,
      "versionNonce": 817953495,
      "isDeleted": false,
      "boundElements": null,
      "updated": 1742893366643,
      "link": null,
      "locked": false,
      "points": [
        [
          0,
          0
        ],
        [
          16.49873100165098,
          -24.25670524355371
        ],
        [
          19.733176914335445,
          -56.64361588937186
        ]
      ],
      "lastCommittedPoint": null,
      "startBinding": {
        "elementId": "xEYg8eeNty3H6oPgbZy6L",
        "focus": 0.6783294172914905,
        "gap": 12.302792574183876
      },
      "endBinding": {
        "elementId": "jBTQWzelo0XEPe4SPfxsB",
        "focus": 0.9055204217866145,
        "gap": 13.634598447535769
      },
      "startArrowhead": null,
      "endArrowhead": "arrow",
      "elbowed": false
    }
  ],
  "appState": {
    "gridSize": 20,
    "gridStep": 5,
    "gridModeEnabled": false,
    "viewBackgroundColor": "transparent"
  },
  "files": {}
}
{% end %}

In this diagram, we can see how these tasks are distributed:

- Task 1: Which gets allocated to thread one and completed rather quickly.
- Task 2: Which gets allocated to thread two, but takes quite a while to complete and `awaits` a few times.
- Task 3: Which goes on thread one when the thread is open and completes quickly too.
- Task 4: Which gets allocated to thread two, but is also quite long with a few `await` points.
- Task 5: Which is allocated to thread one and completes quickly.

After these tasks are scheduled, no new tasks arrive for quite a while.
Tasks 2 and 4 block at `await` points, which allows the other tasks to make progress if possible.
Because Monoio has no work stealing, tasks 2 and 4 will stay on thread two while thread one remains idle until new work comes in.

A work-stealing runtime like Tokio could move task 2 or task 4 to thread one.
This would cause the moved task to complete faster, and possibly the other task too since it wouldn't have to wait for an await point to be started again.

This example demonstrates the fundamental tradeoff of the thread-per-core model: while it eliminates synchronization overhead and maximizes cache efficiency, it can lead to unbalanced resource utilization when tasks have varying completion times.

According to benchmarks from the Monoio team, their gateway implementation has outperformed NGINX in optimized benchmarks by up to 20%, and their RPC implementation showed a 26% performance improvement compared to the Tokio-based version - but these impressive results are primarily achieved in workloads where tasks are evenly distributed across cores.

Based on these characteristics, here are the scenarios where Monoio excels:

1. **Network-intensive workloads**: HTTP servers, proxies, gateways
2. **File I/O heavy operations**: Database-like workloads, file processing
3. **Scenarios with predictable task distribution**: Services where load can be evenly distributed across cores
4. **High throughput, low latency services**: When maximizing requests per second is critical

However, Monoio might not be the best choice for:

1. **CPU-bound workloads**: Where task scheduling flexibility matters more than I/O performance
2. **Workloads with unpredictable task distribution**: Where some threads might be idle while others are overloaded
3. **Applications requiring extensive ecosystem compatibility**: Where compatibility with the broader Tokio ecosystem is important

## Simple Monoio Applications

### Basic Single-Threaded Example

Let's start with a simple Monoio application that demonstrates the async runtime without networking:

```rust
use std::time::Duration;

use monoio::time::sleep;

// timer_enabled is required for sleep() to work
#[monoio::main(timer_enabled = true)]
async fn main() {
    println!(
        "Starting Monoio application on thread: {:?}",
        std::thread::current().id()
    );

    // Spawn a few tasks
    for i in 1..=3 {
        let task_id = i;
        monoio::spawn(async move {
            println!("Task {task_id} started");

            // Simulate some async work
            sleep(Duration::from_secs(1)).await;

            println!("Task {task_id} completed after 1s");
        });
    }

    // Main task does its own work
    println!("Main task doing work...");
    sleep(Duration::from_secs(2)).await;
    println!("Main task completed after 2s");
}
```

{% terminal_output() %}
Starting Monoio application on thread: ThreadId(1)
Main task doing work...
Task 1 started
Task 2 started
Task 3 started
Task 1 completed after 1s
Task 2 completed after 1s
Task 3 completed after 1s
Main task completed after 2s
{% end %}

This example demonstrates several important concepts:
1. The `#[monoio::main]` attribute that sets up the runtime with timer support
2. Spawning multiple tasks that run concurrently
3. Using async sleep to simulate non-blocking work

When you run this program, you'll notice that all tasks execute concurrently within a single thread. This is the most basic usage of Monoio and runs on a single core.

### Multi-Core Thread-Per-Core Example (Using macros)

Now let's see how to utilize multiple cores with Monoio's built-in multi-threading support:

```rust
use std::time::Duration;

use monoio::time::sleep;

#[monoio::main(timer_enabled = true, worker_threads = 2)]
async fn main() {
    let thread_id = std::thread::current().id();

    println!("Starting Monoio application on thread: {thread_id:?}",);

    // Spawn a few tasks
    for i in 1..=3 {
        let task_id = i;
        monoio::spawn(async move {
            println!("Task {task_id} started on thread {thread_id:?}");

            // Simulate some async work
            sleep(Duration::from_secs(1)).await;

            println!(
                "Task {task_id} completed on thread {thread_id:?} after 1s"
            );
        });
    }

    // Main task does its own work
    println!("Main task doing work on thread {thread_id:?}...");
    sleep(Duration::from_secs(2)).await;
    println!("Main task completed on thread {thread_id:?} after 2s");
}
```

{% terminal_output() %}
Starting Monoio application on thread: ThreadId(1)
Main task doing work on thread ThreadId(1)...
Task 1 started on thread ThreadId(1)
Task 2 started on thread ThreadId(1)
Task 3 started on thread ThreadId(1)
Starting Monoio application on thread: ThreadId(2)
Main task doing work on thread ThreadId(2)...
Task 1 started on thread ThreadId(2)
Task 2 started on thread ThreadId(2)
Task 3 started on thread ThreadId(2)
Task 1 completed on thread ThreadId(1) after 1s
Task 2 completed on thread ThreadId(1) after 1s
Task 3 completed on thread ThreadId(1) after 1s
Task 1 completed on thread ThreadId(2) after 1s
Task 2 completed on thread ThreadId(2) after 1s
Task 3 completed on thread ThreadId(2) after 1s
Main task completed on thread ThreadId(2) after 2s
Main task completed on thread ThreadId(1) after 2s
{% end %}

Notice an important difference from Tokio: the `worker_threads` parameter in `#[monoio::main]` actually executes the entire program on each worker thread, rather than distributing tasks across threads.
This is a key characteristic of Monoio's thread-per-core model.
Each thread runs its own complete instance of the application with isolated tasks.

### Multi-Core Thread-Per-Core Example (Production-Ready)
For a production environment, we typically want more control over thread creation and CPU affinity.
This example demonstrates how to create a thread for each available CPU core and bind each thread to its specific core:


```rust
use std::{num::NonZeroUsize, thread::available_parallelism, time::Duration};

use monoio::{IoUringDriver, time::sleep, utils::bind_to_cpu_set};

fn main() -> std::io::Result<()> {
    // Determine how many logical CPU cores are available
    let thread_count = available_parallelism().map_or(1, NonZeroUsize::get);
    println!("Starting with {thread_count} threads (one per logical CPU)");

    // Create threads for each core except the main one
    let threads: Vec<_> = (0..thread_count).map(start_thread_on_core).collect();

    // Wait for all threads to complete
    for thread in threads {
        thread.join().unwrap();
    }

    println!("All threads completed");

    Ok(())
}

fn start_thread_on_core(core: usize) -> std::thread::JoinHandle<()> {
    std::thread::spawn(move || {
        // Pin this thread to the specific CPU core - this must be done
        // inside the thread but before creating the runtime
        bind_to_cpu_set([core]).unwrap();

        // Create a runtime for this thread
        monoio::RuntimeBuilder::<IoUringDriver>::new()
            .enable_timer()
            .build()
            .expect("Failed to build runtime")
            .block_on(_main());
    })
}

async fn _main() {
    let thread_id = std::thread::current().id();

    println!("Starting Monoio application on thread: {thread_id:?}",);

    // Spawn a few tasks
    for i in 1..=3 {
        let task_id = i;
        monoio::spawn(async move {
            println!("Task {task_id} started on thread {thread_id:?}");

            // Simulate some async work
            sleep(Duration::from_secs(1)).await;

            println!(
                "Task {task_id} completed on thread {thread_id:?} after 1s"
            );
        });
    }

    // Main task does its own work
    println!("Main task doing work on thread {thread_id:?}...");
    sleep(Duration::from_secs(2)).await;
    println!("Main task completed on thread {thread_id:?} after 2s");
}
```

{% terminal_output() %}
Starting with 4 threads (one per logical CPU)
Starting Monoio application on thread: ThreadId(2)
Starting Monoio application on thread: ThreadId(3)
Main task doing work on thread ThreadId(2)...
Starting Monoio application on thread: ThreadId(4)
Starting Monoio application on thread: ThreadId(5)
Task 1 started on thread ThreadId(2)
Main task doing work on thread ThreadId(5)...
Main task doing work on thread ThreadId(4)...
Main task doing work on thread ThreadId(3)...
Task 1 started on thread ThreadId(4)
Task 2 started on thread ThreadId(2)
Task 3 started on thread ThreadId(2)
Task 1 started on thread ThreadId(5)
Task 2 started on thread ThreadId(5)
Task 3 started on thread ThreadId(5)
Task 1 started on thread ThreadId(3)
Task 2 started on thread ThreadId(3)
Task 3 started on thread ThreadId(3)
Task 2 started on thread ThreadId(4)
Task 3 started on thread ThreadId(4)
Task 1 completed on thread ThreadId(4) after 1s
Task 1 completed on thread ThreadId(5) after 1s
Task 2 completed on thread ThreadId(4) after 1s
Task 3 completed on thread ThreadId(4) after 1s
Task 2 completed on thread ThreadId(5) after 1s
Task 3 completed on thread ThreadId(5) after 1s
Task 1 completed on thread ThreadId(2) after 1s
Task 2 completed on thread ThreadId(2) after 1s
Task 3 completed on thread ThreadId(2) after 1s
Task 1 completed on thread ThreadId(3) after 1s
Task 2 completed on thread ThreadId(3) after 1s
Task 3 completed on thread ThreadId(3) after 1s
Main task completed on thread ThreadId(5) after 2s
Main task completed on thread ThreadId(3) after 2s
Main task completed on thread ThreadId(4) after 2s
Main task completed on thread ThreadId(2) after 2s
All threads completed
{% end %}

This production-ready approach offers several advantages over the simpler macro-based version:

1. **CPU affinity**: Each thread is explicitly bound to a specific logical CPU core with `bind_to_cpu_set`, preventing the OS scheduler from moving threads between cores and maximizing CPU cache utilization. Note that this uses all logical CPUs, including hyperthreaded cores.
2. **Error handling**: The code properly handles potential errors with `Result` returns, making it more robust for production environments.
3. **Full control**: You have complete control over thread creation, runtime configuration, and lifecycle management.
4. **Resource utilization**: It automatically scales to use all available CPU cores in the system.

The multi-core example demonstrates several important patterns for building high-performance applications with Monoio:

1. **Manual thread creation**: Unlike Tokio's multi-threaded runtime which handles thread creation internally, with Monoio you explicitly create threads for each core
2. **Separate runtimes per thread**: Each thread gets its own independent Monoio runtime
3. **Task isolation**: Tasks spawned on one thread never move to another thread
4. **No cross-thread synchronization**: No locks or shared data structures between threads

This approach is exactly what we'll need for our proxy, as it allows us to:
1. Maximize throughput by utilizing all cores
2. Minimize contention by keeping tasks isolated
3. Avoid synchronization overhead between threads
4. Take full advantage of CPU cache locality

Note the key differences from a Tokio application:
1. We use `#[monoio::main]` for simple cases or manually create runtimes for more control
2. With I/O operations, ownership of buffers is transferred (the "rent" pattern)
3. Tasks are always thread-local without any work stealing

## Conclusion

Monoio represents an exciting advancement in Rust async runtime technology, particularly for I/O-bound server applications.
By leveraging io\_uring and a thread-per-core architecture, it offers significant performance benefits for the right use cases.

The thread-per-core model isn't new — it's a proven approach used by high-performance servers like NGINX and Envoy.
What makes Monoio special is how it brings this architecture to Rust with native io\_uring support, potentially offering best-in-class performance for network services.

As we progress through this blog series, we'll build on these concepts to create increasingly sophisticated components:

1. First, we'll develop a basic HTTP server with Monoio and benchmark it against Hyper/Tokio
2. Next, we'll implement HTTP/2 protocol support
3. Then, we'll add TLS support and evaluate its performance impact
4. Finally, we'll create a complete proxy server with all these features

At each stage, we'll benchmark against both equivalent Tokio implementations and industry-standard proxies like NGINX, Caddy, Envoy, and HAProxy.
This will give us a clear picture of Monoio's real-world performance characteristics.

Stay tuned for the next post where we'll build a basic HTTP server with Monoio and benchmark it against an equivalent Hyper/Tokio implementation!
