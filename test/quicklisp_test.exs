defmodule QuicklispTest do
  use ExUnit.Case
  @moduletag timeout: 180_000

  setup do
    ExLisp.Env.reset()
    :ok
  end

  test "ASDF propagates component parse and evaluation errors" do
    dir = Path.join(System.tmp_dir!(), "exlisp-asdf-errors-#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf!(dir) end)

    eval_file = Path.join(dir, "broken-eval.lisp")
    syntax_file = Path.join(dir, "broken-syntax.lisp")
    File.write!(eval_file, "(error \"component failed\")")
    File.write!(syntax_file, "(defun broken (x)")

    system = %{
      name: "BROKEN",
      pathname: nil,
      components: [{:file, "missing", []}]
    }

    assert_raise RuntimeError, ~r/ASDF component file not found/, fn ->
      ExLisp.ASDF.load_system(system, dir)
    end

    system = %{system | components: [{:file, "broken-eval", []}]}

    assert_raise RuntimeError, ~r/component failed/, fn ->
      ExLisp.ASDF.load_system(system, dir)
    end

    system = %{system | components: [{:file, "broken-syntax", []}]}

    assert_raise SyntaxError, fn ->
      ExLisp.ASDF.load_system(system, dir)
    end
  end

  test "ASDF restores the current package after a failed load" do
    dir =
      Path.join(System.tmp_dir!(), "exlisp-asdf-package-#{System.unique_integer([:positive])}")

    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf!(dir) end)
    File.write!(Path.join(dir, "broken.lisp"), "(in-package :broken) (error \"stop\")")
    ExLisp.Package.make_package("BROKEN")
    previous = ExLisp.Package.current_package()

    assert_raise RuntimeError, fn ->
      ExLisp.ASDF.load_system(
        %{name: "BROKEN", pathname: nil, components: [{:file, "broken", []}]},
        dir
      )
    end

    assert ExLisp.Package.current_package() == previous
  end

  test "reader syntax: block comments, vectors, reader conditionals, uninterned symbols" do
    # Nested block comments #| ... |#
    assert ExLisp.eval("#| block comment |# (+ 1 2)") == 3
    assert ExLisp.eval("(+ 1 #| outer #| inner |# outer |# 2)") == 3

    # Vector literal #( ... )
    assert ExLisp.eval("(vectorp #(1 2 3))") == :t
    assert ExLisp.eval("(svref #(10 20 30) 1)") == 20

    # Reader conditionals #+ and #-
    assert ExLisp.eval("#+exlisp 42 #-exlisp 99") == 42
    assert ExLisp.eval("#-exlisp 99 #+exlisp 100") == 100
    assert ExLisp.eval("#+(or sbcl exlisp) 123") == 123
    assert ExLisp.eval("#-(and (not exlisp) sbcl) 456") == 456
    assert ExLisp.eval("#+sbcl 99 #-sbcl 77") == 77
    assert ExLisp.eval("#+threads 55") == 55

    # Uninterned symbol #:
    assert ExLisp.eval("(symbolp '#:temp-var)") == :t
    assert ExLisp.eval("(symbol-name '#:temp-var)") == "TEMP-VAR"
  end

  test "special forms: typecase, etypecase, check-type" do
    assert ExLisp.eval("(typecase 42 (string :str) (integer :int) (t :other))") == :int
    assert ExLisp.eval("(typecase \"hello\" (number :num) (string :str))") == :str
    assert ExLisp.eval("(typecase #(1 2) (vector :vec) (t :other))") == :vec
    assert ExLisp.eval("(etypecase 10 (integer :ok))") == :ok
    assert ExLisp.eval("(check-type 10 integer)") == nil
  end

  test "special forms: push, pop, incf, decf" do
    assert ExLisp.eval("(let ((x '(2 3))) (push 1 x) x)") == [1, 2, 3]
    assert ExLisp.eval("(let ((x '(1 2 3))) (values (pop x) x))") == 1
    assert ExLisp.eval("(let ((x 5)) (incf x) x)") == 6
    assert ExLisp.eval("(let ((x 5)) (incf x 3) x)") == 8
    assert ExLisp.eval("(let ((x 5)) (decf x 2) x)") == 3
  end

  test "Quicklisp loading and using alexandria and split-sequence" do
    # Load alexandria
    assert ExLisp.eval("(ql:quickload :alexandria)") != nil

    # Verify alexandria functions
    assert ExLisp.eval("(clamp 5 0 10)") == 5
    assert ExLisp.eval("(clamp -5 0 10)") == 0
    assert ExLisp.eval("(clamp 15 0 10)") == 10

    # ASDF query functions
    assert ExLisp.eval("(asdf:system-source-directory :alexandria)") != nil

    # Load split-sequence
    assert ExLisp.eval("(ql:quickload :split-sequence)") != nil

    # Verify split-sequence
    assert ExLisp.eval("(split-sequence #\\Space \"hello world foo bar\")") == [
             "hello",
             "world",
             "foo",
             "bar"
           ]

    # Load anaphora
    assert ExLisp.eval("(ql:quickload :anaphora)") != nil
    assert ExLisp.eval("(anaphora:aif (+ 1 2) (+ it 10) 0)") == 13
    assert ExLisp.eval("(anaphora:awhen (+ 2 3) (+ it 5))") == 10

    # Load trivial-types
    assert ExLisp.eval("(ql:quickload :trivial-types)") != nil
    assert ExLisp.eval("(typep \"hello\" 'trivial-types:string-designator)") == :t

    # Quicklisp utilities
    assert is_list(ExLisp.eval("(ql:system-apropos \"alexandria\")"))
    assert ExLisp.eval("(ql:where-is-system :alexandria)") != nil
  end
end
