defmodule BuiltinFunctionTest do
  use ExUnit.Case
  doctest BuiltinFunction

  describe "builtins/0" do
    test "returns list of builtin function atoms" do
      builtins = BuiltinFunction.builtins()
      assert :+ in builtins
      assert :- in builtins
      assert :* in builtins
      assert :/ in builtins
      assert :cons in builtins
    end
  end

  describe "lookup/1 and builtin?/1" do
    test "identifies builtin functions from various representations" do
      assert BuiltinFunction.lookup({:id, {1, 1}, ["+"]}) == {:ok, :+}
      assert BuiltinFunction.lookup({:id, {1, 1}, ["cons"]}) == {:ok, :cons}
      assert BuiltinFunction.lookup("+") == {:ok, :+}
      assert BuiltinFunction.lookup("cons") == {:ok, :cons}
      assert BuiltinFunction.lookup(:+) == {:ok, :+}
      assert BuiltinFunction.lookup(:cons) == {:ok, :cons}
      assert BuiltinFunction.lookup({:lit, :+}) == {:ok, :+}
      assert BuiltinFunction.lookup({:lit, :cons}) == {:ok, :cons}

      assert BuiltinFunction.lookup("quit") == {:ok, :quit}
      assert BuiltinFunction.lookup("sb-ext:quit") == {:ok, :quit}
      assert BuiltinFunction.lookup("sb-ext::quit") == {:ok, :quit}
      assert BuiltinFunction.lookup({:id, {1, 1}, ["sb-ext", "quit"]}) == {:ok, :quit}
      assert BuiltinFunction.lookup("exit") == {:ok, :quit}
      assert BuiltinFunction.lookup("sb-ext:exit") == {:ok, :quit}
      assert BuiltinFunction.lookup({:id, {1, 1}, ["sb-ext", "exit"]}) == {:ok, :quit}

      assert BuiltinFunction.builtin?("+")
      assert BuiltinFunction.builtin?(:cons)
      assert BuiltinFunction.builtin?(:CONS)
      assert BuiltinFunction.builtin?("CONS")
      assert BuiltinFunction.builtin?("quit")
      assert BuiltinFunction.builtin?("sb-ext:quit")
      assert BuiltinFunction.builtin?({:id, {1, 1}, ["*"]})
      assert BuiltinFunction.lookup("CONS") == {:ok, :cons}
      assert BuiltinFunction.lookup(:CONS) == {:ok, :cons}
    end

    test "returns :error / false for non-builtin functions" do
      assert BuiltinFunction.lookup("unknown") == :error
      assert BuiltinFunction.lookup(:unknown) == :error
      assert BuiltinFunction.lookup({:id, {1, 1}, ["unknown"]}) == :error
      assert BuiltinFunction.lookup(123) == :error

      refute BuiltinFunction.builtin?("unknown")
      refute BuiltinFunction.builtin?(:unknown)
    end
  end

  describe "compile/3" do
    test "compiles arithmetic operations" do
      dummy_compiler = fn
        {:integer, _, _val} = ast -> ast
        val when is_integer(val) -> {:integer, 1, val}
      end

      assert {:case, 1, {:integer, 1, 1}, _} =
               BuiltinFunction.compile(:+, [1, 2], dummy_compiler)

      assert {:case, 1, {:integer, 1, 5}, _} =
               BuiltinFunction.compile(:-, [5, 2], dummy_compiler)

      assert {:case, 1, {:integer, 1, 3}, _} =
               BuiltinFunction.compile(:*, [3, 4], dummy_compiler)

      assert BuiltinFunction.compile(:/, [10, 2], dummy_compiler) ==
               {:call, 1, {:remote, 1, {:atom, 1, ExLisp.Builtins}, {:atom, 1, :divide_two}},
                [{:integer, 1, 10}, {:integer, 1, 2}]}
    end

    test "compiles cons operation" do
      dummy_compiler = fn val -> {:lit, 1, val} end

      assert BuiltinFunction.compile(:cons, [1, [2, 3]], dummy_compiler) ==
               {:call, 1, {:remote, 1, {:atom, 1, ExLisp.Builtins}, {:atom, 1, :cons}},
                [{:lit, 1, 1}, {:lit, 1, [2, 3]}]}
    end

    test "compiles quit operation" do
      dummy_compiler = fn
        {:integer, _, _val} = ast -> ast
        val when is_integer(val) -> {:integer, 1, val}
      end

      assert BuiltinFunction.compile(:quit, [0], dummy_compiler) ==
               {:call, 1, {:remote, 1, {:atom, 1, ExLisp.Builtins}, {:atom, 1, :quit}},
                [{:cons, 1, {:integer, 1, 0}, {nil, 1}}]}
    end

    test "raises ArgumentError when cons has invalid arguments" do
      dummy_compiler = fn val -> {:lit, 1, val} end

      assert_raise ArgumentError, ~r/cons requires exactly 2 arguments/, fn ->
        BuiltinFunction.compile(:cons, [1], dummy_compiler)
      end

      assert_raise ArgumentError, ~r/cons requires exactly 2 arguments/, fn ->
        BuiltinFunction.compile(:cons, [1, 2, 3], dummy_compiler)
      end
    end

    test "raises RuntimeError for unsupported builtin function" do
      dummy_compiler = fn val -> val end

      assert_raise RuntimeError, ~r/Unsupported builtin function/, fn ->
        BuiltinFunction.compile(:unknown, [1, 2], dummy_compiler)
      end
    end
  end
end
