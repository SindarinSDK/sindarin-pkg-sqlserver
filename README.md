# sindarin-pkg-sqlserver

A SQL Server client for the [Sindarin](https://github.com/SindarinSDK/sindarin-compiler) programming language, backed by [FreeTDS](https://www.freetds.org/). Supports direct SQL execution, row queries with typed accessors, and named prepared statements with parameter binding and reuse.

## Installation

Add the package as a dependency in your `sn.yaml`:

```yaml
dependencies:
- name: sindarin-pkg-sqlserver
  git: https://github.com/SindarinSDK/sindarin-pkg-sqlserver.git
  branch: main
```

Then run `sn --install` to fetch the package.

## Quick Start

```sindarin
import "sindarin-pkg-sqlserver/src/sqlserver"

fn main(): void =>
    var conn: SqlServerConn = SqlServerConn.connect(
        "server=localhost:1433;database=mydb;user=sa;password=pass"
    )

    conn.exec("CREATE TABLE users (id INT IDENTITY(1,1) PRIMARY KEY, name NVARCHAR(100), age INT)")
    conn.exec("INSERT INTO users (name, age) VALUES (N'Alice', 30)")

    var rows: SqlServerRow[] = conn.query("SELECT * FROM users ORDER BY id")
    print(rows[0].getString("name"))
    print(rows[0].getInt("age"))

    conn.dispose()
```

---

## SqlServerConn

```sindarin
import "sindarin-pkg-sqlserver/src/sqlserver"
```

A database connection. The connection string uses a semicolon-delimited `key=value` format.

| Method | Signature | Description |
|--------|-----------|-------------|
| `connect` | `static fn connect(connStr: str): SqlServerConn` | Connect to a SQL Server instance |
| `exec` | `fn exec(sql: str): void` | Execute SQL with no results (CREATE, INSERT, UPDATE, DELETE) |
| `query` | `fn query(sql: str): SqlServerRow[]` | Execute a SELECT and return all rows |
| `prepare` | `fn prepare(name: str, sql: str): SqlServerStmt` | Create a named prepared statement |
| `lastError` | `fn lastError(): str` | Last error message from the server |
| `dispose` | `fn dispose(): void` | Close the connection |

Connection string format: `server=hostname:port;database=dbname;user=username;password=secret`

```sindarin
var conn: SqlServerConn = SqlServerConn.connect(
    "server=localhost:1433;database=mydb;user=sa;password=secret"
)

conn.exec("CREATE TABLE IF NOT EXISTS items (id INT IDENTITY(1,1) PRIMARY KEY, name NVARCHAR(200), price FLOAT)")
conn.exec("INSERT INTO items (name, price) VALUES (N'widget', 9.99)")

conn.dispose()
```

---

## SqlServerRow

A single result row. Column values are accessed by name using typed getters.

| Method | Signature | Description |
|--------|-----------|-------------|
| `getString` | `fn getString(col: str): str` | Column value as string (`""` for NULL) |
| `getInt` | `fn getInt(col: str): int` | Column value as integer (`0` for NULL) |
| `getFloat` | `fn getFloat(col: str): double` | Column value as float (`0.0` for NULL) |
| `isNull` | `fn isNull(col: str): bool` | True if the column is SQL NULL |
| `columnCount` | `fn columnCount(): int` | Number of columns in this row |
| `columnName` | `fn columnName(index: int): str` | Column name at the given zero-based index |

```sindarin
var rows: SqlServerRow[] = conn.query("SELECT name, price, notes FROM items")

for i: int = 0; i < rows.length; i += 1 =>
    print(rows[i].getString("name"))
    print(rows[i].getFloat("price"))
    if rows[i].isNull("notes") =>
        print("no notes\n")
```

---

## SqlServerStmt

A named prepared statement with parameter binding. Parameters use `?` placeholders and are indexed from 1. Bind methods return `self` for chaining. Statements can be reset and re-executed with new bindings.

| Method | Signature | Description |
|--------|-----------|-------------|
| `bindString` | `fn bindString(index: int, value: str): SqlServerStmt` | Bind a string to the given parameter (1-based) |
| `bindInt` | `fn bindInt(index: int, value: int): SqlServerStmt` | Bind an integer to the given parameter (1-based) |
| `bindFloat` | `fn bindFloat(index: int, value: double): SqlServerStmt` | Bind a float to the given parameter (1-based) |
| `bindNull` | `fn bindNull(index: int): SqlServerStmt` | Bind SQL NULL to the given parameter (1-based) |
| `exec` | `fn exec(): void` | Execute with no results |
| `query` | `fn query(): SqlServerRow[]` | Execute and return all result rows |
| `reset` | `fn reset(): void` | Clear all bindings for re-use |
| `dispose` | `fn dispose(): void` | Free statement resources |

```sindarin
var stmt: SqlServerStmt = conn.prepare("insert_user",
    "INSERT INTO users (name, age, score) VALUES (?, ?, ?)")

stmt.bindString(1, "Bob").bindInt(2, 25).bindFloat(3, 8.5).exec()

stmt.reset()
stmt.bindString(1, "Carol").bindInt(2, 30).bindNull(3).exec()

stmt.dispose()
```

Prepared statements can also return rows:

```sindarin
var sel: SqlServerStmt = conn.prepare("find_cheap", "SELECT * FROM items WHERE price < ?")
var rows: SqlServerRow[] = sel.bindFloat(1, 20.0).query()
sel.dispose()
```

---

## Examples

### Basic CRUD

```sindarin
import "sindarin-pkg-sqlserver/src/sqlserver"

fn main(): void =>
    var conn: SqlServerConn = SqlServerConn.connect(
        "server=localhost:1433;database=mydb;user=sa;password=secret"
    )

    conn.exec("CREATE TABLE products (id INT IDENTITY(1,1) PRIMARY KEY, name NVARCHAR(100), stock INT)")
    conn.exec("INSERT INTO products (name, stock) VALUES (N'alpha', 10)")
    conn.exec("INSERT INTO products (name, stock) VALUES (N'beta', 5)")

    var rows: SqlServerRow[] = conn.query("SELECT * FROM products ORDER BY id")
    for i: int = 0; i < rows.length; i += 1 =>
        print($"{rows[i].getString(\"name\")}: {rows[i].getInt(\"stock\")}\n")

    conn.exec("UPDATE products SET stock = 0 WHERE name = 'beta'")
    conn.exec("DELETE FROM products WHERE stock = 0")

    conn.dispose()
```

### Bulk insert with prepared statement

```sindarin
import "sindarin-pkg-sqlserver/src/sqlserver"

fn main(): void =>
    var conn: SqlServerConn = SqlServerConn.connect(
        "server=localhost:1433;database=mydb;user=sa;password=secret"
    )
    conn.exec("CREATE TABLE log (msg NVARCHAR(200), level INT)")

    var stmt: SqlServerStmt = conn.prepare("insert_log",
        "INSERT INTO log (msg, level) VALUES (?, ?)")

    stmt.bindString(1, "started").bindInt(2, 1).exec()
    stmt.reset()
    stmt.bindString(1, "processing").bindInt(2, 1).exec()
    stmt.reset()
    stmt.bindString(1, "done").bindInt(2, 2).exec()

    stmt.dispose()
    conn.dispose()
```

### Parameterized query returning rows

```sindarin
import "sindarin-pkg-sqlserver/src/sqlserver"

fn main(): void =>
    var conn: SqlServerConn = SqlServerConn.connect(
        "server=localhost:1433;database=mydb;user=sa;password=secret"
    )

    var sel: SqlServerStmt = conn.prepare("active_users",
        "SELECT name, age FROM users WHERE age >= ? ORDER BY age")
    var rows: SqlServerRow[] = sel.bindInt(1, 18).query()

    for i: int = 0; i < rows.length; i += 1 =>
        print($"{rows[i].getString(\"name\")} ({rows[i].getInt(\"age\")})\n")

    sel.dispose()
    conn.dispose()
```

---

## Development

```bash
# Install dependencies (required before make test)
sn --install

make test    # Build and run all tests
make clean   # Remove build artifacts
```

Tests require a running SQL Server instance. Set the connection string via environment or pass it directly in the test source.

## Dependencies

- [sindarin-pkg-sdk](https://github.com/SindarinSDK/sindarin-pkg-sdk) -- Sindarin standard library.
- [sindarin-pkg-test](https://github.com/SindarinSDK/sindarin-pkg-test) -- Testing framework.
- [FreeTDS](https://www.freetds.org/) -- provides the `sybdb` library for TDS protocol communication with SQL Server.

## Platform Notes

FreeTDS (`libsybdb`) must be available on the system. Install via your package manager:

| Platform | Install Command |
|----------|-----------------|
| **Linux (Debian/Ubuntu)** | `sudo apt install freetds-dev` |
| **Linux (Fedora/RHEL)** | `sudo dnf install freetds-devel` |
| **macOS** | `brew install freetds` |
| **Windows** | Use vcpkg: `vcpkg install freetds` |

## License

MIT License
