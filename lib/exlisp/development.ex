defmodule ExLisp.Development do
  @moduledoc """
  Lightweight development and introspection facilities for Lisp functions.

  Tracing is implemented by wrapping registered functions in the environment;
  stepping evaluates a form while printing it, and disassembly uses the
  retained Lisp AST or BEAM abstract code where it is available.
  """

  @original_tag :exlisp_trace_original
  @traced_tag :exlisp_trace_traced

  def trace(names \\ [])
  def trace([]), do: traced_functions()

  def trace(names) when is_list(names) and is_list(hd(names)) do
    names |> Enum.map(&ExLisp.Env.normalize_name/1) |> trace()
  end

  def trace(names) when is_list(names) do
    if Enum.all?(names, &(is_atom(&1) or is_binary(&1) or match?(%ExLisp.Symbol{}, &1))) do
      Enum.map(names, &trace_one/1)
    else
      trace_one(names)
    end
  end

  def trace(name), do: [trace_one(name)]

  defp trace_one(name) do
    name = ExLisp.Env.normalize_name(name)
    ensure_trace_states()

    if :persistent_term.get({@traced_tag, name}, false) do
      name
    else
      original = ExLisp.Env.get_fun(name)

      wrapper =
        ExLisp.Closure.new(
          fn args ->
            depth = Process.get(:exlisp_trace_depth, 0)
            Process.put(:exlisp_trace_depth, depth + 1)
            indent = String.duplicate("  ", depth)
            IO.puts(:stderr, "#{indent}#{depth}: (#{name} #{format_args(args)})")

            try do
              result = ExLisp.Builtins.invoke_fn(original, args)
              IO.puts(:stderr, "#{indent}#{depth}: returned #{inspect(result)}")
              result
            after
              Process.put(:exlisp_trace_depth, depth)
            end
          end,
          name,
          compiled: false,
          ast: trace_original_ast(original),
          params: trace_original_params(original)
        )

      :persistent_term.put({@original_tag, name}, original)
      :persistent_term.put({@traced_tag, name}, true)
      ExLisp.Env.put_fun(name, wrapper)
      name
    end
  end

  def untrace(names \\ [])

  def untrace([]) do
    traced_functions()
    |> Enum.each(&untrace_one/1)

    :t
  end

  def untrace(names) when is_list(names) and is_list(hd(names)) do
    names |> Enum.map(&ExLisp.Env.normalize_name/1) |> Enum.each(&untrace_one/1)
    :t
  end

  def untrace(names) when is_list(names) do
    if Enum.all?(names, &(is_atom(&1) or is_binary(&1) or match?(%ExLisp.Symbol{}, &1))) do
      Enum.each(names, &untrace_one/1)
      :t
    else
      untrace_one(names)
    end
  end

  def untrace(name) do
    untrace_one(name)
    :t
  end

  defp untrace_one(name) do
    name = ExLisp.Env.normalize_name(name)

    case :persistent_term.get({@original_tag, name}, :not_traced) do
      :not_traced ->
        name

      original ->
        ExLisp.Env.put_fun(name, original)
        erase_trace_key({@original_tag, name})
        erase_trace_key({@traced_tag, name})
        name
    end
  end

  def traced_functions do
    :persistent_term.get()
    |> Enum.flat_map(fn
      {{@traced_tag, name}, true} -> [name]
      _ -> []
    end)
    |> Enum.sort()
  end

  def step(form, args \\ []) do
    IO.puts(:stderr, "STEP: #{inspect(form)}")

    cond do
      match?(%ExLisp.Closure{}, form) or is_function(form) ->
        ExLisp.Builtins.invoke_fn(form, List.wrap(args))

      is_atom(form) ->
        function = ExLisp.Env.get_fun(form)
        ExLisp.Builtins.invoke_fn(function, List.wrap(args))

      true ->
        form
        |> LispBeam.evaluate_ast()
        |> ExLisp.Builtins.unwrap_mv_primary()
    end
  end

  def disassemble(function_or_name) do
    {name, object} =
      cond do
        is_atom(function_or_name) or is_binary(function_or_name) or
            match?(%ExLisp.Symbol{}, function_or_name) ->
          name = ExLisp.Env.normalize_name(function_or_name)
          {name, ExLisp.Env.get_fun(name)}

        true ->
          {function_name(function_or_name), function_or_name}
      end

    representation =
      cond do
        ast = ExLisp.Env.get_fun_ast(name) ->
          inspect(ast, pretty: true, limit: :infinity)

        match?(%ExLisp.Closure{ast: ast} when ast != nil, object) ->
          inspect(object.ast, pretty: true, limit: :infinity)

        info = beam_abstract_info(object) ->
          inspect(info, pretty: true, limit: :infinity)

        true ->
          inspect(object, pretty: true, limit: :infinity)
      end

    IO.puts(:stderr, representation)
    nil
  end

  defp beam_abstract_info(fun) when is_function(fun) do
    case :erlang.fun_info(fun, :module) do
      {:module, module} ->
        with {^module, beam, _file} <- :code.get_object_code(module),
             {:ok, {^module, chunks}} <- :beam_lib.chunks(beam, [:abstract_code]),
             {:raw_abstract_v1, forms} <- chunks[:abstract_code] do
          {:name, fun_name} = :erlang.fun_info(fun, :name)
          {:arity, arity} = :erlang.fun_info(fun, :arity)

          Enum.find(forms, fn
            {:function, _, ^fun_name, ^arity, _} -> true
            _ -> false
          end)
        else
          _ -> nil
        end

      _ ->
        nil
    end
  rescue
    _ -> nil
  end

  defp beam_abstract_info(_), do: nil

  defp function_name(%ExLisp.Closure{name: name}), do: name

  defp function_name(fun) when is_function(fun) do
    case :erlang.fun_info(fun, :name) do
      {:name, name} -> name
      _ -> nil
    end
  end

  defp function_name(_), do: nil

  defp trace_original_ast(%ExLisp.Closure{ast: ast}), do: ast
  defp trace_original_ast(_), do: nil
  defp trace_original_params(%ExLisp.Closure{params: params}), do: params
  defp trace_original_params(_), do: nil

  defp format_args(args) do
    Enum.map_join(args, " ", &inspect/1)
  end

  defp ensure_trace_states, do: :ok

  defp erase_trace_key(key) do
    :persistent_term.erase(key)
  rescue
    _ -> :ok
  end
end
