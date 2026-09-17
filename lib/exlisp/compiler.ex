defmodule ExLisp.Compiler do
  @moduledoc """
  Module for compiling Lisp source code into BEAM bytecode (.beam files).
  Compiled modules can be used as standard Elixir / Erlang modules.
  """

  @default_module ExLisp.Global

  @doc """
  Reads a Lisp file, compiles it into a BEAM module, and outputs a `.beam` file.
  """
  def compile_file(path, opts \\ []) do
    content = File.read!(path)
    module_name = Keyword.get(opts, :module, @default_module)
    output_dir = Keyword.get(opts, :output_dir, ExLisp.default_beam_dir())

    {:ok, mod, binary} =
      compile_string(content, Keyword.merge(opts, module: module_name, write_beam: false))

    File.mkdir_p!(output_dir)
    beam_filename = "#{mod}.beam"
    beam_path = Path.join(output_dir, beam_filename)
    File.write!(beam_path, binary)

    {:ok, mod, beam_path}
  end

  @doc """
  Compiles a Lisp code string into a BEAM module.
  """
  def compile_string(code, opts \\ []) do
    ExLisp.Env.ensure_env()

    module_name = Keyword.get(opts, :module, @default_module)
    output_dir = Keyword.get(opts, :output_dir, nil)
    write_beam = Keyword.get(opts, :write_beam, output_dir != nil)

    asts = ExLisp.LispParser.parse_multiple!(code)

    {vars, funs, top_level_exprs} = analyze_definitions(asts)

    erl_forms = build_forms(module_name, vars, funs, top_level_exprs, asts)

    case :compile.forms(erl_forms, [:binary, :return_errors]) do
      {:ok, ^module_name, binary} ->
        :code.purge(module_name)
        {:module, ^module_name} = :code.load_binary(module_name, ~c"nofile", binary)

        # Top-level execution (run/0)
        try do
          apply(module_name, :run, [])
        rescue
          _ -> :ok
        end

        if write_beam and output_dir do
          File.mkdir_p!(output_dir)
          beam_path = Path.join(output_dir, "#{module_name}.beam")
          File.write!(beam_path, binary)
          {:ok, module_name, beam_path}
        else
          {:ok, module_name, binary}
        end

      {:error, errors, warnings} ->
        raise "BEAM Compilation Failed: #{inspect(errors)} #{inspect(warnings)}"
    end
  end

  defp analyze_definitions(asts) do
    Enum.reduce(asts, {[], [], []}, fn ast, {vars_acc, funs_acc, exprs_acc} ->
      case ast do
        # (defparameter var val) or (defvar var val)
        {:list, _pos, [op_node, var_node | rest]}
        when is_list(rest) ->
          op_name = LispBeam.extract_op_name(op_node)

          case op_name do
            :defparameter ->
              var_name = LispBeam.extract_symbol_name(var_node)
              val_node = Enum.at(rest, 0, {:lit, nil})
              {[{var_name, val_node, :defparameter} | vars_acc], funs_acc, [ast | exprs_acc]}

            :defvar ->
              var_name = LispBeam.extract_symbol_name(var_node)
              val_node = Enum.at(rest, 0, {:lit, nil})
              {[{var_name, val_node, :defvar} | vars_acc], funs_acc, [ast | exprs_acc]}

            :defun ->
              fun_name = LispBeam.extract_symbol_name(var_node)
              params_node = Enum.at(rest, 0, [])
              param_names = LispBeam.extract_param_names(params_node)
              body_nodes = Enum.drop(rest, 1)

              body_nodes =
                case body_nodes do
                  [] -> [{:lit, nil}]
                  _ -> body_nodes
                end

              {vars_acc, [{fun_name, param_names, body_nodes} | funs_acc], [ast | exprs_acc]}

            :defmacro ->
              macro_name = LispBeam.extract_symbol_name(var_node)
              params_node = Enum.at(rest, 0, [])
              body_nodes = Enum.drop(rest, 1)

              try do
                lambda_ast = ExLisp.Macro.build_macro_lambda(params_node, body_nodes)
                macro_fun = LispBeam.evaluate_ast(lambda_ast)
                ExLisp.Env.put_macro(macro_name, macro_fun)
              rescue
                _ -> :ok
              end

              {vars_acc, funs_acc, [ast | exprs_acc]}

            _ ->
              {vars_acc, funs_acc, [ast | exprs_acc]}
          end

        _ ->
          {vars_acc, funs_acc, [ast | exprs_acc]}
      end
    end)
    |> then(fn {v, f, e} -> {Enum.reverse(v), Enum.reverse(f), Enum.reverse(e)} end)
  end

  defp build_forms(module_name, vars, funs, _top_level_exprs, all_asts) do
    # List of functions to export
    fun_exports = Enum.map(funs, fn {name, params, _} -> {name, length(params)} end)

    exports =
      fun_exports ++
        [
          get_var: 1,
          has_var: 1,
          __vars__: 0,
          __funs__: 0,
          run: 0
        ]

    # Function forms
    fun_forms =
      Enum.map(funs, fn {name, param_names, body_nodes} ->
        local_env = MapSet.new(param_names)
        compiled_body = Enum.map(body_nodes, &LispBeam.compile_expr(&1, local_env))
        erl_params = Enum.map(param_names, fn p -> {:var, 1, LispBeam.erl_var_name(p)} end)

        {:function, 1, name, length(param_names),
         [
           {:clause, 1, erl_params, [], compiled_body}
         ]}
      end)

    # get_var/1 forms
    get_var_clauses =
      Enum.map(vars, fn {var_name, val_node, _type} ->
        {:clause, 1, [{:atom, 1, var_name}], [], [LispBeam.compile_expr(val_node, MapSet.new())]}
      end) ++
        [
          {:clause, 1, [{:var, 1, :_}], [], [{:atom, 1, :undefined}]}
        ]

    get_var_form = {:function, 1, :get_var, 1, get_var_clauses}

    # has_var/1 forms
    has_var_clauses =
      Enum.map(vars, fn {var_name, _val, _type} ->
        {:clause, 1, [{:atom, 1, var_name}], [], [{:atom, 1, true}]}
      end) ++
        [
          {:clause, 1, [{:var, 1, :_}], [], [{:atom, 1, false}]}
        ]

    has_var_form = {:function, 1, :has_var, 1, has_var_clauses}

    # __vars__/0 forms
    vars_cons =
      Enum.reduce(
        Enum.reverse(vars),
        {nil, 1},
        fn {var_name, val_node, _type}, acc ->
          {:cons, 1,
           {:tuple, 1, [{:atom, 1, var_name}, LispBeam.compile_expr(val_node, MapSet.new())]},
           acc}
        end
      )

    vars_form = {:function, 1, :__vars__, 0, [{:clause, 1, [], [], [vars_cons]}]}

    # __funs__/0 forms
    funs_cons =
      Enum.reduce(
        Enum.reverse(funs),
        {nil, 1},
        fn {fun_name, params, _}, acc ->
          {:cons, 1, {:tuple, 1, [{:atom, 1, fun_name}, {:integer, 1, length(params)}]}, acc}
        end
      )

    funs_form = {:function, 1, :__funs__, 0, [{:clause, 1, [], [], [funs_cons]}]}

    # run/0 forms (execute all expressions in order)
    run_body =
      case all_asts do
        [] -> [{:atom, 1, :ok}]
        _ -> Enum.map(all_asts, &LispBeam.compile_expr(&1, MapSet.new()))
      end

    run_form = {:function, 1, :run, 0, [{:clause, 1, [], [], run_body}]}

    # Full forms
    [
      {:attribute, 1, :module, module_name},
      {:attribute, 1, :export, exports}
    ] ++ fun_forms ++ [get_var_form, has_var_form, vars_form, funs_form, run_form]
  end
end
