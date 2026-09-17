# ExLisp

A Lisp implementation running on Elixir / BEAM.

## Installation

### Install from Hex.pm

You can install it globally from Hex.pm.

```bash
mix escript.install hex exlisp
```

*Note: After installation, add `~/.mix/escripts` to your `PATH` to run the `exlisp` command directly.*

```bash
exlisp
```

### Build from Source

```bash
mix escript.build
./exlisp
```

## REPL

When started, it enters the REPL interface and evaluates expressions as soon as top-level parentheses are closed (supports multi-line input).

```text
exlisp(1)> (+ 1 2)
3
exlisp(2)> (+ (* 2 3)
      (- 10 4))
12
exlisp(3)> (:math:sqrt 16)
4.0
exlisp(4)> (:math:pow 2 8)
256.0
exlisp(5)> (cons 1 [2 3])
[1, 2, 3]
exlisp(6)> (:lists:reverse [1 2 3 4])
[4, 3, 2, 1]
exlisp(7)> (:lists:sum [10 20 30])
60
exlisp(8)> (:math:sqrt (+ (:math:pow 3 2) (:math:pow 4 2)))
5.0
exlisp(9)> :io:read ">> "
>> 42.
{:ok, 42}
exlisp(10)> IO.puts "hello"
hello
:ok
exlisp(11)> (String.upcase "hello")
"HELLO"
exlisp(12)> (Enum.count [1 2 3 4 5])
5
```

### Re-running Expressions and Referencing Results in REPL

You can specify the prompt number `n` to re-execute past expressions or reference evaluation results.

#### 1. Re-executing Expressions
- `!n`: Re-execute the `n`-th expression (e.g. `!1`)
- `!-1`: Re-execute the previous expression
- `(r n)`: Re-execute the `n`-th expression as a Lisp expression (without args `(r)` for previous)

```text
exlisp(1)> (+ 10 20)
30
exlisp(2)> !1
30
exlisp(3)> (r 1)
30
```

#### 2. Referencing Evaluation Results and Input Expressions
- `(v n)`: Get the `n`-th evaluation result (without args `(v)` for previous)
- `*`, `**`, `***`: Previous / 2nd previous / 3rd previous evaluation results (Common Lisp standard variables)
- `+`, `++`, `+++`: Previous / 2nd previous / 3rd previous input expressions

```text
exlisp(1)> (+ 1 2)
3
exlisp(2)> (+ * 10)
13
exlisp(3)> (v 1)
3
exlisp(4)> [*** ** *]
[3, 13, 3]
```

## Examples

### Basic Arithmetic and Built-in Functions

Built-in functions such as arithmetic operations and `cons` are available.

```text
;; Arithmetic operations
(+ 1 2)                            ; => 3
(* 2 3 4)                          ; => 24

;; Constructing lists (cons)
(cons 1 [2 3])                     ; => [1, 2, 3]
(cons 1 [])                        ; => [1]
(cons (+ 1 2) [(* 2 2)])           ; => [3, 4]
```

### Calling Erlang Functions

You can call Erlang standard module functions in the format `:module:function` or `module:function`.

```text
;; Math functions
(:math:sqrt 16)                    ; => 4.0
(:math:pow 2 8)                    ; => 256.0

;; List operations
(:lists:reverse [1 2 3 4])         ; => [4, 3, 2, 1]
(:lists:sum [10 20 30])            ; => 60
(:lists:nth 2 [10 20 30])          ; => 20

;; System and date information
(:erlang:date)                     ; => {2026, 9, 4}
(:os:type)                         ; => {:unix, :linux}
```

### Nested Execution and Combining Return Values

Return values of functions can be directly combined into other calculations or function calls.

```text
;; Passing function results to arithmetic operations
(+ 10 (:math:sqrt 25))                                ; => 15.0

;; Combining multiple function results (Pythagorean theorem: 3^2 + 4^2 = 5^2)
(:math:sqrt (+ (:math:pow 3 2) (:math:pow 4 2)))      ; => 5.0

;; Fetching elements from list and calculating
(* (:lists:nth 2 [10 20 30]) 2)                       ; => 40
```

### Calling Elixir Functions

You can also call Elixir module functions using the `ModuleName.function_name` format.

```text
(String.upcase "hello")            ; => "HELLO"
(Enum.count [1 2 3 4 5])           ; => 5
(IO.puts "hello")                  ; => :ok
```

At the top level, you can also execute calls without outer parentheses:

```text
String.upcase "hello"              ; => "HELLO"
:math:sqrt 16                      ; => 4.0
```

## Elixir Interoperability (API)

You can evaluate Lisp expressions, get/set global variables, and invoke Lisp functions directly from Elixir code.

```elixir
# Evaluate Lisp expressions
ExLisp.eval("(defparameter count 100)")
# => :count

# Get variable
ExLisp.get_var(:count)
# => 100

# Set variable
ExLisp.set_var(:count, 200)
ExLisp.eval("count")
# => 200

# Define Lisp function and call it from Elixir
ExLisp.eval("(defun multiply (a b) (* a b))")

ExLisp.call(:multiply, [6, 7])
# => 42

# Get as an Elixir anonymous function and execute
mult = ExLisp.get_fun(:multiply)
mult.(3, 5)
# => 15
```

