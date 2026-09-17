defmodule ExLisp.LispParserTest do
  use ExUnit.Case, async: true
  alias ExLisp.LispParser

  describe "tokenize/1" do
    test "tokenizes integer and float numbers" do
      assert {:ok, [{:int, 1, 42}]} = LispParser.tokenize("42")
      assert {:ok, [{:int, 1, -10}]} = LispParser.tokenize("-10")
      assert {:ok, [{:int, 1, 10}]} = LispParser.tokenize("+10")
      assert {:ok, [{:float, 1, 3.14}]} = LispParser.tokenize("3.14")
      assert {:ok, [{:float, 1, -2.5}]} = LispParser.tokenize("-2.5")
    end

    test "tokenizes radix integers (#b, #o, #x)" do
      assert {:ok, [{:int, 1, 5}]} = LispParser.tokenize("#b101")
      assert {:ok, [{:int, 1, 5}]} = LispParser.tokenize("+#b101")
      assert {:ok, [{:int, 1, -5}]} = LispParser.tokenize("-#b101")
      assert {:ok, [{:int, 1, 63}]} = LispParser.tokenize("#o77")
      assert {:ok, [{:int, 1, 31}]} = LispParser.tokenize("#x1f")
      assert {:ok, [{:int, 1, 255}]} = LispParser.tokenize("#xFF")
    end

    test "tokenizes character literals (#\\...)" do
      assert {:ok, [{:char, 1, ?a}]} = LispParser.tokenize("#\\a")
      assert {:ok, [{:char, 1, ?\n}]} = LispParser.tokenize("#\\Newline")
      assert {:ok, [{:char, 1, ?\s}]} = LispParser.tokenize("#\\Space")
      assert {:ok, [{:char, 1, ?\t}]} = LispParser.tokenize("#\\Tab")
    end

    test "tokenizes string literals with escapes" do
      assert {:ok, [{:string, 1, "hello world"}]} = LispParser.tokenize(~s{"hello world"})

      assert {:ok, [{:string, 1, "hello\n\"world\""}]} =
               LispParser.tokenize(~s{"hello\\n\\"world\\""})
    end

    test "tokenizes keywords and symbols" do
      assert {:ok, [{:keyword, 1, :foo}]} = LispParser.tokenize(":foo")
      assert {:ok, [{:keyword, 1, :my_key}]} = LispParser.tokenize(":my-key")
      assert {:ok, [{:symbol, 1, "my_var"}]} = LispParser.tokenize("my-var")
      assert {:ok, [{:symbol, 1, "+"}]} = LispParser.tokenize("+")
      assert {:ok, [{:symbol, 1, "-"}]} = LispParser.tokenize("-")
      assert {:ok, [{:symbol, 1, "1+"}]} = LispParser.tokenize("1+")
      assert {:ok, [{:symbol, 1, "1-"}]} = LispParser.tokenize("1-")
      assert {:ok, [{:symbol, 1, "string="}]} = LispParser.tokenize("string=")
      assert {:ok, [{:symbol, 1, "string/="}]} = LispParser.tokenize("string/=")
      assert {:ok, [{:symbol, 1, "+my_const+"}]} = LispParser.tokenize("+my-const+")
      assert {:ok, [{:symbol, 1, "*loop_i*"}]} = LispParser.tokenize("*loop_i*")
    end

    test "tokenizes remote module calls" do
      assert {:ok, [{:id, 1, ["math", "sqrt"]}]} = LispParser.tokenize(":math:sqrt")
      assert {:ok, [{:id, 1, ["io", "read"]}]} = LispParser.tokenize(":io:read")
      assert {:ok, [{:id, 1, ["String", "upcase"]}]} = LispParser.tokenize("String.upcase")
      assert {:ok, [{:id, 1, ["IO", "puts"]}]} = LispParser.tokenize("IO.puts")
    end

    test "tokenizes nil and t" do
      assert {:ok, [{nil, 1}]} = LispParser.tokenize("nil")
      assert {:ok, [{nil, 1}]} = LispParser.tokenize("NIL")
      assert {:ok, [{:t, 1}]} = LispParser.tokenize("t")
      assert {:ok, [{:t, 1}]} = LispParser.tokenize("T")
    end

    test "tokenizes parentheses, brackets, and quotes" do
      assert {:ok, [{:lparen, 1}, {:symbol, 1, "+"}, {:int, 1, 1}, {:int, 1, 2}, {:rparen, 1}]} =
               LispParser.tokenize("(+ 1 2)")

      assert {:ok, [{:quote, 1}, {:lparen, 1}, {:int, 1, 1}, {:rparen, 1}]} =
               LispParser.tokenize("'(1)")

      assert {:ok, [{:func_quote, 1}, {:symbol, 1, "+"}]} =
               LispParser.tokenize("#'+")

      assert {:ok, [{:lbracket, 1}, {:int, 1, 1}, {:int, 1, 2}, {:rbracket, 1}]} =
               LispParser.tokenize("[1 2]")
    end

    test "skips comments" do
      assert {:ok, [{:int, 1, 1}, {:int, 2, 2}]} =
               LispParser.tokenize("1 ; this is a comment\n2")
    end
  end

  describe "parse/1" do
    test "parses scalar values" do
      assert {:ok, {:lit, 42}} = LispParser.parse("42")
      assert {:ok, {:lit, 3.14}} = LispParser.parse("3.14")
      assert {:ok, {:lit, "hello"}} = LispParser.parse(~s{"hello"})
      assert {:ok, {:lit, :foo}} = LispParser.parse(":foo")
      assert {:ok, {:lit, nil}} = LispParser.parse("nil")
      assert {:ok, {:lit, :t}} = LispParser.parse("t")
      assert {:ok, {:id, 1, ["x"]}} = LispParser.parse("x")
    end

    test "parses empty input as nil" do
      assert {:ok, {:lit, nil}} = LispParser.parse("")
      assert {:ok, {:lit, nil}} = LispParser.parse("   \n\t  ")
    end

    test "parses basic S-expressions" do
      assert {:ok, {:list, 1, [{:id, 1, ["+"]}, {:lit, 1}, {:lit, 2}]}} =
               LispParser.parse("(+ 1 2)")

      assert {:ok,
              {:list, 1,
               [{:id, 1, ["*"]}, {:list, 1, [{:id, 1, ["+"]}, {:lit, 1}, {:lit, 2}]}, {:lit, 3}]}} =
               LispParser.parse("(* (+ 1 2) 3)")
    end

    test "parses quote and function quote expressions" do
      assert {:ok, {:list, 1, [{:id, 1, ["quote"]}, {:list, 1, [{:lit, 1}, {:lit, 2}]}]}} =
               LispParser.parse("'(1 2)")

      assert {:ok, {:list, 1, [{:id, 1, ["function"]}, {:id, 1, ["+"]}]}} =
               LispParser.parse("#'+")
    end

    test "parses bracketed vectors / quoted lists" do
      assert {:ok, {:quoted, 1, [{:lit, 1}, {:lit, 2}, {:lit, 3}]}} =
               LispParser.parse("[1 2 3]")
    end

    test "parses unparenthesized top-level function calls" do
      assert {:ok, {:list, 1, [{:id, 1, ["math", "sqrt"]}, {:lit, 16}]}} =
               LispParser.parse(":math:sqrt 16")

      assert {:ok, {:list, 1, [{:id, 1, ["String", "upcase"]}, {:lit, "hello"}]}} =
               LispParser.parse(~s{String.upcase "hello"})
    end

    test "returns error on syntax errors" do
      assert {:error, _reason} = LispParser.parse("(")
      assert {:error, _reason} = LispParser.parse(")")
      assert {:error, _reason} = LispParser.parse(~s{"unclosed string})
      assert {:error, _reason} = LispParser.parse("(+ 1 2]")
    end
  end
end
