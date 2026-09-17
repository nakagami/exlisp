defmodule ExLisp.ReaderTest do
  use ExUnit.Case, async: true
  alias ExLisp.Reader

  describe "split_expressions/1" do
    test "splits single expression" do
      assert Reader.split_expressions("(+ 1 2)") == ["(+ 1 2)"]
    end

    test "splits multiple expressions" do
      input = """
      (defparameter x 10)
      (defvar y 20)
      (defun add (a b) (+ a b))
      """

      assert Reader.split_expressions(input) == [
               "(defparameter x 10)",
               "(defvar y 20)",
               "(defun add (a b) (+ a b))"
             ]
    end

    test "handles comments and strings containing parentheses" do
      input = """
      ;; This is a comment with (parens)
      (defparameter greeting "hello (world)") ; another comment
      (defun say_hi () greeting)
      """

      expressions = Reader.split_expressions(input)
      assert length(expressions) == 2
      assert Enum.at(expressions, 0) =~ "defparameter greeting"
      assert Enum.at(expressions, 1) =~ "defun say_hi"
    end
  end
end
