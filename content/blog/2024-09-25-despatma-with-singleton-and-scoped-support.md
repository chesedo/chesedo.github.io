+++
title = "Mastering Dependency Injection in Rust: Despatma with Lifetimes"
description = "Learn how to use despatma to manage singleton, scoped, and transient dependencies in Rust. Explore practical examples and best practices for effective dependency lifetime management in your Rust applications."
[taxonomies]
tags = ["Rust", "Dependency Injection", "Software Design", "DesPatMa", "Software Architecture"]
categories = ["Rust Dependency Injection"]
+++

The next iteration of the `despatma` library is ready with [dependency lifetimes](@/blog/2024-08-08-manual-dependency-injection-rust.md#transient-dependencies) support.
This means the dependency container can manage dependencies with the singleton, scoped, and transient lifetimes.

As discussed in the [manual implementation of a dependency container](@/blog/2024-08-08-manual-dependency-injection-rust.md#lifetime-management), the three major dependency lifetimes are:
- **Singleton**: These dependencies are only constructed once when they are requested for the first time.
- **Scope**: These dependencies are only constructed once within a scope.
  A scope can be a web request, a batch run, etc.
- **Transient**: These dependencies are constructed anew every time they are requested.
  Technically `despatma` already had support for these as they don't require any special handling.

In this post we'll explore how dependencies can be made with these lifetimes using `despatma`.

Effective lifetime management in dependency injection is crucial for optimizing resource usage and ensuring correct application behavior.
It controls how often dependencies are instantiated and how long they live, directly impacting performance, memory usage, and state management.
For example, reading configuration files on every request would be inefficient, while using outdated configuration could lead to errors if we want to use it for hot-swapping components.
Proper lifetime management helps strike the right balance between efficiency and correctness.

## Singletons
In the previous post we made a [configuration manager](@/blog/2024-08-16-despatma-a-minimal-macro-for-dependency-injection.md#concrete-type-dependencies).
But in the manual implementation we realized this dependency should be a singleton as we'll only want to parse the config once. So let's make the `configuration_manager()` a singleton instead.

```rust
use despatma::dependency_container;

#[dependency_container]
impl DependencyContainer {
    #[Singleton]
    fn configuration_manager(&self) -> ConfigurationManager {
        ConfigurationManager::new()
    }
}
```

This is achieved by just adding the `#[Singleton]` attribute to the registration function.

### Side-effect dependencies
Another good candidate for singleton dependencies are setting up tracing.
This dependency won't construct an object, but does some side effect before the code gets to its main purpose.
This shows an example for setting up tracing as a side-effect singleton using `dependency_container`.

```rust
#[dependency_container]
impl DependencyContainer {
    #[Singleton]
    fn _tracing(&self, configuration_manager: &ConfigurationManager) -> () {
        let subscriber = FmtSubscriber::builder()
            .with_max_level(configuration_manager.max_log_level)
            .finish();
        tracing::subscriber::set_global_default(subscriber)
            .expect("Failed to set tracing subscriber");
    }
}
```

This will ensure `tracing` is only set up once during the lifecycle of the program.
However, this needs to take a reference to the `ConfigurationManager`.
As we saw in the [manual implementation how to use `OnceCell`](@/blog/2024-08-08-manual-dependency-injection-rust.md#implementing-singleton-dependencies) to control the construction of managed dependencies that `OnceCell` will cause our object to become a reference.

## Scoped
A scoped dependency is setup in the same way.
Except it uses the `#[Scoped]` attribute instead.

```rust
#[dependency_container]
impl DependencyContainer {
    #[Scoped]
    fn user(&self, configuration_manager: &ConfigurationManager) -> User {
        User::builder().id(&configuration_manager.user_id).build()
    }
}
```

## Transient
These can be setup with the `#[Transient]` attribute.
However, transient dependencies are regarded as the default in most frameworks.
So registering a dependency without any attributes will cause it to default to transient anyway.

```rust
use chrono::{DateTime, Local, Utc};

#[dependency_container]
impl DependencyContainer {
    fn datetime(&self) -> DateTime<Utc> {
        Utc::now()
    }
    
    #[Transient]
    fn datetime_local(&self) -> DateTime<Local> {
        Local::now()
    }
}
```

Therefore both these datetime dependencies are transients and will be constructed each time they are requested.

## More advanced uses
Trait based dependencies and dependencies which need an async context to be constructed are also still supported.
However, trait based dependencies need a bit of help from developers to be handled correctly.

```rust
#[dependency_container]
impl DependencyContainer {
    #[Singleton(Postgres)]
    async fn database(
        &self,
        configuration_manager: &ConfigurationManager,
    ) -> impl Database {
        Postgres::connect(
            configuration_manager
                .get_database_connection_string()
                .unwrap(),
        )
        .await
    }
}
```

The type hint (e.g., `#[Singleton(Postgres)]`) is necessary because Rust doesn't allow `impl Trait` as a field type in structs.
Since the `dependency_container` macro generates a struct to manage singleton and scoped dependencies, it needs concrete types for these fields.
By providing the type hint, we tell the macro which specific type to use for storage, while still allowing the method to return an `impl Trait` for flexibility in the public API.

This type hint is supplied inside the lifetime attribute.
Eg `#[Singleton(Postgres)]`
This is also required for any methods which return an `impl Trait`

## Usage
This updates adds a `new_scope()` method.
But, other than this, usage of the generated struct stays the same.

```rust
#[dependency_container]
impl DependencyContainer {
    // Dependencies as earlier
    
    fn service(
        &self,
        _tracing: (),
        database: impl Database,
        datetime: DateTime<Utc>,
    ) -> Service<impl Database> {
        Service::new(database, datetime)
    }
}

#[tokio::main]
async fn main() {
    let dependency_container = DependencyContainer::new();
    let service = dependency_container.service().await;

    service.work();
}
```

## Best Practices for Choosing Dependency Lifetimes
When deciding between singleton, scoped, and transient dependencies, consider these guidelines:

1. **Singleton**: Use for dependencies that are expensive to create and can be safely shared across the entire application.
   Examples include configuration managers, database connection pools, and global logger instances.
2. **Scoped**: Ideal for dependencies that should be shared within a specific context (like a web request) but not across the entire application.
   This can include user session data or request-specific caches.
3. **Transient**: Best for lightweight objects that are cheap to create or when you need a new instance every time.
   This often includes DTOs, value objects, or stateless services.
4. **State and Thread Safety**: Remember that singleton and scoped dependencies may be accessed concurrently.
   Ensure they are thread-safe or use appropriate synchronization mechanisms like `Arc`.

By carefully considering these factors, you can choose the most appropriate lifetime for each dependency, optimizing your application's performance and maintainability.

## Conclusion
The latest iteration of despatma brings powerful lifetime management capabilities to Rust dependency injection.
By supporting singleton, scoped, and transient dependencies, it offers developers fine-grained control over resource management and application state.

Using despatma for dependency lifetime management provides several key benefits:

1. **Simplified Code**: The macro-based approach reduces boilerplate, making your dependency setup more concise and readable.
2. **Flexibility**: You can easily switch between lifetime strategies without major code changes, allowing for easier optimization and refactoring.
3. **Performance**: By controlling instantiation and lifecycle of dependencies, you can optimize resource usage and improve your application's overall performance.
4. **Maintainability**: Clear lifetime definitions make it easier to reason about dependency lifecycles, enhancing code maintainability.

While despatma now supports various dependency lifetimes, it's worth noting that lazy dependencies are not yet implemented.
This feature is planned for a future release, pending some upcoming Rust language features.
Specifically, we're waiting for improvements like `impl` return types in `impl Fn`, expected to arrive in Rust 2024.
These enhancements will allow for more elegant and flexible lazy dependency implementations.

For more advanced usage scenarios and practical examples of despatma in action, be sure to check out the [examples in the despatma repository](https://github.com/chesedo/despatma/tree/main/despatma/examples).
These examples showcase more complex applications and can help you leverage the full power of despatma in your Rust projects.