## Using Quicklisp Libraries (`ql:quickload`)

ExLisp supports Quicklisp and ASDF, allowing you to automatically download and load libraries written in Pure Common Lisp (without C extensions or FFI/CFFI).

```text
;; Load and use Alexandria
exlisp(1)> (ql:quickload :alexandria)
(ALEXANDRIA)
exlisp(2)> (clamp 15 0 10)
10
exlisp(3)> (clamp -5 0 10)
0

;; Load and use split-sequence
exlisp(4)> (ql:quickload :split-sequence)
(SPLIT-SEQUENCE)
exlisp(5)> (split-sequence #\Space "hello world foo bar")
("hello" "world" "foo" "bar")
```

## Using Hex.pm Libraries

Supports single packages (with or without version requirements) or lists of multiple packages.

```text
;; Install and use Jason
exlisp(1)> (hex:install :jason "~> 1.4")
(Jason)
exlisp(2)> (Jason.encode! [1 2 3])
"[1,2,3]"

;; Install latest version (omitting version requirement)
exlisp(3)> (hex:install :floki)
(Floki)
exlisp(4)> (Floki.parse_document! "<h1>Hello</h1>")
({"h1", NIL, ("Hello")})

;; Batch install multiple packages
exlisp(5)> (hex:install '((:decimal "~> 2.0") :timex))
(Decimal Timex)
exlisp(6)> (Decimal.new "123.45")
#Decimal<123.45>
```

## Running Lisp Files and BEAM Compilation

Supports script execution (passing a file argument or `--script`), interactive REPL startup with preloaded files (`--load`), and compiling to BEAM bytecode (`-c` / `--compile`).

### 1. Script Execution (File Argument or `--script`, `-s`)

Evaluates and executes the file sequentially as a script from top to bottom, then exits the process upon completion (no banner display, does not enter REPL).

```bash
# Pass file argument directly
exlisp script.lisp

# Or use --script option
exlisp --script script.lisp
exlisp -s script.lisp
```

### 2. Loading Files and Starting REPL (`--load`, `-l`)

Loads and runs a file, then starts the interactive REPL with the loaded environment preserved.

```bash
# --load option
exlisp --load file.lisp
exlisp -l file.lisp
```

### 3. Compiling to BEAM Bytecode and Persistence (`-c`, `--compile`)

By compiling Lisp source files (`.lisp`) to BEAM bytecode (`.beam` files), compiled variables and functions can be directly accessed from other processes such as `iex -S mix` even after the `exlisp` command exits.

#### Creating a Lisp File

```lisp
;; sample.lisp
(defparameter base 100)
(defvar multiplier 2)

(defun add (a b)
  (+ a b))

(defun calc (x)
  (* (+ x base) multiplier))
```

#### Compiling to BEAM with `exlisp -c`

Specifying the `-c` (or `--compile`) option compiles the Lisp file into BEAM bytecode.

If `-m` or `-o` is not specified, the defaults are:
- **Module Name**: `ExLisp.Global`
- **Output Directory**: `_build/dev/lib/<app>/ebin` inside a Mix project, otherwise `ebin/` under the current directory
- **Generated Filename**: `Elixir.ExLisp.Global.beam`

```bash
# When -m and -o are omitted (default)
exlisp -c sample.lisp
# => Compiled sample.lisp to _build/dev/lib/exlisp/ebin/Elixir.ExLisp.Global.beam (module: ExLisp.Global)
```

*Options can be specified to customize output:*
- `-o <dir>` / `--output <dir>`: Specify output directory (e.g. `-o ebin`)
- `-m <Module>` / `--module <Module>`: Specify generated module name (e.g. `-m MyModule`)

#### Calling from Elixir (When `-m`, `-o` are not specified)

If `-m` is omitted, it is defined as the `ExLisp.Global` module, callable via `ExLisp.Global.<function_name>` (function names are lowercased).

##### 1. Calling Inside a Mix Project (`iex -S mix`)

Under a Mix environment, the compile path is automatically set, so you can call it directly:

```elixir
$ iex -S mix

# Call compiled module functions directly
iex> ExLisp.Global.add(10, 20)
30

iex> ExLisp.Global.calc(5)
210

# Access via ExLisp API
iex> ExLisp.get_var(:base)
100

iex> ExLisp.call(:add, [1, 2])
3

# Use compiled functions/variables inside Lisp expressions
iex> ExLisp.eval("(calc 10)")
220
```

##### 2. Loading beam files output to `ebin/`

Outside a Mix project where `.beam` files are generated in `ebin/` of the current directory, add the load path before calling:

```bash
# Pass path with -pa when starting iex / elixir
$ iex -pa ebin
iex> ExLisp.Global.add(1, 2)
3
```

Alternatively, add the path from within Elixir code:

```elixir
Code.append_path("ebin")
ExLisp.Global.add(1, 2)
# => 3
```

