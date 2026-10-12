defmodule ExLisp.Evaluator do
  @moduledoc """
  Direct AST interpreter/evaluator for ExLisp.
  Evaluates Lisp AST expressions without compiling temporary BEAM modules,
  providing orders-of-magnitude faster execution for interactive and dynamic forms.
  """

  alias ExLisp.Builtins
  alias ExLisp.Env

  @doc """
  Evaluates an AST expression in the given lexical environment.
  """
  def eval(ast, env \\ %{})

  # Literals
  def eval({:lit, val}, _env), do: val
  def eval({:lit, _pos, val}, _env), do: val
  def eval({:atom, _pos, val}, _env), do: val
  def eval({:integer, _pos, val}, _env), do: val
  def eval({:float, _pos, val}, _env), do: val
  def eval({:string, _pos, val}, _env) when is_list(val), do: List.to_string(val)
  def eval({:string, _pos, val}, _env), do: to_string(val)

  def eval({:bin, _pos, [{:bin_element, _, {:string, _, chars}, _, _}]}, _env),
    do: to_string(chars)

  def eval({:char, _pos, code}, _env), do: ExLisp.Character.new(code)
  def eval({nil, _pos}, _env), do: nil

  def eval(val, _env) when is_integer(val) or is_float(val) or is_binary(val), do: val
  def eval(%ExLisp.Ratio{} = val, _env), do: val
  def eval(%ExLisp.Character{} = val, _env), do: val
  def eval({:keyword, _pos, kw}, _env), do: kw
  def eval(nil, _env), do: nil
  def eval(:t, _env), do: :t
  def eval(:T, _env), do: :t
  def eval([], _env), do: nil
  def eval({:list, _pos, []}, _env), do: nil

  # Quoted forms
  def eval({:quoted, _pos, elements}, env) when is_list(elements) do
    Enum.map(elements, fn el ->
      eval(el, env) |> Builtins.unwrap_mv_primary()
    end)
  end

  def eval({:quoted, _pos, element}, _env) do
    eval_quote_node(element)
  end

  def eval({:vector, _pos, elements}, env) do
    elem_vals =
      Enum.map(elements, fn el ->
        eval(el, env) |> Builtins.unwrap_mv_primary()
      end)

    Builtins.vector(elem_vals)
  end

  def eval({:dotted_list, _pos, elements, tail}, env) do
    eval({:list, 1, [{:id, 1, ["list*"]} | elements ++ [tail]]}, env)
  end

  # Backquote
  def eval({:backquote, _pos, inner}, env) do
    expanded = ExLisp.Macro.expand_backquote(inner)
    eval(expanded, env)
  end

  def eval({:comma, _pos, inner}, env), do: eval(inner, env)
  def eval({:comma_at, _pos, inner}, env), do: eval(inner, env)

  # Identifier / Variable lookup
  def eval({:id, _pos, parts} = id_node, env) when is_list(parts) do
    sym_name = LispBeam.extract_symbol_name(id_node)
    eval_symbol(sym_name, env)
  end

  def eval({:id, _pos, name}, env) when is_binary(name) do
    sym_name = LispBeam.extract_symbol_name(name)
    eval_symbol(sym_name, env)
  end

  def eval(sym, env) when is_atom(sym) do
    eval_symbol(sym, env)
  end

  # Function call or special form: `(op ...)`
  def eval({:list, _pos, [op_node | args]} = full_form, env) do
    eval_compound(op_node, args, full_form, env)
  end

  # Fallback
  def eval(other, _env), do: other

  # --- Symbol evaluation ---

  defp eval_symbol(sym, env) when is_atom(sym) do
    cond do
      sym in [nil, nil] ->
        nil

      sym in [:t, :T] ->
        :t

      String.starts_with?(Atom.to_string(sym), ":") ->
        sym

      Map.has_key?(env, {:symbol_macro, sym}) ->
        expansion = Map.get(env, {:symbol_macro, sym})
        eval(expansion, env)

      Map.has_key?(env, sym) ->
        case Map.get(env, sym) do
          {:box, ref} ->
            case :erlang.get(ref) do
              :undefined -> Env.get_var(sym)
              val -> val
            end

          {:box, ref, default_val} ->
            case :erlang.get(ref) do
              :undefined -> default_val
              val -> val
            end

          {:mutated, v_name} ->
            case :erlang.get(v_name) do
              :undefined -> Env.get_var(sym)
              val -> val
            end

          val ->
            val
        end

      true ->
        case :erlang.get(sym) do
          :undefined ->
            case Env.get_var(sym) do
              :unbound ->
                raise RuntimeError, "Unbound variable: #{inspect(sym)}"

              val ->
                val
            end

          val ->
            val
        end
    end
  end

  # --- Compound form evaluation ---

  defp eval_compound(op_node, args, full_form, env) do
    op = LispBeam.extract_op_name(op_node)

    cond do
      # Special operators & special forms
      op in [:quote, :_cl_quote_] ->
        case args do
          [quoted_node | _] -> eval_quote_node(quoted_node)
          _ -> nil
        end

      op in [:function, :_cl_function_] ->
        eval_function(args, env)

      op in [:progn, :_cl_progn_] ->
        eval_progn(args, env)

      op in [:prog1, :_cl_prog1_] ->
        case args do
          [first | rest] ->
            res = eval(first, env)
            eval_progn(rest, env)
            res

          [] ->
            nil
        end

      op in [:prog2, :_cl_prog2_] ->
        case args do
          [first, second | rest] ->
            eval(first, env)
            res = eval(second, env)
            eval_progn(rest, env)
            res

          _ ->
            nil
        end

      op in [:if, :_cl_if_] ->
        case args do
          [test_node, then_node | else_nodes] ->
            test_val = eval(test_node, env) |> Builtins.unwrap_mv_primary()

            if Builtins.truthy?(test_val) do
              eval(then_node, env)
            else
              case else_nodes do
                [else_node | _] -> eval(else_node, env)
                [] -> nil
              end
            end

          _ ->
            nil
        end

      op in [:when, :_cl_when_] ->
        case args do
          [test_node | body] ->
            test_val = eval(test_node, env) |> Builtins.unwrap_mv_primary()
            if Builtins.truthy?(test_val), do: eval_progn(body, env), else: nil

          _ ->
            nil
        end

      op in [:unless, :_cl_unless_] ->
        case args do
          [test_node | body] ->
            test_val = eval(test_node, env) |> Builtins.unwrap_mv_primary()
            unless Builtins.truthy?(test_val), do: eval_progn(body, env), else: nil

          _ ->
            nil
        end

      op in [:cond, :_cl_cond_] ->
        eval_cond(args, env)

      op in [:case, :_cl_case_] ->
        eval_case(args, false, env)

      op in [:ecase, :_cl_ecase_, :ccase, :_cl_ccase_] ->
        eval_case(args, true, env)

      op in [:typecase, :_cl_typecase_] ->
        eval_typecase(args, false, env)

      op in [:etypecase, :_cl_etypecase_, :ctypecase, :_cl_ctypecase_] ->
        eval_typecase(args, true, env)

      op in [:and, :_cl_and_] ->
        eval_and(args, env)

      op in [:or, :_cl_or_] ->
        eval_or(args, env)

      op in [:let, :_cl_let_] ->
        eval_let(args, env)

      op in [:"let*", :_cl_let_star_, :let_star] ->
        eval_let_star(args, env)

      op in [:setq, :_cl_setq_] ->
        eval_setq(args, env)

      op in [:setf, :_cl_setf_] ->
        eval_setf(args, env)

      op in [:psetq, :_cl_psetq_] ->
        eval_psetq(args, env)

      op in [:psetf, :_cl_psetf_] ->
        eval_psetf(args, env)

      op in [:incf, :_cl_incf_] ->
        eval_incf(args, env)

      op in [:decf, :_cl_decf_] ->
        eval_decf(args, env)

      op in [:push, :_cl_push_] ->
        eval_push(args, env)

      op in [:pushnew, :_cl_pushnew_] ->
        eval_pushnew(args, env)

      op in [:pop, :_cl_pop_] ->
        eval_pop(args, env)

      op in [:remf, :_cl_remf_] ->
        eval_remf(args, env)

      op in [:rotatef, :_cl_rotatef_] ->
        eval_rotatef(args, env)

      op in [:shiftf, :_cl_shiftf_] ->
        eval_shiftf(args, env)

      op in [:destructuring_bind, :"destructuring-bind", :_cl_destructuring_bind_] ->
        eval_destructuring_bind(args, env)

      op in [:defvar, :_cl_defvar_] ->
        case args do
          [var_node | rest] ->
            var_sym = LispBeam.extract_symbol_name(var_node)

            {val_node, doc_str} =
              case rest do
                [val, doc | _] -> {val, extract_docstring(doc)}
                [val] -> {val, nil}
                [] -> {nil, nil}
              end

            if doc_str, do: Builtins.set_documentation(var_sym, :variable, doc_str)

            if not Env.has_var?(var_sym) and val_node != nil do
              val = eval(val_node, env) |> Builtins.unwrap_mv_primary()
              Env.put_var(var_sym, val)
            else
              Env.put_var_if_unbound(var_sym, :unbound)
            end

            var_sym

          _ ->
            nil
        end

      op in [:defparameter, :_cl_defparameter_, :defconstant, :_cl_defconstant_] ->
        case args do
          [var_node, val_node | rest] ->
            var_sym = LispBeam.extract_symbol_name(var_node)

            doc_str =
              case rest do
                [doc | _] -> extract_docstring(doc)
                _ -> nil
              end

            if doc_str, do: Builtins.set_documentation(var_sym, :variable, doc_str)
            val = eval(val_node, env) |> Builtins.unwrap_mv_primary()
            Env.put_var(var_sym, val)
            var_sym

          _ ->
            nil
        end

      op in [:defun, :_cl_defun_] ->
        case args do
          [name_node, params_node | body_nodes] ->
            fun_sym = LispBeam.extract_symbol_name(name_node)

            {doc_str, effective_body} =
              case body_nodes do
                [doc | rest] when rest != [] ->
                  case extract_docstring(doc) do
                    str when is_binary(str) -> {str, rest}
                    _ -> {nil, body_nodes}
                  end

                _ ->
                  {nil, body_nodes}
              end

            if doc_str, do: Builtins.set_documentation(fun_sym, :function, doc_str)
            closure = create_closure(params_node, effective_body, env, fun_sym)
            Env.put_fun(fun_sym, closure)
            fun_sym

          _ ->
            nil
        end

      op in [:defmacro, :_cl_defmacro_] ->
        case args do
          [name_node, params_node | body_nodes] ->
            macro_sym = LispBeam.extract_symbol_name(name_node)
            lambda_ast = ExLisp.Macro.build_macro_lambda(params_node, body_nodes)
            macro_fun = eval(lambda_ast, env)
            Env.put_macro(macro_sym, macro_fun)
            macro_sym

          _ ->
            nil
        end

      op in [:lambda, :_cl_lambda_] ->
        case args do
          [params_node | body_nodes] ->
            create_closure(params_node, body_nodes, env, nil)

          _ ->
            nil
        end

      op in [:block, :_cl_block_] ->
        case args do
          [name_node | body_nodes] ->
            block_name = LispBeam.extract_symbol_name(name_node)
            tag = {:block, block_name, make_ref()}
            new_env = Map.put(env, {:block, block_name}, tag)

            try do
              eval_progn(body_nodes, new_env)
            catch
              {:block_return, ^tag, val} -> val
            end

          _ ->
            nil
        end

      op in [:return_from, :_cl_return_from_] ->
        case args do
          [name_node | val_nodes] ->
            block_name = LispBeam.extract_symbol_name(name_node)

            case Map.get(env, {:block, block_name}) do
              nil ->
                throw({:lisp_return, block_name, eval_progn(val_nodes, env)})

              tag ->
                val =
                  case val_nodes do
                    [] -> nil
                    [single] -> eval(single, env)
                    _ -> eval_progn(val_nodes, env)
                  end

                throw({:block_return, tag, val})
            end

          _ ->
            nil
        end

      op in [:return, :_cl_return_] ->
        case Map.get(env, {:block, nil}) do
          nil ->
            val =
              case args do
                [] -> nil
                [single] -> eval(single, env)
                _ -> eval_progn(args, env)
              end

            throw({:lisp_return, nil, val})

          tag ->
            val =
              case args do
                [] -> nil
                [single] -> eval(single, env)
                _ -> eval_progn(args, env)
              end

            throw({:block_return, tag, val})
        end

      op in [:loop, :_cl_loop_] ->
        eval_loop(args, env)

      op in [:dotimes, :_cl_dotimes_] ->
        eval_dotimes(args, env)

      op in [:dolist, :_cl_dolist_] ->
        eval_dolist(args, env)

      op in [:do, :_cl_do_] ->
        expanded = LispBeam.expand_do(args)
        eval(expanded, env)

      op in [:"do*", :_cl_do_star_, :do_star] ->
        expanded = LispBeam.expand_do_star(args)
        eval(expanded, env)

      op in [:prog, :_cl_prog_] ->
        case args do
          [bindings | body] ->
            {_decls, tagbody_body} = LispBeam.split_declarations(body)
            tag = {:block, nil, make_ref()}
            block_env = Map.put(env, {:block, nil}, tag)
            bound_env = eval_let_bindings(bindings, block_env)

            try do
              eval_tagbody(tagbody_body, bound_env)
              nil
            catch
              {:block_return, ^tag, val} -> val
            end

          _ ->
            nil
        end

      op in [:"prog*", :_cl_prog_star_, :prog_star] ->
        case args do
          [bindings | body] ->
            {_decls, tagbody_body} = LispBeam.split_declarations(body)
            tag = {:block, nil, make_ref()}
            block_env = Map.put(env, {:block, nil}, tag)
            bound_env = eval_let_star_bindings(bindings, block_env)

            try do
              eval_tagbody(tagbody_body, bound_env)
              nil
            catch
              {:block_return, ^tag, val} -> val
            end

          _ ->
            nil
        end

      op in [:tagbody, :_cl_tagbody_] ->
        eval_tagbody(args, env)

      op in [:go, :_cl_go_] ->
        case args do
          [tag_node | _] ->
            tag = LispBeam.extract_symbol_name(tag_node)
            tagbody_id = Map.get(env, {:tag, tag})
            throw({:lisp_go, tagbody_id, tag})

          _ ->
            nil
        end

      op in [:progv, :_cl_progv_] ->
        case args do
          [syms_node, vals_node | body_nodes] ->
            syms = eval(syms_node, env) |> Builtins.unwrap_mv_primary()
            vals = eval(vals_node, env) |> Builtins.unwrap_mv_primary()
            syms_list = if is_list(syms), do: syms, else: [syms]
            vals_list = if is_list(vals), do: vals, else: [vals]

            norm_syms =
              Enum.map(syms_list, &Builtins.unwrap_mv_primary/1)
              |> Enum.map(&LispBeam.extract_symbol_name/1)

            norm_vals = Enum.map(vals_list, &Builtins.unwrap_mv_primary/1)

            ExLisp.Env.progv(norm_syms, norm_vals, fn ->
              eval_progn(body_nodes, env)
            end)

          _ ->
            nil
        end

      op in [:multiple_value_bind, :_cl_multiple_value_bind_, :"multiple-value-bind"] ->
        case args do
          [vars_node, val_form | body_nodes] ->
            var_names = LispBeam.extract_param_names(vars_node)
            mv_res = eval(rewrite_mv_form(val_form), env)
            vals_list = extract_values(mv_res)

            padded_vals =
              vals_list ++ List.duplicate(nil, max(0, length(var_names) - length(vals_list)))

            new_env =
              Enum.zip(var_names, padded_vals)
              |> Enum.reduce(env, fn {var, val}, acc ->
                ref = make_ref()
                :erlang.put(ref, val)
                Map.put(acc, var, {:box, ref})
              end)

            eval_progn(body_nodes, new_env)

          _ ->
            nil
        end

      op in [:multiple_value_prog1, :_cl_multiple_value_prog1_] ->
        case args do
          [first_node | rest_nodes] ->
            res = eval(first_node, env)
            eval_progn(rest_nodes, env)
            res

          _ ->
            nil
        end

      op in [:multiple_value_list, :_cl_multiple_value_list_] ->
        case args do
          [form | _] ->
            res = eval(rewrite_mv_form(form), env)
            extract_values(res)

          _ ->
            []
        end

      op in [:nth_value, :_cl_nth_value_] ->
        case args do
          [n_node, form | _] ->
            n = eval(n_node, env) |> Builtins.unwrap_mv_primary()
            res = eval(rewrite_mv_form(form), env)
            Enum.at(extract_values(res), n, nil)

          _ ->
            nil
        end

      op in [:multiple_value_call, :_cl_multiple_value_call_] ->
        case args do
          [fn_node | form_nodes] ->
            fun = eval(fn_node, env)

            all_args =
              Enum.flat_map(form_nodes, fn f -> extract_values(eval(rewrite_mv_form(f), env)) end)

            Builtins.invoke_fn(fun, all_args)

          _ ->
            nil
        end

      op in [:multiple_value_setq, :_cl_multiple_value_setq_, :"multiple-value-setq"] ->
        case args do
          [vars_node, form | _] ->
            var_names = LispBeam.extract_param_names(vars_node)
            mv_res = eval(rewrite_mv_form(form), env)
            vals_list = extract_values(mv_res)

            padded =
              vals_list ++ List.duplicate(nil, max(0, length(var_names) - length(vals_list)))

            Enum.zip(var_names, padded)
            |> Enum.each(fn {var, val} ->
              case Map.get(env, var) do
                box when is_tuple(box) and elem(box, 0) == :box -> :erlang.put(elem(box, 1), val)
                _ -> Env.set_var(var, val)
              end
            end)

            List.first(vals_list)

          _ ->
            nil
        end

      op in [:flet, :_cl_flet_] ->
        eval_flet(args, env)

      op in [:labels, :_cl_labels_] ->
        eval_labels(args, env)

      op in [:macrolet, :_cl_macrolet_] ->
        eval_macrolet(args, env)

      op in [:symbol_macrolet, :_cl_symbol_macrolet_] ->
        eval_symbol_macrolet(args, env)

      op in [:catch, :_cl_catch_] ->
        case args do
          [tag_node | body] ->
            tag_val = eval(tag_node, env) |> Builtins.unwrap_mv_primary()

            try do
              eval_progn(body, env)
            catch
              {:lisp_throw, thrown_tag, val} when thrown_tag == tag_val ->
                val
            end

          _ ->
            nil
        end

      op in [:throw, :_cl_throw_] ->
        case args do
          [tag_node, val_node | _] ->
            tag_val = eval(tag_node, env) |> Builtins.unwrap_mv_primary()
            val = eval(val_node, env)
            throw({:lisp_throw, tag_val, val})

          [tag_node] ->
            tag_val = eval(tag_node, env) |> Builtins.unwrap_mv_primary()
            throw({:lisp_throw, tag_val, nil})

          _ ->
            nil
        end

      op in [:unwind_protect, :_cl_unwind_protect_, :"unwind-protect"] ->
        case args do
          [protected_node | cleanup_nodes] ->
            try do
              eval(protected_node, env)
            after
              eval_progn(cleanup_nodes, env)
            end

          _ ->
            nil
        end

      op in [:locally, :_cl_locally_] ->
        eval_progn(args, env)

      op in [:eval_when, :_cl_eval_when_] ->
        case args do
          [_situations | body] -> eval_progn(body, env)
          _ -> nil
        end

      op in [:ignore_errors, :_cl_ignore_errors_, :"ignore-errors"] ->
        try do
          eval_progn(args, env)
        rescue
          _ -> [:_values_, [nil, :error]]
        catch
          _ -> [:_values_, [nil, :error]]
        end

      op in [:handler_bind, :_cl_handler_bind_, :"handler-bind"] ->
        eval_handler_bind(args, env)

      op in [:handler_case, :_cl_handler_case_, :"handler-case"] ->
        eval_handler_case(args, env)

      op in [:restart_bind, :_cl_restart_bind_, :"restart-bind"] ->
        eval_restart_bind(args, env)

      op in [:restart_case, :_cl_restart_case_, :"restart-case"] ->
        eval_restart_case(args, env)

      op in [:with_simple_restart, :_cl_with_simple_restart_, :"with-simple-restart"] ->
        expanded = LispBeam.expand_with_simple_restart(args)
        eval(expanded, env)

      op in [:define_condition, :_cl_define_condition_, :"define-condition"] ->
        eval_define_condition(args, env)

      op in [:with_open_file, :_cl_with_open_file_, :"with-open-file"] ->
        eval_with_open_file(args, env)

      op in [:with_open_stream, :_cl_with_open_stream_, :"with-open-stream"] ->
        eval_with_open_stream(args, env)

      op in [:with_input_from_string, :_cl_with_input_from_string_, :"with-input-from-string"] ->
        eval_with_input_from_string(args, env)

      op in [:with_output_to_string, :_cl_with_output_to_string_, :"with-output-to-string"] ->
        eval_with_output_to_string(args, env)

      op in [
        :with_mutex,
        :_cl_with_mutex_,
        :"with-mutex",
        :"sb-thread:with-mutex",
        :_sb_thread_with_mutex_
      ] ->
        eval_with_mutex(args, env)

      op in [:defstruct, :_cl_defstruct_] ->
        eval_defstruct(args, env)

      op in [:defclass, :_cl_defclass_] ->
        eval_defclass(args, env)

      op in [:defgeneric, :_cl_defgeneric_] ->
        eval_defgeneric(args, env)

      op in [:defmethod, :_cl_defmethod_] ->
        eval_defmethod(args, env)

      op in [:call_next_method, :_cl_call_next_method_, :"call-next-method"] ->
        case args do
          [] ->
            ExLisp.CLOS.call_next_method()

          _ ->
            eval_args = Enum.map(args, &(eval(&1, env) |> Builtins.unwrap_mv_primary()))
            ExLisp.CLOS.call_next_method(eval_args)
        end

      op in [:next_method_p, :_cl_next_method_p_, :"next-method-p"] ->
        ExLisp.CLOS.next_method_p()

      op in [:check_type, :_cl_check_type_, :"check-type"] ->
        case args do
          [place_node, typespec_node | _] ->
            val = eval(place_node, env) |> Builtins.unwrap_mv_primary()
            typespec = eval_quote_node(typespec_node)

            unless Builtins.truthy?(ExLisp.Type.typep(val, typespec)) do
              raise RuntimeError, "The value #{inspect(val)} is not of type #{inspect(typespec)}"
            end

            nil

          _ ->
            nil
        end

      op in [:assert, :_cl_assert_] ->
        case args do
          [test_node | _] ->
            val = eval(test_node, env) |> Builtins.unwrap_mv_primary()

            unless Builtins.truthy?(val) do
              raise RuntimeError, "Assertion failed: #{inspect(test_node)}"
            end

            nil

          _ ->
            nil
        end

      op in [:the, :_cl_the_] ->
        case args do
          [typespec_node, val_node | _] ->
            val = eval(val_node, env)
            unwrapped = Builtins.unwrap_mv_primary(val)
            typespec = eval_quote_node(typespec_node)

            unless Builtins.truthy?(ExLisp.Type.typep(unwrapped, typespec)) do
              raise RuntimeError,
                    "The value #{inspect(unwrapped)} is not of type #{inspect(typespec)}"
            end

            val

          _ ->
            nil
        end

      op in [:deftype, :_cl_deftype_] ->
        case args do
          [name_node, params_node | body_nodes] ->
            name_sym = LispBeam.extract_symbol_name(name_node)
            params = extract_deftype_params(params_node)
            ExLisp.Type.define_deftype(name_sym, params, body_nodes)
            name_sym

          _ ->
            nil
        end

      op in [:time, :_cl_time_] ->
        case args do
          [inner_expr | _] ->
            Builtins.time_eval(fn -> eval(inner_expr, env) end)

          _ ->
            nil
        end

      op in [:in_package, :_cl_in_package_] ->
        case args do
          [pkg_node | _] ->
            pkg_name = LispBeam.extract_symbol_name(pkg_node)
            ExLisp.Package.set_current_package(pkg_name)

          _ ->
            nil
        end

      op in [:declaim, :_cl_declaim_, :proclaim, :_cl_proclaim_, :declare, :_cl_declare_] ->
        :t

      op in [
        :define_setf_expander,
        :_cl_define_setf_expander_,
        :defsetf,
        :_cl_defsetf_,
        :define_modify_macro,
        :_cl_define_modify_macro_,
        :define_compiler_macro,
        :_cl_define_compiler_macro_
      ] ->
        case args do
          [name_node | _] -> LispBeam.extract_symbol_name(name_node)
          _ -> :t
        end

      op in [
        :with_standard_io_syntax,
        :_cl_with_standard_io_syntax_,
        :with_compilation_unit,
        :_cl_with_compilation_unit_
      ] ->
        eval_progn(args, env)

      op in [:defpackage, :_cl_defpackage_] ->
        case args do
          [pkg_node | opt_nodes] ->
            pkg_name =
              case LispBeam.extract_symbol_name(pkg_node) do
                a when is_atom(a) -> Atom.to_string(a)
                s when is_binary(s) -> s
                _ -> ""
              end
              |> ExLisp.Package.clean_uninterned()
              |> String.trim_leading(":")

            opts_ast =
              Enum.map(opt_nodes, fn
                {:list, _, opt_elems} ->
                  Enum.map(opt_elems, fn
                    {:keyword, _, kw} ->
                      kw

                    node ->
                      case LispBeam.extract_symbol_name(node) do
                        a when is_atom(a) ->
                          Atom.to_string(a) |> ExLisp.Package.clean_uninterned()

                        s when is_binary(s) ->
                          s |> ExLisp.Package.clean_uninterned()

                        _ ->
                          ""
                      end
                  end)
                  |> Enum.reject(&(&1 == ""))

                {:quoted, _, opt_elems} ->
                  Enum.map(opt_elems, fn
                    {:keyword, _, kw} ->
                      kw

                    node ->
                      case LispBeam.extract_symbol_name(node) do
                        a when is_atom(a) ->
                          Atom.to_string(a) |> ExLisp.Package.clean_uninterned()

                        s when is_binary(s) ->
                          s |> ExLisp.Package.clean_uninterned()

                        _ ->
                          ""
                      end
                  end)
                  |> Enum.reject(&(&1 == ""))

                {:dotted_list, _, opt_elems, _tail} ->
                  Enum.map(opt_elems, fn
                    {:keyword, _, kw} ->
                      kw

                    node ->
                      case LispBeam.extract_symbol_name(node) do
                        a when is_atom(a) ->
                          Atom.to_string(a) |> ExLisp.Package.clean_uninterned()

                        s when is_binary(s) ->
                          s |> ExLisp.Package.clean_uninterned()

                        _ ->
                          ""
                      end
                  end)
                  |> Enum.reject(&(&1 == ""))

                other ->
                  other
              end)

            ExLisp.Package.defpackage(pkg_name, opts_ast)

          _ ->
            nil
        end

      op in [:provide, :_cl_provide_, :require, :_cl_require_] ->
        case args do
          [pkg_node | _] -> LispBeam.extract_symbol_name(pkg_node)
          _ -> :t
        end

      op in [:defsystem, :_cl_defsystem_] ->
        :t

      op in [:eval, :_cl_eval_] ->
        case args do
          [arg_node | _] ->
            lisp_form = eval(arg_node, env) |> Builtins.unwrap_mv_primary()
            ast = ExLisp.Macro.lisp_data_to_ast(lisp_form)
            eval(ast, %{})

          _ ->
            nil
        end

      # Macro call
      Map.has_key?(env, {:macro, op}) ->
        macro_fun = Map.get(env, {:macro, op})
        expanded = apply_macro(macro_fun, args, full_form)
        eval(expanded, env)

      Env.has_macro?(op) ->
        macro_fun = Env.get_macro(op)
        expanded = apply_macro(macro_fun, args, full_form)
        eval(expanded, env)

      # Function / Builtin / Remote / Lambda call
      true ->
        case LispBeam.normalize_remote_op(op_node) do
          {:remote, mod, fun} ->
            eval_args = Enum.map(args, &(eval(&1, env) |> Builtins.unwrap_mv_primary()))
            apply(mod, fun, eval_args)

          _ ->
            cond do
              match?({:list, _, _}, op_node) or match?({:quoted, _, _}, op_node) ->
                fun = eval(op_node, env)
                eval_args = Enum.map(args, &(eval(&1, env) |> Builtins.unwrap_mv_primary()))
                Builtins.invoke_fn(fun, eval_args)

              true ->
                eval_call(op, args, env)
            end
        end
    end
  end

  # --- Macro expansion helper ---

  defp apply_macro(macro_fun, args, full_form) do
    lisp_args = Enum.map(args, &ExLisp.Macro.ast_to_lisp_data/1)
    lisp_whole = ExLisp.Macro.ast_to_lisp_data(full_form)

    expanded_data =
      case macro_fun do
        %ExLisp.Closure{fun: fun} ->
          fun.([lisp_args, lisp_whole])

        fun when is_function(fun, 2) ->
          fun.(lisp_args, lisp_whole)

        fun when is_function(fun, 1) ->
          fun.([lisp_args, lisp_whole])

        _ ->
          raise "Invalid macro function: #{inspect(macro_fun)}"
      end

    ExLisp.Macro.lisp_data_to_ast(expanded_data)
  end

  # --- Function / Call evaluation ---

  defp eval_call(op, args, env) do
    eval_args =
      Enum.map(args, fn arg ->
        eval(arg, env) |> Builtins.unwrap_mv_primary()
      end)

    cond do
      op == nil ->
        raise RuntimeError, "Invalid function: nil"

      Map.has_key?(env, {:fun, op}) ->
        fun_val = Map.get(env, {:fun, op})
        Builtins.invoke_fn(fun_val, eval_args)

      Env.has_fun?(op) ->
        fun_val = Env.get_fun(op)
        Builtins.invoke_fn(fun_val, eval_args)

      BuiltinFunction.builtin?(op) ->
        {:ok, canonical} = BuiltinFunction.lookup(op)
        Builtins.dispatch_builtin(canonical, eval_args)

      true ->
        Builtins.invoke_fn(op, eval_args)
    end
  end

  # --- Progn / Sequence evaluation ---

  def eval_progn([], _env), do: nil
  def eval_progn([single], env), do: eval(single, env)

  def eval_progn([first | rest], env) do
    eval(first, env)
    eval_progn(rest, env)
  end

  # --- Cond ---

  defp eval_cond([], _env), do: nil

  defp eval_cond([clause | rest], env) do
    case clause do
      {:list, _, [test_node | body_nodes]} ->
        do_eval_cond_clause(test_node, body_nodes, rest, env)

      [test_node | body_nodes] ->
        do_eval_cond_clause(test_node, body_nodes, rest, env)

      _ ->
        eval_cond(rest, env)
    end
  end

  defp do_eval_cond_clause(test_node, body_nodes, rest_clauses, env) do
    test_res = eval(test_node, env)
    test_val = Builtins.unwrap_mv_primary(test_res)

    if Builtins.truthy?(test_val) do
      if body_nodes == [] do
        test_res
      else
        eval_progn(body_nodes, env)
      end
    else
      eval_cond(rest_clauses, env)
    end
  end

  # --- Case / Ecase ---

  defp eval_case([key_node | clauses], is_error, env) do
    key_val = eval(key_node, env) |> Builtins.unwrap_mv_primary()

    matched =
      Enum.find_value(clauses, fn clause ->
        case clause do
          {:list, _, [keys_node | body_nodes]} ->
            match_case_clause(key_val, keys_node, body_nodes, env)

          [keys_node | body_nodes] ->
            match_case_clause(key_val, keys_node, body_nodes, env)

          _ ->
            nil
        end
      end)

    case matched do
      {:matched, val} ->
        val

      nil ->
        if is_error do
          raise RuntimeError, "No case match for #{inspect(key_val)}"
        else
          nil
        end
    end
  end

  defp eval_case([], _is_error, _env), do: nil

  defp match_case_clause(key_val, keys_node, body_nodes, env) do
    case keys_node do
      {:list, _, key_list} ->
        keys = Enum.map(key_list, &eval_quote_node/1)

        if Enum.any?(keys, &(Builtins.eql(key_val, &1) == :t)) do
          {:matched, eval_progn(body_nodes, env)}
        else
          nil
        end

      other ->
        k = eval_quote_node(other)

        if k in [:t, :otherwise, :_] or Builtins.eql(key_val, k) == :t do
          {:matched, eval_progn(body_nodes, env)}
        else
          nil
        end
    end
  end

  # --- Typecase / Etypecase ---

  defp eval_typecase([key_node | clauses], is_error, env) do
    key_val = eval(key_node, env) |> Builtins.unwrap_mv_primary()

    matched =
      Enum.find_value(clauses, fn clause ->
        case clause do
          {:list, _, [type_spec | body_nodes]} ->
            match_typecase_clause(key_val, type_spec, body_nodes, env)

          [type_spec | body_nodes] ->
            match_typecase_clause(key_val, type_spec, body_nodes, env)

          _ ->
            nil
        end
      end)

    case matched do
      {:matched, val} ->
        val

      nil ->
        if is_error do
          raise RuntimeError, "No typecase match for #{inspect(key_val)}"
        else
          nil
        end
    end
  end

  defp eval_typecase([], _is_error, _env), do: nil

  defp match_typecase_clause(key_val, type_spec, body_nodes, env) do
    type_name = LispBeam.extract_symbol_name(type_spec)

    if type_name in [:t, :otherwise, :_] or
         Builtins.truthy?(ExLisp.Type.typep(key_val, eval_quote_node(type_spec))) do
      {:matched, eval_progn(body_nodes, env)}
    else
      nil
    end
  end

  # --- And / Or ---

  defp eval_and([], _env), do: :t
  defp eval_and([single], env), do: eval(single, env)

  defp eval_and([first | rest], env) do
    res = eval(first, env)
    val = Builtins.unwrap_mv_primary(res)

    if Builtins.truthy?(val) do
      eval_and(rest, env)
    else
      nil
    end
  end

  defp eval_or([], _env), do: nil
  defp eval_or([single], env), do: eval(single, env)

  defp eval_or([first | rest], env) do
    res = eval(first, env)
    val = Builtins.unwrap_mv_primary(res)

    if Builtins.truthy?(val) do
      res
    else
      eval_or(rest, env)
    end
  end

  # --- Let / Let* ---

  defp eval_let([bindings_node | body_nodes], env) do
    new_env = eval_let_bindings(bindings_node, env)
    eval_progn(body_nodes, new_env)
  end

  defp eval_let([], _env), do: nil

  defp eval_let_bindings(bindings_node, env) do
    bindings = LispBeam.extract_bindings(bindings_node)

    evaluated =
      Enum.map(bindings, fn {var_sym, init_node} ->
        val = eval(init_node, env) |> Builtins.unwrap_mv_primary()
        {var_sym, val}
      end)

    Enum.reduce(evaluated, env, fn {var, val}, acc ->
      ref = make_ref()
      :erlang.put(ref, val)
      Map.put(acc, var, {:box, ref})
    end)
  end

  defp eval_let_star([bindings_node | body_nodes], env) do
    new_env = eval_let_star_bindings(bindings_node, env)
    eval_progn(body_nodes, new_env)
  end

  defp eval_let_star([], _env), do: nil

  defp eval_let_star_bindings(bindings_node, env) do
    bindings = LispBeam.extract_bindings(bindings_node)

    Enum.reduce(bindings, env, fn {var_sym, init_node}, acc ->
      val = eval(init_node, acc) |> Builtins.unwrap_mv_primary()
      ref = make_ref()
      :erlang.put(ref, val)
      Map.put(acc, var_sym, {:box, ref})
    end)
  end

  # --- Setq / Setf / Mutators ---

  defp eval_setq(args, env) do
    pairs = Enum.chunk_every(args, 2)

    Enum.reduce(pairs, nil, fn
      [var_node, val_node], _acc ->
        var_sym = LispBeam.extract_symbol_name(var_node)
        val = eval(val_node, env) |> Builtins.unwrap_mv_primary()

        case Map.get(env, var_sym) do
          box when is_tuple(box) and elem(box, 0) == :box -> :erlang.put(elem(box, 1), val)
          _ -> Env.set_var(var_sym, val)
        end

        val

      [var_node], _acc ->
        var_sym = LispBeam.extract_symbol_name(var_node)

        case Map.get(env, var_sym) do
          box when is_tuple(box) and elem(box, 0) == :box -> :erlang.put(elem(box, 1), nil)
          _ -> Env.set_var(var_sym, nil)
        end

        nil
    end)
  end

  defp eval_setf(args, env) do
    pairs = Enum.chunk_every(args, 2)

    Enum.reduce(pairs, nil, fn
      [place, val_node], _acc ->
        val = eval(val_node, env)
        do_eval_setf_place(place, val, env)

      [place], _acc ->
        do_eval_setf_place(place, nil, env)
    end)
  end

  defp do_eval_setf_place(place, val, env) do
    unwrapped = Builtins.unwrap_mv_primary(val)

    case place do
      {:id, _pos, _} ->
        var_sym = LispBeam.extract_symbol_name(place)

        case Map.get(env, var_sym) do
          box when is_tuple(box) and elem(box, 0) == :box -> :erlang.put(elem(box, 1), unwrapped)
          _ -> Env.set_var(var_sym, unwrapped)
        end

        val

      var_sym when is_atom(var_sym) ->
        case Map.get(env, var_sym) do
          box when is_tuple(box) and elem(box, 0) == :box -> :erlang.put(elem(box, 1), unwrapped)
          _ -> Env.set_var(var_sym, unwrapped)
        end

        val

      {:list, _pos, [op_node | place_args]} ->
        op = LispBeam.extract_op_name(op_node)

        case op do
          name when name in [:get, :_cl_get_] ->
            [sym_node, ind_node | _] = place_args
            sym = eval(sym_node, env) |> Builtins.unwrap_mv_primary()
            ind = eval(ind_node, env) |> Builtins.unwrap_mv_primary()
            Builtins.set_get(sym, ind, unwrapped)
            val

          name when name in [:symbol_plist, :_cl_symbol_plist_, :"symbol-plist"] ->
            [sym_node | _] = place_args
            sym = eval(sym_node, env) |> Builtins.unwrap_mv_primary()
            Builtins.set_symbol_plist(sym, unwrapped)
            val

          name when name in [:symbol_value, :_cl_symbol_value_, :"symbol-value"] ->
            [sym_node | _] = place_args
            sym = eval(sym_node, env) |> Builtins.unwrap_mv_primary()
            Builtins.set_symbol_value(sym, unwrapped)
            val

          name when name in [:symbol_function, :_cl_symbol_function_, :"symbol-function"] ->
            [sym_node | _] = place_args
            sym = eval(sym_node, env) |> Builtins.unwrap_mv_primary()
            Builtins.set_symbol_function(sym, unwrapped)
            val

          name when name in [:car, :_cl_car_, :first] ->
            [target_node | _] = place_args
            target = eval(target_node, env) |> Builtins.unwrap_mv_primary()
            Builtins.rplaca(target, unwrapped)
            val

          name when name in [:cdr, :_cl_cdr_, :rest] ->
            [target_node | _] = place_args
            target = eval(target_node, env) |> Builtins.unwrap_mv_primary()
            Builtins.rplacd(target, unwrapped)
            val

          name when name in [:nth, :_cl_nth_] ->
            [idx_node, target_node | _] = place_args
            idx = eval(idx_node, env) |> Builtins.unwrap_mv_primary()
            target = eval(target_node, env) |> Builtins.unwrap_mv_primary()
            Builtins.set_nth(idx, target, unwrapped)
            val

          name when name in [:elt, :_cl_elt_] ->
            [seq_node, idx_node | _] = place_args
            seq = eval(seq_node, env) |> Builtins.unwrap_mv_primary()
            idx = eval(idx_node, env) |> Builtins.unwrap_mv_primary()
            Builtins.set_elt(seq, idx, unwrapped)
            val

          name when name in [:aref, :_cl_aref_] ->
            [arr_node | idx_nodes] = place_args
            arr = eval(arr_node, env) |> Builtins.unwrap_mv_primary()
            idxs = Enum.map(idx_nodes, &(eval(&1, env) |> Builtins.unwrap_mv_primary()))
            Builtins.set_aref(arr, idxs, unwrapped)
            val

          name when name in [:svref, :_cl_svref_] ->
            [vec_node, idx_node | _] = place_args
            vec = eval(vec_node, env) |> Builtins.unwrap_mv_primary()
            idx = eval(idx_node, env) |> Builtins.unwrap_mv_primary()
            Builtins.set_svref(vec, idx, unwrapped)
            val

          name when name in [:row_major_aref, :_cl_row_major_aref_, :"row-major-aref"] ->
            [arr_node, idx_node | _] = place_args
            arr = eval(arr_node, env) |> Builtins.unwrap_mv_primary()
            idx = eval(idx_node, env) |> Builtins.unwrap_mv_primary()
            Builtins.set_row_major_aref(arr, idx, unwrapped)
            val

          name when name in [:gethash, :_cl_gethash_] ->
            [key_node, tbl_node | _] = place_args
            key = eval(key_node, env) |> Builtins.unwrap_mv_primary()
            tbl = eval(tbl_node, env) |> Builtins.unwrap_mv_primary()
            Builtins.set_gethash(key, tbl, unwrapped)
            val

          name when name in [:slot_value, :_cl_slot_value_, :"slot-value"] ->
            [obj_node, slot_node | _] = place_args
            obj = eval(obj_node, env) |> Builtins.unwrap_mv_primary()
            slot = eval(slot_node, env) |> Builtins.unwrap_mv_primary()
            ExLisp.CLOS.set_slot_value(obj, slot, unwrapped)
            val

          name when name in [:documentation, :_cl_documentation_] ->
            case place_args do
              [target_node, type_node] ->
                target = eval(target_node, env) |> Builtins.unwrap_mv_primary()
                type = eval(type_node, env) |> Builtins.unwrap_mv_primary()
                Builtins.set_documentation(target, type, unwrapped)

              [target_node] ->
                target = eval(target_node, env) |> Builtins.unwrap_mv_primary()
                Builtins.set_documentation(target, :function, unwrapped)
            end

            val

          name when name in [:values, :_cl_values_] ->
            vals = extract_values(val)

            Enum.zip(
              place_args,
              vals ++ List.duplicate(nil, max(0, length(place_args) - length(vals)))
            )
            |> Enum.each(fn {p, v} -> do_eval_setf_place(p, v, env) end)

            val

          name when name in [:getf, :_cl_getf_] ->
            [target_node, ind_node | _] = place_args
            target = eval(target_node, env) |> Builtins.unwrap_mv_primary()
            ind = eval(ind_node, env) |> Builtins.unwrap_mv_primary()
            updated_plist = Builtins.put_plist(target, ind, unwrapped)
            do_eval_setf_place(target_node, updated_plist, env)
            val

          name when name in [:subseq, :_cl_subseq_] ->
            case place_args do
              [seq_node, start_node] ->
                seq = eval(seq_node, env) |> Builtins.unwrap_mv_primary()
                start_idx = eval(start_node, env) |> Builtins.unwrap_mv_primary()
                updated = Builtins.set_subseq_update_seq(seq, start_idx, nil, unwrapped)
                do_eval_setf_place(seq_node, updated, env)

              [seq_node, start_node, end_node] ->
                seq = eval(seq_node, env) |> Builtins.unwrap_mv_primary()
                start_idx = eval(start_node, env) |> Builtins.unwrap_mv_primary()
                end_idx = eval(end_node, env) |> Builtins.unwrap_mv_primary()
                updated = Builtins.set_subseq_update_seq(seq, start_idx, end_idx, unwrapped)
                do_eval_setf_place(seq_node, updated, env)
            end

            val

          name when name in [:ldb, :_cl_ldb_] ->
            [bytespec_node, target_place | _] = place_args
            bytespec = eval(bytespec_node, env) |> Builtins.unwrap_mv_primary()
            cur_target_val = eval(target_place, env) |> Builtins.unwrap_mv_primary()
            cur_int = if is_integer(cur_target_val), do: cur_target_val, else: 0
            new_target_val = Builtins.dpb(unwrapped, bytespec, cur_int)
            do_eval_setf_place(target_place, new_target_val, env)
            val

          # Structure accessor or custom setf function
          _ ->
            setf_fn_sym = :"setf_#{op}"

            cond do
              Env.has_fun?(setf_fn_sym) ->
                args = [
                  unwrapped
                  | Enum.map(place_args, &(eval(&1, env) |> Builtins.unwrap_mv_primary()))
                ]

                Builtins.invoke_fn(Env.get_fun(setf_fn_sym), args)
                val

              # Struct slot accessor: struct_slot
              true ->
                [struct_node | _] = place_args
                struct_val = eval(struct_node, env) |> Builtins.unwrap_mv_primary()

                slot_name =
                  case struct_val do
                    {:struct, s_name, _tid} ->
                      s_prefix = "#{s_name}_"
                      op_str = to_string(op)

                      if String.starts_with?(op_str, s_prefix) do
                        String.replace_prefix(op_str, s_prefix, "") |> String.to_atom()
                      else
                        op
                      end

                    _ ->
                      op
                  end

                Builtins.set_struct_slot(struct_val, slot_name, unwrapped)
                val
            end
        end

      _ ->
        val
    end
  end

  defp eval_psetq(args, env) do
    pairs = Enum.chunk_every(args, 2)

    evaluated =
      Enum.map(pairs, fn
        [var_node, val_node] ->
          var_sym = LispBeam.extract_symbol_name(var_node)
          val = eval(val_node, env) |> Builtins.unwrap_mv_primary()
          {var_sym, val}

        [var_node] ->
          var_sym = LispBeam.extract_symbol_name(var_node)
          {var_sym, nil}
      end)

    Enum.each(evaluated, fn {var_sym, val} ->
      case Map.get(env, var_sym) do
        box when is_tuple(box) and elem(box, 0) == :box -> :erlang.put(elem(box, 1), val)
        _ -> Env.set_var(var_sym, val)
      end
    end)

    nil
  end

  defp eval_psetf(args, env) do
    pairs = Enum.chunk_every(args, 2)

    evaluated =
      Enum.map(pairs, fn
        [place, val_node] ->
          val = eval(val_node, env)
          {place, val}

        [place] ->
          {place, nil}
      end)

    Enum.each(evaluated, fn {place, val} ->
      do_eval_setf_place(place, val, env)
    end)

    nil
  end

  defp eval_incf(args, env) do
    case args do
      [place_node] ->
        eval_setf([place_node, {:list, 1, [{:id, 1, ["+"]}, place_node, {:lit, 1}]}], env)

      [place_node, delta_node | _] ->
        eval_setf([place_node, {:list, 1, [{:id, 1, ["+"]}, place_node, delta_node]}], env)

      _ ->
        nil
    end
  end

  defp eval_decf(args, env) do
    case args do
      [place_node] ->
        eval_setf([place_node, {:list, 1, [{:id, 1, ["-"]}, place_node, {:lit, 1}]}], env)

      [place_node, delta_node | _] ->
        eval_setf([place_node, {:list, 1, [{:id, 1, ["-"]}, place_node, delta_node]}], env)

      _ ->
        nil
    end
  end

  defp eval_push(args, env) do
    case args do
      [item_node, place_node | _] ->
        item_val = eval(item_node, env) |> Builtins.unwrap_mv_primary()
        cur_val = eval(place_node, env) |> Builtins.unwrap_mv_primary()
        new_list = [item_val | if(cur_val in [nil, []], do: [], else: cur_val)]
        do_eval_setf_place(place_node, new_list, env)
        new_list

      _ ->
        nil
    end
  end

  defp eval_pushnew(args, env) do
    case args do
      [item_node, place_node | rest_opts] ->
        item_val = eval(item_node, env) |> Builtins.unwrap_mv_primary()
        cur_val = eval(place_node, env) |> Builtins.unwrap_mv_primary()
        opt_vals = Enum.map(rest_opts, &(eval(&1, env) |> Builtins.unwrap_mv_primary()))
        new_list = apply(Builtins, :adjoin, [item_val, cur_val | opt_vals])
        do_eval_setf_place(place_node, new_list, env)
        new_list

      _ ->
        nil
    end
  end

  defp eval_pop(args, env) do
    case args do
      [place_node | _] ->
        cur_val = eval(place_node, env) |> Builtins.unwrap_mv_primary()

        case cur_val do
          [head | tail] ->
            do_eval_setf_place(place_node, tail, env)
            head

          _ ->
            do_eval_setf_place(place_node, nil, env)
            nil
        end

      _ ->
        nil
    end
  end

  defp eval_remf(args, env) do
    case args do
      [place_node, ind_node | _] ->
        ind_val = eval(ind_node, env) |> Builtins.unwrap_mv_primary()
        cur_val = eval(place_node, env) |> Builtins.unwrap_mv_primary()
        [new_plist, removed] = Builtins.rem_plist(cur_val, ind_val)
        do_eval_setf_place(place_node, new_plist, env)
        removed

      _ ->
        nil
    end
  end

  defp eval_rotatef(args, env) do
    if length(args) > 1 do
      vals = Enum.map(args, &(eval(&1, env) |> Builtins.unwrap_mv_primary()))
      rotated_vals = tl(vals) ++ [hd(vals)]

      Enum.zip(args, rotated_vals)
      |> Enum.each(fn {p, v} -> do_eval_setf_place(p, v, env) end)
    end

    nil
  end

  defp eval_shiftf(args, env) do
    if length(args) > 1 do
      vals = Enum.map(args, &(eval(&1, env) |> Builtins.unwrap_mv_primary()))
      first_val = hd(vals)
      shifted_vals = tl(vals)

      Enum.zip(Enum.slice(args, 0..-2//1), shifted_vals)
      |> Enum.each(fn {p, v} -> do_eval_setf_place(p, v, env) end)

      first_val
    else
      nil
    end
  end

  defp eval_destructuring_bind([params_node, form_node | body_nodes], env) do
    val = eval(form_node, env)
    raw_args_sym = :__destruct_val__
    {bindings, _} = ExLisp.Macro.build_bindings(params_node, raw_args_sym, raw_args_sym)
    let_star = {:list, 1, [{:id, 1, ["let*"]}, {:list, 1, bindings} | body_nodes]}
    ref = make_ref()
    :erlang.put(ref, val)
    eval(let_star, Map.put(env, raw_args_sym, {:box, ref}))
  end

  defp eval_destructuring_bind([], _env), do: nil

  # --- Loop constructs ---

  defp eval_loop(args, env) do
    if ExLisp.Loop.extended_loop?(args) do
      expanded = ExLisp.Loop.expand(args)
      eval(expanded, env)
    else
      tag = {:block, nil, make_ref()}
      new_env = Map.put(env, {:block, nil}, tag)

      try do
        eval_infinite_loop(args, new_env)
      catch
        {:block_return, ^tag, val} -> val
      end
    end
  end

  defp eval_infinite_loop(body, env) do
    eval_progn(body, env)
    eval_infinite_loop(body, env)
  end

  defp eval_dotimes(args, env) do
    case args do
      [{:list, _, [var_node, count_node | res_nodes]} | body_nodes] ->
        var_sym = LispBeam.extract_symbol_name(var_node)
        count = eval(count_node, env) |> Builtins.unwrap_mv_primary()

        res_node =
          case res_nodes do
            [r | _] -> r
            [] -> {:lit, nil}
          end

        tag = {:block, nil, make_ref()}
        block_env = Map.put(env, {:block, nil}, tag)
        var_ref = make_ref()
        loop_env = Map.put(block_env, var_sym, {:box, var_ref})

        try do
          do_eval_dotimes(0, count, var_ref, body_nodes, loop_env)
          :erlang.put(var_ref, count)
          eval(res_node, loop_env)
        catch
          {:block_return, ^tag, val} -> val
        end

      _ ->
        nil
    end
  end

  defp do_eval_dotimes(i, count, var_ref, body_nodes, env) do
    if i < count do
      :erlang.put(var_ref, i)

      if Enum.any?(body_nodes, &is_tag_elem?/1) do
        eval_tagbody(body_nodes, env)
      else
        eval_progn(body_nodes, env)
      end

      do_eval_dotimes(i + 1, count, var_ref, body_nodes, env)
    end
  end

  defp eval_dolist(args, env) do
    case args do
      [{:list, _, [var_node, list_node | res_nodes]} | body_nodes] ->
        var_sym = LispBeam.extract_symbol_name(var_node)
        list_val = eval(list_node, env) |> Builtins.unwrap_mv_primary()

        res_node =
          case res_nodes do
            [r | _] -> r
            [] -> {:lit, nil}
          end

        tag = {:block, nil, make_ref()}
        block_env = Map.put(env, {:block, nil}, tag)
        var_ref = make_ref()
        loop_env = Map.put(block_env, var_sym, {:box, var_ref})

        items =
          case list_val do
            nil -> []
            l when is_list(l) -> l
            _ -> []
          end

        try do
          Enum.each(items, fn item ->
            :erlang.put(var_ref, item)

            if Enum.any?(body_nodes, &is_tag_elem?/1) do
              eval_tagbody(body_nodes, loop_env)
            else
              eval_progn(body_nodes, loop_env)
            end
          end)

          :erlang.put(var_ref, nil)
          eval(res_node, loop_env)
        catch
          {:block_return, ^tag, val} -> val
        end

      _ ->
        nil
    end
  end

  defp eval_tagbody(elements, env) do
    raw_segments =
      Enum.reduce(elements, [{:__start__, []}], fn elem, acc ->
        if is_tag_elem?(elem) do
          tag = LispBeam.extract_symbol_name(elem)
          [{tag, []} | acc]
        else
          [{current_tag, exprs} | rest] = acc
          [{current_tag, exprs ++ [elem]} | rest]
        end
      end)
      |> Enum.reverse()

    tag_order = Enum.map(raw_segments, &elem(&1, 0))
    tag_map = Map.new(raw_segments)
    tagbody_id = make_ref()

    tagbody_env =
      Enum.reduce(tag_order, env, fn tag, acc ->
        Map.put(acc, {:tag, tag}, tagbody_id)
      end)

    run_tagbody_loop(:__start__, tag_order, tag_map, tagbody_env, tagbody_id)
    nil
  end

  defp is_tag_elem?({:list, _, _}), do: false
  defp is_tag_elem?({:quoted, _, _}), do: false
  defp is_tag_elem?(_), do: true

  defp run_tagbody_loop(nil, _tag_order, _tag_map, _env, _tagbody_id), do: nil

  defp run_tagbody_loop(current_tag, tag_order, tag_map, env, tagbody_id) do
    exprs = Map.get(tag_map, current_tag, [])
    next_tag = get_next_tagbody_tag(current_tag, tag_order)

    try do
      eval_progn(exprs, env)
      run_tagbody_loop(next_tag, tag_order, tag_map, env, tagbody_id)
    catch
      {:lisp_go, ^tagbody_id, target_tag} ->
        run_tagbody_loop(target_tag, tag_order, tag_map, env, tagbody_id)

      {:lisp_go, nil, target_tag} ->
        if Map.has_key?(tag_map, target_tag) do
          run_tagbody_loop(target_tag, tag_order, tag_map, env, tagbody_id)
        else
          throw({:lisp_go, nil, target_tag})
        end
    end
  end

  defp get_next_tagbody_tag(current_tag, tag_order) do
    case Enum.drop_while(tag_order, &(&1 != current_tag)) do
      [^current_tag, next | _] -> next
      _ -> nil
    end
  end

  # --- Condition & Error System ---

  defp eval_handler_bind([bindings_node | body_nodes], env) do
    binding_pairs =
      case bindings_node do
        {:list, _, list} -> list
        list when is_list(list) -> list
        _ -> []
      end

    handlers =
      Enum.map(binding_pairs, fn
        {:list, _, [type_node, fn_node | _]} ->
          {LispBeam.extract_symbol_name(type_node), eval(fn_node, env)}

        [type_node, fn_node | _] ->
          {LispBeam.extract_symbol_name(type_node), eval(fn_node, env)}
      end)

    ExLisp.Condition.push_handlers(handlers, fn -> eval_progn(body_nodes, env) end)
  end

  defp eval_handler_case([expr_node | clauses], env) do
    {no_error_clause, normal_clauses} =
      Enum.split_with(clauses, fn
        {:list, _, [type_spec | _]} ->
          LispBeam.extract_symbol_name(type_spec) in [:no_error, :_cl_no_error_, :":no-error"]

        [type_spec | _] ->
          LispBeam.extract_symbol_name(type_spec) in [:no_error, :_cl_no_error_, :":no-error"]

        _ ->
          false
      end)

    no_error_fn =
      case no_error_clause do
        [{:list, _, [_no_err_sym, params_node | body_nodes]} | _] ->
          var_names = LispBeam.extract_param_names(params_node)

          fn result ->
            vals = extract_values(result)
            padded = vals ++ List.duplicate(nil, max(0, length(var_names) - length(vals)))

            call_env =
              Enum.zip(var_names, padded)
              |> Enum.reduce(env, fn {var, val}, acc ->
                ref = make_ref()
                :erlang.put(ref, val)
                Map.put(acc, var, {:box, ref})
              end)

            eval_progn(body_nodes, call_env)
          end

        _ ->
          nil
      end

    parsed_clauses =
      Enum.map(normal_clauses, fn
        {:list, _, [type_spec, params_node | body_nodes]} ->
          type_name = LispBeam.extract_symbol_name(type_spec)

          param_var =
            case params_node do
              {:list, _, [p | _]} -> LispBeam.extract_symbol_name(p)
              [p | _] -> LispBeam.extract_symbol_name(p)
              p when p != nil and p != [] -> LispBeam.extract_symbol_name(p)
              _ -> nil
            end

          handler_fn = fn cond_obj ->
            call_env =
              if param_var do
                ref = make_ref()
                :erlang.put(ref, cond_obj)
                Map.put(env, param_var, {:box, ref})
              else
                env
              end

            eval_progn(body_nodes, call_env)
          end

          {type_name, handler_fn}
      end)

    ExLisp.Condition.run_handler_case(fn -> eval(expr_node, env) end, parsed_clauses, no_error_fn)
  end

  defp eval_restart_bind([bindings_node | body_nodes], env) do
    binding_pairs =
      case bindings_node do
        {:list, _, list} -> list
        list when is_list(list) -> list
        _ -> []
      end

    restarts =
      Enum.map(binding_pairs, fn
        {:list, _, [name_node, fn_node | _]} ->
          {LispBeam.extract_symbol_name(name_node), eval(fn_node, env)}

        [name_node, fn_node | _] ->
          {LispBeam.extract_symbol_name(name_node), eval(fn_node, env)}
      end)

    ExLisp.Condition.push_restarts(restarts, fn -> eval_progn(body_nodes, env) end)
  end

  defp eval_restart_case([expr_node | clauses], env) do
    parsed_clauses =
      Enum.map(clauses, fn clause ->
        {name_node, params_node, rest_nodes} =
          case clause do
            {:list, _, [n, p | r]} -> {n, p, r}
            [n, p | r] -> {n, p, r}
            {:list, _, [n]} -> {n, nil, []}
            [n] -> {n, nil, []}
          end

        name = LispBeam.extract_symbol_name(name_node)
        {options, handler_body} = parse_restart_case_options(rest_nodes)

        params =
          case params_node do
            {:list, _, ps} -> Enum.map(ps, &LispBeam.extract_symbol_name/1)
            ps when is_list(ps) -> Enum.map(ps, &LispBeam.extract_symbol_name/1)
            nil -> []
            p -> [LispBeam.extract_symbol_name(p)]
          end

        handler_fn = fn args ->
          args_list = if is_list(args), do: args, else: [args]
          padded = args_list ++ List.duplicate(nil, max(0, length(params) - length(args_list)))

          call_env =
            Enum.zip(params, padded)
            |> Enum.reduce(env, fn {var, val}, acc ->
              ref = make_ref()
              :erlang.put(ref, val)
              Map.put(acc, var, {:box, ref})
            end)

          eval_progn(handler_body, call_env)
        end

        report_val =
          case Keyword.get(options, :report) do
            nil -> nil
            rep_node when is_binary(rep_node) -> rep_node
            rep_node -> eval(rep_node, env)
          end

        test_val =
          case Keyword.get(options, :test) do
            nil -> nil
            test_node -> eval(test_node, env)
          end

        %{
          name: name,
          fun: handler_fn,
          report: report_val,
          test: test_val
        }
      end)

    ExLisp.Condition.run_restart_case(fn -> eval(expr_node, env) end, parsed_clauses)
  end

  defp parse_restart_case_options(nodes) do
    do_parse_restart_case_options(nodes, [])
  end

  defp do_parse_restart_case_options([], acc), do: {Enum.reverse(acc), []}

  defp do_parse_restart_case_options([node, val | rest], acc) do
    key_name =
      case node do
        {:keyword, _, kw} -> to_string(kw)
        {:id, _, [kw]} -> to_string(kw)
        {:lit, kw} -> to_string(kw)
        {:atom, _, kw} -> to_string(kw)
        kw when is_atom(kw) or is_binary(kw) -> to_string(kw)
        _ -> nil
      end

    if key_name && (String.starts_with?(key_name, ":") or match?({:keyword, _, _}, node)) do
      key = key_name |> String.trim_leading(":") |> String.to_atom()
      do_parse_restart_case_options(rest, [{key, val} | acc])
    else
      {Enum.reverse(acc), [node, val | rest]}
    end
  end

  defp do_parse_restart_case_options(body_nodes, acc), do: {Enum.reverse(acc), body_nodes}

  defp eval_define_condition([name_node, parents_node | rest_nodes], _env) do
    cond_name = LispBeam.extract_symbol_name(name_node)

    parents =
      case parents_node do
        {:list, _, p_list} ->
          Enum.map(p_list, &LispBeam.extract_symbol_name/1)

        {:quoted, _, p_list} when is_list(p_list) ->
          Enum.map(p_list, &LispBeam.extract_symbol_name/1)

        nil ->
          [:condition]

        _ ->
          [LispBeam.extract_symbol_name(parents_node)]
      end

    slot_nodes =
      case rest_nodes do
        [{:list, _pos, slots} | _] -> slots
        [slots | _] when is_list(slots) -> slots
        _ -> []
      end

    raw_slots =
      Enum.map(slot_nodes, fn
        {:list, _pos, [s_name_node | s_opts]} ->
          [LispBeam.extract_symbol_name(s_name_node) | Enum.map(s_opts, &eval_quote_node/1)]

        s_name_node ->
          LispBeam.extract_symbol_name(s_name_node)
      end)

    options_nodes =
      case rest_nodes do
        [_slots | opts] -> opts
        _ -> []
      end

    raw_opts =
      Enum.map(options_nodes, fn
        {:list, _pos, [opt_k | opt_v]} ->
          [LispBeam.extract_symbol_name(opt_k) | Enum.map(opt_v, &eval_quote_node/1)]

        opt ->
          LispBeam.extract_symbol_name(opt)
      end)

    ExLisp.Condition.define_condition(cond_name, parents, raw_slots, raw_opts)
    cond_name
  end

  # --- Streams & Files ---

  defp eval_with_open_file(args, env) do
    case args do
      [{:list, _, [stream_var_node, filespec_node | options]} | body_nodes] ->
        stream_var = LispBeam.extract_symbol_name(stream_var_node)
        filespec = eval(filespec_node, env) |> Builtins.unwrap_mv_primary()
        opt_args = Enum.map(options, &(eval(&1, env) |> Builtins.unwrap_mv_primary()))
        stream = Builtins.open(filespec, opt_args)
        ref = make_ref()
        :erlang.put(ref, stream)

        try do
          call_env = Map.put(env, stream_var, {:box, ref})
          eval_progn(body_nodes, call_env)
        after
          Builtins.close(stream)
        end

      _ ->
        nil
    end
  end

  defp eval_with_open_stream(args, env) do
    case args do
      [{:list, _, [var_node, stream_node]} | body_nodes] ->
        var_sym = LispBeam.extract_symbol_name(var_node)
        stream = eval(stream_node, env) |> Builtins.unwrap_mv_primary()
        ref = make_ref()
        :erlang.put(ref, stream)

        try do
          call_env = Map.put(env, var_sym, {:box, ref})
          eval_progn(body_nodes, call_env)
        after
          Builtins.close(stream)
        end

      _ ->
        nil
    end
  end

  defp eval_with_input_from_string(args, env) do
    case args do
      [{:list, _, [var_node, string_node | _opts]} | body_nodes] ->
        var_sym = LispBeam.extract_symbol_name(var_node)
        str_val = eval(string_node, env) |> Builtins.unwrap_mv_primary()
        stream = Builtins.make_string_input_stream(str_val)
        ref = make_ref()
        :erlang.put(ref, stream)

        try do
          call_env = Map.put(env, var_sym, {:box, ref})
          eval_progn(body_nodes, call_env)
        after
          Builtins.close(stream)
        end

      _ ->
        nil
    end
  end

  defp eval_with_output_to_string(args, env) do
    case args do
      [{:list, _, [var_node | _opts]} | body_nodes] ->
        var_sym = LispBeam.extract_symbol_name(var_node)
        stream = Builtins.make_string_output_stream()
        ref = make_ref()
        :erlang.put(ref, stream)

        try do
          call_env = Map.put(env, var_sym, {:box, ref})
          eval_progn(body_nodes, call_env)
          Builtins.get_output_stream_string(stream)
        after
          Builtins.close(stream)
        end

      _ ->
        nil
    end
  end

  defp eval_with_mutex(args, env) do
    case args do
      [{:list, _, [mutex_node | _opts]} | body_nodes] ->
        mutex = eval(mutex_node, env) |> Builtins.unwrap_mv_primary()
        ExLisp.SBCLCompat.grab_mutex(mutex)

        try do
          eval_progn(body_nodes, env)
        after
          ExLisp.SBCLCompat.release_mutex(mutex)
        end

      _ ->
        nil
    end
  end

  # --- CLOS & Structs ---

  defp eval_defstruct([name_spec | slot_specs], env) do
    struct_name =
      case name_spec do
        {:list, _pos, [name | _]} -> LispBeam.extract_symbol_name(name)
        _ -> LispBeam.extract_symbol_name(name_spec)
      end

    parsed_slots =
      Enum.map(slot_specs, fn
        {:list, _pos, [slot_name, default_val | _]} ->
          {LispBeam.extract_symbol_name(slot_name), eval(default_val, env)}

        slot_name ->
          {LispBeam.extract_symbol_name(slot_name), nil}
      end)

    # make-<struct>
    make_fn = fn passed_args ->
      Builtins.make_struct(struct_name, parsed_slots, passed_args)
    end

    Env.put_fun(:"make_#{struct_name}", ExLisp.Closure.new(make_fn, :"make_#{struct_name}"))

    # <struct>-p
    p_fn = fn [s | _] ->
      case s do
        {:struct, ^struct_name, _} -> :t
        _ -> nil
      end
    end

    Env.put_fun(:"#{struct_name}_p", ExLisp.Closure.new(p_fn, :"#{struct_name}_p"))

    # copy-<struct>
    copy_fn = fn [s | _] -> Builtins.copy_struct(s) end
    Env.put_fun(:"copy_#{struct_name}", ExLisp.Closure.new(copy_fn, :"copy_#{struct_name}"))

    # <struct>-<slot> accessors
    Enum.each(parsed_slots, fn {slot, _} ->
      acc_fn = fn [s | _] -> Builtins.get_struct_slot(s, slot) end

      Env.put_fun(
        :"#{struct_name}_#{slot}",
        ExLisp.Closure.new(acc_fn, :"#{struct_name}_#{slot}")
      )
    end)

    struct_name
  end

  defp eval_defclass([name_node, superclasses_node | rest], _env) do
    name = LispBeam.extract_symbol_name(name_node)

    supers =
      case superclasses_node do
        {:list, _, s_list} -> Enum.map(s_list, &LispBeam.extract_symbol_name/1)
        _ -> []
      end

    slots =
      case rest do
        [{:list, _, s_nodes} | _] -> s_nodes
        _ -> []
      end

    options =
      case rest do
        [_slots | opts] -> opts
        _ -> []
      end

    ExLisp.CLOS.register_class(name, supers, slots, options)
    name
  end

  defp eval_defgeneric([name_node, params_node | options], _env) do
    name = LispBeam.extract_symbol_name(name_node)
    ExLisp.CLOS.register_generic(name, params_node, options)
    name
  end

  defp eval_defmethod(args, env) do
    {name_node, qualifier, params_node, body_nodes} = extract_qualifier_and_rest(args)
    method_name = LispBeam.extract_symbol_name(name_node)

    param_list =
      case params_node do
        {:list, _pos, elems} -> elems
        elems when is_list(elems) -> elems
        _ -> []
      end

    {param_names, raw_specializers} = parse_method_params(param_list, env)

    method_fun = fn passed_args ->
      norm_args = normalize_raw_args(passed_args)
      padded = norm_args ++ List.duplicate(nil, max(0, length(param_names) - length(norm_args)))

      call_env =
        Enum.zip(param_names, padded)
        |> Enum.reduce(env, fn {var, val}, acc ->
          ref = make_ref()
          :erlang.put(ref, val)
          Map.put(acc, var, {:box, ref})
        end)

      tag = {:block, method_name, make_ref()}
      block_env = Map.put(call_env, {:block, method_name}, tag)

      try do
        eval_progn(body_nodes, block_env)
      catch
        {:block_return, ^tag, val} -> val
      end
    end

    ExLisp.CLOS.register_method(method_name, qualifier, raw_specializers, method_fun)
    method_name
  end

  defp extract_qualifier_and_rest(args) do
    case args do
      [name_node, qual_node, params_node | body] ->
        case extract_qualifier(qual_node) do
          {:ok, q} -> {name_node, q, params_node, body}
          :error -> {name_node, nil, qual_node, [params_node | body]}
        end

      [name_node, params_node | body] ->
        {name_node, nil, params_node, body}

      [name_node] ->
        {name_node, nil, {:list, 1, []}, []}
    end
  end

  defp extract_qualifier(node) do
    case node do
      {:lit, kw} when is_atom(kw) ->
        str = kw |> Atom.to_string() |> String.trim_leading(":") |> String.downcase()
        if str in ["before", "after", "around"], do: {:ok, String.to_atom(str)}, else: :error

      {:keyword, _, kw} ->
        str = kw |> Atom.to_string() |> String.trim_leading(":") |> String.downcase()
        if str in ["before", "after", "around"], do: {:ok, String.to_atom(str)}, else: :error

      {:id, _, [str_id]} ->
        str = str_id |> String.trim_leading(":") |> String.downcase()
        if str in ["before", "after", "around"], do: {:ok, String.to_atom(str)}, else: :error

      _ ->
        :error
    end
  end

  defp parse_method_params(param_list, env) do
    Enum.map(param_list, fn
      {:list, _pos, [p, {:list, _, [{:id, _, [eql_name]}, val_node]} | _]}
      when eql_name in ["eql", "EQL"] ->
        p_name = LispBeam.extract_symbol_name(p)
        val = eval(val_node, env) |> Builtins.unwrap_mv_primary()
        {p_name, {:eql, val}}

      {:list, _pos, [p, spec_node | _]} ->
        p_name = LispBeam.extract_symbol_name(p)
        spec = LispBeam.extract_symbol_name(spec_node)
        {p_name, spec}

      p ->
        p_name = LispBeam.extract_symbol_name(p)
        {p_name, :t}
    end)
    |> Enum.reduce({[], []}, fn {p_name, raw_spec}, {p_acc, raw_acc} ->
      {p_acc ++ [p_name], raw_acc ++ [raw_spec]}
    end)
  end

  defp extract_deftype_params({:list, _pos, elems}),
    do: Enum.map(elems, &extract_symbol_or_spec/1)

  defp extract_deftype_params({:quoted, _pos, elems}),
    do: Enum.map(elems, &extract_symbol_or_spec/1)

  defp extract_deftype_params([]), do: []
  defp extract_deftype_params(nil), do: []
  defp extract_deftype_params(other), do: [extract_symbol_or_spec(other)]

  defp extract_symbol_or_spec({:list, _pos, [var, def_val | _]}) do
    [LispBeam.extract_symbol_name(var), eval_ast_to_lit(def_val)]
  end

  defp extract_symbol_or_spec(node), do: LispBeam.extract_symbol_name(node)

  defp eval_ast_to_lit({:lit, v}), do: v
  defp eval_ast_to_lit({:id, _, [s]}), do: String.to_atom(s)
  defp eval_ast_to_lit({:quoted, _, node}), do: eval_ast_to_lit(node)
  defp eval_ast_to_lit(_), do: :*

  # --- Flet / Labels / Macrolet / Symbol-macrolet ---

  defp eval_flet([bindings_node | body_nodes], env) do
    fn_defs = LispBeam.extract_fn_bindings(bindings_node)

    closures =
      Enum.map(fn_defs, fn {name, params_node, fn_body} ->
        closure = create_closure(params_node, fn_body, env, name)
        {{:fun, name}, closure}
      end)

    new_env = Map.merge(env, Map.new(closures))
    eval_progn(body_nodes, new_env)
  end

  defp eval_flet([], _env), do: nil

  defp eval_labels([bindings_node | body_nodes], env) do
    fn_defs = LispBeam.extract_fn_bindings(bindings_node)
    dispatcher_ref = make_ref()

    closures =
      Enum.map(fn_defs, fn {name, _params, _} ->
        wrapper = fn args_list ->
          actual_env = :erlang.get(dispatcher_ref)
          fun = Map.get(actual_env, {:fun, name})
          Builtins.invoke_fn(fun, args_list)
        end

        {{:fun, name}, ExLisp.Closure.new(wrapper, name)}
      end)

    rec_env = Map.merge(env, Map.new(closures))

    actual_closures =
      Enum.map(fn_defs, fn {name, params_node, fn_body} ->
        closure = create_closure(params_node, fn_body, rec_env, name)
        {{:fun, name}, closure}
      end)

    final_env = Map.merge(rec_env, Map.new(actual_closures))
    :erlang.put(dispatcher_ref, final_env)

    try do
      eval_progn(body_nodes, final_env)
    after
      :erlang.erase(dispatcher_ref)
    end
  end

  defp eval_labels([], _env), do: nil

  defp eval_macrolet([bindings_node | body_nodes], env) do
    macro_defs = LispBeam.extract_fn_bindings(bindings_node)

    macro_bindings =
      Enum.map(macro_defs, fn {name, params_node, fn_body} ->
        lambda_ast = ExLisp.Macro.build_macro_lambda(params_node, fn_body)
        macro_fun = eval(lambda_ast, env)
        {{:macro, name}, macro_fun}
      end)

    new_env = Map.merge(env, Map.new(macro_bindings))
    eval_progn(body_nodes, new_env)
  end

  defp eval_macrolet([], _env), do: nil

  defp eval_symbol_macrolet([bindings_node | body_nodes], env) do
    bindings = LispBeam.extract_bindings(bindings_node)

    macro_bindings =
      Enum.map(bindings, fn {sym, expansion_ast} ->
        {{:symbol_macro, sym}, expansion_ast}
      end)

    new_env = Map.merge(env, Map.new(macro_bindings))
    eval_progn(body_nodes, new_env)
  end

  defp eval_symbol_macrolet([], _env), do: nil

  # --- Function / Closure creation ---

  defp eval_function(args, env) do
    case args do
      [{:list, _pos, [lambda_op | lambda_args]}] ->
        if LispBeam.extract_op_name(lambda_op) in [:lambda, :_cl_lambda_] do
          case lambda_args do
            [params_node | body_nodes] -> create_closure(params_node, body_nodes, env, nil)
            _ -> nil
          end
        else
          fn_sym = LispBeam.extract_symbol_name(lambda_op)
          lookup_function_symbol(fn_sym, env)
        end

      [fn_node] ->
        fn_sym = LispBeam.extract_symbol_name(fn_node)
        lookup_function_symbol(fn_sym, env)

      _ ->
        nil
    end
  end

  defp lookup_function_symbol(fn_sym, env) when is_atom(fn_sym) do
    cond do
      Map.has_key?(env, {:fun, fn_sym}) ->
        Map.get(env, {:fun, fn_sym})

      true ->
        case BuiltinFunction.canonical_name(fn_sym) do
          {:ok, c} ->
            c

          :error ->
            if Env.has_fun?(fn_sym) do
              Env.get_fun(fn_sym)
            else
              fn_sym
            end
        end
    end
  end

  @doc """
  Creates a closure function wrapping parameter binding and body evaluation.
  """
  def create_closure(params_node, body_nodes, captured_env, name \\ nil) do
    tag = {:block, name, make_ref()}
    snapshotted_env = snapshot_env(captured_env)

    if LispBeam.has_lambda_list_keywords?(params_node) do
      # Use Macro.build_bindings to expand &optional, &rest, &key, etc.
      args_sym = :__fn_args__
      {bindings, _} = ExLisp.Macro.build_bindings(params_node, args_sym, args_sym)

      let_star_body =
        {:list, 1,
         [
           {:id, 1, ["let*"]},
           {:list, 1, bindings}
           | body_nodes
         ]}

      fun = fn passed_args ->
        ref = make_ref()
        :erlang.put(ref, passed_args)
        call_env = Map.put(snapshotted_env, args_sym, {:box, ref})
        block_env = if name, do: Map.put(call_env, {:block, name}, tag), else: call_env

        try do
          eval(let_star_body, block_env)
        catch
          {:block_return, ^tag, val} -> val
        end
      end

      ExLisp.Closure.new(fun, name)
    else
      param_names = LispBeam.extract_param_names(params_node)

      base_fun = fn passed_args ->
        norm_args = normalize_raw_args(passed_args)
        padded = norm_args ++ List.duplicate(nil, max(0, length(param_names) - length(norm_args)))
        bindings = Enum.zip(param_names, padded)

        call_env =
          Enum.reduce(bindings, snapshotted_env, fn {p_name, val}, acc ->
            ref = make_ref()
            :erlang.put(ref, val)
            Map.put(acc, p_name, {:box, ref})
          end)

        block_env = if name, do: Map.put(call_env, {:block, name}, tag), else: call_env

        try do
          eval_progn(body_nodes, block_env)
        catch
          {:block_return, ^tag, val} -> val
        end
      end

      case length(param_names) do
        0 -> fn -> base_fun.([]) end
        1 -> fn a -> base_fun.([a]) end
        2 -> fn a, b -> base_fun.([a, b]) end
        3 -> fn a, b, c -> base_fun.([a, b, c]) end
        4 -> fn a, b, c, d -> base_fun.([a, b, c, d]) end
        5 -> fn a, b, c, d, e -> base_fun.([a, b, c, d, e]) end
        6 -> fn a, b, c, d, e, f -> base_fun.([a, b, c, d, e, f]) end
        7 -> fn a, b, c, d, e, f, g -> base_fun.([a, b, c, d, e, f, g]) end
        8 -> fn a, b, c, d, e, f, g, h -> base_fun.([a, b, c, d, e, f, g, h]) end
        _ -> ExLisp.Closure.new(base_fun, name)
      end
    end
  end

  defp snapshot_env(env) do
    Enum.into(env, %{}, fn
      {k, {:box, ref}} ->
        val =
          case :erlang.get(ref) do
            :undefined -> nil
            v -> v
          end

        {k, {:box, ref, val}}

      {k, {:box, ref, old_val}} ->
        val =
          case :erlang.get(ref) do
            :undefined -> old_val
            v -> v
          end

        {k, {:box, ref, val}}

      pair ->
        pair
    end)
  end

  defp rewrite_mv_form(form) do
    case form do
      {:list, pos, [{:id, id_pos, [op_name]} | form_args]} ->
        normalized = op_name |> String.downcase() |> String.replace("-", "_")

        case normalized do
          "gethash" ->
            {:list, pos, [{:id, id_pos, ["gethash_mv"]} | form_args]}

          "read_line" ->
            {:list, pos, [{:id, id_pos, ["read_line_mv"]} | form_args]}

          "parse_namestring" ->
            {:list, pos, [{:id, id_pos, ["parse_namestring_mv"]} | form_args]}

          _ ->
            form
        end

      {:quoted, pos, [{:id, id_pos, [op_name]} | form_args]} ->
        normalized = op_name |> String.downcase() |> String.replace("-", "_")

        case normalized do
          "gethash" ->
            {:quoted, pos, [{:id, id_pos, ["gethash_mv"]} | form_args]}

          "read_line" ->
            {:quoted, pos, [{:id, id_pos, ["read_line_mv"]} | form_args]}

          "parse_namestring" ->
            {:quoted, pos, [{:id, id_pos, ["parse_namestring_mv"]} | form_args]}

          _ ->
            form
        end

      _ ->
        form
    end
  end

  defp extract_docstring({:lit, doc}) when is_binary(doc), do: doc
  defp extract_docstring({:string, _pos, doc}) when is_list(doc), do: List.to_string(doc)
  defp extract_docstring({:string, _pos, doc}) when is_binary(doc), do: doc
  defp extract_docstring(doc) when is_binary(doc), do: doc
  defp extract_docstring(_), do: nil

  defp normalize_raw_args(nil), do: []
  defp normalize_raw_args([]), do: []
  defp normalize_raw_args([head | tail]), do: [head | normalize_raw_args(tail)]
  defp normalize_raw_args(other), do: [other]

  # --- Quote helpers ---

  defp eval_quote_node({:id, _pos, parts}) do
    Enum.join(parts, ".") |> LispBeam.normalize_quote_symbol()
  end

  defp eval_quote_node({:lit, val}), do: val
  defp eval_quote_node({:lit, _pos, val}), do: val
  defp eval_quote_node({:atom, _pos, val}), do: val
  defp eval_quote_node({:integer, _pos, val}), do: val
  defp eval_quote_node({:float, _pos, val}), do: val
  defp eval_quote_node({:string, _pos, val}) when is_list(val), do: List.to_string(val)
  defp eval_quote_node({:string, _pos, val}), do: to_string(val)

  defp eval_quote_node({:bin, _pos, [{:bin_element, _, {:string, _, chars}, _, _}]}),
    do: to_string(chars)

  defp eval_quote_node({:char, _pos, code}), do: ExLisp.Character.new(code)
  defp eval_quote_node({nil, _pos}), do: nil

  defp eval_quote_node(val) when is_integer(val) or is_float(val) or is_binary(val), do: val
  defp eval_quote_node(%ExLisp.Ratio{} = val), do: val
  defp eval_quote_node(%ExLisp.Character{} = val), do: val
  defp eval_quote_node({:keyword, _pos, kw}), do: kw

  defp eval_quote_node({:vector, _pos, elements}) do
    eval_quote_elements(elements) |> Builtins.vector()
  end

  defp eval_quote_node({:quoted, _pos, elements}) when is_list(elements) do
    eval_quote_elements(elements)
  end

  defp eval_quote_node({:quoted, _pos, element}), do: eval_quote_node(element)
  defp eval_quote_node({:list, _pos, elements}), do: eval_quote_elements(elements)

  defp eval_quote_node({:dotted_list, _pos, elements, tail}) do
    head_vals = eval_quote_elements(elements)
    tail_val = eval_quote_node(tail)
    make_improper_list(head_vals, tail_val)
  end

  defp eval_quote_node([]), do: nil
  defp eval_quote_node(nil), do: nil
  defp eval_quote_node(other), do: other

  defp eval_quote_elements(elements) do
    Enum.map(elements, &eval_quote_node/1)
  end

  defp make_improper_list([], tail), do: tail
  defp make_improper_list([h | rest], tail), do: [h | make_improper_list(rest, tail)]

  # --- Values helpers ---

  defp extract_values([:_values_, vals]) when is_list(vals), do: vals
  defp extract_values([:_values_ | vals]) when is_list(vals), do: vals
  defp extract_values(single), do: [single]
end
