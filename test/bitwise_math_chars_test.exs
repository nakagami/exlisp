defmodule BitwiseMathCharsTest do
  use ExUnit.Case

  test "boole operations and constants" do
    assert ExLisp.eval("(boole boole-and 5 3)") == 1
    assert ExLisp.eval("(boole boole-ior 5 3)") == 7
    assert ExLisp.eval("(boole boole-xor 5 3)") == 6
    assert ExLisp.eval("(boole boole-clr 5 3)") == 0
    assert ExLisp.eval("(boole boole-set 5 3)") == -1
    assert ExLisp.eval("(boole boole-1 5 3)") == 5
    assert ExLisp.eval("(boole boole-2 5 3)") == 3
    assert ExLisp.eval("(boole boole-c1 5 3)") == -6
    assert ExLisp.eval("(boole boole-c2 5 3)") == -4
    assert ExLisp.eval("(boole boole-andc1 5 3)") == 2
    assert ExLisp.eval("(boole boole-andc2 5 3)") == 4
    assert ExLisp.eval("(boole boole-orc1 5 3)") == -5
    assert ExLisp.eval("(boole boole-orc2 5 3)") == -3
    assert ExLisp.eval("(boole boole-nand 5 3)") == -2
    assert ExLisp.eval("(boole boole-nor 5 3)") == -8
    assert ExLisp.eval("(boole boole-eqv 5 3)") == -7
  end

  test "logtest" do
    assert ExLisp.eval("(logtest 2 6)") == :t
    assert ExLisp.eval("(logtest 1 6)") == nil
    assert ExLisp.eval("(logtest 0 10)") == nil
  end

  test "pi constant" do
    pi_val = ExLisp.eval("pi")
    assert is_float(pi_val)
    assert_in_delta pi_val, 3.141592653589793, 0.00001
  end

  test "fixnum constants" do
    assert ExLisp.eval("most-positive-fixnum") == 4_611_686_018_427_387_903
    assert ExLisp.eval("most-negative-fixnum") == -4_611_686_018_427_387_904
    assert ExLisp.eval("(typep most-positive-fixnum 'fixnum)") == :t
    assert ExLisp.eval("(typep most-negative-fixnum 'fixnum)") == :t
    assert ExLisp.eval("(typep (+ most-positive-fixnum 1) 'bignum)") == :t
    assert ExLisp.eval("(typep (- most-negative-fixnum 1) 'bignum)") == :t
    assert ExLisp.eval("(typep (+ most-positive-fixnum 1) 'fixnum)") == nil
    assert ExLisp.eval("(typep (- most-negative-fixnum 1) 'fixnum)") == nil
  end

  test "signum" do
    assert ExLisp.eval("(signum -42)") == -1
    assert ExLisp.eval("(signum 0)") == 0
    assert ExLisp.eval("(signum 100)") == 1
    assert ExLisp.eval("(signum -3.14)") == -1.0
    assert ExLisp.eval("(signum 0.0)") == 0.0
    assert ExLisp.eval("(signum 5.5)") == 1.0
  end

  test "random and make-random-state" do
    r = ExLisp.eval("(random 10)")
    assert is_integer(r) and r >= 0 and r < 10

    rf = ExLisp.eval("(random 5.0)")
    assert is_float(rf) and rf >= 0.0 and rf < 5.0

    state = ExLisp.eval("(make-random-state)")
    assert state != nil
  end

  test "make-string" do
    assert ExLisp.eval("(make-string 5)") == "     "
    assert ExLisp.eval("(make-string 3 :initial-element #\\a)") == "aaa"
    assert ExLisp.eval("(make-string 4 :initial-element #\\*)") == "****"
  end

  test "char-name and name-char" do
    assert ExLisp.eval("(char-name #\\Space)") == "Space"
    assert ExLisp.eval("(char-name #\\Newline)") == "Newline"
    assert ExLisp.eval("(char-name #\\Tab)") == "Tab"
    assert ExLisp.eval("(char-name #\\a)") == nil

    assert ExLisp.eval("(name-char \"Space\")") == ?\s
    assert ExLisp.eval("(name-char \"newline\")") == ?\n
    assert ExLisp.eval("(name-char \"TAB\")") == ?\t
    assert ExLisp.eval("(name-char \"unknown\")") == nil
  end

  test "digit-char" do
    assert ExLisp.eval("(digit-char 7)") == ?7
    assert ExLisp.eval("(digit-char 12 16)") == ?C
    assert ExLisp.eval("(digit-char 10 10)") == nil
    assert ExLisp.eval("(digit-char 35 36)") == ?Z
    assert ExLisp.eval("(digit-char 36 36)") == nil
  end

  test "char-int and int-char" do
    assert ExLisp.eval("(char-int #\\A)") == 65
    assert ExLisp.eval("(int-char 65)") == ?A
    assert ExLisp.eval("(int-char (char-int #\\z))") == ?z
  end

  test "realp predicate" do
    assert ExLisp.eval("(realp 42)") == :t
    assert ExLisp.eval("(realp 3.14)") == :t
    assert ExLisp.eval("(realp 1/3)") == :t
    assert ExLisp.eval("(realp #c(1 2))") == nil
    assert ExLisp.eval("(realp \"abc\")") == nil
    assert ExLisp.eval("(realp 'sym)") == nil
  end

  test "parse-integer" do
    assert ExLisp.eval("(parse-integer \"123\")") == 123
    assert ExLisp.eval("(multiple-value-list (parse-integer \"  -456  \"))") == [-456, 8]
    assert ExLisp.eval("(multiple-value-list (parse-integer \"10110\" :radix 2))") == [22, 5]
    assert ExLisp.eval("(multiple-value-list (parse-integer \"ff\" :radix 16))") == [255, 2]

    assert ExLisp.eval("(multiple-value-list (parse-integer \"123abc\" :junk-allowed t))") == [
             123,
             3
           ]
  end

  test "bitwise operations with multiple arguments" do
    assert ExLisp.eval("(logand 1 3 7 15)") == 1
    assert ExLisp.eval("(logior 1 2 4 8)") == 15
    assert ExLisp.eval("(logxor 1 2 3)") == 0
    assert ExLisp.eval("(logeqv -1 -1 -1)") == -1
    assert ExLisp.eval("(logcount 15)") == 4
    assert ExLisp.eval("(logbitp 2 4)") == :t
    assert ExLisp.eval("(logbitp 1 4)") == nil
  end
end
