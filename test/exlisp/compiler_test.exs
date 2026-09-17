defmodule ExLisp.CompilerTest do
  use ExUnit.Case
  alias ExLisp.Compiler

  @tmp_dir Path.expand("../../tmp/compiler_test", __DIR__)

  setup do
    ExLisp.Env.reset()
    File.mkdir_p!(@tmp_dir)

    on_exit(fn ->
      File.rm_rf!(@tmp_dir)
    end)

    :ok
  end

  describe "compile_string/2" do
    test "compiles lisp code into a BEAM module" do
      code = """
      (defparameter base 50)
      (defvar factor 3)
      (defun multiply (a b) (* a b))
      (defun calc (x) (* (+ x base) factor))
      """

      {:ok, mod, binary} =
        Compiler.compile_string(code, module: TestModuleCompiled, write_beam: false)

      assert mod == TestModuleCompiled
      assert is_binary(binary)
      assert apply(TestModuleCompiled, :multiply, [4, 5]) == 20
      assert apply(TestModuleCompiled, :calc, [10]) == 180
      assert apply(TestModuleCompiled, :get_var, [:base]) == 50
      assert apply(TestModuleCompiled, :has_var, [:base])
      refute apply(TestModuleCompiled, :has_var, [:unknown])
    end
  end

  describe "compile_file/2 and file output" do
    test "compiles a file to .beam on disk" do
      lisp_file = Path.join(@tmp_dir, "my_math.lisp")

      File.write!(lisp_file, """
      (defparameter offset 10)
      (defun add_offset (n) (+ n offset))
      """)

      {:ok, mod, beam_path} =
        Compiler.compile_file(lisp_file, module: MyMathModule, output_dir: @tmp_dir)

      assert mod == MyMathModule
      assert File.exists?(beam_path)

      # Load from disk and verify
      char_dir = String.to_charlist(@tmp_dir)
      :code.add_patha(char_dir)
      :code.purge(MyMathModule)
      {:module, MyMathModule} = :code.load_file(MyMathModule)

      assert apply(MyMathModule, :add_offset, [5]) == 15
      assert apply(MyMathModule, :get_var, [:offset]) == 10
    end
  end
end
