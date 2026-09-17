defmodule ExLisp.Loop do
  @moduledoc """
  Parser and transpiler for Common Lisp Extended Loop syntax.
  Parses loop clauses such as `(loop for i below 5 sum i)` and expands
  into standard Lisp AST (tail-recursive functions with block, let*, labels).
  """

  @loop_keywords [
    :for,
    :as,
    :repeat,
    :while,
    :until,
    :always,
    :never,
    :thereis,
    :collect,
    :collecting,
    :append,
    :appending,
    :nconc,
    :nconcing,
    :sum,
    :summing,
    :count,
    :counting,
    :maximize,
    :maximizing,
    :minimize,
    :minimizing,
    :do,
    :doing,
    :return,
    :with,
    :initially,
    :finally,
    :when,
    :if,
    :unless,
    :and
  ]

  @doc """
  Determines whether a list of AST nodes represents an extended loop form.
  """
  def extended_loop?(nodes) when is_list(nodes) do
    Enum.any?(nodes, fn node ->
      kw = kw_name(node)
      kw in @loop_keywords
    end)
  end

  def extended_loop?(_), do: false

  @doc """
  Expands an extended loop AST into equivalent Lisp AST.
  """
  def expand(nodes) do
    parsed = parse_loop(nodes)
    build_ast(parsed)
  end

  # --- Token extraction helpers ---

  def kw_name({:id, _pos, [name]}) when is_binary(name) do
    case name do
      "=" -> :=
      ":=" -> :=
      _ -> String.downcase(name) |> String.to_atom()
    end
  end

  def kw_name({:lit, atom}) when is_atom(atom) do
    case atom do
      := -> :=
      _ -> atom |> Atom.to_string() |> String.downcase() |> String.to_atom()
    end
  end

  def kw_name(atom) when is_atom(atom) do
    case atom do
      := -> :=
      _ -> atom |> Atom.to_string() |> String.downcase() |> String.to_atom()
    end
  end

  def kw_name(_), do: nil

  defp symbol_node({:id, _, _} = node), do: node
  defp symbol_node({:list, _, _} = node), do: node
  defp symbol_node({:quoted, _, _} = node), do: node

  defp symbol_node(name) when is_atom(name) do
    {:id, {1, 1}, [Atom.to_string(name)]}
  end

  defp symbol_node(name) when is_binary(name) do
    {:id, {1, 1}, [name]}
  end

  defp symbol_node(node) when is_tuple(node), do: node

  defp lit_node(val) do
    {:lit, val}
  end

  defp int_node(val) when is_integer(val) do
    {:integer, {1, 1}, val}
  end

  # --- Parsing loop syntax ---

  defp parse_loop(nodes) do
    state = %{
      with: [],
      initially: [],
      finally: [],
      for: [],
      body: []
    }

    do_parse_loop(nodes, state)
  end

  defp do_parse_loop([], state), do: state

  defp do_parse_loop([node | rest], state) do
    case kw_name(node) do
      kw when kw in [:for, :as] ->
        {for_clause, rem_tokens} = parse_for_clause(rest)
        do_parse_loop(rem_tokens, %{state | for: state.for ++ [for_clause]})

      :and ->
        {for_clause, rem_tokens} = parse_for_clause(rest)
        do_parse_loop(rem_tokens, %{state | for: state.for ++ [for_clause]})

      :repeat ->
        case rest do
          [count_expr | rem_tokens] ->
            for_clause = {:repeat, count_expr}
            do_parse_loop(rem_tokens, %{state | for: state.for ++ [for_clause]})

          [] ->
            raise ArgumentError, "loop repeat requires a count expression"
        end

      :with ->
        {with_bindings, rem_tokens} = parse_with_clause(rest)
        do_parse_loop(rem_tokens, %{state | with: state.with ++ with_bindings})

      :initially ->
        {forms, rem_tokens} = collect_forms_until_kw(rest)
        do_parse_loop(rem_tokens, %{state | initially: state.initially ++ forms})

      :finally ->
        {forms, rem_tokens} = collect_forms_until_kw(rest)
        do_parse_loop(rem_tokens, %{state | finally: state.finally ++ forms})

      kw when kw in [:while, :until, :always, :never, :thereis] ->
        case rest do
          [expr | rem_tokens] ->
            do_parse_loop(rem_tokens, %{state | body: state.body ++ [{kw, expr}]})

          [] ->
            raise ArgumentError, "loop #{kw} requires an expression"
        end

      kw when kw in [:collect, :collecting, :append, :appending, :nconc, :nconcing] ->
        norm_kw =
          case kw do
            k when k in [:collect, :collecting] -> :collect
            k when k in [:append, :appending] -> :append
            k when k in [:nconc, :nconcing] -> :nconc
          end

        {expr, into_var, rem_tokens} = parse_accumulation_expr(rest)
        do_parse_loop(rem_tokens, %{state | body: state.body ++ [{norm_kw, expr, into_var}]})

      kw
      when kw in [
             :sum,
             :summing,
             :count,
             :counting,
             :maximize,
             :maximizing,
             :minimize,
             :minimizing
           ] ->
        norm_kw =
          case kw do
            k when k in [:sum, :summing] -> :sum
            k when k in [:count, :counting] -> :count
            k when k in [:maximize, :maximizing] -> :maximize
            k when k in [:minimize, :minimizing] -> :minimize
          end

        {expr, into_var, rem_tokens} = parse_accumulation_expr(rest)
        do_parse_loop(rem_tokens, %{state | body: state.body ++ [{norm_kw, expr, into_var}]})

      kw when kw in [:do, :doing] ->
        {forms, rem_tokens} = collect_forms_until_kw(rest)
        do_parse_loop(rem_tokens, %{state | body: state.body ++ [{:do, forms}]})

      :return ->
        case rest do
          [expr | rem_tokens] ->
            do_parse_loop(rem_tokens, %{state | body: state.body ++ [{:return, expr}]})

          [] ->
            raise ArgumentError, "loop return requires an expression"
        end

      kw when kw in [:when, :if] ->
        {clause, rem_tokens} = parse_conditional(:when, rest)
        do_parse_loop(rem_tokens, %{state | body: state.body ++ [clause]})

      :unless ->
        {clause, rem_tokens} = parse_conditional(:unless, rest)
        do_parse_loop(rem_tokens, %{state | body: state.body ++ [clause]})

      _other ->
        # Treat non-keyword expressions as do clauses
        do_parse_loop(rest, %{state | body: state.body ++ [{:do, [node]}]})
    end
  end

  # with var [= val] [and with ...]
  defp parse_with_clause([var_node | rest]) do
    {val_node, rem_tokens} =
      case rest do
        [eq_node, val | next_rem] ->
          if kw_name(eq_node) in [:=, :=] do
            {val, next_rem}
          else
            {lit_node(nil), rest}
          end

        _ ->
          {lit_node(nil), rest}
      end

    binding = {var_node, val_node}

    case rem_tokens do
      [and_node, with_node | after_and] ->
        if kw_name(and_node) == :and and kw_name(with_node) == :with do
          {more_bindings, final_rem} = parse_with_clause(after_and)
          {[binding | more_bindings], final_rem}
        else
          {[binding], rem_tokens}
        end

      [and_node | after_and] ->
        if kw_name(and_node) == :and do
          {more_bindings, final_rem} = parse_with_clause(after_and)
          {[binding | more_bindings], final_rem}
        else
          {[binding], rem_tokens}
        end

      _ ->
        {[binding], rem_tokens}
    end
  end

  defp parse_with_clause([]), do: {[], []}

  # Parse for/as clauses
  defp parse_for_clause([var_node | rest]) do
    case rest do
      [kw_node | after_kw] ->
        case kw_name(kw_node) do
          k when k in [:=, :=] ->
            case after_kw do
              [init_expr, then_node, step_expr | rem_tokens] ->
                if kw_name(then_node) == :then do
                  {{:equals_then, var_node, init_expr, step_expr}, rem_tokens}
                else
                  {{:equals_always, var_node, init_expr}, [then_node, step_expr | rem_tokens]}
                end

              [init_expr | rem_tokens] ->
                {{:equals_always, var_node, init_expr}, rem_tokens}

              [] ->
                raise ArgumentError, "loop for = requires an expression"
            end

          :in ->
            case after_kw do
              [list_expr, by_node, step_fn | rem_tokens] ->
                if kw_name(by_node) == :by do
                  {{:in, var_node, list_expr, step_fn}, rem_tokens}
                else
                  {{:in, var_node, list_expr, nil}, [by_node, step_fn | rem_tokens]}
                end

              [list_expr | rem_tokens] ->
                {{:in, var_node, list_expr, nil}, rem_tokens}

              [] ->
                raise ArgumentError, "loop for in requires a list expression"
            end

          :on ->
            case after_kw do
              [list_expr, by_node, step_fn | rem_tokens] ->
                if kw_name(by_node) == :by do
                  {{:on, var_node, list_expr, step_fn}, rem_tokens}
                else
                  {{:on, var_node, list_expr, nil}, [by_node, step_fn | rem_tokens]}
                end

              [list_expr | rem_tokens] ->
                {{:on, var_node, list_expr, nil}, rem_tokens}

              [] ->
                raise ArgumentError, "loop for on requires a list expression"
            end

          :across ->
            case after_kw do
              [vec_expr | rem_tokens] ->
                {{:across, var_node, vec_expr}, rem_tokens}

              [] ->
                raise ArgumentError, "loop for across requires a vector expression"
            end

          range_kw
          when range_kw in [
                 :from,
                 :upfrom,
                 :downfrom,
                 :to,
                 :upto,
                 :downto,
                 :below,
                 :above
               ] ->
            parse_range_clause(var_node, rest)

          _ ->
            raise ArgumentError, "Unknown loop for subclause: #{inspect(kw_node)}"
        end

      [] ->
        raise ArgumentError, "Incomplete loop for clause"
    end
  end

  defp parse_range_clause(var_node, tokens) do
    # Default values
    opts = %{
      start: nil,
      limit_type: nil,
      limit: nil,
      step: int_node(1),
      dir: :up
    }

    {parsed_opts, rem_tokens} = do_parse_range(tokens, opts)

    dir =
      cond do
        parsed_opts.limit_type in [:downto, :above] -> :down
        parsed_opts.dir == :down -> :down
        true -> :up
      end

    start_expr =
      parsed_opts.start ||
        case dir do
          :up -> int_node(0)
          :down -> int_node(0)
        end

    clause =
      {:range, var_node, start_expr, parsed_opts.limit_type, parsed_opts.limit, parsed_opts.step,
       dir}

    {clause, rem_tokens}
  end

  defp do_parse_range([], opts), do: {opts, []}

  defp do_parse_range([kw_node | rest] = tokens, opts) do
    case kw_name(kw_node) do
      kw when kw in [:from, :upfrom] ->
        [val | rem_tokens] = rest
        do_parse_range(rem_tokens, %{opts | start: val, dir: :up})

      :downfrom ->
        [val | rem_tokens] = rest
        do_parse_range(rem_tokens, %{opts | start: val, dir: :down})

      kw when kw in [:to, :upto, :downto, :below, :above] ->
        [val | rem_tokens] = rest
        do_parse_range(rem_tokens, %{opts | limit_type: kw, limit: val})

      :by ->
        [val | rem_tokens] = rest
        do_parse_range(rem_tokens, %{opts | step: val})

      _ ->
        {opts, tokens}
    end
  end

  # Parse accumulation expression and [into var] [of-type type]
  defp parse_accumulation_expr([expr | rest]) do
    do_parse_accum_modifiers(rest, expr, nil, nil)
  end

  defp parse_accumulation_expr([]) do
    raise ArgumentError, "Missing expression in accumulation clause"
  end

  defp do_parse_accum_modifiers([kw_node, val_node | rem], expr, into_var, type) do
    case kw_name(kw_node) do
      :into ->
        do_parse_accum_modifiers(rem, expr, val_node, type)

      kw when kw in [:of_type, :"of-type"] ->
        do_parse_accum_modifiers(rem, expr, into_var, val_node)

      _ ->
        {expr, into_var, [kw_node, val_node | rem]}
    end
  end

  defp do_parse_accum_modifiers(rest, expr, into_var, _type) do
    {expr, into_var, rest}
  end

  # Parse conditional clauses (when / if / unless)
  defp parse_conditional(type, [test_expr | rest]) do
    {then_subclauses, rem_tokens1} = parse_subclause_group(rest)

    {else_subclauses, rem_tokens2} =
      case rem_tokens1 do
        [else_node | after_else] ->
          if kw_name(else_node) == :else do
            parse_subclause_group(after_else)
          else
            {[], rem_tokens1}
          end

        _ ->
          {[], rem_tokens1}
      end

    rem_tokens3 =
      case rem_tokens2 do
        [end_node | after_end] ->
          if kw_name(end_node) == :end do
            after_end
          else
            rem_tokens2
          end

        _ ->
          rem_tokens2
      end

    clause = {:conditional, type, test_expr, then_subclauses, else_subclauses}
    {clause, rem_tokens3}
  end

  defp parse_subclause_group(tokens) do
    # Parse a single clause or clauses connected by 'and'
    {first_clause, rem_tokens} = parse_single_body_clause(tokens)

    case rem_tokens do
      [and_node | after_and] ->
        if kw_name(and_node) == :and do
          {more_clauses, final_rem} = parse_subclause_group(after_and)
          {[first_clause | more_clauses], final_rem}
        else
          {[first_clause], rem_tokens}
        end

      _ ->
        {[first_clause], rem_tokens}
    end
  end

  defp parse_single_body_clause([node | rest]) do
    case kw_name(node) do
      kw when kw in [:when, :if] ->
        parse_conditional(:when, rest)

      :unless ->
        parse_conditional(:unless, rest)

      kw when kw in [:while, :until, :always, :never, :thereis] ->
        case rest do
          [expr | rem_tokens] ->
            {{kw, expr}, rem_tokens}

          [] ->
            raise ArgumentError, "loop #{kw} requires an expression"
        end

      kw when kw in [:collect, :collecting, :append, :appending, :nconc, :nconcing] ->
        norm_kw =
          case kw do
            k when k in [:collect, :collecting] -> :collect
            k when k in [:append, :appending] -> :append
            k when k in [:nconc, :nconcing] -> :nconc
          end

        {expr, into_var, rem_tokens} = parse_accumulation_expr(rest)
        {{norm_kw, expr, into_var}, rem_tokens}

      kw
      when kw in [
             :sum,
             :summing,
             :count,
             :counting,
             :maximize,
             :maximizing,
             :minimize,
             :minimizing
           ] ->
        norm_kw =
          case kw do
            k when k in [:sum, :summing] -> :sum
            k when k in [:count, :counting] -> :count
            k when k in [:maximize, :maximizing] -> :maximize
            k when k in [:minimize, :minimizing] -> :minimize
          end

        {expr, into_var, rem_tokens} = parse_accumulation_expr(rest)
        {{norm_kw, expr, into_var}, rem_tokens}

      kw when kw in [:do, :doing] ->
        {forms, rem_tokens} = collect_forms_until_kw(rest)
        {{:do, forms}, rem_tokens}

      :return ->
        [expr | rem_tokens] = rest
        {{:return, expr}, rem_tokens}

      _ ->
        {{:do, [node]}, rest}
    end
  end

  defp collect_forms_until_kw(tokens) do
    do_collect_forms(tokens, [])
  end

  defp do_collect_forms([], acc), do: {Enum.reverse(acc), []}

  defp do_collect_forms([node | _] = tokens, acc) do
    if is_loop_boundary_kw?(node) do
      {Enum.reverse(acc), tokens}
    else
      [form | rest] = tokens
      do_collect_forms(rest, [form | acc])
    end
  end

  defp is_loop_boundary_kw?(node) do
    kw = kw_name(node)

    kw in [
      :for,
      :as,
      :repeat,
      :while,
      :until,
      :always,
      :never,
      :thereis,
      :collect,
      :collecting,
      :append,
      :appending,
      :nconc,
      :nconcing,
      :sum,
      :summing,
      :count,
      :counting,
      :maximize,
      :maximizing,
      :minimize,
      :minimizing,
      :do,
      :doing,
      :return,
      :with,
      :initially,
      :finally,
      :when,
      :if,
      :unless,
      :else,
      :end,
      :and
    ]
  end

  # --- AST construction ---

  defp build_ast(parsed) do
    # Determine accumulators and special termination values
    acc_info = analyze_accumulators(parsed.body)

    # Initialize loop variables and state
    {init_bindings, loop_params, loop_inits, step_updates, end_checks, var_bindings} =
      build_for_machinery(parsed.for)

    # with bindings
    with_bindings =
      Enum.map(parsed.with, fn {var_node, val_node} ->
        {:list, {1, 1}, [var_node, val_node]}
      end)

    # Initial accumulator bindings and loop arguments
    {acc_bindings, acc_params, acc_inits, final_acc_expr} = build_acc_machinery(acc_info)

    all_params = loop_params ++ acc_params
    all_inits = loop_inits ++ acc_inits

    # Loop body expressions
    loop_fn_name = symbol_node(:"__loop_fn_#{System.unique_integer([:positive, :monotonic])}")

    # Recursive call: (loop_fn <next_loop_vars> <next_acc_vars>)
    recur_call_builder = fn next_acc_vars ->
      args = step_updates ++ next_acc_vars
      {:list, {1, 1}, [loop_fn_name | args]}
    end

    # Process finally clauses
    final_with_finally =
      case parsed.finally do
        [] ->
          final_acc_expr

        finally_forms ->
          case final_acc_expr do
            {:lit, nil} ->
              {:list, {1, 1}, [symbol_node(:progn) | finally_forms]}

            _ ->
              {:list, {1, 1},
               [
                 symbol_node(:"let*"),
                 {:list, {1, 1},
                  [
                    {:list, {1, 1}, [symbol_node(:__final_res__), final_acc_expr]}
                  ]},
                 {:list, {1, 1},
                  [
                    symbol_node(:progn),
                    {:list, {1, 1}, [symbol_node(:progn) | finally_forms]},
                    symbol_node(:__final_res__)
                  ]}
               ]}
          end
      end

    # Code generation for loop body
    body_expr =
      build_body_steps(
        parsed.body,
        acc_info,
        recur_call_builder,
        var_bindings,
        all_params,
        final_with_finally
      )

    # Code generation for termination check: (if (or check1 check2 ...) final_result body_expr)
    full_loop_body =
      if end_checks == [] do
        body_expr
      else
        combined_end_check =
          case end_checks do
            [single] -> single
            multiple -> {:list, {1, 1}, [symbol_node(:or) | multiple]}
          end

        {:list, {1, 1}, [symbol_node(:if), combined_end_check, final_with_finally, body_expr]}
      end

    # labels syntax
    fn_def =
      {:list, {1, 1},
       [
         loop_fn_name,
         {:list, {1, 1}, all_params},
         full_loop_body
       ]}

    initial_call = {:list, {1, 1}, [loop_fn_name | all_inits]}

    labels_form =
      {:list, {1, 1},
       [
         symbol_node(:labels),
         {:list, {1, 1}, [fn_def]},
         initial_call
       ]}

    # If initially clause exists, wrap in progn
    top_body =
      case parsed.initially do
        [] ->
          labels_form

        init_forms ->
          {:list, {1, 1}, [symbol_node(:progn) | init_forms ++ [labels_form]]}
      end

    # Outermost let* (with bindings + initial bindings) and block nil
    all_top_bindings = with_bindings ++ init_bindings ++ acc_bindings

    let_form =
      if all_top_bindings == [] do
        top_body
      else
        {:list, {1, 1},
         [
           symbol_node(:"let*"),
           {:list, {1, 1}, all_top_bindings},
           top_body
         ]}
      end

    {:list, {1, 1}, [symbol_node(:block), lit_node(nil), let_form]}
  end

  # --- Accumulator analysis ---

  defp analyze_accumulators(body_clauses) do
    # Detect accumulator types and variable names
    Enum.reduce(body_clauses, %{types: [], vars: %{}, special: nil}, fn clause, acc ->
      case clause do
        {kw, _expr, into_var}
        when kw in [:collect, :append, :nconc, :sum, :count, :maximize, :minimize] ->
          var_name = into_var || :__default_acc__
          %{acc | types: Enum.uniq([kw | acc.types]), vars: Map.put(acc.vars, var_name, kw)}

        {:conditional, _type, _test, then_clauses, else_clauses} ->
          sub = analyze_accumulators(then_clauses ++ else_clauses)

          %{
            acc
            | types: Enum.uniq(acc.types ++ sub.types),
              vars: Map.merge(acc.vars, sub.vars),
              special: acc.special || sub.special
          }

        {:always, _} ->
          %{acc | special: :always}

        {:never, _} ->
          %{acc | special: :never}

        {:thereis, _} ->
          %{acc | special: :thereis}

        _ ->
          acc
      end
    end)
  end

  defp build_acc_machinery(acc_info) do
    cond do
      acc_info.special == :always ->
        {[], [], [], symbol_node(:t)}

      acc_info.special == :never ->
        {[], [], [], symbol_node(:t)}

      acc_info.special == :thereis ->
        {[], [], [], lit_node(nil)}

      map_size(acc_info.vars) > 0 ->
        vars_list = Map.to_list(acc_info.vars)

        bindings =
          Enum.map(vars_list, fn {var_name, kw} ->
            init_val =
              case kw do
                k when k in [:collect, :append, :nconc] -> {:quoted, {1, 1}, []}
                k when k in [:sum, :count] -> int_node(0)
                _ -> lit_node(nil)
              end

            var_node = if is_atom(var_name), do: symbol_node(var_name), else: var_name
            {:list, {1, 1}, [var_node, init_val]}
          end)

        params =
          Enum.map(vars_list, fn {var_name, _} ->
            if is_atom(var_name), do: symbol_node(var_name), else: var_name
          end)

        inits =
          Enum.map(vars_list, fn {var_name, _} ->
            if is_atom(var_name), do: symbol_node(var_name), else: var_name
          end)

        # Return value
        default_var =
          if Map.has_key?(acc_info.vars, :__default_acc__) do
            symbol_node(:__default_acc__)
          else
            lit_node(nil)
          end

        {bindings, params, inits, default_var}

      true ->
        {[], [], [], lit_node(nil)}
    end
  end

  # --- Building machinery for for-clauses ---

  defp build_for_machinery(for_clauses) do
    # Generate initialization, parameters, step updates, and termination checks for each for-clause
    Enum.reduce(
      for_clauses,
      {[], [], [], [], [], []},
      fn clause, {inits_acc, params_acc, inits_val_acc, steps_acc, checks_acc, bindings_acc} ->
        case clause do
          {:range, var_node, start_expr, limit_type, limit_expr, step_expr, dir} ->
            var_sym = symbol_node(LispBeam.extract_symbol_name(var_node))

            # Termination check
            check =
              if limit_expr do
                op =
                  case {dir, limit_type} do
                    {:up, :below} -> :>=
                    {:up, _} -> :>
                    {:down, :above} -> :<=
                    {:down, _} -> :<
                  end

                {:list, {1, 1}, [symbol_node(op), var_sym, limit_expr]}
              else
                nil
              end

            # Step update
            step_op = if dir == :up, do: :+, else: :-
            next_val = {:list, {1, 1}, [symbol_node(step_op), var_sym, step_expr]}

            checks = if check, do: checks_acc ++ [check], else: checks_acc

            {
              inits_acc ++ [{:list, {1, 1}, [var_sym, start_expr]}],
              params_acc ++ [var_sym],
              inits_val_acc ++ [var_sym],
              steps_acc ++ [next_val],
              checks,
              bindings_acc
            }

          {:in, var_node, list_expr, step_fn} ->
            list_sym = symbol_node(:"__list_#{System.unique_integer([:positive, :monotonic])}")
            var_sym = symbol_node(LispBeam.extract_symbol_name(var_node))

            # Termination check: (null list_sym)
            check = {:list, {1, 1}, [symbol_node(:null), list_sym]}

            next_list =
              if step_fn do
                {:list, {1, 1}, [symbol_node(:funcall), step_fn, list_sym]}
              else
                {:list, {1, 1}, [symbol_node(:cdr), list_sym]}
              end

            # var binding in each iteration: (car list_sym)
            var_binding = {var_sym, {:list, {1, 1}, [symbol_node(:car), list_sym]}}

            {
              inits_acc ++ [{:list, {1, 1}, [list_sym, list_expr]}],
              params_acc ++ [list_sym],
              inits_val_acc ++ [list_sym],
              steps_acc ++ [next_list],
              checks_acc ++ [check],
              bindings_acc ++ [var_binding]
            }

          {:on, var_node, list_expr, step_fn} ->
            case var_node do
              {:list, _, [head_node, {:id, _, ["."]}, tail_node]} ->
                sublist_sym =
                  symbol_node(:"__on_#{System.unique_integer([:positive, :monotonic])}")

                check = {:list, {1, 1}, [symbol_node(:null), sublist_sym]}

                next_list =
                  if step_fn do
                    {:list, {1, 1}, [symbol_node(:funcall), step_fn, sublist_sym]}
                  else
                    {:list, {1, 1}, [symbol_node(:cdr), sublist_sym]}
                  end

                head_sym = symbol_node(LispBeam.extract_symbol_name(head_node))
                tail_sym = symbol_node(LispBeam.extract_symbol_name(tail_node))

                head_binding = {head_sym, {:list, {1, 1}, [symbol_node(:car), sublist_sym]}}
                tail_binding = {tail_sym, {:list, {1, 1}, [symbol_node(:cdr), sublist_sym]}}

                {
                  inits_acc ++ [{:list, {1, 1}, [sublist_sym, list_expr]}],
                  params_acc ++ [sublist_sym],
                  inits_val_acc ++ [sublist_sym],
                  steps_acc ++ [next_list],
                  checks_acc ++ [check],
                  bindings_acc ++ [head_binding, tail_binding]
                }

              _ ->
                var_sym = symbol_node(LispBeam.extract_symbol_name(var_node))
                check = {:list, {1, 1}, [symbol_node(:null), var_sym]}

                next_list =
                  if step_fn do
                    {:list, {1, 1}, [symbol_node(:funcall), step_fn, var_sym]}
                  else
                    {:list, {1, 1}, [symbol_node(:cdr), var_sym]}
                  end

                {
                  inits_acc ++ [{:list, {1, 1}, [var_sym, list_expr]}],
                  params_acc ++ [var_sym],
                  inits_val_acc ++ [var_sym],
                  steps_acc ++ [next_list],
                  checks_acc ++ [check],
                  bindings_acc
                }
            end

          {:across, var_node, vec_expr} ->
            vec_sym = symbol_node(:"__vec_#{System.unique_integer([:positive, :monotonic])}")
            idx_sym = symbol_node(:"__idx_#{System.unique_integer([:positive, :monotonic])}")
            var_sym = symbol_node(LispBeam.extract_symbol_name(var_node))

            check =
              {:list, {1, 1},
               [
                 symbol_node(:>=),
                 idx_sym,
                 {:list, {1, 1}, [symbol_node(:length), vec_sym]}
               ]}

            next_idx = {:list, {1, 1}, [symbol_node(:+), idx_sym, int_node(1)]}

            var_binding =
              {var_sym, {:list, {1, 1}, [symbol_node(:aref), vec_sym, idx_sym]}}

            {
              inits_acc ++
                [
                  {:list, {1, 1}, [vec_sym, vec_expr]},
                  {:list, {1, 1}, [idx_sym, int_node(0)]}
                ],
              params_acc ++ [vec_sym, idx_sym],
              inits_val_acc ++ [vec_sym, idx_sym],
              steps_acc ++ [vec_sym, next_idx],
              checks_acc ++ [check],
              bindings_acc ++ [var_binding]
            }

          {:equals_then, var_node, init_expr, step_expr} ->
            var_sym = symbol_node(LispBeam.extract_symbol_name(var_node))

            {
              inits_acc ++ [{:list, {1, 1}, [var_sym, init_expr]}],
              params_acc ++ [var_sym],
              inits_val_acc ++ [var_sym],
              steps_acc ++ [step_expr],
              checks_acc,
              bindings_acc
            }

          {:equals_always, var_node, expr} ->
            var_sym = symbol_node(LispBeam.extract_symbol_name(var_node))
            var_binding = {var_sym, expr}

            {
              inits_acc,
              params_acc,
              inits_val_acc,
              steps_acc,
              checks_acc,
              bindings_acc ++ [var_binding]
            }

          {:repeat, count_expr} ->
            cnt_sym = symbol_node(:"__cnt_#{System.unique_integer([:positive, :monotonic])}")
            check = {:list, {1, 1}, [symbol_node(:<=), cnt_sym, int_node(0)]}
            next_cnt = {:list, {1, 1}, [symbol_node(:-), cnt_sym, int_node(1)]}

            {
              inits_acc ++ [{:list, {1, 1}, [cnt_sym, count_expr]}],
              params_acc ++ [cnt_sym],
              inits_val_acc ++ [cnt_sym],
              steps_acc ++ [next_cnt],
              checks_acc ++ [check],
              bindings_acc
            }
        end
      end
    )
  end

  # --- Code generation for loop body steps ---

  defp build_body_steps(
         body_clauses,
         acc_info,
         recur_call_builder,
         var_bindings,
         all_params,
         final_val
       ) do
    # Wrap var_bindings (e.g. binding x for x in list) with let*
    inner_expr =
      do_build_body_steps(body_clauses, acc_info, recur_call_builder, all_params, final_val)

    if var_bindings == [] do
      inner_expr
    else
      bindings_list =
        Enum.map(var_bindings, fn {var_sym, val_expr} ->
          {:list, {1, 1}, [var_sym, val_expr]}
        end)

      {:list, {1, 1},
       [
         symbol_node(:"let*"),
         {:list, {1, 1}, bindings_list},
         inner_expr
       ]}
    end
  end

  defp do_build_body_steps([], acc_info, recur_call_builder, _all_params, _final_val) do
    # Default recursive call (carrying over accumulator variables as is)
    acc_vars =
      Enum.map(Map.keys(acc_info.vars), fn var_name ->
        if is_atom(var_name), do: symbol_node(var_name), else: var_name
      end)

    recur_call_builder.(acc_vars)
  end

  defp do_build_body_steps([clause | rest], acc_info, recur_call_builder, all_params, final_val) do
    case clause do
      {:while, test_expr} ->
        rest_expr =
          do_build_body_steps(rest, acc_info, recur_call_builder, all_params, final_val)

        {:list, {1, 1}, [symbol_node(:if), test_expr, rest_expr, final_val]}

      {:until, test_expr} ->
        rest_expr =
          do_build_body_steps(rest, acc_info, recur_call_builder, all_params, final_val)

        {:list, {1, 1}, [symbol_node(:if), test_expr, final_val, rest_expr]}

      {:always, test_expr} ->
        rest_expr =
          do_build_body_steps(rest, acc_info, recur_call_builder, all_params, final_val)

        {:list, {1, 1},
         [
           symbol_node(:if),
           test_expr,
           rest_expr,
           {:list, {1, 1}, [symbol_node(:return_from), lit_node(nil), lit_node(nil)]}
         ]}

      {:never, test_expr} ->
        rest_expr =
          do_build_body_steps(rest, acc_info, recur_call_builder, all_params, final_val)

        {:list, {1, 1},
         [
           symbol_node(:if),
           test_expr,
           {:list, {1, 1}, [symbol_node(:return_from), lit_node(nil), lit_node(nil)]},
           rest_expr
         ]}

      {:thereis, test_expr} ->
        temp_sym = symbol_node(:"__val_#{System.unique_integer([:positive, :monotonic])}")

        rest_expr =
          do_build_body_steps(rest, acc_info, recur_call_builder, all_params, final_val)

        {:list, {1, 1},
         [
           symbol_node(:"let*"),
           {:list, {1, 1}, [{:list, {1, 1}, [temp_sym, test_expr]}]},
           {:list, {1, 1},
            [
              symbol_node(:if),
              temp_sym,
              {:list, {1, 1}, [symbol_node(:return_from), lit_node(nil), temp_sym]},
              rest_expr
            ]}
         ]}

      {:return, expr} ->
        {:list, {1, 1}, [symbol_node(:return_from), lit_node(nil), expr]}

      {:do, forms} ->
        rest_expr =
          do_build_body_steps(rest, acc_info, recur_call_builder, all_params, final_val)

        case forms do
          [] -> rest_expr
          _ -> {:list, {1, 1}, [symbol_node(:progn) | forms ++ [rest_expr]]}
        end

      {accum_kw, expr, into_var}
      when accum_kw in [
             :collect,
             :append,
             :nconc,
             :sum,
             :count,
             :maximize,
             :minimize
           ] ->
        acc_var_name = into_var || :__default_acc__
        acc_sym = if is_atom(acc_var_name), do: symbol_node(acc_var_name), else: acc_var_name
        next_acc_val = build_acc_step(accum_kw, acc_sym, expr)

        # Wrap remaining steps with new acc_sym
        rest_expr =
          do_build_body_steps(rest, acc_info, recur_call_builder, all_params, final_val)

        {:list, {1, 1},
         [
           symbol_node(:"let*"),
           {:list, {1, 1}, [{:list, {1, 1}, [acc_sym, next_acc_val]}]},
           rest_expr
         ]}

      {:conditional, type, test_expr, then_clauses, else_clauses} ->
        # rest_expr after executing each of then and else branches
        then_branch =
          do_build_body_steps(
            then_clauses ++ rest,
            acc_info,
            recur_call_builder,
            all_params,
            final_val
          )

        else_branch =
          case else_clauses do
            [] ->
              do_build_body_steps(rest, acc_info, recur_call_builder, all_params, final_val)

            _ ->
              do_build_body_steps(
                else_clauses ++ rest,
                acc_info,
                recur_call_builder,
                all_params,
                final_val
              )
          end

        case type do
          :when ->
            {:list, {1, 1}, [symbol_node(:if), test_expr, then_branch, else_branch]}

          :unless ->
            {:list, {1, 1}, [symbol_node(:if), test_expr, else_branch, then_branch]}
        end
    end
  end

  defp build_acc_step(:sum, acc_sym, expr) do
    {:list, {1, 1}, [symbol_node(:+), acc_sym, expr]}
  end

  defp build_acc_step(:count, acc_sym, expr) do
    {:list, {1, 1},
     [
       symbol_node(:if),
       expr,
       {:list, {1, 1}, [symbol_node(:+), acc_sym, int_node(1)]},
       acc_sym
     ]}
  end

  defp build_acc_step(:collect, acc_sym, expr) do
    {:list, {1, 1}, [symbol_node(:append), acc_sym, {:list, {1, 1}, [symbol_node(:list), expr]}]}
  end

  defp build_acc_step(:append, acc_sym, expr) do
    {:list, {1, 1}, [symbol_node(:append), acc_sym, expr]}
  end

  defp build_acc_step(:nconc, acc_sym, expr) do
    {:list, {1, 1}, [symbol_node(:append), acc_sym, expr]}
  end

  defp build_acc_step(:maximize, acc_sym, expr) do
    temp_sym = symbol_node(:"__m_#{System.unique_integer([:positive, :monotonic])}")

    {:list, {1, 1},
     [
       symbol_node(:"let*"),
       {:list, {1, 1}, [{:list, {1, 1}, [temp_sym, expr]}]},
       {:list, {1, 1},
        [
          symbol_node(:if),
          {:list, {1, 1},
           [
             symbol_node(:or),
             {:list, {1, 1}, [symbol_node(:null), acc_sym]},
             {:list, {1, 1}, [symbol_node(:>), temp_sym, acc_sym]}
           ]},
          temp_sym,
          acc_sym
        ]}
     ]}
  end

  defp build_acc_step(:minimize, acc_sym, expr) do
    temp_sym = symbol_node(:"__m_#{System.unique_integer([:positive, :monotonic])}")

    {:list, {1, 1},
     [
       symbol_node(:"let*"),
       {:list, {1, 1}, [{:list, {1, 1}, [temp_sym, expr]}]},
       {:list, {1, 1},
        [
          symbol_node(:if),
          {:list, {1, 1},
           [
             symbol_node(:or),
             {:list, {1, 1}, [symbol_node(:null), acc_sym]},
             {:list, {1, 1}, [symbol_node(:<), temp_sym, acc_sym]}
           ]},
          temp_sym,
          acc_sym
        ]}
     ]}
  end
end
