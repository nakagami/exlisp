defmodule ExLisp.Runtime do
  @moduledoc false

  def unwrap_mv_primary([:_values_, [first | _]]), do: first
  def unwrap_mv_primary([:_values_, []]), do: nil
  def unwrap_mv_primary([:_values_ | _]), do: nil
  def unwrap_mv_primary(other), do: other

  def normalize_raw_args(nil), do: []
  def normalize_raw_args([]), do: []
  def normalize_raw_args([head | tail]), do: [head | normalize_raw_args(tail)]
  def normalize_raw_args(_other), do: []

  def invoke_fn(fn_val, [arg]) when is_function(fn_val, 1) do
    fn_val.(unwrap_mv_primary(arg))
  end

  def invoke_fn(fn_val, [a, b]) when is_function(fn_val, 2) do
    fn_val.(unwrap_mv_primary(a), unwrap_mv_primary(b))
  end

  def invoke_fn(fn_val, [a, b, c]) when is_function(fn_val, 3) do
    fn_val.(unwrap_mv_primary(a), unwrap_mv_primary(b), unwrap_mv_primary(c))
  end

  def invoke_fn(%ExLisp.Closure{fun: fun, package: package}, args) do
    norm_args = args |> normalize_raw_args() |> Enum.map(&unwrap_mv_primary/1)

    if package do
      previous = ExLisp.Package.current_package()

      try do
        ExLisp.Package.set_current_package(package)
        fun.(norm_args)
      after
        if ExLisp.Package.find_package(previous) do
          ExLisp.Package.set_current_package(previous)
        else
          ExLisp.Package.set_current_package(package)
        end
      end
    else
      fun.(norm_args)
    end
  end

  def invoke_fn(fn_val, args) when is_function(fn_val) do
    norm_args = args |> normalize_raw_args() |> Enum.map(&unwrap_mv_primary/1)

    if is_function(fn_val, length(norm_args)) do
      Kernel.apply(fn_val, norm_args)
    else
      raise RuntimeError,
            "Invalid arity for function #{inspect(fn_val)} with #{length(norm_args)} arguments"
    end
  end

  def invoke_fn(sym, args) when is_atom(sym) and sym not in [nil, nil] do
    down_sym = sym |> Atom.to_string() |> String.downcase() |> String.to_atom()
    norm_args = normalize_raw_args(args)

    case BuiltinFunction.canonical_name(down_sym) do
      {:ok, canonical} ->
        ExLisp.Builtins.dispatch_builtin(canonical, norm_args)

      :error ->
        mapped_args = Enum.map(norm_args, &unwrap_mv_primary/1)

        cond do
          function_exported?(ExLisp.Builtins, down_sym, length(mapped_args)) ->
            Kernel.apply(ExLisp.Builtins, down_sym, mapped_args)

          ExLisp.Env.has_fun?(down_sym) ->
            ExLisp.Env.call_fun(down_sym, mapped_args)

          macro_callsite = Process.get(:exlisp_macro_callsite_package) ->
            callsite_name =
              macro_callsite
              |> to_string()
              |> String.downcase()
              |> String.replace("_", "-")

            qualified_name = :"#{callsite_name}.#{down_sym}"

            if ExLisp.Env.has_fun?(qualified_name) do
              ExLisp.Env.call_fun(qualified_name, mapped_args)
            else
              raise RuntimeError,
                    "Undefined function: #{inspect(sym)} (package #{ExLisp.Package.current_package()}, macro callsite #{inspect(macro_callsite)})"
            end

          true ->
            raise RuntimeError,
                  "Undefined function: #{inspect(sym)} (package #{ExLisp.Package.current_package()}, macro callsite #{inspect(Process.get(:exlisp_macro_callsite_package))})"
        end
    end
  end

  def invoke_fn(other, _args) do
    raise RuntimeError, "Invalid function: #{inspect(other)}"
  end

  def funcall(fn_val, args) when is_list(args), do: invoke_fn(fn_val, args)
  def funcall(fn_val, a), do: invoke_fn(fn_val, [a])
  def funcall(fn_val, a, b), do: invoke_fn(fn_val, [a, b])
  def funcall(fn_val, a, b, c), do: invoke_fn(fn_val, [a, b, c])

  def apply(fn_val, args) when is_list(args) do
    flat_args =
      case args do
        [] ->
          []

        _ ->
          [last | rev_leading] = Enum.reverse(args)
          leading = Enum.reverse(rev_leading)

          trailing =
            cond do
              last in [nil, []] -> []
              is_list(last) -> last
              true -> [last]
            end

          leading ++ trailing
      end

    invoke_fn(fn_val, flat_args)
  end
end
