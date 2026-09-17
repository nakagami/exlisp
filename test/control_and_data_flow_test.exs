defmodule ExLisp.ControlAndDataFlowTest do
  use ExUnit.Case, async: false

  test "destructuring-bind with nested lists and patterns" do
    assert ExLisp.eval("(destructuring-bind (a b c) '(1 2 3) (+ a b c))") == 6

    assert ExLisp.eval("(destructuring-bind (a (b c) d) '(1 (2 3) 4) (list a b c d))") == [
             1,
             2,
             3,
             4
           ]
  end

  test "multiple values: multiple-value-bind, multiple-value-list, multiple-value-setq, nth-value, multiple-value-prog1" do
    assert ExLisp.eval("(multiple-value-bind (x y z) (values 1 2 3) (list x y z))") == [1, 2, 3]
    assert ExLisp.eval("(multiple-value-bind (x y) 42 (list x y))") == [42, nil]

    assert ExLisp.eval("(multiple-value-list (values 'a 'b 'c))") == [:a, :b, :c]
    assert ExLisp.eval("(multiple-value-list 10)") == [10]

    code_mv_setq = """
    (let (x y)
      (multiple-value-setq (x y) (values 100 200))
      (list x y))
    """

    assert ExLisp.eval(code_mv_setq) == [100, 200]

    assert ExLisp.eval("(nth-value 0 (values 10 20 30))") == 10
    assert ExLisp.eval("(nth-value 1 (values 10 20 30))") == 20
    assert ExLisp.eval("(nth-value 2 (values 10 20 30))") == 30

    assert ExLisp.eval("(multiple-value-list (multiple-value-prog1 (values 1 2) (+ 10 20)))") == [
             1,
             2
           ]

    assert ExLisp.eval("(multiple-value-prog1 (values 1 2) (+ 10 20))") == 1
  end

  test "catch and throw" do
    code_catch = """
    (catch 'done
      (let ((x 1))
        (throw 'done 42)
        999))
    """

    assert ExLisp.eval(code_catch) == 42

    code_nested_catch = """
    (catch 'outer
      (catch 'inner
        (throw 'outer :escaped)
        :inner-result)
      :outer-fallback)
    """

    assert ExLisp.eval(code_nested_catch) == :escaped
  end

  test "progv dynamic binding" do
    ExLisp.eval("(defparameter *test-dyn-var* 10)")

    code_progv = """
    (progv '(*test-dyn-var*) '(99)
      *test-dyn-var*)
    """

    assert ExLisp.eval(code_progv) == 99
    assert ExLisp.eval("*test-dyn-var*") == 10
  end

  test "psetq, psetf, rotatef, shiftf" do
    code_psetq = """
    (let ((a 1) (b 2))
      (psetq a b b a)
      (list a b))
    """

    assert ExLisp.eval(code_psetq) == [2, 1]

    code_rotatef = """
    (let ((a 1) (b 2) (c 3))
      (rotatef a b c)
      (list a b c))
    """

    assert ExLisp.eval(code_rotatef) == [2, 3, 1]

    code_shiftf = """
    (let ((a 1) (b 2) (c 3))
      (let ((old (shiftf a b c 99)))
        (list old a b c)))
    """

    assert ExLisp.eval(code_shiftf) == [1, 2, 3, 99]
  end

  test "symbol-function, fdefinition, fmakunbound, makunbound, boundp, fboundp" do
    ExLisp.eval("(defun test-dyn-fun (x) (* x 3))")
    assert ExLisp.eval("(fboundp 'test-dyn-fun)") == :t
    assert ExLisp.eval("(funcall (symbol-function 'test-dyn-fun) 4)") == 12

    ExLisp.eval("(setf (symbol-function 'test-alias) (symbol-function 'test-dyn-fun))")
    assert ExLisp.eval("(test-alias 5)") == 15

    ExLisp.eval("(fmakunbound 'test-dyn-fun)")
    assert ExLisp.eval("(fboundp 'test-dyn-fun)") == nil

    ExLisp.eval("(defparameter *dyn-b* 55)")
    assert ExLisp.eval("(boundp '*dyn-b*)") == :t
    ExLisp.eval("(makunbound '*dyn-b*)")
    assert ExLisp.eval("(boundp '*dyn-b*)") == nil
  end
end
