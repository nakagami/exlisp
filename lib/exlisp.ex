defmodule ExLisp do
  @moduledoc """
  Documentation for `ExLisp`.
  """

  @doc """
  Evaluates a Lisp code string.

  ## Examples

      iex> ExLisp.eval("(+ 1 2)")
      3

      iex> ExLisp.eval("(* 2 3 4)")
      24

  """
  def eval(code) do
    ExLisp.Env.ensure_env()
    ast = ExLisp.LispParser.parse!(code)
    res = LispBeam.evaluate_ast(ast)
    unwrap_primary_value(res)
  end

  defp unwrap_primary_value([:_values_, [first | _]]), do: first
  defp unwrap_primary_value([:_values_, []]), do: nil
  defp unwrap_primary_value(other), do: other

  @doc """
  Converts data for REPL display, turning symbols/atoms to uppercase.
  """
  def to_repl_display(val) when is_atom(val) do
    case val do
      nil -> ExLisp.Symbol.new("NIL")
      :t -> ExLisp.Symbol.new("T")
      _ -> val |> Atom.to_string() |> String.upcase() |> ExLisp.Symbol.new()
    end
  end

  def to_repl_display(%ExLisp.Symbol{} = val), do: val
  def to_repl_display(%ExLisp.List{} = val), do: val

  def to_repl_display([]), do: ExLisp.Symbol.new("NIL")

  def to_repl_display(val) when is_list(val) do
    ExLisp.List.new(val)
  end

  def to_repl_display(val) when is_tuple(val) do
    val |> Tuple.to_list() |> Enum.map(&to_repl_display/1) |> List.to_tuple()
  end

  def to_repl_display(val) when is_struct(val), do: val

  def to_repl_display(val) when is_map(val) do
    Map.new(val, fn {k, v} -> {to_repl_display(k), to_repl_display(v)} end)
  end

  def to_repl_display(val), do: val

  @doc """
  Evaluates Lisp code and formats symbols in uppercase for REPL display.
  """
  def eval_repl(code) do
    ExLisp.IOTracker.with_tracker(fn ->
      raw_result = eval(code)
      ExLisp.Env.record_history(code, raw_result)
      to_repl_display(raw_result)
    end)
  end

  # --- File / BEAM Compilation API ---

  @doc """
  Returns the default `.beam` output directory.
  """
  def default_beam_dir do
    cond do
      Code.ensure_loaded?(Mix.Project) and function_exported?(Mix.Project, :compile_path, 0) and
          Mix.Project.get() != nil ->
        Mix.Project.compile_path()

      File.dir?("_build/dev/lib/exlisp/ebin") ->
        "_build/dev/lib/exlisp/ebin"

      true ->
        "ebin"
    end
  end

  @doc """
  Compiles a Lisp file into a BEAM module and outputs the `.beam` file.
  """
  def compile_file(path, opts \\ []) do
    ExLisp.Compiler.compile_file(path, opts)
  end

  @doc """
  Loads a Lisp source file and evaluates each top-level expression sequentially.
  """
  def load_file(path) do
    ExLisp.Env.ensure_env()
    abs_path = Path.expand(path)
    ExLisp.Env.set_var(:"*load-pathname*", abs_path)
    ExLisp.Env.set_var(:"*load-truename*", abs_path)
    content = File.read!(path)
    asts = ExLisp.LispParser.parse_multiple!(content)
    res = LispBeam.evaluate_asts(asts)
    unwrap_primary_value(res)
  end

  @doc """
  Compiles a Lisp code string into a BEAM module.
  """
  def compile_string(code, opts \\ []) do
    ExLisp.Compiler.compile_string(code, opts)
  end

  # --- Formatting API ---

  @doc """
  Formats a Lisp code string according to standard Common Lisp conventions.

  ## Examples

      iex> ExLisp.format("(+  1   2)")
      "(+ 1 2)\\n"

  """
  def format(code, opts \\ []) when is_binary(code) do
    ExLisp.Formatter.format(code, opts)
  end

  @doc """
  Reads a Lisp file and returns the formatted code.
  If option `in_place: true` or `write: true` is given, it overwrites the file.
  """
  def format_file(path, opts \\ []) do
    ExLisp.Formatter.format_file(path, opts)
  end

  # --- Elixir Interoperability API ---

  @doc """
  Gets the value of a Lisp global variable.

  ## Examples

      iex> ExLisp.eval("(defparameter x 100)")
      :x
      iex> ExLisp.get_var(:x)
      100
      iex> ExLisp.get_var("X")
      100

  """
  def get_var(name) do
    ExLisp.Env.get_var(name)
  end

  @doc """
  Sets a Lisp global variable.

  ## Examples

      iex> ExLisp.set_var(:y, 200)
      200
      iex> ExLisp.eval("y")
      200

  """
  def set_var(name, value) do
    ExLisp.Env.put_var(name, value)
    value
  end

  @doc """
  Checks if a Lisp global variable is defined.
  """
  def has_var?(name) do
    ExLisp.Env.has_var?(name)
  end

  @doc """
  Deletes a Lisp global variable.
  """
  def delete_var(name) do
    ExLisp.Env.delete_var(name)
  end

  @doc """
  Gets a Lisp function as an Elixir anonymous function.

  ## Examples

      iex> ExLisp.eval("(defun add (a b) (+ a b))")
      :add
      iex> add = ExLisp.get_fun(:add)
      iex> add.(2, 3)
      5

  """
  def get_fun(name) do
    ExLisp.Env.get_fun(name)
  end

  @doc """
  Checks if a Lisp function is defined.
  """
  def has_fun?(name) do
    ExLisp.Env.has_fun?(name)
  end

  @doc """
  Calls a Lisp function with the given arguments list.

  ## Examples

      iex> ExLisp.eval("(defun multiply (a b) (* a b))")
      :multiply
      iex> ExLisp.call(:multiply, [3, 4])
      12
      iex> ExLisp.call("MULTIPLY", [5, 6])
      30

  """
  def call(name, args) when is_list(args) do
    ExLisp.Env.call_fun(name, args)
  end
end
