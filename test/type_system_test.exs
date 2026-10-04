defmodule TypeSystemTest do
  use ExUnit.Case

  describe "Type System - Primitive & Compound Types" do
    test "typep with primitives" do
      assert ExLisp.eval("(typep 42 'integer)") == :t
      assert ExLisp.eval("(typep 42 'fixnum)") == :t
      assert ExLisp.eval("(typep 42 'number)") == :t
      assert ExLisp.eval("(typep 42 'real)") == :t
      assert ExLisp.eval("(typep 42 'rational)") == :t
      assert ExLisp.eval("(typep 42 'float)") == nil

      assert ExLisp.eval("(typep 3.14 'float)") == :t
      assert ExLisp.eval("(typep 3.14 'real)") == :t
      assert ExLisp.eval("(typep 3.14 'number)") == :t
      assert ExLisp.eval("(typep 3.14 'integer)") == nil

      assert ExLisp.eval("(typep #\\a 'character)") == :t
      assert ExLisp.eval("(typep #\\a 'base-char)") == :t
      assert ExLisp.eval("(typep #\\a 'standard-char)") == :t

      assert ExLisp.eval("(typep \"hello\" 'string)") == :t
      assert ExLisp.eval("(typep \"hello\" 'simple-string)") == :t
      assert ExLisp.eval("(typep \"hello\" 'vector)") == :t
      assert ExLisp.eval("(typep \"hello\" 'array)") == :t
      assert ExLisp.eval("(typep \"hello\" 'sequence)") == :t

      assert ExLisp.eval("(typep '(1 2 3) 'list)") == :t
      assert ExLisp.eval("(typep '(1 2 3) 'cons)") == :t
      assert ExLisp.eval("(typep '(1 2 3) 'sequence)") == :t
      assert ExLisp.eval("(typep nil 'null)") == :t
      assert ExLisp.eval("(typep nil 'list)") == :t
      assert ExLisp.eval("(typep nil 'cons)") == nil
      assert ExLisp.eval("(typep nil 'boolean)") == :t
      assert ExLisp.eval("(typep t 'boolean)") == :t
    end

    test "typep with compound types (and, or, not, member, eql, satisfies)" do
      assert ExLisp.eval("(typep 5 '(and integer (satisfies plusp)))") == :t
      assert ExLisp.eval("(typep -5 '(and integer (satisfies plusp)))") == nil

      assert ExLisp.eval("(typep 42 '(or string integer))") == :t
      assert ExLisp.eval("(typep \"hi\" '(or string integer))") == :t
      assert ExLisp.eval("(typep :foo '(or string integer))") == nil

      assert ExLisp.eval("(typep 42 '(not string))") == :t
      assert ExLisp.eval("(typep \"hi\" '(not string))") == nil

      assert ExLisp.eval("(typep :b '(member :a :b :c))") == :t
      assert ExLisp.eval("(typep :d '(member :a :b :c))") == nil

      assert ExLisp.eval("(typep 100 '(eql 100))") == :t
      assert ExLisp.eval("(typep 100 '(eql 200))") == nil
    end

    test "typep with numeric intervals and mod" do
      assert ExLisp.eval("(typep 5 '(integer 0 10))") == :t
      assert ExLisp.eval("(typep 0 '(integer 0 10))") == :t
      assert ExLisp.eval("(typep 10 '(integer 0 10))") == :t
      assert ExLisp.eval("(typep -1 '(integer 0 10))") == nil
      assert ExLisp.eval("(typep 11 '(integer 0 10))") == nil

      # Exclusive bounds
      assert ExLisp.eval("(typep 0 '(integer (0) 10))") == nil
      assert ExLisp.eval("(typep 1 '(integer (0) 10))") == :t
      assert ExLisp.eval("(typep 10 '(integer 0 (10)))") == nil
      assert ExLisp.eval("(typep 9 '(integer 0 (10)))") == :t

      # mod type
      assert ExLisp.eval("(typep 0 '(mod 5))") == :t
      assert ExLisp.eval("(typep 4 '(mod 5))") == :t
      assert ExLisp.eval("(typep 5 '(mod 5))") == nil
      assert ExLisp.eval("(typep -1 '(mod 5))") == nil

      # signed-byte & unsigned-byte
      assert ExLisp.eval("(typep 255 '(unsigned-byte 8))") == :t
      assert ExLisp.eval("(typep 256 '(unsigned-byte 8))") == nil
      assert ExLisp.eval("(typep 127 '(signed-byte 8))") == :t
      assert ExLisp.eval("(typep -128 '(signed-byte 8))") == :t
      assert ExLisp.eval("(typep 128 '(signed-byte 8))") == nil
      assert ExLisp.eval("(typep -129 '(signed-byte 8))") == nil
    end

    test "typep with compound string, vector, and cons types" do
      assert ExLisp.eval("(typep \"abc\" '(string 3))") == :t
      assert ExLisp.eval("(typep \"abc\" '(string 4))") == nil
      assert ExLisp.eval("(typep '(1 . 2) '(cons integer integer))") == :t
    end
  end

  describe "deftype and Type Expansion" do
    test "defining simple deftype" do
      ExLisp.eval("""
      (deftype natural () '(integer 0 *))
      """)

      assert ExLisp.eval("(typep 0 'natural)") == :t
      assert ExLisp.eval("(typep 100 'natural)") == :t
      assert ExLisp.eval("(typep -1 'natural)") == nil
    end

    test "defining parameterized deftype" do
      ExLisp.eval("""
      (deftype square-matrix (elem-type n)
        `(simple-array ,elem-type (,n ,n)))
      """)

      ExLisp.eval("""
      (deftype non-empty-list ()
        '(cons t t))
      """)

      assert ExLisp.eval("(typep '(1 2 3) 'non-empty-list)") == :t
      assert ExLisp.eval("(typep nil 'non-empty-list)") == nil
    end
  end

  describe "check-type and the" do
    test "check-type macro passes on valid type" do
      code = """
      (let ((x 10))
        (check-type x integer)
        x)
      """
      assert ExLisp.eval(code) == 10
    end

    test "check-type raises error on invalid type" do
      code = """
      (let ((x "not an integer"))
        (check-type x integer)
        x)
      """
      assert_raise RuntimeError, fn ->
        ExLisp.eval(code)
      end
    end

    test "the form returns value on matching type" do
      assert ExLisp.eval("(the integer (+ 1 2))") == 3
      assert ExLisp.eval("(the string \"hello\")") == "hello"
      assert ExLisp.eval("(the function #'cons)") == :cons
      assert ExLisp.eval("(the (simple-base-string 5) \"hello\")") == "hello"
      assert ExLisp.eval("(the (simple-bit-vector 5) (make-array 5 :element-type 'bit :initial-contents '(0 0 1 1 0)))") != nil
    end

    test "the form raises error on mismatched type" do
      assert_raise RuntimeError, fn ->
        ExLisp.eval("(the integer \"not int\")")
      end
    end
  end

  describe "typecase, etypecase, subtypep" do
    test "typecase branches correctly" do
      code = """
      (defun classify (x)
        (typecase x
          (integer :int)
          (string :str)
          (cons :list)
          (otherwise :other)))
      """
      ExLisp.eval(code)

      assert ExLisp.eval("(classify 42)") == :int
      assert ExLisp.eval("(classify \"hi\")") == :str
      assert ExLisp.eval("(classify '(1 2))") == :list
      assert ExLisp.eval("(classify :foo)") == :other
    end

    test "etypecase raises on no match" do
      code = """
      (etypecase :foo
        (integer :int)
        (string :str))
      """
      assert_raise RuntimeError, fn ->
        ExLisp.eval(code)
      end
    end

    test "subtypep" do
      assert ExLisp.eval("(subtypep 'fixnum 'integer)") == :t
      assert ExLisp.eval("(subtypep 'integer 'number)") == :t
      assert ExLisp.eval("(subtypep 'string 'sequence)") == :t
      assert ExLisp.eval("(subtypep 'cons 'list)") == :t
      assert ExLisp.eval("(subtypep 'number 'integer)") == nil
    end

    test "upgraded array and complex types" do
      assert ExLisp.eval("(upgraded-array-element-type 'base-char)") == :character
      assert ExLisp.eval("(upgraded-array-element-type 'bit)") == :bit
      assert ExLisp.eval("(upgraded-array-element-type 'integer)") == :t
      assert ExLisp.eval("(upgraded-complex-part-type 'single-float)") == :single_float
    end
  end
end
