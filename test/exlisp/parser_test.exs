defmodule ExLisp.ParserTest do
  use ExUnit.Case, async: true
  alias ExLisp.Parser

  describe "check_delimiters/1" do
    test "balanced single line expressions" do
      assert Parser.check_delimiters("(+ 1 2)") == :complete
      assert Parser.check_delimiters("42") == :complete
      assert Parser.check_delimiters(~s{"hello (world)"}) == :complete
      assert Parser.check_delimiters("[:a 1 (:b 2)]") == :complete
      assert Parser.check_delimiters("{:a 1 :b 2}") == :complete
    end

    test "incomplete expressions" do
      assert Parser.check_delimiters("(+ 1") == {:incomplete, 1}
      assert Parser.check_delimiters("(* (+ 1 2)") == {:incomplete, 1}
      assert Parser.check_delimiters(~s{"unclosed string}) == {:incomplete, :in_string}
    end

    test "empty / whitespace input" do
      assert Parser.check_delimiters("") == :empty
      assert Parser.check_delimiters("   \n\t  ") == :empty
    end

    test "mismatched or unexpected delimiters" do
      assert {:error, _} = Parser.check_delimiters(")")
      assert {:error, _} = Parser.check_delimiters("(+ 1 2))")
      assert {:error, _} = Parser.check_delimiters("(}")
      assert {:error, _} = Parser.check_delimiters("[)")
    end

    test "expressions with comments" do
      assert Parser.check_delimiters("(+ 1 ; comment\n 2)") == :complete
      assert Parser.check_delimiters("42 ; comment") == :complete
    end
  end

  describe "parse/3" do
    test "returns ok tuple for complete expression" do
      assert {:ok, expr, {"", :other}} = Parser.parse("(+ 1 2)\n", [], "")
      assert Macro.to_string(expr) == "ExLisp.eval_repl(\"(+ 1 2)\")"
    end

    test "returns ok tuple for :io:read call expression" do
      assert {:ok, expr, {"", :other}} = Parser.parse(":io:read \">> \"\n", [], "")
      assert Macro.to_string(expr) == ~s{ExLisp.eval_repl(":io:read \\">> \\"")}
    end

    test "returns ok tuple for parenthesized (:io:read ...) call" do
      assert {:ok, expr, {"", :other}} = Parser.parse("(:io:read \">> \")\n", [], "")
      assert Macro.to_string(expr) == ~s{ExLisp.eval_repl("(:io:read \\">> \\")")}
    end

    test "returns incomplete for open parenthesis across multiline input" do
      assert {:incomplete, {"(+ 1\n", :other}} = Parser.parse("(+ 1\n", [], "")
      assert {:ok, expr, {"", :other}} = Parser.parse("   2)\n", [], {"(+ 1\n", :other})
      assert Macro.to_string(expr) == "ExLisp.eval_repl(\"(+ 1\\n   2)\")"
    end

    test "returns dont_display_result for empty input" do
      assert {:ok, expr, {"", :other}} = Parser.parse("\n", [], "")
      assert Macro.to_string(expr) == "IEx.dont_display_result()"
    end

    test "raises SyntaxError for unexpected delimiter" do
      assert_raise SyntaxError, ~r/unexpected delimiter \)/, fn ->
        Parser.parse(")\n", [], "")
      end
    end
  end
end
