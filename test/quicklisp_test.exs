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

  test "ASDF infers secondary systems from package-inferred definitions" do
    dir =
      Path.join(System.tmp_dir!(), "exlisp-asdf-inferred-#{System.unique_integer([:positive])}")

    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf!(dir) end)

    File.write!(
      Path.join(dir, "demo.asd"),
      """
      (defsystem :demo
        :class :package-inferred-system
        :depends-on (:demo/main))
      """
    )

    File.write!(
      Path.join(dir, "main.lisp"),
      """
      (uiop:define-package :demo
        (:use :cl)
        (:use-reexport :demo/helpers)
        (:import-from :alexandria :clamp)
        (:export :run))
      """
    )

    File.write!(Path.join(dir, "helpers.lisp"), "(defpackage :demo/helpers (:use :cl))")

    systems = ExLisp.ASDF.parse_asd(Path.join(dir, "demo.asd"))

    assert systems["demo/main"].depends_on == ["demo/helpers", "alexandria"]
    assert systems["demo/main"].components == [{:file, "main", []}]
    assert systems["demo/helpers"].components == [{:file, "helpers", []}]
  end

  test "ASDF orders components by explicit and serial dependencies" do
    explicit_system = %{
      components: [
        {:file, "runtime", ["support"]},
        {:file, "support", []},
        {:module, "module-a",
         [
           {:file, "first", []},
           {:file, "second", ["first"]}
         ], []}
      ],
      serial: false,
      pathname: "src"
    }

    assert ExLisp.ASDF.get_load_order(explicit_system) == [
             "src/support.lisp",
             "src/runtime.lisp",
             "src/module-a/first.lisp",
             "src/module-a/second.lisp"
           ]

    serial_system = %{
      components: [{:file, "first", []}, {:file, "second", []}],
      serial: true
    }

    assert ExLisp.ASDF.get_load_order(serial_system) == ["first.lisp", "second.lisp"]
  end

  test "ASDF detects component dependency cycles" do
    system = %{
      components: [{:file, "a", ["b"]}, {:file, "b", ["a"]}],
      serial: false,
      pathname: nil
    }

    assert_raise RuntimeError, ~r/dependency cycle/, fn ->
      ExLisp.ASDF.get_load_order(system)
    end
  end

  test "ASDF evaluates macros that generate secondary systems" do
    dir =
      Path.join(System.tmp_dir!(), "exlisp-asdf-generated-#{System.unique_integer([:positive])}")

    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf!(dir) end)

    asd = Path.join(dir, "generated.asd")

    File.write!(
      asd,
      """
      (defmacro define-generated-systems (kind path &rest components)
        `(progn
           ,@(mapcar (lambda (component)
                       `(defsystem ,(format nil "~a/~a/~a" "generated" kind component)
                          :pathname ,path
                          :components ((:file ,component))))
                     components)))
      (define-generated-systems "impl" #p"src/" "one" "two")
      """
    )

    systems = ExLisp.ASDF.parse_asd(asd)

    assert systems["generated/impl/one"].pathname == "src"
    assert systems["generated/impl/one"].components == [{:file, "one", []}]
    assert systems["generated/impl/two"].components == [{:file, "two", []}]
  end

  test "source loading evaluates read-time forms in source order" do
    path =
      Path.join(
        System.tmp_dir!(),
        "exlisp-read-time-#{System.unique_integer([:positive])}.lisp"
      )

    on_exit(fn -> File.rm(path) end)
    File.write!(path, "(defparameter *load-order-value* 42)\n#.*load-order-value*")

    assert ExLisp.load_file(path) == 42
  end

  test "reader keeps single-escaped delimiters inside symbols" do
    source = "(let ((\\(-pos 1) (\\)-pos 2)) (+ \\(-pos \\)-pos))"
    assert ExLisp.Reader.split_expressions(source) == [source]
    assert ExLisp.eval(source) == 3
  end

  test "reader syntax: block comments, vectors, reader conditionals, uninterned symbols" do
    # Nested block comments #| ... |#
    assert ExLisp.eval("#| block comment |# (+ 1 2)") == 3
    assert ExLisp.eval("(+ 1 #| outer #| inner |# outer |# 2)") == 3

    # Vector literal #( ... )
    assert ExLisp.eval("(vectorp #(1 2 3))") == :t
    assert ExLisp.eval("(svref #(10 20 30) 1)") == 20

    assert ExLisp.eval("(list (aref #32@(#x1 #x2) 0) (aref #32@(#x1 #x2) 1))") ==
             [1, 2]

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
