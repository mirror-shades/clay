## built with zig 0.15

- use 'zig build' to build from source

# Para Language Documentation

Para is a minimalist data representation language designed for clear, typed data structures. It prioritizes simplicity, compile-time error detection, and explicitness, making it ideal for configuration files, data serialization, and simple data modeling. Para maps directly to Zig types for efficient integration.

## Design Principles

- **Simplicity**: Minimal syntax with clear distinctions between variables and groups.
- **Explicitness**: All variables must be initialized, and types are strictly enforced.
- **Compile-Time Safety**: Errors (e.g., undefined references, type mismatches) are caught at compile time.
- **Mutability**: All variables and groups are mutable, unless marked constant.
- **Scoped Naming**: Variables and groups have distinct namespaces within their scope.

## Syntax Rules

- Every line starts with an identifier (variable or group).
- Variables are declared with `:` followed by a type and value.
- Groups are declared with `->` and contain nested variables or groups.
- Statements end with a newline or EOF; whitespace and empty lines are ignored.
- Identifiers must be unique within their scope (e.g., a variable and group cannot share a name).
- All variables must be initialized; uninitialized declarations are a compile-time error.
- References to variables or groups must be defined earlier in the file (top-to-bottom evaluation).

### Identifiers

- Valid identifiers use `a-z`, `0-9`, `_`, but must not start with a number (e.g., `my_var`, `user2`, `first_name`).
- Case-sensitive (e.g., `myVar` and `MyVar` are distinct).
- Reserved keywords (TBD, e.g., `int`, `float`, `string`, `bool`, `time`) cannot be used as identifiers.

### Comments

- Single-line: `// This is a comment`
- Multi-line: `/* This is a multi-line comment */`

## Simple Types

Para has five fixed types, all mutable unless marked constant. Heterogeneous arrays will be added in the future.

### Integer

```para
// int is an i32
x : int = 18
```

### Float

```para
// float is a f64
y : float = 3.14
```

### String

```para
// string is a []u8
z : string = "hello world"
```

### Boolean

```para
// bool is a bool
logics : bool = true
```

### Time

```para
// time is a i64 but the front end can handle ISO conversion
created : time = 17453900000
updated : time = "2024-03-14T16:45:00Z"
```

### Constants

```para
// fields can be marked constant
id : const int = 567
```

### Nulls

```para
// null is a value than can be assigned to any type if permitted
x : int = null // this errors, must be a nullable type
x : int? = null // this is correct
x : const int? = null // this errors because const can't be null
```

## Variable References

Variables can reference other variables:

```para
// internal reference is allowed
x : int = 5
nested : int = x
```

## Complex Types

Para has one complex type called a "group", similar to a struct in other languages.

### Basic Group Usage

```para
person -> age : int = 25
person -> name : string = "Bob"

// nested groupings are allowed as well
bigNest -> littleNest -> member1 : int = 5
```

### Group Scopes

Groups can be written using scope syntax for better readability:

```para
// this
bigNest -> {
    littleNest -> {
        member1 : int = 10
    }
    member2 : int = 2
    member3 : int = 3
}

// reduces to
bigNest -> littleNest -> member1 : int = 10
bigNest -> member2 : int = 2
bigNest -> member3 : int = 3
```

### Typed Group Scopes

Groups can enforce types for their members:

```para
// this
nest -> : int {
    member1 = 10
    member2 = 20
}

// reduces to
nest -> member1 : int = 10
nest -> member2 : int = 20
```

## Preprocessing Steps

Para files go through several preprocessing steps for flexibility and optimization:

### Step 1: Starting Config

Configs are flexible - as long as values are initialized before use, they can be referenced:

```para
defaults -> age : int = 25
new_age : int = defaults -> age
person -> age : int = new_age
person -> name : string = "Robert"
nickname : string = "Bob"
person -> nickname = nickname
```

### Step 2: Baked Values

This is the default way Para is used. All values are resolved before runtime:

```para
defaults -> age : int = 25
new_age : int = 25
person -> age : int = 25
person -> name : string = "Robert"
nickname : string = "Bob"
person -> nickname = "Bob"
```

### Step 3: Compressed Values

An additional step can be done to compress values. Globals are raised and groups are unified:

```para
new_age : int = 25
nickname : string = "Bob"

defaults -> age : int = 25
person -> {
    age : int = 25
    name : string = "Robert"
    nickname = "Bob"
}
```

### Step 4: Transpile

The compressed format can be transpiled into other serialization languages:

```json
{
  "new_age": 25,
  "nickname": "Bob",
  "defaults": {
    "age": 25
  },
  "person": {
    "age": 25,
    "name": "Robert",
    "nickname": "Bob"
  }
}
```
