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
    {:floating_point_inexact, [:arithmetic_error]},
    {:floating_point_invalid_operation, [:arithmetic_error]},
    {:floating_point_overflow, [:arithmetic_error]},
    {:floating_point_underflow, [:arithmetic_error]},
    {:control_error, [:error]},
    {:program_error, [:error]},
    {:parse_error, [:error]},
    {:package_error, [:error]},
    {:stream_error, [:error]},
    {:end_of_file, [:stream_error]},
    {:reader_error, [:parse_error, :stream_error]},
    {:file_error, [:error]},
    {:print_not_readable, [:error]},
    {:simple_type_error, [:simple_condition, :type_error]},
    {:storage_condition, [:serious_condition]},
    {:warning, [:condition]},
    {:style_warning, [:warning]},
    {:unbound_slot, [:cell_error]},
    {:simple_warning, [:warning, :simple_condition]}
  ]

  def init_condition_hierarchy do
    Enum.each(@condition_classes, fn {name, supers} ->
      extra_slots =
        case name do
          n when n in [:cell_error, :unbound_variable, :undefined_function, :unbound_slot] ->
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
        parent_types == [] or parent_types == nil ->
          [:condition]

        is_list(parent_types) ->
          case Enum.reject(parent_types, &is_nil/1) do
            [] -> [:condition]
            normalized -> normalized
          end

        true ->
          [parent_types]
      end

    report_opt =
      Enum.find_value(options, fn
        [key, rep] when is_atom(key) ->
          if normalize_option_key(key) == "report", do: rep

        {:report, rep} ->
          rep

        [":report", rep] ->
          rep

        _ ->
          nil
      end)

    extra_slots =
      if report_opt != nil do
        report_form =
          cond do
            is_atom(report_opt) ->
              fn instance, stream ->
                ExLisp.Builtins.invoke_fn(report_opt, [instance, stream])
              end

            true ->
              report_opt
          end

        [[:report_fun, :initarg, :report_fun, :initform, report_form]]
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

      is_map(type_or_obj) and is_atom(type_or_obj[:name]) ->
        make_condition(type_or_obj[:name], initargs)

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

  def is_condition?({:instance, _class_name, _tid} = instance) do
    ExLisp.CLOS.subclassp(ExLisp.CLOS.class_of(instance), :condition) == :t
  end

  def is_condition?(_), do: false

  # --- Handlers Stack Management ---

  def push_handlers(handlers, fun) when is_list(handlers) and is_function(fun, 0) do
    group = make_ref()

    norm_handlers =
      Enum.map(handlers, fn
        %{type: t, fun: f} -> %{type: normalize_name(t), fun: f, group: group}
        {t, f} -> %{type: normalize_name(t), fun: f, group: group}
        [t, f] -> %{type: normalize_name(t), fun: f, group: group}
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
          %{r | name: normalize_restart_name(n)}

        {n, f} ->
          %{name: normalize_restart_name(n), fun: f, report: nil, test: nil}

        [n, f] ->
          %{name: normalize_restart_name(n), fun: f, report: nil, test: nil}
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
    associate_restart_case_condition(cond_obj)
    handlers = get_handlers()

    search_and_invoke_handler(handlers, cond_obj, [])
    nil
  end

  @doc """
  Issues a warning. Signals condition, prints to stderr if unhandled, and offers muffle-warning.
  """
  def warn(datum, args \\ []) do
    cond_obj = coerce_to_condition(datum, args, :simple_warning)

    if datum == [] do
      ExLisp.Condition.error(:program_error, "WARN requires a datum")
    end

    unless ExLisp.Type.typep(cond_obj, :warning) |> ExLisp.Builtins.truthy?() do
      ExLisp.Condition.error(:type_error, datum: datum, expected_type: :warning)
    end

    if is_condition?(datum) and args != [] do
      ExLisp.Condition.error(:type_error, datum: args, expected_type: nil)
    end

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
        output = "WARNING: #{msg}\n"

        stream =
          try do
            ExLisp.Env.get_var(:"*error-output*")
          rescue
            _ -> :standard_io
          end

        case stream do
          :standard_io -> IO.write(:stderr, output)
          destination -> ExLisp.Stream.write_string(output, destination)
        end

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
  Invokes the dynamic `*debugger-hook*` when one is installed.  Since ExLisp
  has no interactive debugger, an unhandled invocation prints the condition
  and raises the corresponding serious condition.
  """
  def invoke_debugger(condition) do
    object = coerce_to_condition(condition, [], :simple_error)
    old_hook = debugger_hook()

    case old_hook do
      nil ->
        :ok

      hook ->
        previous_debugger_state = Process.get(:exlisp_debugger_hook_active, :inactive)
        Process.put(:exlisp_debugger_hook_active, true)

        try do
          ExLisp.Env.with_special_bindings([{:"*debugger-hook*", nil}], fn ->
            try do
              ExLisp.Builtins.invoke_fn(hook, [object, old_hook])
            rescue
              e ->
                error(:program_error, Exception.message(e))
            end
          end)
        after
          if previous_debugger_state == :inactive do
            Process.delete(:exlisp_debugger_hook_active)
          else
            Process.put(:exlisp_debugger_hook_active, previous_debugger_state)
          end

          Process.put(:exlisp_previous_debugger_hook, old_hook)
        end
    end

    raise RuntimeError, message: format_condition(object)
  end

  defp debugger_hook do
    key = {:"$special$", ExLisp.Env.normalize_name(:"*debugger-hook*")}

    case :erlang.get(key) do
      :undefined ->
        if ExLisp.Env.has_var?(:"*debugger-hook*") do
          ExLisp.Env.get_var(:"*debugger-hook*")
        end

      hook ->
        hook
    end
  rescue
    _ -> nil
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
      Process.put(
        :exlisp_condition_handlers,
        Enum.reverse(skipped) ++ Enum.reject(rest, &(&1[:group] == handler[:group]))
      )

      try do
        ExLisp.Builtins.invoke_fn(fun, [cond_obj])
      after
        Process.put(:exlisp_condition_handlers, Enum.reverse(skipped) ++ [handler | rest])
      end
    end

    search_and_invoke_handler(rest, cond_obj, [handler | skipped])
  end

  def condition_matches_type?(cond_obj, expected_type) do
    norm_type =
      case expected_type do
        %{name: name} -> normalize_name(name)
        _ -> normalize_name(expected_type)
      end

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
    init_condition_hierarchy()

    cond do
      is_condition?(datum) ->
        datum

      is_atom(datum) ->
        norm = normalize_name(datum)

        if ExLisp.CLOS.find_class(norm) do
          make_condition(norm, args)
        else
          flat_args = flatten_args(args)

          make_condition(default_type,
            format_control: Atom.to_string(datum),
            format_arguments: flat_args
          )
        end

      is_binary(datum) ->
        flat_args = flatten_args(args)

        make_condition(default_type,
          format_control: datum,
          format_arguments: flat_args
        )

      true ->
        flat_args = flatten_args(args)

        make_condition(default_type,
          format_control: inspect(datum),
          format_arguments: flat_args
        )
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

      %ExLisp.Closure{} = closure ->
        {:ok, str_io} = StringIO.open("")
        ExLisp.Builtins.invoke_fn(closure, [inst, str_io])
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
    ExLisp.CLFormat.format(ctrl, args || [])
  end

  defp format_string(other, _), do: to_string(other)

  # --- Restart Operations ---

  @doc """
  Finds an active restart by name.
  """
  def find_restart(name, condition \\ nil) do
    norm_name = normalize_restart_name(name)
    restarts = get_restarts()

    Enum.find(restarts, fn r ->
      r_name = normalize_restart_name(r.name)

      if r_name == norm_name and restart_applies_to_condition?(r, condition) do
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
        restart_applies_to_condition?(r, condition) and
          if is_function(r[:test], 1), do: r.test.(condition), else: true
      end)
    end
  end

  def with_condition_restarts(condition, restarts, fun) do
    previous = Process.get(:exlisp_restart_associations, [])

    associations =
      Enum.reduce(List.wrap(restarts), previous, fn restart, acc ->
        [{restart, condition} | acc]
      end)

    Process.put(:exlisp_restart_associations, associations)

    try do
      fun.()
    after
      Process.put(:exlisp_restart_associations, previous)
    end
  end

  defp associate_restart_case_condition(condition) do
    case Process.get(:exlisp_restart_case_groups, []) do
      [restarts | _] ->
        existing =
          Process.get(:exlisp_restart_associations, [])
          |> Enum.map(&elem(&1, 0))

        additions =
          Enum.reject(restarts, &(&1 in existing))
          |> Enum.map(&{&1, condition})

        Process.put(
          :exlisp_restart_associations,
          additions ++ Process.get(:exlisp_restart_associations, [])
        )

      [] ->
        :ok
    end
  end

  defp restart_applies_to_condition?(restart, nil) do
    if is_function(restart[:test], 1), do: restart.test.(nil), else: true
  end

  defp restart_applies_to_condition?(restart, condition) do
    associated =
      Process.get(:exlisp_restart_associations, [])
      |> Enum.filter(fn {candidate, _condition} -> candidate == restart end)
      |> Enum.map(&elem(&1, 1))

    associated == [] or condition in associated
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
  def restart_name(%{name: n}) do
    case ExLisp.Package.intern(
           ExLisp.Builtins.symbol_name(n),
           ExLisp.Package.current_package()
         ) do
      [:_values_, [symbol | _]] -> symbol
      _ -> n
    end
  end

  def restart_name(name) when is_atom(name), do: name
  def restart_name(%ExLisp.Symbol{name: n}), do: String.to_atom(String.downcase(n))
  def restart_name(_), do: nil

  def format_restart(%{report: report, name: _name} = restart) do
    cond do
      is_binary(report) ->
        report

      is_function(report) or match?(%ExLisp.Closure{}, report) ->
        {:ok, stream} = StringIO.open("")

        try do
          ExLisp.Builtins.invoke_fn(report, [stream])
          {_input, output} = StringIO.contents(stream)
          output
        after
          StringIO.close(stream)
        end

      true ->
        restart
        |> Map.get(:name)
        |> to_string()
        |> String.upcase()
    end
  end

  def format_restart(other), do: to_string(other)

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

              var_sym =
                try do
                  String.to_atom(var_str)
                rescue
                  _ -> var_str
                end

              make_condition(:unbound_variable,
                name: var_sym,
                format_control: msg,
                format_arguments: []
              )

            String.starts_with?(msg, "Undefined function: ") ->
              fn_str = String.replace_prefix(msg, "Undefined function: ", "")

              fn_sym =
                try do
                  String.to_atom(fn_str)
                rescue
                  _ -> fn_str
                end

              make_condition(:undefined_function,
                name: fn_sym,
                format_control: msg,
                format_arguments: []
              )

            true ->
              make_condition(:simple_error, format_control: msg, format_arguments: [])
          end

        matching = Enum.find(clauses, fn {t, _} -> condition_matches_type?(cond_obj, t) end)

        if matching do
          {_t, handler_fn} = matching
          handler_fn.(cond_obj)
        else
          reraise ex, __STACKTRACE__
        end

      :error, ex ->
        cond_obj = make_condition(:error, format_control: inspect(ex), format_arguments: [])
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

    previous_groups = Process.get(:exlisp_restart_case_groups, [])
    previous_associations = Process.get(:exlisp_restart_associations, [])
    Process.put(:exlisp_restart_case_groups, [restarts | previous_groups])

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
    after
      Process.put(:exlisp_restart_case_groups, previous_groups)
      Process.put(:exlisp_restart_associations, previous_associations)
    end
  end

  # --- Standard Restart Convenience Functions ---

  def abort(condition \\ nil) do
    case find_restart(:abort, condition) do
      nil -> error(:control_error, "No abort restart active")
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
      nil -> error(:control_error, "No muffle-warning restart active")
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

  def normalize_name(name), do: ExLisp.Symbol.normalize_name(name)

  defp normalize_restart_name(name) do
    normalized = normalize_name(name)

    case Atom.to_string(normalized) |> String.split(".", parts: 2) do
      [package, local] ->
        if ExLisp.Package.find_package(package |> String.upcase() |> String.replace("_", "-")) do
          normalize_name(local)
        else
          normalized
        end

      _ ->
        normalized
    end
  end

  defp normalize_option_key(key) do
    key
    |> Atom.to_string()
    |> String.downcase()
    |> String.split(".", parts: 2)
    |> List.last()
    |> String.trim_leading(":")
  end

  # --- Standard Condition Accessors ---

  def type_error_datum(cond_obj), do: get_condition_slot(cond_obj, :datum)
  def type_error_expected_type(cond_obj), do: get_condition_slot(cond_obj, :expected_type)
  def cell_error_name(cond_obj), do: get_condition_slot(cond_obj, :name)
  def unbound_variable_name(cond_obj), do: cell_error_name(cond_obj)
  def undefined_function_name(cond_obj), do: cell_error_name(cond_obj)
  def stream_error_stream(cond_obj), do: get_condition_slot(cond_obj, :stream)
  def file_error_pathname(cond_obj), do: get_condition_slot(cond_obj, :pathname)
  def package_error_package(cond_obj), do: get_condition_slot(cond_obj, :package)
  def arithmetic_error_operation(cond_obj), do: get_condition_slot(cond_obj, :operation)
  def arithmetic_error_operands(cond_obj), do: get_condition_slot(cond_obj, :operands)
  def simple_condition_format_control(cond_obj), do: get_condition_slot(cond_obj, :format_control)

  def simple_condition_format_arguments(cond_obj),
    do: get_condition_slot(cond_obj, :format_arguments)

  def get_slot(cond_obj, slot_name), do: get_condition_slot(cond_obj, slot_name)

  defp get_condition_slot(cond_obj, slot_name) do
    case cond_obj do
      {:instance, _class, _tid} = inst ->
        try do
          ExLisp.CLOS.slot_value(inst, slot_name)
        rescue
          _ -> nil
        end

      _ ->
        nil
    end
  end
end
