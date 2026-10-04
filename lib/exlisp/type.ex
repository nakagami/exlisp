defmodule ExLisp.Type do
  @moduledoc """
  ANSI Common Lisp Type System implementation for ExLisp.
  Supports primitive types, compound type specifiers, `deftype` user-defined types,
  `typep`, `subtypep`, and type expansion.
  """

  @deftype_table :exlisp_deftypes

  @doc """
  Ensures the ETS table for deftype is created.
  """
  def ensure_tables do
    if :ets.info(@deftype_table) == :undefined do
      :ets.new(@deftype_table, [:named_table, :public, :set, read_concurrency: true])
    end
    :ok
  end

  @doc """
  Registers a deftype definition.
  `lambda_list` is a list of parameters, and `expander_fun` is a function `fn args -> expanded_typespec end`.
  """
  def register_deftype(name, lambda_list, expander_fun) when is_function(expander_fun) do
    ensure_tables()
    norm_name = normalize_type_name(name)
    :ets.insert(@deftype_table, {norm_name, {lambda_list, expander_fun}})
    norm_name
  end

  @doc """
  Registers a deftype with an AST expansion or macro-like transformer.
  """
  def define_deftype(name, lambda_list, body_forms) do
    ensure_tables()
    norm_name = normalize_type_name(name)

    expander_fun = fn args ->
      eval_deftype_expansion(lambda_list, body_forms, args)
    end

    :ets.insert(@deftype_table, {norm_name, {lambda_list, expander_fun}})
    norm_name
  end

  defp eval_deftype_expansion(lambda_list, body_forms, args) do
    # Bind arguments to parameters and evaluate the body forms (last form is returned)
    param_names =
      Enum.map(lambda_list, fn
        a when is_atom(a) -> a
        %ExLisp.Symbol{name: n} -> String.to_atom(String.downcase(n))
        s when is_binary(s) -> String.to_atom(String.downcase(s))
        other -> other
      end)

    # Process &optional and defaults if any
    bindings = bind_deftype_params(param_names, args)

    let_bindings =
      Enum.map(bindings, fn {var, val} ->
        {:list, 1, [{:id, 1, [Atom.to_string(var)]}, {:lit, val}]}
      end)

    wrapped_ast =
      {:list, 1,
       [
         {:id, 1, ["let*"]},
         {:list, 1, let_bindings}
         | body_forms
       ]}

    case LispBeam.evaluate_ast(wrapped_ast) do
      [:_values_, [res | _]] -> res
      res -> res
    end
  end

  defp bind_deftype_params([], _args), do: []

  defp bind_deftype_params([:"&optional" | rest_params], args) do
    bind_optional_params(rest_params, args)
  end

  defp bind_deftype_params([:"&rest", rest_var | _], args) do
    [{rest_var, args}]
  end

  defp bind_deftype_params([p | rest_params], [a | rest_args]) do
    [{p, a} | bind_deftype_params(rest_params, rest_args)]
  end

  defp bind_deftype_params([p | rest_params], []) do
    [{p, :*} | bind_deftype_params(rest_params, [])]
  end

  defp bind_optional_params([], _args), do: []

  defp bind_optional_params([:"&rest", rest_var | _], args) do
    [{rest_var, args}]
  end

  defp bind_optional_params([p | rest_params], [a | rest_args]) do
    case p do
      [var, _default | _] -> [{normalize_param_name(var), a} | bind_optional_params(rest_params, rest_args)]
      var -> [{normalize_param_name(var), a} | bind_optional_params(rest_params, rest_args)]
    end
  end

  defp bind_optional_params([p | rest_params], []) do
    case p do
      [var, default | _] -> [{normalize_param_name(var), default} | bind_optional_params(rest_params, [])]
      var -> [{normalize_param_name(var), :*} | bind_optional_params(rest_params, [])]
    end
  end

  defp normalize_param_name(a) when is_atom(a), do: a
  defp normalize_param_name(%ExLisp.Symbol{name: n}), do: String.to_atom(String.downcase(n))
  defp normalize_param_name(s) when is_binary(s), do: String.to_atom(String.downcase(s))

  @doc """
  Expands a type specifier if it is a user-defined deftype.
  Recursively expands up to max_depth.
  """
  def expand_type(type_spec, depth \\ 0)

  def expand_type(type_spec, depth) when depth > 32 do
    type_spec
  end

  def expand_type(name, depth) when is_atom(name) or is_binary(name) do
    norm = normalize_type_name(name)
    ensure_tables()

    case :ets.lookup(@deftype_table, norm) do
      [{^norm, {_params, expander_fun}}] ->
        expanded = expander_fun.([])
        expand_type(expanded, depth + 1)

      _ ->
        norm
    end
  end

  def expand_type(%ExLisp.Symbol{name: n}, depth) do
    expand_type(n, depth)
  end

  def expand_type([head | args], depth) when is_atom(head) or is_binary(head) or is_struct(head, ExLisp.Symbol) do
    norm_head = normalize_type_name(head)
    ensure_tables()

    case :ets.lookup(@deftype_table, norm_head) do
      [{^norm_head, {_params, expander_fun}}] ->
        expanded = expander_fun.(args)
        expand_type(expanded, depth + 1)

      _ ->
        [norm_head | Enum.map(args, &expand_type_arg(&1, depth))]
    end
  end

  def expand_type(other, _depth), do: other

  defp expand_type_arg(arg, depth) do
    cond do
      is_list(arg) and arg != [] and (is_atom(hd(arg)) or is_binary(hd(arg)) or is_struct(hd(arg), ExLisp.Symbol)) ->
        expand_type(arg, depth)
      is_atom(arg) ->
        norm = normalize_type_name(arg)
        ensure_tables()
        case :ets.lookup(@deftype_table, norm) do
          [{^norm, _}] -> expand_type(arg, depth)
          _ -> arg
        end
      true -> arg
    end
  end

  def normalize_type_name(nil), do: :null
  def normalize_type_name(:null), do: :null
  def normalize_type_name(:t), do: :t
  def normalize_type_name(:common), do: :common
  def normalize_type_name(%ExLisp.Symbol{name: n}), do: normalize_type_name(n)

  def normalize_type_name(str) when is_binary(str) do
    down = String.downcase(str) |> String.replace("-", "_")
    String.to_atom(down)
  end

  def normalize_type_name(atom) when is_atom(atom) do
    str = Atom.to_string(atom) |> String.downcase() |> String.replace("-", "_")
    String.to_atom(str)
  end

  def normalize_type_name(other), do: other

  # --- Type Predicate (typep) ---

  @doc """
  Determines if `val` is of type `type_spec`.
  """
  def typep(val, type_spec) do
    expanded = expand_type(type_spec)
    do_typep(val, expanded)
  end

  defp do_typep(_val, :t), do: true
  defp do_typep(_val, :common), do: true
  defp do_typep(_val, :nil), do: false

  defp do_typep(val, :null), do: val == nil or val == []
  defp do_typep(val, :boolean), do: val in [:t, nil, true, false]
  defp do_typep(val, :symbol), do: is_atom(val) or match?(%ExLisp.Symbol{}, val)
  defp do_typep(val, :keyword), do: is_atom(val) and ExLisp.Env.keyword?(val)

  defp do_typep(val, type) when type in [:character, :base_char, :standard_char, :extended_char] do
    is_integer(val) and val >= 0 and val <= 0x10FFFF
  end

  defp do_typep(val, :number) do
    is_number(val) or match?(%ExLisp.Ratio{}, val) or match?({:complex, _, _}, val)
  end

  defp do_typep(val, :real) do
    is_number(val) or match?(%ExLisp.Ratio{}, val)
  end

  defp do_typep(val, :rational) do
    is_integer(val) or match?(%ExLisp.Ratio{}, val)
  end

  defp do_typep(val, :ratio), do: match?(%ExLisp.Ratio{}, val)
  defp do_typep(val, :complex), do: match?({:complex, _, _}, val)
  defp do_typep(val, :integer), do: is_integer(val)
  defp do_typep(val, :signed_byte), do: is_integer(val)
  defp do_typep(val, :unsigned_byte), do: is_integer(val) and val >= 0
  defp do_typep(val, :fixnum) do
    is_integer(val) and val >= -4_611_686_018_427_387_904 and val <= 4_611_686_018_427_387_903
  end
  defp do_typep(val, :bignum) do
    is_integer(val) and (val < -4_611_686_018_427_387_904 or val > 4_611_686_018_427_387_903)
  end
  defp do_typep(val, type) when type in [:float, :short_float, :single_float, :double_float, :long_float], do: is_float(val)
  defp do_typep(val, :bit), do: val in [0, 1]

  defp do_typep(val, type) when type in [:string, :simple_string, :base_string, :simple_base_string] do
    is_binary(val) or
      (match?({:array, [_], _}, val) and
         case type do
           t when t in [:string, :base_string] -> ExLisp.Builtins.stringp(val) == :t
           t when t in [:simple_string, :simple_base_string] -> ExLisp.Builtins.simple_string_p(val) == :t
         end)
  end

  defp do_typep(val, :pathname), do: match?(%ExLisp.Pathname{}, val)
  defp do_typep(%ExLisp.Pathname{host: h}, :logical_pathname) do
    h not in [nil, :unspecific, ""]
  end
  defp do_typep(_val, :logical_pathname), do: false

  defp do_typep(val, :stream), do: ExLisp.Stream.streamp(val) == :t
  defp do_typep(%ExLisp.Stream{type: :file}, :file_stream), do: true
  defp do_typep(_val, :file_stream), do: false

  defp do_typep(%ExLisp.Stream{type: t}, :string_stream) when t in [:string_input, :string_output], do: true
  defp do_typep(_val, :string_stream), do: false

  defp do_typep(%ExLisp.Stream{type: :broadcast}, :broadcast_stream), do: true
  defp do_typep(_val, :broadcast_stream), do: false

  defp do_typep(%ExLisp.Stream{type: :concatenated}, :concatenated_stream), do: true
  defp do_typep(_val, :concatenated_stream), do: false

  defp do_typep(%ExLisp.Stream{type: :two_way}, :two_way_stream), do: true
  defp do_typep(_val, :two_way_stream), do: false

  defp do_typep(%ExLisp.Stream{type: :synonym}, :synonym_stream), do: true
  defp do_typep(_val, :synonym_stream), do: false

  defp do_typep(%ExLisp.Stream{type: :echo}, :echo_stream), do: true
  defp do_typep(_val, :echo_stream), do: false

  defp do_typep(val, :list), do: is_list(val) or val == nil
  defp do_typep(val, :cons), do: is_list(val) and val != [] and hd(val) != :_values_
  defp do_typep(val, :atom), do: not (is_list(val) and val != [] and hd(val) != :_values_)

  defp do_typep(val, :sequence) do
    is_list(val) or is_binary(val) or is_tuple(val) or
      match?({:array, [_], _}, val) or match?({:bit_vector, _}, val) or
      (is_map(val) and Map.get(val, :__struct__) in [ExLisp.Array, ExLisp.Vector])
  end

  defp do_typep(val, type) when type in [:vector, :simple_vector] do
    is_binary(val) or is_tuple(val) or
      (is_map(val) and Map.get(val, :__struct__) == ExLisp.Vector) or
      (is_list(val) and val != [] and hd(val) == :vector) or
      match?({:bit_vector, _}, val) or
      (match?({:array, [_], _}, val) and
         (type == :vector or ExLisp.Builtins.simple_vector_p(val) == :t))
  end

  defp do_typep(val, type) when type in [:bit_vector, :simple_bit_vector] do
    case val do
      {:bit_vector, bits} when is_list(bits) ->
        true

      {:array, [_], _} ->
        if type == :bit_vector do
          ExLisp.Builtins.bit_vector_p(val) == :t
        else
          ExLisp.Builtins.simple_bit_vector_p(val) == :t
        end

      _ ->
        false
    end
  end

  defp do_typep(val, type) when type in [:array, :simple_array] do
    is_binary(val) or is_tuple(val) or match?({:bit_vector, _}, val) or
      (is_map(val) and Map.get(val, :__struct__) in [ExLisp.Array, ExLisp.Vector]) or
      (is_list(val) and val != [] and hd(val) in [:vector, :array]) or
      (match?({:array, _, _}, val) and
         (type == :array or simple_array_type_check(val)))
  end

  defp do_typep(val, :hash_table) do
    case val do
      {:hash_table, _, _} -> true
      _ -> false
    end
  end

  defp do_typep(val, type) when type in [:function, :compiled_function] do
    is_function(val) or match?(%ExLisp.Closure{}, val) or
      (is_atom(val) and val not in [nil, :t, :nil, :false, :true] and
         (BuiltinFunction.builtin?(val) or ExLisp.Env.has_fun?(val)))
  end

  defp do_typep(val, :package), do: match?(%ExLisp.Package{}, val)
  defp do_typep(val, :readtable), do: match?({:readtable, _}, val)

  defp do_typep(val, :structure_object) do
    is_map(val) and Map.has_key?(val, :__struct__)
  end

  defp do_typep(val, :standard_object) do
    match?({:instance, _, _}, val)
  end

  # Compound type specifiers
  defp do_typep(val, [:and | types]) do
    Enum.all?(types, &do_typep(val, expand_type(&1)))
  end

  defp do_typep(val, [:or | types]) do
    Enum.any?(types, &do_typep(val, expand_type(&1)))
  end

  defp do_typep(val, [:not, type]) do
    not do_typep(val, expand_type(type))
  end

  defp do_typep(val, [:member | members]) do
    Enum.any?(members, fn m ->
      ExLisp.Builtins.eql(val, m) == :t
    end)
  end

  defp do_typep(val, [:eql, obj]) do
    ExLisp.Builtins.eql(val, obj) == :t
  end

  defp do_typep(val, [:satisfies, pred_name]) do
    pred_atom = normalize_type_name(pred_name)
    call_pred(pred_atom, val)
  end

  defp do_typep(val, [:integer | rest]) do
    if is_integer(val) do
      check_range(val, rest)
    else
      false
    end
  end

  defp do_typep(val, [:rational | rest]) do
    if is_integer(val) or match?(%ExLisp.Ratio{}, val) do
      num_val = if is_integer(val), do: val, else: val.numerator / val.denominator
      check_range(num_val, rest)
    else
      false
    end
  end

  defp do_typep(val, [:float | rest]) do
    if is_float(val) do
      check_range(val, rest)
    else
      false
    end
  end

  defp do_typep(val, [:real | rest]) do
    if is_number(val) or match?(%ExLisp.Ratio{}, val) do
      num_val =
        cond do
          is_number(val) -> val
          match?(%ExLisp.Ratio{}, val) -> val.numerator / val.denominator
          true -> val
        end
      check_range(num_val, rest)
    else
      false
    end
  end

  defp do_typep(val, [:mod, n]) when is_integer(n) do
    is_integer(val) and val >= 0 and val < n
  end

  defp do_typep(val, [:signed_byte | rest]) do
    if is_integer(val) do
      case rest do
        [s | _] when is_integer(s) and s > 0 ->
          limit = Bitwise.bsl(1, s - 1)
          val >= -limit and val < limit
        _ ->
          true
      end
    else
      false
    end
  end

  defp do_typep(val, [:unsigned_byte | rest]) do
    if is_integer(val) and val >= 0 do
      case rest do
        [s | _] when is_integer(s) and s > 0 ->
          limit = Bitwise.bsl(1, s)
          val < limit
        _ ->
          true
      end
    else
      false
    end
  end

  defp do_typep(val, [:cons | rest]) do
    if is_list(val) and val != [] and hd(val) != :_values_ do
      case rest do
        [car_t, cdr_t | _] ->
          do_typep(hd(val), expand_type(car_t)) and do_typep(tl(val), expand_type(cdr_t))
        [car_t] ->
          do_typep(hd(val), expand_type(car_t))
        _ ->
          true
      end
    else
      false
    end
  end

  defp do_typep(val, [t | rest]) when t in [:string, :simple_string, :base_string, :simple_base_string] do
    if do_typep(val, t) do
      case rest do
        [len | _] when is_integer(len) -> ExLisp.Builtins.length(val) == len
        _ -> true
      end
    else
      false
    end
  end

  defp do_typep(val, [t | rest]) when t in [:bit_vector, :simple_bit_vector] do
    if do_typep(val, t) do
      case rest do
        [len | _] when is_integer(len) -> ExLisp.Builtins.length(val) == len
        _ -> true
      end
    else
      false
    end
  end

  defp do_typep(val, [:function | _]) do
    do_typep(val, :function)
  end

  defp do_typep(val, [:compiled_function | _]) do
    do_typep(val, :compiled_function)
  end

  defp do_typep(val, [:vector | rest]) do
    if do_typep(val, :vector) do
      case rest do
        [elem_t, size | _] ->
          check_vector_elem_and_size(val, elem_t, size)
        [elem_t] ->
          check_vector_elem_and_size(val, elem_t, :*)
        _ ->
          true
      end
    else
      false
    end
  end

  defp do_typep(val, [:simple_vector | rest]) do
    if do_typep(val, :simple_vector) do
      case rest do
        [size | _] when is_integer(size) -> ExLisp.Builtins.length(val) == size
        _ -> true
      end
    else
      false
    end
  end

  defp do_typep(val, [:array | rest]) do
    if do_typep(val, :array) do
      case rest do
        [elem_t, dims | _] ->
          check_array_elem_and_dims(val, elem_t, dims)
        [elem_t] ->
          check_array_elem_and_dims(val, elem_t, :*)
        _ ->
          true
      end
    else
      false
    end
  end

  defp do_typep(val, [:simple_array | rest]) do
    if do_typep(val, :simple_array) do
      case rest do
        [elem_t, dims | _] ->
          check_array_elem_and_dims(val, elem_t, dims)
        [elem_t] ->
          check_array_elem_and_dims(val, elem_t, :*)
        _ ->
          true
      end
    else
      false
    end
  end

  # CLOS Class check
  defp do_typep(val, class_name) when is_atom(class_name) do
    case val do
      {:instance, c, _tid} ->
        c == class_name or ExLisp.CLOS.subclassp(c, class_name) == :t
      _ ->
        false
    end
  end

  defp do_typep(_val, _type), do: false

  defp simple_array_type_check({:array, _, tid}) do
    case :ets.lookup(tid, :__meta__) do
      [{:__meta__, meta}] ->
        fp = Map.get(meta, :fill_pointer, nil)
        adj = Map.get(meta, :adjustable, false)
        disp = Map.get(meta, :displaced_to, nil)
        fp == nil and not adj and disp == nil

      _ ->
        true
    end
  end

  defp simple_array_type_check(_), do: true

  defp check_range(num, []) when is_number(num), do: true
  defp check_range(num, [low]) when is_number(num), do: check_bound_low(num, low)
  defp check_range(num, [low, high | _]) when is_number(num) do
    check_bound_low(num, low) and check_bound_high(num, high)
  end

  defp check_bound_low(_num, :*), do: true
  defp check_bound_low(_num, :_), do: true
  defp check_bound_low(num, [l]) when is_number(l), do: num > l
  defp check_bound_low(num, l) when is_number(l), do: num >= l
  defp check_bound_low(_num, _), do: true

  defp check_bound_high(_num, :*), do: true
  defp check_bound_high(_num, :_), do: true
  defp check_bound_high(num, [h]) when is_number(h), do: num < h
  defp check_bound_high(num, h) when is_number(h), do: num <= h
  defp check_bound_high(_num, _), do: true

  defp check_vector_elem_and_size(val, elem_t, size) do
    size_ok =
      case size do
        :* -> true
        :_ -> true
        s when is_integer(s) -> ExLisp.Builtins.length(val) == s
        _ -> true
      end

    elem_ok =
      case elem_t do
        :* -> true
        :_ -> true
        :t -> true
        _ ->
          expanded_elem = expand_type(elem_t)
          # Check elements if list or binary
          cond do
            is_binary(val) ->
              expanded_elem in [:character, :base_char, :standard_char]
            is_list(val) ->
              Enum.all?(val, &do_typep(&1, expanded_elem))
            true ->
              true
          end
      end

    size_ok and elem_ok
  end

  defp check_array_elem_and_dims(val, elem_t, dims) do
    dims_ok =
      case dims do
        :* -> true
        :_ -> true
        rank when is_integer(rank) ->
          ExLisp.Builtins.array_rank(val) == rank
        dim_list when is_list(dim_list) ->
          actual_dims = ExLisp.Builtins.array_dimensions(val)
          length(actual_dims) == length(dim_list) and
            Enum.zip(actual_dims, dim_list)
            |> Enum.all?(fn
              {_, :*} -> true
              {_, :_} -> true
              {a, d} when is_integer(d) -> a == d
              _ -> true
            end)
        _ ->
          true
      end

    elem_ok =
      case elem_t do
        :* -> true
        :_ -> true
        :t -> true
        _ ->
          true
      end

    dims_ok and elem_ok
  end

  defp call_pred(pred_atom, val) do
    try do
      # Lookup in builtins or evaluate function call
      case ExLisp.Builtins.funcall(pred_atom, [val]) do
        nil -> false
        false -> false
        _ -> true
      end
    rescue
      _ -> false
    end
  end

  # --- Subtypep ---

  @doc """
  Determines if `type1` is a subtype of `type2`.
  Returns `[:_values_, [is_sub_bool, is_known_bool]]`.
  """
  def subtypep(type1, type2) do
    t1 = expand_type(type1)
    t2 = expand_type(type2)

    is_sub = is_subtype_internal?(t1, t2)
    [:_values_, [ExLisp.Builtins.lisp_bool(is_sub), :t]]
  end

  defp is_subtype_internal?(t1, t2) do
    t1_norm = normalize_type_for_sub(t1)
    t2_norm = normalize_type_for_sub(t2)

    cond do
      t1_norm == t2_norm ->
        true

      t2_norm in [:t, :common, :*] ->
        true

      t1_norm in [:nil, :null, nil] and t2_norm in [:list, :sequence, :symbol, :atom, :t, :common] ->
        true

      t1_norm == :null and t2_norm in [:list, :sequence, :symbol, :atom, :t, :common] ->
        true

      # Simple string types
      t1_norm in [:simple_string, :simple_base_string] and
          (t2_norm in [:string, :vector, :array, :sequence, :simple_array, :base_string, :simple_string] or
             match?([st | _] when st in [:simple_array, :array, :vector, :string], t2_norm)) ->
        case t2_norm do
          :simple_array ->
            true

          [:simple_array, elem, dims] ->
            elem_match?(elem, :character) and dims_match?(dims, 1)

          [:simple_array, elem] ->
            elem_match?(elem, :character)

          [:simple_array] ->
            true

          [:array, elem, dims] ->
            elem_match?(elem, :character) and dims_match?(dims, 1)

          [:array, elem] ->
            elem_match?(elem, :character)

          [:array] ->
            true

          [:vector, elem, size] ->
            elem_match?(elem, :character) and size_match?(size, :*)

          [:vector, elem] ->
            elem_match?(elem, :character)

          [:vector] ->
            true

          [:string, _] ->
            true

          [:string] ->
            true

          _ ->
            t2_norm in [:string, :vector, :array, :sequence, :simple_array, :base_string, :simple_string]
        end

      t1_norm in [:base_string, :string] and
          (t2_norm in [:string, :vector, :array, :sequence] or
             match?([st | _] when st in [:array, :vector, :string], t2_norm)) ->
        case t2_norm do
          [:array, elem, dims] ->
            elem_match?(elem, :character) and dims_match?(dims, 1)

          [:array, elem] ->
            elem_match?(elem, :character)

          [:array] ->
            true

          [:vector, elem, size] ->
            elem_match?(elem, :character) and size_match?(size, :*)

          [:vector, elem] ->
            elem_match?(elem, :character)

          [:vector] ->
            true

          [:string, _] ->
            true

          [:string] ->
            true

          _ ->
            t2_norm in [:string, :vector, :array, :sequence]
        end

      t1_norm in [:bit_vector, :simple_bit_vector] and
          (t2_norm in [:vector, :array, :sequence] or
             (t1_norm == :simple_bit_vector and t2_norm == :simple_array) or
             match?([st | _] when st in [:simple_array, :array, :vector, :bit_vector], t2_norm)) ->
        case t2_norm do
          :simple_array when t1_norm == :simple_bit_vector ->
            true

          [:simple_array, elem, dims] when t1_norm == :simple_bit_vector ->
            elem_match?(elem, :bit) and dims_match?(dims, 1)

          [:simple_array, elem] when t1_norm == :simple_bit_vector ->
            elem_match?(elem, :bit)

          [:simple_array] when t1_norm == :simple_bit_vector ->
            true

          [:array, elem, dims] ->
            elem_match?(elem, :bit) and dims_match?(dims, 1)

          [:array, elem] ->
            elem_match?(elem, :bit)

          [:array] ->
            true

          [:vector, elem, size] ->
            elem_match?(elem, :bit) and size_match?(size, :*)

          [:vector, elem] ->
            elem_match?(elem, :bit)

          [:vector] ->
            true

          _ ->
            t2_norm in [:bit_vector, :vector, :array, :sequence]
        end

      t1_norm == :simple_vector and
          (t2_norm in [:vector, :array, :sequence, :simple_array] or
             match?([st | _] when st in [:simple_array, :array, :vector], t2_norm)) ->
        case t2_norm do
          :simple_array ->
            true

          [:simple_array, elem, dims] ->
            elem_match?(elem, :t) and dims_match?(dims, 1)

          [:simple_array, elem] ->
            elem_match?(elem, :t)

          [:simple_array] ->
            true

          [:array, elem, dims] ->
            elem_match?(elem, :t) and dims_match?(dims, 1)

          [:array, elem] ->
            elem_match?(elem, :t)

          [:array] ->
            true

          [:vector, elem, size] ->
            elem_match?(elem, :t) and size_match?(size, :*)

          [:vector, elem] ->
            elem_match?(elem, :t)

          [:vector] ->
            true

          _ ->
            t2_norm in [:vector, :array, :sequence, :simple_array]
        end

      t1_norm == :vector and
          (t2_norm in [:array, :sequence] or match?([:array | _], t2_norm)) ->
        case t2_norm do
          [:array, elem, dims] ->
            elem in [:*, :_] and dims_match?(dims, 1)

          [:array, elem] ->
            elem in [:*, :_]

          [:array] ->
            true

          _ ->
            t2_norm in [:array, :sequence]
        end

      t1_norm in [:standard_char, :base_char, :extended_char] and t2_norm == :character ->
        true

      t1_norm == :standard_char and t2_norm == :base_char ->
        true

      t1_norm == :cons and t2_norm in [:list, :sequence] ->
        true

      t1_norm == :list and t2_norm == :sequence ->
        true

      t1_norm in [:fixnum, :bignum] and t2_norm in [:integer, :rational, :real, :number] ->
        true

      t1_norm == :integer and t2_norm in [:rational, :real, :number] ->
        true

      t1_norm == :ratio and t2_norm in [:rational, :real, :number] ->
        true

      t1_norm == :rational and t2_norm in [:real, :number] ->
        true

      t1_norm in [:short_float, :single_float, :double_float, :long_float] and
          t2_norm in [:float, :real, :number] ->
        true

      t1_norm == :float and t2_norm in [:real, :number] ->
        true

      t1_norm in [:bit, :boolean] ->
        if t1_norm == :bit,
          do: t2_norm in [:integer, :rational, :real, :number],
          else: t2_norm in [:symbol, :atom]

      match?([:and | _], t1_norm) ->
        [:and | sub_types] = t1_norm
        Enum.all?(sub_types, &is_subtype_internal?(&1, t2_norm))

      match?([:or | _], t2_norm) ->
        [:or | sup_types] = t2_norm
        Enum.any?(sup_types, &is_subtype_internal?(t1_norm, &1))

      # Compound type vs Compound type
      match?([_ | _], t1_norm) and match?([_ | _], t2_norm) ->
        check_compound_subtype(t1_norm, t2_norm)

      is_atom(t1_norm) and is_atom(t2_norm) and ExLisp.CLOS.subclassp(t1_norm, t2_norm) == :t ->
        true

      true ->
        false
    end
  end

  defp normalize_type_for_sub(t) do
    case t do
      atom when is_atom(atom) -> normalize_type_name(atom)
      str when is_binary(str) -> normalize_type_name(str)
      %ExLisp.Symbol{name: n} -> normalize_type_name(n)

      [head | rest] ->
        [normalize_type_for_sub(head) | Enum.map(rest, &normalize_type_for_sub/1)]

      other ->
        other
    end
  end

  defp elem_match?(spec_elem, target_elem) do
    spec_elem in [:*, :_, :t] or spec_elem == target_elem or
      (target_elem in [:character, :base_char] and
         spec_elem in [:character, :base_char, :standard_char]) or
      is_subtype_internal?(target_elem, spec_elem)
  end

  defp dims_match?(dims, rank) do
    case dims do
      :* -> true
      :_ -> true
      r when is_integer(r) -> r == rank
      [d] -> d in [:*, :_] or d == rank
      l when is_list(l) -> length(l) == rank
      _ -> true
    end
  end

  defp size_match?(size, expected) do
    size in [:*, :_] or size == expected
  end

  defp check_compound_subtype([head1 | args1], [head2 | args2]) do
    cond do
      head1 in [:simple_array, :array] and head2 == :array ->
        case {args1, args2} do
          {[e1, d1 | _], [e2, d2 | _]} -> elem_match?(e2, e1) and dims_subtype?(d1, d2)
          {[e1 | _], [e2 | _]} -> elem_match?(e2, e1)
          {_, []} -> true
          _ -> false
        end

      head1 == :simple_array and head2 == :simple_array ->
        case {args1, args2} do
          {[e1, d1 | _], [e2, d2 | _]} -> elem_match?(e2, e1) and dims_subtype?(d1, d2)
          {[e1 | _], [e2 | _]} -> elem_match?(e2, e1)
          {_, []} -> true
          _ -> false
        end

      head1 == :vector and head2 in [:vector, :array] ->
        case {args1, args2} do
          {[e1, s1 | _], [e2, d2 | _]} -> elem_match?(e2, e1) and dims_subtype?(s1, d2)
          {[e1 | _], [e2 | _]} -> elem_match?(e2, e1)
          {_, []} -> true
          _ -> false
        end

      head1 in [:string, :simple_string, :base_string, :simple_base_string] and
          head2 in [:string, :vector, :array, :simple_array] ->
        true

      true ->
        false
    end
  end

  defp dims_subtype?(d1, d2) do
    case {d1, d2} do
      {_, :*} -> true
      {_, :_} -> true
      {r1, r2} when is_integer(r1) and is_integer(r2) -> r1 == r2
      {[r1], r2} when is_integer(r2) -> r1 in [:*, :_] or r1 == r2
      {r1, [r2]} when is_integer(r1) -> r2 in [:*, :_] or r1 == r2
      {[s1], [s2]} -> s2 in [:*, :_] or s1 == s2
      _ -> true
    end
  end

  @doc """
  Upgrades an array element type.
  """
  def upgraded_array_element_type(typespec, _env \\ nil) do
    norm = normalize_type_name(typespec)
    case norm do
      :character -> :character
      :base_char -> :character
      :standard_char -> :character
      :bit -> :bit
      _ -> :t
    end
  end

  @doc """
  Upgrades a complex part type.
  """
  def upgraded_complex_part_type(typespec, _env \\ nil) do
    norm = normalize_type_name(typespec)
    case norm do
      :short_float -> :short_float
      :single_float -> :single_float
      :double_float -> :double_float
      :long_float -> :long_float
      _ -> :real
    end
  end
end
