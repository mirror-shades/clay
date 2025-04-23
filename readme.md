# Clay Language Documentation

Clay is a minimalist data representation language designed for clear, typed data structures. It prioritizes simplicity, compile-time error detection, and explicitness, making it ideal for configuration files, data serialization, and simple data modeling. Clay maps directly to Zig types for efficient integration.

## Design Principles

- **Simplicity**:: Minimal syntax with clear distinctions between variables and groups.
- **Explicitness**:: All variables must be initialized, and types are strictly enforced.
- **Compile-Time Safety**:: Errors (e.g., undefined references, type mismatches) are caught at compile time.
- **Mutability**:: All variables and groups are mutable, with no constants.
- **Scoped Naming**:: Variables and groups have distinct namespaces within their scope.

## Syntax Rules

- Every line starts with an identifier (variable or group).
- Variables are declared with `::` followed by a type and value.
- Groups are declared with `->` and contain nested variables or groups.
- Statements end with a newline or EOF; whitespace and empty lines are ignored.
- Identifiers must be unique within their scope (e.g., a variable and group cannot share a name).
- All variables must be initialized; uninitialized declarations are a compile-time error.
- References to variables or groups must be defined earlier in the file (top-to-bottom evaluation).

### Identifiers

- Valid identifiers use `a-z`, `0-9`, `_`, but must not start with a number (e.g., `my_var`, `user2`, `first_name`).
- Case-sensitive (e.g., `myVar` and `MyVar` are distinct).
- Reserved keywords (TBD, e.g., `int`, `double`, `string`, `bool`, `time`) cannot be used as identifiers.

### Comments

- Single-line:: `; This is a comment`
- Multi-line:: `;* This is a multi-line comment *;`

## Simple Types

Clay has five fixed types, all mutable, mapping to Zig types. Arrays may be added in the future.

### Integer

```clay
; int is an i32
x :: int is 18
```

### Double

```clay
; double is a f64
y :: double is 3.14
```

### String

```clay
; string is a []u8
z :: string is "hello world"
```

### Boolean

```clay
; bool is a bool
; this is because C does not use bools natively
logics :: bool is true
```

### Time

```clay
; time is a i64 but the front end handles ISO conversion
created :: time is 17453900000
updated :: time is "2024-03-14T16::45::00Z"
```

## Variable References

Variables can reference other variables::

```clay
; internal reference is allowed
x :: int is 5
nested :: int is x
```

## Complex Types

Clay has one complex type called a "group", similar to a struct in other languages.

### Basic Group Usage

```clay
person -> age :: int is 25
person -> name :: string is "Bob"

; nested groupings are allowed as well
bigNest -> littleNest -> member1 :: int is 5
```

### Group Scopes

Groups can be written using scope syntax for better readability::

```clay
; this
bigNest -> {
    littleNest -> {
        member1 :: int is 10
    }
    member2 :: int is 2
    member3 :: int is 3
}

; reduces to
bigNest -> littleNest -> member1 :: int is 10
bigNest -> member2 :: int is 2
bigNest -> member3 :: int is 3
```

### Typed Group Scopes

Groups can enforce types for their members::

```clay
; this
nest -> :: int {
    member1 is 10
    member2 is 20
}

; reduces to
nest -> member1 :: int is 10
nest -> member2 :: int is 20
```
