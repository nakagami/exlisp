defmodule ExLisp.JIT do
  @moduledoc false

  require Logger

  @default_threshold 32
  @counter_tag :exlisp_jit_counter
  @compiled_tag :exlisp_jit_compiled
  @failed_tag :exlisp_jit_failed

  def invoke(name, fun, args) do
    if enabled?() and eligible?(fun) do
      maybe_compile_and_invoke(name, fun, args)
    else
      ExLisp.Builtins.invoke_fn(fun, args)
    end
  end

  def compiled?(name) do
    case :persistent_term.get({@compiled_tag, ExLisp.Env.normalize_name(name)}, nil) do
      {_ast, fun} -> ExLisp.Env.get_fun(name) == fun
      nil -> false
    end
  end

  def with_disabled(fun) when is_function(fun, 0) do
    previous = Process.get(:exlisp_jit_disabled, false)
    Process.put(:exlisp_jit_disabled, true)

    try do
      fun.()
    after
      Process.put(:exlisp_jit_disabled, previous)
    end
  end

  defp maybe_compile_and_invoke(name, fun, args) do
    normalized = ExLisp.Env.normalize_name(name)
    ast = ExLisp.Env.get_fun_ast_for(normalized, fun)

    cond do
      ast == nil ->
        ExLisp.Builtins.invoke_fn(fun, args)

      not safely_compilable?(ast) ->
        ExLisp.Builtins.invoke_fn(fun, args)

      failed?(normalized, ast, fun) ->
        ExLisp.Builtins.invoke_fn(fun, args)

      compiled_fun = cached_compiled_fun(normalized, ast, fun) ->
        ExLisp.Builtins.invoke_fn(compiled_fun, args)

      true ->
        counter_key = {@counter_tag, normalized, ast, fun}
        count = Process.get(counter_key, 0) + 1
        Process.put(counter_key, count)

        if count >= threshold() do
          compile_and_invoke(normalized, ast, fun, args)
        else
          ExLisp.Builtins.invoke_fn(fun, args)
        end
    end
  end

  defp compile_and_invoke(name, ast, original_fun, args) do
    package = package_for(original_fun)
    previous_package = ExLisp.Package.current_package()

    compile_result =
      try do
        if package, do: ExLisp.Package.set_current_package(package)
        LispBeam.compile_and_eval_asts([ast])
        compiled_fun = ExLisp.Env.get_fun(name)
        :persistent_term.put({@compiled_tag, name}, {ast, compiled_fun})
        {:ok, compiled_fun}
      rescue
        error in [ArgumentError, RuntimeError, CompileError] ->
          :persistent_term.put({@failed_tag, {name, ast, original_fun}}, true)
          Logger.warning("ExLisp JIT disabled for #{name}: #{Exception.message(error)}")
          :error
      after
        if package do
          ExLisp.Package.set_current_package(previous_package)
        end
      end

    case compile_result do
      {:ok, compiled_fun} -> ExLisp.Builtins.invoke_fn(compiled_fun, args)
      :error -> ExLisp.Builtins.invoke_fn(original_fun, args)
    end
  end

  defp cached_compiled_fun(name, ast, current_fun) do
    case :persistent_term.get({@compiled_tag, name}, nil) do
      {^ast, ^current_fun} ->
        current_fun

      nil ->
        nil

      {_old_ast, compiled_fun} ->
        if ExLisp.Env.get_fun(name) == compiled_fun, do: compiled_fun, else: nil
    end
  end

  defp failed?(name, ast, fun) do
    :persistent_term.get({@failed_tag, {name, ast, fun}}, false)
  end

  defp package_for(%ExLisp.Closure{package: package}), do: package
  defp package_for(_), do: nil

  defp safely_compilable?({:list, _, [{:id, _, [op]}, _name, params_node | body_nodes]})
       when op in ["defun", "DEFUN"] do
    param_names = LispBeam.extract_param_names(params_node)
    mutated = LispBeam.mutated_vars(body_nodes)

    Enum.all?(param_names, &(not MapSet.member?(mutated, &1))) and
      (MapSet.size(mutated) == 0 or not contains_closure_form?(body_nodes))
  end

  defp safely_compilable?(_), do: false

  defp contains_closure_form?(ast) when is_list(ast),
    do: Enum.any?(ast, &contains_closure_form?/1)

  defp contains_closure_form?({:list, _, [{:id, _, [op]} | args]}) do
    normalized = op |> String.downcase() |> String.replace("-", "_")
    normalized in ["lambda", "flet", "labels", "macrolet"] or contains_closure_form?(args)
  end

  defp contains_closure_form?(tuple) when is_tuple(tuple) do
    tuple |> Tuple.to_list() |> contains_closure_form?()
  end

  defp contains_closure_form?(_), do: false

  defp eligible?(fun) do
    is_function(fun) or match?(%ExLisp.Closure{compiled: false}, fun)
  end

  defp enabled?, do: not Process.get(:exlisp_jit_disabled, false)

  defp threshold do
    case Process.get(:exlisp_jit_threshold) do
      value when is_integer(value) and value > 0 ->
        value

      nil ->
        case Integer.parse(System.get_env("EXLISP_JIT_THRESHOLD", "")) do
          {value, ""} when value > 0 -> value
          _ -> @default_threshold
        end
    end
  end
end
