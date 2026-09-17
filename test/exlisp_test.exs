defmodule ExLispTest do
  use ExUnit.Case
  doctest ExLisp

  describe "literal evaluation" do
    test "evaluates integer literals" do
      assert ExLisp.eval("42") == 42
      assert ExLisp.eval("-10") == -10
    end

    test "evaluates float literals" do
      assert ExLisp.eval("3.14") == 3.14
      assert ExLisp.eval("-2.5") == -2.5
    end

    test "evaluates string literals" do
      assert ExLisp.eval(~s{"hello"}) == "hello"
    end

    test "evaluates atom literals" do
      assert ExLisp.eval(":foo") == :foo
    end
  end

  describe "arithmetic operations" do
    test "evaluates addition (+)" do
      assert ExLisp.eval("(+ 5)") == 5
      assert ExLisp.eval("(+ 1 2)") == 3
      assert ExLisp.eval("(+ 1 2 3 4)") == 10
      assert ExLisp.eval("(+ 1.5 2.5)") == 4.0
    end

    test "evaluates subtraction (-)" do
      assert ExLisp.eval("(- 5)") == -5
      assert ExLisp.eval("(- 10 3)") == 7
      assert ExLisp.eval("(- 10 3 2)") == 5
    end

    test "evaluates multiplication (*)" do
      assert ExLisp.eval("(* 5)") == 5
      assert ExLisp.eval("(* 3 4)") == 12
      assert ExLisp.eval("(* 2 3 4)") == 24
    end

    test "evaluates division (/)" do
      assert ExLisp.eval("(/ 5)") == ExLisp.Ratio.new(1, 5)
      assert ExLisp.eval("(/ 10 2)") == 5
      assert ExLisp.eval("(/ 20 2 2)") == 5
      assert ExLisp.eval("(/ 4 6)") == ExLisp.Ratio.new(2, 3)
      assert ExLisp.eval("(/ 4.0 6)") == 4.0 / 6
    end
  end

  describe "list operations" do
    test "evaluates cons" do
      assert ExLisp.eval("(cons 1 [2 3])") == [1, 2, 3]
      assert ExLisp.eval("(cons 1 [])") == [1]
      assert ExLisp.eval("(cons [1 2] [3 4])") == [[1, 2], 3, 4]
      assert ExLisp.eval("(cons (+ 1 2) [(* 2 2)])") == [3, 4]
    end

    test "raises error when cons has invalid number of arguments" do
      assert_raise ArgumentError, ~r/cons requires exactly 2 arguments/, fn ->
        ExLisp.eval("(cons 1)")
      end

      assert_raise ArgumentError, ~r/cons requires exactly 2 arguments/, fn ->
        ExLisp.eval("(cons 1 [2] [3])")
      end
    end
  end

  describe "nested expressions" do
    test "evaluates nested arithmetic expressions" do
      assert ExLisp.eval("(+ (* 2 3) (- 10 4))") == 12
      assert ExLisp.eval("(* (+ 1 2) (- 10 (/ 8 2)))") == 18
    end
  end

  describe "remote function calls" do
    import ExUnit.CaptureIO

    test "evaluates Erlang math module functions" do
      assert ExLisp.eval("(:math:sqrt 16)") == 4.0
      assert ExLisp.eval(":math:sqrt 16") == 4.0
      assert ExLisp.eval("(math:sqrt 16)") == 4.0
      assert ExLisp.eval("(math.sqrt 16)") == 4.0
    end

    test "evaluates nested remote calls with arithmetic" do
      assert ExLisp.eval("(+ 10 (:math:sqrt 25))") == 15.0
    end

    test "evaluates Elixir module functions" do
      captured =
        capture_io(fn ->
          assert ExLisp.eval(~s{(IO.puts "hello")}) == :ok
        end)

      assert captured == "hello\n"

      assert ExLisp.eval(~s{String.upcase "hello"}) == "HELLO"
      assert ExLisp.eval(~s{(String.upcase "world")}) == "WORLD"
      assert ExLisp.eval(~s{(Enum.count [1 2 3 4])}) == 4
    end

    test "evaluates :io:read call" do
      captured =
        capture_io([input: "123.\n"], fn ->
          assert ExLisp.eval(~s{:io:read ">> "}) == {:ok, 123}
        end)

      assert captured == ">> "
    end

    test "evaluates parenthesized (:io:read ...) call" do
      captured =
        capture_io([input: "atom_val.\n"], fn ->
          assert ExLisp.eval(~s{(:io:read ">> ")}) == {:ok, :atom_val}
        end)

      assert captured == ">> "
    end
  end

  setup do
    ExLisp.Env.reset()
    :ok
  end

  describe "defparameter" do
    test "defines parameter and sets its value" do
      assert ExLisp.eval("(defparameter x 10)") == :x
      assert ExLisp.eval("x") == 10
    end

    test "evaluates expressions for initial value" do
      assert ExLisp.eval("(defparameter x (+ 10 20))") == :x
      assert ExLisp.eval("x") == 30
    end

    test "always overwrites existing value" do
      assert ExLisp.eval("(defparameter x 10)") == :x
      assert ExLisp.eval("x") == 10
      assert ExLisp.eval("(defparameter x 20)") == :x
      assert ExLisp.eval("x") == 20
    end

    test "supports optional docstring" do
      assert ExLisp.eval(~s{(defparameter x 42 "a test parameter")}) == :x
      assert ExLisp.eval("x") == 42
    end
  end

  describe "defvar" do
    test "defines variable when unbound" do
      assert ExLisp.eval("(defvar y 100)") == :y
      assert ExLisp.eval("y") == 100
    end

    test "does not overwrite existing value" do
      assert ExLisp.eval("(defparameter z 50)") == :z
      assert ExLisp.eval("(defvar z 999)") == :z
      assert ExLisp.eval("z") == 50
    end

    test "does not evaluate init-form if already bound" do
      assert ExLisp.eval("(defparameter a 10)") == :a
      # If (+ a 5) were evaluated, it would evaluate cleanly, but we verify 'a' remains unchanged
      assert ExLisp.eval("(defvar a (+ a 5))") == :a
      assert ExLisp.eval("a") == 10
    end

    test "supports optional docstring" do
      assert ExLisp.eval(~s{(defvar v 77 "a docstring")}) == :v
      assert ExLisp.eval("v") == 77
    end
  end

  describe "defun" do
    test "defines a function and invokes it" do
      assert ExLisp.eval("(defun add (a b) (+ a b))") == :add
      assert ExLisp.eval("(add 3 4)") == 7
    end

    test "defines zero-argument function" do
      assert ExLisp.eval("(defun answer () 42)") == :answer
      assert ExLisp.eval("(answer)") == 42
    end

    test "supports multiple expressions in body (evaluates all, returns last)" do
      assert ExLisp.eval("(defun multi (x) (+ x 1) (+ x 2) (+ x 3))") == :multi
      assert ExLisp.eval("(multi 10)") == 13
    end

    test "supports optional docstring in body" do
      assert ExLisp.eval(~s{(defun double (x) "doubles x" (* x 2))}) == :double
      assert ExLisp.eval("(double 5)") == 10
    end

    test "calls other user-defined functions" do
      ExLisp.eval("(defun double (x) (* x 2))")
      ExLisp.eval("(defun quad (x) (double (double x)))")
      assert ExLisp.eval("(quad 3)") == 12
    end

    test "references global variables" do
      ExLisp.eval("(defparameter base 100)")
      ExLisp.eval("(defun add_to_base (x) (+ x base))")
      assert ExLisp.eval("(add_to_base 5)") == 105

      ExLisp.eval("(defparameter base 200)")
      assert ExLisp.eval("(add_to_base 5)") == 205
    end

    test "parameters shadow global variables" do
      ExLisp.eval("(defparameter x 100)")
      ExLisp.eval("(defun shadow_test (x) (+ x 1))")
      assert ExLisp.eval("(shadow_test 5)") == 6
      assert ExLisp.eval("x") == 100
    end

    test "redefines function when defun is called again" do
      ExLisp.eval("(defun greet (x) (+ x 1))")
      assert ExLisp.eval("(greet 10)") == 11

      ExLisp.eval("(defun greet (x) (+ x 100))")
      assert ExLisp.eval("(greet 10)") == 110
    end
  end

  describe "symbol case handling and REPL display" do
    test "stores symbols internally in lowercase" do
      assert ExLisp.eval("(DEFPARAMETER MY_VAL 100)") == :my_val
      assert ExLisp.eval("my_val") == 100
      assert ExLisp.eval("MY_VAL") == 100
      assert ExLisp.eval("My_Val") == 100

      assert ExLisp.eval("(DEFVAR OTHER_VAL 200)") == :other_val
      assert ExLisp.eval("(defvar OTHER_VAL 999)") == :other_val
      assert ExLisp.eval("OTHER_VAL") == 200

      assert ExLisp.eval("(DEFUN ADD_TWO (A B) (+ A B))") == :add_two
      assert ExLisp.eval("(add_two 1 2)") == 3
      assert ExLisp.eval("(ADD_TWO 1 2)") == 3
      assert ExLisp.eval("(Add_Two 1 2)") == 3

      assert ExLisp.eval(":FOO") == :foo
      assert ExLisp.eval(":foo") == :foo
    end

    test "converts symbols to uppercase for REPL display" do
      assert ExLisp.eval_repl("(defparameter x 10)") == ExLisp.Symbol.new("X")
      assert ExLisp.eval_repl("(DEFPARAMETER X 10)") == ExLisp.Symbol.new("X")
      assert ExLisp.eval_repl("(defparameter *small* 1)") == ExLisp.Symbol.new("*SMALL*")
      assert inspect(ExLisp.eval_repl("(defparameter *small* 1)")) == "*SMALL*"
      assert inspect(ExLisp.eval_repl("(defparameter x 10)")) == "X"
      assert ExLisp.eval_repl("*small*") == 1
      assert ExLisp.eval_repl("*SMALL*") == 1
      assert ExLisp.eval_repl("(defun add (a b) (+ a b))") == ExLisp.Symbol.new("ADD")
      assert inspect(ExLisp.eval_repl("(defun add (a b) (+ a b))")) == "ADD"
      assert ExLisp.eval_repl(":foo") == ExLisp.Symbol.new("FOO")
      assert ExLisp.eval_repl("x") == 10
      assert ExLisp.eval_repl("(add 1 2)") == 3

      assert ExLisp.to_repl_display(:my_symbol) == ExLisp.Symbol.new("MY_SYMBOL")
      assert inspect(ExLisp.to_repl_display(:my_symbol)) == "MY_SYMBOL"
      assert ExLisp.to_repl_display(:"*small*") == ExLisp.Symbol.new("*SMALL*")
      assert inspect(ExLisp.to_repl_display(:"*small*")) == "*SMALL*"

      assert ExLisp.to_repl_display([:a, :b, 10]) ==
               %ExLisp.List{
                 items: [
                   ExLisp.Symbol.new("A"),
                   ExLisp.Symbol.new("B"),
                   10
                 ],
                 tail: nil
               }

      assert inspect(ExLisp.to_repl_display([:a, :b, 10])) == "(A B 10)"
      assert inspect(ExLisp.eval_repl("'(expt 2 3)")) == "(EXPT 2 3)"
      assert inspect(ExLisp.eval_repl("'('chichen 'cat)")) == "('CHICHEN 'CAT)"
      assert inspect(ExLisp.eval_repl("(cons 'chichen 'cat)")) == "(CHICHEN . CAT)"
      assert inspect(ExLisp.eval_repl("'''a")) == "''A"

      assert ExLisp.to_repl_display({:ok, :hello}) ==
               {ExLisp.Symbol.new("OK"), ExLisp.Symbol.new("HELLO")}

      assert inspect(ExLisp.to_repl_display({:ok, :hello})) == "{OK, HELLO}"
    end
  end

  describe "Elixir interop API" do
    test "gets and sets global variables from Elixir" do
      ExLisp.eval("(defparameter count 42)")
      assert ExLisp.get_var(:count) == 42
      assert ExLisp.get_var("COUNT") == 42
      assert ExLisp.has_var?(:count)
      assert ExLisp.has_var?("count")

      ExLisp.set_var(:count, 100)
      assert ExLisp.eval("count") == 100

      ExLisp.set_var("new_var", [1, 2, 3])
      assert ExLisp.eval("new_var") == [1, 2, 3]

      ExLisp.delete_var(:count)
      refute ExLisp.has_var?(:count)
    end

    test "calls Lisp functions from Elixir" do
      ExLisp.eval("(defun multiply (a b) (* a b))")
      assert ExLisp.has_fun?(:multiply)
      assert ExLisp.has_fun?("MULTIPLY")

      assert ExLisp.call(:multiply, [6, 7]) == 42
      assert ExLisp.call("MULTIPLY", [3, 5]) == 15

      fun = ExLisp.get_fun(:multiply)
      assert is_function(fun, 2)
      assert fun.(4, 5) == 20
    end
  end

  describe "REPL history and rerun (v, r, *, **, ***)" do
    test "records history and retrieves results with v and *" do
      ExLisp.Env.reset()
      # counter 1 => 30
      ExLisp.eval_repl("(+ 10 20)")
      # counter 2 => 6
      ExLisp.eval_repl("(* 2 3)")
      # counter 3 => 99
      ExLisp.eval_repl("(- 100 1)")

      assert ExLisp.eval_repl("(list * ** ***)") == %ExLisp.List{items: [99, 6, 30], tail: nil}

      assert ExLisp.eval_repl("(v 1)") == 30
      assert ExLisp.eval_repl("(v 2)") == 6
      assert ExLisp.eval_repl("(v 3)") == 99
      assert ExLisp.eval_repl("(v)") == 99

      ExLisp.eval_repl("'(expt 2 3)")
      assert ExLisp.eval_repl("(car *)") == ExLisp.Symbol.new("EXPT")
      assert ExLisp.eval_repl("(cdr **)") == %ExLisp.List{items: [2, 3], tail: nil}
      assert inspect(ExLisp.eval_repl("(cdr ***)")) == "(2 3)"
    end

    test "reruns expressions with r and !" do
      import ExUnit.CaptureIO

      ExLisp.Env.reset()
      ExLisp.eval_repl("(defparameter val 10)")
      ExLisp.eval_repl("(setf val (+ val 5))")
      assert ExLisp.eval_repl("val") == 15

      # Re-execute the 2nd expression: (setf val (+ val 5))
      captured_r =
        capture_io(fn ->
          ExLisp.eval_repl("(r 2)")
        end)

      assert captured_r =~ "==> (setf val (+ val 5))"
      assert ExLisp.eval_repl("val") == 20

      # Test !n in Parser
      captured_bang =
        capture_io(fn ->
          assert {:ok, expr, {"", :other}} = ExLisp.Parser.parse("!1\n", [], "")
          assert Macro.to_string(expr) == "ExLisp.eval_repl(\"(defparameter val 10)\")"
        end)

      assert captured_bang =~ "==> (defparameter val 10)"
    end

    test "ensures fresh-line after output in eval_repl" do
      import ExUnit.CaptureIO

      # princ does not print a newline, but eval_repl adds a fresh-line (newline) at termination
      captured =
        capture_io(fn ->
          assert ExLisp.eval_repl(~s{(princ "aaa")}) == "aaa"
        end)

      assert captured == "aaa\n"

      # eval alone does not add a newline (conforming to Common Lisp spec)
      captured_eval =
        capture_io(fn ->
          assert ExLisp.eval(~s{(princ "aaa")}) == "aaa"
        end)

      assert captured_eval == "aaa"

      # When a trailing newline already exists, do not double newline
      captured_format =
        capture_io(fn ->
          assert ExLisp.eval_repl(~s{(format t "hello~%")}) == ExLisp.Symbol.new("NIL")
        end)

      assert captured_format == "hello\n"

      # Expressions without output should print nothing
      captured_pure =
        capture_io(fn ->
          assert ExLisp.eval_repl("(+ 1 2)") == 3
        end)

      assert captured_pure == ""
    end
  end

  describe "file loading (load, load_file)" do
    test "loads and evaluates a lisp file" do
      tmp_file =
        Path.join(System.tmp_dir!(), "test_load_#{System.unique_integer([:positive])}.lisp")

      File.write!(tmp_file, """
      (defparameter *test_loaded_var* 123)
      (defun test-loaded-fn (x) (* x 2))
      """)

      on_exit(fn -> File.rm(tmp_file) end)

      assert ExLisp.load_file(tmp_file) != nil
      assert ExLisp.eval("*test_loaded_var*") == 123
      assert ExLisp.eval("(test-loaded-fn 21)") == 42

      # Via Common Lisp (load ...) function
      assert ExLisp.eval(~s{(load "#{tmp_file}")}) == :t
    end
  end

  describe "error handling" do
    test "raises error for undefined function" do
      assert_raise RuntimeError, ~r/Undefined function/, fn ->
        ExLisp.eval("(unknown 1 2)")
      end
    end

    test "raises error for unbound variable" do
      assert_raise RuntimeError, ~r/Unbound variable/, fn ->
        ExLisp.eval("unbound_var")
      end
    end
  end
end
