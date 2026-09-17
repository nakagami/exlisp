# Calculator (ASDF Multi-File Example)

A multi-file project example using **ASDF**, the standard build and system definition facility for Common Lisp.

## Directory Structure

```text
examples/calculator/
├── calculator.asd    # ASDF system definition (dependencies, component definitions)
├── package.lisp      # Package definition and exported symbols
├── math.lisp         # Arithmetic functions (add, subtract, multiply, divide)
├── utils.lisp        # Utility and formatting functions
├── main.lisp         # Main logic and demo execution function (calculate-and-print, run-demo)
├── run.lisp          # Runner script
└── README.md         # This README file
```

## How to Run

```bash
# Direct script execution
./exlisp --script examples/calculator/run.lisp

# Or execute from REPL / eval
(asdf:load-system :calculator)
(calculator:run-demo)
```
