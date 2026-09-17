defmodule QuicklispTest do
  use ExUnit.Case
  @moduletag timeout: 180_000

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

    # Load split-sequence
    assert ExLisp.eval("(ql:quickload :split-sequence)") != nil

    # Verify split-sequence
    assert ExLisp.eval("(split-sequence #\\Space \"hello world foo bar\")") == [
             "hello",
             "world",
             "foo",
             "bar"
           ]
  end
end
