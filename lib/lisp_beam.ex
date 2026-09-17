defmodule LispBeam do
  @moduledoc """
  Generates Erlang Abstract Format from ExLisp AST,
  compiles it to BEAM binaries, and executes it (with interactive REPL).
  """

  @doc """
  Starts the REPL (Read-Eval-Print Loop).
  """
  def start_repl do
    IO.puts("--- BEAM Lisp REPL ---")
    IO.puts("Exit with Ctrl+C or type 'exit'")
    repl_loop(1)
  end

  defp repl_loop(counter) do
    input = IO.gets("lisp(#{counter})> ")

    case String.trim(input) do
      "exit" ->
        IO.puts("Goodbye!")

      "" ->
        repl_loop(counter)

      code ->
        try do
          # 1. Read: parse with custom parser
          ast = ExLisp.LispParser.parse!(code)

          # 2. Eval: compile to BEAM & execute
          result = evaluate_ast(ast, counter)

          # 3. Print: output result
          IO.inspect(ExLisp.to_repl_display(result), label: "=>")
          repl_loop(counter + 1)
        rescue
          e ->
            IO.puts("Error: #{inspect(e)}")
            repl_loop(counter)
        end
    end
  end

  @doc """
  Dynamically compiles AST into a temporary BEAM module and executes it.
  Directly evaluates simple expressions (literals, constants, quotes, etc.) for performance.
  """
  def evaluate_ast(ast, counter \\ nil) do
    ExLisp.Env.ensure_env()

    case try_direct_eval(ast) do
      {:ok, val} ->
        val

      {:error, :not_simple} ->
        evaluate_asts([ast], counter)
    end
  end

  @doc """
  Directly evaluates simple expressions (literals, constants, quotes, simple variable references) without invoking compiler.
  """
  def try_direct_eval(ast) do
    case ast do
      {:lit, val} ->
        {:ok, val}

      val when is_integer(val) or is_float(val) or is_binary(val) ->
        {:ok, val}

      %ExLisp.Ratio{} = val ->
        {:ok, val}

      {:keyword, _pos, kw} ->
        {:ok, kw}

      {:quoted, _pos, elements} when is_list(elements) ->
        eval_quoted_elements(elements)

      {:quoted, _pos, element} ->
        eval_quote_node(element)

      {:list, _pos, [{:id, _p2, [q]}, quoted_node]} when q in ["quote", "QUOTE"] ->
        eval_quote_node(quoted_node)

      {:id, _pos, [name]} ->
        down = String.downcase(name)

        cond do
          down in ["nil", "n.i.l"] ->
            {:ok, nil}

          down == "t" ->
            {:ok, :t}

          String.starts_with?(name, ":") ->
            kw = String.trim_leading(name, ":") |> String.downcase() |> String.to_atom()
            {:ok, kw}

          true ->
            var_atom = down |> String.to_atom()

            if ExLisp.Env.has_var?(var_atom) do
              {:ok, ExLisp.Env.get_var(var_atom)}
            else
              {:error, :not_simple}
            end
        end

      nil ->
        {:ok, nil}

      :t ->
        {:ok, :t}

      _ ->
        {:error, :not_simple}
    end
  end

  defp eval_quote_node({:id, _pos, parts}) do
    {:ok, Enum.join(parts, ".") |> normalize_quote_symbol()}
  end

  defp eval_quote_node({:lit, val}), do: {:ok, val}
  defp eval_quote_node({:lit, _pos, val}), do: {:ok, val}

  defp eval_quote_node(val) when is_integer(val) or is_float(val) or is_binary(val),
    do: {:ok, val}

  defp eval_quote_node(%ExLisp.Ratio{} = val), do: {:ok, val}
  defp eval_quote_node({:keyword, _pos, kw}), do: {:ok, kw}

  defp eval_quote_node({:vector, _pos, elements}) do
    with {:ok, elem_vals} <- eval_quoted_elements(elements) do
      {:ok, ExLisp.Builtins.vector(elem_vals)}
    else
      _ -> {:error, :not_simple}
    end
  end

  defp eval_quote_node({:quoted, _pos, elements}) when is_list(elements),
    do: eval_quoted_elements(elements)

  defp eval_quote_node({:quoted, _pos, element}), do: eval_quote_node(element)
  defp eval_quote_node({:list, _pos, elements}), do: eval_quoted_elements(elements)

  defp eval_quote_node({:dotted_list, _pos, elements, tail}) do
    with {:ok, head_vals} <- eval_quoted_elements(elements),
         {:ok, tail_val} <- eval_quote_node(tail) do
      {:ok, make_eval_improper(head_vals, tail_val)}
    else
      _ -> {:error, :not_simple}
    end
  end

  defp eval_quote_node([]), do: {:ok, []}
  defp eval_quote_node(nil), do: {:ok, nil}
  defp eval_quote_node(_), do: {:error, :not_simple}

  defp make_eval_improper([], tail), do: tail
  defp make_eval_improper([h | rest], tail), do: [h | make_eval_improper(rest, tail)]

  defp eval_quoted_elements(elements) do
    results =
      Enum.reduce_while(elements, [], fn elem, acc ->
        case eval_quote_node(elem) do
          {:ok, val} -> {:cont, [val | acc]}
          {:error, _} -> {:halt, :error}
        end
      end)

    case results do
      :error -> {:error, :not_simple}
      list -> {:ok, Enum.reverse(list)}
    end
  end

  @doc """
  Compiles and executes multiple ASTs in batch (optimizing batch execution such as file loading).
  """
  def evaluate_asts(asts, counter \\ nil)
  def evaluate_asts([], _counter), do: nil

  def evaluate_asts(asts, counter) when is_list(asts) do
    ExLisp.Env.ensure_env()

    chunks = chunk_by_macro_defs(asts)

    Enum.reduce(chunks, nil, fn chunk, _acc ->
      unique_id = counter || System.unique_integer([:positive, :monotonic])
      module_name = Module.concat(["LispReplModule#{unique_id}"])
      module_atom = module_name

      compiled_exprs =
        case chunk do
          [] ->
            [{:atom, 1, nil}]

          [single] ->
            [compile_expr(single, MapSet.new())]

          multiple ->
            Enum.map(multiple, fn ast ->
              try do
                expr = compile_expr(ast, MapSet.new())

                {:try, 1, [expr], [],
                 [
                   {:clause, 1, [{:tuple, 1, [{:var, 1, :_}, {:var, 1, :_}, {:var, 1, :_}]}], [],
                    [{:atom, 1, nil}]}
                 ], []}
              rescue
                _ -> {:atom, 1, nil}
              end
            end)
        end

      erl_forms = [
        {:attribute, 1, :module, module_atom},
        {:attribute, 1, :export, [run: 0]},
        {:function, 1, :run, 0,
         [
           {:clause, 1, [], [], compiled_exprs}
         ]}
      ]

      case :compile.forms(erl_forms, [:binary, :return_errors]) do
        {:ok, ^module_atom, binary} ->
          :code.purge(module_atom)
          {:module, ^module_atom} = :code.load_binary(module_atom, ~c"nofile", binary)
          result = apply(module_name, :run, [])

          # Modules without function definitions or closures are safely purged immediately to prevent memory growth
          unless Enum.any?(chunk, &contains_closure_or_def?(ast_or_inner(&1))) do
            :code.delete(module_atom)
            :code.purge(module_atom)
          end

          result

        {:error, errors, warnings} ->
          raise "BEAM Compilation Failed: #{inspect(errors)} #{inspect(warnings)}"
      end
    end)
  end

  defp ast_or_inner(ast), do: ast

  defp contains_closure_or_def?(ast) do
    case ast do
      {:list, _pos, [op | rest]} ->
        name = extract_symbol_name(op)

        (is_atom(name) and
           Atom.to_string(name) in [
             "defun",
             "defmacro",
             "defmethod",
             "defgeneric",
             "defstruct",
             "defclass",
             "lambda",
             "flet",
             "labels",
             "function",
             "#",
             "#'"
           ]) or Enum.any?(rest, &contains_closure_or_def?/1)

      {:quoted, _pos, [op | rest]} ->
        name = extract_symbol_name(op)

        (is_atom(name) and
           Atom.to_string(name) in [
             "defun",
             "defmacro",
             "defmethod",
             "defgeneric",
             "defstruct",
             "defclass",
             "lambda",
             "flet",
             "labels",
             "function",
             "#",
             "#'"
           ]) or Enum.any?(rest, &contains_closure_or_def?/1)

      [op | rest] when is_list(rest) ->
        name =
          case op do
            a when is_atom(a) -> Atom.to_string(a) |> String.downcase()
            s when is_binary(s) -> String.downcase(s)
            _ -> ""
          end

        name in [
          "defun",
          "defmacro",
          "defmethod",
          "defgeneric",
          "defstruct",
          "defclass",
          "lambda",
          "flet",
          "labels",
          "function"
        ] or Enum.any?(rest, &contains_closure_or_def?/1)

      _ ->
        false
    end
  end

  defp chunk_by_macro_defs(asts) do
    {chunks, current} =
      Enum.reduce(asts, {[], []}, fn ast, {chunks_acc, current_acc} ->
        if macro_defining_ast?(ast) do
          new_chunks =
            if current_acc == [] do
              chunks_acc ++ [[ast]]
            else
              chunks_acc ++ [Enum.reverse(current_acc), [ast]]
            end

          {new_chunks, []}
        else
          {chunks_acc, [ast | current_acc]}
        end
      end)

    if current == [] do
      chunks
    else
      chunks ++ [Enum.reverse(current)]
    end
  end

  defp macro_defining_ast?(ast) do
    case ast do
      [:defmacro | _] ->
        true

      {:list, _pos, [{:id, _pos2, [name]} | _]} ->
        String.downcase(name) in [
          "defmacro",
          "eval-when",
          "load",
          "in-package",
          "in_package",
          "defpackage",
          "provide",
          "require"
        ]

      _ ->
        false
    end
  end

  # --- Transpilation from AST to Erlang Abstract Format ---

  def compile_expr(ast, local_env \\ MapSet.new())

  # Pass-through for nodes already in Erlang format
  def compile_expr({:atom, _line, _val} = erl_ast, _local_env), do: erl_ast
  def compile_expr({:integer, _line, _val} = erl_ast, _local_env), do: erl_ast
  def compile_expr({:float, _line, _val} = erl_ast, _local_env), do: erl_ast
  def compile_expr({:bin, _line, _val} = erl_ast, _local_env), do: erl_ast
  def compile_expr({:var, _line, _val} = erl_ast, _local_env), do: erl_ast
  def compile_expr({:call, _line, _fn, _args} = erl_ast, _local_env), do: erl_ast
  def compile_expr({:case, _line, _expr, _clauses} = erl_ast, _local_env), do: erl_ast
  def compile_expr({:block, _line, _exprs} = erl_ast, _local_env), do: erl_ast
  def compile_expr({:cons, _line, _h, _t} = erl_ast, _local_env), do: erl_ast
  def compile_expr({nil, _line} = erl_ast, _local_env), do: erl_ast

  # Array object
  def compile_expr({:array, _dims, _tid} = arr, _local_env) do
    elements = ExLisp.Builtins.seq_to_list(arr)

    compiled_elems =
      Enum.map(elements, fn elem -> compile_quote(ExLisp.Macro.lisp_data_to_ast(elem)) end)

    {:call, 1, {:remote, 1, {:atom, 1, ExLisp.Builtins}, {:atom, 1, :vector}},
     [ast_cons_list(compiled_elems)]}
  end

  # AST literal
  def compile_expr({:lit, %ExLisp.Ratio{numerator: num, denominator: den}}, _local_env) do
    {:call, 1, {:remote, 1, {:atom, 1, ExLisp.Ratio}, {:atom, 1, :new}},
     [{:integer, 1, num}, {:integer, 1, den}]}
  end

  def compile_expr({:lit, val}, _local_env) when is_integer(val) do
    {:integer, 1, val}
  end

  def compile_expr({:lit, val}, _local_env) when is_float(val) do
    {:float, 1, val}
  end

  def compile_expr({:lit, val}, _local_env) when is_binary(val) do
    {:bin, 1, [{:bin_element, 1, {:string, 1, :erlang.binary_to_list(val)}, :default, :default}]}
  end

  def compile_expr({:lit, val}, _local_env) when is_atom(val) do
    case val do
      nil ->
        {:atom, 1, nil}

      :t ->
        {:atom, 1, :t}

      :T ->
        {:atom, 1, :t}

      _ ->
        atom_down = Atom.to_string(val) |> String.downcase() |> String.to_atom()
        {:atom, 1, atom_down}
    end
  end

  def compile_expr({:lit, val}, local_env) when is_list(val) do
    ast_cons_list(Enum.map(val, &compile_expr({:lit, &1}, local_env)))
  end

  def compile_expr({:lit, {:keyword, _pos, val}}, _local_env) do
    {:atom, 1, val}
  end

  def compile_expr({:lit, inner}, local_env) when is_tuple(inner) do
    compile_expr(inner, local_env)
  end

  # Keyword node
  def compile_expr({:keyword, _pos, val}, _local_env) do
    {:atom, 1, val}
  end

  # Identifier (variable reference, nil, t, etc.)
  def compile_expr({:id, _pos, parts}, local_env) when is_list(parts) do
    if length(parts) == 1 do
      [name] = parts
      down_name = String.downcase(name)

      cond do
        down_name in ["nil", "n.i.l"] ->
          {:atom, 1, nil}

        down_name in ["t"] ->
          {:atom, 1, :t}

        String.starts_with?(name, ":") ->
          trimmed = String.trim_leading(name, ":") |> String.downcase()

          clean_kw =
            case trimmed do
              "nil" -> :":nil"
              "t" -> :":t"
              _ -> String.to_atom(trimmed)
            end

          {:atom, 1, clean_kw}

        String.contains?(name, ".") or String.contains?(name, ":") ->
          case normalize_remote_op({:id, nil, parts}) do
            {:remote, mod, fun} ->
              {:call, 1, {:remote, 1, {:atom, 1, mod}, {:atom, 1, fun}}, []}

            _ ->
              compile_var_lookup(name, local_env)
          end

        true ->
          compile_var_lookup(down_name, local_env)
      end
    else
      case normalize_remote_op({:id, nil, parts}) do
        {:remote, mod, fun} ->
          {:call, 1, {:remote, 1, {:atom, 1, mod}, {:atom, 1, fun}}, []}

        _ ->
          joined_name = Enum.join(parts, ".")
          compile_var_lookup(joined_name, local_env)
      end
    end
  end

  # Raw value (fallback)
  def compile_expr(%ExLisp.Ratio{numerator: num, denominator: den}, _local_env) do
    {:call, 1, {:remote, 1, {:atom, 1, ExLisp.Ratio}, {:atom, 1, :new}},
     [{:integer, 1, num}, {:integer, 1, den}]}
  end

  def compile_expr(val, _local_env) when is_integer(val) do
    {:integer, 1, val}
  end

  def compile_expr(val, _local_env) when is_float(val) do
    {:float, 1, val}
  end

  def compile_expr(val, _local_env) when is_binary(val) do
    {:bin, 1, [{:bin_element, 1, {:string, 1, :erlang.binary_to_list(val)}, :default, :default}]}
  end

  def compile_expr(val, _local_env) when is_atom(val) do
    case val do
      nil ->
        {:atom, 1, nil}

      :t ->
        {:atom, 1, :t}

      :T ->
        {:atom, 1, :t}

      _ ->
        atom_down = Atom.to_string(val) |> String.downcase() |> String.to_atom()
        {:atom, 1, atom_down}
    end
  end

  # Backquote form
  def compile_expr({:backquote, _pos, inner}, local_env) do
    expanded = ExLisp.Macro.expand_backquote(inner)
    compile_expr(expanded, local_env)
  end

  def compile_expr({:comma, _pos, inner}, local_env) do
    compile_expr(inner, local_env)
  end

  def compile_expr({:comma_at, _pos, inner}, local_env) do
    compile_expr(inner, local_env)
  end

  # Quoted list form (bracket [...]): {:quoted, _pos, elements}
  def compile_expr({:quoted, _pos, elements}, local_env) when is_list(elements) do
    ast_cons_list(Enum.map(elements, &compile_expr(&1, local_env)))
  end

  def compile_expr({:quoted, _pos, element}, _local_env) do
    compile_quote(element)
  end

  # Vector form: {:vector, _pos, elements}
  def compile_expr({:vector, _pos, _elements} = node, _local_env) do
    compile_quote(node)
  end

  # Empty list
  def compile_expr({:list, _pos, []}, _local_env), do: {nil, 1}
  def compile_expr([], _local_env), do: {nil, 1}

  # Dotted list form: {:dotted_list, pos, elements, tail}
  def compile_expr({:dotted_list, line, elements, tail}, local_env) do
    compile_expr({:list, line, [{:id, line, ["list*"]} | elements ++ [tail]]}, local_env)
  end

  # List form: {:list, _pos, [op | args]}
  def compile_expr({:list, _pos, [op | args]}, local_env) do
    compile_op(op, args, local_env)
  end

  # [op | args] list form
  def compile_expr([op | args], local_env) do
    compile_op(op, args, local_env)
  end

  defp compile_var_lookup(var_name, local_env) do
    var_atom =
      if is_atom(var_name) do
        var_name
      else
        var_name |> String.downcase() |> String.to_atom()
      end

    renamed =
      Enum.find_value(local_env, fn
        {:renamed_var, ^var_atom, erl_name} -> erl_name
        _ -> nil
      end)

    cond do
      renamed != nil ->
        {:var, 1, renamed}

      MapSet.member?(local_env, {:mutated, var_atom}) ->
        lex_var = :"V_lex_#{System.unique_integer([:positive, :monotonic])}"

        {:case, 1,
         {:call, 1, {:remote, 1, {:atom, 1, :erlang}, {:atom, 1, :get}}, [{:atom, 1, var_atom}]},
         [
           {:clause, 1, [{:atom, 1, :undefined}], [], [{:var, 1, erl_var_name(var_atom)}]},
           {:clause, 1, [{:var, 1, lex_var}], [], [{:var, 1, lex_var}]}
         ]}

      MapSet.member?(local_env, var_atom) ->
        {:var, 1, erl_var_name(var_atom)}

      var_atom == :_cl_1plus_ ->
        {:atom, 1, :"1+"}

      var_atom == :_cl_1minus_ ->
        {:atom, 1, :"1-"}

      var_atom == :_cl_lt_ ->
        {:atom, 1, :<}

      var_atom == :_cl_lte_ ->
        {:atom, 1, :<=}

      var_atom == :_cl_gt_ ->
        {:atom, 1, :>}

      var_atom == :_cl_gte_ ->
        {:atom, 1, :>=}

      var_atom == :_cl_string_eq_ ->
        {:atom, 1, :"string="}

      var_atom == :_cl_string_neq_ ->
        {:atom, 1, :"string/="}

      var_atom == :_cl_char_eq_ ->
        {:atom, 1, :"char="}

      true ->
        {:call, 1, {:remote, 1, {:atom, 1, ExLisp.Env}, {:atom, 1, :get_var}},
         [{:atom, 1, var_atom}]}
    end
  end

  # --- Compilation of operators and special forms ---

  def compile_op(op, args, local_env \\ MapSet.new()) do
    case extract_op_name(op) do
      :defparameter ->
        compile_defparameter(args, local_env)

      :defvar ->
        compile_defvar(args, local_env)

      :defconstant ->
        compile_defparameter(args, local_env)

      :defun ->
        compile_defun(args, local_env)

      :defmacro ->
        compile_defmacro(args, local_env)

      :macrolet ->
        compile_macrolet(args, local_env)

      name when name in [:symbol_macrolet, :_cl_symbol_macrolet_] ->
        compile_symbol_macrolet(args, local_env)

      :_cl_backquote_ ->
        case args do
          [inner] -> compile_expr(ExLisp.Macro.expand_backquote(inner), local_env)
          _ -> {nil, 1}
        end

      :defstruct ->
        compile_defstruct(args, local_env)

      :defclass ->
        compile_defclass(args, local_env)

      :defgeneric ->
        compile_defgeneric(args, local_env)

      :defmethod ->
        compile_defmethod(args, local_env)

      :quote ->
        case args do
          [quoted_node] -> compile_quote(quoted_node)
          _ -> {nil, 1}
        end

      :function ->
        compile_function_form(args, local_env)

      :if ->
        compile_if(args, local_env)

      :car ->
        case args do
          [arg] ->
            c_arg = compile_expr(arg, local_env)
            h_var = :"V_h_#{System.unique_integer([:positive])}"
            other_var = :"V_other_#{System.unique_integer([:positive])}"

            {:case, 1, c_arg,
             [
               {:clause, 1, [{:cons, 1, {:var, 1, h_var}, {:var, 1, :_}}], [],
                [{:var, 1, h_var}]},
               {:clause, 1, [{:atom, 1, nil}], [], [{:atom, 1, nil}]},
               {:clause, 1, [{nil, 1}], [], [{:atom, 1, nil}]},
               {:clause, 1, [{:var, 1, other_var}], [],
                [
                  {:call, 1, {:remote, 1, {:atom, 1, ExLisp.Builtins}, {:atom, 1, :car}},
                   [{:var, 1, other_var}]}
                ]}
             ]}

          _ ->
            compile_regular_op(op, args, local_env)
        end

      :cdr ->
        case args do
          [arg] ->
            c_arg = compile_expr(arg, local_env)
            t_var = :"V_t_#{System.unique_integer([:positive])}"
            other_var = :"V_other_#{System.unique_integer([:positive])}"

            {:case, 1, c_arg,
             [
               {:clause, 1, [{:cons, 1, {:var, 1, :_}, {:var, 1, t_var}}], [],
                [{:var, 1, t_var}]},
               {:clause, 1, [{:atom, 1, nil}], [], [{:atom, 1, nil}]},
               {:clause, 1, [{nil, 1}], [], [{:atom, 1, nil}]},
               {:clause, 1, [{:var, 1, other_var}], [],
                [
                  {:call, 1, {:remote, 1, {:atom, 1, ExLisp.Builtins}, {:atom, 1, :cdr}},
                   [{:var, 1, other_var}]}
                ]}
             ]}

          _ ->
            compile_regular_op(op, args, local_env)
        end

      :cons ->
        case args do
          [car_node, cdr_node] ->
            {:call, 1, {:remote, 1, {:atom, 1, ExLisp.Builtins}, {:atom, 1, :cons}},
             [compile_expr(car_node, local_env), compile_expr(cdr_node, local_env)]}

          _ ->
            compile_regular_op(op, args, local_env)
        end

      :list ->
        compiled_args = Enum.map(args, &compile_expr(&1, local_env))
        ast_cons_list(compiled_args)

      name when name in [:not, :null] ->
        case args do
          [arg] ->
            c_arg = compile_expr(arg, local_env)

            {:case, 1, c_arg,
             [
               {:clause, 1, [{nil, 1}], [], [{:atom, 1, :t}]},
               {:clause, 1, [{:atom, 1, nil}], [], [{:atom, 1, :t}]},
               {:clause, 1, [{:atom, 1, false}], [], [{:atom, 1, :t}]},
               {:clause, 1, [{:var, 1, :_}], [], [{:atom, 1, nil}]}
             ]}

          _ ->
            compile_regular_op(op, args, local_env)
        end

      :consp ->
        case args do
          [arg] ->
            c_arg = compile_expr(arg, local_env)

            {:case, 1, c_arg,
             [
               {:clause, 1, [{:cons, 1, {:var, 1, :_}, {:var, 1, :_}}], [], [{:atom, 1, :t}]},
               {:clause, 1, [{:var, 1, :_}], [], [{:atom, 1, nil}]}
             ]}

          _ ->
            compile_regular_op(op, args, local_env)
        end

      :atom ->
        case args do
          [arg] ->
            c_arg = compile_expr(arg, local_env)

            {:case, 1, c_arg,
             [
               {:clause, 1, [{:cons, 1, {:var, 1, :_}, {:var, 1, :_}}], [], [{:atom, 1, nil}]},
               {:clause, 1, [{:var, 1, :_}], [], [{:atom, 1, :t}]}
             ]}

          _ ->
            compile_regular_op(op, args, local_env)
        end

      :eq ->
        case args do
          [arg1, arg2] ->
            c1 = compile_expr(arg1, local_env)
            c2 = compile_expr(arg2, local_env)

            {:case, 1, {:op, 1, :"=:=", c1, c2},
             [
               {:clause, 1, [{:atom, 1, true}], [], [{:atom, 1, :t}]},
               {:clause, 1, [{:atom, 1, false}], [], [{:atom, 1, nil}]}
             ]}

          _ ->
            compile_regular_op(op, args, local_env)
        end

      name when name in [:"1+", :_cl_1plus_] ->
        case args do
          [arg] ->
            {:call, 1, {:remote, 1, {:atom, 1, ExLisp.Builtins}, {:atom, 1, :add_two}},
             [compile_expr(arg, local_env), {:integer, 1, 1}]}

          _ ->
            compile_regular_op(op, args, local_env)
        end

      name when name in [:"1-", :_cl_1minus_] ->
        case args do
          [arg] ->
            {:call, 1, {:remote, 1, {:atom, 1, ExLisp.Builtins}, {:atom, 1, :sub_two}},
             [compile_expr(arg, local_env), {:integer, 1, 1}]}

          _ ->
            compile_regular_op(op, args, local_env)
        end

      :when ->
        compile_when(args, local_env)

      :unless ->
        compile_unless(args, local_env)

      :cond ->
        compile_cond(args, local_env)

      :progn ->
        compile_progn(args, local_env)

      :prog ->
        case args do
          [bindings | body] ->
            {decls, tagbody_body} = split_declarations(body)

            compile_expr(
              {:list, 1,
               [
                 {:id, 1, ["block"]},
                 {:lit, nil},
                 {:list, 1,
                  [
                    {:id, 1, ["let"]},
                    bindings
                  ] ++
                    decls ++
                    [
                      {:list, 1, [{:id, 1, ["tagbody"]} | tagbody_body]}
                    ]}
               ]},
              local_env
            )

          _ ->
            {:atom, 1, nil}
        end

      name when name in [:"prog*", :_cl_prog_star_, :prog_star] ->
        case args do
          [bindings | body] ->
            {decls, tagbody_body} = split_declarations(body)

            compile_expr(
              {:list, 1,
               [
                 {:id, 1, ["block"]},
                 {:lit, nil},
                 {:list, 1,
                  [
                    {:id, 1, ["let*"]},
                    bindings
                  ] ++
                    decls ++
                    [
                      {:list, 1, [{:id, 1, ["tagbody"]} | tagbody_body]}
                    ]}
               ]},
              local_env
            )

          _ ->
            {:atom, 1, nil}
        end

      :prog1 ->
        compile_prog1(args, local_env)

      :prog2 ->
        compile_prog2(args, local_env)

      :let ->
        compile_let(args, local_env)

      name when name in [:"let*", :_cl_let_star_] ->
        compile_let_star(args, local_env)

      :flet ->
        compile_flet(args, local_env)

      :labels ->
        compile_labels(args, local_env)

      :and ->
        compile_and(args, local_env)

      :or ->
        compile_or(args, local_env)

      :lambda ->
        compile_lambda(args, local_env)

      :setq ->
        compile_setq(args, local_env)

      :setf ->
        compile_setf(args, local_env)

      :dotimes ->
        compile_dotimes(args, local_env)

      :dolist ->
        compile_dolist(args, local_env)

      :loop ->
        compile_loop(args, local_env)

      :block ->
        compile_block(args, local_env)

      :return ->
        compile_return(args, local_env)

      name when name in [:return_from, :_cl_return_from_] ->
        compile_return_from(args, local_env)

      name when name in [:unwind_protect, :_cl_unwind_protect_, :"unwind-protect"] ->
        compile_unwind_protect(args, local_env)

      :do ->
        compile_do(args, local_env)

      name when name in [:"do*", :_cl_do_star_, :do_star] ->
        compile_do(args, local_env)

      :tagbody ->
        compile_tagbody(args, local_env)

      :go ->
        compile_go(args, local_env)

      name when name in [:with_open_file, :_cl_with_open_file_, :"with-open-file"] ->
        compile_with_open_file(args, local_env)

      name
      when name in [
             :with_input_from_string,
             :_cl_with_input_from_string_,
             :"with-input-from-string"
           ] ->
        compile_with_input_from_string(args, local_env)

      name
      when name in [:with_output_to_string, :_cl_with_output_to_string_, :"with-output-to-string"] ->
        compile_with_output_to_string(args, local_env)

      name when name in [:locally, :_cl_locally_] ->
        compile_locally(args, local_env)

      name when name in [:ignore_errors, :_cl_ignore_errors_] ->
        compile_ignore_errors(args, local_env)

      name when name in [:handler_case, :_cl_handler_case_] ->
        compile_handler_case(args, local_env)

      name
      when name in [:declaim, :_cl_declaim_, :proclaim, :_cl_proclaim_, :declare, :_cl_declare_] ->
        {:atom, 1, :t}

      name
      when name in [
             :define_setf_expander,
             :_cl_define_setf_expander_,
             :defsetf,
             :_cl_defsetf_,
             :define_modify_macro,
             :_cl_define_modify_macro_,
             :define_compiler_macro,
             :_cl_define_compiler_macro_
           ] ->
        case args do
          [name_node | _] ->
            sym_name = extract_symbol_name(name_node)
            {:atom, 1, sym_name}

          _ ->
            {:atom, 1, :t}
        end

      name when name in [:eval_when, :_cl_eval_when_] ->
        case args do
          [_situations | body_nodes] -> compile_progn(body_nodes, local_env)
          _ -> {:atom, 1, nil}
        end

      name
      when name in [
             :defpackage,
             :_cl_defpackage_,
             :in_package,
             :_cl_in_package_,
             :provide,
             :_cl_provide_,
             :require,
             :_cl_require_
           ] ->
        case args do
          [pkg_node | _] ->
            pkg_name = extract_symbol_name(pkg_node)
            {:atom, 1, pkg_name}

          _ ->
            {:atom, 1, :t}
        end

      name when name in [:defsystem, :_cl_defsystem_] ->
        {:atom, 1, :t}

      name when name in [:keywordp, :_cl_keywordp_] ->
        case args do
          [{:keyword, _, _}] ->
            {:atom, 1, :t}

          [{:list, _, [{:id, _, [q]}, {:keyword, _, _}]}] when q in ["quote", "QUOTE"] ->
            {:atom, 1, :t}

          _ ->
            compile_regular_op(op, args, local_env)
        end

      name when name in [:check_type, :_cl_check_type_] ->
        {:atom, 1, nil}

      name when name in [:assert, :_cl_assert_] ->
        case args do
          [test_node | _] ->
            compile_expr(
              {:list, 1,
               [
                 {:id, 1, ["unless"]},
                 test_node,
                 {:list, 1,
                  [
                    {:id, 1, ["error"]},
                    {:lit, "Assertion failed: ~S"},
                    {:list, 1, [{:id, 1, ["quote"]}, test_node]}
                  ]}
               ]},
              local_env
            )

          _ ->
            {:atom, 1, nil}
        end

      name when name in [:deftype, :_cl_deftype_] ->
        {:atom, 1, :t}

      name when name in [:define_condition, :_cl_define_condition_] ->
        {:atom, 1, :t}

      name when name in [:the, :_cl_the_] ->
        case args do
          [_type, value_node | _] -> compile_expr(value_node, local_env)
          _ -> {:atom, 1, nil}
        end

      name
      when name in [:symbol_macrolet, :"symbol-macrolet", :_cl_symbol_macrolet_] ->
        compile_symbol_macrolet(args, local_env)

      name when name in [:destructuring_bind, :"destructuring-bind", :_cl_destructuring_bind_] ->
        compile_destructuring_bind(args, local_env)

      name
      when name in [:multiple_value_bind, :"multiple-value-bind", :_cl_multiple_value_bind_] ->
        compile_multiple_value_bind(args, local_env)

      name
      when name in [:multiple_value_call, :"multiple-value-call", :_cl_multiple_value_call_] ->
        compile_multiple_value_call(args, local_env)

      name
      when name in [:multiple_value_list, :"multiple-value-list", :_cl_multiple_value_list_] ->
        compile_multiple_value_list(args, local_env)

      name
      when name in [:multiple_value_setq, :"multiple-value-setq", :_cl_multiple_value_setq_] ->
        compile_multiple_value_setq(args, local_env)

      name
      when name in [:multiple_value_prog1, :"multiple-value-prog1", :_cl_multiple_value_prog1_] ->
        compile_multiple_value_prog1(args, local_env)

      name when name in [:nth_value, :"nth-value", :_cl_nth_value_] ->
        compile_nth_value(args, local_env)

      name when name in [:catch, :_cl_catch_] ->
        compile_catch(args, local_env)

      name when name in [:throw, :_cl_throw_] ->
        compile_throw(args, local_env)

      name when name in [:progv, :_cl_progv_] ->
        compile_progv(args, local_env)

      name when name in [:psetq, :_cl_psetq_] ->
        compile_psetq(args, local_env)

      name when name in [:psetf, :_cl_psetf_] ->
        compile_psetf(args, local_env)

      name when name in [:rotatef, :_cl_rotatef_] ->
        compile_rotatef(args, local_env)

      name when name in [:shiftf, :_cl_shiftf_] ->
        compile_shiftf(args, local_env)

      name when name in [:push, :_cl_push_] ->
        case args do
          [item_node, place_node | _] ->
            uid = System.unique_integer([:positive, :monotonic])
            item_var = {:id, 1, ["__push_item_#{uid}"]}
            {bound_place, arg_bindings} = decompose_macro_place(place_node, "push")

            ast =
              {:list, 1,
               [
                 {:id, 1, ["let*"]},
                 {:list, 1, [{:list, 1, [item_var, item_node]} | arg_bindings]},
                 {:list, 1,
                  [
                    {:id, 1, ["setf"]},
                    bound_place,
                    {:list, 1, [{:id, 1, ["cons"]}, item_var, bound_place]}
                  ]}
               ]}

            compile_expr(ast, local_env)

          _ ->
            {:atom, 1, nil}
        end

      name when name in [:pushnew, :_cl_pushnew_] ->
        case args do
          [item_node, place_node | rest_opts] ->
            uid = System.unique_integer([:positive, :monotonic])
            item_var = {:id, 1, ["__pushnew_item_#{uid}"]}

            opt_vars =
              Enum.map(rest_opts, fn _ ->
                {:id, 1, ["__pushnew_opt_#{System.unique_integer([:positive, :monotonic])}"]}
              end)

            opt_bindings =
              Enum.zip(opt_vars, rest_opts)
              |> Enum.map(fn {var, expr} -> {:list, 1, [var, expr]} end)

            {bound_place, arg_bindings} = decompose_macro_place(place_node, "pushnew")

            all_bindings =
              [{:list, 1, [item_var, item_node]} | arg_bindings ++ opt_bindings]

            ast =
              {:list, 1,
               [
                 {:id, 1, ["let*"]},
                 {:list, 1, all_bindings},
                 {:list, 1,
                  [
                    {:id, 1, ["setf"]},
                    bound_place,
                    {:list, 1, [{:id, 1, ["adjoin"]}, item_var, bound_place | opt_vars]}
                  ]}
               ]}

            compile_expr(ast, local_env)

          _ ->
            {:atom, 1, nil}
        end

      name when name in [:remf, :_cl_remf_] ->
        case args do
          [place_node, indicator_node | _] ->
            ind_var = {:id, 1, ["__remf_ind_#{System.unique_integer([:positive, :monotonic])}"]}
            tmp_res = {:id, 1, ["__remf_res_#{System.unique_integer([:positive, :monotonic])}"]}

            tmp_plist =
              {:id, 1, ["__remf_plist_#{System.unique_integer([:positive, :monotonic])}"]}

            tmp_removed =
              {:id, 1, ["__remf_rem_#{System.unique_integer([:positive, :monotonic])}"]}

            case place_node do
              {:list, pos, [acc_op | acc_args]} ->
                arg_vars =
                  Enum.map(acc_args, fn _ ->
                    {:id, 1, ["__remf_arg_#{System.unique_integer([:positive, :monotonic])}"]}
                  end)

                arg_bindings =
                  Enum.zip(arg_vars, acc_args)
                  |> Enum.map(fn {var, expr} -> {:list, 1, [var, expr]} end)

                bound_target = {:list, pos, [acc_op | arg_vars]}

                all_bindings =
                  arg_bindings ++
                    [{:list, 1, [ind_var, indicator_node]}] ++
                    [
                      {:list, 1,
                       [
                         tmp_res,
                         {:list, 1,
                          [
                            {:id, 1, ["_cl_rem_plist_"]},
                            bound_target,
                            ind_var
                          ]}
                       ]},
                      {:list, 1, [tmp_plist, {:list, 1, [{:id, 1, ["car"]}, tmp_res]}]},
                      {:list, 1, [tmp_removed, {:list, 1, [{:id, 1, ["cadr"]}, tmp_res]}]}
                    ]

                ast =
                  {:list, 1,
                   [
                     {:id, 1, ["let*"]},
                     {:list, 1, all_bindings},
                     {:list, 1, [{:id, 1, ["setf"]}, bound_target, tmp_plist]},
                     tmp_removed
                   ]}

                compile_expr(ast, local_env)

              _ ->
                all_bindings =
                  [{:list, 1, [ind_var, indicator_node]}] ++
                    [
                      {:list, 1,
                       [
                         tmp_res,
                         {:list, 1,
                          [
                            {:id, 1, ["_cl_rem_plist_"]},
                            place_node,
                            ind_var
                          ]}
                       ]},
                      {:list, 1, [tmp_plist, {:list, 1, [{:id, 1, ["car"]}, tmp_res]}]},
                      {:list, 1, [tmp_removed, {:list, 1, [{:id, 1, ["cadr"]}, tmp_res]}]}
                    ]

                ast =
                  {:list, 1,
                   [
                     {:id, 1, ["let*"]},
                     {:list, 1, all_bindings},
                     {:list, 1, [{:id, 1, ["setf"]}, place_node, tmp_plist]},
                     tmp_removed
                   ]}

                compile_expr(ast, local_env)
            end

          _ ->
            {:atom, 1, nil}
        end

      name when name in [:pop, :_cl_pop_] ->
        case args do
          [place_node | _] ->
            uid = System.unique_integer([:positive, :monotonic])
            tmp_val = {:id, 1, ["__pop_val_#{uid}"]}
            {bound_place, arg_bindings} = decompose_macro_place(place_node, "pop")

            ast =
              {:list, 1,
               [
                 {:id, 1, ["let*"]},
                 {:list, 1,
                  arg_bindings ++
                    [{:list, 1, [tmp_val, {:list, 1, [{:id, 1, ["car"]}, bound_place]}]}]},
                 {:list, 1,
                  [
                    {:id, 1, ["setf"]},
                    bound_place,
                    {:list, 1, [{:id, 1, ["cdr"]}, bound_place]}
                  ]},
                 tmp_val
               ]}

            compile_expr(ast, local_env)

          _ ->
            {:atom, 1, nil}
        end

      name when name in [:incf, :_cl_incf_] ->
        case args do
          [place_node] ->
            compile_setf(
              [place_node, {:list, 1, [{:id, 1, ["+"]}, place_node, {:lit, 1}]}],
              local_env
            )

          [place_node, delta_node | _] ->
            compile_setf(
              [place_node, {:list, 1, [{:id, 1, ["+"]}, place_node, delta_node]}],
              local_env
            )

          _ ->
            {:atom, 1, nil}
        end

      name when name in [:decf, :_cl_decf_] ->
        case args do
          [place_node] ->
            compile_setf(
              [place_node, {:list, 1, [{:id, 1, ["-"]}, place_node, {:lit, 1}]}],
              local_env
            )

          [place_node, delta_node | _] ->
            compile_setf(
              [place_node, {:list, 1, [{:id, 1, ["-"]}, place_node, delta_node]}],
              local_env
            )

          _ ->
            {:atom, 1, nil}
        end

      name when name in [:case, :_cl_case_] ->
        compile_case(args, local_env)

      name when name in [:ecase, :_cl_ecase_, :ccase, :_cl_ccase_] ->
        compile_ecase(args, local_env)

      name when name in [:typecase, :_cl_typecase_] ->
        compile_typecase(args, local_env)

      name when name in [:etypecase, :_cl_etypecase_, :ctypecase, :_cl_ctypecase_] ->
        compile_etypecase(args, local_env)

      _ ->
        case op do
          {:list, _pos, _} ->
            compiled_fn = compile_expr(op, local_env)
            compiled_args = Enum.map(args, &compile_expr(&1, local_env))
            {:call, 1, compiled_fn, compiled_args}

          _ ->
            compile_regular_op(op, args, local_env)
        end
    end
  end

  # --- Quote compilation ---

  def compile_quote(ast) do
    case ast do
      {:lit, val} when is_integer(val) ->
        {:integer, 1, val}

      {:lit, _pos, val} when is_integer(val) ->
        {:integer, 1, val}

      {:lit, val} when is_float(val) ->
        {:float, 1, val}

      {:lit, _pos, val} when is_float(val) ->
        {:float, 1, val}

      {:lit, val} when is_binary(val) ->
        {:bin, 1,
         [{:bin_element, 1, {:string, 1, :erlang.binary_to_list(val)}, :default, :default}]}

      {:lit, _pos, val} when is_binary(val) ->
        {:bin, 1,
         [{:bin_element, 1, {:string, 1, :erlang.binary_to_list(val)}, :default, :default}]}

      {:lit, val} when is_atom(val) ->
        case val do
          nil ->
            {:atom, 1, nil}

          :t ->
            {:atom, 1, :t}

          :T ->
            {:atom, 1, :t}

          _ ->
            str = Atom.to_string(val)

            if String.starts_with?(str, ":") do
              {:atom, 1, val}
            else
              {:atom, 1, str |> String.downcase() |> String.to_atom()}
            end
        end

      {:lit, _pos, val} when is_atom(val) ->
        case val do
          nil ->
            {:atom, 1, nil}

          :t ->
            {:atom, 1, :t}

          :T ->
            {:atom, 1, :t}

          _ ->
            str = Atom.to_string(val)

            if String.starts_with?(str, ":") do
              {:atom, 1, val}
            else
              {:atom, 1, str |> String.downcase() |> String.to_atom()}
            end
        end

      {:keyword, _pos, val} ->
        {:atom, 1, val}

      {:id, _pos, parts} ->
        sym_str = Enum.join(parts, ".")
        atom = normalize_quote_symbol(sym_str)
        {:atom, 1, atom}

      {:vector, _pos, elements} ->
        {:call, 1, {:remote, 1, {:atom, 1, ExLisp.Builtins}, {:atom, 1, :vector}},
         [ast_cons_list(Enum.map(elements, &compile_quote/1))]}

      {:list, _pos, elements} ->
        ast_cons_list(Enum.map(elements, &compile_quote/1))

      {:dotted_list, _pos, elements, tail} ->
        ast_cons_list(Enum.map(elements, &compile_quote/1), compile_quote(tail))

      {:quoted, _pos, elements} when is_list(elements) ->
        ast_cons_list(Enum.map(elements, &compile_quote/1))

      {:quoted, _pos, element} ->
        compile_quote(element)

      [] ->
        {nil, 1}

      val when is_integer(val) ->
        {:integer, 1, val}

      val when is_float(val) ->
        {:float, 1, val}

      val when is_binary(val) ->
        {:bin, 1,
         [{:bin_element, 1, {:string, 1, :erlang.binary_to_list(val)}, :default, :default}]}

      val when is_atom(val) ->
        {:atom, 1, val}

      other ->
        compile_expr(other, MapSet.new())
    end
  end

  defp normalize_quote_symbol(str) do
    cond do
      String.starts_with?(str, "|") ->
        String.to_atom(str)

      String.starts_with?(str, ":|") ->
        String.to_atom(str)

      String.starts_with?(str, "#:UNINTERNED_") ->
        String.to_atom(str)

      true ->
        down = String.downcase(str)

        case down do
          "nil" ->
            nil

          "t" ->
            :t

          "_cl_1plus_" ->
            :"1+"

          "_cl_1minus_" ->
            :"1-"

          "_cl_lt_" ->
            :<

          "_cl_lte_" ->
            :<=

          "_cl_gt_" ->
            :>

          "_cl_gte_" ->
            :>=

          "_cl_string_eq_" ->
            :"string="

          "_cl_string_neq_" ->
            :"string/="

          "_cl_string_lt_" ->
            :"string<"

          "_cl_string_lte_" ->
            :"string<="

          "_cl_string_gt_" ->
            :"string>"

          "_cl_string_gte_" ->
            :"string>="

          "_cl_char_eq_" ->
            :"char="

          "_cl_char_neq_" ->
            :"char/="

          "_cl_char_lt_" ->
            :"char<"

          "_cl_char_lte_" ->
            :"char<="

          "_cl_char_gt_" ->
            :"char>"

          "_cl_char_gte_" ->
            :"char>="

          "_cl_list_star_" ->
            :"list*"

          _ ->
            String.to_atom(down)
        end
    end
  end

  # --- Function forms (#') ---

  defp compile_function_form(args, local_env) do
    case args do
      [{:list, _pos, [lambda_op | lambda_args]}] ->
        if extract_op_name(lambda_op) == :lambda do
          compile_lambda(lambda_args, local_env)
        else
          compile_function_symbol(lambda_op, local_env)
        end

      [fn_node] ->
        compile_function_symbol(fn_node, local_env)

      _ ->
        {:atom, 1, nil}
    end
  end

  defp compile_function_symbol(fn_node, local_env) do
    fn_name = extract_symbol_name(fn_node)

    if is_atom(fn_name) and
         (MapSet.member?(local_env, fn_name) or
            MapSet.member?(local_env, {:direct_fn, fn_name}) or
            MapSet.member?(local_env, {:closure_fn, fn_name})) do
      {:var, 1, erl_var_name(fn_name)}
    else
      canonical =
        case BuiltinFunction.canonical_name(fn_name) do
          {:ok, c} -> c
          :error -> fn_name
        end

      {:atom, 1, canonical}
    end
  end

  # --- Control structures ---

  def compile_if([test_node, then_node | rest], local_env) do
    else_node = Enum.at(rest, 0, {:lit, nil})
    else_expr = compile_expr(else_node, local_env)
    then_expr = compile_expr(then_node, local_env)

    {:case, 1,
     {:call, 1, {:remote, 1, {:atom, 1, ExLisp.Builtins}, {:atom, 1, :truthy?}},
      [compile_expr(test_node, local_env)]},
     [
       {:clause, 1, [{:atom, 1, false}], [], [else_expr]},
       {:clause, 1, [{:atom, 1, true}], [], [then_expr]}
     ]}
  end

  def compile_if([test_node], local_env) do
    compile_if([test_node, {:lit, nil}], local_env)
  end

  def compile_when([test_node | body_nodes], local_env) do
    then_expr =
      case body_nodes do
        [] -> {:atom, 1, nil}
        [single] -> compile_expr(single, local_env)
        _ -> {:block, 1, Enum.map(body_nodes, &compile_expr(&1, local_env))}
      end

    {:case, 1,
     {:call, 1, {:remote, 1, {:atom, 1, ExLisp.Builtins}, {:atom, 1, :truthy?}},
      [compile_expr(test_node, local_env)]},
     [
       {:clause, 1, [{:atom, 1, false}], [], [{:atom, 1, nil}]},
       {:clause, 1, [{:atom, 1, true}], [], [then_expr]}
     ]}
  end

  def compile_unless([test_node | body_nodes], local_env) do
    then_expr =
      case body_nodes do
        [] -> {:atom, 1, nil}
        [single] -> compile_expr(single, local_env)
        _ -> {:block, 1, Enum.map(body_nodes, &compile_expr(&1, local_env))}
      end

    {:case, 1,
     {:call, 1, {:remote, 1, {:atom, 1, ExLisp.Builtins}, {:atom, 1, :truthy?}},
      [compile_expr(test_node, local_env)]},
     [
       {:clause, 1, [{:atom, 1, false}], [], [then_expr]},
       {:clause, 1, [{:atom, 1, true}], [], [{:atom, 1, nil}]}
     ]}
  end

  def compile_cond(clauses, local_env) do
    case clauses do
      [] ->
        {:atom, 1, nil}

      [clause | rest_clauses] ->
        case clause do
          {:list, _pos, [test_node | body_nodes]} ->
            test_op = extract_symbol_name(test_node)

            if test_op in [:t, :T] do
              case body_nodes do
                [] -> {:atom, 1, :t}
                [single] -> compile_expr(single, local_env)
                _ -> {:block, 1, Enum.map(body_nodes, &compile_expr(&1, local_env))}
              end
            else
              rest_compiled = compile_cond(rest_clauses, local_env)

              case body_nodes do
                [] ->
                  temp_var = :"V_cond_#{System.unique_integer([:positive, :monotonic])}"

                  {:block, 1,
                   [
                     {:match, 1, {:var, 1, temp_var}, compile_expr(test_node, local_env)},
                     {:case, 1,
                      {:call, 1, {:remote, 1, {:atom, 1, ExLisp.Builtins}, {:atom, 1, :truthy?}},
                       [{:var, 1, temp_var}]},
                      [
                        {:clause, 1, [{:atom, 1, false}], [], [rest_compiled]},
                        {:clause, 1, [{:atom, 1, true}], [],
                         [
                           {:call, 1,
                            {:remote, 1, {:atom, 1, ExLisp.Builtins},
                             {:atom, 1, :unwrap_mv_primary}}, [{:var, 1, temp_var}]}
                         ]}
                      ]}
                   ]}

                _ ->
                  then_body =
                    case body_nodes do
                      [single] -> compile_expr(single, local_env)
                      _ -> {:block, 1, Enum.map(body_nodes, &compile_expr(&1, local_env))}
                    end

                  {:case, 1,
                   {:call, 1, {:remote, 1, {:atom, 1, ExLisp.Builtins}, {:atom, 1, :truthy?}},
                    [compile_expr(test_node, local_env)]},
                   [
                     {:clause, 1, [{:atom, 1, false}], [], [rest_compiled]},
                     {:clause, 1, [{:atom, 1, true}], [], [then_body]}
                   ]}
              end
            end

          _ ->
            {:atom, 1, nil}
        end
    end
  end

  def compile_case([key_node | clauses], local_env) do
    key_var_sym = :"__case_key_#{System.unique_integer([:positive, :monotonic])}"
    key_var_str = Atom.to_string(key_var_sym)
    key_var_ast = {:id, 1, [key_var_str]}

    cond_clauses =
      Enum.map(clauses, fn
        {:list, _pos, [keys_spec | body_nodes]} ->
          clause_body = if body_nodes == [], do: [{:lit, nil}], else: body_nodes

          case keys_spec do
            {:id, _pos2, [name]} when name in ["t", "otherwise"] ->
              {:list, 1, [{:id, 1, ["t"]} | clause_body]}

            {:lit, name} when name in [:t, :otherwise] ->
              {:list, 1, [{:id, 1, ["t"]} | clause_body]}

            {:id, _pos2, ["nil"]} ->
              {:list, 1, [{:lit, nil} | clause_body]}

            {:lit, nil} ->
              {:list, 1, [{:lit, nil} | clause_body]}

            {:list, _pos2, key_list} ->
              tests =
                Enum.map(key_list, fn
                  {:lit, s} when is_binary(s) ->
                    {:lit, nil}

                  s when is_binary(s) ->
                    {:lit, nil}

                  k ->
                    {:list, 1,
                     [{:id, 1, ["eql"]}, key_var_ast, {:list, 1, [{:id, 1, ["quote"]}, k]}]}
                end)

              case_test =
                case tests do
                  [] -> {:lit, nil}
                  [single_test] -> single_test
                  multiple -> {:list, 1, [{:id, 1, ["or"]} | multiple]}
                end

              {:list, 1, [case_test | clause_body]}

            {:lit, s} when is_binary(s) ->
              {:list, 1, [{:lit, nil} | clause_body]}

            s when is_binary(s) ->
              {:list, 1, [{:lit, nil} | clause_body]}

            single_key ->
              case_test =
                {:list, 1,
                 [
                   {:id, 1, ["eql"]},
                   key_var_ast,
                   {:list, 1, [{:id, 1, ["quote"]}, single_key]}
                 ]}

              {:list, 1, [case_test | clause_body]}
          end

        clause ->
          clause
      end)

    compile_expr(
      {:list, 1,
       [
         {:id, 1, ["let*"]},
         {:list, 1,
          [{:list, 1, [key_var_ast, {:list, 1, [{:id, 1, ["nth-value"]}, {:lit, 0}, key_node]}]}]},
         {:list, 1, [{:id, 1, ["cond"]} | cond_clauses]}
       ]},
      local_env
    )
  end

  def compile_case([], _local_env), do: {:atom, 1, nil}

  def compile_ecase([key_node | clauses], local_env) do
    err_clause =
      {:list, 1,
       [
         {:id, 1, ["t"]},
         {:list, 1, [{:id, 1, ["error"]}, {:lit, "No case match"}]}
       ]}

    compile_case([key_node | clauses ++ [err_clause]], local_env)
  end

  def compile_ecase([], _local_env), do: {:atom, 1, nil}

  def compile_typecase([key_node | clauses], local_env) do
    key_var_sym = :"__typecase_key_#{System.unique_integer([:positive, :monotonic])}"
    key_var_str = Atom.to_string(key_var_sym)
    key_var_ast = {:id, 1, [key_var_str]}

    cond_clauses =
      Enum.map(clauses, fn
        {:list, _pos, [type_spec | body_nodes]} ->
          type_name = extract_symbol_name(type_spec)

          if type_name in [:t, :otherwise, :_] do
            {:list, 1, [{:id, 1, ["t"]} | body_nodes]}
          else
            type_test =
              {:list, 1,
               [
                 {:id, 1, ["typep"]},
                 key_var_ast,
                 {:list, 1, [{:id, 1, ["quote"]}, type_spec]}
               ]}

            {:list, 1, [type_test | body_nodes]}
          end

        clause ->
          clause
      end)

    compile_expr(
      {:list, 1,
       [
         {:id, 1, ["let*"]},
         {:list, 1, [{:list, 1, [key_var_ast, key_node]}]},
         {:list, 1, [{:id, 1, ["cond"]} | cond_clauses]}
       ]},
      local_env
    )
  end

  def compile_typecase([], _local_env), do: {:atom, 1, nil}

  def compile_etypecase([key_node | clauses], local_env) do
    err_clause =
      {:list, 1,
       [
         {:id, 1, ["t"]},
         {:list, 1, [{:id, 1, ["error"]}, {:lit, "No typecase match"}]}
       ]}

    compile_typecase([key_node | clauses ++ [err_clause]], local_env)
  end

  def compile_etypecase([], _local_env), do: {:atom, 1, nil}

  def compile_progn(forms, local_env) do
    case forms do
      [] -> {:atom, 1, nil}
      [single] -> compile_expr(single, local_env)
      _ -> {:block, 1, Enum.map(forms, &compile_expr(&1, local_env))}
    end
  end

  def compile_prog1([first | rest], local_env) do
    temp_var = :"V_prog1_#{System.unique_integer([:positive, :monotonic])}"
    compiled_first = compile_expr(first, local_env)
    compiled_rest = Enum.map(rest, &compile_expr(&1, local_env))

    primary_call =
      {:call, 1, {:remote, 1, {:atom, 1, ExLisp.Builtins}, {:atom, 1, :primary_val}},
       [{:var, 1, temp_var}]}

    {:block, 1,
     [{:match, 1, {:var, 1, temp_var}, compiled_first}] ++
       compiled_rest ++
       [primary_call]}
  end

  def compile_prog1([], _local_env), do: {:atom, 1, nil}

  def compile_prog2([first, second | rest], local_env) do
    temp_var = :"V_prog2_#{System.unique_integer([:positive, :monotonic])}"
    compiled_first = compile_expr(first, local_env)
    compiled_second = compile_expr(second, local_env)
    compiled_rest = Enum.map(rest, &compile_expr(&1, local_env))

    primary_call =
      {:call, 1, {:remote, 1, {:atom, 1, ExLisp.Builtins}, {:atom, 1, :primary_val}},
       [{:var, 1, temp_var}]}

    {:block, 1,
     [compiled_first, {:match, 1, {:var, 1, temp_var}, compiled_second}] ++
       compiled_rest ++
       [primary_call]}
  end

  def compile_prog2([first], local_env) do
    {:call, 1, {:remote, 1, {:atom, 1, ExLisp.Builtins}, {:atom, 1, :primary_val}},
     [compile_expr(first, local_env)]}
  end

  def compile_prog2([], _local_env), do: {:atom, 1, nil}

  def compile_locally(args, local_env) do
    {decls, body_nodes} = split_declarations(args)
    specials = extract_special_vars(decls)
    new_local_env = Enum.reduce(specials, local_env, &MapSet.delete(&2, &1))
    compile_progn(body_nodes, new_local_env)
  end

  # --- Variable binding (let, let*) ---

  def compile_let([bindings_node | body_nodes], local_env) do
    bindings = extract_bindings(bindings_node)
    {decls, actual_body_nodes} = split_declarations(body_nodes)
    specials = extract_special_vars(decls)
    mutated = find_mutated_vars([bindings_node | actual_body_nodes])

    compiled_vals =
      Enum.map(bindings, fn {_var, val_expr} ->
        compile_expr(val_expr, local_env)
      end)

    var_names = Enum.map(bindings, &elem(&1, 0))
    lexical_vars = Enum.reject(var_names, &(&1 in specials))

    new_local_env =
      Enum.reduce(lexical_vars, local_env, fn v, acc ->
        acc = acc |> MapSet.delete(v) |> MapSet.delete({:mutated, v})

        if MapSet.member?(mutated, v) do
          MapSet.put(acc, {:mutated, v})
        else
          MapSet.put(acc, v)
        end
      end)

    special_bindings =
      Enum.flat_map(bindings, fn {v, _val_expr} ->
        if v in specials do
          [{:tuple, 1, [{:atom, 1, v}, {:var, 1, erl_var_name(v)}]}]
        else
          []
        end
      end)

    raw_body =
      case actual_body_nodes do
        [] -> [{:atom, 1, nil}]
        _ -> Enum.map(actual_body_nodes, &compile_expr(&1, new_local_env))
      end

    compiled_body =
      if special_bindings != [] do
        bindings_list_ast = ast_cons_list(special_bindings)

        with_specials_call =
          {:call, 1, {:remote, 1, {:atom, 1, ExLisp.Env}, {:atom, 1, :with_special_bindings}},
           [
             bindings_list_ast,
             {:fun, 1, {:clauses, [{:clause, 1, [], [], raw_body}]}}
           ]}

        [with_specials_call]
      else
        raw_body
      end

    mutated_vars = Enum.filter(lexical_vars, &MapSet.member?(mutated, &1))

    init_erases =
      Enum.map(mutated_vars, fn v ->
        {:call, 1, {:remote, 1, {:atom, 1, :erlang}, {:atom, 1, :erase}}, [{:atom, 1, v}]}
      end)

    body_with_try =
      if init_erases != [] do
        [{:try, 1, compiled_body, [], [], init_erases}]
      else
        compiled_body
      end

    erl_params = Enum.map(var_names, fn v -> {:var, 1, erl_var_name(v)} end)

    {:call, 1, {:fun, 1, {:clauses, [{:clause, 1, erl_params, [], body_with_try}]}},
     compiled_vals}
  end

  def compile_let([], _local_env), do: {:atom, 1, nil}

  def compile_symbol_macrolet([bindings_node | body_nodes], local_env) do
    bindings = extract_bindings(bindings_node)
    macro_map = Map.new(bindings)
    expanded_body = Enum.map(body_nodes, &substitute_symbol_macros(&1, macro_map))
    compile_progn(expanded_body, local_env)
  end

  def compile_symbol_macrolet([], _local_env), do: {:atom, 1, nil}

  defp substitute_symbol_macros(ast, macro_map) when map_size(macro_map) == 0, do: ast

  defp substitute_symbol_macros({:id, _pos, [name]} = ast, macro_map) do
    sym = extract_symbol_name(name)

    case Map.fetch(macro_map, sym) do
      {:ok, expansion} -> expansion
      :error -> ast
    end
  end

  defp substitute_symbol_macros({:id, _pos, parts} = ast, macro_map) when is_list(parts) do
    sym = Enum.join(parts, ".") |> extract_symbol_name()

    case Map.fetch(macro_map, sym) do
      {:ok, expansion} -> expansion
      :error -> ast
    end
  end

  defp substitute_symbol_macros({:list, pos, [op | args] = elements}, macro_map) do
    op_sym = extract_symbol_name(op)

    case op_sym do
      :quote ->
        {:list, pos, elements}

      name when name in [:let, :"let*", :_cl_let_star_] ->
        case args do
          [bindings_node | body] ->
            bound_syms = extract_bindings(bindings_node) |> Enum.map(&elem(&1, 0))
            inner_macro_map = Map.drop(macro_map, bound_syms)

            expanded_bindings =
              case bindings_node do
                {:list, b_pos, b_elems} ->
                  {:list, b_pos,
                   Enum.map(b_elems, fn
                     {:list, p, [v, val | r]} ->
                       {:list, p, [v, substitute_symbol_macros(val, macro_map) | r]}

                     other ->
                       other
                   end)}

                other ->
                  other
              end

            expanded_body = Enum.map(body, &substitute_symbol_macros(&1, inner_macro_map))
            {:list, pos, [op, expanded_bindings | expanded_body]}

          _ ->
            {:list, pos, Enum.map(elements, &substitute_symbol_macros(&1, macro_map))}
        end

      _ ->
        {:list, pos, Enum.map(elements, &substitute_symbol_macros(&1, macro_map))}
    end
  end

  defp substitute_symbol_macros({:list, pos, elements}, macro_map) do
    {:list, pos, Enum.map(elements, &substitute_symbol_macros(&1, macro_map))}
  end

  defp substitute_symbol_macros({:quoted, pos, elements}, macro_map) when is_list(elements) do
    {:quoted, pos, Enum.map(elements, &substitute_symbol_macros(&1, macro_map))}
  end

  defp substitute_symbol_macros(other, _macro_map), do: other

  def compile_let_star([bindings_node | body_nodes], local_env) do
    bindings = extract_bindings(bindings_node)
    {decls, actual_body_nodes} = split_declarations(body_nodes)
    specials = extract_special_vars(decls)
    mutated = find_mutated_vars([bindings_node | actual_body_nodes])
    var_names = Enum.map(bindings, &elem(&1, 0))
    mutated_vars = Enum.filter(var_names, &MapSet.member?(mutated, &1))

    init_erases =
      Enum.map(mutated_vars, fn v ->
        {:call, 1, {:remote, 1, {:atom, 1, :erlang}, {:atom, 1, :erase}}, [{:atom, 1, v}]}
      end)

    chained = compile_let_star_chain(bindings, actual_body_nodes, local_env, specials, mutated)

    if init_erases != [] do
      {:try, 1, [chained], [], [], init_erases}
    else
      chained
    end
  end

  def compile_let_star([], _local_env), do: {:atom, 1, nil}

  defp compile_let_star_chain([], body_nodes, local_env, _specials, _mutated) do
    case body_nodes do
      [] -> {:atom, 1, nil}
      [single] -> compile_expr(single, local_env)
      _ -> {:block, 1, Enum.map(body_nodes, &compile_expr(&1, local_env))}
    end
  end

  defp compile_let_star_chain(
         [{var_name, val_expr} | rest_bindings],
         body_nodes,
         local_env,
         specials,
         mutated
       ) do
    compiled_val = compile_expr(val_expr, local_env)

    new_local_env =
      cond do
        var_name in specials ->
          local_env |> MapSet.delete(var_name) |> MapSet.delete({:mutated, var_name})

        MapSet.member?(mutated, var_name) ->
          local_env |> MapSet.delete(var_name) |> MapSet.put({:mutated, var_name})

        true ->
          local_env |> MapSet.delete({:mutated, var_name}) |> MapSet.put(var_name)
      end

    rest_compiled =
      compile_let_star_chain(rest_bindings, body_nodes, new_local_env, specials, mutated)

    clause_body =
      if var_name in specials do
        bindings_list_ast =
          {:cons, 1, {:tuple, 1, [{:atom, 1, var_name}, {:var, 1, erl_var_name(var_name)}]},
           {nil, 1}}

        with_specials_call =
          {:call, 1, {:remote, 1, {:atom, 1, ExLisp.Env}, {:atom, 1, :with_special_bindings}},
           [
             bindings_list_ast,
             {:fun, 1, {:clauses, [{:clause, 1, [], [], [rest_compiled]}]}}
           ]}

        [with_specials_call]
      else
        [rest_compiled]
      end

    {:call, 1,
     {:fun, 1, {:clauses, [{:clause, 1, [{:var, 1, erl_var_name(var_name)}], [], clause_body}]}},
     [compiled_val]}
  end

  defp split_declarations(forms) do
    Enum.split_while(forms, fn
      {:list, _pos, [{:id, _pos2, [name]} | _]} ->
        String.downcase(name) == "declare"

      [:declare | _] ->
        true

      _ ->
        false
    end)
  end

  defp find_mutated_vars(asts) when is_list(asts) do
    Enum.reduce(asts, MapSet.new(), fn ast, acc ->
      MapSet.union(acc, find_mutated_vars(ast))
    end)
  end

  defp find_mutated_vars({:list, _pos, [op | args] = elements}) do
    op_name = extract_symbol_name(op)

    this_mutated =
      case op_name do
        name when name in [:symbol_macrolet, :"symbol-macrolet", :_cl_symbol_macrolet_] ->
          case args do
            [bindings_node | body] ->
              bindings = extract_bindings(bindings_node)
              macro_map = Map.new(bindings)
              expanded_body = Enum.map(body, &substitute_symbol_macros(&1, macro_map))
              find_mutated_vars(expanded_body)

            _ ->
              MapSet.new()
          end

        name
        when name in [
               :setq,
               :_cl_setq_,
               :setf,
               :_cl_setf_,
               :psetq,
               :_cl_psetq_,
               :psetf,
               :_cl_psetf_
             ] ->
          Enum.chunk_every(args, 2)
          |> Enum.flat_map(fn
            [place | _] -> extract_place_vars(place)
            _ -> []
          end)
          |> MapSet.new()

        name
        when name in [
               :incf,
               :_cl_incf_,
               :decf,
               :_cl_decf_,
               :pop,
               :_cl_pop_,
               :remf,
               :_cl_remf_
             ] ->
          case args do
            [place | _] ->
              extract_place_vars(place) |> MapSet.new()

            _ ->
              MapSet.new()
          end

        name when name in [:push, :_cl_push_, :pushnew, :_cl_pushnew_] ->
          case args do
            [_, place | _] ->
              extract_place_vars(place) |> MapSet.new()

            _ ->
              MapSet.new()
          end

        name
        when name in [
               :multiple_value_setq,
               :"multiple-value-setq",
               :_cl_multiple_value_setq_
             ] ->
          case args do
            [{:list, _, vars} | _] ->
              Enum.flat_map(vars, &extract_place_vars/1)
              |> MapSet.new()

            _ ->
              MapSet.new()
          end

        name when name in [:rotatef, :_cl_rotatef_] ->
          Enum.flat_map(args, &extract_place_vars/1)
          |> MapSet.new()

        name when name in [:shiftf, :_cl_shiftf_] ->
          if length(args) > 1 do
            Enum.slice(args, 0..-2//1)
            |> Enum.flat_map(&extract_place_vars/1)
            |> MapSet.new()
          else
            MapSet.new()
          end

        _ ->
          MapSet.new()
      end

    Enum.reduce(elements, this_mutated, fn child, acc ->
      MapSet.union(acc, find_mutated_vars(child))
    end)
  end

  defp find_mutated_vars({:quoted, _pos, elements}) do
    find_mutated_vars(elements)
  end

  defp find_mutated_vars(_), do: MapSet.new()

  defp extract_place_vars(node) do
    case node do
      {:id, _pos, [name]} ->
        sym = extract_symbol_name(name)
        if is_atom(sym) and sym not in [nil, :t], do: [sym], else: []

      {:id, _pos, parts} when is_list(parts) ->
        sym = Enum.join(parts, ".") |> extract_symbol_name()
        if is_atom(sym) and sym not in [nil, :t], do: [sym], else: []

      {:list, _pos, [_op | place_args]} ->
        Enum.flat_map(place_args, &extract_place_vars/1)

      _ ->
        []
    end
  end

  defp extract_special_vars(decls) do
    Enum.flat_map(decls, fn
      {:list, _pos, [{:id, _pos2, _} | decl_clauses]} ->
        Enum.flat_map(decl_clauses, fn
          {:list, _pos3, [{:id, _pos4, [name]} | vars]} ->
            if String.downcase(name) == "special" do
              Enum.map(vars, &extract_symbol_name/1)
            else
              []
            end

          _ ->
            []
        end)

      [:declare | decl_clauses] ->
        Enum.flat_map(decl_clauses, fn
          [:special | vars] ->
            Enum.map(vars, fn
              v when is_atom(v) -> v
              {:id, _, [n]} -> String.to_atom(String.downcase(n))
              _ -> nil
            end)
            |> Enum.reject(&is_nil/1)

          _ ->
            []
        end)

      _ ->
        []
    end)
  end

  defp extract_bindings({:list, _pos, elements}),
    do: elements |> Enum.reject(&(&1 in [nil, {:lit, nil}])) |> Enum.map(&parse_single_binding/1)

  defp extract_bindings({:quoted, _pos, elements}),
    do: elements |> Enum.reject(&(&1 in [nil, {:lit, nil}])) |> Enum.map(&parse_single_binding/1)

  defp extract_bindings(elements) when is_list(elements),
    do: elements |> Enum.reject(&(&1 in [nil, {:lit, nil}])) |> Enum.map(&parse_single_binding/1)

  defp extract_bindings(_), do: []

  defp parse_single_binding({:list, _pos, [var_node, val_node | _]}) do
    {extract_symbol_name(var_node), val_node}
  end

  defp parse_single_binding({:list, _pos, [var_node]}) do
    {extract_symbol_name(var_node), {:atom, 1, nil}}
  end

  defp parse_single_binding({:quoted, _pos, [var_node, val_node | _]}) do
    {extract_symbol_name(var_node), val_node}
  end

  defp parse_single_binding({:quoted, _pos, [var_node]}) do
    {extract_symbol_name(var_node), {:atom, 1, nil}}
  end

  defp parse_single_binding(var_node) do
    {extract_symbol_name(var_node), {:atom, 1, nil}}
  end

  # --- Local functions (flet, labels) ---

  def compile_flet([bindings_node | body_nodes], local_env) do
    fn_defs = extract_fn_bindings(bindings_node)

    fun_exprs =
      Enum.map(fn_defs, fn {fn_name, params_node, fn_body_nodes} ->
        {decls, actual_fn_body} = split_declarations(fn_body_nodes)
        specials = extract_special_vars(decls)

        if has_lambda_list_keywords?(params_node) do
          raw_args_sym = :__fn_args__
          {bindings, _} = ExLisp.Macro.build_bindings(params_node, raw_args_sym, raw_args_sym)

          let_star_body =
            {:list, 1,
             [
               {:id, 1, ["let*"]},
               {:list, 1, bindings}
             ] ++
               decls ++
               [
                 {:list, 1,
                  [{:id, 1, ["block"]}, {:id, 1, [Atom.to_string(fn_name)]} | actual_fn_body]}
               ]}

          fn_local_env = MapSet.put(local_env, raw_args_sym)
          compiled_body = [compile_expr(let_star_body, fn_local_env)]

          raw_fun =
            {:fun, 1,
             {:clauses,
              [{:clause, 1, [{:var, 1, erl_var_name(raw_args_sym)}], [], compiled_body}]}}

          {:call, 1, {:remote, 1, {:atom, 1, ExLisp.Closure}, {:atom, 1, :new}},
           [raw_fun, {:atom, 1, fn_name}]}
        else
          param_names = extract_param_names(params_node)
          lexical_params = Enum.reject(param_names, &(&1 in specials))
          fn_local_env = MapSet.union(local_env, MapSet.new(lexical_params))

          special_bindings =
            Enum.flat_map(param_names, fn p ->
              if p in specials do
                [{:tuple, 1, [{:atom, 1, p}, {:var, 1, erl_var_name(p)}]}]
              else
                []
              end
            end)

          raw_fn_body =
            case actual_fn_body do
              [] -> [{:atom, 1, nil}]
              _ -> [compile_block([{:atom, 1, fn_name} | actual_fn_body], fn_local_env)]
            end

          compiled_fn_body =
            if special_bindings != [] do
              bindings_list_ast = ast_cons_list(special_bindings)

              with_specials_call =
                {:call, 1,
                 {:remote, 1, {:atom, 1, ExLisp.Env}, {:atom, 1, :with_special_bindings}},
                 [
                   bindings_list_ast,
                   {:fun, 1, {:clauses, [{:clause, 1, [], [], raw_fn_body}]}}
                 ]}

              [with_specials_call]
            else
              raw_fn_body
            end

          erl_params = Enum.map(param_names, fn p -> {:var, 1, erl_var_name(p)} end)
          {:fun, 1, {:clauses, [{:clause, 1, erl_params, [], compiled_fn_body}]}}
        end
      end)

    fn_names = Enum.map(fn_defs, &elem(&1, 0))
    new_local_env =
      Enum.reduce(fn_defs, local_env, fn {name, params_node, _}, env ->
        if has_lambda_list_keywords?(params_node) do
          MapSet.put(env, {:closure_fn, name})
        else
          MapSet.put(env, {:direct_fn, name})
        end
      end)

    {_body_decls, actual_body_nodes} = split_declarations(body_nodes)

    compiled_body =
      case actual_body_nodes do
        [] -> [{:atom, 1, nil}]
        _ -> Enum.map(actual_body_nodes, &compile_expr(&1, new_local_env))
      end

    erl_fn_vars = Enum.map(fn_names, fn name -> {:var, 1, erl_var_name(name)} end)

    {:call, 1, {:fun, 1, {:clauses, [{:clause, 1, erl_fn_vars, [], compiled_body}]}}, fun_exprs}
  end

  def compile_flet([], _local_env), do: {:atom, 1, nil}

  def compile_labels([bindings_node | body_nodes], local_env) do
    fn_defs = extract_fn_bindings(bindings_node)

    case fn_defs do
      [] ->
        case body_nodes do
          [] -> {:atom, 1, nil}
          [single] -> compile_expr(single, local_env)
          _ -> {:block, 1, Enum.map(body_nodes, &compile_expr(&1, local_env))}
        end

      _ ->
        fn_names = Enum.map(fn_defs, &elem(&1, 0))
        all_fn_env = Enum.reduce(fn_names, local_env, &MapSet.put(&2, {:closure_fn, &1}))
        dispatcher_var = :"V_disp_#{System.unique_integer([:positive])}"

        fn_wrappers =
          Enum.map(fn_defs, fn {name, _params_node, _} ->
            args_var = :"V_args_#{System.unique_integer([:positive])}"

            call_dispatcher =
              {:call, 1, {:var, 1, dispatcher_var}, [{:atom, 1, name}, {:var, 1, args_var}]}

            raw_closure_fun =
              {:fun, 1, {:clauses, [{:clause, 1, [{:var, 1, args_var}], [], [call_dispatcher]}]}}

            {:call, 1, {:remote, 1, {:atom, 1, ExLisp.Closure}, {:atom, 1, :new}},
             [raw_closure_fun, {:atom, 1, name}]}
          end)

        dispatcher_clauses =
          Enum.map(fn_defs, fn {name, params_node, fn_body_nodes} ->
            args_var_sym = :"__fn_args_#{System.unique_integer([:positive])}"

            fn_body_ast =
              if has_lambda_list_keywords?(params_node) do
                {bindings, _} =
                  ExLisp.Macro.build_bindings(params_node, args_var_sym, args_var_sym)

                {:list, 1,
                 [
                   {:id, 1, ["let*"]},
                   {:list, 1, bindings},
                   {:list, 1,
                    [{:id, 1, ["block"]}, {:id, 1, [Atom.to_string(name)]} | fn_body_nodes]}
                 ]}
              else
                param_names = extract_param_names(params_node)

                destruct =
                  Enum.with_index(param_names)
                  |> Enum.map(fn {p, idx} ->
                    {:list, 1,
                     [
                       {:id, 1, [Atom.to_string(p)]},
                       {:list, 1,
                        [{:id, 1, ["nth"]}, {:lit, idx}, {:id, 1, [Atom.to_string(args_var_sym)]}]}
                     ]}
                  end)

                {:list, 1,
                 [
                   {:id, 1, ["let*"]},
                   {:list, 1, destruct},
                   {:list, 1,
                    [{:id, 1, ["block"]}, {:id, 1, [Atom.to_string(name)]} | fn_body_nodes]}
                 ]}
              end

            fn_local_env = MapSet.put(all_fn_env, args_var_sym)
            compiled_clause_body = [compile_expr(fn_body_ast, fn_local_env)]

            wrapper_calls =
              {:call, 1,
               {:fun, 1,
                {:clauses,
                 [
                   {:clause, 1, Enum.map(fn_names, fn n -> {:var, 1, erl_var_name(n)} end), [],
                    compiled_clause_body}
                 ]}}, fn_wrappers}

            {:clause, 1, [{:atom, 1, name}, {:var, 1, erl_var_name(args_var_sym)}], [],
             [wrapper_calls]}
          end)

        dispatcher_fun =
          {:named_fun, 1, dispatcher_var, dispatcher_clauses}

        {_body_decls, actual_body_nodes} = split_declarations(body_nodes)

        compiled_body =
          case actual_body_nodes do
            [] -> [{:atom, 1, nil}]
            _ -> Enum.map(actual_body_nodes, &compile_expr(&1, all_fn_env))
          end

        erl_fn_vars = Enum.map(fn_names, fn name -> {:var, 1, erl_var_name(name)} end)

        {:call, 1,
         {:fun, 1,
          {:clauses,
           [
             {:clause, 1, [{:var, 1, dispatcher_var}], [],
              [
                {:call, 1, {:fun, 1, {:clauses, [{:clause, 1, erl_fn_vars, [], compiled_body}]}},
                 fn_wrappers}
              ]}
           ]}}, [dispatcher_fun]}
    end
  end

  def compile_labels([], _local_env), do: {:atom, 1, nil}

  defp extract_fn_bindings({:list, _pos, elements}),
    do: Enum.map(elements, &parse_single_fn_binding/1)

  defp extract_fn_bindings({:quoted, _pos, elements}),
    do: Enum.map(elements, &parse_single_fn_binding/1)

  defp extract_fn_bindings(elements) when is_list(elements),
    do: Enum.map(elements, &parse_single_fn_binding/1)

  defp extract_fn_bindings(_), do: []

  defp parse_single_fn_binding({:list, _pos, [name_node, params_node | body_nodes]}) do
    {extract_symbol_name(name_node), params_node, body_nodes}
  end

  defp parse_single_fn_binding({:quoted, _pos, [name_node, params_node | body_nodes]}) do
    {extract_symbol_name(name_node), params_node, body_nodes}
  end

  defp parse_single_fn_binding([name_node, params_node | body_nodes]) do
    {extract_symbol_name(name_node), params_node, body_nodes}
  end

  defp parse_single_fn_binding({:list, _pos, [name_node]}) do
    {extract_symbol_name(name_node), [], []}
  end

  defp parse_single_fn_binding({:quoted, _pos, [name_node]}) do
    {extract_symbol_name(name_node), [], []}
  end

  defp parse_single_fn_binding([name_node]) do
    {extract_symbol_name(name_node), [], []}
  end

  # --- Logical operations (and, or) ---

  def compile_and([], _local_env), do: {:atom, 1, :t}
  def compile_and([single], local_env), do: compile_expr(single, local_env)

  def compile_and([first | rest], local_env) do
    {:case, 1,
     {:call, 1, {:remote, 1, {:atom, 1, ExLisp.Builtins}, {:atom, 1, :truthy?}},
      [compile_expr(first, local_env)]},
     [
       {:clause, 1, [{:atom, 1, false}], [], [{:atom, 1, nil}]},
       {:clause, 1, [{:atom, 1, true}], [], [compile_and(rest, local_env)]}
     ]}
  end

  def compile_or([], _local_env), do: {:atom, 1, nil}
  def compile_or([single], local_env), do: compile_expr(single, local_env)

  def compile_or([first | rest], local_env) do
    temp_var = :"V_or_#{System.unique_integer([:positive, :monotonic])}"
    rest_compiled = compile_or(rest, local_env)

    {:case, 1, compile_expr(first, local_env),
     [
       {:clause, 1, [{:atom, 1, nil}], [], [rest_compiled]},
       {:clause, 1, [{:atom, 1, false}], [], [rest_compiled]},
       {:clause, 1, [{nil, 1}], [], [rest_compiled]},
       {:clause, 1, [{:cons, 1, {:atom, 1, :_values_}, {:cons, 1, {nil, 1}, {nil, 1}}}], [],
        [rest_compiled]},
       {:clause, 1,
        [
          {:cons, 1, {:atom, 1, :_values_},
           {:cons, 1, {:cons, 1, {:atom, 1, nil}, {:var, 1, :_}}, {:var, 1, :_}}}
        ], [], [rest_compiled]},
       {:clause, 1,
        [
          {:cons, 1, {:atom, 1, :_values_},
           {:cons, 1, {:cons, 1, {:atom, 1, false}, {:var, 1, :_}}, {:var, 1, :_}}}
        ], [], [rest_compiled]},
       {:clause, 1,
        [
          {:cons, 1, {:atom, 1, :_values_},
           {:cons, 1, {:cons, 1, {nil, 1}, {:var, 1, :_}}, {:var, 1, :_}}}
        ], [], [rest_compiled]},
       {:clause, 1, [{:var, 1, temp_var}], [],
        [
          {:call, 1, {:remote, 1, {:atom, 1, ExLisp.Builtins}, {:atom, 1, :unwrap_mv_primary}},
           [{:var, 1, temp_var}]}
        ]}
     ]}
  end

  # --- Anonymous functions (lambda) ---

  def compile_lambda([params_node | body_nodes], local_env) do
    clean_local_env =
      Enum.reject(local_env, fn
        {:__tagbody_local__, _, _, _} -> true
        _ -> false
      end)
      |> MapSet.new()

    if has_lambda_list_keywords?(params_node) do
      raw_args_sym = :__fn_args__
      {bindings, _} = ExLisp.Macro.build_bindings(params_node, raw_args_sym, raw_args_sym)

      let_star_body =
        {:list, 1,
         [
           {:id, 1, ["let*"]},
           {:list, 1, bindings}
           | body_nodes
         ]}

      new_local_env = MapSet.put(clean_local_env, raw_args_sym)
      compiled_body = [compile_expr(let_star_body, new_local_env)]

      raw_fun =
        {:fun, 1,
         {:clauses, [{:clause, 1, [{:var, 1, erl_var_name(raw_args_sym)}], [], compiled_body}]}}

      {:call, 1, {:remote, 1, {:atom, 1, ExLisp.Closure}, {:atom, 1, :new}}, [raw_fun]}
    else
      param_names = extract_param_names(params_node)
      mutated = find_mutated_vars(body_nodes)

      new_local_env =
        Enum.reduce(param_names, clean_local_env, fn p, acc ->
          acc = acc |> MapSet.delete(p) |> MapSet.delete({:mutated, p})

          if MapSet.member?(mutated, p) do
            MapSet.put(acc, {:mutated, p})
          else
            MapSet.put(acc, p)
          end
        end)

      mutated_params = Enum.filter(param_names, &MapSet.member?(mutated, &1))

      init_erases =
        Enum.map(mutated_params, fn p ->
          {:call, 1, {:remote, 1, {:atom, 1, :erlang}, {:atom, 1, :erase}}, [{:atom, 1, p}]}
        end)

      compiled_body =
        case body_nodes do
          [] -> init_erases ++ [{:atom, 1, nil}]
          _ -> init_erases ++ Enum.map(body_nodes, &compile_expr(&1, new_local_env))
        end

      erl_params = Enum.map(param_names, fn p -> {:var, 1, erl_var_name(p)} end)
      {:fun, 1, {:clauses, [{:clause, 1, erl_params, [], compiled_body}]}}
    end
  end

  def compile_lambda([], _local_env), do: {:atom, 1, nil}

  # --- Variable assignment (setq, setf) ---

  def compile_setq(args, local_env) do
    pairs = Enum.chunk_every(args, 2)

    exprs =
      Enum.map(pairs, fn
        [var_node, val_node] ->
          var_name = extract_symbol_name(var_node)
          compiled_val = compile_expr(val_node, local_env)

          if MapSet.member?(local_env, var_name) or
               MapSet.member?(local_env, {:mutated, var_name}) do
            {:call, 1, {:remote, 1, {:atom, 1, ExLisp.Env}, {:atom, 1, :set_lexical_var}},
             [{:atom, 1, var_name}, compiled_val]}
          else
            {:call, 1, {:remote, 1, {:atom, 1, ExLisp.Env}, {:atom, 1, :set_var}},
             [{:atom, 1, var_name}, compiled_val]}
          end

        [var_node] ->
          var_name = extract_symbol_name(var_node)

          if MapSet.member?(local_env, var_name) or
               MapSet.member?(local_env, {:mutated, var_name}) do
            {:call, 1, {:remote, 1, {:atom, 1, ExLisp.Env}, {:atom, 1, :set_lexical_var}},
             [{:atom, 1, var_name}, {:atom, 1, nil}]}
          else
            {:call, 1, {:remote, 1, {:atom, 1, ExLisp.Env}, {:atom, 1, :set_var}},
             [{:atom, 1, var_name}, {:atom, 1, nil}]}
          end
      end)

    case exprs do
      [] -> {:atom, 1, nil}
      [single] -> single
      _ -> {:block, 1, exprs}
    end
  end

  def compile_setf(args, local_env) do
    case args do
      [place, val] ->
        compile_single_setf(place, val, local_env)

      pairs when is_list(pairs) and rem(length(pairs), 2) == 0 ->
        exprs =
          pairs
          |> Enum.chunk_every(2)
          |> Enum.map(fn [p, v] -> compile_single_setf(p, v, local_env) end)

        {:block, 1, exprs}

      _ ->
        compile_setq(args, local_env)
    end
  end

  defp decompose_macro_place(place_node, prefix) do
    case place_node do
      {:list, pos, [acc_op | acc_args]} ->
        case extract_op_name(acc_op) do
          name when name in [:getf, :_cl_getf_] ->
            case acc_args do
              [target_node | rest_args] ->
                arg_vars =
                  Enum.map(rest_args, fn _ ->
                    {:id, 1, ["__#{prefix}_arg_#{System.unique_integer([:positive, :monotonic])}"]}
                  end)

                arg_bindings =
                  Enum.zip(arg_vars, rest_args)
                  |> Enum.map(fn {var, expr} -> {:list, 1, [var, expr]} end)

                bound_place = {:list, pos, [acc_op, target_node | arg_vars]}
                {bound_place, arg_bindings}

              _ ->
                {place_node, []}
            end

          name when name in [:nth, :_cl_nth_] ->
            case acc_args do
              [idx_node, target_node] ->
                idx_var =
                  {:id, 1, ["__#{prefix}_idx_#{System.unique_integer([:positive, :monotonic])}"]}

                bound_place = {:list, pos, [acc_op, idx_var, target_node]}
                {bound_place, [{:list, 1, [idx_var, idx_node]}]}

              _ ->
                {place_node, []}
            end

          name when name in [:car, :_cl_car_, :cdr, :_cl_cdr_] ->
            {place_node, []}

          _ ->
            case expand_c_r_place(extract_op_name(acc_op), acc_args) do
              {:ok, _} ->
                {place_node, []}

              :error ->
                arg_vars =
                  Enum.map(acc_args, fn _ ->
                    {:id, 1, ["__#{prefix}_arg_#{System.unique_integer([:positive, :monotonic])}"]}
                  end)

                arg_bindings =
                  Enum.zip(arg_vars, acc_args)
                  |> Enum.map(fn {var, expr} -> {:list, 1, [var, expr]} end)

                bound_place = {:list, pos, [acc_op | arg_vars]}
                {bound_place, arg_bindings}
            end
        end

      _ ->
        {place_node, []}
    end
  end

  defp decompose_place_target(target_node) do
    case target_node do
      {:id, _, _} ->
        {:var, target_node, []}

      {:list, _pos, [{:id, _, [p]} | forms]} when p in ["progn", "PROGN"] and forms != [] ->
        init_forms = Enum.drop(forms, -1)
        last_form = List.last(forms)
        dummy_var = {:id, 1, ["__place_init_#{System.unique_integer([:positive, :monotonic])}"]}

        progn_binding =
          if init_forms == [] do
            []
          else
            [{:list, 1, [dummy_var, {:list, 1, [{:id, 1, ["progn"]} | init_forms]}]}]
          end

        {inner_kind, inner_target, inner_bindings} = decompose_place_target(last_form)
        {inner_kind, inner_target, progn_binding ++ inner_bindings}

      {:list, pos, [acc_op | acc_args]} ->
        arg_vars =
          Enum.map(acc_args, fn _ ->
            {:id, 1, ["__place_arg_#{System.unique_integer([:positive, :monotonic])}"]}
          end)

        arg_bindings =
          Enum.zip(arg_vars, acc_args)
          |> Enum.map(fn {var, expr} -> {:list, 1, [var, expr]} end)

        bound_target = {:list, pos, [acc_op | arg_vars]}
        {:accessor, bound_target, arg_bindings}

      other ->
        var = {:id, 1, ["__place_expr_#{System.unique_integer([:positive, :monotonic])}"]}
        {:expr, var, [{:list, 1, [var, other]}]}
    end
  end

  defp decompose_sub_arg(sub_arg) do
    case sub_arg do
      {:id, _, _} ->
        {[], sub_arg}

      {:list, _pos, [{:id, _, [p]} | forms]} when p in ["progn", "PROGN"] and forms != [] ->
        init_forms = Enum.drop(forms, -1)
        last_form = List.last(forms)

        progn_binding =
          if init_forms == [] do
            []
          else
            dummy_var =
              {:id, 1, ["__place_progn_#{System.unique_integer([:positive, :monotonic])}"]}

            [{:list, 1, [dummy_var, {:list, 1, [{:id, 1, ["progn"]} | init_forms]}]}]
          end

        {last_bindings, last_var} = decompose_sub_arg(last_form)
        {progn_binding ++ last_bindings, last_var}

      _ ->
        temp_var = {:id, 1, ["__place_sub_#{System.unique_integer([:positive, :monotonic])}"]}
        {[{:list, 1, [temp_var, sub_arg]}], temp_var}
    end
  end

  defp decompose_places(places) do
    Enum.reduce(places, {[], []}, fn place, {bindings_acc, rewritten_places_acc} ->
      case place do
        {:list, pos, [op_node | sub_args]} ->
          case extract_op_name(op_node) do
            name when name in [:values, :_cl_values_] ->
              {nested_bindings, nested_rewritten} = decompose_places(sub_args)

              {bindings_acc ++ nested_bindings,
               rewritten_places_acc ++ [{:list, pos, [op_node | nested_rewritten]}]}

            _ ->
              {sub_bindings, sub_vars} =
                Enum.reduce(sub_args, {[], []}, fn sub_arg, {b_acc, v_acc} ->
                  {b, v} = decompose_sub_arg(sub_arg)
                  {b_acc ++ b, v_acc ++ [v]}
                end)

              rewritten_place = {:list, pos, [op_node | sub_vars]}
              {bindings_acc ++ sub_bindings, rewritten_places_acc ++ [rewritten_place]}
          end

        other ->
          {bindings_acc, rewritten_places_acc ++ [other]}
      end
    end)
  end

  defp compile_setf_values(place_args, val_node, local_env) do
    {sub_bindings, rewritten_places} = decompose_places(place_args)
    mv_var = {:id, 1, ["__mv_setf_#{System.unique_integer([:positive, :monotonic])}"]}
    mv_form = rewrite_mv_form(val_node)

    setf_exprs =
      Enum.with_index(rewritten_places)
      |> Enum.flat_map(fn {place_i, idx} ->
        val_expr =
          {:list, 1,
           [
             {:id, 1, ["if"]},
             {:list, 1,
              [
                {:id, 1, ["and"]},
                {:list, 1, [{:id, 1, ["consp"]}, mv_var]},
                {:list, 1,
                 [{:id, 1, ["eq"]}, {:list, 1, [{:id, 1, ["car"]}, mv_var]}, {:lit, :_values_}]}
              ]},
             {:list, 1,
              [
                {:id, 1, ["nth"]},
                {:lit, idx},
                {:list, 1, [{:id, 1, ["cadr"]}, mv_var]}
              ]},
             if(idx == 0, do: mv_var, else: {:lit, nil})
           ]}

        case place_i do
          {:list, _pos, [op_node | nested_places]} ->
            case extract_op_name(op_node) do
              name when name in [:values, :_cl_values_] ->
                case nested_places do
                  [] ->
                    []

                  [first_nested | rest_nested] ->
                    [{:list, 1, [{:id, 1, ["setf"]}, first_nested, val_expr]}] ++
                      Enum.map(rest_nested, fn rest_place ->
                        {:list, 1, [{:id, 1, ["setf"]}, rest_place, {:lit, nil}]}
                      end)
                end

              _ ->
                [{:list, 1, [{:id, 1, ["setf"]}, place_i, val_expr]}]
            end

          _ ->
            [{:list, 1, [{:id, 1, ["setf"]}, place_i, val_expr]}]
        end
      end)

    return_vals =
      Enum.with_index(rewritten_places)
      |> Enum.map(fn {_place_i, idx} ->
        {:list, 1,
         [
           {:id, 1, ["if"]},
           {:list, 1,
            [
              {:id, 1, ["and"]},
              {:list, 1, [{:id, 1, ["consp"]}, mv_var]},
              {:list, 1,
               [{:id, 1, ["eq"]}, {:list, 1, [{:id, 1, ["car"]}, mv_var]}, {:lit, :_values_}]}
            ]},
           {:list, 1,
            [
              {:id, 1, ["nth"]},
              {:lit, idx},
              {:list, 1, [{:id, 1, ["cadr"]}, mv_var]}
            ]},
           if(idx == 0, do: mv_var, else: {:lit, nil})
         ]}
      end)

    return_expr =
      case return_vals do
        [] -> {:lit, nil}
        [single] -> single
        multiple -> {:list, 1, [{:id, 1, ["values"]} | multiple]}
      end

    ast =
      {:list, 1,
       [
         {:id, 1, ["let*"]},
         {:list, 1, sub_bindings ++ [{:list, 1, [mv_var, mv_form]}]}
         | setf_exprs ++ [return_expr]
       ]}

    compile_expr(ast, local_env)
  end

  defp compile_single_setf(place, val_node, local_env) do
    case place do
      {:list, _pos, [{:id, _, [p]} | forms]} when p in ["progn", "PROGN"] and forms != [] ->
        init_forms = Enum.drop(forms, -1)
        last_form = List.last(forms)

        compile_expr(
          {:list, 1,
           [{:id, 1, ["progn"]} | init_forms ++ [{:list, 1, [{:id, 1, ["setf"]}, last_form, val_node]}]]},
          local_env
        )

      {:list, _pos, [op_node | place_args]} ->
        case extract_op_name(op_node) do
          name when name in [:values, :_cl_values_] ->
            compile_setf_values(place_args, val_node, local_env)

          name when name in [:car, :_cl_car_] ->
            case place_args do
              [target_node] ->
                case target_node do
                  {:list, _pos, [{:id, _, ["progn"]} | forms]} when forms != [] ->
                    init_forms = Enum.drop(forms, -1)
                    last_form = List.last(forms)

                    new_setf =
                      {:list, 1,
                       [{:id, 1, ["setf"]}, {:list, 1, [{:id, 1, ["car"]}, last_form]}, val_node]}

                    compile_expr(
                      {:list, 1, [{:id, 1, ["progn"]} | init_forms ++ [new_setf]]},
                      local_env
                    )

                  _ ->
                    val_var =
                      {:id, 1, ["__setf_val_#{System.unique_integer([:positive, :monotonic])}"]}

                    ast =
                      {:list, 1,
                       [
                         {:id, 1, ["let*"]},
                         {:list, 1, [{:list, 1, [val_var, val_node]}]},
                         {:list, 1,
                          [
                            {:id, 1, ["setf"]},
                            target_node,
                            {:list, 1,
                             [
                               {:id, 1, ["cons"]},
                               val_var,
                               {:list, 1, [{:id, 1, ["cdr"]}, target_node]}
                             ]}
                          ]},
                         val_var
                       ]}

                    compile_expr(ast, local_env)
                end

              _ ->
                compile_setq([place, val_node], local_env)
            end

          name when name in [:cdr, :_cl_cdr_] ->
            case place_args do
              [target_node] ->
                case target_node do
                  {:list, _pos, [{:id, _, ["progn"]} | forms]} when forms != [] ->
                    init_forms = Enum.drop(forms, -1)
                    last_form = List.last(forms)

                    new_setf =
                      {:list, 1,
                       [{:id, 1, ["setf"]}, {:list, 1, [{:id, 1, ["cdr"]}, last_form]}, val_node]}

                    compile_expr(
                      {:list, 1, [{:id, 1, ["progn"]} | init_forms ++ [new_setf]]},
                      local_env
                    )

                  _ ->
                    val_var =
                      {:id, 1, ["__setf_val_#{System.unique_integer([:positive, :monotonic])}"]}

                    ast =
                      {:list, 1,
                       [
                         {:id, 1, ["let*"]},
                         {:list, 1, [{:list, 1, [val_var, val_node]}]},
                         {:list, 1,
                          [
                            {:id, 1, ["setf"]},
                            target_node,
                            {:list, 1,
                             [
                               {:id, 1, ["cons"]},
                               {:list, 1, [{:id, 1, ["car"]}, target_node]},
                               val_var
                             ]}
                          ]},
                         val_var
                       ]}

                    compile_expr(ast, local_env)
                end

              _ ->
                compile_setq([place, val_node], local_env)
            end

          name when name in [:nth, :_cl_nth_] ->
            case place_args do
              [idx_node, target_node] ->
                case target_node do
                  {:list, _pos, [{:id, _, ["progn"]} | forms]} when forms != [] ->
                    init_forms = Enum.drop(forms, -1)
                    last_form = List.last(forms)

                    new_setf =
                      {:list, 1,
                       [
                         {:id, 1, ["setf"]},
                         {:list, 1, [{:id, 1, ["nth"]}, idx_node, last_form]},
                         val_node
                       ]}

                    compile_expr(
                      {:list, 1, [{:id, 1, ["progn"]} | init_forms ++ [new_setf]]},
                      local_env
                    )

                  _ ->
                    val_var =
                      {:id, 1, ["__setf_val_#{System.unique_integer([:positive, :monotonic])}"]}

                    idx_var =
                      {:id, 1, ["__setf_idx_#{System.unique_integer([:positive, :monotonic])}"]}

                    ast =
                      {:list, 1,
                       [
                         {:id, 1, ["let*"]},
                         {:list, 1,
                          [
                            {:list, 1, [idx_var, idx_node]},
                            {:list, 1, [val_var, val_node]}
                          ]},
                         {:list, 1,
                          [
                            {:id, 1, ["setf"]},
                            target_node,
                            {:list, 1,
                             [
                               {:id, 1, ["_cl_set_nth_"]},
                               idx_var,
                               target_node,
                               val_var
                             ]}
                          ]},
                         val_var
                       ]}

                    compile_expr(ast, local_env)
                end

              _ ->
                compile_setq([place, val_node], local_env)
            end

          name when name in [:getf, :_cl_getf_] ->
            case place_args do
              [target_node, indicator_node | default_rest] ->
                default_node = List.first(default_rest)

                val_var =
                  {:id, 1, ["__setf_val_#{System.unique_integer([:positive, :monotonic])}"]}

                ind_var =
                  {:id, 1, ["__setf_ind_#{System.unique_integer([:positive, :monotonic])}"]}

                def_bindings =
                  if default_node do
                    def_var =
                      {:id, 1, ["__setf_def_#{System.unique_integer([:positive, :monotonic])}"]}

                    [{:list, 1, [def_var, default_node]}]
                  else
                    []
                  end

                case target_node do
                  {:list, pos, [acc_op | acc_args]} ->
                    {arg_bindings, bound_args} =
                      Enum.reduce(acc_args, {[], []}, fn
                        {:list, _, [{:id, _, ["progn"]} | forms]} = _arg_progn, {b_acc, a_acc}
                        when forms != [] ->
                          init_forms = Enum.drop(forms, -1)
                          last_form = List.last(forms)

                          dummy_var =
                            {:id, 1,
                             ["__setf_init_#{System.unique_integer([:positive, :monotonic])}"]}

                          progn_init = {:list, 1, [{:id, 1, ["progn"]} | init_forms]}

                          {b_acc ++ [{:list, 1, [dummy_var, progn_init]}], a_acc ++ [last_form]}

                        {:id, _, _} = arg_id, {b_acc, a_acc} ->
                          {b_acc, a_acc ++ [arg_id]}

                        other_arg, {b_acc, a_acc} ->
                          arg_var =
                            {:id, 1,
                             ["__setf_arg_#{System.unique_integer([:positive, :monotonic])}"]}

                          {b_acc ++ [{:list, 1, [arg_var, other_arg]}], a_acc ++ [arg_var]}
                      end)

                    bound_target = {:list, pos, [acc_op | bound_args]}

                    all_bindings =
                      arg_bindings ++
                        [{:list, 1, [ind_var, indicator_node]}] ++
                        def_bindings ++
                        [{:list, 1, [val_var, val_node]}]

                    ast =
                      {:list, 1,
                       [
                         {:id, 1, ["let*"]},
                         {:list, 1, all_bindings},
                         {:list, 1,
                          [
                            {:id, 1, ["setf"]},
                            bound_target,
                            {:list, 1,
                             [
                               {:id, 1, ["_cl_put_plist_"]},
                               bound_target,
                               ind_var,
                               val_var
                             ]}
                          ]},
                         val_var
                       ]}

                    compile_expr(ast, local_env)

                  _ ->
                    all_bindings =
                      [{:list, 1, [ind_var, indicator_node]}] ++
                        def_bindings ++
                        [{:list, 1, [val_var, val_node]}]

                    ast =
                      {:list, 1,
                       [
                         {:id, 1, ["let*"]},
                         {:list, 1, all_bindings},
                         {:list, 1,
                          [
                            {:id, 1, ["setf"]},
                            target_node,
                            {:list, 1,
                             [
                               {:id, 1, ["_cl_put_plist_"]},
                               target_node,
                               ind_var,
                               val_var
                             ]}
                          ]},
                         val_var
                       ]}

                    compile_expr(ast, local_env)
                end

              _ ->
                compile_setq([place, val_node], local_env)
            end

          name when name in [:symbol_function, :_cl_symbol_function_, :fdefinition] ->
            case place_args do
              [sym_node | _] ->
                {:call, 1,
                 {:remote, 1, {:atom, 1, ExLisp.Builtins}, {:atom, 1, :set_symbol_function}},
                 [compile_expr(sym_node, local_env), compile_expr(val_node, local_env)]}

              _ ->
                compile_setq([place, val_node], local_env)
            end

          name when name in [:symbol_value, :_cl_symbol_value_] ->
            case place_args do
              [sym_node | _] ->
                {:call, 1,
                 {:remote, 1, {:atom, 1, ExLisp.Builtins}, {:atom, 1, :set_symbol_value}},
                 [compile_expr(sym_node, local_env), compile_expr(val_node, local_env)]}

              _ ->
                compile_setq([place, val_node], local_env)
            end

          :gethash ->
            case place_args do
              [key_node, table_node | _] ->
                {:call, 1, {:remote, 1, {:atom, 1, ExLisp.Builtins}, {:atom, 1, :set_gethash}},
                 [
                   compile_expr(key_node, local_env),
                   compile_expr(table_node, local_env),
                   compile_expr(val_node, local_env)
                 ]}

              _ ->
                compile_setq([place, val_node], local_env)
            end

          name when name in [:char, :_cl_char_, :schar, :_cl_schar_] ->
            case place_args do
              [seq_node, idx_node] ->
                {kind, target, target_bindings} = decompose_place_target(seq_node)

                idx_var =
                  {:id, 1, ["__setf_char_idx_#{System.unique_integer([:positive, :monotonic])}"]}

                val_var =
                  {:id, 1, ["__setf_char_val_#{System.unique_integer([:positive, :monotonic])}"]}

                all_bindings =
                  target_bindings ++
                    [
                      {:list, 1, [idx_var, idx_node]},
                      {:list, 1, [val_var, val_node]}
                    ]

                update_call =
                  {:list, 1,
                   [
                     {:id, 1, ["_cl_set_char_update_seq_"]},
                     target,
                     idx_var,
                     val_var
                   ]}

                set_form =
                  case kind do
                    :var -> {:list, 1, [{:id, 1, ["setq"]}, target, update_call]}
                    :accessor -> {:list, 1, [{:id, 1, ["setf"]}, target, update_call]}
                    :expr -> update_call
                  end

                ast =
                  {:list, 1,
                   [
                     {:id, 1, ["let*"]},
                     {:list, 1, all_bindings},
                     set_form,
                     val_var
                   ]}

                compile_expr(ast, local_env)

              _ ->
                compile_setq([place, val_node], local_env)
            end

          name when name in [:elt, :_cl_elt_] ->
            case place_args do
              [seq_node, idx_node] ->
                {kind, target, target_bindings} = decompose_place_target(seq_node)

                idx_var =
                  {:id, 1, ["__setf_elt_idx_#{System.unique_integer([:positive, :monotonic])}"]}

                val_var =
                  {:id, 1, ["__setf_elt_val_#{System.unique_integer([:positive, :monotonic])}"]}

                all_bindings =
                  target_bindings ++
                    [
                      {:list, 1, [idx_var, idx_node]},
                      {:list, 1, [val_var, val_node]}
                    ]

                update_call =
                  {:list, 1,
                   [
                     {:id, 1, ["_cl_set_elt_update_seq_"]},
                     target,
                     idx_var,
                     val_var
                   ]}

                set_form =
                  case kind do
                    :var -> {:list, 1, [{:id, 1, ["setq"]}, target, update_call]}
                    :accessor -> {:list, 1, [{:id, 1, ["setf"]}, target, update_call]}
                    :expr -> update_call
                  end

                ast =
                  {:list, 1,
                   [
                     {:id, 1, ["let*"]},
                     {:list, 1, all_bindings},
                     set_form,
                     val_var
                   ]}

                compile_expr(ast, local_env)

              _ ->
                compile_setq([place, val_node], local_env)
            end

          name when name in [:subseq, :_cl_subseq_] ->
            case place_args do
              [seq_node, start_node] ->
                {kind, target, target_bindings} = decompose_place_target(seq_node)

                start_var =
                  {:id, 1,
                   ["__setf_subseq_start_#{System.unique_integer([:positive, :monotonic])}"]}

                val_var =
                  {:id, 1,
                   ["__setf_subseq_val_#{System.unique_integer([:positive, :monotonic])}"]}

                all_bindings =
                  target_bindings ++
                    [
                      {:list, 1, [start_var, start_node]},
                      {:list, 1, [val_var, val_node]}
                    ]

                update_call =
                  {:list, 1,
                   [
                     {:id, 1, ["_cl_set_subseq_update_seq_"]},
                     target,
                     start_var,
                     val_var
                   ]}

                set_form =
                  case kind do
                    :var -> {:list, 1, [{:id, 1, ["setq"]}, target, update_call]}
                    :accessor -> {:list, 1, [{:id, 1, ["setf"]}, target, update_call]}
                    :expr -> update_call
                  end

                ast =
                  {:list, 1,
                   [
                     {:id, 1, ["let*"]},
                     {:list, 1, all_bindings},
                     set_form,
                     val_var
                   ]}

                compile_expr(ast, local_env)

              [seq_node, start_node, end_node] ->
                {kind, target, target_bindings} = decompose_place_target(seq_node)

                start_var =
                  {:id, 1,
                   ["__setf_subseq_start_#{System.unique_integer([:positive, :monotonic])}"]}

                end_var =
                  {:id, 1,
                   ["__setf_subseq_end_#{System.unique_integer([:positive, :monotonic])}"]}

                val_var =
                  {:id, 1,
                   ["__setf_subseq_val_#{System.unique_integer([:positive, :monotonic])}"]}

                all_bindings =
                  target_bindings ++
                    [
                      {:list, 1, [start_var, start_node]},
                      {:list, 1, [end_var, end_node]},
                      {:list, 1, [val_var, val_node]}
                    ]

                update_call =
                  {:list, 1,
                   [
                     {:id, 1, ["_cl_set_subseq_update_seq_"]},
                     target,
                     start_var,
                     end_var,
                     val_var
                   ]}

                set_form =
                  case kind do
                    :var -> {:list, 1, [{:id, 1, ["setq"]}, target, update_call]}
                    :accessor -> {:list, 1, [{:id, 1, ["setf"]}, target, update_call]}
                    :expr -> update_call
                  end

                ast =
                  {:list, 1,
                   [
                     {:id, 1, ["let*"]},
                     {:list, 1, all_bindings},
                     set_form,
                     val_var
                   ]}

                compile_expr(ast, local_env)

              _ ->
                compile_setq([place, val_node], local_env)
            end

          name when name in [:aref, :_cl_aref_, :bit, :_cl_bit_, :sbit, :_cl_sbit_] ->
            case place_args do
              [arr_node, idx_node] ->
                arr_var = :"V_arr_#{System.unique_integer([:positive, :monotonic])}"
                idx_var = :"V_idx_#{System.unique_integer([:positive, :monotonic])}"
                val_var = :"V_val_#{System.unique_integer([:positive, :monotonic])}"

                {:block, 1,
                 [
                   {:match, 1, {:var, 1, arr_var}, compile_expr(arr_node, local_env)},
                   {:match, 1, {:var, 1, idx_var}, compile_expr(idx_node, local_env)},
                   {:match, 1, {:var, 1, val_var}, compile_expr(val_node, local_env)},
                   {:call, 1, {:remote, 1, {:atom, 1, ExLisp.Builtins}, {:atom, 1, :set_aref}},
                    [{:var, 1, arr_var}, {:var, 1, idx_var}, {:var, 1, val_var}]}
                 ]}

              [arr_node | idx_nodes] ->
                arr_var = :"V_arr_#{System.unique_integer([:positive, :monotonic])}"
                val_var = :"V_val_#{System.unique_integer([:positive, :monotonic])}"

                idx_vars =
                  Enum.map(idx_nodes, fn _ ->
                    :"V_idx_#{System.unique_integer([:positive, :monotonic])}"
                  end)

                arr_match = {:match, 1, {:var, 1, arr_var}, compile_expr(arr_node, local_env)}

                idx_matches =
                  Enum.zip(idx_vars, idx_nodes)
                  |> Enum.map(fn {v, node} ->
                    {:match, 1, {:var, 1, v}, compile_expr(node, local_env)}
                  end)

                val_match = {:match, 1, {:var, 1, val_var}, compile_expr(val_node, local_env)}

                idx_cons = ast_cons_list(Enum.map(idx_vars, fn v -> {:var, 1, v} end))

                {:block, 1,
                 [arr_match] ++
                   idx_matches ++
                   [
                     val_match,
                     {:call, 1,
                      {:remote, 1, {:atom, 1, ExLisp.Builtins}, {:atom, 1, :set_aref}},
                      [{:var, 1, arr_var}, idx_cons, {:var, 1, val_var}]}
                   ]}

              _ ->
                compile_setq([place, val_node], local_env)
            end

          :get ->
            case place_args do
              [sym_node, prop_node] ->
                {:call, 1,
                 {:remote, 1, {:atom, 1, ExLisp.Builtins}, {:atom, 1, :set_symbol_prop}},
                 [
                   compile_expr(sym_node, local_env),
                   compile_expr(prop_node, local_env),
                   compile_expr(val_node, local_env)
                 ]}

              [sym_node, prop_node, def_node] ->
                sym_var = :"V_getsym_#{System.unique_integer([:positive, :monotonic])}"
                prop_var = :"V_getprop_#{System.unique_integer([:positive, :monotonic])}"

                {:block, 1,
                 [
                   {:match, 1, {:var, 1, sym_var}, compile_expr(sym_node, local_env)},
                   {:match, 1, {:var, 1, prop_var}, compile_expr(prop_node, local_env)},
                   compile_expr(def_node, local_env),
                   {:call, 1,
                    {:remote, 1, {:atom, 1, ExLisp.Builtins}, {:atom, 1, :set_symbol_prop}},
                    [
                      {:var, 1, sym_var},
                      {:var, 1, prop_var},
                      compile_expr(val_node, local_env)
                    ]}
                 ]}

              _ ->
                compile_setq([place, val_node], local_env)
            end

          name when name in [:symbol_plist, :_cl_symbol_plist_] ->
            case place_args do
              [sym_node] ->
                {:call, 1,
                 {:remote, 1, {:atom, 1, ExLisp.Builtins}, {:atom, 1, :set_symbol_plist}},
                 [
                   compile_expr(sym_node, local_env),
                   compile_expr(val_node, local_env)
                 ]}

              _ ->
                compile_setq([place, val_node], local_env)
            end

          :svref ->
            case place_args do
              [vec_node, idx_node] ->
                {:call, 1, {:remote, 1, {:atom, 1, ExLisp.Builtins}, {:atom, 1, :set_svref}},
                 [
                   compile_expr(vec_node, local_env),
                   compile_expr(idx_node, local_env),
                   compile_expr(val_node, local_env)
                 ]}

              _ ->
                compile_setq([place, val_node], local_env)
            end

          name when name in [:slot_value, :_cl_slot_value_] ->
            case place_args do
              [inst_node, slot_node] ->
                {:call, 1, {:remote, 1, {:atom, 1, ExLisp.Builtins}, {:atom, 1, :set_slot_value}},
                 [
                   compile_expr(inst_node, local_env),
                   compile_expr(slot_node, local_env),
                   compile_expr(val_node, local_env)
                 ]}

              _ ->
                compile_setq([place, val_node], local_env)
            end

          :ldb ->
            case place_args do
              [bytespec_node, target_node] ->
                dpb_call =
                  {:call, 1, {:remote, 1, {:atom, 1, ExLisp.Builtins}, {:atom, 1, :dpb}},
                   [
                     compile_expr(val_node, local_env),
                     compile_expr(bytespec_node, local_env),
                     compile_expr(target_node, local_env)
                   ]}

                compile_single_setf(target_node, dpb_call, local_env)

              _ ->
                compile_setq([place, val_node], local_env)
            end

          name when name in [:fill_pointer, :_cl_fill_pointer_] ->
            case place_args do
              [arr_node | _] ->
                {:call, 1,
                 {:remote, 1, {:atom, 1, ExLisp.Builtins}, {:atom, 1, :set_fill_pointer}},
                 [
                   compile_expr(arr_node, local_env),
                   compile_expr(val_node, local_env)
                 ]}

              _ ->
                compile_setq([place, val_node], local_env)
            end

          accessor_name when is_atom(accessor_name) and length(place_args) == 1 ->
            case expand_c_r_place(accessor_name, place_args) do
              {:ok, new_place} ->
                compile_single_setf(new_place, val_node, local_env)

              :error ->
                # e.g. (person-name p) -> set_struct_slot(p, :name, val)
                [target_node] = place_args
                accessor_str = Atom.to_string(accessor_name)

                slot_name =
                  case String.split(accessor_str, "_") do
                    [_struct_prefix | rest_parts] when rest_parts != [] ->
                      Enum.join(rest_parts, "_") |> String.to_atom()

                    _ ->
                      accessor_name
                  end

                {:call, 1,
                 {:remote, 1, {:atom, 1, ExLisp.Builtins}, {:atom, 1, :set_struct_slot}},
                 [
                   compile_expr(target_node, local_env),
                   {:atom, 1, slot_name},
                   compile_expr(val_node, local_env)
                 ]}
            end

          _ ->
            case expand_c_r_place(extract_op_name(op_node), place_args) do
              {:ok, new_place} ->
                compile_single_setf(new_place, val_node, local_env)

              :error ->
                setf_fn_sym = :"setf_#{extract_op_name(op_node)}"

                if is_atom(setf_fn_sym) and
                     (MapSet.member?(local_env, setf_fn_sym) or ExLisp.Env.has_fun?(setf_fn_sym)) do
                  setf_call =
                    {:list, 1, [{:id, 1, [Atom.to_string(setf_fn_sym)]}, val_node | place_args]}

                  compile_expr(setf_call, local_env)
                else
                  compile_setq([place, val_node], local_env)
                end
            end
        end

      _ ->
        compile_setq([place, val_node], local_env)
    end
  end

  defp expand_c_r_place(name, [target_node]) when is_atom(name) do
    case target_node do
      {:list, _pos, [{:id, _, [p]} | forms]} when p in ["progn", "PROGN"] and forms != [] ->
        init_forms = Enum.drop(forms, -1)
        last_form = List.last(forms)

        case expand_c_r_place(name, [last_form]) do
          {:ok, expanded} ->
            {:ok, {:list, 1, [{:id, 1, ["progn"]} | init_forms ++ [expanded]]}}

          :error ->
            :error
        end

      _ ->
        str =
          name
          |> Atom.to_string()
          |> String.downcase()
          |> String.trim_leading(":")
          |> String.trim_leading("_cl_")
          |> String.trim_trailing("_")

        case str do
          "first" ->
            {:ok, {:list, 1, [{:id, 1, ["car"]}, target_node]}}

          "second" ->
            {:ok, {:list, 1, [{:id, 1, ["cadr"]}, target_node]}}

          "third" ->
            {:ok, {:list, 1, [{:id, 1, ["caddr"]}, target_node]}}

          "fourth" ->
            {:ok, {:list, 1, [{:id, 1, ["cadddr"]}, target_node]}}

          "fifth" ->
            {:ok, {:list, 1, [{:id, 1, ["nth"]}, {:lit, 4}, target_node]}}

          "sixth" ->
            {:ok, {:list, 1, [{:id, 1, ["nth"]}, {:lit, 5}, target_node]}}

          "seventh" ->
            {:ok, {:list, 1, [{:id, 1, ["nth"]}, {:lit, 6}, target_node]}}

          "eighth" ->
            {:ok, {:list, 1, [{:id, 1, ["nth"]}, {:lit, 7}, target_node]}}

          "ninth" ->
            {:ok, {:list, 1, [{:id, 1, ["nth"]}, {:lit, 8}, target_node]}}

          "tenth" ->
            {:ok, {:list, 1, [{:id, 1, ["nth"]}, {:lit, 9}, target_node]}}

          "rest" ->
            {:ok, {:list, 1, [{:id, 1, ["cdr"]}, target_node]}}

          "c" <> rest when byte_size(rest) >= 3 ->
            if String.ends_with?(rest, "r") do
              mid = binary_part(rest, 0, byte_size(rest) - 1)

              if Regex.match?(~r/^[ad]+$/, mid) and byte_size(mid) >= 2 do
                first_char = String.first(mid)
                rem_mid = String.slice(mid, 1..-1//1)
                first_op = if first_char == "a", do: "car", else: "cdr"
                rem_op = "c" <> rem_mid <> "r"

                {:ok,
                 {:list, 1,
                  [{:id, 1, [first_op]}, {:list, 1, [{:id, 1, [rem_op]}, target_node]}]}}
              else
                :error
              end
            else
              :error
            end

          _ ->
            :error
        end
    end
  end

  defp expand_c_r_place(_, _), do: :error

  # --- Loop & control flow (loop, block, return, return-from, unwind-protect, do, tagbody, go, dotimes, dolist) ---

  def compile_block([name_node | body_nodes], local_env) do
    block_name = to_atom_symbol(name_node)
    unique_tag = :"__block_#{block_name}_#{System.unique_integer([:positive])}"

    filtered_env =
      Enum.reject(local_env, fn
        {:__block__, ^block_name, _} -> true
        _ -> false
      end)
      |> MapSet.new()

    new_local_env = MapSet.put(filtered_env, {:__block__, block_name, unique_tag})

    compiled_body =
      case body_nodes do
        [] -> [{:atom, 1, nil}]
        _ -> Enum.map(body_nodes, &compile_expr(&1, new_local_env))
      end

    ret_var = :"V_ret_#{System.unique_integer([:positive])}"

    {:try, 1, compiled_body, [],
     [
       {:clause, 1,
        [
          {:tuple, 1,
           [
             {:atom, 1, :throw},
             {:tuple, 1, [{:atom, 1, :lisp_return}, {:atom, 1, unique_tag}, {:var, 1, ret_var}]},
             {:var, 1, :_}
           ]}
        ], [], [{:var, 1, ret_var}]}
     ], []}
  end

  def compile_return_from([name_node | val_nodes], local_env) do
    block_name = to_atom_symbol(name_node)

    target_tag =
      Enum.find_value(local_env, block_name, fn
        {:__block__, ^block_name, tag} -> tag
        _ -> nil
      end)

    val_expr =
      case val_nodes do
        [] -> {:atom, 1, nil}
        [single] -> compile_expr(single, local_env)
        _ -> compile_progn(val_nodes, local_env)
      end

    {:call, 1, {:remote, 1, {:atom, 1, :erlang}, {:atom, 1, :throw}},
     [{:tuple, 1, [{:atom, 1, :lisp_return}, {:atom, 1, target_tag}, val_expr]}]}
  end

  defp to_atom_symbol(node) do
    case node do
      {:atom, _, a} ->
        a

      {:lit, a} when is_atom(a) ->
        a

      {:lit, i} when is_integer(i) ->
        String.to_atom("tag_#{i}")

      {:id, _, [s]} ->
        s |> String.downcase() |> String.to_atom()

      {:id, _, parts} when is_list(parts) ->
        Enum.join(parts, ".") |> String.downcase() |> String.to_atom()

      a when is_atom(a) ->
        a

      i when is_integer(i) ->
        String.to_atom("tag_#{i}")

      s when is_binary(s) ->
        s |> String.downcase() |> String.to_atom()

      _ ->
        String.to_atom("#{inspect(node)}")
    end
  end

  def compile_return(args, local_env) do
    compile_return_from([{:atom, 1, nil} | args], local_env)
  end

  def compile_loop(body_nodes, local_env) do
    if ExLisp.Loop.extended_loop?(body_nodes) do
      expanded_ast = ExLisp.Loop.expand(body_nodes)
      compile_expr(expanded_ast, local_env)
    else
      # Implicit (block nil ...)
      block_name = nil
      unique_tag = :"__block_nil_#{System.unique_integer([:positive])}"

      filtered_env =
        Enum.reject(local_env, fn
          {:__block__, ^block_name, _} -> true
          _ -> false
        end)
        |> MapSet.new()

      new_local_env = MapSet.put(filtered_env, {:__block__, block_name, unique_tag})

      loop_fun_name = :"Loop_#{System.unique_integer([:positive, :monotonic])}"
      compiled_body = Enum.map(body_nodes, &compile_expr(&1, new_local_env))

      loop_clauses = [
        {:clause, 1, [], [], compiled_body ++ [{:call, 1, {:var, 1, loop_fun_name}, []}]}
      ]

      loop_call = {:call, 1, {:named_fun, 1, loop_fun_name, loop_clauses}, []}

      ret_var = :"V_ret_#{System.unique_integer([:positive])}"

      {:try, 1, [loop_call], [],
       [
         {:clause, 1,
          [
            {:tuple, 1,
             [
               {:atom, 1, :throw},
               {:tuple, 1,
                [{:atom, 1, :lisp_return}, {:atom, 1, unique_tag}, {:var, 1, ret_var}]},
               {:var, 1, :_}
             ]}
          ], [], [{:var, 1, ret_var}]}
       ], []}
    end
  end

  def compile_unwind_protect([protected_node | cleanup_nodes], local_env) do
    protected_expr = compile_expr(protected_node, local_env)
    compiled_cleanups = Enum.map(cleanup_nodes, &compile_expr(&1, local_env))
    cleanups = if compiled_cleanups == [], do: [{:atom, 1, nil}], else: compiled_cleanups

    {:try, 1, [protected_expr], [], [], cleanups}
  end

  def compile_ignore_errors(forms, local_env) do
    compiled_forms =
      case forms do
        [] -> [{:atom, 1, nil}]
        _ -> Enum.map(forms, &compile_expr(&1, local_env))
      end

    {:try, 1, compiled_forms, [],
     [
       {:clause, 1,
        [
          {:tuple, 1,
           [
             {:var, 1, :_},
             {:var, 1, :_},
             {:var, 1, :_}
           ]}
        ], [], [{:atom, 1, nil}]}
     ], []}
  end

  def compile_handler_case([expr_node | clauses], local_env) do
    compiled_expr = compile_expr(expr_node, local_env)

    if clauses == [] do
      compiled_expr
    else
      catch_clauses =
        Enum.map(clauses, fn
          {:list, _pos, [_type_spec, params_node | handler_body]} ->
            err_var_name =
              case params_node do
                {:list, _pos, [v | _]} -> extract_symbol_name(v)
                v when not is_list(v) and v != nil -> extract_symbol_name(v)
                _ -> :_
              end

            erl_err_var =
              if err_var_name == :_,
                do: {:var, 1, :_},
                else: {:var, 1, erl_var_name(err_var_name)}

            handler_env =
              if err_var_name == :_, do: local_env, else: MapSet.put(local_env, err_var_name)

            compiled_handler =
              case handler_body do
                [] -> [{:atom, 1, nil}]
                _ -> Enum.map(handler_body, &compile_expr(&1, handler_env))
              end

            {:clause, 1,
             [
               {:tuple, 1,
                [
                  {:var, 1, :_},
                  erl_err_var,
                  {:var, 1, :_}
                ]}
             ], [], compiled_handler}

          _ ->
            {:clause, 1,
             [
               {:tuple, 1, [{:var, 1, :_}, {:var, 1, :_}, {:var, 1, :_}]}
             ], [], [{:atom, 1, nil}]}
        end)

      try_expr = {:try, 1, [compiled_expr], [], catch_clauses, []}
      {:call, 1, {:fun, 1, {:clauses, [{:clause, 1, [], [], [try_expr]}]}}, []}
    end
  end

  def compile_do([bindings_node, test_clause | body_nodes], local_env) do
    bindings = parse_do_bindings(bindings_node)
    {end_test_node, result_nodes} = parse_do_test_clause(test_clause)

    var_names = Enum.map(bindings, &elem(&1, 0))
    init_nodes = Enum.map(bindings, &elem(&1, 1))
    step_nodes = Enum.map(bindings, &elem(&1, 2))

    loop_fun_name = :"DoLoop_#{System.unique_integer([:positive, :monotonic])}"
    loop_env = MapSet.union(local_env, MapSet.new(var_names))
    erl_vars = Enum.map(var_names, fn v -> {:var, 1, erl_var_name(v)} end)

    compiled_test = compile_expr(end_test_node, loop_env)

    compiled_result =
      case result_nodes do
        [] -> {:atom, 1, nil}
        _ -> compile_progn(result_nodes, loop_env)
      end

    compiled_body = Enum.map(body_nodes, &compile_expr(&1, loop_env))
    compiled_steps = Enum.map(step_nodes, &compile_expr(&1, loop_env))
    recur_call = {:call, 1, {:var, 1, loop_fun_name}, compiled_steps}

    loop_clauses = [
      {:clause, 1, erl_vars, [],
       [
         {:case, 1, compiled_test,
          [
            {:clause, 1, [{:atom, 1, nil}], [], compiled_body ++ [recur_call]},
            {:clause, 1, [{:var, 1, :_}], [], [compiled_result]}
          ]}
       ]}
    ]

    compiled_inits = Enum.map(init_nodes, &compile_expr(&1, local_env))
    loop_call = {:call, 1, {:named_fun, 1, loop_fun_name, loop_clauses}, compiled_inits}
    compile_block([{:atom, 1, nil}, loop_call], local_env)
  end

  defp parse_do_bindings({:list, _pos, elems}),
    do: elems |> Enum.reject(&(&1 in [nil, {:lit, nil}])) |> Enum.map(&parse_single_do_binding/1)

  defp parse_do_bindings({:quoted, _pos, elems}),
    do: elems |> Enum.reject(&(&1 in [nil, {:lit, nil}])) |> Enum.map(&parse_single_do_binding/1)

  defp parse_do_bindings(elems) when is_list(elems),
    do: elems |> Enum.reject(&(&1 in [nil, {:lit, nil}])) |> Enum.map(&parse_single_do_binding/1)

  defp parse_do_bindings(_), do: []

  defp parse_single_do_binding({:list, _pos, [v, init, step | _]}),
    do: {extract_symbol_name(v), init, step}

  defp parse_single_do_binding({:list, _pos, [v, init]}), do: {extract_symbol_name(v), init, v}

  defp parse_single_do_binding({:list, _pos, [v]}),
    do: {extract_symbol_name(v), {:atom, 1, nil}, v}

  defp parse_single_do_binding({:quoted, _pos, [v, init, step | _]}),
    do: {extract_symbol_name(v), init, step}

  defp parse_single_do_binding({:quoted, _pos, [v, init]}), do: {extract_symbol_name(v), init, v}

  defp parse_single_do_binding({:quoted, _pos, [v]}),
    do: {extract_symbol_name(v), {:atom, 1, nil}, v}

  defp parse_single_do_binding(v), do: {extract_symbol_name(v), {:atom, 1, nil}, v}

  defp parse_do_test_clause({:list, _pos, [test | results]}), do: {test, results}
  defp parse_do_test_clause({:quoted, _pos, [test | results]}), do: {test, results}
  defp parse_do_test_clause([test | results]), do: {test, results}
  defp parse_do_test_clause(test), do: {test, []}

  def compile_tagbody(elements, local_env) do
    segments = group_tagbody_segments(elements)
    unique_tag = :"__tagbody_#{System.unique_integer([:positive])}"

    tag_set =
      Enum.map(segments, &elem(&1, 0))
      |> Enum.reject(&(&1 == :__start__))
      |> MapSet.new()

    filtered_env =
      Enum.reject(local_env, fn
        {:__tagbody_tag__, t, _} -> MapSet.member?(tag_set, t)
        _ -> false
      end)
      |> MapSet.new()

    tagbody_env =
      Enum.reduce(tag_set, filtered_env, fn t, acc ->
        MapSet.put(acc, {:__tagbody_tag__, t, unique_tag})
      end)

    v_tag = :"V_tag_#{System.unique_integer([:positive])}"
    v_next = :"V_next_#{System.unique_integer([:positive])}"
    v_throw_dest = :"V_throw_dest_#{System.unique_integer([:positive])}"
    v_dest_tag = :"V_dest_tag_#{System.unique_integer([:positive])}"
    loop_fun_name = :"TagbodyLoop_#{System.unique_integer([:positive, :monotonic])}"

    case_clauses =
      Enum.map(segments, fn {tag, expr_nodes, next_tag} ->
        compiled_exprs = Enum.map(expr_nodes, &compile_expr(&1, tagbody_env))

        next_val =
          if next_tag do
            {:tuple, 1, [{:atom, 1, :next}, {:atom, 1, next_tag}]}
          else
            {:atom, 1, :done}
          end

        {:clause, 1, [{:atom, 1, tag}], [], compiled_exprs ++ [next_val]}
      end) ++
        [
          {:clause, 1, [{:var, 1, :_}], [], [{:atom, 1, :done}]}
        ]

    case_expr = {:case, 1, {:var, 1, v_tag}, case_clauses}

    try_expr =
      {:try, 1, [case_expr], [],
       [
         {:clause, 1,
          [
            {:tuple, 1,
             [
               {:atom, 1, :throw},
               {:tuple, 1,
                [{:atom, 1, :lisp_go}, {:atom, 1, unique_tag}, {:var, 1, v_throw_dest}]},
               {:var, 1, :_}
             ]}
          ], [], [{:tuple, 1, [{:atom, 1, :next}, {:var, 1, v_throw_dest}]}]}
       ], []}

    dest_check_clause =
      {:clause, 1,
       [
         {:tuple, 1, [{:atom, 1, :next}, {:var, 1, v_dest_tag}]}
       ],
       [
         [
           {:op, 1, :"/=", {:var, 1, v_dest_tag}, {:atom, 1, nil}}
         ]
       ],
       [
         {:call, 1, {:var, 1, loop_fun_name}, [{:var, 1, v_dest_tag}]}
       ]}

    default_check_clause =
      {:clause, 1, [{:var, 1, :_}], [], [{:atom, 1, nil}]}

    case_next_expr =
      {:case, 1, {:var, 1, v_next}, [dest_check_clause, default_check_clause]}

    loop_clauses = [
      {:clause, 1, [{:var, 1, v_tag}], [],
       [
         {:match, 1, {:var, 1, v_next}, try_expr},
         case_next_expr
       ]}
    ]

    first_tag =
      case segments do
        [{t, _, _} | _] -> t
        _ -> :__done__
      end

    {:call, 1, {:named_fun, 1, loop_fun_name, loop_clauses}, [{:atom, 1, first_tag}]}
  end

  defp group_tagbody_segments(elements) do
    # Break elements into [{tag, [exprs], next_tag}]
    raw_segments =
      Enum.reduce(elements, [{:__start__, []}], fn elem, acc ->
        if is_tag?(elem) do
          tag = to_atom_symbol(elem)
          [{tag, []} | acc]
        else
          [{current_tag, exprs} | rest] = acc
          [{current_tag, exprs ++ [elem]} | rest]
        end
      end)
      |> Enum.reverse()

    tags = Enum.map(raw_segments, &elem(&1, 0))
    next_tags = tl(tags) ++ [nil]

    Enum.zip(raw_segments, next_tags)
    |> Enum.map(fn {{tag, exprs}, next_t} -> {tag, exprs, next_t} end)
  end

  defp is_tag?({:list, _, _}), do: false
  defp is_tag?({:quoted, _, _}), do: false
  defp is_tag?(_), do: true

  def compile_go([tag_node | _], local_env) do
    tag = to_atom_symbol(tag_node)

    target_tagbody_id =
      Enum.find_value(local_env, fn
        {:__tagbody_tag__, ^tag, tagbody_id} -> tagbody_id
        _ -> nil
      end)

    {:call, 1, {:remote, 1, {:atom, 1, :erlang}, {:atom, 1, :throw}},
     [{:tuple, 1, [{:atom, 1, :lisp_go}, {:atom, 1, target_tagbody_id}, {:atom, 1, tag}]}]}
  end

  # --- Loops (dotimes, dolist) ---

  def compile_dotimes([header | body_nodes], local_env) do
    {var_name, count_node, result_node} =
      case header do
        {:list, _pos, [v, c, r | _]} -> {extract_symbol_name(v), c, r}
        {:list, _pos, [v, c]} -> {extract_symbol_name(v), c, {:atom, 1, nil}}
        {:quoted, _pos, [v, c, r | _]} -> {extract_symbol_name(v), c, r}
        {:quoted, _pos, [v, c]} -> {extract_symbol_name(v), c, {:atom, 1, nil}}
        _ -> raise ArgumentError, "Invalid dotimes header: #{inspect(header)}"
      end

    mutated_in_body = find_mutated_vars(body_nodes)

    threaded_vars =
      Enum.filter(mutated_in_body, fn v ->
        (MapSet.member?(local_env, v) or MapSet.member?(local_env, {:mutated, v})) and
          v != var_name
      end)

    if can_thread_loop?(body_nodes, threaded_vars) do
      compile_threaded_dotimes(
        var_name,
        count_node,
        result_node,
        body_nodes,
        threaded_vars,
        local_env
      )
    else
      compile_standard_dotimes(var_name, count_node, result_node, body_nodes, local_env)
    end
  end

  defp compile_standard_dotimes(var_name, count_node, result_node, body_nodes, local_env) do
    loop_fun_name = :"Loop_#{System.unique_integer([:positive, :monotonic])}"
    var_erl = erl_var_name(var_name)
    body_env = MapSet.put(local_env, var_name)
    compiled_body = Enum.map(body_nodes, &compile_expr(&1, body_env))

    loop_clauses = [
      {:clause, 1, [{:var, 1, var_erl}, {:var, 1, :V_limit}],
       [[{:op, 1, :>=, {:var, 1, var_erl}, {:var, 1, :V_limit}}]],
       [compile_expr(result_node, local_env)]},
      {:clause, 1, [{:var, 1, var_erl}, {:var, 1, :V_limit}], [],
       compiled_body ++
         [
           {:call, 1, {:var, 1, loop_fun_name},
            [{:op, 1, :+, {:var, 1, var_erl}, {:integer, 1, 1}}, {:var, 1, :V_limit}]}
         ]}
    ]

    {:call, 1, {:named_fun, 1, loop_fun_name, loop_clauses},
     [{:integer, 1, 0}, compile_expr(count_node, local_env)]}
  end

  defp compile_threaded_dotimes(
         var_name,
         count_node,
         result_node,
         body_nodes,
         threaded_vars,
         local_env
       ) do
    loop_fun_name = :"Loop_#{System.unique_integer([:positive, :monotonic])}"
    var_erl = erl_var_name(var_name)

    initial_threaded_map = Map.new(threaded_vars, fn v -> {v, erl_var_name(v)} end)
    threaded_erl_params = Enum.map(threaded_vars, fn v -> {:var, 1, initial_threaded_map[v]} end)

    # Termination clause: I >= Limit
    result_env = make_threaded_env(local_env, initial_threaded_map) |> MapSet.put(var_name)

    sync_exprs =
      Enum.map(threaded_vars, fn v ->
        {:call, 1, {:remote, 1, {:atom, 1, ExLisp.Env}, {:atom, 1, :set_lexical_var}},
         [{:atom, 1, v}, {:var, 1, initial_threaded_map[v]}]}
      end)

    compiled_result = compile_expr(result_node, result_env)
    term_body = sync_exprs ++ [compiled_result]

    term_clause =
      {:clause, 1, [{:var, 1, var_erl}, {:var, 1, :V_limit} | threaded_erl_params],
       [[{:op, 1, :>=, {:var, 1, var_erl}, {:var, 1, :V_limit}}]], term_body}

    # Continuation clause: I < Limit
    base_step_env = MapSet.put(local_env, var_name)

    {step_exprs, final_map} =
      compile_threaded_body(body_nodes, initial_threaded_map, base_step_env, threaded_vars)

    next_threaded_args = Enum.map(threaded_vars, fn v -> {:var, 1, final_map[v]} end)

    loop_call =
      {:call, 1, {:var, 1, loop_fun_name},
       [
         {:op, 1, :+, {:var, 1, var_erl}, {:integer, 1, 1}},
         {:var, 1, :V_limit} | next_threaded_args
       ]}

    step_clause =
      {:clause, 1, [{:var, 1, var_erl}, {:var, 1, :V_limit} | threaded_erl_params], [],
       step_exprs ++ [loop_call]}

    loop_clauses = [term_clause, step_clause]

    initial_threaded_args =
      Enum.map(threaded_vars, fn v ->
        compile_expr({:id, 1, [Atom.to_string(v)]}, local_env)
      end)

    {:call, 1, {:named_fun, 1, loop_fun_name, loop_clauses},
     [{:integer, 1, 0}, compile_expr(count_node, local_env) | initial_threaded_args]}
  end

  def compile_dolist([header | body_nodes], local_env) do
    {var_name, list_node, result_node} =
      case header do
        {:list, _pos, [v, l, r | _]} -> {extract_symbol_name(v), l, r}
        {:list, _pos, [v, l]} -> {extract_symbol_name(v), l, {:atom, 1, nil}}
        {:quoted, _pos, [v, l, r | _]} -> {extract_symbol_name(v), l, r}
        {:quoted, _pos, [v, l]} -> {extract_symbol_name(v), l, {:atom, 1, nil}}
        _ -> raise ArgumentError, "Invalid dolist header: #{inspect(header)}"
      end

    mutated_in_body = find_mutated_vars(body_nodes)

    threaded_vars =
      Enum.filter(mutated_in_body, fn v ->
        (MapSet.member?(local_env, v) or MapSet.member?(local_env, {:mutated, v})) and
          v != var_name
      end)

    if can_thread_loop?(body_nodes, threaded_vars) do
      compile_threaded_dolist(
        var_name,
        list_node,
        result_node,
        body_nodes,
        threaded_vars,
        local_env
      )
    else
      compile_standard_dolist(var_name, list_node, result_node, body_nodes, local_env)
    end
  end

  defp compile_standard_dolist(var_name, list_node, result_node, body_nodes, local_env) do
    loop_fun_name = :"Loop_#{System.unique_integer([:positive, :monotonic])}"
    var_erl = erl_var_name(var_name)
    body_env = MapSet.put(local_env, var_name)
    compiled_body = Enum.map(body_nodes, &compile_expr(&1, body_env))

    loop_clauses = [
      {:clause, 1, [{nil, 1}], [], [compile_expr(result_node, local_env)]},
      {:clause, 1, [{:atom, 1, nil}], [], [compile_expr(result_node, local_env)]},
      {:clause, 1, [{:cons, 1, {:var, 1, var_erl}, {:var, 1, :V_tail}}], [],
       compiled_body ++
         [
           {:call, 1, {:var, 1, loop_fun_name}, [{:var, 1, :V_tail}]}
         ]}
    ]

    {:call, 1, {:named_fun, 1, loop_fun_name, loop_clauses}, [compile_expr(list_node, local_env)]}
  end

  defp compile_threaded_dolist(
         var_name,
         list_node,
         result_node,
         body_nodes,
         threaded_vars,
         local_env
       ) do
    loop_fun_name = :"Loop_#{System.unique_integer([:positive, :monotonic])}"
    var_erl = erl_var_name(var_name)

    initial_threaded_map = Map.new(threaded_vars, fn v -> {v, erl_var_name(v)} end)
    threaded_erl_params = Enum.map(threaded_vars, fn v -> {:var, 1, initial_threaded_map[v]} end)

    # Termination clause: [] or nil
    result_env = make_threaded_env(local_env, initial_threaded_map) |> MapSet.put(var_name)

    sync_exprs =
      Enum.map(threaded_vars, fn v ->
        {:call, 1, {:remote, 1, {:atom, 1, ExLisp.Env}, {:atom, 1, :set_lexical_var}},
         [{:atom, 1, v}, {:var, 1, initial_threaded_map[v]}]}
      end)

    compiled_result = compile_expr(result_node, result_env)
    term_body = sync_exprs ++ [compiled_result]

    term_clause_nil =
      {:clause, 1, [{nil, 1} | threaded_erl_params], [], term_body}

    term_clause_atom_nil =
      {:clause, 1, [{:atom, 1, nil} | threaded_erl_params], [], term_body}

    # Continuation clause: [Head | Tail]
    base_step_env = MapSet.put(local_env, var_name)

    {step_exprs, final_map} =
      compile_threaded_body(body_nodes, initial_threaded_map, base_step_env, threaded_vars)

    next_threaded_args = Enum.map(threaded_vars, fn v -> {:var, 1, final_map[v]} end)

    loop_call =
      {:call, 1, {:var, 1, loop_fun_name}, [{:var, 1, :V_tail} | next_threaded_args]}

    step_clause =
      {:clause, 1, [{:cons, 1, {:var, 1, var_erl}, {:var, 1, :V_tail}} | threaded_erl_params], [],
       step_exprs ++ [loop_call]}

    loop_clauses = [term_clause_nil, term_clause_atom_nil, step_clause]

    initial_threaded_args =
      Enum.map(threaded_vars, fn v ->
        compile_expr({:id, 1, [Atom.to_string(v)]}, local_env)
      end)

    {:call, 1, {:named_fun, 1, loop_fun_name, loop_clauses},
     [compile_expr(list_node, local_env) | initial_threaded_args]}
  end

  defp make_threaded_env(base_env, var_map) do
    keys = Map.keys(var_map) |> MapSet.new()

    cleaned_env =
      Enum.reject(base_env, fn
        {:mutated, v} -> MapSet.member?(keys, v)
        {:renamed_var, v, _} -> MapSet.member?(keys, v)
        v when is_atom(v) -> MapSet.member?(keys, v)
        _ -> false
      end)
      |> MapSet.new()

    Enum.reduce(var_map, cleaned_env, fn {v, erl_name}, acc ->
      MapSet.put(acc, {:renamed_var, v, erl_name})
    end)
  end

  defp can_thread_loop?(body_nodes, threaded_vars) do
    threaded_vars != [] and
      Enum.all?(body_nodes, &flat_threadable_expr?(&1, MapSet.new(threaded_vars)))
  end

  defp flat_threadable_expr?({:list, _pos, [op | args]}, threaded_set) do
    op_name = extract_symbol_name(op)

    case op_name do
      name when name in [:setq, :_cl_setq_] ->
        pairs = Enum.chunk_every(args, 2)

        Enum.all?(pairs, fn
          [var_node, val_node] ->
            v = extract_symbol_name(var_node)
            MapSet.member?(threaded_set, v) and not contains_disallowed_loop_forms?(val_node)

          _ ->
            false
        end)

      name when name in [:incf, :_cl_incf_, :decf, :_cl_decf_] ->
        case args do
          [var_node | rest] ->
            v = extract_symbol_name(var_node)

            MapSet.member?(threaded_set, v) and
              Enum.all?(rest, &(not contains_disallowed_loop_forms?(&1)))

          _ ->
            false
        end

      name
      when name in [
             :block,
             :return_from,
             :tagbody,
             :go,
             :catch,
             :throw,
             :unwind_protect,
             :flet,
             :labels,
             :lambda,
             :defun,
             :defmacro
           ] ->
        false

      _ ->
        not contains_disallowed_loop_forms?({:list, 0, [op | args]})
    end
  end

  defp flat_threadable_expr?(other, _threaded_set) do
    not contains_disallowed_loop_forms?(other)
  end

  defp contains_disallowed_loop_forms?({:list, _pos, [op | _args] = elements}) do
    op_name = extract_symbol_name(op)

    cond do
      op_name in [
        :block,
        :return_from,
        :tagbody,
        :go,
        :catch,
        :throw,
        :unwind_protect,
        :flet,
        :labels,
        :lambda,
        :defun,
        :defmacro,
        :setq,
        :_cl_setq_,
        :setf,
        :_cl_setf_,
        :psetq,
        :_cl_psetq_,
        :incf,
        :_cl_incf_,
        :decf,
        :_cl_decf_,
        :pop,
        :_cl_pop_,
        :push,
        :_cl_push_
      ] ->
        true

      true ->
        Enum.any?(elements, &contains_disallowed_loop_forms?/1)
    end
  end

  defp contains_disallowed_loop_forms?({:quoted, _pos, _}), do: false

  defp contains_disallowed_loop_forms?(list) when is_list(list),
    do: Enum.any?(list, &contains_disallowed_loop_forms?/1)

  defp contains_disallowed_loop_forms?(_), do: false

  defp compile_threaded_body(body_nodes, initial_map, base_env, threaded_vars) do
    threaded_set = MapSet.new(threaded_vars)

    Enum.reduce(body_nodes, {[], initial_map}, fn expr, {exprs_acc, cur_map} ->
      env = make_threaded_env(base_env, cur_map)

      case expr do
        {:list, _pos, [op | args]} ->
          op_name = extract_symbol_name(op)

          cond do
            op_name in [:setq, :_cl_setq_] ->
              pairs = Enum.chunk_every(args, 2)

              Enum.reduce(pairs, {exprs_acc, cur_map}, fn
                [var_node, val_node], {inner_exprs, inner_map} ->
                  v = extract_symbol_name(var_node)
                  inner_env = make_threaded_env(base_env, inner_map)
                  compiled_val = compile_expr(val_node, inner_env)

                  if MapSet.member?(threaded_set, v) do
                    new_erl_var = :"V_#{v}_#{System.unique_integer([:positive, :monotonic])}"
                    match_expr = {:match, 1, {:var, 1, new_erl_var}, compiled_val}
                    {inner_exprs ++ [match_expr], Map.put(inner_map, v, new_erl_var)}
                  else
                    setq_call =
                      {:call, 1,
                       {:remote, 1, {:atom, 1, ExLisp.Env}, {:atom, 1, :set_lexical_var}},
                       [{:atom, 1, v}, compiled_val]}

                    {inner_exprs ++ [setq_call], inner_map}
                  end

                [var_node], {inner_exprs, inner_map} ->
                  v = extract_symbol_name(var_node)

                  if MapSet.member?(threaded_set, v) do
                    new_erl_var = :"V_#{v}_#{System.unique_integer([:positive, :monotonic])}"
                    match_expr = {:match, 1, {:var, 1, new_erl_var}, {:atom, 1, nil}}
                    {inner_exprs ++ [match_expr], Map.put(inner_map, v, new_erl_var)}
                  else
                    setq_call =
                      {:call, 1,
                       {:remote, 1, {:atom, 1, ExLisp.Env}, {:atom, 1, :set_lexical_var}},
                       [{:atom, 1, v}, {:atom, 1, nil}]}

                    {inner_exprs ++ [setq_call], inner_map}
                  end
              end)

            op_name in [:incf, :_cl_incf_] ->
              case args do
                [var_node | rest] ->
                  delta_node = Enum.at(rest, 0, {:lit, 1})
                  v = extract_symbol_name(var_node)
                  add_ast = {:list, 1, [{:id, 1, ["+"]}, var_node, delta_node]}
                  compiled_val = compile_expr(add_ast, env)

                  if MapSet.member?(threaded_set, v) do
                    new_erl_var = :"V_#{v}_#{System.unique_integer([:positive, :monotonic])}"
                    match_expr = {:match, 1, {:var, 1, new_erl_var}, compiled_val}
                    {exprs_acc ++ [match_expr], Map.put(cur_map, v, new_erl_var)}
                  else
                    setq_call =
                      {:call, 1,
                       {:remote, 1, {:atom, 1, ExLisp.Env}, {:atom, 1, :set_lexical_var}},
                       [{:atom, 1, v}, compiled_val]}

                    {exprs_acc ++ [setq_call], cur_map}
                  end

                _ ->
                  {exprs_acc ++ [compile_expr(expr, env)], cur_map}
              end

            op_name in [:decf, :_cl_decf_] ->
              case args do
                [var_node | rest] ->
                  delta_node = Enum.at(rest, 0, {:lit, 1})
                  v = extract_symbol_name(var_node)
                  sub_ast = {:list, 1, [{:id, 1, ["-"]}, var_node, delta_node]}
                  compiled_val = compile_expr(sub_ast, env)

                  if MapSet.member?(threaded_set, v) do
                    new_erl_var = :"V_#{v}_#{System.unique_integer([:positive, :monotonic])}"
                    match_expr = {:match, 1, {:var, 1, new_erl_var}, compiled_val}
                    {exprs_acc ++ [match_expr], Map.put(cur_map, v, new_erl_var)}
                  else
                    setq_call =
                      {:call, 1,
                       {:remote, 1, {:atom, 1, ExLisp.Env}, {:atom, 1, :set_lexical_var}},
                       [{:atom, 1, v}, compiled_val]}

                    {exprs_acc ++ [setq_call], cur_map}
                  end

                _ ->
                  {exprs_acc ++ [compile_expr(expr, env)], cur_map}
              end

            true ->
              {exprs_acc ++ [compile_expr(expr, env)], cur_map}
          end

        other ->
          {exprs_acc ++ [compile_expr(other, env)], cur_map}
      end
    end)
  end

  defp compile_with_open_file([header | body_nodes], local_env) do
    header_elements =
      case header do
        {:list, _pos, elems} -> elems
        elems when is_list(elems) -> elems
        _ -> raise ArgumentError, "Invalid with-open-file header: #{inspect(header)}"
      end

    case header_elements do
      [var_node, file_node | opt_nodes] ->
        stream_var = extract_symbol_name(var_node)
        erl_var = erl_var_name(stream_var)
        new_env = MapSet.put(local_env, stream_var)

        open_args = [file_node | opt_nodes]
        compiled_open_args = Enum.map(open_args, &compile_expr(&1, local_env))
        open_args_cons = ast_cons_list(compiled_open_args)

        open_call =
          {:call, 1, {:remote, 1, {:atom, 1, ExLisp.Builtins}, {:atom, 1, :open}},
           [open_args_cons]}

        body_exprs =
          case body_nodes do
            [] -> [{:atom, 1, nil}]
            _ -> Enum.map(body_nodes, &compile_expr(&1, new_env))
          end

        close_call =
          {:call, 1, {:remote, 1, {:atom, 1, ExLisp.Builtins}, {:atom, 1, :close}},
           [{:var, 1, erl_var}]}

        {:block, 1,
         [
           {:match, 1, {:var, 1, erl_var}, open_call},
           {:try, 1, body_exprs, [], [], [close_call]}
         ]}

      _ ->
        raise ArgumentError, "Invalid with-open-file header: #{inspect(header)}"
    end
  end

  def compile_defparameter([var_node, val_node | _rest], local_env) do
    var_name = extract_symbol_name(var_node)
    compiled_val = compile_expr(val_node, local_env)

    {:call, 1, {:remote, 1, {:atom, 1, ExLisp.Env}, {:atom, 1, :put_var}},
     [{:atom, 1, var_name}, compiled_val]}
  end

  def compile_defparameter([var_node], _local_env) do
    var_name = extract_symbol_name(var_node)

    {:call, 1, {:remote, 1, {:atom, 1, ExLisp.Env}, {:atom, 1, :put_var}},
     [{:atom, 1, var_name}, {:atom, 1, nil}]}
  end

  def compile_defvar([var_node], _local_env) do
    var_name = extract_symbol_name(var_node)
    lazy_fun = {:fun, 1, {:clauses, [{:clause, 1, [], [], [{:atom, 1, nil}]}]}}

    {:call, 1, {:remote, 1, {:atom, 1, ExLisp.Env}, {:atom, 1, :defvar_lazy}},
     [{:atom, 1, var_name}, lazy_fun]}
  end

  def compile_defvar([var_node, val_node | _rest], local_env) do
    var_name = extract_symbol_name(var_node)
    compiled_val = compile_expr(val_node, local_env)
    lazy_fun = {:fun, 1, {:clauses, [{:clause, 1, [], [], [compiled_val]}]}}

    {:call, 1, {:remote, 1, {:atom, 1, ExLisp.Env}, {:atom, 1, :defvar_lazy}},
     [{:atom, 1, var_name}, lazy_fun]}
  end

  def compile_defun([name_node, params_node | body_nodes], local_env) do
    fun_name = extract_symbol_name(name_node)

    if has_lambda_list_keywords?(params_node) do
      raw_args_sym = :__fn_args__
      {bindings, _} = ExLisp.Macro.build_bindings(params_node, raw_args_sym, raw_args_sym)

      let_star_body =
        {:list, 1,
         [
           {:id, 1, ["let*"]},
           {:list, 1, bindings}
           | body_nodes
         ]}

      new_local_env = MapSet.union(local_env, MapSet.new([fun_name, raw_args_sym]))
      compiled_body = [compile_block([{:atom, 1, fun_name}, let_star_body], new_local_env)]
      named_fun_name = erl_var_name(fun_name)

      fun_expr =
        {:named_fun, 1, named_fun_name,
         [{:clause, 1, [{:var, 1, erl_var_name(raw_args_sym)}], [], compiled_body}]}

      wrapped_closure =
        {:call, 1, {:remote, 1, {:atom, 1, ExLisp.Closure}, {:atom, 1, :new}},
         [fun_expr, {:atom, 1, fun_name}]}

      {:call, 1, {:remote, 1, {:atom, 1, ExLisp.Env}, {:atom, 1, :put_fun}},
       [{:atom, 1, fun_name}, wrapped_closure]}
    else
      param_names = extract_param_names(params_node)
      mutated = find_mutated_vars(body_nodes)

      new_local_env =
        Enum.reduce(param_names, MapSet.put(local_env, {:direct_fn, fun_name}), fn p, acc ->
          acc = acc |> MapSet.delete(p) |> MapSet.delete({:mutated, p})

          if MapSet.member?(mutated, p) do
            MapSet.put(acc, {:mutated, p})
          else
            MapSet.put(acc, p)
          end
        end)

      mutated_params = Enum.filter(param_names, &MapSet.member?(mutated, &1))

      init_erases =
        Enum.map(mutated_params, fn p ->
          {:call, 1, {:remote, 1, {:atom, 1, :erlang}, {:atom, 1, :erase}}, [{:atom, 1, p}]}
        end)

      compiled_body =
        case body_nodes do
          [] -> init_erases ++ [{:atom, 1, nil}]
          _ -> init_erases ++ [compile_block([{:atom, 1, fun_name} | body_nodes], new_local_env)]
        end

      erl_params = Enum.map(param_names, fn p -> {:var, 1, erl_var_name(p)} end)
      named_fun_name = erl_var_name(fun_name)
      fun_expr = {:named_fun, 1, named_fun_name, [{:clause, 1, erl_params, [], compiled_body}]}

      {:call, 1, {:remote, 1, {:atom, 1, ExLisp.Env}, {:atom, 1, :put_fun}},
       [{:atom, 1, fun_name}, fun_expr]}
    end
  end

  def compile_defstruct([name_spec | slot_specs], local_env) do
    struct_name =
      case name_spec do
        {:list, _pos, [name | _]} -> extract_symbol_name(name)
        _ -> extract_symbol_name(name_spec)
      end

    parsed_slots =
      Enum.map(slot_specs, fn
        {:list, _pos, [slot_name, default_val | _]} ->
          {extract_symbol_name(slot_name), compile_expr(default_val, local_env)}

        slot_name ->
          {extract_symbol_name(slot_name), {:atom, 1, nil}}
      end)

    make_fn_name = :"make_#{struct_name}"

    defaults_cons =
      ast_cons_list(
        Enum.map(parsed_slots, fn {s, def_expr} ->
          {:tuple, 1, [{:atom, 1, s}, def_expr]}
        end)
      )

    make_body = [
      {:call, 1, {:remote, 1, {:atom, 1, ExLisp.Builtins}, {:atom, 1, :make_struct}},
       [{:atom, 1, struct_name}, defaults_cons, {:var, 1, :V_args}]}
    ]

    make_fun_expr = {:fun, 1, {:clauses, [{:clause, 1, [{:var, 1, :V_args}], [], make_body}]}}

    p_fn_name = :"#{struct_name}_p"

    p_body = [
      {:case, 1, {:var, 1, :V_s},
       [
         {:clause, 1,
          [{:tuple, 1, [{:atom, 1, :struct}, {:atom, 1, struct_name}, {:var, 1, :_}]}], [],
          [{:atom, 1, :t}]},
         {:clause, 1, [{:var, 1, :_}], [], [{:atom, 1, nil}]}
       ]}
    ]

    p_fun_expr = {:fun, 1, {:clauses, [{:clause, 1, [{:var, 1, :V_s}], [], p_body}]}}

    copy_fn_name = :"copy_#{struct_name}"

    copy_body = [
      {:call, 1, {:remote, 1, {:atom, 1, ExLisp.Builtins}, {:atom, 1, :copy_struct}},
       [{:var, 1, :V_s}]}
    ]

    copy_fun_expr = {:fun, 1, {:clauses, [{:clause, 1, [{:var, 1, :V_s}], [], copy_body}]}}

    accessor_exprs =
      Enum.map(parsed_slots, fn {slot, _} ->
        acc_fn_name = :"#{struct_name}_#{slot}"

        acc_body = [
          {:call, 1, {:remote, 1, {:atom, 1, ExLisp.Builtins}, {:atom, 1, :get_struct_slot}},
           [{:var, 1, :V_s}, {:atom, 1, slot}]}
        ]

        acc_fun = {:fun, 1, {:clauses, [{:clause, 1, [{:var, 1, :V_s}], [], acc_body}]}}

        {:call, 1, {:remote, 1, {:atom, 1, ExLisp.Env}, {:atom, 1, :put_fun}},
         [{:atom, 1, acc_fn_name}, acc_fun]}
      end)

    exprs =
      [
        {:call, 1, {:remote, 1, {:atom, 1, ExLisp.Env}, {:atom, 1, :put_fun}},
         [{:atom, 1, make_fn_name}, make_fun_expr]},
        {:call, 1, {:remote, 1, {:atom, 1, ExLisp.Env}, {:atom, 1, :put_fun}},
         [{:atom, 1, p_fn_name}, p_fun_expr]},
        {:call, 1, {:remote, 1, {:atom, 1, ExLisp.Env}, {:atom, 1, :put_fun}},
         [{:atom, 1, copy_fn_name}, copy_fun_expr]}
      ] ++ accessor_exprs ++ [{:atom, 1, struct_name}]

    {:block, 1, exprs}
  end

  def compile_defclass([name_node, _supers_node | _slot_nodes], _local_env) do
    class_name = extract_symbol_name(name_node)
    {:atom, 1, class_name}
  end

  def compile_defgeneric([name_node | _rest], _local_env) do
    gen_name = extract_symbol_name(name_node)
    {:atom, 1, gen_name}
  end

  def compile_defmethod([name_node, params_node | body_nodes], local_env) do
    method_name = extract_symbol_name(name_node)

    param_list =
      case params_node do
        {:list, _pos, elems} -> elems
        elems when is_list(elems) -> elems
        _ -> []
      end

    {param_names, param_types} =
      Enum.map(param_list, fn
        {:list, _pos, [p, type_node | _]} ->
          {extract_symbol_name(p), extract_symbol_name(type_node)}

        p ->
          {extract_symbol_name(p), :t}
      end)
      |> Enum.unzip()

    new_local_env = MapSet.union(local_env, MapSet.new(param_names))

    compiled_body =
      case body_nodes do
        [] -> [{:atom, 1, nil}]
        _ -> [compile_block([{:atom, 1, method_name} | body_nodes], new_local_env)]
      end

    erl_params = Enum.map(param_names, fn p -> {:var, 1, erl_var_name(p)} end)
    fun_expr = {:fun, 1, {:clauses, [{:clause, 1, erl_params, [], compiled_body}]}}

    types_list_ast = ast_cons_list(Enum.map(param_types, &{:atom, 1, &1}))

    {:call, 1, {:remote, 1, {:atom, 1, ExLisp.Env}, {:atom, 1, :register_method}},
     [{:atom, 1, method_name}, types_list_ast, fun_expr]}
  end

  def compile_defmacro([name_node, params_node | body_nodes], local_env) do
    macro_name = extract_symbol_name(name_node)
    lambda_ast = ExLisp.Macro.build_macro_lambda(params_node, body_nodes)

    # Register in compile-time environment immediately
    try do
      macro_fun = evaluate_ast(lambda_ast)
      ExLisp.Env.put_macro(macro_name, macro_fun)
    rescue
      _ -> :ok
    end

    # Generate Form that calls Env.put_macro at runtime as well
    compiled_lambda = compile_expr(lambda_ast, local_env)

    {:call, 1, {:remote, 1, {:atom, 1, ExLisp.Env}, {:atom, 1, :put_macro}},
     [{:atom, 1, macro_name}, compiled_lambda]}
  end

  def compile_macrolet([bindings_node | body_nodes], local_env) do
    macro_defs = extract_fn_bindings(bindings_node)

    local_macros =
      Map.new(macro_defs, fn {name, params, fn_body} ->
        lambda_ast = ExLisp.Macro.build_macro_lambda(params, fn_body)
        macro_fun = evaluate_ast(lambda_ast)
        {name, macro_fun}
      end)

    expanded_body_nodes = Enum.map(body_nodes, &expand_local_macros(&1, local_macros))

    case expanded_body_nodes do
      [] -> {:atom, 1, nil}
      [single] -> compile_expr(single, local_env)
      _ -> {:block, 1, Enum.map(expanded_body_nodes, &compile_expr(&1, local_env))}
    end
  end

  defp expand_local_macros(ast, local_macros) do
    case ast do
      {:list, line, [op | args]} ->
        op_name = extract_symbol_name(op)

        cond do
          is_atom(op_name) and Map.has_key?(local_macros, op_name) ->
            macro_fun = Map.get(local_macros, op_name)
            lisp_args = Enum.map(args, &ExLisp.Macro.ast_to_lisp_data/1)
            lisp_whole = ExLisp.Macro.ast_to_lisp_data(ast)

            expanded_data =
              if is_function(macro_fun, 2) do
                macro_fun.(lisp_args, lisp_whole)
              else
                macro_fun.(lisp_args)
              end

            expanded_ast = ExLisp.Macro.lisp_data_to_ast(expanded_data, line)
            expand_local_macros(expanded_ast, local_macros)

          is_atom(op_name) and ExLisp.Env.has_macro?(op_name) ->
            macro_fun = ExLisp.Env.get_macro(op_name)
            lisp_args = Enum.map(args, &ExLisp.Macro.ast_to_lisp_data/1)
            lisp_whole = ExLisp.Macro.ast_to_lisp_data(ast)

            expanded_data =
              if is_function(macro_fun, 2) do
                macro_fun.(lisp_args, lisp_whole)
              else
                macro_fun.(lisp_args)
              end

            expanded_ast = ExLisp.Macro.lisp_data_to_ast(expanded_data, line)
            expand_local_macros(expanded_ast, local_macros)

          op_name in [:tagbody, :_cl_tagbody_] ->
            expanded_args =
              Enum.map(args, fn
                {:list, _, _} = item ->
                  expanded = expand_local_macros(item, local_macros)

                  case expanded do
                    {:list, _, _} -> expanded
                    _non_list -> {:list, line, [{:id, line, ["progn"]}, expanded]}
                  end

                other ->
                  other
              end)

            {:list, line, [op | expanded_args]}

          true ->
            {:list, line,
             [
               expand_local_macros(op, local_macros)
               | Enum.map(args, &expand_local_macros(&1, local_macros))
             ]}
        end

      _ ->
        ast
    end
  end

  def compile_regular_op(op, args, local_env) do
    op_name = extract_symbol_name(op)

    cond do
      is_atom(op_name) and not MapSet.member?(local_env, op_name) and
          ExLisp.Env.has_macro?(op_name) ->
        # Global macro expansion
        macro_fun = ExLisp.Env.get_macro(op_name)
        lisp_args = Enum.map(args, &ExLisp.Macro.ast_to_lisp_data/1)
        lisp_whole = ExLisp.Macro.ast_to_lisp_data({:list, 1, [op | args]})

        expanded_lisp_data =
          if is_function(macro_fun, 2) do
            macro_fun.(lisp_args, lisp_whole)
          else
            macro_fun.(lisp_args)
          end

        expanded_ast = ExLisp.Macro.lisp_data_to_ast(expanded_lisp_data)
        compile_expr(expanded_ast, local_env)

      match?({:list, _, _}, op) or match?({:quoted, _, _}, op) or is_list(op) ->
        compiled_fn = compile_expr(op, local_env)
        compiled_args = Enum.map(args, &compile_expr(&1, local_env))

        args_cons =
          Enum.reduce(Enum.reverse(compiled_args), {nil, 1}, fn elem, acc ->
            {:cons, 1, elem, acc}
          end)

        {:call, 1, {:remote, 1, {:atom, 1, ExLisp.Builtins}, {:atom, 1, :funcall}},
         [compiled_fn, args_cons]}

      true ->
        cond do
          is_atom(op_name) and MapSet.member?(local_env, {:direct_fn, op_name}) ->
            compiled_args = Enum.map(args, &compile_expr(&1, local_env))
            {:call, 1, {:var, 1, erl_var_name(op_name)}, compiled_args}

          is_atom(op_name) and MapSet.member?(local_env, {:closure_fn, op_name}) ->
            compiled_args = Enum.map(args, &compile_expr(&1, local_env))

            erl_args_cons =
              Enum.reduce(Enum.reverse(compiled_args), {nil, 1}, fn elem, acc ->
                {:cons, 1, elem, acc}
              end)

            {:call, 1, {:remote, 1, {:atom, 1, ExLisp.Builtins}, {:atom, 1, :invoke_fn}},
             [{:var, 1, erl_var_name(op_name)}, erl_args_cons]}

          match?({:ok, _}, BuiltinFunction.lookup(op)) ->
            {:ok, builtin_op} = BuiltinFunction.lookup(op)
            BuiltinFunction.compile(builtin_op, args, &compile_expr(&1, local_env))

          is_atom(op_name) and ExLisp.Env.has_fun?(op_name) ->
            compiled_args = Enum.map(args, &compile_expr(&1, local_env))

            erl_args_cons =
              Enum.reduce(Enum.reverse(compiled_args), {nil, 1}, fn elem, acc ->
                {:cons, 1, elem, acc}
              end)

            {:call, 1, {:remote, 1, {:atom, 1, ExLisp.Env}, {:atom, 1, :call_fun}},
             [{:atom, 1, op_name}, erl_args_cons]}

          match?({:remote, _, _}, normalize_remote_op(op)) ->
            {:remote, mod, fun} = normalize_remote_op(op)

            {:call, 1, {:remote, 1, {:atom, 1, mod}, {:atom, 1, fun}},
             Enum.map(args, &compile_expr(&1, local_env))}

          true ->
            compiled_args = Enum.map(args, &compile_expr(&1, local_env))

            erl_args_cons =
              Enum.reduce(Enum.reverse(compiled_args), {nil, 1}, fn elem, acc ->
                {:cons, 1, elem, acc}
              end)

            {:call, 1, {:remote, 1, {:atom, 1, ExLisp.Env}, {:atom, 1, :call_fun}},
             [{:atom, 1, op_name}, erl_args_cons]}
        end
    end
  end

  defp has_lambda_list_keywords?(params_node) do
    elems =
      case params_node do
        {:list, _pos, es} -> es
        {:quoted, _pos, es} -> es
        es when is_list(es) -> es
        _ -> []
      end

    Enum.any?(elems, fn
      {:id, _, [name]} -> String.starts_with?(name, "&")
      {:list, _, _} -> true
      {:quoted, _, _} -> true
      atom when is_atom(atom) -> String.starts_with?(Atom.to_string(atom), "&")
      name when is_binary(name) -> String.starts_with?(name, "&")
      _ -> false
    end)
  end

  def ast_cons_list(list, tail \\ {nil, 1}) do
    Enum.reduce(Enum.reverse(list), tail, fn elem, acc ->
      {:cons, 1, elem, acc}
    end)
  end

  def extract_param_names({:list, _pos, elements}),
    do: Enum.map(elements, &extract_symbol_name/1)

  def extract_param_names({:quoted, _pos, elements}),
    do: Enum.map(elements, &extract_symbol_name/1)

  def extract_param_names(elements) when is_list(elements),
    do: Enum.map(elements, &extract_symbol_name/1)

  def extract_param_names(_), do: []

  def extract_symbol_name({:id, _pos, [name]}) when is_binary(name) do
    if String.starts_with?(name, "|") or String.starts_with?(name, ":|") do
      String.to_atom(name)
    else
      String.downcase(name) |> String.to_atom()
    end
  end

  def extract_symbol_name({:id, _pos, parts}) when is_list(parts) do
    case parts do
      ["#", name] ->
        String.downcase(name) |> String.to_atom()

      [sym] when is_atom(sym) ->
        str = Atom.to_string(sym)

        if String.starts_with?(str, "|") or String.starts_with?(str, ":|") do
          sym
        else
          str |> String.downcase() |> String.to_atom()
        end

      _ ->
        Enum.join(parts, ".") |> String.downcase() |> String.to_atom()
    end
  end

  def extract_symbol_name({:lit, atom}) when is_atom(atom) do
    str = Atom.to_string(atom)

    if String.starts_with?(str, "|") or String.starts_with?(str, ":|") do
      atom
    else
      str |> String.downcase() |> String.to_atom()
    end
  end

  def extract_symbol_name(atom) when is_atom(atom) do
    str = Atom.to_string(atom)

    if String.starts_with?(str, "|") or String.starts_with?(str, ":|") do
      atom
    else
      str |> String.downcase() |> String.to_atom()
    end
  end

  def extract_symbol_name(name) when is_binary(name) do
    if String.starts_with?(name, "|") or String.starts_with?(name, ":|") do
      String.to_atom(name)
    else
      String.downcase(name) |> String.to_atom()
    end
  end

  def extract_symbol_name({:list, _pos, [{:id, _, [s]}, inner]}) when s in ["setf", "SETF"] do
    inner_sym = extract_symbol_name(inner)
    :"setf_#{inner_sym}"
  end

  def extract_symbol_name([:setf, inner]) do
    inner_sym = extract_symbol_name(inner)
    :"setf_#{inner_sym}"
  end

  def extract_symbol_name(other), do: other

  def extract_op_name({:id, _pos, parts}) when is_list(parts) do
    case parts do
      [name] ->
        if String.contains?(name, ":") do
          nil
        else
          String.downcase(name) |> String.to_atom()
        end

      _ ->
        mod = Enum.drop(parts, -1) |> build_module_atom()

        if valid_remote_module?(mod) do
          nil
        else
          Enum.join(parts, ".") |> String.downcase() |> String.to_atom()
        end
    end
  end

  def extract_op_name({:lit, atom}) when is_atom(atom) do
    Atom.to_string(atom) |> String.downcase() |> String.to_atom()
  end

  def extract_op_name(atom) when is_atom(atom) do
    Atom.to_string(atom) |> String.downcase() |> String.to_atom()
  end

  def extract_op_name(name) when is_binary(name) do
    String.downcase(name) |> String.to_atom()
  end

  def extract_op_name(_), do: nil

  def erl_var_name(atom_name) when is_atom(atom_name) do
    String.to_atom("V_" <> Atom.to_string(atom_name))
  end

  def erl_var_name(name) when is_binary(name) do
    clean_name = name |> String.downcase() |> String.replace(~r/[^a-zA-Z0-9_]/, "_")
    String.to_atom("V_" <> clean_name)
  end

  def erl_var_name(%ExLisp.Symbol{name: name}) do
    erl_var_name(name)
  end

  def erl_var_name(other) do
    clean = extract_symbol_name(other)

    if is_atom(clean) and not is_nil(clean) do
      erl_var_name(clean)
    else
      String.to_atom("V_#{System.unique_integer([:positive])}")
    end
  end

  defp valid_remote_module?(mod) do
    case mod do
      atom when is_atom(atom) ->
        mod_str = Atom.to_string(atom)

        if String.starts_with?(mod_str, "Elixir.") do
          Code.ensure_loaded?(atom)
        else
          case :code.ensure_loaded(atom) do
            {:module, ^atom} -> true
            _ -> false
          end
        end

      _ ->
        false
    end
  end

  defp normalize_remote_op({:id, _pos, parts}) when is_list(parts) and length(parts) >= 2 do
    mod = Enum.drop(parts, -1) |> build_module_atom()
    fun = List.last(parts) |> String.to_atom()

    if valid_remote_module?(mod) do
      {:remote, mod, fun}
    else
      {:unsupported, Enum.join(parts, ".")}
    end
  end

  defp normalize_remote_op({:id, _pos, [name]}) when is_binary(name) do
    if String.contains?(name, ".") or String.contains?(name, ":") do
      parts = String.split(name, ~r/[:.]/) |> Enum.reject(&(&1 == ""))

      if length(parts) >= 2 do
        mod = Enum.drop(parts, -1) |> build_module_atom()
        fun = List.last(parts) |> String.to_atom()

        if valid_remote_module?(mod) do
          {:remote, mod, fun}
        else
          {:unsupported, name}
        end
      else
        {:unsupported, name}
      end
    else
      {:unsupported, name}
    end
  end

  defp normalize_remote_op({:lit, atom}) when is_atom(atom), do: normalize_atom_remote_op(atom)
  defp normalize_remote_op(op) when is_atom(op), do: normalize_atom_remote_op(op)
  defp normalize_remote_op(op), do: op

  defp normalize_atom_remote_op(atom) do
    str = Atom.to_string(atom)

    if String.contains?(str, ":") or String.contains?(str, ".") do
      parts = String.split(str, ~r/[:.]/) |> Enum.reject(&(&1 == ""))

      if length(parts) >= 2 do
        fun = List.last(parts) |> String.to_atom()
        mod = Enum.drop(parts, -1) |> build_module_atom()
        {:remote, mod, fun}
      else
        {:unsupported, atom}
      end
    else
      {:unsupported, atom}
    end
  end

  defp build_module_atom(mod_parts) do
    first = hd(mod_parts)

    if first =~ ~r/^[A-Z]/ do
      Module.concat(mod_parts)
    else
      mod_parts
      |> Enum.map(&String.trim_leading(&1, ":"))
      |> Enum.join(".")
      |> String.to_atom()
    end
  end

  # --- ANSI Common Lisp Control & Data Flow Forms ---

  def compile_catch(args, local_env) do
    case args do
      [tag_node | body_nodes] ->
        compiled_tag = compile_expr(tag_node, local_env)
        tag_var = :"V_tag_#{System.unique_integer([:positive, :monotonic])}"
        val_var = :"V_val_#{System.unique_integer([:positive, :monotonic])}"
        caught_tag_var = :"V_ctag_#{System.unique_integer([:positive, :monotonic])}"

        compiled_body =
          case body_nodes do
            [] -> [{:atom, 1, nil}]
            _ -> Enum.map(body_nodes, &compile_expr(&1, local_env))
          end

        catch_clause1 =
          {:clause, 1,
           [
             {:tuple, 1,
              [
                {:atom, 1, :throw},
                {:tuple, 1, [{:var, 1, caught_tag_var}, {:var, 1, val_var}]},
                {:var, 1, :_}
              ]}
           ], [[{:op, 1, :"=:=", {:var, 1, caught_tag_var}, {:var, 1, tag_var}}]],
           [{:var, 1, val_var}]}

        catch_clause2 =
          {:clause, 1,
           [
             {:tuple, 1,
              [
                {:atom, 1, :throw},
                {:tuple, 1, [{:var, 1, caught_tag_var}, {:var, 1, val_var}]},
                {:var, 1, :_}
              ]}
           ], [],
           [
             {:call, 1, {:remote, 1, {:atom, 1, :erlang}, {:atom, 1, :throw}},
              [{:tuple, 1, [{:var, 1, caught_tag_var}, {:var, 1, val_var}]}]}
           ]}

        {:block, 1,
         [
           {:match, 1, {:var, 1, tag_var}, compiled_tag},
           {:try, 1, compiled_body, [], [catch_clause1, catch_clause2], []}
         ]}

      _ ->
        {:atom, 1, nil}
    end
  end

  def compile_throw(args, local_env) do
    case args do
      [tag_node, val_node | _] ->
        compiled_tag = compile_expr(tag_node, local_env)
        compiled_val = compile_expr(val_node, local_env)

        {:call, 1, {:remote, 1, {:atom, 1, :erlang}, {:atom, 1, :throw}},
         [{:tuple, 1, [compiled_tag, compiled_val]}]}

      [tag_node] ->
        compiled_tag = compile_expr(tag_node, local_env)

        {:call, 1, {:remote, 1, {:atom, 1, :erlang}, {:atom, 1, :throw}},
         [{:tuple, 1, [compiled_tag, {:atom, 1, nil}]}]}

      _ ->
        {:atom, 1, nil}
    end
  end

  defp rewrite_mv_form(form) do
    case form do
      {:list, pos, [{:id, id_pos, [op_name]} | form_args]}
      when op_name in ["gethash", "GETHASH"] ->
        {:list, pos, [{:id, id_pos, ["gethash_mv"]} | form_args]}

      {:quoted, pos, [{:id, id_pos, [op_name]} | form_args]}
      when op_name in ["gethash", "GETHASH"] ->
        {:quoted, pos, [{:id, id_pos, ["gethash_mv"]} | form_args]}

      _ ->
        form
    end
  end

  def compile_multiple_value_bind(args, local_env) do
    case args do
      [vars_node, values_form | body_nodes] ->
        var_names = extract_symbols(vars_node)
        mv_var = {:id, 1, ["__mv_res_#{System.unique_integer([:positive, :monotonic])}"]}
        mv_form = rewrite_mv_form(values_form)

        bindings =
          Enum.with_index(var_names)
          |> Enum.map(fn {v, idx} ->
            v_node = {:id, 1, [Atom.to_string(v)]}

            val_expr =
              {:list, 1,
               [
                 {:id, 1, ["if"]},
                 {:list, 1,
                  [
                    {:id, 1, ["and"]},
                    {:list, 1, [{:id, 1, ["consp"]}, mv_var]},
                    {:list, 1,
                     [
                       {:id, 1, ["eq"]},
                       {:list, 1, [{:id, 1, ["car"]}, mv_var]},
                       {:lit, :_values_}
                     ]}
                  ]},
                 {:list, 1,
                  [
                    {:id, 1, ["nth"]},
                    {:lit, idx},
                    {:list, 1, [{:id, 1, ["cadr"]}, mv_var]}
                  ]},
                 if(idx == 0, do: mv_var, else: {:lit, nil})
               ]}

            {:list, 1, [v_node, val_expr]}
          end)

        ast =
          {:list, 1,
           [
             {:id, 1, ["let*"]},
             {:list, 1, [{:list, 1, [mv_var, mv_form]} | bindings]}
             | body_nodes
           ]}

        compile_expr(ast, local_env)

      _ ->
        {:atom, 1, nil}
    end
  end

  def compile_multiple_value_list(args, local_env) do
    case args do
      [form] ->
        temp = :"V_mv_#{System.unique_integer([:positive])}"
        compiled_form = compile_expr(form, local_env)

        {:case, 1, compiled_form,
         [
           {:clause, 1,
            [{:cons, 1, {:atom, 1, :_values_}, {:cons, 1, {:var, 1, temp}, {:var, 1, :_}}}], [],
            [{:var, 1, temp}]},
           {:clause, 1, [{:var, 1, temp}], [], [{:cons, 1, {:var, 1, temp}, {nil, 1}}]}
         ]}

      _ ->
        {nil, 1}
    end
  end

  def compile_multiple_value_call(args, local_env) do
    case args do
      [fn_node | form_nodes] ->
        compiled_fn = compile_expr(fn_node, local_env)

        list_exprs =
          Enum.map(form_nodes, fn form ->
            {:list, 1, [{:id, 1, ["multiple-value-list"]}, form]}
          end)

        combined_list_ast =
          case list_exprs do
            [] ->
              {:lit, nil}

            [single] ->
              single

            [first | rest] ->
              Enum.reduce(rest, first, fn next_expr, acc ->
                {:list, 1, [{:id, 1, ["append"]}, acc, next_expr]}
              end)
          end

        compiled_combined_list = compile_expr(combined_list_ast, local_env)

        {:call, 1, {:remote, 1, {:atom, 1, ExLisp.Builtins}, {:atom, 1, :apply}},
         [compiled_fn, {:cons, 1, compiled_combined_list, {nil, 1}}]}

      _ ->
        {:atom, 1, nil}
    end
  end

  def compile_multiple_value_setq(args, local_env) do
    case args do
      [vars_node, form] ->
        var_nodes =
          case vars_node do
            {:list, _pos, elems} -> elems
            {:quoted, _pos, elems} -> elems
            elems when is_list(elems) -> elems
            _ -> []
          end

        {sub_bindings, rewritten_vars} = decompose_places(var_nodes)
        mv_var = {:id, 1, ["__mv_setq_#{System.unique_integer([:positive, :monotonic])}"]}
        mv_form = rewrite_mv_form(form)

        setf_exprs =
          Enum.with_index(rewritten_vars)
          |> Enum.map(fn {v_node, idx} ->
            val_expr =
              {:list, 1,
               [
                 {:id, 1, ["if"]},
                 {:list, 1,
                  [
                    {:id, 1, ["and"]},
                    {:list, 1, [{:id, 1, ["consp"]}, mv_var]},
                    {:list, 1,
                     [
                       {:id, 1, ["eq"]},
                       {:list, 1, [{:id, 1, ["car"]}, mv_var]},
                       {:lit, :_values_}
                     ]}
                  ]},
                 {:list, 1,
                  [
                    {:id, 1, ["nth"]},
                    {:lit, idx},
                    {:list, 1, [{:id, 1, ["cadr"]}, mv_var]}
                  ]},
                 if(idx == 0, do: mv_var, else: {:lit, nil})
               ]}

            {:list, 1, [{:id, 1, ["setf"]}, v_node, val_expr]}
          end)

        primary_val_expr =
          {:list, 1,
           [
             {:id, 1, ["if"]},
             {:list, 1,
              [
                {:id, 1, ["and"]},
                {:list, 1, [{:id, 1, ["consp"]}, mv_var]},
                {:list, 1,
                 [{:id, 1, ["eq"]}, {:list, 1, [{:id, 1, ["car"]}, mv_var]}, {:lit, :_values_}]}
              ]},
             {:list, 1, [{:id, 1, ["car"]}, {:list, 1, [{:id, 1, ["cadr"]}, mv_var]}]},
             mv_var
           ]}

        ast =
          {:list, 1,
           [
             {:id, 1, ["let*"]},
             {:list, 1, sub_bindings ++ [{:list, 1, [mv_var, mv_form]}]}
             | setf_exprs ++ [primary_val_expr]
           ]}

        compile_expr(ast, local_env)

      _ ->
        {:atom, 1, nil}
    end
  end

  def compile_multiple_value_prog1(args, local_env) do
    case args do
      [first_form | body_nodes] ->
        mv_var = {:id, 1, ["__mv_prog1_#{System.unique_integer([:positive, :monotonic])}"]}

        ast =
          {:list, 1,
           [
             {:id, 1, ["let*"]},
             {:list, 1, [{:list, 1, [mv_var, first_form]}]}
             | body_nodes ++ [mv_var]
           ]}

        compile_expr(ast, local_env)

      _ ->
        {:atom, 1, nil}
    end
  end

  def compile_nth_value(args, local_env) do
    case args do
      [n_node, form] ->
        ast =
          {:list, 1,
           [
             {:id, 1, ["nth"]},
             n_node,
             {:list, 1, [{:id, 1, ["multiple_value_list"]}, form]}
           ]}

        compile_expr(ast, local_env)

      _ ->
        {:atom, 1, nil}
    end
  end

  def compile_destructuring_bind(args, local_env) do
    case args do
      [pattern, expr_node | body_nodes] ->
        temp_var = {:id, 1, ["__destruct_#{System.unique_integer([:positive, :monotonic])}"]}
        bindings = build_destructuring_bindings(pattern, temp_var)

        ast =
          {:list, 1,
           [
             {:id, 1, ["let*"]},
             {:list, 1, [{:list, 1, [temp_var, expr_node]} | bindings]}
             | body_nodes
           ]}

        compile_expr(ast, local_env)

      _ ->
        {:atom, 1, nil}
    end
  end

  defp build_destructuring_bindings(pattern, src_expr) do
    elems =
      case pattern do
        {:list, _pos, es} -> es
        {:quoted, _pos, es} -> es
        es when is_list(es) -> es
        _ -> nil
      end

    if is_nil(elems) do
      [{:list, 1, [pattern, src_expr]}]
    else
      {bindings, _} = do_build_destruct_list(elems, src_expr)
      bindings
    end
  end

  defp do_build_destruct_list(elems, src_expr) do
    curr_src = {:id, 1, ["__cur_src_#{System.unique_integer([:positive, :monotonic])}"]}
    init_binding = {:list, 1, [curr_src, src_expr]}

    {bindings, _} =
      Enum.reduce(elems, {[], curr_src}, fn elem, {acc, cur} ->
        cond do
          is_list_node?(elem) ->
            sub_val = {:list, 1, [{:id, 1, ["car"]}, cur]}
            sub_bindings = build_destructuring_bindings(elem, sub_val)
            next_cur = {:id, 1, ["__cur_src_#{System.unique_integer([:positive, :monotonic])}"]}
            step_binding = {:list, 1, [next_cur, {:list, 1, [{:id, 1, ["cdr"]}, cur]}]}
            {acc ++ sub_bindings ++ [step_binding], next_cur}

          is_dot_node?(elem) ->
            {acc, cur}

          true ->
            val_binding = {:list, 1, [elem, {:list, 1, [{:id, 1, ["car"]}, cur]}]}
            next_cur = {:id, 1, ["__cur_src_#{System.unique_integer([:positive, :monotonic])}"]}
            step_binding = {:list, 1, [next_cur, {:list, 1, [{:id, 1, ["cdr"]}, cur]}]}
            {acc ++ [val_binding, step_binding], next_cur}
        end
      end)

    {[init_binding | bindings], curr_src}
  end

  defp is_dot_node?(elem) do
    sym_name = extract_symbol_name(elem)
    sym_str = if is_atom(sym_name), do: Atom.to_string(sym_name), else: to_string(sym_name)
    sym_str in [".", ":."]
  end

  defp is_list_node?({:list, _, _}), do: true
  defp is_list_node?({:quoted, _, _}), do: true
  defp is_list_node?(l) when is_list(l), do: true
  defp is_list_node?(_), do: false

  def compile_progv([syms_node, vals_node | body_nodes], local_env) do
    body_fn =
      {:fun, 1,
       {:clauses,
        [
          {:clause, 1, [], [],
           case body_nodes do
             [] -> [{:atom, 1, nil}]
             _ -> Enum.map(body_nodes, &compile_expr(&1, local_env))
           end}
        ]}}

    {:call, 1, {:remote, 1, {:atom, 1, ExLisp.Builtins}, {:atom, 1, :progv_eval}},
     [compile_expr(syms_node, local_env), compile_expr(vals_node, local_env), body_fn]}
  end

  def compile_progv(_, _local_env), do: {:atom, 1, nil}

  def compile_psetq(args, local_env) do
    pairs = Enum.chunk_every(args, 2)

    temps =
      Enum.map(pairs, fn [var_node, val_node] ->
        temp_var = {:id, 1, ["__psetq_#{System.unique_integer([:positive, :monotonic])}"]}
        {var_node, val_node, temp_var}
      end)

    temp_bindings =
      Enum.map(temps, fn {_var_node, val_node, temp_var} ->
        {:list, 1, [temp_var, val_node]}
      end)

    setq_exprs =
      Enum.map(temps, fn {var_node, _val_node, temp_var} ->
        {:list, 1, [{:id, 1, ["setq"]}, var_node, temp_var]}
      end)

    ast =
      {:list, 1,
       [
         {:id, 1, ["let*"]},
         {:list, 1, temp_bindings}
         | setq_exprs ++ [{:lit, nil}]
       ]}

    compile_expr(ast, local_env)
  end

  def compile_psetf(args, local_env) do
    pairs = Enum.chunk_every(args, 2)

    temps =
      Enum.map(pairs, fn [place_node, val_node] ->
        temp_var = {:id, 1, ["__psetf_#{System.unique_integer([:positive, :monotonic])}"]}
        {place_node, val_node, temp_var}
      end)

    temp_bindings =
      Enum.map(temps, fn {_place_node, val_node, temp_var} ->
        {:list, 1, [temp_var, val_node]}
      end)

    setf_exprs =
      Enum.map(temps, fn {place_node, _val_node, temp_var} ->
        {:list, 1, [{:id, 1, ["setf"]}, place_node, temp_var]}
      end)

    ast =
      {:list, 1,
       [
         {:id, 1, ["let*"]},
         {:list, 1, temp_bindings}
         | setf_exprs ++ [{:lit, nil}]
       ]}

    compile_expr(ast, local_env)
  end

  def compile_rotatef(args, local_env) do
    case args do
      [] ->
        {:atom, 1, nil}

      [single] ->
        compile_expr(single, local_env)

      places ->
        temps =
          Enum.map(places, fn p ->
            temp_var = {:id, 1, ["__rot_#{System.unique_integer([:positive, :monotonic])}"]}
            {p, temp_var}
          end)

        temp_bindings =
          Enum.map(temps, fn {p, temp_var} ->
            {:list, 1, [temp_var, p]}
          end)

        # rotate left: p_i receives temp_{i+1}, last p receives temp_1
        temp_vars = Enum.map(temps, &elem(&1, 1))
        rotated_temp_vars = tl(temp_vars) ++ [hd(temp_vars)]

        setf_exprs =
          Enum.zip(places, rotated_temp_vars)
          |> Enum.map(fn {p, t_var} ->
            {:list, 1, [{:id, 1, ["setf"]}, p, t_var]}
          end)

        ast =
          {:list, 1,
           [
             {:id, 1, ["let*"]},
             {:list, 1, temp_bindings}
             | setf_exprs ++ [{:lit, nil}]
           ]}

        compile_expr(ast, local_env)
    end
  end

  def compile_shiftf(args, local_env) do
    case args do
      [] ->
        {:atom, 1, nil}

      [single] ->
        compile_expr(single, local_env)

      [place, newval] ->
        old_temp = {:id, 1, ["__shift_old_#{System.unique_integer([:positive, :monotonic])}"]}

        ast =
          {:list, 1,
           [
             {:id, 1, ["let*"]},
             {:list, 1, [{:list, 1, [old_temp, place]}]},
             {:list, 1, [{:id, 1, ["setf"]}, place, newval]},
             old_temp
           ]}

        compile_expr(ast, local_env)

      all ->
        places = Enum.slice(all, 0..-2//1)
        newval = List.last(all)

        temps =
          Enum.map(places, fn p ->
            temp_var = {:id, 1, ["__shift_#{System.unique_integer([:positive, :monotonic])}"]}
            {p, temp_var}
          end)

        old_first_temp =
          {:id, 1, ["__shift_old1_#{System.unique_integer([:positive, :monotonic])}"]}

        temp_newval = {:id, 1, ["__shift_new_#{System.unique_integer([:positive, :monotonic])}"]}

        temp_bindings =
          [{:list, 1, [old_first_temp, hd(places)]}] ++
            Enum.map(tl(temps), fn {p, temp_var} ->
              {:list, 1, [temp_var, p]}
            end) ++
            [{:list, 1, [temp_newval, newval]}]

        temp_vars = Enum.map(tl(temps), &elem(&1, 1)) ++ [temp_newval]

        setf_exprs =
          Enum.zip(places, temp_vars)
          |> Enum.map(fn {p, t_var} ->
            {:list, 1, [{:id, 1, ["setf"]}, p, t_var]}
          end)

        ast =
          {:list, 1,
           [
             {:id, 1, ["let*"]},
             {:list, 1, temp_bindings}
             | setf_exprs ++ [old_first_temp]
           ]}

        compile_expr(ast, local_env)
    end
  end

  # --- ANSI Common Lisp Stream Macros ---

  def compile_with_input_from_string(args, local_env) do
    case args do
      [{:list, _pos, [stream_var, string_node | options]} | body_nodes] ->
        open_call = {:list, 1, [{:id, 1, ["make-string-input-stream"]}, string_node | options]}
        compile_stream_wrapper(stream_var, open_call, body_nodes, local_env)

      [{:quoted, _pos, [stream_var, string_node | options]} | body_nodes] ->
        open_call = {:list, 1, [{:id, 1, ["make-string-input-stream"]}, string_node | options]}
        compile_stream_wrapper(stream_var, open_call, body_nodes, local_env)

      _ ->
        {:atom, 1, nil}
    end
  end

  def compile_with_output_to_string(args, local_env) do
    case args do
      [{:list, _pos, [stream_var | _options]} | body_nodes] ->
        stream_init = {:list, 1, [{:id, 1, ["make-string-output-stream"]}]}
        res_call = {:list, 1, [{:id, 1, ["get-output-stream-string"]}, stream_var]}
        body_with_res = body_nodes ++ [res_call]
        compile_stream_wrapper(stream_var, stream_init, body_with_res, local_env)

      [{:quoted, _pos, [stream_var | _options]} | body_nodes] ->
        stream_init = {:list, 1, [{:id, 1, ["make-string-output-stream"]}]}
        res_call = {:list, 1, [{:id, 1, ["get-output-stream-string"]}, stream_var]}
        body_with_res = body_nodes ++ [res_call]
        compile_stream_wrapper(stream_var, stream_init, body_with_res, local_env)

      _ ->
        {:atom, 1, nil}
    end
  end

  defp compile_stream_wrapper(stream_var, stream_init, body_nodes, local_env) do
    ast =
      {:list, 1,
       [
         {:id, 1, ["let*"]},
         {:list, 1, [{:list, 1, [stream_var, stream_init]}]},
         {:list, 1,
          [
            {:id, 1, ["unwind-protect"]},
            {:list, 1, [{:id, 1, ["progn"]} | body_nodes]},
            {:list, 1,
             [
               {:id, 1, ["when"]},
               stream_var,
               {:list, 1, [{:id, 1, ["close"]}, stream_var]}
             ]}
          ]}
       ]}

    compile_expr(ast, local_env)
  end

  defp extract_symbols({:list, _pos, elems}), do: Enum.map(elems, &extract_symbol_name/1)
  defp extract_symbols({:quoted, _pos, elems}), do: Enum.map(elems, &extract_symbol_name/1)
  defp extract_symbols(elems) when is_list(elems), do: Enum.map(elems, &extract_symbol_name/1)
  defp extract_symbols(_), do: []
end
