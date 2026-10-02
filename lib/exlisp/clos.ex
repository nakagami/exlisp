defmodule ExLisp.CLOS do
  @moduledoc """
  Common Lisp Object System (CLOS) implementation for ExLisp.
  Supports:
  - defclass (inheritance, CPL linearization, slot inheritance, initargs, initforms, accessors, readers, writers)
  - defgeneric and defmethod
  - Method qualifiers: :before, :after, :around, and primary methods
  - Standard Method Combination
  - Multi-argument method dispatch and (eql ...) specializers
  - call-next-method and next-method-p
  - make-instance, slot-value, (setf slot-value), slot-boundp, slot-makunbound, slot-exists-p
  - class-of, find-class, class-name, subclassp, subtypep integration
  """

  def ensure_tables do
    case :persistent_term.get({:exlisp_clos_class, :t}, :__not_found__) do
      :__not_found__ -> init_built_in_classes()
      _ -> :ok
    end

    :ok
  end

  def reset do
    for {{tag, _} = key, _} <- :persistent_term.get(),
        tag in [:exlisp_clos_class, :exlisp_clos_generic, :exlisp_clos_methods] do
      :persistent_term.erase(key)
    end

    init_built_in_classes()
    :ok
  end

  # --- Built-in Class Hierarchy ---

  @built_in_classes [
    {:t, [], [:t]},
    {:standard_object, [:t], [:standard_object, :t]},
    {:structure_object, [:t], [:structure_object, :t]},
    {:number, [:t], [:number, :t]},
    {:integer, [:number], [:integer, :number, :t]},
    {:fixnum, [:integer], [:fixnum, :integer, :number, :t]},
    {:bignum, [:integer], [:bignum, :integer, :number, :t]},
    {:float, [:number], [:float, :number, :t]},
    {:ratio, [:number], [:ratio, :number, :t]},
    {:symbol, [:t], [:symbol, :t]},
    {:keyword, [:symbol], [:keyword, :symbol, :t]},
    {:string, [:t], [:string, :t]},
    {:character, [:t], [:character, :t]},
    {:list, [:t], [:list, :t]},
    {:cons, [:list], [:cons, :list, :t]},
    {:null, [:symbol, :list], [:null, :symbol, :list, :t]},
    {:hash_table, [:t], [:hash_table, :t]},
    {:function, [:t], [:function, :t]},
    {:vector, [:t], [:vector, :t]},
    {:array, [:t], [:array, :t]}
  ]

  def init_built_in_classes do
    Enum.each(@built_in_classes, fn {name, supers, cpl} ->
      class_info = %{
        name: name,
        direct_supers: supers,
        cpl: cpl,
        slots: %{},
        options: %{}
      }

      :persistent_term.put({:exlisp_clos_class, name}, class_info)
    end)
  end

  # --- CPL (Class Precedence List) Computation ---

  @doc """
  Computes the Class Precedence List (CPL) for a class using CLOS standard linearization.
  """
  def compute_cpl(class_name, direct_supers) do
    norm_supers =
      case direct_supers do
        [] -> [:standard_object]
        supers -> supers
      end

    super_cpls = Enum.map(norm_supers, &get_cpl/1)
    lists_to_merge = super_cpls ++ [norm_supers]

    merged = merge_cpls(lists_to_merge)
    [class_name | merged] |> Enum.uniq()
  end

  def get_cpl(class_name) do
    ensure_tables()
    norm = normalize_name(class_name)

    case :persistent_term.get({:exlisp_clos_class, norm}, :__not_found__) do
      %{cpl: cpl} -> cpl
      _ -> [norm, :standard_object, :t]
    end
  end

  defp merge_cpls(lists) do
    cleaned_lists = Enum.reject(lists, &Enum.empty?/1)
    if Enum.empty?(cleaned_lists) do
      []
    else
      # Find candidate in head of any list that does not appear in tail of any list
      candidate =
        Enum.find_value(cleaned_lists, fn [head | _] ->
          in_tails? =
            Enum.any?(cleaned_lists, fn
              [_h | tail] -> head in tail
              _ -> false
            end)

          if not in_tails?, do: head, else: nil
        end)

      case candidate do
        nil ->
          # Fallback: pick first head to break cycle
          [fallback_head | _] = hd(cleaned_lists)
          remaining =
            Enum.map(cleaned_lists, fn
              [^fallback_head | rest] -> rest
              other -> other
            end)
          [fallback_head | merge_cpls(remaining)]

        chosen ->
          remaining =
            Enum.map(cleaned_lists, fn
              [^chosen | rest] -> rest
              other -> other
            end)
          [chosen | merge_cpls(remaining)]
      end
    end
  end

  # --- Class Registration ---

  @doc """
  Registers a CLOS class.
  """
  def register_class(name, supers, slots_spec, options \\ []) do
    ensure_tables()
    class_name = normalize_name(name)
    norm_supers = Enum.map(supers, &normalize_name/1)
    cpl = compute_cpl(class_name, norm_supers)

    parsed_slots = parse_slots_spec(slots_spec)
    all_slots = inherit_slots(cpl, parsed_slots)

    class_info = %{
      name: class_name,
      direct_supers: norm_supers,
      cpl: cpl,
      direct_slots: parsed_slots,
      slots: all_slots,
      options: options
    }

    :persistent_term.put({:exlisp_clos_class, class_name}, class_info)
    register_slot_methods(class_name, parsed_slots)
    class_name
  end

  def find_class(name) do
    ensure_tables()
    norm = normalize_name(name)

    case :persistent_term.get({:exlisp_clos_class, norm}, :__not_found__) do
      :__not_found__ -> nil
      info -> info
    end
  end

  def class_name(%{name: name}), do: name
  def class_name(name) when is_atom(name), do: name
  def class_name(_), do: nil

  defp parse_slots_spec(slots_spec) do
    Enum.map(slots_spec, fn
      slot_name when is_atom(slot_name) or is_binary(slot_name) ->
        norm = normalize_name(slot_name)
        {norm, %{name: norm, initargs: [], initform_fun: nil, initform_ast: nil, accessors: [], readers: [], writers: [], type: :t, allocation: :instance}}

      slot_def when is_list(slot_def) ->
        [name | opts] = slot_def
        norm = normalize_name(name)
        parsed_opts = parse_slot_opts(opts)
        {norm, Map.put(parsed_opts, :name, norm)}

      {name, opts} ->
        norm = normalize_name(name)
        {norm, Map.put(opts, :name, norm)}
    end)
    |> Map.new()
  end

  defp parse_slot_opts(opts) do
    Enum.chunk_every(opts, 2)
    |> Enum.reduce(%{initargs: [], initform_fun: nil, initform_ast: nil, accessors: [], readers: [], writers: [], type: :t, allocation: :instance}, fn
      [key, val], acc ->
        k_str = to_string(key) |> String.downcase() |> String.trim_leading(":")
        case k_str do
          "initarg" ->
            norm_kw = val |> to_string() |> String.trim_leading(":") |> String.downcase() |> String.to_atom()
            Map.update!(acc, :initargs, &[norm_kw | &1])

          k when k in ["initform", "initform_fun"] ->
            if is_function(val, 0) do
              Map.put(acc, :initform_fun, val)
            else
              acc
              |> Map.put(:initform_ast, val)
              |> Map.put(:initform_fun, compile_initform_fun(val))
            end

          "accessor" ->
            acc_name = normalize_name(val)
            Map.update!(acc, :accessors, &[acc_name | &1])

          "reader" ->
            r_name = normalize_name(val)
            Map.update!(acc, :readers, &[r_name | &1])

          "writer" ->
            w_name = normalize_name(val)
            Map.update!(acc, :writers, &[w_name | &1])

          "type" ->
            Map.put(acc, :type, normalize_name(val))

          "allocation" ->
            Map.put(acc, :allocation, normalize_name(val))

          _ ->
            acc
        end

      _, acc ->
        acc
    end)
  end

  defp compile_initform_fun(ast) do
    fn ->
      try do
        LispBeam.evaluate_ast(ast)
      rescue
        _ -> ast
      end
    end
  end

  defp inherit_slots(cpl, direct_slots) do
    # Traverse CPL in reverse (:t -> supers -> direct) to merge slots
    cpl
    |> Enum.reverse()
    |> Enum.reduce(%{}, fn class, acc ->
      case find_class(class) do
        %{slots: parent_slots} ->
          Map.merge(acc, parent_slots, fn _k, p_slot, c_slot ->
            merge_slot_definition(p_slot, c_slot)
          end)

        _ ->
          acc
      end
    end)
    |> Map.merge(direct_slots, fn _k, p_slot, c_slot ->
      merge_slot_definition(p_slot, c_slot)
    end)
  end

  defp merge_slot_definition(parent_slot, child_slot) do
    %{
      name: child_slot.name,
      initargs: Enum.uniq((child_slot[:initargs] || []) ++ (parent_slot[:initargs] || [])),
      initform_fun: child_slot[:initform_fun] || parent_slot[:initform_fun],
      initform_ast: child_slot[:initform_ast] || parent_slot[:initform_ast],
      accessors: Enum.uniq((child_slot[:accessors] || []) ++ (parent_slot[:accessors] || [])),
      readers: Enum.uniq((child_slot[:readers] || []) ++ (parent_slot[:readers] || [])),
      writers: Enum.uniq((child_slot[:writers] || []) ++ (parent_slot[:writers] || [])),
      type: child_slot[:type] || parent_slot[:type] || :t,
      allocation: child_slot[:allocation] || parent_slot[:allocation] || :instance
    }
  end

  defp register_slot_methods(class_name, slots) do
    Enum.each(slots, fn {_name, slot_def} ->
      slot_sym = slot_def.name

      # Readers
      readers = (slot_def[:readers] || []) ++ (slot_def[:accessors] || [])
      Enum.each(readers, fn r_name ->
        register_method(r_name, nil, [class_name], fn inst ->
          slot_value(inst, slot_sym)
        end)
      end)

      # Accessors setf
      accessors = slot_def[:accessors] || []
      Enum.each(accessors, fn acc_name ->
        setf_name = :"setf_#{acc_name}"
        register_method(setf_name, nil, [:t, class_name], fn val, inst ->
          set_slot_value(inst, slot_sym, val)
        end)
      end)

      # Writers
      writers = slot_def[:writers] || []
      Enum.each(writers, fn w_name ->
        register_method(w_name, nil, [:t, class_name], fn val, inst ->
          set_slot_value(inst, slot_sym, val)
        end)

        setf_name = :"setf_#{w_name}"
        register_method(setf_name, nil, [:t, class_name], fn val, inst ->
          set_slot_value(inst, slot_sym, val)
        end)
      end)
    end)
  end

  # --- Instance Operations ---

  @doc """
  Creates a new CLOS instance.
  """
  def make_instance(class_name_or_obj, initargs \\ []) do
    ensure_tables()
    class_name =
      case class_name_or_obj do
        %{name: n} -> n
        n when is_atom(n) or is_binary(n) -> normalize_name(n)
        _ -> :standard_object
      end

    class_info = find_class(class_name)
    slots = if class_info, do: class_info.slots, else: %{}

    init_map = parse_initargs_kv(initargs)

    tid = :ets.new(:lisp_instance, [:set, :public])

    Enum.each(slots, fn {slot_name, slot_def} ->
      # Check if any initarg matches
      init_val =
        Enum.find_value(slot_def[:initargs] || [], fn initarg ->
          case Map.fetch(init_map, initarg) do
            {:ok, val} -> {:ok, val}
            :error -> nil
          end
        end)

      case init_val do
        {:ok, val} ->
          :ets.insert(tid, {slot_name, val})

        nil ->
          # Check initform
          if is_function(slot_def[:initform_fun], 0) do
            val = slot_def[:initform_fun].()
            :ets.insert(tid, {slot_name, val})
          end
      end
    end)

    # Also insert any leftover explicit initargs as slots (e.g. dynamic slots)
    Enum.each(init_map, fn {k, v} ->
      if not :ets.member(tid, k) do
        :ets.insert(tid, {k, v})
      end
    end)

    inst = {:instance, class_name, tid}

    # Call initialize-instance if defined
    try do
      if generic_defined?(:initialize_instance) or generic_defined?(:"initialize-instance") do
        init_gen_name = if generic_defined?(:initialize_instance), do: :initialize_instance, else: :"initialize-instance"
        apply_generic(init_gen_name, [inst, initargs])
      end
    rescue
      _ -> :ok
    end

    inst
  end

  defp parse_initargs_kv(initargs) when is_map(initargs) do
    Enum.reduce(initargs, %{}, fn {k, v}, acc ->
      norm_k = k |> to_string() |> String.trim_leading(":") |> String.downcase() |> String.replace("-", "_") |> String.to_atom()
      Map.put(acc, norm_k, v)
    end)
  end

  defp parse_initargs_kv(initargs) when is_list(initargs) do
    cond do
      Keyword.keyword?(initargs) or (initargs != [] and is_tuple(hd(initargs))) ->
        Enum.reduce(initargs, %{}, fn
          {k, v}, acc ->
            norm_k = k |> to_string() |> String.trim_leading(":") |> String.downcase() |> String.replace("-", "_") |> String.to_atom()
            Map.put(acc, norm_k, v)

          _, acc ->
            acc
        end)

      true ->
        Enum.chunk_every(initargs, 2)
        |> Enum.reduce(%{}, fn
          [k, v], acc ->
            norm_k = k |> to_string() |> String.trim_leading(":") |> String.downcase() |> String.replace("-", "_") |> String.to_atom()
            Map.put(acc, norm_k, v)

          _, acc ->
            acc
        end)
    end
  end
  defp parse_initargs_kv(_), do: %{}

  def slot_value({:instance, _class, tid}, slot_name) do
    norm = normalize_slot_name(slot_name)
    case :ets.lookup(tid, norm) do
      [{^norm, val}] -> val
      [] -> nil
    end
  end
  def slot_value({:struct, name, tid}, slot_name), do: ExLisp.Builtins.get_struct_slot({:struct, name, tid}, slot_name)
  def slot_value(_other, _slot), do: nil

  def set_slot_value({:instance, _class, tid}, slot_name, val) do
    norm = normalize_slot_name(slot_name)
    :ets.insert(tid, {norm, val})
    val
  end
  def set_slot_value({:struct, name, tid}, slot_name, val), do: ExLisp.Builtins.set_struct_slot({:struct, name, tid}, slot_name, val)
  def set_slot_value(_other, _slot, val), do: val

  def slot_boundp({:instance, _class, tid}, slot_name) do
    norm = normalize_slot_name(slot_name)
    if :ets.member(tid, norm), do: :t, else: nil
  end
  def slot_boundp(_other, _slot), do: nil

  def slot_makunbound({:instance, _class, tid} = inst, slot_name) do
    norm = normalize_slot_name(slot_name)
    :ets.delete(tid, norm)
    inst
  end
  def slot_makunbound(other, _slot), do: other

  def slot_exists_p({:instance, class_name, _tid}, slot_name) do
    norm = normalize_slot_name(slot_name)
    class_info = find_class(class_name)
    if class_info != nil and Map.has_key?(class_info.slots, norm), do: :t, else: nil
  end
  def slot_exists_p(_other, _slot), do: nil

  def class_of({:instance, class_name, _tid}), do: class_name
  def class_of({:struct, struct_name, _tid}), do: struct_name
  def class_of(val) when is_integer(val), do: :integer
  def class_of(val) when is_float(val), do: :float
  def class_of(%ExLisp.Ratio{}), do: :ratio
  def class_of(val) when is_binary(val), do: :string
  def class_of(val) when is_atom(val) do
    cond do
      val in [nil, :nil, []] -> :null
      ExLisp.Env.keyword?(val) -> :keyword
      true -> :symbol
    end
  end
  def class_of(val) when is_list(val), do: :cons
  def class_of(val) when is_map(val), do: :hash_table
  def class_of(val) when is_function(val), do: :function
  def class_of(_), do: :t

  def subclassp(sub, super) do
    sub_norm = normalize_name(sub)
    super_norm = normalize_name(super)
    if sub_norm == super_norm do
      :t
    else
      cpl = get_cpl(sub_norm)
      if super_norm in cpl, do: :t, else: nil
    end
  end

  def type_matches_clos?(expected_type, arg) do
    exp_norm = normalize_name(expected_type)
    if exp_norm in [:t, :_] do
      true
    else
      actual_class = class_of(arg)
      if actual_class == exp_norm do
        true
      else
        cpl = get_cpl(actual_class)
        exp_norm in cpl
      end
    end
  end

  # --- Generic Functions and Method Dispatch ---

  @doc """
  Registers a generic function definition.
  """
  def register_generic(name, lambda_list \\ [], options \\ []) do
    ensure_tables()
    gen_name = normalize_name(name)

    info = %{
      name: gen_name,
      lambda_list: lambda_list,
      options: options
    }

    :persistent_term.put({:exlisp_clos_generic, gen_name}, info)
    ensure_generic_dispatcher(gen_name)
    gen_name
  end

  def generic_defined?(name) do
    ensure_tables()
    gen_name = normalize_name(name)
    :persistent_term.get({:exlisp_clos_generic, gen_name}, :__not_found__) != :__not_found__
  end

  @doc """
  Registers a method on a generic function.
  qualifier can be nil (primary), :before, :after, :around.
  specializers is a list of type names or {:eql, value}.
  fun is (args -> result).
  """
  def register_method(name, qualifier, specializers, fun)
      when is_atom(name) and is_list(specializers) and is_function(fun) do
    ensure_tables()
    gen_name = normalize_name(name)
    norm_qualifier = normalize_qualifier(qualifier)
    norm_specializers = Enum.map(specializers, &normalize_specializer/1)

    key = {:exlisp_clos_methods, gen_name}
    current_methods = :persistent_term.get(key, [])

    method_entry = %{
      qualifier: norm_qualifier,
      specializers: norm_specializers,
      fun: fun
    }

    updated_methods =
      [
        method_entry
        | Enum.reject(current_methods, fn m ->
            m.qualifier == norm_qualifier and m.specializers == norm_specializers
          end)
      ]

    :persistent_term.put(key, updated_methods)
    ensure_generic_dispatcher(gen_name)
    gen_name
  end

  defp normalize_qualifier(nil), do: :primary
  defp normalize_qualifier(:primary), do: :primary
  defp normalize_qualifier(q) when is_atom(q) do
    case q |> Atom.to_string() |> String.downcase() |> String.trim_leading(":") do
      "before" -> :before
      "after" -> :after
      "around" -> :around
      _ -> :primary
    end
  end
  defp normalize_qualifier(_), do: :primary

  defp normalize_specializer({:eql, val}), do: {:eql, val}
  defp normalize_specializer(s) when is_atom(s) or is_binary(s), do: normalize_name(s)
  defp normalize_specializer(other), do: other

  defp ensure_generic_dispatcher(gen_name) do
    dispatcher = fn args ->
      apply_generic(gen_name, args)
    end

    closure = %ExLisp.Closure{
      fun: dispatcher,
      name: gen_name,
      variadic: true
    }

    ExLisp.Env.put_fun(gen_name, closure)
  end

  @doc """
  Applies a generic function using the Standard Method Combination.
  """
  def apply_generic(gen_name, args) do
    ensure_tables()
    key = {:exlisp_clos_methods, normalize_name(gen_name)}
    methods = :persistent_term.get(key, [])

    applicable = find_applicable_methods(methods, args)

    if Enum.empty?(applicable) do
      raise RuntimeError,
            "No applicable method for #{inspect(gen_name)} with arguments #{inspect(args)}"
    end

    # Group sorted applicable methods by qualifier
    around_methods = Enum.filter(applicable, &(&1.qualifier == :around))
    before_methods = Enum.filter(applicable, &(&1.qualifier == :before))
    primary_methods = Enum.filter(applicable, &(&1.qualifier == :primary))
    after_methods = Enum.filter(applicable, &(&1.qualifier == :after)) |> Enum.reverse()

    if Enum.empty?(primary_methods) and Enum.empty?(around_methods) do
      raise RuntimeError,
            "No primary or around method for #{inspect(gen_name)} with arguments #{inspect(args)}"
    end

    # Execution builder:
    # 1. Main core: run all :before, then primary chain, then all :after, return primary result.
    run_main_core = fn current_args ->
      Enum.each(before_methods, fn m -> invoke_method(m, current_args, []) end)
      primary_result = execute_primary_chain(primary_methods, current_args)
      Enum.each(after_methods, fn m -> invoke_method(m, current_args, []) end)
      primary_result
    end

    # If around methods exist, wrap main core in around chain
    if Enum.empty?(around_methods) do
      run_main_core.(args)
    else
      execute_around_chain(around_methods, run_main_core, args)
    end
  end

  defp execute_primary_chain([], _args) do
    raise RuntimeError, "No more next methods in primary chain"
  end
  defp execute_primary_chain([head | rest], args) do
    invoke_method(head, args, rest)
  end

  defp execute_around_chain([], main_core, args) do
    main_core.(args)
  end
  defp execute_around_chain([head | rest], main_core, args) do
    next_around_fn = fn next_args ->
      execute_around_chain(rest, main_core, next_args)
    end

    pseudo_next = %{
      qualifier: :around,
      specializers: [],
      fun: fn
        next_args when is_list(next_args) ->
          next_around_fn.(next_args)

        single_arg ->
          next_around_fn.([single_arg])
      end
    }
    invoke_method(head, args, [pseudo_next])
  end

  defp invoke_method(method, args, next_methods) do
    # Store next_methods in process dictionary for call-next-method / next-method-p
    prev_next = Process.get(:exlisp_clos_next_methods, :none)
    prev_args = Process.get(:exlisp_clos_current_args, :none)

    Process.put(:exlisp_clos_next_methods, next_methods)
    Process.put(:exlisp_clos_current_args, args)

    try do
      fun = method.fun
      cond do
        is_function(fun, length(args)) ->
          apply(fun, args)

        is_function(fun, 1) ->
          fun.(args)

        true ->
          apply(fun, args)
      end
    after
      if prev_next == :none do
        Process.delete(:exlisp_clos_next_methods)
      else
        Process.put(:exlisp_clos_next_methods, prev_next)
      end

      if prev_args == :none do
        Process.delete(:exlisp_clos_current_args)
      else
        Process.put(:exlisp_clos_current_args, prev_args)
      end
    end
  end

  @doc """
  Invokes the next method in the current method combination chain.
  """
  def call_next_method(custom_args \\ nil) do
    case Process.get(:exlisp_clos_next_methods, []) do
      [] ->
        raise RuntimeError, "No next method available for call-next-method"

      [next_method | remaining] ->
        args =
          if custom_args != nil and custom_args != [],
            do: custom_args,
            else: Process.get(:exlisp_clos_current_args, [])

        invoke_method(next_method, args, remaining)
    end
  end

  @doc """
  Returns :t if a next method is available, nil otherwise.
  """
  def next_method_p do
    case Process.get(:exlisp_clos_next_methods, []) do
      [] -> nil
      [_ | _] -> :t
      _ -> nil
    end
  end

  # --- Method Applicability and Specificity Sorting ---

  defp find_applicable_methods(methods, args) do
    methods
    |> Enum.filter(fn m -> method_applicable?(m.specializers, args) end)
    |> Enum.sort(fn m1, m2 -> method_more_specific?(m1.specializers, m2.specializers, args) end)
  end

  defp method_applicable?(specializers, args) do
    # Match specializers with args (prefix match allowed for rest args)
    Enum.zip(specializers, args)
    |> Enum.all?(fn {spec, arg} -> specializer_matches?(spec, arg) end)
  end

  defp specializer_matches?({:eql, val}, arg), do: val == arg
  defp specializer_matches?(spec, arg), do: type_matches_clos?(spec, arg)

  defp method_more_specific?([], [], _args), do: true
  defp method_more_specific?([], _s2, _args), do: false
  defp method_more_specific?(_s1, [], _args), do: true
  defp method_more_specific?([spec1 | rest1], [spec2 | rest2], [arg | rest_args]) do
    case compare_specializer(spec1, spec2, arg) do
      :greater -> true
      :lesser -> false
      :equal -> method_more_specific?(rest1, rest2, rest_args)
    end
  end
  defp method_more_specific?([_ | rest1], [_ | rest2], []) do
    method_more_specific?(rest1, rest2, [])
  end

  defp compare_specializer(s, s, _arg), do: :equal
  defp compare_specializer({:eql, _}, _other, _arg), do: :greater
  defp compare_specializer(_other, {:eql, _}, _arg), do: :lesser
  defp compare_specializer(s1, s2, arg) do
    cpl = get_cpl(class_of(arg))
    idx1 = Enum.find_index(cpl, &(&1 == s1)) || 999_999
    idx2 = Enum.find_index(cpl, &(&1 == s2)) || 999_999

    cond do
      idx1 < idx2 -> :greater
      idx1 > idx2 -> :lesser
      true -> :equal
    end
  end

  # --- Helper functions ---

  defp normalize_name(name) when is_atom(name) do
    name |> Atom.to_string() |> String.downcase() |> String.replace("-", "_") |> String.to_atom()
  end
  defp normalize_name(name) when is_binary(name) do
    name |> String.downcase() |> String.replace("-", "_") |> String.to_atom()
  end
  defp normalize_name(%ExLisp.Symbol{name: name}), do: normalize_name(name)
  defp normalize_name(other), do: other

  defp normalize_slot_name(name) when is_atom(name) do
    name |> Atom.to_string() |> String.downcase() |> String.replace("-", "_") |> String.to_atom()
  end
  defp normalize_slot_name(name) when is_binary(name) do
    name |> String.downcase() |> String.replace("-", "_") |> String.to_atom()
  end
  defp normalize_slot_name(%ExLisp.Symbol{name: name}), do: normalize_slot_name(name)
  defp normalize_slot_name(other), do: other
end
