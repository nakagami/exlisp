defmodule ExLisp.Condition do
  @moduledoc """
  Common Lisp Condition and Restart system for ExLisp.
  Supports:
  - define-condition, make-condition
  - signal, warn, error, cerror
  - handler-bind, handler-case, ignore-errors
  - restart-bind, restart-case, invoke-restart, find-restart, compute-restarts
  - standard restarts: abort, continue, muffle-warning, store-value, use-value
  """

  @condition_classes [
    {:condition, [:t]},
    {:serious_condition, [:condition]},
    {:error, [:serious_condition]},
    {:simple_condition, [:condition]},
    {:simple_error, [:error, :simple_condition]},
    {:type_error, [:error]},
    {:cell_error, [:error]},
    {:unbound_variable, [:cell_error]},
    {:undefined_function, [:cell_error]},
    {:arithmetic_error, [:error]},
    {:division_by_zero, [:arithmetic_error]},
    {:floating_point_overflow, [:arithmetic_error]},
    {:floating_point_underflow, [:arithmetic_error]},
    {:control_error, [:error]},
    {:program_error, [:error]},
    {:parse_error, [:error]},
    {:package_error, [:error]},
    {:stream_error, [:error]},
    {:file_error, [:error]},
    {:storage_condition, [:serious_condition]},
    {:warning, [:condition]},
    {:style_warning, [:warning]},
    {:simple_warning, [:warning, :simple_condition]}
  ]

  def init_condition_hierarchy do
    Enum.each(@condition_classes, fn {name, supers} ->
      extra_slots =
        case name do
          n when n in [:cell_error, :unbound_variable, :undefined_function] ->
            [[:name, :initarg, :name, :initform, nil]]

          :type_error ->
            [
              [:datum, :initarg, :datum, :initform, nil],
              [:expected_type, :initarg, :expected_type, :initform, nil]
            ]

          :stream_error ->
            [[:stream, :initarg, :stream, :initform, nil]]

          :file_error ->
            [[:pathname, :initarg, :pathname, :initform, nil]]

          :package_error ->
            [[:package, :initarg, :package, :initform, nil]]

          :arithmetic_error ->
            [
              [:operation, :initarg, :operation, :initform, nil],
              [:operands, :initarg, :operands, :initform, []]
            ]

          _ ->
            []
        end

      ExLisp.CLOS.register_class(name, supers, [
        [:format_control, :initarg, :format_control, :initform, ""],
        [:format_arguments, :initarg, :format_arguments, :initform, []],
        [:report_fun, :initarg, :report_fun, :initform, nil]
        | extra_slots
      ])
    end)
  end

  # --- Condition Definition & Creation ---

  @doc """
  Registers a user-defined condition.
  """
  def define_condition(name, parent_types, slots, options \\ []) do
    init_condition_hierarchy()
    parents =
      cond do
        parent_types == [] or parent_types == nil -> [:condition]
        is_list(parent_types) -> parent_types
        true -> [parent_types]
      end

    report_opt =
      Enum.find_value(options, fn
        [:report, rep] -> rep
        {:report, rep} -> rep
        [":report", rep] -> rep
        _ -> nil
      end)

    extra_slots =
      if report_opt != nil do
        [[:report_fun, :initarg, :report_fun, :initform, report_opt]]
      else
        []
      end

    norm_slots =
      Enum.map(slots, fn
        s when is_list(s) -> s
        s when is_atom(s) or is_binary(s) -> [s]
        other -> other
      end)

    ExLisp.CLOS.register_class(name, parents, norm_slots ++ extra_slots, options)
    name
  end

  @doc """
  Creates a condition instance.
  """
  def make_condition(type_or_obj, initargs \\ []) do
    init_condition_hierarchy()

    flat_args = flatten_args(initargs)

    cond do
      is_condition?(type_or_obj) ->
        type_or_obj

      is_atom(type_or_obj) or is_binary(type_or_obj) ->
        norm_type = normalize_name(type_or_obj)

        if is_nil(ExLisp.CLOS.find_class(norm_type)) do
          define_condition(norm_type, [:error], [])
        end

        ExLisp.CLOS.make_instance(norm_type, flat_args)

      true ->
        ExLisp.CLOS.make_instance(:simple_error, flat_args)
    end
  end

  def is_condition?({:instance, class_name, _tid}) do
    ExLisp.CLOS.subclassp(class_name, :condition) == :t
  end
  def is_condition?(_), do: false

  # --- Handlers Stack Management ---

  def push_handlers(handlers, fun) when is_list(handlers) and is_function(fun, 0) do
    norm_handlers =
      Enum.map(handlers, fn
        %{type: t, fun: f} -> %{type: normalize_name(t), fun: f}
        {t, f} -> %{type: normalize_name(t), fun: f}
        [t, f] -> %{type: normalize_name(t), fun: f}
      end)

    prev = Process.get(:exlisp_condition_handlers, [])
    Process.put(:exlisp_condition_handlers, norm_handlers ++ prev)

    try do
      fun.()
    after
      Process.put(:exlisp_condition_handlers, prev)
    end
  end

  def get_handlers do
    Process.get(:exlisp_condition_handlers, [])
  end

  # --- Restarts Stack Management ---

  def push_restarts(restarts, fun) when is_list(restarts) and is_function(fun, 0) do
    norm_restarts =
      Enum.map(restarts, fn
        %{name: n} = r ->
          %{r | name: normalize_name(n)}

        {n, f} ->
          %{name: normalize_name(n), fun: f, report: nil, test: nil}

        [n, f] ->
          %{name: normalize_name(n), fun: f, report: nil, test: nil}
      end)

    prev = Process.get(:exlisp_condition_restarts, [])
    Process.put(:exlisp_condition_restarts, norm_restarts ++ prev)

    try do
      fun.()
    after
      Process.put(:exlisp_condition_restarts, prev)
    end
  end

  def get_restarts do
    Process.get(:exlisp_condition_restarts, [])
  end

  # --- Signaling Functions ---

  @doc """
  Signals a condition. Searches active handlers in order.
  """
  def signal(datum, args \\ []) do
    cond_obj = coerce_to_condition(datum, args, :simple_condition)
    handlers = get_handlers()

    search_and_invoke_handler(handlers, cond_obj, [])
    nil
  end

  @doc """
  Issues a warning. Signals condition, prints to stderr if unhandled, and offers muffle-warning.
  """
  def warn(datum, args \\ []) do
    cond_obj = coerce_to_condition(datum, args, :simple_warning)

    muffle_tag = make_ref()
    muffle_restart = %{
      name: :muffle_warning,
      fun: fn -> throw({:muffle_warning_invoked, muffle_tag}) end,
      report: fn stream -> IO.write(stream, "Skip warning.") end,
      test: fn _ -> true end
    }

    try do
      push_restarts([muffle_restart], fn ->
        signal(cond_obj)

        msg = format_condition(cond_obj)
        IO.puts(:stderr, "WARNING: #{msg}")
        nil
      end)
    catch
      {:muffle_warning_invoked, ^muffle_tag} -> nil
    end
  end

  @doc """
  Signals a fatal error. If unhandled, invokes debugger or raises.
  """
  def error(datum, args \\ []) do
    cond_obj = coerce_to_condition(datum, args, :simple_error)
    signal(cond_obj)

    # If unhandled by user handlers, raise runtime error
    msg = format_condition(cond_obj)
    raise RuntimeError, message: msg
  end

  @doc """
  Signals a continuable error with a continue restart.
  """
  def cerror(continue_control, datum, args \\ []) do
    cond_obj = coerce_to_condition(datum, args, :simple_error)

    cont_tag = make_ref()
    cont_restart = %{
      name: :continue,
      fun: fn -> throw({:continue_invoked, cont_tag}) end,
      report: fn stream ->
        msg =
          cond do
            is_binary(continue_control) -> continue_control
            is_function(continue_control, 0) -> continue_control.()
            true -> to_string(continue_control)
          end
        IO.write(stream, msg)
      end,
      test: fn _ -> true end
    }

    try do
      push_restarts([cont_restart], fn ->
        error(cond_obj)
      end)
    catch
      {:continue_invoked, ^cont_tag} -> nil
    end
  end

  defp search_and_invoke_handler([], _cond_obj, _skipped), do: nil
  defp search_and_invoke_handler([handler | rest], cond_obj, skipped) do
    %{type: type, fun: fun} = handler

    if condition_matches_type?(cond_obj, type) do
      # Temporarily pop current handler while invoking it
      Process.put(:exlisp_condition_handlers, Enum.reverse(skipped) ++ rest)
      try do
        fun.(cond_obj)
      after
        Process.put(:exlisp_condition_handlers, Enum.reverse(skipped) ++ [handler | rest])
      end
    end

    search_and_invoke_handler(rest, cond_obj, [handler | skipped])
  end

  def condition_matches_type?(cond_obj, expected_type) do
    norm_type = normalize_name(expected_type)

    if norm_type in [:t, :condition, :_] do
      true
    else
      class = ExLisp.CLOS.class_of(cond_obj)

      if class == norm_type do
        true
      else
        cpl = ExLisp.CLOS.get_cpl(class)
        norm_type in cpl
      end
    end
  end

  def coerce_to_condition(datum, args, default_type) do
    cond do
      is_condition?(datum) ->
        datum

      is_atom(datum) ->
        norm = normalize_name(datum)

        if ExLisp.CLOS.find_class(norm) do
          make_condition(norm, args)
        else
          flat_args = flatten_args(args)
          make_condition(default_type, [
            format_control: Atom.to_string(datum),
            format_arguments: flat_args
          ])
        end

      is_binary(datum) ->
        flat_args = flatten_args(args)
        make_condition(default_type, [
          format_control: datum,
          format_arguments: flat_args
        ])

      true ->
        flat_args = flatten_args(args)
        make_condition(default_type, [
          format_control: inspect(datum),
          format_arguments: flat_args
        ])
    end
  end

  defp flatten_args([a | b]) when is_list(b), do: [a | flatten_args(b)]
  defp flatten_args(other) when is_list(other), do: other
  defp flatten_args(other), do: [other]

  def format_condition({:instance, _class, _tid} = inst) do
    case ExLisp.CLOS.slot_value(inst, :report_fun) do
      fun when is_function(fun, 1) ->
        fun.(inst)

      fun when is_function(fun, 2) ->
        {:ok, str_io} = StringIO.open("")
        fun.(inst, str_io)
        {_in, out} = StringIO.contents(str_io)
        out

      str when is_binary(str) ->
        str

      _ ->
        ctrl = ExLisp.CLOS.slot_value(inst, :format_control) || ""
        args = ExLisp.CLOS.slot_value(inst, :format_arguments) || []
        format_string(ctrl, args)
    end
  end
  def format_condition(other), do: inspect(other)

  defp format_string(ctrl, args) when is_binary(ctrl) do
    if args == [] or args == nil do
      ctrl
    else
      flat_args = if is_list(args), do: args, else: [args]
      Enum.reduce(flat_args, ctrl, fn arg, acc ->
        arg_str = ExLisp.to_repl_display(arg) |> inspect()
        if String.contains?(acc, "~a") or String.contains?(acc, "~A") do
          Regex.replace(~r/~[aA]/, acc, to_string(arg), global: false)
        else
          Regex.replace(~r/~[sS]/, acc, arg_str, global: false)
        end
      end)
    end
  end
  defp format_string(other, _), do: to_string(other)

  # --- Restart Operations ---

  @doc """
  Finds an active restart by name.
  """
  def find_restart(name, condition \\ nil) do
    norm_name = normalize_name(name)
    restarts = get_restarts()

    Enum.find(restarts, fn r ->
      r_name = normalize_name(r.name)

      if r_name == norm_name do
        if is_function(r[:test], 1) and condition != nil do
          r.test.(condition)
        else
          true
        end
      else
        false
      end
    end)
  end

  @doc """
  Returns a list of all active restarts.
  """
  def compute_restarts(condition \\ nil) do
    restarts = get_restarts()

    if condition == nil do
      restarts
    else
      Enum.filter(restarts, fn r ->
        if is_function(r[:test], 1), do: r.test.(condition), else: true
      end)
    end
  end

  @doc """
  Invokes a restart by name or restart object with optional arguments.
  """
  def invoke_restart(restart_or_name, args \\ []) do
    restart =
      case restart_or_name do
        %{fun: _} = r -> r
        name -> find_restart(name)
      end

    if restart == nil do
      raise RuntimeError, "Restart #{inspect(restart_or_name)} not found"
    end

    fun = restart.fun
    arg_list = if is_list(args), do: args, else: [args]

    cond do
      is_function(fun, length(arg_list)) ->
        apply(fun, arg_list)

      is_function(fun, 1) and length(arg_list) != 1 ->
        fun.(arg_list)

      is_function(fun, 0) and arg_list == [] ->
        fun.()

      true ->
        apply(fun, arg_list)
    end
  end

  @doc """
  Returns the name of a restart object.
  """
  def restart_name(%{name: n}), do: n
  def restart_name(name) when is_atom(name), do: name
  def restart_name(%ExLisp.Symbol{name: n}), do: String.to_atom(String.downcase(n))
  def restart_name(_), do: nil

  # --- High-level handler-case and restart-case runners ---

  @doc """
  Executes body_fun with handlers registered.
  Clauses: [{type, fn cond -> ... end}]
  no_error_clause: nil or fn result -> ... end
  """
  def run_handler_case(body_fun, clauses, no_error_clause \\ nil) do
    tag = make_ref()

    handlers =
      Enum.map(clauses, fn {type, handler_fn} ->
        %{
          type: type,
          fun: fn c ->
            throw({tag, handler_fn, c})
          end
        }
      end)

    try do
      res =
        push_handlers(handlers, fn ->
          body_fun.()
        end)

      if is_function(no_error_clause, 1) do
        no_error_clause.(res)
      else
        res
      end
    catch
      {^tag, handler_fn, c} ->
        handler_fn.(c)

      :error, %RuntimeError{message: msg} = ex ->
        cond_obj =
          cond do
            String.starts_with?(msg, "Unbound variable: ") ->
              var_str = String.replace_prefix(msg, "Unbound variable: ", "")
              var_sym = try do String.to_atom(var_str) rescue _ -> var_str end
              make_condition(:unbound_variable, [name: var_sym, format_control: msg, format_arguments: []])
            String.starts_with?(msg, "Undefined function: ") ->
              fn_str = String.replace_prefix(msg, "Undefined function: ", "")
              fn_sym = try do String.to_atom(fn_str) rescue _ -> fn_str end
              make_condition(:undefined_function, [name: fn_sym, format_control: msg, format_arguments: []])
            true ->
              make_condition(:simple_error, [format_control: msg, format_arguments: []])
          end

        matching = Enum.find(clauses, fn {t, _} -> condition_matches_type?(cond_obj, t) end)
        if matching do
          {_t, handler_fn} = matching
          handler_fn.(cond_obj)
        else
          reraise ex, __STACKTRACE__
        end

      :error, ex ->
        cond_obj = make_condition(:error, [format_control: inspect(ex), format_arguments: []])
        matching = Enum.find(clauses, fn {t, _} -> condition_matches_type?(cond_obj, t) end)
        if matching do
          {_t, handler_fn} = matching
          handler_fn.(cond_obj)
        else
          reraise ex, __STACKTRACE__
        end
    end
  end

  @doc """
  Executes body_fun with restarts registered.
  Clauses: [%{name: name, fun: (...args -> result), report: report_fun, test: test_fun}]
  """
  def run_restart_case(body_fun, clauses) do
    tag = make_ref()

    restarts =
      Enum.map(clauses, fn c ->
        name = c[:name] || c["name"]
        handler_fn = c[:fun] || c["fun"]
        report_fn = c[:report] || c["report"]
        test_fn = c[:test] || c["test"]
        int_fn = c[:interactive] || c["interactive"]

        %{
          name: name,
          fun: fn
            args when is_list(args) -> throw({tag, handler_fn, args})
            single -> throw({tag, handler_fn, [single]})
          end,
          report: report_fn,
          test: test_fn,
          interactive: int_fn
        }
      end)

    try do
      push_restarts(restarts, fn ->
        body_fun.()
      end)
    catch
      {^tag, handler_fn, args} ->
        arg_list = if is_list(args), do: args, else: [args]
        cond do
          is_function(handler_fn, length(arg_list)) ->
            apply(handler_fn, arg_list)
          is_function(handler_fn, 1) ->
            handler_fn.(arg_list)
          is_function(handler_fn, 0) ->
            handler_fn.()
          true ->
            apply(handler_fn, arg_list)
        end
    end
  end

  # --- Standard Restart Convenience Functions ---

  def abort(condition \\ nil) do
    case find_restart(:abort, condition) do
      nil -> raise RuntimeError, "No abort restart active"
      r -> invoke_restart(r, [])
    end
  end

  def continue(condition \\ nil) do
    case find_restart(:continue, condition) do
      nil -> nil
      r -> invoke_restart(r, [])
    end
  end

  def muffle_warning(condition \\ nil) do
    case find_restart(:muffle_warning, condition) do
      nil -> raise RuntimeError, "No muffle-warning restart active"
      r -> invoke_restart(r, [])
    end
  end

  def store_value(val, condition \\ nil) do
    case find_restart(:store_value, condition) do
      nil -> nil
      r -> invoke_restart(r, [val])
    end
  end

  def use_value(val, condition \\ nil) do
    case find_restart(:use_value, condition) do
      nil -> nil
      r -> invoke_restart(r, [val])
    end
  end

  def normalize_name(name) when is_atom(name) do
    name |> Atom.to_string() |> String.downcase() |> String.replace("-", "_") |> String.to_atom()
  end
  def normalize_name(name) when is_binary(name) do
    name |> String.downcase() |> String.replace("-", "_") |> String.to_atom()
  end
  def normalize_name(%ExLisp.Symbol{name: name}), do: normalize_name(name)
  def normalize_name(other), do: other
end
