+++
title = "Mastering Dependency Injection in Rust: Using a macro part 1"
description = "Explore how to simplify dependency injection in Rust using a custom macro. Learn about concrete types, trait-based dependencies, dynamic traits, chaining, and async dependencies with the despatma crate."
[taxonomies]
tags = ["Rust", "Dependency Injection", "Software Design", "DesPatMa", "Software Architecture"]
categories = ["Rust Dependency Injection"]
+++

In the last post of this series, we [crafted a manual dependency container](@/blog/2024-08-08-manual-dependency-injection-rust.md) to understand how dependency injection might work in Rust.
In this post we are going to look at a minimal macro implementation to automate the wiring that had to be done in the manual solution.

By the end of the last post, we had a `DependencyContainer` implementation that was almost 130 lines of code.
While comprehensive, it required a lot of boilerplate and manual wiring.
I mentioned that a macro could generate all of the public functions for us.
It's now time to see what that macro will look like.

I decided to add the macro to the `despatma` crate.
This crate is an acronym for **Des**ign **Pat**tern **Ma**cros.
I created it a few years ago with the intent to have it be the goto crate for design pattern helper macros.

In the last post we discussed a bunch of dependency injection features.
But this first iteration of the macro only supports the following:
- [Concrete Type Dependencies](@/blog/2024-08-08-manual-dependency-injection-rust.md#concrete-type-dependencies)
- [Trait-Based Dependencies](@/blog/2024-08-08-manual-dependency-injection-rust.md#trait-based-dependencies)
- [Dynamic Trait Dependencies](@/blog/2024-08-08-manual-dependency-injection-rust.md#dynamic-trait-dependencies)
- [Chaining Dependencies](@/blog/2024-08-08-manual-dependency-injection-rust.md#chaining-dependencies)
- [Async Dependencies](@/blog/2024-08-08-manual-dependency-injection-rust.md#an-async-dependency)

Let's see how each type can help us simplify the manual dependency container.

## Concrete Type Dependencies
Again, this is the simplest case.
Here's how we can use the macro for concrete type dependencies:

```rust
use despatma::dependency_container;

#[dependency_container]
impl DependencyContainer {
    fn configuration_manager(&self) -> ConfigurationManager {
        ConfigurationManager::new()
    }
}
```

This code is essentially repeating the `impl` block from the manual implementation.
This creates a struct called `DependencyContainer` with a `configuration_manager()` method to get a `ConfigurationManager`.

Under the hood, the macro copies this method to the `create_*` method of the manual implementation.
The macro then creates a public `configuration_manager()` method which does all the resolves this dependency might need.
We'll get to resolution in the [Chaining Dependencies](#chaining-dependencies) section.

## Trait-Based Dependencies
Trait-based dependencies are the main reason for using Dependency Injection, as we saw in the manual post.
Here's how we can implement them with our macro:

```rust
#[dependency_container]
impl Dependencies {
    fn data_collector(&self) -> impl DataCollector {
        SimpleDataCollector::new("api_key".to_string())
    }
}
```

We again just use a `impl` return type instead.
This keeps our container simple by not introducing any generic on it.
Generics will just make it harder to pass this struct to functions later.

## Chaining Dependencies
In real-world scenarios, dependencies often depend on other dependencies.
For instance, our data collector should get its API key from the `ConfigurationManager`.
Here's how we can specify that:

```rust
#[dependency_container]
impl DependencyContainer {
    fn configuration_manager(&self) -> ConfigurationManager {
        ConfigurationManager::new()
    }

    fn data_collector(
        &self,
        configuration_manager: ConfigurationManager,
    ) -> impl DataCollector {
        SimpleDataCollector::new(configuration_manager.api_key)
    }
}


pub trait DataCollector {
    fn collect_data(&self) -> Vec<String>;
}
```

The macro will take care of wiring these dependencies correctly when it makes the public method for data collector.
The wiring happens because the `configuration_manager()` method has the same name as the `configuration_manager` function parameter in the `data_collector()` function.

Developers can use the following code to get a data collector:

```rust
let dependency_container = DependencyContainer::new();
let data_collector = dependency_container.data_collector();
```

Notice how the `data_collector()` method takes no arguments now.
This means developers don't need to know about the data collector's dependencies to get access to one.
The macro fully takes care of resolving the dependencies correctly.
This significantly simplifies the usage of our dependencies while maintaining the correct dependency chain.

The macro also generated the `new()` method for our dependency container.

## Dynamic Trait Dependencies
Sometimes, we need to choose between different implementations of a trait at runtime.
Our macro supports this use case as well:

```rust
use auto_impl::auto_impl;

#[dependency_container]
impl DependencyContainer {
    // ConfigurationManager as before

    fn data_collector(
        &self,
        configuration_manager: ConfigurationManager,
    ) -> impl DataCollector {
        let data_collector: Box<dyn DataCollector> = if let Some(api_key) = configuration_manager.get_api_key() {
            Box::new(SimpleDataCollector::new(api_key.to_string()))
        } else {
            Box::new(SqlDataCollector::new(
                configuration_manager
                    .get_database_connection_string()
                    .expect("api key or connection string to be set")
                    .to_string(),
            ))
        };

        data_collector
    }
}

// Use [auto_impl] to also implement the trait for any [Box]ed type
#[auto_impl(Box)]
pub trait DataCollector {
    fn collect_data(&self) -> Vec<String>;
}
```

In this example, we're using a `Box<dyn DataCollector>` variable to allow for runtime polymorphism.
We also use the `auto_impl` attribute to ensures that our `DataCollector` trait is implemented for boxed types as well.

Notice however that the function still returns a `impl DataCollector` to make it easy to swap out the concrete data collectors.

## Async Dependencies
Modern applications often deal with asynchronous operations.
Our macro supports async dependencies seamlessly:

```rust
#[dependency_container]
impl DependencyContainer {
    async fn configuration_manager(&self) -> ConfigurationManager {
        ConfigurationManager::new().await
    }

    // DataCollector as before
    // Aka. it stays non-async
}
```

With this setup, developers can use async-await syntax to resolve dependencies:

```rust
let dependency_container = DependencyContainer::new();
let data_collector = dependency_container.data_collector().await;
```

The macro automatically handles the propagation of `async` up the dependency chain, ensuring that all necessary awaits are in place.
So the `data_collector()` method does not need to be async just because it is an `async` dependency.
This would make it mentally taxing for developers to keep track of when a component needs to be `async` just because it has an `async` dependency.
So this makes it easier as developers only have to add async-await syntax to the resolvers which truly need to be async.

## Comparison with Manual Approach
Compared to our manual implementation from the previous post, this macro-based approach offers several advantages:

1. Reduced boilerplate: We no longer have to make a private `create_*`method.
And a public method to hide the dependencies needed to get any single object.
Instead we now only make one function and the macro creates the other one for us.
1. Automatic wiring: Dependencies are automatically resolved based on method names, eliminating the need for manual wiring.
1. Simplified usage: Developers only have to add async-await syntax to the functions that need them.
The macro takes care of adding it to any parent dependencies that might need it.

However, it's worth noting that this approach does have some limitations compared to the manual version, such as the current lack of support for scoped or singleton lifetimes.

## Conclusion
The `dependency_container` macro significantly simplifies the process of implementing dependency injection in Rust.
It automates much of the boilerplate we saw in our manual implementation while maintaining Rust's strong type safety and performance characteristics.

By supporting concrete types, trait-based dependencies, dynamic trait dependencies, chained dependencies, and async dependencies, this macro covers a wide range of use cases.
It allows developers to focus on defining their dependencies and their relationships, rather than on the mechanics of wiring them together.

However, it's important to note that this is just the first iteration of the macro.
It doesn't yet support some advanced features like scoped or singleton lifetimes, or lazy dependencies.
These are areas for future development.
We'll explore these more advanced cases in the next post.

Remember, while tools like this macro can greatly simplify our code, the key to effective dependency injection lies in good system design.
Always strive for loose coupling and high cohesion in your code, and let tools like this macro help you achieve those goals more easily.

For more detailed information, check out the [official `dependency_container` documentation](https://docs.rs/despatma/latest/despatma/attr.dependency_container.html).
