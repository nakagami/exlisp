defmodule ExLisp.Macro do
  @moduledoc """
  Common Lisp-style macro expansion system.
  Provides destructuring-bind, backquote expansion, and macroexpand.
  """

  @doc """
  Generates a macro function lambda AST from defmacro parameters and body.
  The generated AST has the form `(lambda (__macro_args__ __macro_whole__) (let* (...) body...))`.
  """
  def build_macro_lambda(params_node, body_nodes) do
    raw_args_sym = :__macro_args__
    raw_whole_sym = :__macro_whole__

    {bindings, _} = build_bindings(params_node, raw_args_sym, raw_whole_sym)

    body_list =
      case body_nodes do
        [] -> [{:lit, nil}]
        _ -> body_nodes
      end

    {:list, 1,
     [
       {:id, 1, ["lambda"]},
       {:list, 1,
        [
          {:id, 1, [Atom.to_string(raw_args_sym)]},
          {:id, 1, [Atom.to_string(raw_whole_sym)]}
        ]},
       {:list, 1,
        [
          {:id, 1, ["let*"]},
          {:list, 1, bindings}
          | body_list
        ]}
     ]}
  end

  @doc """
  Constructs a list of `let*` binding ASTs from a macro's lambda list.
  """
  def build_bindings(params_node, args_var, whole_var) do
    elems = extract_elements(params_node)
    do_build_bindings(elems, args_var, whole_var, 0, :req, elems, [])
  end

  defp extract_elements({:list, _pos, elems}), do: elems
  defp extract_elements({:quoted, _pos, elems}), do: elems
  defp extract_elements(elems) when is_list(elems), do: elems
  defp extract_elements(_), do: []

  defp do_build_bindings([], _curr_args_var, _whole_var, _step, _state, _all_elems, acc) do
    {Enum.reverse(acc), nil}
  end

  defp do_build_bindings([elem | rest], curr_args_var, whole_var, step, state, all_elems, acc) do
    sym = param_symbol(elem)

    case sym do
      :"&whole" ->
        [whole_param | remaining] = rest
        binding = {:list, 1, [to_var_ast(whole_param), to_var_ast(whole_var)]}

        do_build_bindings(remaining, curr_args_var, whole_var, step, state, all_elems, [
          binding | acc
        ])

      :"&optional" ->
        do_build_bindings(rest, curr_args_var, whole_var, step, :opt, all_elems, acc)

      s when s in [:"&rest", :"&body"] ->
        [rest_param | remaining] = rest

        case rest_param do
          {:list, _, _} ->
            {nested_bindings, _} = build_bindings(rest_param, curr_args_var, whole_var)

            do_build_bindings(
              remaining,
              curr_args_var,
              whole_var,
              step,
              :after_rest,
              all_elems,
              Enum.reverse(nested_bindings) ++ acc
            )

          _ ->
            binding = {:list, 1, [to_var_ast(rest_param), to_var_ast(curr_args_var)]}

            do_build_bindings(remaining, curr_args_var, whole_var, step, :after_rest, all_elems, [
              binding | acc
            ])
        end

      :"&key" ->
        {_tag, allowed_keys, allow_other?} = parse_allowed_keys(all_elems)

        validation_check =
          {:list, 1,
           [
             {:id, 1, ["exlisp_check_key_args"]},
             to_var_ast(curr_args_var),
             {:quoted, 1, Enum.map(allowed_keys, &{:lit, &1})},
             {:lit, if(allow_other?, do: :t, else: nil)}
           ]}

        dummy_var = unique_macro_var("check_keys")
        check_binding = {:list, 1, [to_var_ast(dummy_var), validation_check]}

        do_build_bindings(rest, curr_args_var, whole_var, step, :key, all_elems, [
          check_binding | acc
        ])

      :"&allow_other_keys" ->
        do_build_bindings(rest, curr_args_var, whole_var, step, state, all_elems, acc)

      :"&aux" ->
        do_build_bindings(rest, curr_args_var, whole_var, step, :aux, all_elems, acc)

      :"&environment" ->
        [_env_param | remaining] = rest
        do_build_bindings(remaining, curr_args_var, whole_var, step, state, all_elems, acc)

      _ ->
        case state do
          :req ->
            next_args_var = unique_macro_var("args")

            case elem do
              {:list, _, _} ->
                sub_var = unique_macro_var("sub")
                sub_binding = {:list, 1, [to_var_ast(sub_var), car_ast(curr_args_var)]}
                next_binding = {:list, 1, [to_var_ast(next_args_var), cdr_ast(curr_args_var)]}
                {nested_bindings, _} = build_bindings(elem, sub_var, whole_var)
                new_acc = [next_binding | Enum.reverse(nested_bindings)] ++ [sub_binding | acc]

                do_build_bindings(
                  rest,
                  next_args_var,
                  whole_var,
                  step + 1,
                  :req,
                  all_elems,
                  new_acc
                )

              _ ->
                val_expr =
                  {:list, 1,
                   [
                     {:id, 1, ["if"]},
                     to_var_ast(curr_args_var),
                     car_ast(curr_args_var),
                     {:list, 1, [{:id, 1, ["error"]}, {:lit, "Too few arguments"}]}
                   ]}

                val_binding = {:list, 1, [to_var_ast(elem), val_expr]}
                next_binding = {:list, 1, [to_var_ast(next_args_var), cdr_ast(curr_args_var)]}

                do_build_bindings(rest, next_args_var, whole_var, step + 1, :req, all_elems, [
                  next_binding,
                  val_binding | acc
                ])
            end

          :opt ->
            next_args_var = unique_macro_var("args")
            {opt_var, default_ast, supplied_p_var} = parse_opt_item(elem)

            opt_val =
              {:list, 1,
               [
                 {:id, 1, ["if"]},
                 to_var_ast(curr_args_var),
                 car_ast(curr_args_var),
                 default_ast
               ]}

            opt_binding = {:list, 1, [to_var_ast(opt_var), opt_val]}

            next_binding =
              {:list, 1,
               [
                 to_var_ast(next_args_var),
                 {:list, 1,
                  [
                    {:id, 1, ["if"]},
                    to_var_ast(curr_args_var),
                    cdr_ast(curr_args_var),
                    {:lit, nil}
                  ]}
               ]}

            acc_with_supplied =
              if supplied_p_var do
                supp_val =
                  {:list, 1,
                   [
                     {:id, 1, ["if"]},
                     to_var_ast(curr_args_var),
                     {:lit, :t},
                     {:lit, nil}
                   ]}

                [
                  {:list, 1, [to_var_ast(supplied_p_var), supp_val]},
                  next_binding,
                  opt_binding | acc
                ]
              else
                [next_binding, opt_binding | acc]
              end

            do_build_bindings(
              rest,
              next_args_var,
              whole_var,
              step + 1,
              :opt,
              all_elems,
              acc_with_supplied
            )

          :key ->
            {key_name, var_name, default_ast, supplied_p_var} = parse_key_item(elem)
            not_found_sym = unique_macro_var("not_found")

            getf_call =
              {:list, 1,
               [
                 {:id, 1, ["getf"]},
                 to_var_ast(curr_args_var),
                 {:lit, key_name},
                 {:list, 1, [{:id, 1, ["quote"]}, to_var_ast(not_found_sym)]}
               ]}

            tmp_var = unique_macro_var("k")
            tmp_binding = {:list, 1, [to_var_ast(tmp_var), getf_call]}

            key_val =
              {:list, 1,
               [
                 {:id, 1, ["if"]},
                 {:list, 1,
                  [
                    {:id, 1, ["eq"]},
                    to_var_ast(tmp_var),
                    {:list, 1, [{:id, 1, ["quote"]}, to_var_ast(not_found_sym)]}
                  ]},
                 default_ast,
                 to_var_ast(tmp_var)
               ]}

            key_binding = {:list, 1, [to_var_ast(var_name), key_val]}

            acc_with_key =
              if supplied_p_var do
                supp_val =
                  {:list, 1,
                   [
                     {:id, 1, ["if"]},
                     {:list, 1,
                      [
                        {:id, 1, ["eq"]},
                        to_var_ast(tmp_var),
                        {:list, 1, [{:id, 1, ["quote"]}, to_var_ast(not_found_sym)]}
                      ]},
                     {:lit, nil},
                     {:lit, :t}
                   ]}

                [
                  {:list, 1, [to_var_ast(supplied_p_var), supp_val]},
                  key_binding,
                  tmp_binding | acc
                ]
              else
                [key_binding, tmp_binding | acc]
              end

            do_build_bindings(
              rest,
              curr_args_var,
              whole_var,
              step + 1,
              :key,
              all_elems,
              acc_with_key
            )

          :aux ->
            {aux_var, init_ast} = parse_aux_item(elem)
            binding = {:list, 1, [to_var_ast(aux_var), init_ast]}

            do_build_bindings(rest, curr_args_var, whole_var, step + 1, :aux, all_elems, [
              binding | acc
            ])

          :after_rest ->
            do_build_bindings(rest, curr_args_var, whole_var, step, :after_rest, all_elems, acc)
        end
    end
  end

  defp parse_allowed_keys(elems) do
    key_idx = Enum.find_index(elems, fn elem -> param_symbol(elem) == :"&key" end)

    if key_idx != nil do
      key_elems = Enum.slice(elems, (key_idx + 1)..-1//1)
      allow_other? = Enum.any?(key_elems, fn e -> param_symbol(e) == :"&allow_other_keys" end)

      allowed_keys =
        key_elems
        |> Enum.take_while(fn e ->
          param_symbol(e) not in [:"&aux", :"&allow_other_keys", :"&environment"]
        end)
        |> Enum.map(fn e ->
          {key_name, _var, _def, _supp} = parse_key_item(e)
          key_name
        end)

      {:has_key, allowed_keys, allow_other?}
    else
      {:no_key, [], true}
    end
  end

  defp unique_macro_var(prefix) do
    id = System.unique_integer([:positive, :monotonic])
    :"__#{prefix}_#{id}"
  end

  defp car_ast(var_atom) do
    {:list, 1, [{:id, 1, ["car"]}, to_var_ast(var_atom)]}
  end

  defp cdr_ast(var_atom) do
    {:list, 1, [{:id, 1, ["cdr"]}, to_var_ast(var_atom)]}
  end

  defp to_var_ast({:id, _, _} = node), do: node
  defp to_var_ast(atom) when is_atom(atom), do: {:id, 1, [Atom.to_string(atom)]}
  defp to_var_ast(str) when is_binary(str), do: {:id, 1, [str]}
  defp to_var_ast(other), do: other

  defp param_symbol({:id, _pos, [name]}), do: String.downcase(name) |> String.to_atom()

  defp param_symbol(atom) when is_atom(atom),
    do: Atom.to_string(atom) |> String.downcase() |> String.to_atom()

  defp param_symbol(name) when is_binary(name), do: String.downcase(name) |> String.to_atom()
  defp param_symbol(_), do: nil

  defp parse_opt_item({:list, _pos, [var_node, default_node, supp_node | _]}) do
    {var_node, default_node, supp_node}
  end

  defp parse_opt_item({:list, _pos, [var_node, default_node]}) do
    {var_node, default_node, nil}
  end

  defp parse_opt_item({:list, _pos, [var_node]}) do
    {var_node, {:lit, nil}, nil}
  end

  defp parse_opt_item(var_node) do
    {var_node, {:lit, nil}, nil}
  end

  defp parse_key_item({:list, _pos, [key_spec, default_node, supp_node | _]}) do
    {key_name, var_node} = parse_key_spec(key_spec)
    {key_name, var_node, default_node, supp_node}
  end

  defp parse_key_item({:list, _pos, [key_spec, default_node]}) do
    {key_name, var_node} = parse_key_spec(key_spec)
    {key_name, var_node, default_node, nil}
  end

  defp parse_key_item({:list, _pos, [key_spec]}) do
    {key_name, var_node} = parse_key_spec(key_spec)
    {key_name, var_node, {:lit, nil}, nil}
  end

  defp parse_key_item(var_node) do
    {key_name, var_node} = parse_key_spec(var_node)
    {key_name, var_node, {:lit, nil}, nil}
  end

  defp parse_key_spec({:list, _pos, [k_node, var_node | _]}) do
    k_name = param_symbol(k_node)
    {k_name, var_node}
  end

  defp parse_key_spec(var_node) do
    sym = param_symbol(var_node)
    {sym, var_node}
  end

  defp parse_aux_item({:list, _pos, [var_node, init_node | _]}) do
    {var_node, init_node}
  end

  defp parse_aux_item({:list, _pos, [var_node]}) do
    {var_node, {:lit, nil}}
  end

  defp parse_aux_item(var_node) do
    {var_node, {:lit, nil}}
  end

  # =========================================================================
  # Backquote Expander
  # =========================================================================

  @doc """
  Transforms a backquote expression AST into an expanded AST using list / append / quote.
  Manages nested backquote depth to perform unquoting at the appropriate level.
  """
  def expand_backquote(ast, depth \\ 1) do
    case ast do
      {:comma, _line, inner} ->
        if depth == 1 do
          inner
        else
          {:list, 1,
           [
             {:id, 1, ["list"]},
             {:list, 1, [{:id, 1, ["quote"]}, {:id, 1, ["_cl_comma_"]}]},
             expand_backquote(inner, depth - 1)
           ]}
        end

      [:_cl_comma_, inner] ->
        if depth == 1 do
          lisp_data_to_ast(inner)
        else
          {:list, 1,
           [
             {:id, 1, ["list"]},
             {:list, 1, [{:id, 1, ["quote"]}, {:id, 1, ["_cl_comma_"]}]},
             expand_backquote(inner, depth - 1)
           ]}
        end

      {:comma_at, _line, inner} ->
        if depth == 1 do
          inner
        else
          {:list, 1,
           [
             {:id, 1, ["list"]},
             {:list, 1, [{:id, 1, ["quote"]}, {:id, 1, ["_cl_comma_at_"]}]},
             expand_backquote(inner, depth - 1)
           ]}
        end

      [:_cl_comma_at_, inner] ->
        if depth == 1 do
          lisp_data_to_ast(inner)
        else
          {:list, 1,
           [
             {:id, 1, ["list"]},
             {:list, 1, [{:id, 1, ["quote"]}, {:id, 1, ["_cl_comma_at_"]}]},
             expand_backquote(inner, depth - 1)
           ]}
        end

      {:backquote, line, inner} ->
        {:list, line,
         [
           {:id, line, ["list"]},
           {:list, line, [{:id, line, ["quote"]}, {:id, line, ["_cl_backquote_"]}]},
           expand_backquote(inner, depth + 1)
         ]}

      [:_cl_backquote_, inner] ->
        {:list, 1,
         [
           {:id, 1, ["list"]},
           {:list, 1, [{:id, 1, ["quote"]}, {:id, 1, ["_cl_backquote_"]}]},
           expand_backquote(inner, depth + 1)
         ]}

      {:list, line, elements} ->
        expand_backquote_list(elements, line, depth)

      {:dotted_list, line, elements, tail} ->
        {:list, line,
         [
           {:id, line, ["list*"]}
           | Enum.map(elements, &expand_backquote(&1, depth)) ++
               [expand_backquote(tail, depth)]
         ]}

      {:vector, line, elements} ->
        {:list, line,
         [
           {:id, line, ["vector"]}
           | Enum.map(elements, &expand_backquote(&1, depth))
         ]}

      {:quoted, line, elements} ->
        expand_backquote_list(elements, line, depth)

      {:id, line, parts} = id_node ->
        if length(parts) == 1 and hd(parts) in ["nil", "n.i.l"] do
          {:lit, nil}
        else
          {:list, line, [{:id, line, ["quote"]}, id_node]}
        end

      {:keyword, line, val} ->
        {:list, line, [{:id, line, ["quote"]}, {:keyword, line, val}]}

      {:lit, atom_val} when is_atom(atom_val) and not is_nil(atom_val) and atom_val != :t ->
        {:list, 1, [{:id, 1, ["quote"]}, {:lit, atom_val}]}

      {:lit, _} = lit_node ->
        lit_node

      atom when is_atom(atom) and not is_nil(atom) and atom != :t ->
        {:list, 1, [{:id, 1, ["quote"]}, {:id, 1, [Atom.to_string(atom)]}]}

      elements when is_list(elements) ->
        expand_backquote_list(elements, 1, depth)

      other ->
        other
    end
  end

  defp expand_backquote_list([], line, _depth) do
    {:list, line, [{:id, line, ["quote"]}, {:list, line, []}]}
  end

  defp expand_backquote_list(elements, line, depth) do
    has_splice =
      depth == 1 and
        Enum.any?(elements, fn
          {:comma_at, _, _} -> true
          [:_cl_comma_at_, _] -> true
          _ -> false
        end)

    if has_splice do
      chunks = chunk_backquote_elements(elements, line, depth)
      {:list, line, [{:id, line, ["append"]} | chunks]}
    else
      list_args =
        Enum.map(elements, fn elem ->
          case elem do
            {:comma, _, inner} when depth == 1 -> inner
            [:_cl_comma_, inner] when depth == 1 -> lisp_data_to_ast(inner, line)
            _ -> expand_backquote(elem, depth)
          end
        end)

      {:list, line, [{:id, line, ["list"]} | list_args]}
    end
  end

  defp chunk_backquote_elements(elements, line, depth) do
    Enum.reduce(elements, {[], []}, fn elem, {chunks_acc, current_group} ->
      case elem do
        {:comma_at, _, inner} when depth == 1 ->
          if current_group == [] do
            {[inner | chunks_acc], []}
          else
            list_node = {:list, line, [{:id, line, ["list"]} | Enum.reverse(current_group)]}
            {[inner, list_node | chunks_acc], []}
          end

        [:_cl_comma_at_, inner] when depth == 1 ->
          inner_ast = lisp_data_to_ast(inner, line)

          if current_group == [] do
            {[inner_ast | chunks_acc], []}
          else
            list_node = {:list, line, [{:id, line, ["list"]} | Enum.reverse(current_group)]}
            {[inner_ast, list_node | chunks_acc], []}
          end

        {:comma, _, inner} when depth == 1 ->
          {chunks_acc, [inner | current_group]}

        [:_cl_comma_, inner] when depth == 1 ->
          {chunks_acc, [lisp_data_to_ast(inner, line) | current_group]}

        other ->
          {chunks_acc, [expand_backquote(other, depth) | current_group]}
      end
    end)
    |> then(fn {chunks_acc, current_group} ->
      if current_group == [] do
        Enum.reverse(chunks_acc)
      else
        list_node = {:list, line, [{:id, line, ["list"]} | Enum.reverse(current_group)]}
        Enum.reverse([list_node | chunks_acc])
      end
    end)
  end

  # =========================================================================
  # Interconversion between AST and Lisp Data
  # =========================================================================

  @doc """
  Converts an AST node to Common Lisp S-expression data (atom, list, lit).
  """
  def ast_to_lisp_data(ast) do
    case ast do
      {:keyword, _pos, val} ->
        val

      {:lit, val} ->
        val

      {:id, _pos, [name]} ->
        LispBeam.extract_symbol_name(name)

      {:id, _pos, parts} when is_list(parts) ->
        Enum.join(parts, ".") |> String.downcase() |> String.to_atom()

      {:list, _pos, elements} ->
        Enum.map(elements, &ast_to_lisp_data/1)

      {:dotted_list, _pos, elements, tail} ->
        Enum.reduce(Enum.reverse(elements), ast_to_lisp_data(tail), fn el, acc ->
          [ast_to_lisp_data(el) | acc]
        end)

      {:quoted, _pos, elements} ->
        Enum.map(elements, &ast_to_lisp_data/1)

      {:backquote, _pos, inner} ->
        [:_cl_backquote_, ast_to_lisp_data(inner)]

      {:comma, _pos, inner} ->
        [:_cl_comma_, ast_to_lisp_data(inner)]

      {:comma_at, _pos, inner} ->
        [:_cl_comma_at_, ast_to_lisp_data(inner)]

      elements when is_list(elements) ->
        {items, tail} = decompose_list(elements, [])
        l_items = Enum.map(items, &ast_to_lisp_data/1)

        if tail == nil or tail == [] do
          l_items
        else
          Enum.reduce(Enum.reverse(l_items), ast_to_lisp_data(tail), fn el, acc -> [el | acc] end)
        end

      other ->
        other
    end
  end

  @doc """
  Converts Common Lisp S-expression data (atom, list, lit) to an AST node.
  """
  def lisp_data_to_ast(data, line \\ 1) do
    case data do
      {:keyword, _, _} = node ->
        node

      {:lit, _} = node ->
        node

      {:id, _, _} = node ->
        node

      {:list, _, _} = node ->
        node

      {:dotted_list, _, _, _} = node ->
        node

      {:quoted, _, _} = node ->
        node

      {:vector, _, _} = node ->
        node

      {:backquote, _, _} = node ->
        node

      {:comma, _, _} = node ->
        node

      {:comma_at, _, _} = node ->
        node

      nil ->
        {:lit, nil}

      :t ->
        {:lit, :t}

      val when is_integer(val) or is_float(val) or is_binary(val) ->
        {:lit, val}

      val when is_boolean(val) ->
        if val, do: {:lit, :t}, else: {:lit, nil}

      %ExLisp.Symbol{name: name} ->
        {:id, line, [String.downcase(name)]}

      [:_cl_backquote_, inner] ->
        {:backquote, line, lisp_data_to_ast(inner, line)}

      [:_cl_comma_, inner] ->
        {:comma, line, lisp_data_to_ast(inner, line)}

      [:_cl_comma_at_, inner] ->
        {:comma_at, line, lisp_data_to_ast(inner, line)}

      elements when is_list(elements) ->
        lisp_list_to_ast(elements, line)

      sym when is_atom(sym) ->
        str = Atom.to_string(sym)
        {:id, line, [str]}

      other ->
        {:lit, other}
    end
  end

  defp lisp_list_to_ast(list, line) do
    {items, tail} = decompose_list(list, [])
    ast_items = Enum.map(items, &lisp_data_to_ast(&1, line))

    if tail == nil or tail == [] do
      {:list, line, ast_items}
    else
      {:dotted_list, line, ast_items, lisp_data_to_ast(tail, line)}
    end
  end

  defp decompose_list([], acc), do: {Enum.reverse(acc), nil}
  defp decompose_list([h | t], acc) when is_list(t), do: decompose_list(t, [h | acc])
  defp decompose_list([h | nil], acc), do: {Enum.reverse([h | acc]), nil}
  defp decompose_list([h | t], acc), do: {Enum.reverse([h | acc]), t}
end
