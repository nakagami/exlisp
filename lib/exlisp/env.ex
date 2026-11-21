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
    ExLisp.CLOS.ensure_tables()
    ExLisp.Type.ensure_tables()

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
        tag in [
          :exlisp_var,
          :exlisp_fun,
          :exlisp_macro,
          :exlisp_fun_ast,
          :exlisp_symbol_macro,
          :exlisp_compiler_macro,
          :exlisp_trace_original,
          :exlisp_trace_traced
        ] do
      :persistent_term.erase(key)
    end

    try do
      :ets.delete_all_objects(@history_table)
    rescue
      _ -> :ok
    end

    ExLisp.CLOS.reset()

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
    :"*standard-input*" => :standard_io,
    :"*standard_input*" => :standard_io,
    :"*standard-output*" => :standard_io,
    :"*standard_output*" => :standard_io,
    :"*error-output*" => :standard_io,
    :"*error_output*" => :standard_io,
    :"*trace-output*" => :standard_io,
    :"*trace_output*" => :standard_io,
    :"*debug-io*" => :standard_io,
    :"*debug_io*" => :standard_io,
    :"*query-io*" => :standard_io,
    :"*query_io*" => :standard_io,
    :"*terminal-io*" => :standard_io,
    :"*terminal_io*" => :standard_io,
    :features => [
      :exlisp,
      :cl,
      :common_lisp,
      :ansi_cl,
      :beam,
      :erlang,
      :elixir,
      :sbcl,
      :sb_thread,
      :sb_ext,
      :sb_posix,
      :sb_sys,
      :"sb-thread",
      :"sb-ext",
      :"sb-posix",
      :"sb-sys"
    ],
    :"*features*" => [
      :exlisp,
      :cl,
      :common_lisp,
      :ansi_cl,
      :beam,
      :erlang,
      :elixir,
      :sbcl,
      :sb_thread,
      :sb_ext,
      :sb_posix,
      :sb_sys,
      :"sb-thread",
      :"sb-ext",
      :"sb-posix",
      :"sb-sys"
    ],
    :pi => :math.pi(),
    :least_positive_single_float => 4.9e-45,
    :least_positive_short_float => 4.9e-45,
    :least_positive_normalized_single_float => 1.17549435e-38,
    :least_positive_normalized_short_float => 1.17549435e-38,
    :least_positive_double_float => 4.9e-324,
    :least_positive_long_float => 4.9e-324,
    :least_positive_normalized_double_float => 2.2250738585072014e-308,
    :least_positive_normalized_long_float => 2.2250738585072014e-308,
    :least_negative_single_float => -4.9e-45,
    :least_negative_short_float => -4.9e-45,
    :least_negative_normalized_single_float => -1.17549435e-38,
    :least_negative_normalized_short_float => -1.17549435e-38,
    :least_negative_double_float => -4.9e-324,
    :least_negative_long_float => -4.9e-324,
    :least_negative_normalized_double_float => -2.2250738585072014e-308,
    :least_negative_normalized_long_float => -2.2250738585072014e-308,
    :most_positive_single_float => 3.40282347e38,
    :most_positive_short_float => 3.40282347e38,
    :most_positive_double_float => 1.7976931348623157e308,
    :most_positive_long_float => 1.7976931348623157e308,
    :most_negative_single_float => -3.40282347e38,
    :most_negative_short_float => -3.40282347e38,
    :most_negative_double_float => -1.7976931348623157e308,
    :most_negative_long_float => -1.7976931348623157e308,
    :single_float_epsilon => 1.1102230246251568e-16,
    :short_float_epsilon => 1.1102230246251568e-16,
    :single_float_negative_epsilon => 5.551115123125784e-17,
    :short_float_negative_epsilon => 5.551115123125784e-17,
    :double_float_epsilon => 1.1102230246251568e-16,
    :long_float_epsilon => 1.1102230246251568e-16,
    :double_float_negative_epsilon => 5.551115123125784e-17,
    :long_float_negative_epsilon => 5.551115123125784e-17,
    :most_positive_fixnum => 4_611_686_018_427_387_903,
    :"most-positive-fixnum" => 4_611_686_018_427_387_903,
    :most_negative_fixnum => -4_611_686_018_427_387_904,
    :"most-negative-fixnum" => -4_611_686_018_427_387_904,
    :array_rank_limit => 128,
    :"array-rank-limit" => 128,
    :array_dimension_limit => 1_073_741_824,
    :"array-dimension-limit" => 1_073_741_824,
    :array_total_size_limit => 4_611_686_018_427_387_903,
    :"array-total-size-limit" => 4_611_686_018_427_387_903,
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
            cands = symbol_lookup_candidates(var_name)

            posix_argv_names = [
              :"*posix-argv*",
              :posix_argv,
              :"*posix_argv*",
              :"sb-ext:*posix-argv*",
              :"sb_ext:*posix_argv*",
              :"sb-ext:*posix_argv*",
              :"sb-ext.*posix-argv*",
              :"sb_ext.*posix_argv*",
              :"sb-ext.*posix_argv*"
            ]

            cond do
              var_name == :"*readtable*" or var_name == :readtable or
                  Enum.any?(cands, &(&1 == :"*readtable*")) ->
                ExLisp.Readtable.current_readtable()

              var_name in posix_argv_names or Enum.any?(cands, &(&1 in posix_argv_names)) ->
                ["exlisp" | System.argv()]

              Map.has_key?(@predefined_vars, var_name) ->
                Map.fetch!(@predefined_vars, var_name)

              Enum.find_value(cands, fn c -> Map.get(@predefined_vars, c) end) != nil ->
                Enum.find_value(cands, fn c -> Map.get(@predefined_vars, c) end)

              keyword?(var_name) ->
                var_name

              true ->
                case lookup_global_module_var(var_name) do
                  {:ok, value} ->
                    value

                  :error ->
                    raise RuntimeError, "Unbound variable: #{var_name}"
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
    bindings =
      Enum.flat_map(bindings_list, fn {var, value} ->
        normalized = normalize_name(var)
        text = Atom.to_string(normalized)
        aliases = [normalized, text |> String.replace("_", "-") |> String.to_atom()]
        aliases |> Enum.uniq() |> Enum.map(&{&1, value})
      end)

    saved = Enum.map(bindings, fn {var, _val} -> {var, :erlang.get({:"$special$", var})} end)

    try do
      Enum.each(bindings, fn {var, val} -> :erlang.put({:"$special$", var}, val) end)
      fun.()
    after
      Enum.each(saved, fn
        {var, :undefined} -> :erlang.erase({:"$special$", var})
        {var, old_val} -> :erlang.put({:"$special$", var}, old_val)
      end)
    end
  end

  @doc """
  Dynamically binds variables (for progv).
  """
  def progv(symbols, values, fun) when is_function(fun, 0) do
    sym_list =
      case symbols do
        list when is_list(list) ->
          Enum.map(list, fn
            sym when is_atom(sym) -> normalize_name(sym)
            %ExLisp.Symbol{name: name} -> normalize_name(name)
            str when is_binary(str) -> normalize_name(str)
            other -> normalize_name(other)
          end)

        _ ->
          []
      end

    val_list =
      case values do
        list when is_list(list) -> list
        _ -> []
      end

    padded_vals = (val_list ++ Stream.repeatedly(fn -> nil end)) |> Enum.take(length(sym_list))
    bindings = Enum.zip(sym_list, padded_vals)

    with_special_bindings(bindings, fun)
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

    if :persistent_term.get({:exlisp_var, var_name}, :__not_found__) != :__not_found__ do
      true
    else
      cands = symbol_lookup_candidates(var_name)

      posix_argv_names = [
        :"*posix-argv*",
        :posix_argv,
        :"*posix_argv*",
        :"sb-ext:*posix-argv*",
        :"sb_ext:*posix_argv*",
        :"sb-ext:*posix_argv*",
        :"sb-ext.*posix-argv*",
        :"sb_ext.*posix_argv*",
        :"sb-ext.*posix_argv*"
      ]

      cond do
        var_name in posix_argv_names or Enum.any?(cands, &(&1 in posix_argv_names)) ->
          true

        Map.has_key?(@predefined_vars, var_name) or
            Enum.any?(cands, &Map.has_key?(@predefined_vars, &1)) ->
          true

        Enum.any?(cands, fn c ->
          :persistent_term.get({:exlisp_var, c}, :__not_found__) != :__not_found__
        end) ->
          true

        true ->
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

    name_str = Atom.to_string(fun_name)
    h_name = String.replace(name_str, "_", "-") |> String.to_atom()
    u_name = String.replace(name_str, "-", "_") |> String.to_atom()
    :persistent_term.put({:exlisp_fun, h_name}, fun)
    :persistent_term.put({:exlisp_fun, u_name}, fun)

    try do
      curr_pkg = ExLisp.Package.current_package()

      if curr_pkg != nil and not String.contains?(name_str, ".") and
           not String.contains?(name_str, ":") do
        pkg_name = to_string(curr_pkg) |> String.downcase()
        pkg_h = String.replace(pkg_name, "_", "-")
        :persistent_term.put({:exlisp_fun, :"#{pkg_name}.#{fun_name}"}, fun)
        :persistent_term.put({:exlisp_fun, :"#{pkg_name}:#{fun_name}"}, fun)
        :persistent_term.put({:exlisp_fun, :"#{pkg_h}.#{h_name}"}, fun)
        :persistent_term.put({:exlisp_fun, :"#{pkg_h}:#{h_name}"}, fun)
      end
    rescue
      _ -> :ok
    end

    fun_name
  end

  @doc """
  Gets a registered function.
  """
  def get_fun(name) do
    fun_name = normalize_name(name)

    case :persistent_term.get({:exlisp_fun, fun_name}, :__not_found__) do
      :__not_found__ ->
        candidates = symbol_lookup_candidates(fun_name)

        found_fun =
          Enum.find_value(candidates, fn cand ->
            case :persistent_term.get({:exlisp_fun, cand}, :__not_found__) do
              :__not_found__ -> nil
              f -> f
            end
          end)

        case found_fun do
          nil ->
            case Enum.find_value(candidates, fn cand ->
                   case lookup_global_module_fun(cand) do
                     {:ok, f} -> f
                     :error -> nil
                   end
                 end) do
              nil ->
                case Enum.find_value(candidates, fn cand ->
                       case BuiltinFunction.lookup(cand) do
                         {:ok, canonical} ->
                           ExLisp.Closure.new(
                             fn args -> ExLisp.Builtins.dispatch_builtin(canonical, args) end,
                             canonical
                           )

                         :error ->
                           nil
                       end
                     end) do
                  nil -> raise RuntimeError, "Undefined function: #{fun_name}"
                  builtin_closure -> builtin_closure
                end

              mod_fun ->
                mod_fun
            end

          fun ->
            fun
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
  Stores the AST source of a function for compilation or inspection.
  """
  def put_fun_ast(name, ast) do
    ensure_env()
    fun_name = normalize_name(name)
    key = {:exlisp_fun_ast, fun_name}
    :persistent_term.put(key, ast)

    name_str = Atom.to_string(fun_name)
    h_name = String.replace(name_str, "_", "-") |> String.to_atom()
    u_name = String.replace(name_str, "-", "_") |> String.to_atom()
    :persistent_term.put({:exlisp_fun_ast, h_name}, ast)
    :persistent_term.put({:exlisp_fun_ast, u_name}, ast)

    ast
  end

  @doc """
  Retrieves the AST source of a function.
  """
  def get_fun_ast(name) do
    fun_name = normalize_name(name)

    case :persistent_term.get({:exlisp_fun_ast, fun_name}, :__not_found__) do
      :__not_found__ ->
        candidates = symbol_lookup_candidates(fun_name)

        Enum.find_value(candidates, fn cand ->
          case :persistent_term.get({:exlisp_fun_ast, cand}, :__not_found__) do
            :__not_found__ -> nil
            ast -> ast
          end
        end)

      ast ->
        ast
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
      candidates = symbol_lookup_candidates(fun_name)

      Enum.any?(candidates, fn cand ->
        if :persistent_term.get({:exlisp_fun, cand}, :__not_found__) != :__not_found__ do
          true
        else
          case lookup_global_module_fun(cand) do
            {:ok, _} -> true
            :error -> BuiltinFunction.builtin?(cand)
          end
        end
      end)
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
    register_method(name, nil, types, fun)
  end

  def register_method(name, qualifier, types, fun)
      when is_atom(name) and is_list(types) and is_function(fun) do
    ensure_env()
    fun_name = normalize_name(name)
    ExLisp.CLOS.register_method(fun_name, qualifier, types, fun)
    fun_name
  end

  @doc """
  Deletes a function (for fmakunbound).
  """
  def delete_fun(name) do
    fun_name = normalize_name(name)
    candidates = symbol_lookup_candidates(fun_name)

    Enum.each(candidates, fn cand ->
      try do
        :persistent_term.erase({:exlisp_fun, cand})
      rescue
        _ -> :ok
      end
    end)

    try do
      curr_pkg = ExLisp.Package.current_package()

      if curr_pkg != nil do
        name_str = Atom.to_string(fun_name)
        pkg_name = to_string(curr_pkg) |> String.downcase()
        pkg_h = String.replace(pkg_name, "_", "-")
        h_name = String.replace(name_str, "_", "-")
        :persistent_term.erase({:exlisp_fun, :"#{pkg_name}.#{fun_name}"})
        :persistent_term.erase({:exlisp_fun, :"#{pkg_name}:#{fun_name}"})
        :persistent_term.erase({:exlisp_fun, :"#{pkg_h}.#{h_name}"})
        :persistent_term.erase({:exlisp_fun, :"#{pkg_h}:#{h_name}"})
      end
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
  def put_macro(name, macro_fun)
      when is_function(macro_fun) or is_struct(macro_fun, ExLisp.Closure) do
    ensure_env()
    macro_name = normalize_name(name)
    key = {:exlisp_macro, macro_name}
    :persistent_term.put(key, macro_fun)

    name_str = Atom.to_string(macro_name)
    h_name = String.replace(name_str, "_", "-") |> String.to_atom()
    u_name = String.replace(name_str, "-", "_") |> String.to_atom()
    :persistent_term.put({:exlisp_macro, h_name}, macro_fun)
    :persistent_term.put({:exlisp_macro, u_name}, macro_fun)

    try do
      curr_pkg = ExLisp.Package.current_package()

      if curr_pkg != nil and not String.contains?(name_str, ".") and
           not String.contains?(name_str, ":") do
        pkg_name = to_string(curr_pkg) |> String.downcase()
        pkg_h = String.replace(pkg_name, "_", "-")
        :persistent_term.put({:exlisp_macro, :"#{pkg_name}.#{macro_name}"}, macro_fun)
        :persistent_term.put({:exlisp_macro, :"#{pkg_name}:#{macro_name}"}, macro_fun)
        :persistent_term.put({:exlisp_macro, :"#{pkg_h}.#{h_name}"}, macro_fun)
        :persistent_term.put({:exlisp_macro, :"#{pkg_h}:#{h_name}"}, macro_fun)
      end
    rescue
      _ -> :ok
    end

    macro_name
  end

  @doc """
  Gets a registered macro function.
  """
  def get_macro(name) do
    macro_name = normalize_name(name)

    case :persistent_term.get({:exlisp_macro, macro_name}, :__not_found__) do
      :__not_found__ ->
        candidates = symbol_lookup_candidates(macro_name)

        found_macro =
          Enum.find_value(candidates, fn cand ->
            case :persistent_term.get({:exlisp_macro, cand}, :__not_found__) do
              :__not_found__ -> nil
              m -> m
            end
          end)

        case found_macro do
          nil ->
            raise RuntimeError, "Undefined macro: #{macro_name}"

          macro_fun ->
            macro_fun
        end

      macro_fun ->
        macro_fun
    end
  end

  @doc """
  Checks whether a macro is defined.
  """
  def has_macro?(name) do
    macro_name = normalize_name(name)

    if :persistent_term.get({:exlisp_macro, macro_name}, :__not_found__) != :__not_found__ do
      true
    else
      candidates = symbol_lookup_candidates(macro_name)

      Enum.any?(candidates, fn cand ->
        :persistent_term.get({:exlisp_macro, cand}, :__not_found__) != :__not_found__
      end)
    end
  end

  defp symbol_lookup_candidates(sym) when is_atom(sym) do
    str = Atom.to_string(sym)

    if :binary.match(str, ["_", "-", ".", ":"]) == :nomatch do
      [sym]
    else
      str_h = String.replace(str, "_", "-")
      str_u = String.replace(str, "-", "_")

      cands =
        cond do
          String.contains?(str, ".") ->
            [pkg, name] = String.split(str, ".", parts: 2)
            pkg_h = String.replace(pkg, "_", "-")
            pkg_u = String.replace(pkg, "-", "_")
            name_h = String.replace(name, "_", "-")
            name_u = String.replace(name, "-", "_")

            [
              sym,
              String.to_atom(str_h),
              String.to_atom(str_u),
              String.to_atom("#{pkg}:#{name}"),
              String.to_atom("#{pkg_h}:#{name_h}"),
              String.to_atom("#{pkg_u}:#{name_u}")
            ]

          String.contains?(str, ":") ->
            [pkg, name] = String.split(str, ":", parts: 2)
            pkg_h = String.replace(pkg, "_", "-")
            pkg_u = String.replace(pkg, "-", "_")
            name_h = String.replace(name, "_", "-")
            name_u = String.replace(name, "-", "_")

            [
              sym,
              String.to_atom(str_h),
              String.to_atom(str_u),
              String.to_atom("#{pkg}.#{name}"),
              String.to_atom("#{pkg_h}.#{name_h}"),
              String.to_atom("#{pkg_u}.#{name_u}")
            ]

          true ->
            [sym, String.to_atom(str_h), String.to_atom(str_u)]
        end

      cands |> Enum.uniq()
    end
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
  Defines or removes a global symbol macro.
  """
  def put_symbol_macro(name, expansion) do
    normalized = normalize_name(name)
    :persistent_term.put({:exlisp_symbol_macro, normalized}, expansion)
    normalized
  end

  def get_symbol_macro(name) do
    :persistent_term.get({:exlisp_symbol_macro, normalize_name(name)}, nil)
  end

  def has_symbol_macro?(name) do
    :persistent_term.get({:exlisp_symbol_macro, normalize_name(name)}, :__not_found__) !=
      :__not_found__
  end

  @doc """
  Defines a compiler macro.
  """
  def put_compiler_macro(name, fun) do
    normalized = normalize_name(name)
    :persistent_term.put({:exlisp_compiler_macro, normalized}, fun)
    normalized
  end

  def get_compiler_macro(name) do
    :persistent_term.get({:exlisp_compiler_macro, normalize_name(name)}, nil)
  end

  def has_compiler_macro?(name) do
    :persistent_term.get({:exlisp_compiler_macro, normalize_name(name)}, :__not_found__) !=
      :__not_found__
  end

  # --- Environment and implementation introspection ---

  def lisp_implementation_type, do: "ExLisp"

  def lisp_implementation_version do
    case Application.spec(:exlisp, :vsn) do
      nil -> Mix.Project.config()[:version]
      version -> to_string(version)
    end
  rescue
    _ -> "0.1.4"
  end

  def short_site_name, do: System.get_env("HOSTNAME") || machine_instance()
  def long_site_name, do: short_site_name()

  def machine_type do
    arch =
      :erlang.system_info(:system_architecture)
      |> to_string()

    case String.split(arch, "-", parts: 2) do
      [machine | _] -> machine
      _ -> arch
    end
  end

  def machine_version, do: nil

  def machine_instance do
    case :inet.gethostname() do
      {:ok, hostname} -> to_string(hostname)
      _ -> ""
    end
  end

  def software_type, do: elem(:os.type(), 1) |> Atom.to_string()

  def software_version do
    case :os.version() do
      {major, minor, patch} -> "#{major}.#{minor}.#{patch}"
      tuple when is_tuple(tuple) -> tuple |> Tuple.to_list() |> Enum.join(".")
      other -> to_string(other)
    end
  end

  def compile_file_pathname(input_file, output_file \\ nil) do
    input = pathname_namestring(input_file)
    parsed = ExLisp.Pathname.pathname(input)
    basename = parsed.name || Path.rootname(Path.basename(input))

    target =
      cond do
        output_file != nil ->
          pathname_namestring(output_file)

        true ->
          directory =
            case parsed.directory do
              nil -> ""
              directory -> ExLisp.Pathname.directory_namestring(%{parsed | directory: directory})
            end

          Path.join(directory, "#{basename}.beam")
      end

    ExLisp.Pathname.pathname(target)
  end

  def type_of(value) do
    cond do
      value == nil or value == [] ->
        :null

      value == :t ->
        :symbol

      match?({:_values_, _}, value) ->
        :values

      match?({:instance, _, _}, value) ->
        ExLisp.CLOS.class_of(value)

      match?(%ExLisp.Pathname{}, value) ->
        :pathname

      match?(%ExLisp.Character{}, value) ->
        :character

      match?(%ExLisp.Ratio{}, value) ->
        :ratio

      match?(%ExLisp.Stream{}, value) ->
        :stream

      match?(%ExLisp.Symbol{}, value) ->
        :symbol

      match?(%ExLisp.Closure{compiled: true}, value) ->
        :compiled_function

      match?(%ExLisp.Closure{}, value) ->
        :function

      match?({:hash_table, _, _}, value) ->
        :hash_table

      match?({:array, _, _}, value) ->
        :array

      match?({:vector, _}, value) ->
        :vector

      match?({:complex, _, _}, value) ->
        :complex

      is_boolean(value) ->
        :boolean

      is_integer(value) ->
        ExLisp.CLOS.class_of(value)

      is_float(value) ->
        :single_float

      is_binary(value) ->
        :simple_string

      is_atom(value) ->
        if keyword?(value), do: :keyword, else: :symbol

      is_map(value) ->
        :hash_table

      is_list(value) ->
        :cons

      is_function(value) ->
        :function

      true ->
        :t
    end
  end

  @doc """
  Determines whether a Lisp value is a constant expression. An optional
  environment may provide a map with `:constants` and `:variables`.
  """
  def constantp(value, environment \\ nil) do
    boolean =
      cond do
        value in [nil, :t, true, false] ->
          true

        is_number(value) or is_binary(value) ->
          true

        keyword?(value) ->
          true

        match?(%ExLisp.Character{}, value) ->
          true

        match?({:lit, _}, value) ->
          true

        match?({:keyword, _, _}, value) ->
          true

        match?({:atom, _, _}, value) ->
          true

        quoted_form?(value) ->
          true

        is_atom(value) ->
          environment_constant?(environment, value) or
            has_constant_var?(value)

        match?({:id, _, _}, value) ->
          normalized = normalize_name(value)
          environment_constant?(environment, normalized) or has_constant_var?(normalized)

        true ->
          false
      end

    if boolean, do: :t, else: nil
  end

  def variable_information(name, environment \\ nil) do
    normalized = normalize_name(name)

    cond do
      environment_constant?(environment, normalized) ->
        :constant

      is_map(environment) and normalized in Map.get(environment, :specials, []) ->
        :special

      is_map(environment) and normalized in Map.keys(Map.get(environment, :lexical, %{})) ->
        :lexical

      has_var?(normalized) ->
        :special

      true ->
        nil
    end
  end

  def function_information(name, environment \\ nil) do
    normalized = normalize_name(name)

    cond do
      is_map(environment) and Map.has_key?(Map.get(environment, :functions, %{}), normalized) ->
        :function

      has_macro?(normalized) ->
        :macro

      has_fun?(normalized) ->
        :function

      true ->
        nil
    end
  end

  def declaration_information(name, environment \\ nil) do
    if is_map(environment),
      do: Map.get(environment, :declarations, %{}) |> Map.get(normalize_name(name)),
      else: nil
  end

  defp pathname_namestring(%ExLisp.Pathname{} = path), do: ExLisp.Pathname.namestring(path)
  defp pathname_namestring(path) when is_binary(path), do: path
  defp pathname_namestring(path), do: ExLisp.Pathname.namestring(ExLisp.Pathname.pathname(path))

  defp quoted_form?({:list, _pos, [head, _value]}), do: normalize_name(head) == :quote
  defp quoted_form?([head, _value]) when is_atom(head), do: normalize_name(head) == :quote
  defp quoted_form?(_), do: false

  defp environment_constant?(environment, name) when is_map(environment) do
    name in Map.get(environment, :constants, []) or
      Map.has_key?(Map.get(environment, :constant_bindings, %{}), name)
  end

  defp environment_constant?(_, _), do: false

  defp has_constant_var?(name) do
    normalized = normalize_name(name)
    text = Atom.to_string(normalized)

    case normalized do
      n when n in [:pi, :t, nil, :internal_time_units_per_second] ->
        true

      _ ->
        String.starts_with?(text, "most-") or
          String.starts_with?(text, "most_") or
          String.starts_with?(text, "least-") or
          String.starts_with?(text, "least_") or
          String.starts_with?(text, "single-float-") or
          String.starts_with?(text, "single_float_") or
          String.starts_with?(text, "double-float-") or
          String.starts_with?(text, "double_float_") or
          String.starts_with?(text, "long-float-") or
          String.starts_with?(text, "long_float_") or
          String.starts_with?(text, "short-float-") or
          String.starts_with?(text, "short_float_") or
          String.starts_with?(text, "boole-") or
          String.starts_with?(text, "boole_")
    end
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
