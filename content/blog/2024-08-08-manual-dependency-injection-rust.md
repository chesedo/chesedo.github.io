+++
title = "Mastering Dependency Injection in Rust: Crafting a Custom Container"
description = "Learn how to implement a custom Dependency Injection (DI) container in Rust. This comprehensive guide covers various dependency types, lifetimes, and advanced patterns, providing a solid foundation for building modular and testable Rust applications."
[taxonomies]
tags = ["Rust", "Dependency Injection", "Software Design", "Advanced Rust", "Software Architecture"]
categories = ["Rust Dependency Injection"]
+++

In modern software development, managing dependencies efficiently is essential for creating scalable and maintainable applications.
Dependency Injection (DI) is a powerful design pattern that promotes Inversion of Control (IoC), enhancing modularity and simplifying testing.
However, implementing DI in Rust presents unique challenges due to the language's lack of runtime reflection.

My journey with DI in Rust began with Luca Palmieri's Pavex framework in late 2022.
Initially, I struggled to grasp its implementation.
It wasn't until RustNation in March 2024 where [Luca's showed an update of Pavex](https://www.youtube.com/watch?v=cMea6IMRk2s) that I fully understood how DI could work in Rust.
Inspired by this insight, I set out to possibly create a DI solution using Rust's macro system, avoiding the extra compile step required by Pavex.

This article, the first in a series, documents my investigation into DI in Rust using a dependency container.
We'll explore the principles and patterns necessary for this approach, laying the groundwork for eventually automating much of the boilerplate code with a proc-macro.

We'll cover:
- The concept of Dependency Injection and its benefits
- How other languages implement DI
- Rust's unique challenges and strengths in implementing DI
- A step-by-step guide to crafting a custom DI container in Rust

## Dependency Injection: The Foundation of Modular Software Design
Dependency Injection (DI) is a design pattern that addresses how components obtain their dependencies.
Instead of creating dependencies directly, a component receives its dependencies from an external source, often called an injector or a container.

### Benefits of Dependency Injection in Software Design

1. **Improved Testability**: By injecting dependencies, you can easily replace them with mocks or stubs during testing, allowing for more isolated and controlled tests.
1. **Decoupling of Components**: DI promotes loose coupling between components, making your codebase more modular and easier to maintain.
1. **Easier Maintenance**: With DI, you can change the implementation of a dependency without altering the components that use it, leading to more maintainable and adaptable code.

### Dependency Injection in Action

Consider a simple example of a monitoring system that sends alerts.
Without DI, the monitoring system might directly create instances of the email service and data collector:

#### Easy Approach: Code Without Dependency Injection

{% mermaid() %}
---
title: Monitoring System without Dependency Injection
---
classDiagram
    direction LR
    class MonitoringSystem {
        -EmailService email_service
        -SimpleDataCollector data_collector
        +new(\n    username: str,\n    password: str,\n    api_key: str\n) Self
        +check_for_alerts()
    }
    class EmailService {
        -username String
        -password String
        +new(\n    username: str,\n    password: str\n) Self
        +send(to: str, message: str)
    }
    class SimpleDataCollector {
        -api_key String
        +new(api_key: str) Self
        +collect_data() Vec~String~
    }

    MonitoringSystem --> EmailService : uses
    MonitoringSystem --> SimpleDataCollector : uses
{% end %}

In this scenario:

- **Testability**: Testing is difficult because the `MonitoringSystem` directly depends on `EmailService`, which requires actual email credentials and can send real emails during tests.
Automated tests would need real credentials, making them complex and environment-dependent.
- **Maintenance**: Maintenance is hard because switching to a different notification sender (like Slack) requires changes throughout the `MonitoringSystem` where `EmailService` is used.
- **Mixing Business Logic with Implementation Details**: The `MonitoringSystem` includes both business logic and low-level details such as email credentials and API keys.
Business logic should be driven by stakeholder requirements, while low-level details are programmer concerns.
This mix complicates both the understanding and modification of the business logic.

With DI, we can inject the `EmailService` and `DataCollector` dependencies, making the system more flexible and testable:

#### Improved Design: Implementing Dependency Injection

{% mermaid() %}
---
title: Monitoring System with Dependency Injection
---
classDiagram
    direction LR
    class MonitoringSystem {
        -MessageService message_service
        -DataCollector data_collector
        +new(\n    message_service: MessageService,\n    data_collector: DataCollector\n) Self
        +check_for_alerts()
    }
    class MessageService {
        <<interface>>
        +send(to: str, message: str)
    }
    class DataCollector {
        <<interface>>
        +collect_data() Vec~String~
    }
    class EmailService {
        -username String
        -password String
        +new(username: str, password: str) Self
        +send(to: str, message: str)
    }
    class SimpleDataCollector {
        -api_key String
        +new(api_key: str) Self
        +collect_data() Vec~String~
    }

    EmailService ..|> MessageService : implements
    MonitoringSystem --> MessageService : uses
    MonitoringSystem --> DataCollector : uses
    SimpleDataCollector ..|> DataCollector : implements
{% end %}

In this scenario:

- **Testability**: The `MonitoringSystem` now depends on abstractions (`MessageService` and `DataCollector`), making it easier to inject different implementations.
Testing is simplified because you can inject mock implementations, avoiding the need for real credentials and external dependencies.
- **Maintenance**: Maintenance is easier as you can switch implementations of `MessageService` or `DataCollector` without altering the `MonitoringSystem`.
- **Separation of Concerns**: The `MonitoringSystem` now focuses on business logic, driven by stakeholder requirements, while low-level details such as email credentials and API keys are managed by the respective services.
This separation aligns with [Clean Architecture](https://www.amazon.com/Clean-Architecture-Craftsmans-Software-Structure/dp/0134494164) principles, where all dependency arrows point towards the business logic, making it stable and adaptable to changes in lower-level details.

But I don't want to spend time stating the benefits of such a design in this article.
There is already a great article on [Hexagonal Architecture Design in Rust](https://www.howtocodeit.com/articles/master-hexagonal-architecture-rust).
However, that article ends with a `setup` module which can be improved by a more automated dependency resolution for bigger applications - it is, however, absoulutely fine for smaller, simpler applications.

## How Other Languages Handle Dependency Injection
My first exposure to DI was in C# around the time that services became a first class citizen in the language.
The hard part with Dependency Injection is linking up your entire chain of dependencies.
However, luckily, C# takes care of the linking part automatically.
This code snippet shows how we would setup and resolve these dependencies in C#.

```cs
// Set up Dependency Injection
var serviceProvider = new ServiceCollection()
    .AddSingleton<IMessageService>(sp => new EmailService("user", "pass"))
    .AddSingleton<IDataCollector>(sp => new SimpleDataCollector("api_key"))
    .AddSingleton<MonitoringSystem>()
    .BuildServiceProvider();

// Resolve the MonitoringSystem and call CheckForAlerts
var monitoringSystem = serviceProvider.GetService<MonitoringSystem>();
monitoringSystem.CheckForAlerts();
```

Here the `ServiceCollection` from C# will find all the constructors for `MonitoringSystem` at runtime.
It would then find that the single constructor as per our design needs something which implements a `MessageService` and a `DataCollector` to be able to call the constructor.
And this is why we also register another two dependencies on the collection which does implement these.
One for the `MessageService` and another for the `DataCollector`.

In Java this is even easier because of `@Autowired`.

```java
// Only get the final class we want
ApplicationContext context = new AnnotationConfigApplicationContext(AppConfig.class);
    MonitoringSystem monitoringSystem = context.getBean(MonitoringSystem.class);
    monitoringSystem.checkForAlerts();
```

In this example we only have to make the request to the final `MonitoringSystem` class without having to explicitly setup all the dependencies at this call site like we did for C#.
But the constructors of each class does have `@Autowire` annotation to, well, auto wire them correctly later to `@Component`s.

### Under the Hood of C# and Java
The reason C# and Java are able to automatically deduce that it needs to use a `MessageService` and a `DataCollector` to be able to construct a `MonitoringSystem` is because of reflection at runtime.
This means that at runtime it is possible to inspect the `MonitoringSystem` class to know which constructors it has and what the arguments are for the constructors.
It is then able, at runtime, to find and instantiate any other dependencies that satisfy these constructor arguments.

However, reflection programming is not possible in Rust.
So we can't have this auto-wiring of dependencies easily.

### The Benefits of No Reflection
Not having access to reflection is a good thing in a wider sense because reflection:

1. **Adds runtime overhead**.
Inspecting objects at runtime is CPU time wasted that could have gone towards solving the business case the code is for.
1. **Adds binary bloat**.
Code running at runtime needs to be in the runtime binary.
Including any reflection and meta code.
1. **Moves errors from compile time to runtime**.
Since reflection happens at runtime, if there is an error there, then you only know about it at runtime.
Ie if the `DataCollector` dependency is missing in these C# and Java code examples, then you will only get an error once the program is started.
This will be long after all the linting and compile checks happened.
And will be when the service is already in production.
In the Rust ecosystem we love to rather have these errors at compile time.
1. **Is less explicit**.
Take the Java approach as an example, one will have to search through the entire codebase to understand what uses which dependencies.
This makes maintenance of that code slower.
Basically, too much "magic" makes the code hard to understand.
The same does not apply for C# since all the dependencies are explicitely setup at the same location.
1. **Can use interfaces / traits instead**.
Any code that typically relies on reflection can be redesigned using an interface-first mindset.

## Leveraging Rust's Features for Dependency Injection
Like `ServiceProvider` from C# and `ApplicationContext` from Java we need an object that knows how to construct each of the dependencies we possibly want.
This is each dependency on the chain of dependencies to make something like the `MonitoringSystem`.

Since we don't have access to reflection, nor are we aiming to use macros, we are going to write this container manually.

### Benefits of a Manual Dependency Container
The benefits of writing it manually are:
- We get to better understand what some of these frameworks are doing behind the scenes.
We are unveiling the magic so to speak.
- We get to establish patterns on how to handle certain cases by seeing a repeat of things happening for a common group of cases.
This is important as it sets the ground work for turning the repeated things into a macro.
- We promote all errors in missing dependencies to compile time errors.

### Requirements for a Rust Dependency Container
Before we dive into the implementation, let's outline the key requirements and concepts for our Rust dependency container.
These are designed to leverage Rust's strengths while addressing the unique challenges of implementing DI in Rust.

#### Compile-Time Safety and Performance
- All errors must be compile-time errors to maintain Rust's safety guarantees.
- The container should support lazy instantiation of dependencies to optimize performance.

#### Flexibility and Usability
- Support for returning concrete types, trait objects, and dynamic trait objects.
Overall, we want to keep a clean DX by avoiding the use of generics.
Generics will just make the codebase harder to read and to pass our container around.
- Ability to handle deeply nested dependencies without complicating the API for developers.
- Support for conditional dependencies based on runtime configuration.

#### Lifetime Management
One crucial aspect of our dependency container is managing the lifetimes of the objects it creates.
To understand why this is important, let's consider a practical example:

Imagine our `DataCollector` turned out to be something which collects data from a DB.
Further imagine our service is a background task which checks for alerts every minute.
We might therefore request a `MonitoringSystem` on every 1 minute loop.
This means building the entire dependency tree for `MonitoringSystem` every minute.
Since the DB connection is one of these dependencies, we will be establishing a new connection for it every minute too.
And this is unneeded overhead.
It would be better to make the DB connect once when the program starts, or the first time when the object is requested, and then reuse the object each time the dependency is needed again.

This example illustrates why we need different lifetime strategies for our dependencies.
Based on these needs, our container must support three major dependency lifetimes:

1. **Singleton Lifetime**: Objects created once and shared throughout the application's lifetime.
Examples include database connections, configuration managers, and global loggers.
1. **Scoped Lifetime**: Objects tied to a specific scope of work, such as a single request in a web application or a single run of a batch process.
Examples include request IDs, user contexts, or scoped loggers.
1. **Transient Lifetime**: New instances created each time they're requested.
These are typically lightweight objects like DTOs, formatters, or ID generators.

#### Advanced Features
- Support for asynchronous dependencies.
- Ability to return `dyn Trait` types for runtime polymorphism.

In the following sections, we'll implement our dependency container step by step, addressing each of these requirements and demonstrating how to manage different dependency lifetimes effectively.

## From Theory to Practice: Crafting a Rust Dependency Container
Let's continue with the list of requirements for the dependency container.
We will now address each item in the list starting with returning concrete types.

### Implementing Concrete Type Returns
This is a simple case.
To return a concrete type like `DateTime` we simply use that type as the return type and construct it in the method.
These types are very rare.
But sometimes we might have a concrete type like config settings, a random id generator, or the current datetime that we might want to control to test the business logic works as expected.

```rust
use chrono::{DateTime, Utc};

// The container we are going to use to resolve dependencies.
// Like `ServiceCollection` in .NET Core
// And `ApplicationContext` in Spring
pub struct DependencyContainer;

impl DependencyContainer {
    pub fn new() -> Self {
        Self
    }

    // We just make a function to return the concrete type
    pub fn datetime(&self) -> DateTime<Utc> {
        Utc::now()
    }
}
```

### Implementing Trait Type Returns
Returning something that implements a trait is also simple by using the `impl` on the return type.

```rust
impl DependencyContainer {
    // This time we are returning an abstract type
    // This allows us to change the implementation of this function to change
    // the low-level details without changing the business code
    pub fn data_collector_impl(&self) -> impl DataCollector {
        SimpleDataCollector::new("api_key".to_string())
    }
}

// -------------------------------------
// data_collector.rs
// -------------------------------------
pub trait DataCollector {
    fn collect_data(&self) -> Vec<String>;
}

pub struct SimpleDataCollector {
    api_key: String,
}

impl SimpleDataCollector {
    pub fn new(api_key: String) -> Self {
        Self { api_key }
    }
}

impl DataCollector for SimpleDataCollector {
    fn collect_data(&self) -> Vec<String> {
        vec!["data1".to_string(), "data2".to_string()]
    }
}
```

This is the primary case why we are using Dependency Injection.
These types are technical details the programmers understand, but does not affect how the business logic works at all.
So we have them behind traits.
We can now easily swap out this `SimpleDataCollector`, which fetches data using an API call, with any other type of data collector.
This other data collector might be a database call or some socket reader instead.
It does not matter since that's something a developer will know how to implement and it does not change the business logic at all in terms of which data points will become alerts.
But by using the `impl` with a trait we can easily swap this out for another data collector when that is needed simply by changing this single method.

By using `impl` we also don't introduce any generics on our `DependencyContainer` or the method.
This keeps it easy to pass the `DependencyContainer` around to functions it might need to go.

### Implementing Dynamic Trait Type Returns
Suppose we have both the API data collector and SQL data collector.
Next, we want to choose which one to use at runtime.
So our method should be able to return both.
Hence, we might try the following.

```rust
impl DependencyContainer {
    // Attempt to conditional choose the [DataCollector] at runtime
    fn create_data_collector_impl_error(&self) -> impl DataCollector {
        if false {
            SimpleDataCollector::new("api_key".to_string())
        } else {
            SqlDataCollector::new("connection_string".to_string())
        }
    }
}

// -------------------------------------
// data_collector.rs
// -------------------------------------
pub struct SqlDataCollector {
    connection_string: String,
}

impl SqlDataCollector {
    pub fn new(connection_string: String) -> Self {
        Self { connection_string }
    }
}

impl DataCollector for SqlDataCollector {
    fn collect_data(&self) -> Vec<String> {
        vec!["sql_data1".to_string(), "sql_data2".to_string()]
    }
}
```

This will give a `'if' and 'else' have incompatible types` compile error.
This is because the `impl` return type is a syntax sugar for a generic return type... well almost atleast.
So the block in the previous section replaces the `impl DataCollector` return type with `SimpleDataCollector` instead.
But this new section has both `SimpleDataCollector` and `SqlDataCollector` for return types so the compiler does not know what to replace the `impl DataCollector` return type with.
The solution is to rather return `dyn DataCollector`.

```rust
impl DependencyContainer {
    fn create_data_collector_dyn_error(&self) -> dyn DataCollector {
        if false {
            SimpleDataCollector::new("api_key".to_string())
        } else {
            SqlDataCollector::new("connection_string".to_string())
        }
    }
}
```

This gives a new `doesn't have a size known at compile-time`.
By returning a `dyn` type we are switching from [static dispatch to dynamic dispatch](https://www.youtube.com/watch?v=xcygqF5LVmM).
The fix is to wrap the `dyn` in a box instead.
Thus the following allows us to return dyn traits which allows choosing the concrete `DataCollector` at runtime.

```rust
impl DependencyContainer {
    // We can now conditionally choose which [DataCollector] to use at runtime
    fn create_data_collector_dyn(&self) -> Box<dyn DataCollector> {
        if false {
            Box::new(SimpleDataCollector::new("api_key".to_string()))
        } else {
            Box::new(SqlDataCollector::new("connection_string".to_string()))
        }
    }
}
```

But we will soon find that we won't be able to use the `Box<dyn>` type as a substitute for a `DataCollector` when we create the `MonitoringSystem`.
Infact, we can already the see the error by adding the following method which again returns a `impl DataCollector` but calls the dynamic method variant we just created.

```rust
impl DependencyContainer {
    // Things calling this method does not care that it might be a boxed type
    // They just want a [DataCollector]
    pub fn data_collector_dyn(&self) -> impl DataCollector {
        self.create_data_collector_dyn()
    }
}
```

We see from the error message that the box does not implement our trait.
Since we declared the `DataCollector` trait, we can add a default implementation for it being wrapped by a box.

```rust
// -------------------------------------
// data_collector.rs
// -------------------------------------
impl<T: DataCollector + ?Sized> DataCollector for Box<T> {
    fn collect_data(&self) -> Vec<String> {
        T::collect_data(self)
    }
}
```

Now any `DataCollector` wrapped by a `Box` can still be used as a `DataCollector`.

### Managing Dependency Chains
You might have noticed three things so far (or some of them)

1. The API key and connection string were hard coded this whole time.
1. The `if` condition is hard coded too.
1. The `create_*` method for the box is not public.

This is a good segue into dependencies that require other dependencies.
The hard coded values should come from some configuration instead.
So let's create the following configuration manager.

```rust
// -------------------------------------
// configuration_manager.rs
// -------------------------------------
pub struct ConfigurationManager {
    email_service_username: String,
    email_service_password: String,
    database_connection_string: Option<String>,
    api_key: Option<String>,
}

impl ConfigurationManager {
    pub fn new() -> Self {
        // This should use something like clap to read the configuration from
        // the command line
        // But this is good enough to show a configuration manager.
        Self {
            email_service_username: "user".to_string(),
            email_service_password: "pass".to_string(),
            database_connection_string: None,
            api_key: Some("api_key".to_string()),
        }
    }

    pub fn get_email_service_username(&self) -> &str {
        &self.email_service_username
    }

    pub fn get_email_service_password(&self) -> &str {
        &self.email_service_password
    }

    pub fn get_database_connection_string(&self) -> Option<&str> {
        self.database_connection_string.as_ref().map(|s| s.as_str())
    }

    pub fn get_api_key(&self) -> Option<&str> {
        self.api_key.as_ref().map(|s| s.as_str())
    }
}
```
We already saw with the `DateTime` example how to register a concrete type like this as a dependency with the follow code:

```rust
impl DependencyContainer {
    fn create_configuration_manager(&self) -> ConfigurationManager {
        ConfigurationManager::new()
    }

    pub fn configuration_manager(&self) -> ConfigurationManager {
        self.create_configuration_manager()
    }
}
```

This now comes to why we had the `create_*` prefixed method and why it was private.
By using the configuration manager we have the following create method for the data collector instead.

```rust
impl DependencyContainer {
    // Create [DataCollector] based on the configuration
    fn create_data_collector(
        &self,
        configuration_manager: ConfigurationManager,
    ) -> Box<dyn DataCollector> {
        if let Some(api_key) = configuration_manager.get_api_key() {
            Box::new(SimpleDataCollector::new(api_key.to_string()))
        } else {
            Box::new(SqlDataCollector::new(
                configuration_manager
                    .get_database_connection_string()
                    .expect("api key or connection string to be set")
                    .to_string(),
            ))
        }
    }
}
```

We won't want developers to be concerned about the fact that this dependency requires the configuration manager to be constructed.
One of the requirements were, "we don't want developers to know which chain of dependencies are needed for any specific dependency they are trying to resolve".
So we are making this method private.
We will continue this pattern and all `create_*` methods will be private.
We will create a simple public `data_collector()` method which will call this create method with the configuration manager.

```rust
impl DependencyContainer {
    // Developers can call this method easily without needing to know about the
    // dependency on [ConfigurationManager]
    pub fn data_collector(&self) -> impl DataCollector {
        let configuration_manager = self.configuration_manager();
        self.create_data_collector(configuration_manager)
    }
}
```

And this method is easy for developers to call whenever they need a data collector since it has no extra arguments.
When we get to the monitoring system dependency, then our `create_monitoring_system()` method will have an argument for the data collector and another argument for the message service.
These arguments will then be passed on to the monitoring system resolver as we'll see.

### Implementing Singleton Dependencies
Using the same pattern we can make the dependency for the message service as follow.

```rust
impl DependencyContainer {
    // Get a [MessageService] which also needs the [ConfigurationManager]
    fn create_message_service(
        &self,
        configuration_manager: ConfigurationManager,
    ) -> impl MessageService {
        EmailMessageService::new(
            configuration_manager
                .get_email_service_username()
                .to_string(),
            configuration_manager
                .get_email_service_password()
                .to_string(),
        )
    }

    pub fn message_service(&self) -> impl MessageService {
        self.create_message_service(self.configuration_manager())
    }
}

// -------------------------------------
// message_service.rs
// -------------------------------------
pub trait MessageService {
    fn send_message(&self, message: &str);
}

pub struct EmailMessageService {
    username: String,
    password: String,
}

impl EmailMessageService {
    pub fn new(username: String, password: String) -> Self {
        EmailMessageService { username, password }
    }
}

impl MessageService for EmailMessageService {
    fn send_message(&self, message: &str) {
        println!("Sending message: {}", message);
        // Logic to send the message using the email service credentials
    }
}
```

Notice how this also calls `configuration_manager()` too.
This means we will construct, and therefore parse, the configuration twice.
Once when we get the data collector and again to get the message service.
This will be inefficient and leads to the need of singleton lifetimes.

We will only want to read the configuration once for the entire duration of the application.
We can use `OnceCell` to only construct it once by updating the container as follow:

```rust
use std::cell::OnceCell;

pub struct DependencyContainer {
    configuration_manager: OnceCell<ConfigurationManager>,
}

impl DependencyContainer {
    pub fn new() -> Self {
        Self {
            configuration_manager: OnceCell::new(),
        }
    }

    pub fn configuration_manager(&self) -> &ConfigurationManager {
        // Use [OnceCell] to only create the [ConfigurationManager] once
        self.configuration_manager
            .get_or_init(|| self.create_configuration_manager())
    }
}
```

We need a field on the container to store the single instance of the configuration manager.
This will also require an update of the container's resolver.
Finally, we use the `get_or_init` from `OnceCell` to get the configuration manager if it was already created before, else it is created by calling the create method.
Notice, the return type also became a reference since we are reusing the same `ConfigurationManager` whenever this method is called.
So `create_message_service()` and `create_data_collector()` needs to be updated to take references too.

### Implementing Scoped Dependencies
Imagine the API data collector also wanted to log out each data point it collected before returning to the caller.
This means the need for a logging service.

```rust
// -------------------------------------
// data_collector.rs
// -------------------------------------
pub struct ApiDataCollector<L: LoggingService> {
    api_key: String,
    logging_service: L,
}

impl<L: LoggingService> ApiDataCollector<L> {
    pub fn new(api_key: String, logging_service: L) -> Self {
        Self {
            api_key,
            logging_service,
        }
    }
}

impl<L: LoggingService> DataCollector for ApiDataCollector<L> {
    fn collect_data(&self) -> Vec<String> {
        let data = vec!["data1".to_string(), "data2".to_string()];

        for d in data.iter() {
            self.logging_service.log(&d);
        }

        data
    }
}

// -------------------------------------
// logging_service.rs
// -------------------------------------
pub trait LoggingService {
    fn log(&self, message: &str);
}

pub struct StdoutLoggingService {
    alert_id: String,
}

impl StdoutLoggingService {
    pub fn new(alert_id: &str) -> Self {
        StdoutLoggingService {
            alert_id: alert_id.to_string(),
        }
    }
}

impl LoggingService for StdoutLoggingService {
    fn log(&self, message: &str) {
        println!("[Alert {}] Log: {}", self.alert_id, message);
    }
}
```

Further, notice we want each logging instance to be linked to the alert check/id currently happening by taking in the alert ID on the constructor.
This is the need for a scoped lifetime dependency.
Like a singleton lifetime dependency this is easy to solve with a `OnceCell`.
But we will need a way to reset the created object for "new scopes".

```rust
use std::rc::Rc;

pub struct DependencyContainer {
    // This now has to be an [Rc] to be able to clone the singleton instance in
    // the [new_scope] method
    configuration_manager: Rc<OnceCell<ConfigurationManager>>,
    // Scope dependencies just use an [OnceCell]
    logging_service: OnceCell<StdoutLoggingService>,
    // Some scope specific data
    alert_id: String,
}

impl DependencyContainer {
    pub fn new() -> Self {
        Self {
            configuration_manager: Rc::new(OnceCell::new()),
            logging_service: OnceCell::new(),
            alert_id: Default::default(),
        }
    }

    // This has a dependency on some scope config
    fn create_logging_service(&self, alert_id: &str) -> StdoutLoggingService {
        StdoutLoggingService::new(alert_id)
    }

    pub fn logging_service(&self) -> impl LoggingService {
        let logging_service = self
            .logging_service
            .get_or_init(|| self.create_logging_service(&self.alert_id));

        logging_service
    }

    fn create_data_collector(
        &self,
        configuration_manager: &ConfigurationManager,
    ) -> Box<dyn DataCollector> {
        if let Some(api_key) = configuration_manager.get_api_key() {
            // The logging service should be injected as an arg,
            // but we'll see how to do that later
            Box::new(ApiDataCollector::new(
                api_key.to_string(),
                self.logging_service(),
            ))
        } else {
            Box::new(SqlDataCollector::new(
                configuration_manager
                    .get_database_connection_string()
                    .expect("api key or connection string to be set")
                    .to_string(),
            ))
        }
    }

    /// Start a new scope for any scope specific dependencies
    pub fn new_scope(&self, alert_id: &str) -> Self {
        Self {
            // Clone to have singleton behavior
            configuration_manager: self.configuration_manager.clone(),
            // Make a new instance to have scope specific behavior
            logging_service: OnceCell::new(),
            // Set scope config
            alert_id: alert_id.to_string(),
        }
    }
}
```

So let's create a `new_scope()` method on the dependency container.
We will also add a new alert field to our dependency container to record the current alert run id for a scope.

Our `new_scope` method will set this id, clone the current singleton lifetime, and will reset the `OnceCell` for the scoped lifetime object (logging service).
But to be able to clone the singleton object, we need the type inside the `OnceCell` to be clonable too.
A way around this is to wrap that `OnceCell` with an `Rc` instead.

Creating the logging service uses the same `create_*` pattern to ingest the dependencies and the `logging_service()` method is exactly the same pattern as a singleton lifetime.
Thus, the only difference between a singleton lifetime and a scoped lifetime is their implementations in `new_scope()` and their data types.
The singleton does a clone, while a scope resets the `OnceCell` to be ready to create the scope object anew.
The singleton uses `Rc<OnceCell<_>>` while the scope just uses `OnceCell`.

However, this will fail to compile with an error of `'&StdoutLoggingService: LoggingService' is not satisfied`.
We know from earlier that `OnceCell` caused the `ConfigurationManager` return type to become a reference.
By looking at my editor's inlay hints, I can see the `logging_service` variable in this function is a reference too.
Since `OnceCell` causes us to return a reference, we have the same issue we had earlier when returning a `Box<dyn Trait>`.
The fix for this error is also the same.
Implementing our trait for any references.

```rust
// -------------------------------------
// logging_service.rs
// -------------------------------------
impl<L: LoggingService + ?Sized> LoggingService for &L {
    fn log(&self, message: &str) {
        (*self).log(message);
    }
}
```

But now we have a new error.
And this is fine.
We are following this manual process exactly to find all the edge cases before macro-ifying the process.

The error states: `hidden type for 'impl LoggingService' captures lifetime that does not appear in bounds`.
So let's take a closer look at that function.

```rust
pub fn logging_service(&self) -> impl LoggingService {
    let logging_service = self
        .logging_service
        .get_or_init(|| self.create_logging_service(&self.alert_id));

    logging_service
}
```

We know this function is returning a reference.
And because of Rust's ownership model, the compiler will need to know how long this reference is valid for.
Since this reference is tight to `&self` (via the `logging_service` field), we can just add the same lifetime to self and the return type of this method.

But that makes the code too complicated and we have a requirement to keep things simple.
So we are going to use the wildcard lifetime (`'_`) on the return type to have the compiler give the return the same lifetime as `&self`.

```rust
pub fn logging_service(&self) -> impl LoggingService + '_ {
    let logging_service = self
        .logging_service
        .get_or_init(|| self.create_logging_service(&self.alert_id));

    logging_service
}
```

And now we have a new error again.
And again this is good as it allows us to set the patterns to cover all edge cases.

This time the error states the `DataCollector` in the following method `may not live long enough`.

```rust
fn create_data_collector(
    &self,
    configuration_manager: &ConfigurationManager,
) -> Box<dyn DataCollector> {
    if let Some(api_key) = configuration_manager.get_api_key() {
        // The logging service should be injected as an arg,
        // but we'll see how to do that later
        Box::new(
            ApiDataCollector::new(
                api_key.to_string(),
                self.logging_service()
            )
        )
    } else {
        Box::new(SqlDataCollector::new(
            configuration_manager
                .get_database_connection_string()
                .expect("api key or connection string to be set")
                .to_string(),
        ))
    }
}
```

This error is the same as the last one, but with a different error message.
The `ApiDataCollector` is generic over the logging service.
Since the logging service is a reference type, because of it's scoped lifetime, `ApiDataCollector` now technically has a lifetime too.
So the returned `Box` can potentially have a lifetime associated with it.

But [boxes default to having the `'static` lifetime](https://doc.rust-lang.org/reference/lifetime-elision.html#default-trait-object-lifetimes).
And the actual lifetime is correctly detected to be that of `&self`.
However, `&self` has a shorter lifetime than `'static`.
Hence the error message of `&self` not living long enough.

We fix this by also having the `Box` have its lifetime linked to `&self`.
And using the wildcard lifetime is again an easy way to do this.

```rust
fn create_data_collector(
    &self,
    configuration_manager: &ConfigurationManager,
) -> Box<dyn DataCollector + '_> {
    // Same implementation as before
}
```

Now we get another `captures lifetime that does not appear in bounds` on `data_collector()`.
But we already know how to fix this with the wildcard lifetime.

```rust
pub fn data_collector(&self) -> impl DataCollector + '_ { ... }
```

With all the errors fixed, our main can now use a new scope as follow to run alert checks indefinitely in the background.

```rust
use std::thread::sleep;
use std::time::Duration;

fn main() {
    let dc = DependencyContainer::new();

    // Run forever in the background
    for i in 1.. {
        let alert_id = format!("Alert{}", i);

        let dc = dc.new_scope(&alert_id);
        let data_collector = dc.data_collector();
        let message_service = dc.message_service();

        let monitoring_system =
            MonitoringSystem::new(data_collector, message_service);

        monitoring_system.check_alert();

        sleep(Duration::from_secs(5));
    }
}

// -------------------------------------
// monitoring_system.rs
// -------------------------------------
pub struct MonitoringSystem<D: DataCollector, M: MessageService> {
    data_collector: D,
    message_service: M,
}

impl<D: DataCollector, M: MessageService> MonitoringSystem<D, M> {
    pub fn new(data_collector: D, message_service: M) -> Self {
        MonitoringSystem {
            data_collector,
            message_service,
        }
    }

    // This function should be the only function with core business logic.
    // Thus, it should be under proper tests.
    // And it should not contain low-level details.
    // Which will make it easy to test.
    pub fn check_alert(&self) {
        let data = self.data_collector.collect_data();

        for d in data {
            if d.contains("2") {
                self.message_service.send_message(&d);
            }
        }
    }
}
```

This is the first section were we finally had to use generics.
First to pass the logging service to the `ApiDataCollector`.
And just now to pass a `DataCollector` and `MessageService` to the `MonitoringSystem`.

These make the code harder to write.
But they can no longer be avoided.
Luckily our `DependencyContainer` is still free of generics.
And is therefore easy to pass around functions.
Especially now that it supports scopes too.

### Implementing Transient Dependencies
Lastly, we probably don't want to send the data points as is.
We will want to give them some formatting, known as view.
This responsibility does not belong with the data collector (if we change the data collector then we don't want the message formatting to change), nor does it belong to the message service (while an email might be an HTML message and slack message some markdown, the base contextual message should be the same for both... at least in this example).

So we will create a message builder next.
It's a lightweight dependency which we can recreate whenever it is needed.
This means a transient lifetime.

```rust
impl DependencyContainer {
    fn create_notification_message_builder(
        &self,
    ) -> impl NotificationMessageBuilder {
        DefaultNotificationMessageBuilder::new()
    }

    pub fn notification_message_builder(
        &self,
    ) -> impl NotificationMessageBuilder {
        self.create_notification_message_builder()
    }
}

// -------------------------------------
// notification_message_builder.rs
// -------------------------------------
pub trait NotificationMessageBuilder {
    fn build_message(&self, alert: &str) -> String;
}

pub struct DefaultNotificationMessageBuilder;

impl DefaultNotificationMessageBuilder {
    pub fn new() -> Self {
        DefaultNotificationMessageBuilder
    }
}

impl NotificationMessageBuilder for DefaultNotificationMessageBuilder {
    fn build_message(&self, alert: &str) -> String {
        format!("Alert Notification: {}", alert)
    }
}

// -------------------------------------
// monitoring_system.rs
// -------------------------------------
pub struct MonitoringSystem<
    D: DataCollector,
    M: MessageService,
    B: NotificationMessageBuilder,
> {
    data_collector: D,
    message_service: M,
    notification_message_builder: B,
}

impl<D: DataCollector, M: MessageService, B: NotificationMessageBuilder>
    MonitoringSystem<D, M, B>
{
    pub fn new(
        data_collector: D,
        message_service: M,
        notification_message_builder: B,
    ) -> Self {
        MonitoringSystem {
            data_collector,
            message_service,
            notification_message_builder,
        }
    }

    pub fn check_alert(&self) {
        let data = self.data_collector.collect_data();

        for d in data {
            if d.contains("2") {
                let message =
                    self.notification_message_builder.build_message(&d);
                self.message_service.send_message(&message);
            }
        }
    }
}
```

These are easy: we just need a method to return these.
So no need to use `OnceCell` or store anything on our dependency container.
Thus, these follow the pattern we've used for most of the start of this article.

### Finalizing the Dependency Container
We can now update main to also get and inject this message builder.
But we are designing a dependency container exactly for the reason so that we don't have to make linking changes at random places in the codebase.
Ie. our dependency manager should also return our core business logic object.
Aka `MonitoringSystem`.
So let's add that to the dependency container.

```rust
impl DependencyContainer {
    // Ingest all the dependencies needed to build a [MonitoringSystem]
    fn create_monitoring_system(
        &self,
        data_collector: impl DataCollector,
        message_service: impl MessageService,
        notification_message_builder: impl NotificationMessageBuilder,
    ) -> MonitoringSystem<
        impl DataCollector,
        impl MessageService,
        impl NotificationMessageBuilder,
    > {
        MonitoringSystem::new(
            data_collector,
            message_service,
            notification_message_builder,
        )
    }

    // Method which is easy for other developers to call since it knows nothing
    // about the dependencies of [MonitoringSystem].
    // It also has to use the wildcard lifetimes to correctly link the
    // references to `&self`.
    pub fn monitoring_system(
        &self,
    ) -> MonitoringSystem<
        impl DataCollector + '_,
        impl MessageService + '_,
        impl NotificationMessageBuilder + '_,
    > {
        let data_collector = self.data_collector();
        let message_service = self.message_service();
        let notification_message_builder = self.notification_message_builder();

        self.create_monitoring_system(
            data_collector,
            message_service,
            notification_message_builder,
        )
    }
}

fn main() {
    let dc = DependencyContainer::new();

    // Run forever in the background
    for i in 1.. {
        let alert_id = format!("Alert{}", i);

        let dc = dc.new_scope(&alert_id);
        // Resolving a [MonitoringSystem] is now easy
        let monitoring_system = dc.monitoring_system();

        monitoring_system.check_alert();

        sleep(Duration::from_secs(5));
    }
}
```

Our main is simple now.
Notice how dependency container does the same function that a `setup()` function does in most Rust applications.
But if we had to put all the code of dependency container in a single `setup()` function then that function would have been too complex to understand.
As it is now, the `DependencyContainer` is just under 100 lines of code.
Thus, dependency container is just a more complex evolution of the `setup()` function for applications that outgrow the `setup()` function.
This also means that what is shown here is only applicable to bigger applications.
And smaller applications don't need this `DependencyContainer` approach at all.

### Implementing Lazy and Conditional Dependencies
We had a requirement to creating a dependency as late as possible.
Which is why our current `create_data_collector()` calls the creation of the logging service directly.
But we won't want this in the long run as it hides the dependency the data collector potentially has on the logging service.
Throughout our code so far we wanted to be explicit about the dependencies any `create_*` method needs.
We will rather always want `create_*` methods to take in all required dependencies as args and they should never call out to dependencies directly.

But if we look at this function below, then we'll see that only the `ApiDataCollector` needs a logging service.
The `SqlDataCollector` does not need the logging service.

```rust
impl DependencyContainer {
    fn create_data_collector(
        &self,
        configuration_manager: &ConfigurationManager,
    ) -> Box<dyn DataCollector + '_>
    {
        if let Some(api_key) = configuration_manager.get_api_key() {
            // The logging service should be injected as an arg,
            // but we'll see how to do that now
            Box::new(
                ApiDataCollector::new(
                    api_key.to_string(),
                    self.logging_service()
                )
            )
        } else {
            Box::new(SqlDataCollector::new(
                configuration_manager
                    .get_database_connection_string()
                    .expect("api key or connection string to be set")
                    .to_string(),
            ))
        }
    }
}
```

We will only want to create the logging service for the `ApiDataCollector` path and we want to create the object as late as possible to ensure in is not created unnecessarily.
So we'll use an `Fn` argument as follow to receive a callback to create the logging service if & when needed.

```rust
impl DependencyContainer {
    pub fn data_collector(&self) -> impl DataCollector + '_ {
        self.create_data_collector(self.configuration_manager(), || {
            self.logging_service()
        })
    }

    // Construct the logging service only if it is needed by using a callback
    fn create_data_collector<'a, L>(
        &self,
        configuration_manager: &ConfigurationManager,
        logging_service_fn: impl Fn() -> L,
    ) -> Box<dyn DataCollector + 'a>
    where
        L: LoggingService + 'a,
    {
        if let Some(api_key) = configuration_manager.get_api_key() {
            let logging_service = logging_service_fn();
            Box::new(ApiDataCollector::new(
                api_key.to_string(),
                logging_service,
            ))
        } else {
            Box::new(SqlDataCollector::new(
                configuration_manager
                    .get_database_connection_string()
                    .expect("api key or connection string to be set")
                    .to_string(),
            ))
        }
    }
}
```

This time we can't use the wildcard lifetime.
As we saw earlier the `LoggingService` is a reference because it has a scoped lifetime.
The `Fn` return type also needs to be a generic as `impl Fn` does not support `impl` return types yet.
Since the `where` clause does not support the wildcard lifetime, we have to be explicit about it.

These generics are the first code that is making the `DependencyContainer` complicated.
But this lazy instantiation is also the only thing that is introducing generics to our container.

Now the `LoggingService` will only be created if the runtime config stated the `ApiDataCollector` is used.
Else the `SqlDataCollector` is used which does not need a `LoggingService`.

Notice how we don't have to change anything in the main file anymore.
We have now completely isolated this file from our dependency logic.

### Implementing an async dependency
Suppose our logging service dependency needed some async context to be created.

```rust
use std::time::Duration;
use tokio::time::sleep;

impl StdoutLoggingService {
    pub async fn new(alert_id: &str) -> Self {
        // Simulate some async work
        sleep(Duration::from_millis(50)).await;

        StdoutLoggingService {
            alert_id: alert_id.to_string(),
        }
    }
}
```

This is not much of an issue.
We just have to make all the functions in this calltree async too.
And this is easy for all the functions we created so far.
It is only the lazy instantiation function that is a bit complex.
And we have to swap `OnceCell` out for something that has async support too.

```rust
use async_once_cell::OnceCell as AsyncOnceCell;
use std::future::Future;
use std::rc::Rc;

pub struct DependencyContainer {
    configuration_manager: Rc<OnceCell<ConfigurationManager>>,
    logging_service: AsyncOnceCell<StdoutLoggingService>,
    alert_id: String,
}

impl DependencyContainer {
    pub fn new() -> Self {
        Self {
            configuration_manager: Rc::new(OnceCell::new()),
            logging_service: AsyncOnceCell::new(),
            alert_id: Default::default(),
        }
    }

    pub fn new_scope(&self, alert_id: &str) -> Self {
        Self {
            configuration_manager: self.configuration_manager.clone(),
            logging_service: AsyncOnceCell::new(),
            alert_id: alert_id.to_string(),
        }
    }

    async fn create_logging_service(&self, alert_id: &str)
        -> StdoutLoggingService
    {
        StdoutLoggingService::new(alert_id).await
    }

    pub async fn logging_service(&self) -> impl LoggingService + '_ {
        let logging_service = self
            .logging_service
            .get_or_init(self.create_logging_service(&self.alert_id)).await;

        logging_service
    }

    async fn create_data_collector<'a, F, L>(
        &self,
        configuration_manager: &ConfigurationManager,
        logging_service_fn: impl Fn() -> F,
    ) -> Box<dyn DataCollector + 'a>
    where
        F: Future<Output = L>,
        L: LoggingService + 'a,
    {
        if let Some(api_key) = configuration_manager.get_api_key() {
            let logging_service = logging_service_fn().await;
            Box::new(ApiDataCollector::new(api_key.to_string(), logging_service))
        } else {
            Box::new(SqlDataCollector::new(
                configuration_manager
                    .get_database_connection_string()
                    .expect("api key or connection string to be set")
                    .to_string(),
            ))
        }
    }

    pub async fn data_collector(&self) -> impl DataCollector + '_ {
        self.create_data_collector(
            self.configuration_manager(),
            || self.logging_service()
        ).await
    }

    pub async fn monitoring_system(
        &self,
    ) -> MonitoringSystem<
        impl DataCollector + '_,
        impl MessageService + '_,
        impl NotificationMessageBuilder + '_,
    > {
        let data_collector = self.data_collector().await;
        let message_service = self.message_service();
        let notification_message_builder = self.notification_message_builder();

        self.create_monitoring_system(
            data_collector,
            message_service,
            notification_message_builder,
        )
    }
}

#[tokio::main]
async fn main() {
    let dc = DependencyContainer::new();

    // Run forever in the background
    for i in 1.. {
        let alert_id = format!("Alert{}", i);

        let dc = dc.new_scope(&alert_id);
        let monitoring_system = dc.monitoring_system().await;

        monitoring_system.check_alert();

        sleep(Duration::from_secs(5)).await;
    }
}
```

As seen we have to:
1. Swap the affected singleton or scope field(s) to use `async_once_cell` instead.
1. The private `create_logging_service` is made async.
1. In general all the public function in the calltree then has to be made async.
1. But in this case the calltree has the private `create_*` with a `Fn` argument.
So this argument is updated too.
1. Finally an `.await` is added in `main.rs` when getting the monitoring system.

This update also makes it easier to see the public function are just boilerplate really.
They have most of the updates but just have the job of linking the dependencies together correctly.
They are prime targets for things a proc-macro can rather generate.
But that is the topic for a next article.

## Dependency Injection in Rust: Pattern Cheatsheet
Here is a recap of all the patterns needed to address each of the requirements we established earlier.

### Concrete Type Dependencies
These are the simplest.
We just return the type as seen for the `ConfigurationManager`.

```rust
impl DependencyContainer {
    fn create_concrete_type(&self) -> ConcreteType {
        ConcreteType::new()
    }

    pub fn concrete_type(&self) -> ConcreteType {
        self.create_concrete_type()
    }
}
```

### Trait-Based Dependencies
This is the main use case for DI.
Here we can return a single abstract type while also taking advantage of static dispatch.
This was seen in the `MessageService` example.

```rust
impl DependencyContainer {
    fn create_impl_abstract(&self) -> impl Abstract {
        ConcreteType::new()
    }

    pub fn impl_abstract(&self) -> impl Abstract {
        self.create_impl_abstract()
    }
}
```

### Dynamic Trait Dependencies
But sometimes the concrete type needs to be decided based off some runtime config.
This requires the use of dynamic dispatch which was seen in for `DataCollector`.

```rust
impl DependencyContainer {
    fn create_impl_abstract(&self, arg: i32) -> Box<dyn Abstract> {
        if arg > 5 {
            Box::new(ConcreteType::new())
        } else {
            Box::new(AnotherConcreteType::new(arg))
        }
    }

    pub fn impl_abstract(&self) -> impl Abstract {
        let arg = self.config;
        
        self.create_impl_abstract(arg)
    }
}

// Implement the [Abstract] trait for the boxed types too
impl<T: Abstract + ?Sized> Abstract for Box<T> {
    fn method_1(&self) -> Vec<String> {
        T::method_1(self)
    }

    fn method_2(&self) -> Vec<String> {
        T::method_2(self)
    }
}
```

### Chaining Dependencies
When a dependency requires some other dependencies or configuration, then these are passed to the private `create_*` method.
This keeps the DX clean by making it easier for developers to just call the argumentless public function instead.

```rust
impl DependencyContainer {
    fn create_chained_dependency(
        &self,
        concrete_type: ConcreteType,
        abstract_type: impl Abstract
    ) -> impl Service
    {
        ConcreteService::new(concrete_type, abstract_type)
    }

    pub fn chained_dependency(&self) -> impl Service {
        let concrete_type = self.concrete_type();
        let abstract_type = self.impl_abstract();
        
        self.create_chained_dependency(concrete_type, abstract_type)
    }
}
```

### Lazy and Conditional Dependencies
Sometimes a dependency in the chain might be conditionally needed.
So we want to avoid creating the dependency in cases when it will not be needed.
This is solved by using a `Fn` callback argument as seen for the `LoggingService`.

```rust
impl DependencyContainer {
    fn create_impl_repository<'a, L>(
        &self,
        optional_dependency_fn: impl Fn() -> L
    ) -> impl Repository
    where
        L: LoggingService + 'a,
    {
        if true {
            let logging_service = optional_dependency_fn();

            Sqlite::new_logging(logging_service)
        } else {
            Sqlite::new()
        }
    }

    pub fn impl_repository(&self) -> impl Repository {
        let logging_service_fn = || self.logging_service();
        
        self.create_impl_repository(logging_service_fn)
    }
}
```

### Transient Dependencies
These are the "default" since they require nothing special.
They just use the normal private `create_*` to hide any dependencies and configuration.
And then have the simple public method which is called without any arguments.
Thus all the above cheatsheet examples are all transient dependencies.
So the dependencies will be created anew with every call.

### Scoped Dependencies
This is a lifetime that does require some changes.
But we only have to add a field to `DependencyContainer` and update the public function by wrapping its content in a `get_or_init()` call.
And we also create a method to easily make new scopes.

Because these return a reference, we may also need to use the wildcard lifetime to correctly link with the `&self` argument's lifetime.
But this is only if the return type is a `impl Trait` like `DataCollector`.
It is not needed for concrete types like `ConfigurationManager`.

```rust
struct DependencyContainer {
    impl_abstract: OnceCell<ConcreteType>, // Or OnceCell<Box<dyn Abstract>>
    scope_config: String,
}
impl DependencyContainer {
    pub fn new() -> Self {
        Self {
            impl_abstract: OnceCell::new(),
            scope_config: Default::default(),
        }
    }

    pub fn new_scope(&self, scope_config: &str) -> Self {
        Self {
            impl_abstract: OnceCell::new(),
            scope_config: scope_config.to_string(),
        }
    }

    pub fn impl_abstract_scoped(&self) -> impl Abstract + '_ {
        self.impl_abstract
            .get_or_init(|| {
                let arg = self.scope_config;

                self.create_impl_abstract(arg)
            })
    }
}

// Implement the [Abstract] trait for the reference returned by [OnceCell]
impl<T: Abstract + ?Sized> Abstract for &T
{
    fn method_1(&self) -> Vec<String> {
        T::method_1(self)
    }

    fn method_2(&self) -> Vec<String> {
        T::method_2(self)
    }
}
```

### Singleton Dependencies
A singleton has the same pattern as a scope and also has the same wildcard lifetime need.
Except that it needs to clone the `OnceCell` when a new scope is created.
This requires wrapping the `OnceCell` in a `Rc`.

```rust
struct DependencyContainer {
    // Or Rc<OnceCell<Box<dyn Abstract>>>
    impl_abstract: Rc<OnceCell<ConcreteType>>,
}
impl DependencyContainer {
    pub fn new() -> Self {
        Self {
            impl_abstract: Rc::new(OnceCell::new()),
        }
    }

    pub fn new_scope(&self) -> Self {
        Self {
            impl_abstract: self.impl_abstract.clone(),
        }
    }

    pub fn impl_abstract_singleton(&self) -> impl Abstract + '_ {
        self.impl_abstract
            .get_or_init(|| {
                let arg = self.config;

                self.create_impl_abstract(arg)
            })
    }
}

// Implement the [Abstract] trait for the reference returned by [OnceCell]
impl<T: Abstract + ?Sized> Abstract for &T
{
    fn method_1(&self) -> Vec<String> {
        T::method_1(self)
    }

    fn method_2(&self) -> Vec<String> {
        T::method_2(self)
    }
}
```
### An async dependency
The last item was a dependency needing an async context to be created.
Here we simply update the affected private `create_*` method and then all the public methods in the calltree to be async too.

```rust
impl DependencyContainer {
    async fn create_impl_service(
        &self,
        concrete_type: ConcreteType,
        abstract_type: impl Abstract
    ) -> impl Service {
        ConcreteService::new_async(concrete_type, abstract_type).await
    }

    pub async fn impl_service(&self) -> impl Service {
        let concrete_type = self.concrete_type();
        let abstract_type = self.impl_abstract();
        
        self.create_impl_service(concrete_type, abstract_type).await
    }
}
```

## Conclusion
In this article, we've explored the intricacies of implementing a custom Dependency Injection container in Rust.
We've tackled the challenges posed by Rust's lack of runtime reflection, leveraging the language's powerful type system and ownership model to create a flexible and type-safe DI solution.

We've covered patterns for handling various dependency types - from simple concrete types to trait objects and async dependencies.
We've also addressed different dependency lifetimes, providing solutions for transient, scoped, and singleton dependencies.
The resulting DI container offers compile-time safety, flexible dependency management, and a clear separation of concerns.

While this manual approach is effective, it can be verbose, especially for larger projects.
However, it provides a solid foundation for understanding how DI works in Rust and sets the stage for further optimizations.

In future articles, we'll explore how to automate much of this boilerplate using Rust's powerful procedural macros, potentially reducing the verbosity while maintaining the type safety and flexibility we've achieved here.
As a macro designer I can already see the private `create_*` methods provide enough details to allow all the other methods and the `DependencyContainer` struct to be generated by a macro.

I encourage you to experiment with these patterns in your own Rust projects.
They can significantly improve the modularity and testability of your code, especially in larger applications.
As you do, you may discover further optimizations or use cases - I'd love to hear about your experiences and insights.

Stay tuned for more articles in this series as we continue to explore advanced dependency management techniques in Rust!
