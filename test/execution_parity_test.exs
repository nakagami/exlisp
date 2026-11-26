defmodule ExLisp.ExecutionParityTest do
  use ExUnit.Case

  setup do
    ExLisp.Env.reset()
    :ok
  end

  test "interpreter and compiler agree for control flow, closures, and mutations" do
    source = """
    (defmacro twice (form) `(+ ,form ,form))

    (defun parity-control (n)
      (let ((sum 0))
        (dotimes (i n)
          (incf sum i))
        (tagbody
          start
            (when (plusp n)
              (decf n)
              (go start)))
        (list sum
              (twice (+ n 3))
              (funcall (lambda (x) (* x 2)) sum))))
    """

    assert parity_result(source, :parity_control, [5]) ==
             [10, 6, 20]
  end

  test "interpreter and compiler preserve multiple values" do
    source = """
    (defun parity-values (x)
      (multiple-value-bind (a b c)
          (values x (+ x 1) nil)
        (list a b c)))
    """

    assert parity_result(source, :parity_values, [40]) == [40, 41, nil]
  end

  test "interpreter and compiler preserve package-qualified calls" do
    setup_source = """
    (defpackage :parity-package (:use :cl) (:export :increment))
    (in-package :parity-package)
    (defun increment (x) (+ x 1))
    (in-package :common-lisp-user)
    """

    source = """
    (defun parity-package-call (x)
      (parity-package:increment x))
    """

    assert parity_result(source, :parity_package_call, [41], setup_source) == 42
  end

  test "interpreter and compiler expose the same runtime error" do
    source = """
    (defun parity-error (value)
      (1+ (car value)))
    """

    {interpreted, compiled} = parity_errors(source, :parity_error, [nil])

    assert interpreted == compiled
    assert {FunctionClauseError, message} = interpreted
    assert message =~ "add_two"
  end

  test "hot named functions are compiled and invalidated after redefinition" do
    Process.put(:exlisp_jit_threshold, 2)

    ExLisp.eval("(defun parity-hot (x) (* x 3))")
    refute ExLisp.JIT.compiled?(:parity_hot)

    assert ExLisp.call(:parity_hot, [7]) == 21
    assert ExLisp.call(:parity_hot, [8]) == 24
    assert ExLisp.JIT.compiled?(:parity_hot)

    ExLisp.eval("(defun parity-hot (x) (* x 4))")
    refute ExLisp.JIT.compiled?(:parity_hot)

    assert ExLisp.call(:parity_hot, [7]) == 28
    assert ExLisp.call(:parity_hot, [8]) == 32
    assert ExLisp.JIT.compiled?(:parity_hot)
  after
    Process.delete(:exlisp_jit_threshold)
  end

  test "JIT does not replay a compiled function after a runtime error" do
    Process.put(:exlisp_jit_threshold, 2)
    ExLisp.eval("(defparameter *jit-error-count* 0)")

    ExLisp.eval("""
    (defun parity-hot-error ()
      (incf *jit-error-count*)
      (error "jit runtime failure"))
    """)

    assert_raise RuntimeError, "jit runtime failure", fn ->
      ExLisp.call(:parity_hot_error, [])
    end

    assert ExLisp.eval("*jit-error-count*") == 1

    assert_raise RuntimeError, "jit runtime failure", fn ->
      ExLisp.call(:parity_hot_error, [])
    end

    assert ExLisp.eval("*jit-error-count*") == 2
    assert ExLisp.JIT.compiled?(:parity_hot_error)
  after
    Process.delete(:exlisp_jit_threshold)
  end

  test "JIT does not replace a newly installed function with stale AST" do
    Process.put(:exlisp_jit_threshold, 1)
    ExLisp.eval("(defun stale-jit () 1)")
    ExLisp.eval("(setf (symbol-function 'stale-jit) (lambda () 2))")

    assert ExLisp.call(:stale_jit, []) == 2
    refute ExLisp.JIT.compiled?(:stale_jit)
  after
    Process.delete(:exlisp_jit_threshold)
  end

  test "JIT keeps closure-capturing mutated parameters interpreted" do
    Process.put(:exlisp_jit_threshold, 1)
    ExLisp.eval("(defun counter-jit (x) (lambda () (incf x)))")

    first = ExLisp.call(:counter_jit, [0])
    second = ExLisp.call(:counter_jit, [100])

    assert ExLisp.Builtins.invoke_fn(first, []) == 1
    assert ExLisp.Builtins.invoke_fn(second, []) == 101
    assert ExLisp.Builtins.invoke_fn(first, []) == 2
    refute ExLisp.JIT.compiled?(:counter_jit)
  after
    Process.delete(:exlisp_jit_threshold)
  end

  defp parity_result(source, function, args, setup_source \\ "") do
    ExLisp.Env.reset()
    eval_source(setup_source)
    eval_source(source)
    interpreted = ExLisp.call(function, args)

    ExLisp.Env.reset()
    eval_source(setup_source)
    {:ok, module, _binary} = compile_source(source, function)
    compiled = apply(module, function, args)

    assert interpreted == compiled
    interpreted
  end

  defp parity_errors(source, function, args) do
    ExLisp.Env.reset()
    eval_source(source)
    interpreted = capture_error(fn -> ExLisp.call(function, args) end)

    ExLisp.Env.reset()
    {:ok, module, _binary} = compile_source(source, function)
    compiled = capture_error(fn -> apply(module, function, args) end)

    {interpreted, compiled}
  end

  defp compile_source(source, function) do
    module = Module.concat([ExLisp.ExecutionParity, function])
    ExLisp.Compiler.compile_string(source, module: module, execute_top_level: false)
  end

  defp eval_source(source) do
    source
    |> ExLisp.Reader.split_expressions()
    |> Enum.each(&ExLisp.eval/1)
  end

  defp capture_error(fun) do
    try do
      fun.()
      flunk("expected Lisp evaluation to fail")
    rescue
      error -> {error.__struct__, Exception.message(error)}
    end
  end
end
