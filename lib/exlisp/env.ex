defmodule ExLisp.Env do
  @moduledoc """
  Module managing global environments (variables and functions) for ExLisp.
  Uses `:persistent_term` to hold and reference values and functions across sessions with extreme speed.
  """

  @history_table :exlisp_history
  @keywords_table :exlisp_keywords

  @doc """
  Prepares the ETS history table and verifies code paths for compiled BEAM modules (initial run only).
  """
  def ensure_env do
    ensure_table(@history_table)
    ensure_table(@keywords_table)

    if not :persistent_term.get(:exlisp_code_paths_initialized, false) do
      ensure_code_paths()
      :persistent_term.put(:exlisp_code_paths_initialized, true)
    end

    :ok
  end

  def register_keyword(atom) when is_atom(atom) do
    ensure_table(@keywords_table)
    :ets.insert(@keywords_table, {atom, true})
    atom
  end

  def keyword?(atom) when is_atom(atom) do
    if atom in [nil, true, false, :t] do
      false
    else
      ensure_table(@keywords_table)

      case :ets.lookup(@keywords_table, atom) do
        [{^atom, true}] -> true
        _ -> false
      end
    end
  end

  def keyword?(_), do: false

  defp ensure_code_paths do
    paths = [
      "ebin",
      "_build/dev/lib/exlisp/ebin",
      "_build/test/lib/exlisp/ebin",
      "_build/prod/lib/exlisp/ebin"
    ]

    for p <- paths, File.dir?(p) do
      char_p = String.to_charlist(Path.expand(p))

      if char_p not in :code.get_path() do
        :code.add_pathz(char_p)
      end
    end

    :ok
  end

  defp ensure_table(table) do
    case :ets.info(table) do
      :undefined ->
        try do
          :ets.new(table, [:set, :public, :named_table, read_concurrency: true])
        rescue
          ArgumentError -> :ok
        end

      _ ->
        :ok
    end
  end

  @doc """
  Initializes and clears the environment (variables, functions, and history).
  """
  def reset do
    ensure_env()

    for {{tag, _} = key, _} <- :persistent_term.get(),
        tag in [:exlisp_var, :exlisp_fun, :exlisp_macro] do
      :persistent_term.erase(key)
    end

    try do
      :ets.delete_all_objects(@history_table)
    rescue
      _ -> :ok
    end

    :ok
  end

  # --- Variable management ---

  @doc """
  Sets a variable and returns the assigned value (for setq / setf).
  """
  def set_var(name, value) do
    ensure_env()
    var_name = normalize_name(name)

    case :erlang.get({:"$special$", var_name}) do
      :undefined ->
        key = {:exlisp_var, var_name}
        :persistent_term.put(key, value)
        value

      _ ->
        :erlang.put({:"$special$", var_name}, value)
        value
    end
  end

  @doc """
  Sets a lexical variable in the process dictionary and returns the assigned value (for setq / setf).
  """
  def set_lexical_var(name, value) do
    :erlang.put(name, value)
    value
  end

  @doc """
  Sets a variable (for defparameter). Always overwrites with the new value.
  Returns the symbol name.
  """
  def put_var(name, value) do
    ensure_env()
    var_name = normalize_name(name)
    key = {:exlisp_var, var_name}
    :persistent_term.put(key, value)
    var_name
  end

  @doc """
  Sets a variable only if unbound (for defvar).
  Takes a value-computing function and evaluates it only when unbound.
  Returns the symbol name.
  """
  def defvar_lazy(name, val_fn) when is_function(val_fn, 0) do
    ensure_env()
    var_name = normalize_name(name)

    if has_var?(var_name) do
      var_name
    else
      val = val_fn.()
      put_var(var_name, val)
      var_name
    end
  end

  @doc """
  Sets a variable only if unbound (for defvar).
  Returns the symbol name.
  """
  def put_var_if_unbound(name, value) do
    ensure_env()
    var_name = normalize_name(name)

    if has_var?(var_name) do
      var_name
    else
      put_var(var_name, value)
      var_name
    end
  end

  @doc """
  Returns the process dictionary value (after setq modification) or default value for a lexical variable.
  """
  def get_lexical_or_default(var_name, default_val) do
    case :erlang.get(var_name) do
      :undefined -> default_val
      val -> val
    end
  end

  @predefined_vars %{
    :features => [:exlisp, :cl, :common_lisp, :ansi_cl, :beam, :erlang, :elixir],
    :"*features*" => [:exlisp, :cl, :common_lisp, :ansi_cl, :beam, :erlang, :elixir],
    :pi => :math.pi(),
    :most_positive_fixnum => 4_611_686_018_427_387_903,
    :"most-positive-fixnum" => 4_611_686_018_427_387_903,
    :most_negative_fixnum => -4_611_686_018_427_387_904,
    :"most-negative-fixnum" => -4_611_686_018_427_387_904,
    :boole_clr => 0,
    :"boole-clr" => 0,
    :boole_set => 1,
    :"boole-set" => 1,
    :boole_1 => 2,
    :"boole-1" => 2,
    :boole_2 => 3,
    :"boole-2" => 3,
    :boole_c1 => 4,
    :"boole-c1" => 4,
    :boole_c2 => 5,
    :"boole-c2" => 5,
    :boole_and => 6,
    :"boole-and" => 6,
    :boole_ior => 7,
    :"boole-ior" => 7,
    :boole_xor => 8,
    :"boole-xor" => 8,
    :boole_eqv => 9,
    :"boole-eqv" => 9,
    :boole_nand => 10,
    :"boole-nand" => 10,
    :boole_nor => 11,
    :"boole-nor" => 11,
    :boole_andc1 => 12,
    :"boole-andc1" => 12,
    :boole_andc2 => 13,
    :"boole-andc2" => 13,
    :boole_orc1 => 14,
    :"boole-orc1" => 14,
    :boole_orc2 => 15,
    :"boole-orc2" => 15,
    :"*random-state*" => :":*random_state*:",
    :random_state => :":*random_state*:",
    :internal_time_units_per_second => 1_000_000,
    :"internal-time-units-per-second" => 1_000_000
  }

  @doc """
  Gets the value of a variable. Raises RuntimeError when unbound.
  """
  def get_var(name) do
    var_name = normalize_name(name)

    case :erlang.get({:"$special$", var_name}) do
      :undefined ->
        case :persistent_term.get({:exlisp_var, var_name}, :__not_found__) do
          :__not_found__ ->
            case Map.fetch(@predefined_vars, var_name) do
              {:ok, val} ->
                val

              :error ->
                if keyword?(var_name) do
                  var_name
                else
                  case lookup_global_module_var(var_name) do
                    {:ok, value} ->
                      value

                    :error ->
                      raise RuntimeError, "Unbound variable: #{var_name}"
                  end
                end
            end

          value ->
            value
        end

      val ->
        val
    end
  end

  @doc """
  Temporarily binds special (dynamically scoped) variables, executes function, and restores previous state upon exit.
  """
  def with_special_bindings(bindings_list, fun)
      when is_list(bindings_list) and is_function(fun, 0) do
    saved = Enum.map(bindings_list, fn {var, _val} -> {var, :erlang.get({:"$special$", var})} end)

    try do
      Enum.each(bindings_list, fn {var, val} -> :erlang.put({:"$special$", var}, val) end)
      fun.()
    after
      Enum.each(saved, fn
        {var, :undefined} -> :erlang.erase({:"$special$", var})
        {var, old_val} -> :erlang.put({:"$special$", var}, old_val)
      end)
    end
  end

  defp lookup_global_module_var(var_name) do
    mod = ExLisp.Global

    if Code.ensure_loaded?(mod) and function_exported?(mod, :has_var, 1) and
         apply(mod, :has_var, [var_name]) do
      {:ok, apply(mod, :get_var, [var_name])}
    else
      :error
    end
  end

  @doc """
  Checks whether a variable is bound.
  """
  def has_var?(name) do
    var_name = normalize_name(name)

    if Map.has_key?(@predefined_vars, var_name) do
      true
    else
      if :persistent_term.get({:exlisp_var, var_name}, :__not_found__) != :__not_found__ do
        true
      else
        mod = ExLisp.Global

        Code.ensure_loaded?(mod) and function_exported?(mod, :has_var, 1) and
          apply(mod, :has_var, [var_name])
      end
    end
  end

  @doc """
  Deletes a variable.
  """
  def delete_var(name) do
    var_name = normalize_name(name)
    key = {:exlisp_var, var_name}

    try do
      :persistent_term.erase(key)
    rescue
      _ -> :ok
    end

    :ok
  end

  # --- Function management ---

  @doc """
  Registers a function (for defun).
  Returns the function name.
  """
  def put_fun(name, fun) when is_function(fun) or is_struct(fun, ExLisp.Closure) do
    ensure_env()
    fun_name = normalize_name(name)
    key = {:exlisp_fun, fun_name}
    :persistent_term.put(key, fun)
    fun_name
  end

  @doc """
  Gets a registered function.
  """
  def get_fun(name) do
    fun_name = normalize_name(name)

    case :persistent_term.get({:exlisp_fun, fun_name}, :__not_found__) do
      :__not_found__ ->
        case lookup_global_module_fun(fun_name) do
          {:ok, fun} ->
            fun

          :error ->
            case BuiltinFunction.lookup(fun_name) do
              {:ok, canonical} ->
                ExLisp.Closure.new(
                  fn args -> ExLisp.Builtins.dispatch_builtin(canonical, args) end,
                  canonical
                )

              :error ->
                raise RuntimeError, "Undefined function: #{fun_name}"
            end
        end

      fun ->
        fun
    end
  end

  defp lookup_global_module_fun(fun_name) do
    mod = ExLisp.Global

    if Code.ensure_loaded?(mod) and function_exported?(mod, :__funs__, 0) do
      funs = apply(mod, :__funs__, [])

      case Enum.find(funs, fn {name, _arity} -> name == fun_name end) do
        {^fun_name, arity} ->
          {:ok, Function.capture(mod, fun_name, arity)}

        nil ->
          :error
      end
    else
      :error
    end
  end

  @doc """
  Checks whether a function is defined.
  """
  def has_fun?(name) do
    fun_name = normalize_name(name)

    if :persistent_term.get({:exlisp_fun, fun_name}, :__not_found__) != :__not_found__ do
      true
    else
      case lookup_global_module_fun(fun_name) do
        {:ok, _} -> true
        :error -> BuiltinFunction.builtin?(fun_name)
      end
    end
  end

  @doc """
  Executes a registered function.
  """
  def call_fun(name, args) when is_list(args) do
    fun_name = normalize_name(name)
    fun = get_fun(fun_name)

    case fun do
      %ExLisp.Closure{fun: f} ->
        f.(args)

      _ ->
        if is_function(fun, length(args)) do
          apply(fun, args)
        else
          fun.(args)
        end
    end
  end

  @doc """
  Registers a method for a generic function. Dispatches according to argument type list.
  """
  def register_method(name, types, fun)
      when is_atom(name) and is_list(types) and is_function(fun) do
    ensure_env()
    fun_name = normalize_name(name)
    key = {:exlisp_generic_methods, fun_name}

    current_methods =
      case :ets.lookup(@history_table, key) do
        [{^key, methods}] -> methods
        _ -> []
      end

    updated_methods =
      [{types, fun} | Enum.reject(current_methods, fn {t, _} -> t == types end)]
      |> Enum.sort_by(fn {t_list, _} ->
        Enum.count(t_list, fn t -> t == :t or t == :_ end)
      end)

    :ets.insert(@history_table, {key, updated_methods})

    dispatcher = fn args ->
      case find_matching_method(updated_methods, args) do
        {:ok, method_fun} ->
          if is_function(method_fun, length(args)) do
            apply(method_fun, args)
          else
            method_fun.(args)
          end

        :error ->
          raise RuntimeError,
                "No applicable method for #{inspect(fun_name)} with arguments #{inspect(args)}"
      end
    end

    closure = %ExLisp.Closure{
      fun: dispatcher,
      name: fun_name,
      variadic: true
    }

    put_fun(fun_name, closure)
    fun_name
  end

  defp find_matching_method(methods, args) do
    Enum.find_value(methods, :error, fn {types, fun} ->
      if method_matches?(types, args) do
        {:ok, fun}
      else
        nil
      end
    end)
  end

  defp method_matches?(types, args) do
    if length(types) == length(args) do
      Enum.zip(types, args)
      |> Enum.all?(fn {type, arg} -> type_matches?(type, arg) end)
    else
      false
    end
  end

  defp type_matches?(:t, _arg), do: true
  defp type_matches?(:_, _arg), do: true
  defp type_matches?(t, arg) when t in [:integer, :fixnum, :bignum], do: is_integer(arg)
  defp type_matches?(:float, arg), do: is_float(arg)
  defp type_matches?(:number, arg), do: is_number(arg) or is_struct(arg, ExLisp.Ratio)
  defp type_matches?(t, arg) when t in [:list, :cons], do: is_list(arg)
  defp type_matches?(t, arg) when t in [:atom, :symbol], do: is_atom(arg) and not is_nil(arg)
  defp type_matches?(:string, arg), do: is_binary(arg)
  defp type_matches?(_other, _arg), do: true

  @doc """
  Deletes a function (for fmakunbound).
  """
  def delete_fun(name) do
    fun_name = normalize_name(name)
    key = {:exlisp_fun, fun_name}

    try do
      :persistent_term.erase(key)
    rescue
      _ -> :ok
    end

    :ok
  end

  # --- Macro management ---

  @doc """
  Registers a macro function (for defmacro).
  Returns the macro name.
  """
  def put_macro(name, macro_fun) when is_function(macro_fun) do
    ensure_env()
    macro_name = normalize_name(name)
    key = {:exlisp_macro, macro_name}
    :persistent_term.put(key, macro_fun)
    macro_name
  end

  @doc """
  Gets a registered macro function.
  """
  def get_macro(name) do
    macro_name = normalize_name(name)

    case :persistent_term.get({:exlisp_macro, macro_name}, :__not_found__) do
      :__not_found__ ->
        raise RuntimeError, "Undefined macro: #{macro_name}"

      macro_fun ->
        macro_fun
    end
  end

  @doc """
  Checks whether a macro is defined.
  """
  def has_macro?(name) do
    macro_name = normalize_name(name)
    :persistent_term.get({:exlisp_macro, macro_name}, :__not_found__) != :__not_found__
  end

  @doc """
  Deletes a macro.
  """
  def delete_macro(name) do
    macro_name = normalize_name(name)
    key = {:exlisp_macro, macro_name}

    try do
      :persistent_term.erase(key)
    rescue
      _ -> :ok
    end

    :ok
  end

  @doc """
  Normalizes symbol names to lowercase atoms.
  """
  def normalize_name(name) when is_atom(name) do
    case name do
      :_cl_star_star_ -> :*
      :_cl_star_star_star_star_ -> :**
      :_cl_star_star_star_star_star_star_ -> :"***"
      :_cl_plus_plus_ -> :+
      :_cl_plus_plus_plus_plus_ -> :++
      :_cl_plus_plus_plus_plus_plus_plus_ -> :+++
      _ -> Atom.to_string(name) |> String.downcase() |> String.to_atom()
    end
  end

  def normalize_name(name) when is_binary(name) do
    case name do
      "_cl_star_star_" -> :*
      "_cl_star_star_star_star_" -> :**
      "_cl_star_star_star_star_star_star_" -> :"***"
      "_cl_plus_plus_" -> :+
      "_cl_plus_plus_plus_plus_" -> :++
      "_cl_plus_plus_plus_plus_plus_plus_" -> :+++
      _ -> String.downcase(name) |> String.to_atom()
    end
  end

  def normalize_name(%ExLisp.Symbol{id: id, name: name}) do
    if id != nil do
      :"$uninterned_#{id}$"
    else
      normalize_name(name)
    end
  end

  def normalize_name({:id, _pos, parts}) when is_list(parts) do
    parts |> Enum.join(".") |> normalize_name()
  end

  def normalize_name({:list, _pos, [{:id, _, [s]}, inner]}) when s in ["setf", "SETF"] do
    inner_sym = normalize_name(inner)
    :"setf_#{inner_sym}"
  end

  def normalize_name([:setf, inner]) do
    inner_sym = normalize_name(inner)
    :"setf_#{inner_sym}"
  end

  def normalize_name({:lit, val}), do: normalize_name(val)

  def normalize_name(other) do
    other |> to_string() |> normalize_name()
  end

  # --- History management (REPL counter / re-execution) ---

  @doc """
  Records REPL input expression and evaluation result in history table.
  Also updates Common Lisp special variables (*, **, ***, +, ++, +++).
  """
  def record_history(code, result) do
    ensure_env()
    counter = :ets.update_counter(@history_table, :__counter__, {2, 1}, {:__counter__, 0})
    :ets.insert(@history_table, {counter, code, result})

    # Update Common Lisp history variables
    # *** = **, ** = *, * = result
    v_star = get_var_or_nil(:*)
    v_star2 = get_var_or_nil(:**)
    put_var(:"***", v_star2)
    put_var(:**, v_star)
    put_var(:*, result)

    # +++ = ++, ++ = +, + = code
    c_plus = get_var_or_nil(:+)
    c_plus2 = get_var_or_nil(:++)
    put_var(:+++, c_plus2)
    put_var(:++, c_plus)
    put_var(:+, code)

    counter
  end

  defp get_var_or_nil(name) do
    var_name = normalize_name(name)
    :persistent_term.get({:exlisp_var, var_name}, nil)
  end

  @doc """
  Gets history code string for the specified index (or negative relative index).
  """
  def get_history_code(n \\ -1) when is_integer(n) do
    ensure_env()
    target_idx = resolve_history_index(n)

    case :ets.lookup(@history_table, target_idx) do
      [{^target_idx, code, _result}] -> code
      [] -> nil
    end
  end

  @doc """
  Gets evaluation result for the specified index (or negative relative index).
  """
  def get_history_result(n \\ -1) when is_integer(n) do
    ensure_env()
    target_idx = resolve_history_index(n)

    case :ets.lookup(@history_table, target_idx) do
      [{^target_idx, _code, result}] -> result
      [] -> nil
    end
  end

  defp resolve_history_index(n) when n > 0, do: n

  defp resolve_history_index(n) when n <= 0 do
    current =
      case :ets.lookup(@history_table, :__counter__) do
        [{:__counter__, count}] -> count
        [] -> 0
      end

    if n == 0 or n == -1 do
      current
    else
      current + n + 1
    end
  end
end
