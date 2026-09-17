defmodule ExLisp.Builtins do
  @moduledoc """
  Implementation module for Common Lisp (SBCL-compliant) built-in functions and predicates.
  """

  import Kernel,
    except: [
      apply: 2,
      length: 1,
      min: 2,
      max: 2,
      round: 1,
      floor: 1,
      ceil: 1,
      abs: 1,
      trunc: 1,
      rem: 2
    ]

  import Bitwise

  # --- Boolean / nil handling ---

  @doc """
  Determines the truthiness in Lisp.
  nil, :nil, false, and [] are false; everything else is true.
  """
  def truthy?([:_values_, [first | _]]), do: truthy?(first)
  def truthy?([:_values_, []]), do: false
  def truthy?([:_values_ | _]), do: false

  def truthy?(val) do
    val != nil and val != false and val != []
  end

  @doc """
  Converts an Elixir boolean into a Lisp boolean (:t or nil).
  """
  def lisp_bool(true), do: :t
  def lisp_bool(false), do: nil

  def lisp_bool(val) do
    if truthy?(val), do: :t, else: nil
  end

  @variadic_builtins MapSet.new([
                       :r,
                       :v,
                       :append,
                       :values,
                       :values_list,
                       :map,
                       :every,
                       :some,
                       :notany,
                       :notevery,
                       :position,
                       :position_if,
                       :position_if_not,
                       :find,
                       :find_if,
                       :find_if_not,
                       :count,
                       :count_if,
                       :count_if_not,
                       :string_upcase,
                       :string_downcase,
                       :string_capitalize,
                       :nstring_upcase,
                       :nstring_downcase,
                       :nstring_capitalize,
                       :string_trim,
                       :string_left_trim,
                       :string_right_trim,
                       :remove,
                       :remove_if,
                       :remove_if_not,
                       :remove_duplicates,
                       :delete_duplicates,
                       :substitute,
                       :substitute_if,
                       :substitute_if_not,
                       :mismatch,
                       :fill,
                       :replace,
                       :char_eq,
                       :char_neq,
                       :char_lt,
                       :char_lte,
                       :char_gt,
                       :char_gte,
                       :char_equal,
                       :char_not_equal,
                       :char_lessp,
                       :char_greaterp,
                       :char_not_greaterp,
                       :char_not_lessp,
                       :string_not_greaterp,
                       :string_not_lessp,
                       :string_eq,
                       :string_neq,
                       :string_lt,
                       :string_lte,
                       :string_gt,
                       :string_gte,
                       :string_equal,
                       :string_not_equal,
                       :string_lessp,
                       :string_greaterp,
                       :union,
                       :nunion,
                       :intersection,
                       :nintersection,
                       :set_difference,
                       :nset_difference,
                       :set_exclusive_or,
                       :nset_exclusive_or,
                       :subsetp,
                       :member,
                       :member_if,
                       :member_if_not,
                       :assoc,
                       :assoc_if,
                       :assoc_if_not,
                       :rassoc,
                       :rassoc_if,
                       :rassoc_if_not,
                       :adjoin,
                       :subst,
                       :nsubst,
                       :subst_if,
                       :nsubst_if,
                       :subst_if_not,
                       :nsubst_if_not,
                       :sublis,
                       :nsublis,
                       :tree_equal,
                       :pairlis,
                       :copy_list,
                       :copy_alist,
                       :copy_tree,
                       :revappend,
                       :nreconc,
                       :nconc,
                       :tailp,
                       :ldiff,
                       :last,
                       :butlast,
                       :nbutlast,
                       :getf,
                       :remf,
                       :get_properties,
                       :mapc,
                       :mapcar,
                       :mapcan,
                       :maplist,
                       :mapl,
                       :mapcon,
                       :make_list,
                       :make_sequence,
                       :concatenate,
                       :search,
                       :map_into,
                       :reduce,
                       :merge,
                       :delete,
                       :delete_if,
                       :delete_if_not,
                       :nsubstitute,
                       :nsubstitute_if,
                       :nsubstitute_if_not,
                       :subseq,
                       :sort,
                       :stable_sort,
                       :elt,
                       :array_row_major_index,
                       :compile,
                       :export,
                       :use_package,
                       :shadow,
                       :shadowing_import,
                       :import,
                       :provide,
                       :require,
                       :parse_integer,
                       :make_string,
                       :make_string_output_stream,
                       :make_array,
                       :vector,
                       :aref,
                       :make_symbol,
                       :copy_symbol,
                       :special_operator_p,
                       :logand,
                       :logior,
                       :logxor,
                       :logeqv,
                       :quickload,
                       :system_apropos,
                       :where_is_system,
                       :hex_install,
                       :hex_search,
                       :hex_info,
                       :hex_where_is_package,
                       :quit
                     ])

  def unwrap_mv_primary([:_values_, [first | _]]), do: first
  def unwrap_mv_primary([:_values_, []]), do: nil
  def unwrap_mv_primary([:_values_ | _]), do: nil
  def unwrap_mv_primary(other), do: other

  defp normalize_raw_args(nil), do: []
  defp normalize_raw_args([]), do: []
  defp normalize_raw_args([head | tail]), do: [head | normalize_raw_args(tail)]
  defp normalize_raw_args(_other), do: []

  # --- Higher-order function invocation helper ---

  @doc """
  Invokes a function object or function name symbol with the given arguments list.
  """
  def invoke_fn(fn_val, [arg]) when is_function(fn_val, 1) do
    fn_val.(unwrap_mv_primary(arg))
  end

  def invoke_fn(fn_val, [a, b]) when is_function(fn_val, 2) do
    fn_val.(unwrap_mv_primary(a), unwrap_mv_primary(b))
  end

  def invoke_fn(fn_val, [a, b, c]) when is_function(fn_val, 3) do
    fn_val.(unwrap_mv_primary(a), unwrap_mv_primary(b), unwrap_mv_primary(c))
  end

  def invoke_fn(%ExLisp.Closure{fun: fun}, args) do
    norm_args = args |> normalize_raw_args() |> Enum.map(&unwrap_mv_primary/1)
    fun.(norm_args)
  end

  def invoke_fn(fn_val, args) when is_function(fn_val) do
    norm_args = args |> normalize_raw_args() |> Enum.map(&unwrap_mv_primary/1)

    cond do
      is_function(fn_val, length(norm_args)) ->
        Kernel.apply(fn_val, norm_args)

      true ->
        raise RuntimeError,
              "Invalid arity for function #{inspect(fn_val)} with #{length(norm_args)} arguments"
    end
  end

  def invoke_fn(sym, args) when is_atom(sym) and sym not in [nil, nil] do
    down_sym = sym |> Atom.to_string() |> String.downcase() |> String.to_atom()
    norm_args = args |> normalize_raw_args()

    case BuiltinFunction.canonical_name(down_sym) do
      {:ok, canonical} ->
        dispatch_builtin(canonical, norm_args)

      :error ->
        mapped_args = Enum.map(norm_args, &unwrap_mv_primary/1)

        cond do
          function_exported?(__MODULE__, down_sym, length(mapped_args)) ->
            Kernel.apply(__MODULE__, down_sym, mapped_args)

          ExLisp.Env.has_fun?(down_sym) ->
            ExLisp.Env.call_fun(down_sym, mapped_args)

          true ->
            raise RuntimeError, "Undefined function: #{inspect(sym)}"
        end
    end
  end

  def invoke_fn(other, _args) do
    raise RuntimeError, "Invalid function: #{inspect(other)}"
  end

  defp apply_key(nil, elem), do: elem
  defp apply_key(key_fn, elem), do: invoke_fn(key_fn, [elem])

  def funcall(fn_val, args) when is_list(args) do
    invoke_fn(fn_val, args)
  end

  def funcall(fn_val, a), do: invoke_fn(fn_val, [a])
  def funcall(fn_val, a, b), do: invoke_fn(fn_val, [a, b])
  def funcall(fn_val, a, b, c), do: invoke_fn(fn_val, [a, b, c])

  def apply(fn_val, args) when is_list(args) do
    flat_args =
      case args do
        [] ->
          []

        _ ->
          [last | rev_leading] = Enum.reverse(args)
          leading = Enum.reverse(rev_leading)

          trailing =
            cond do
              last in [nil, []] -> []
              is_list(last) -> last
              true -> [last]
            end

          leading ++ trailing
      end

    invoke_fn(fn_val, flat_args)
  end

  def identity(x), do: x

  def constantly(val) do
    %ExLisp.Closure{
      fun: fn _raw_args -> val end,
      name: :constantly,
      variadic: true
    }
  end

  def complement(pred) do
    %ExLisp.Closure{
      fun: fn raw_args ->
        res = invoke_fn(pred, raw_args)
        if truthy?(res), do: nil, else: :t
      end,
      name: :complement,
      variadic: true
    }
  end

  def values(), do: [:_values_, []]
  def values(args) when is_list(args), do: [:_values_, Enum.map(args, &unwrap_mv_primary/1)]
  def values(a), do: [:_values_, [unwrap_mv_primary(a)]]
  def values(a, b), do: [:_values_, [unwrap_mv_primary(a), unwrap_mv_primary(b)]]

  def values(a, b, c),
    do: [:_values_, [unwrap_mv_primary(a), unwrap_mv_primary(b), unwrap_mv_primary(c)]]

  def values_list(list) when is_list(list) do
    if proper_list?(list) do
      [:_values_, list]
    else
      raise ArgumentError, "values-list requires a proper list, got: #{inspect(list)}"
    end
  end

  def values_list(nil), do: [:_values_, []]
  def values_list([list]) when is_list(list), do: values_list(list)
  def values_list([nil]), do: [:_values_, []]

  def values_list(other) do
    raise ArgumentError, "values-list requires a proper list, got: #{inspect(other)}"
  end

  defp proper_list?([]), do: true
  defp proper_list?([_ | tail]) when is_list(tail), do: proper_list?(tail)
  defp proper_list?([_ | _]), do: false
  defp proper_list?(_), do: false

  @doc """
  Dispatches and executes a built-in function.
  """
  def dispatch_builtin(name, raw_args) do
    norm_raw = normalize_raw_args(raw_args)

    args =
      if name in [:values, :values_list, :_cl_values_, :_cl_values_list_] do
        norm_raw
      else
        Enum.map(norm_raw, &unwrap_mv_primary/1)
      end

    case name do
      :+ ->
        add(args)

      :- ->
        sub(args)

      :* ->
        mul(args)

      :/ ->
        divide(args)

      := ->
        num_eq(args)

      :"/=" ->
        num_neq(args)

      :< ->
        num_lt(args)

      :<= ->
        num_lte(args)

      :> ->
        num_gt(args)

      :>= ->
        num_gte(args)

      :min ->
        min(args)

      :max ->
        max(args)

      :gcd ->
        gcd(args)

      :lcm ->
        lcm(args)

      :list ->
        list(args)

      :"list*" ->
        list_star(args)

      :append ->
        append(args)

      :"1+" ->
        case args do
          [x] -> one_plus(x)
        end

      :"1-" ->
        case args do
          [x] -> one_minus(x)
        end

      :not ->
        case args do
          [x] -> not_fn(x)
        end

      name
      when name in [
             :"string=",
             :_cl_string_eq_,
             :string_eq,
             :"string/=",
             :_cl_string_neq_,
             :string_neq,
             :"string<",
             :_cl_string_lt_,
             :string_lt,
             :"string<=",
             :_cl_string_lte_,
             :string_lte,
             :"string>",
             :_cl_string_gt_,
             :string_gt,
             :"string>=",
             :_cl_string_gte_,
             :string_gte,
             :string_equal,
             :_cl_string_equal_,
             :string_not_equal,
             :_cl_string_not_equal_,
             :string_lessp,
             :_cl_string_lessp_,
             :string_greaterp,
             :_cl_string_greaterp_,
             :string_not_greaterp,
             :_cl_string_not_greaterp_,
             :string_not_lessp,
             :_cl_string_not_lessp_,
             :string_upcase,
             :_cl_string_upcase_,
             :string_downcase,
             :_cl_string_downcase_,
             :string_capitalize,
             :_cl_string_capitalize_,
             :nstring_upcase,
             :_cl_nstring_upcase_,
             :nstring_downcase,
             :_cl_nstring_downcase_,
             :nstring_capitalize,
             :_cl_nstring_capitalize_,
             :make_string,
             :_cl_make_string_,
             :"char=",
             :_cl_char_eq_,
             :char_eq,
             :"char/=",
             :_cl_char_neq_,
             :char_neq,
             :"char<",
             :_cl_char_lt_,
             :char_lt,
             :"char<=",
             :_cl_char_lte_,
             :char_lte,
             :"char>",
             :_cl_char_gt_,
             :char_gt,
             :"char>=",
             :_cl_char_gte_,
             :char_gte,
             :char_equal,
             :_cl_char_equal_,
             :char_not_equal,
             :_cl_char_not_equal_,
             :char_lessp,
             :_cl_char_lessp_,
             :char_greaterp,
             :_cl_char_greaterp_,
             :char_not_greaterp,
             :_cl_char_not_greaterp_,
             :char_not_lessp,
             :_cl_char_not_lessp_
           ] ->
        canonical =
          case name do
            n when n in [:"string=", :_cl_string_eq_, :string_eq] -> :string_eq
            n when n in [:"string/=", :_cl_string_neq_, :string_neq] -> :string_neq
            n when n in [:"string<", :_cl_string_lt_, :string_lt] -> :string_lt
            n when n in [:"string<=", :_cl_string_lte_, :string_lte] -> :string_lte
            n when n in [:"string>", :_cl_string_gt_, :string_gt] -> :string_gt
            n when n in [:"string>=", :_cl_string_gte_, :string_gte] -> :string_gte
            n when n in [:string_equal, :_cl_string_equal_] -> :string_equal
            n when n in [:string_not_equal, :_cl_string_not_equal_] -> :string_not_equal
            n when n in [:string_lessp, :_cl_string_lessp_] -> :string_lessp
            n when n in [:string_greaterp, :_cl_string_greaterp_] -> :string_greaterp
            n when n in [:string_not_greaterp, :_cl_string_not_greaterp_] -> :string_not_greaterp
            n when n in [:string_not_lessp, :_cl_string_not_lessp_] -> :string_not_lessp
            n when n in [:string_upcase, :_cl_string_upcase_] -> :string_upcase
            n when n in [:string_downcase, :_cl_string_downcase_] -> :string_downcase
            n when n in [:string_capitalize, :_cl_string_capitalize_] -> :string_capitalize
            n when n in [:nstring_upcase, :_cl_nstring_upcase_] -> :nstring_upcase
            n when n in [:nstring_downcase, :_cl_nstring_downcase_] -> :nstring_downcase
            n when n in [:nstring_capitalize, :_cl_nstring_capitalize_] -> :nstring_capitalize
            n when n in [:make_string, :_cl_make_string_] -> :make_string
            n when n in [:"char=", :_cl_char_eq_, :char_eq] -> :char_eq
            n when n in [:"char/=", :_cl_char_neq_, :char_neq] -> :char_neq
            n when n in [:"char<", :_cl_char_lt_, :char_lt] -> :char_lt
            n when n in [:"char<=", :_cl_char_lte_, :char_lte] -> :char_lte
            n when n in [:"char>", :_cl_char_gt_, :char_gt] -> :char_gt
            n when n in [:"char>=", :_cl_char_gte_, :char_gte] -> :char_gte
            n when n in [:char_equal, :_cl_char_equal_] -> :char_equal
            n when n in [:char_not_equal, :_cl_char_not_equal_] -> :char_not_equal
            n when n in [:char_lessp, :_cl_char_lessp_] -> :char_lessp
            n when n in [:char_greaterp, :_cl_char_greaterp_] -> :char_greaterp
            n when n in [:char_not_greaterp, :_cl_char_not_greaterp_] -> :char_not_greaterp
            n when n in [:char_not_lessp, :_cl_char_not_lessp_] -> :char_not_lessp
          end

        Kernel.apply(__MODULE__, canonical, [args])

      :numerator ->
        case args do
          [x] -> numerator(x)
        end

      :denominator ->
        case args do
          [x] -> denominator(x)
        end

      :rational ->
        case args do
          [x] -> rational(x)
        end

      :rationalp ->
        case args do
          [x] -> rationalp(x)
        end

      :realp ->
        case args do
          [x] -> realp(x)
        end

      :parse_integer ->
        parse_integer(args)

      :make_symbol ->
        make_symbol(args)

      :copy_symbol ->
        copy_symbol(args)

      :special_operator_p ->
        special_operator_p(args)

      :set ->
        case args do
          [sym, val] -> set_symbol_value(sym, val)
          _ -> raise ArgumentError, "set requires 2 arguments"
        end

      :symbol_plist ->
        case args do
          [sym] -> symbol_plist(sym)
          _ -> raise ArgumentError, "symbol-plist requires 1 argument"
        end

      :get ->
        case args do
          [sym, prop] -> get_symbol_prop(sym, prop, nil)
          [sym, prop, default] -> get_symbol_prop(sym, prop, default)
          _ -> raise ArgumentError, "get requires 2 or 3 arguments"
        end

      :remprop ->
        case args do
          [sym, prop] -> remprop(sym, prop)
          _ -> raise ArgumentError, "remprop requires 2 arguments"
        end

      name
      when name in [
             :logand,
             :logior,
             :logxor,
             :logeqv,
             :_cl_logand_,
             :_cl_logior_,
             :_cl_logxor_,
             :_cl_logeqv_
           ] ->
        canonical =
          case name do
            :_cl_logand_ -> :logand
            :_cl_logior_ -> :logior
            :_cl_logxor_ -> :logxor
            :_cl_logeqv_ -> :logeqv
            other -> other
          end

        Kernel.apply(__MODULE__, canonical, [args])

      :cons ->
        case args do
          [h, t] -> cons(h, t)
          _ -> raise ArgumentError, "cons requires 2 arguments"
        end

      :constantly ->
        case args do
          [x] -> constantly(x)
          _ -> constantly(args)
        end

      :complement ->
        case args do
          [f] -> complement(f)
          _ -> raise ArgumentError, "complement requires 1 argument"
        end

      name
      when name in [
             :every,
             :some,
             :notany,
             :notevery,
             :_cl_every_,
             :_cl_some_,
             :_cl_notany_,
             :_cl_notevery_
           ] ->
        canonical =
          case name do
            :_cl_every_ -> :every
            :_cl_some_ -> :some
            :_cl_notany_ -> :notany
            :_cl_notevery_ -> :notevery
            other -> other
          end

        Kernel.apply(__MODULE__, canonical, [args])

      name when name in [:values, :_cl_values_] ->
        values(raw_args)

      name when name in [:values_list, :_cl_values_list_] ->
        values_list(raw_args)

      name when name in [:compile, :_cl_compile_] ->
        compile(args)

      :quit ->
        quit(args)

      :exit ->
        quit(args)

      _ ->
        arity = length(args)

        cond do
          MapSet.member?(@variadic_builtins, name) ->
            Kernel.apply(__MODULE__, name, [args])

          function_exported?(__MODULE__, name, arity) ->
            Kernel.apply(__MODULE__, name, args)

          true ->
            raise ArgumentError, "Cannot invoke builtin: #{name} with #{arity} arguments"
        end
    end
  end

  # --- Arithmetic helpers ---

  def negate_num([:_values_ | _] = v), do: negate_num(unwrap_mv_primary(v))
  def negate_num({:complex, r, i}), do: {:complex, negate_num(r), negate_num(i)}
  def negate_num(%ExLisp.Ratio{} = r), do: ExLisp.Ratio.negate(r)
  def negate_num(x) when is_number(x), do: -x

  def add_two([:_values_ | _] = a, b), do: add_two(unwrap_mv_primary(a), b)
  def add_two(a, [:_values_ | _] = b), do: add_two(a, unwrap_mv_primary(b))
  def add_two({:complex, r1, i1}, {:complex, r2, i2}), do: {:complex, add_two(r1, r2), add_two(i1, i2)}
  def add_two({:complex, r1, i1}, b), do: {:complex, add_two(r1, b), i1}
  def add_two(a, {:complex, r2, i2}), do: {:complex, add_two(a, r2), i2}
  def add_two(a, b) when is_integer(a) and is_integer(b), do: a + b
  def add_two(a, b) when is_float(a) and is_float(b), do: a + b
  def add_two(%ExLisp.Ratio{} = a, b) when is_float(b), do: ExLisp.Ratio.to_float(a) + b
  def add_two(a, %ExLisp.Ratio{} = b) when is_float(a), do: a + ExLisp.Ratio.to_float(b)

  def add_two(a, b) when is_struct(a, ExLisp.Ratio) or is_struct(b, ExLisp.Ratio),
    do: ExLisp.Ratio.add(a, b)

  def add_two(a, b) when is_number(a) and is_number(b), do: a + b

  def sub_two([:_values_ | _] = a, b), do: sub_two(unwrap_mv_primary(a), b)
  def sub_two(a, [:_values_ | _] = b), do: sub_two(a, unwrap_mv_primary(b))
  def sub_two({:complex, r1, i1}, {:complex, r2, i2}), do: {:complex, sub_two(r1, r2), sub_two(i1, i2)}
  def sub_two({:complex, r1, i1}, b), do: {:complex, sub_two(r1, b), i1}
  def sub_two(a, {:complex, r2, i2}), do: {:complex, sub_two(a, r2), negate_num(i2)}
  def sub_two(a, b) when is_integer(a) and is_integer(b), do: a - b
  def sub_two(a, b) when is_float(a) and is_float(b), do: a - b
  def sub_two(%ExLisp.Ratio{} = a, b) when is_float(b), do: ExLisp.Ratio.to_float(a) - b
  def sub_two(a, %ExLisp.Ratio{} = b) when is_float(a), do: a - ExLisp.Ratio.to_float(b)

  def sub_two(a, b) when is_struct(a, ExLisp.Ratio) or is_struct(b, ExLisp.Ratio),
    do: ExLisp.Ratio.sub(a, b)

  def sub_two(a, b) when is_number(a) and is_number(b), do: a - b

  def mul_two([:_values_ | _] = a, b), do: mul_two(unwrap_mv_primary(a), b)
  def mul_two(a, [:_values_ | _] = b), do: mul_two(a, unwrap_mv_primary(b))
  def mul_two({:complex, r1, i1}, {:complex, r2, i2}) do
    {:complex, sub_two(mul_two(r1, r2), mul_two(i1, i2)), add_two(mul_two(r1, i2), mul_two(i1, r2))}
  end
  def mul_two({:complex, r1, i1}, b), do: {:complex, mul_two(r1, b), mul_two(i1, b)}
  def mul_two(a, {:complex, r2, i2}), do: {:complex, mul_two(a, r2), mul_two(a, i2)}
  def mul_two(a, b) when is_integer(a) and is_integer(b), do: a * b
  def mul_two(a, b) when is_float(a) and is_float(b), do: a * b
  def mul_two(%ExLisp.Ratio{} = a, b) when is_float(b), do: ExLisp.Ratio.to_float(a) * b
  def mul_two(a, %ExLisp.Ratio{} = b) when is_float(a), do: a * ExLisp.Ratio.to_float(b)

  def mul_two(a, b) when is_struct(a, ExLisp.Ratio) or is_struct(b, ExLisp.Ratio),
    do: ExLisp.Ratio.mul(a, b)

  def mul_two(a, b) when is_number(a) and is_number(b), do: a * b

  def divide_two([:_values_ | _] = a, b), do: divide_two(unwrap_mv_primary(a), b)
  def divide_two(a, [:_values_ | _] = b), do: divide_two(a, unwrap_mv_primary(b))
  def divide_two(_a, 0), do: raise(ArithmeticError, "division by zero")
  def divide_two(_a, %ExLisp.Ratio{numerator: 0}), do: raise(ArithmeticError, "division by zero")
  def divide_two({:complex, r1, i1}, {:complex, r2, i2}) do
    denom = add_two(mul_two(r2, r2), mul_two(i2, i2))
    r = divide_two(add_two(mul_two(r1, r2), mul_two(i1, i2)), denom)
    i = divide_two(sub_two(mul_two(i1, r2), mul_two(r1, i2)), denom)
    {:complex, r, i}
  end
  def divide_two({:complex, r1, i1}, b), do: {:complex, divide_two(r1, b), divide_two(i1, b)}
  def divide_two(a, {:complex, r2, i2}) do
    denom = add_two(mul_two(r2, r2), mul_two(i2, i2))
    r = divide_two(mul_two(a, r2), denom)
    i = divide_two(negate_num(mul_two(a, i2)), denom)
    {:complex, r, i}
  end
  def divide_two(a, b) when is_integer(a) and is_integer(b), do: ExLisp.Ratio.new(a, b)
  def divide_two(%ExLisp.Ratio{} = a, b) when is_float(b), do: ExLisp.Ratio.to_float(a) / b
  def divide_two(a, %ExLisp.Ratio{} = b) when is_float(a), do: a / ExLisp.Ratio.to_float(b)

  def divide_two(a, b) when is_struct(a, ExLisp.Ratio) or is_struct(b, ExLisp.Ratio),
    do: ExLisp.Ratio.divide(a, b)

  def divide_two(a, b) when is_number(a) and is_number(b), do: a / b

  # --- Arithmetic operations ---

  def add(a, b), do: add_two(a, b)
  def add([]), do: 0
  def add([x]), do: x
  def add([a, b]), do: add_two(a, b)

  def add(args) when is_list(args),
    do: Enum.reduce(args, 0, fn elem, acc -> add_two(acc, elem) end)

  def sub(a, b), do: sub_two(a, b)
  def sub([]), do: raise(ArgumentError, "sub requires at least 1 argument")
  def sub([x]), do: negate_num(x)
  def sub([a, b]), do: sub_two(a, b)

  def sub([first | rest]) when is_list(rest) and rest != [] do
    Enum.reduce(rest, first, fn elem, acc -> sub_two(acc, elem) end)
  end

  def mul(a, b), do: mul_two(a, b)
  def mul([]), do: 1
  def mul([x]), do: x
  def mul([a, b]), do: mul_two(a, b)

  def mul(args) when is_list(args),
    do: Enum.reduce(args, 1, fn elem, acc -> mul_two(acc, elem) end)

  def divide(a, b), do: divide_two(a, b)
  def divide([]), do: raise(ArgumentError, "divide requires at least 1 argument")
  def divide([x]), do: divide_two(1, x)
  def divide([a, b]), do: divide_two(a, b)

  def divide([first | rest]) when is_list(rest) and rest != [] do
    Enum.reduce(rest, first, fn elem, acc -> divide_two(acc, elem) end)
  end

  def one_plus(x), do: add_two(x, 1)
  def one_minus(x), do: sub_two(x, 1)

  def abs(%ExLisp.Ratio{numerator: n, denominator: d}),
    do: %ExLisp.Ratio{numerator: Kernel.abs(n), denominator: d}

  def abs(x) when is_number(x), do: Kernel.abs(x)

  def min([first | rest]), do: Enum.reduce(rest, first, &min/2)
  def min([]), do: raise(ArgumentError, "min requires at least 1 argument")

  def min(a, b) do
    if compare_nums(a, b) == :lt, do: a, else: b
  end

  def max([first | rest]), do: Enum.reduce(rest, first, &max/2)
  def max([]), do: raise(ArgumentError, "max requires at least 1 argument")

  def max(a, b) do
    if compare_nums(a, b) == :gt, do: a, else: b
  end

  def mod(n, d) when is_integer(n) and is_integer(d) do
    r = Kernel.rem(n, d)
    if (r > 0 and d < 0) or (r < 0 and d > 0), do: r + d, else: r
  end

  def mod(n, d) when is_number(n) and is_number(d) do
    n - d * :math.floor(n / d)
  end

  def rem(n, d) when is_integer(n) and is_integer(d), do: Kernel.rem(n, d)
  def rem(n, d) when is_number(n) and is_number(d), do: n - d * Kernel.trunc(n / d)

  def floor(x, d \\ 1) do
    q =
      case divide_two(x, d) do
        %ExLisp.Ratio{numerator: vn, denominator: vd} ->
          if (vn >= 0 and vd > 0) or (vn <= 0 and vd < 0) do
            div(abs(vn), abs(vd))
          else
            quot = div(vn, vd)
            if rem(vn, vd) == 0, do: quot, else: quot - 1
          end

        v when is_integer(v) ->
          v

        v when is_float(v) ->
          Kernel.trunc(:math.floor(v))
      end

    r = sub_two(x, mul_two(q, d))
    [:_values_, [q, r]]
  end

  def ceiling(x, d \\ 1) do
    q =
      case divide_two(x, d) do
        %ExLisp.Ratio{numerator: vn, denominator: vd} ->
          if (vn >= 0 and vd > 0) or (vn <= 0 and vd < 0) do
            quot = div(vn, vd)
            if rem(vn, vd) == 0, do: quot, else: quot + 1
          else
            div(vn, vd)
          end

        v when is_integer(v) ->
          v

        v when is_float(v) ->
          Kernel.trunc(:math.ceil(v))
      end

    r = sub_two(x, mul_two(q, d))
    [:_values_, [q, r]]
  end

  def round(x, d \\ 1) do
    q =
      case divide_two(x, d) do
        %ExLisp.Ratio{numerator: vn, denominator: vd} ->
          {n, d_pos} = if vd < 0, do: {-vn, -vd}, else: {vn, vd}
          quot = div(n, d_pos)
          rem_val = Kernel.rem(n, d_pos)

          {q_floor, r} =
            if rem_val < 0 do
              {quot - 1, rem_val + d_pos}
            else
              {quot, rem_val}
            end

          cond do
            r * 2 < d_pos ->
              q_floor

            r * 2 > d_pos ->
              q_floor + 1

            true ->
              if Kernel.rem(q_floor, 2) == 0, do: q_floor, else: q_floor + 1
          end

        v when is_integer(v) ->
          v

        v when is_float(v) ->
          f_floor = :math.floor(v) |> Kernel.trunc()
          diff = v - f_floor

          cond do
            diff < 0.5 ->
              f_floor

            diff > 0.5 ->
              f_floor + 1

            true ->
              if Kernel.rem(f_floor, 2) == 0, do: f_floor, else: f_floor + 1
          end
      end

    r = sub_two(x, mul_two(q, d))
    [:_values_, [q, r]]
  end

  def truncate(x, d \\ 1) do
    q =
      case divide_two(x, d) do
        %ExLisp.Ratio{numerator: vn, denominator: vd} ->
          div(vn, vd)

        v when is_integer(v) ->
          v

        v when is_float(v) ->
          Kernel.trunc(v)
      end

    r = sub_two(x, mul_two(q, d))
    [:_values_, [q, r]]
  end

  def sqrt(x) when is_number(x), do: :math.sqrt(x)
  def exp(x) when is_number(x), do: :math.exp(x)

  def expt(%ExLisp.Ratio{numerator: n, denominator: d}, power)
      when is_integer(power) and power >= 0 do
    ExLisp.Ratio.new(Integer.pow(n, power), Integer.pow(d, power))
  end

  def expt(%ExLisp.Ratio{numerator: n, denominator: d}, power)
      when is_integer(power) and power < 0 do
    ExLisp.Ratio.new(Integer.pow(d, -power), Integer.pow(n, -power))
  end

  def expt(base, power) when is_integer(base) and is_integer(power) and power < 0 do
    ExLisp.Ratio.new(1, Integer.pow(base, -power))
  end

  def expt(base, power) when is_integer(base) and is_integer(power) and power >= 0 do
    Integer.pow(base, power)
  end

  def expt(base, power) when is_number(base) and is_number(power) do
    :math.pow(base, power)
  end

  def expt(%ExLisp.Ratio{} = base, power) when is_number(power) do
    :math.pow(ExLisp.Ratio.to_float(base), power)
  end

  def log(x, base \\ nil) do
    val = if is_struct(x, ExLisp.Ratio), do: ExLisp.Ratio.to_float(x), else: x

    if base == nil do
      :math.log(val)
    else
      base_val = if is_struct(base, ExLisp.Ratio), do: ExLisp.Ratio.to_float(base), else: base
      :math.log(val) / :math.log(base_val)
    end
  end

  def sin(x) when is_number(x), do: :math.sin(x)
  def cos(x) when is_number(x), do: :math.cos(x)
  def tan(x) when is_number(x), do: :math.tan(x)
  def asin(x) when is_number(x), do: :math.asin(x)
  def acos(x) when is_number(x), do: :math.acos(x)
  def atan(x) when is_number(x), do: :math.atan(x)

  def gcd([]), do: 0
  def gcd([x]), do: Kernel.abs(unwrap_mv_primary(x))

  def gcd(args) when is_list(args) do
    args
    |> Enum.map(&unwrap_mv_primary/1)
    |> Enum.reduce(0, &Integer.gcd/2)
  end

  def lcm([]), do: 1
  def lcm([x]), do: Kernel.abs(unwrap_mv_primary(x))

  def lcm(args) when is_list(args) do
    args
    |> Enum.map(&unwrap_mv_primary/1)
    |> Enum.reduce(1, fn a, b ->
      if a == 0 or b == 0, do: 0, else: Kernel.div(Kernel.abs(a * b), Integer.gcd(a, b))
    end)
  end

  def complex([real, imag]), do: {:complex, unwrap_mv_primary(real), unwrap_mv_primary(imag)}

  def complex([real]) do
    real_val = unwrap_mv_primary(real)
    if is_float(real_val), do: {:complex, real_val, 0.0}, else: real_val
  end

  def complex(real), do: complex([real])
  def complex(real, imag), do: complex([real, imag])

  def complexp({:complex, _, _}), do: :t
  def complexp([x]), do: complexp(x)
  def complexp(_), do: nil

  def realpart({:complex, r, _i}), do: r
  def realpart(r) when is_number(r), do: r
  def realpart(%ExLisp.Ratio{} = r), do: r
  def realpart([x]), do: realpart(x)
  def realpart(_), do: 0

  def imagpart({:complex, _r, i}), do: i
  def imagpart(r) when is_float(r), do: 0.0
  def imagpart([x]), do: imagpart(x)
  def imagpart(_), do: 0

  # --- Numeric comparison helpers ---

  def compare_nums([:_values_ | _] = a, b), do: compare_nums(unwrap_mv_primary(a), b)
  def compare_nums(a, [:_values_ | _] = b), do: compare_nums(a, unwrap_mv_primary(b))
  def compare_nums(a, b) when is_integer(a) and is_integer(b) do
    cond do
      a < b -> :lt
      a > b -> :gt
      true -> :eq
    end
  end

  def compare_nums(a, b) when is_float(a) and is_float(b) do
    cond do
      a < b -> :lt
      a > b -> :gt
      true -> :eq
    end
  end

  def compare_nums(a, b) when is_number(a) and is_number(b) do
    cond do
      a < b -> :lt
      a > b -> :gt
      true -> :eq
    end
  end

  def compare_nums(%ExLisp.Ratio{numerator: an, denominator: ad}, %ExLisp.Ratio{
        numerator: bn,
        denominator: bd
      }) do
    left = an * bd
    right = bn * ad

    cond do
      left < right -> :lt
      left > right -> :gt
      true -> :eq
    end
  end

  def compare_nums(%ExLisp.Ratio{numerator: an, denominator: ad}, b) when is_integer(b) do
    left = an
    right = b * ad

    cond do
      left < right -> :lt
      left > right -> :gt
      true -> :eq
    end
  end

  def compare_nums(a, %ExLisp.Ratio{numerator: bn, denominator: bd}) when is_integer(a) do
    left = a * bd
    right = bn

    cond do
      left < right -> :lt
      left > right -> :gt
      true -> :eq
    end
  end

  def compare_nums(%ExLisp.Ratio{} = a, b) when is_float(b) do
    af = ExLisp.Ratio.to_float(a)

    cond do
      af < b -> :lt
      af > b -> :gt
      true -> :eq
    end
  end

  def compare_nums(a, %ExLisp.Ratio{} = b) when is_float(a) do
    bf = ExLisp.Ratio.to_float(b)

    cond do
      a < bf -> :lt
      a > bf -> :gt
      true -> :eq
    end
  end

  def compare_nums({:complex, r1, i1}, {:complex, r2, i2}) do
    if compare_nums(r1, r2) == :eq and compare_nums(i1, i2) == :eq, do: :eq, else: :invalid
  end

  def compare_nums({:complex, r1, i1}, b) do
    if compare_nums(r1, b) == :eq and compare_nums(i1, 0) == :eq, do: :eq, else: :invalid
  end

  def compare_nums(a, {:complex, r2, i2}) do
    if compare_nums(a, r2) == :eq and compare_nums(0, i2) == :eq, do: :eq, else: :invalid
  end

  def compare_nums(_, _), do: :invalid

  # --- Fast 2-argument comparison ---

  def num_lte_two(a, b) when is_integer(a) and is_integer(b) do
    if a <= b, do: :t, else: nil
  end

  def num_lte_two(a, b) when is_float(a) and is_float(b) do
    if a <= b, do: :t, else: nil
  end

  def num_lte_two(a, b) when is_number(a) and is_number(b) do
    if a <= b, do: :t, else: nil
  end

  def num_lte_two(a, b) do
    if compare_nums(a, b) in [:lt, :eq], do: :t, else: nil
  end

  def num_lt_two(a, b) when is_integer(a) and is_integer(b) do
    if a < b, do: :t, else: nil
  end

  def num_lt_two(a, b) when is_float(a) and is_float(b) do
    if a < b, do: :t, else: nil
  end

  def num_lt_two(a, b) when is_number(a) and is_number(b) do
    if a < b, do: :t, else: nil
  end

  def num_lt_two(a, b) do
    if compare_nums(a, b) == :lt, do: :t, else: nil
  end

  def num_gte_two(a, b) when is_integer(a) and is_integer(b) do
    if a >= b, do: :t, else: nil
  end

  def num_gte_two(a, b) when is_float(a) and is_float(b) do
    if a >= b, do: :t, else: nil
  end

  def num_gte_two(a, b) when is_number(a) and is_number(b) do
    if a >= b, do: :t, else: nil
  end

  def num_gte_two(a, b) do
    if compare_nums(a, b) in [:gt, :eq], do: :t, else: nil
  end

  def num_gt_two(a, b) when is_integer(a) and is_integer(b) do
    if a > b, do: :t, else: nil
  end

  def num_gt_two(a, b) when is_float(a) and is_float(b) do
    if a > b, do: :t, else: nil
  end

  def num_gt_two(a, b) when is_number(a) and is_number(b) do
    if a > b, do: :t, else: nil
  end

  def num_gt_two(a, b) do
    if compare_nums(a, b) == :gt, do: :t, else: nil
  end

  def num_eq_two(a, b) when is_integer(a) and is_integer(b) do
    if a == b, do: :t, else: nil
  end

  def num_eq_two(a, b) when is_float(a) and is_float(b) do
    if a == b, do: :t, else: nil
  end

  def num_eq_two(a, b) when is_number(a) and is_number(b) do
    if a == b, do: :t, else: nil
  end

  def num_eq_two(a, b) do
    if compare_nums(a, b) == :eq, do: :t, else: nil
  end

  def num_neq_two(a, b) when is_integer(a) and is_integer(b) do
    if a != b, do: :t, else: nil
  end

  def num_neq_two(a, b) when is_float(a) and is_float(b) do
    if a != b, do: :t, else: nil
  end

  def num_neq_two(a, b) when is_number(a) and is_number(b) do
    if a != b, do: :t, else: nil
  end

  def num_neq_two(a, b) do
    if compare_nums(a, b) != :eq, do: :t, else: nil
  end

  # --- Numeric comparisons ---

  def num_eq(a, b), do: num_eq_two(a, b)
  def num_eq([]), do: :t
  def num_eq([_]), do: :t
  def num_eq([a, b]), do: num_eq_two(a, b)

  def num_eq(args) when is_list(args) do
    args
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.all?(fn [a, b] -> compare_nums(a, b) == :eq end)
    |> lisp_bool()
  end

  def num_neq(a, b), do: num_neq_two(a, b)
  def num_neq([]), do: :t
  def num_neq([_]), do: :t
  def num_neq([a, b]), do: num_neq_two(a, b)

  def num_neq(args) when is_list(args) do
    all_pairs_neq?(args) |> lisp_bool()
  end

  defp all_pairs_neq?([]), do: true
  defp all_pairs_neq?([_]), do: true

  defp all_pairs_neq?([head | tail]) do
    Enum.all?(tail, fn item -> compare_nums(head, item) != :eq end) and all_pairs_neq?(tail)
  end

  def num_lt(a, b), do: num_lt_two(a, b)
  def num_lt([]), do: :t
  def num_lt([_]), do: :t
  def num_lt([a, b]), do: num_lt_two(a, b)

  def num_lt(args) when is_list(args) do
    args
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.all?(fn [a, b] -> compare_nums(a, b) == :lt end)
    |> lisp_bool()
  end

  def num_lte(a, b), do: num_lte_two(a, b)
  def num_lte([]), do: :t
  def num_lte([_]), do: :t
  def num_lte([a, b]), do: num_lte_two(a, b)

  def num_lte(args) when is_list(args) do
    args
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.all?(fn [a, b] -> compare_nums(a, b) in [:lt, :eq] end)
    |> lisp_bool()
  end

  def num_gt(a, b), do: num_gt_two(a, b)
  def num_gt([]), do: :t
  def num_gt([_]), do: :t
  def num_gt([a, b]), do: num_gt_two(a, b)

  def num_gt(args) when is_list(args) do
    args
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.all?(fn [a, b] -> compare_nums(a, b) == :gt end)
    |> lisp_bool()
  end

  def num_gte(a, b), do: num_gte_two(a, b)
  def num_gte([]), do: :t
  def num_gte([_]), do: :t
  def num_gte([a, b]), do: num_gte_two(a, b)

  def num_gte(args) when is_list(args) do
    args
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.all?(fn [a, b] -> compare_nums(a, b) in [:gt, :eq] end)
    |> lisp_bool()
  end

  # --- Equality and predicates ---

  def eq(x, y) when x in [nil, [], nil] and y in [nil, [], nil], do: :t
  def eq(x, y) when is_atom(x) and is_atom(y), do: (x === y) |> lisp_bool()
  def eq(x, y), do: (x === y) |> lisp_bool()
  def eqt(x, y), do: eq(x, y)

  def eql(x, y) when x in [nil, [], nil] and y in [nil, [], nil], do: :t
  def eql(x, y) when is_atom(x) and is_atom(y), do: (x === y) |> lisp_bool()

  def eql(x, y) when is_number(x) and is_number(y) do
    (x === y and is_float(x) == is_float(y)) |> lisp_bool()
  end

  def eql(%ExLisp.Ratio{} = x, %ExLisp.Ratio{} = y), do: (x == y) |> lisp_bool()

  def eql({:complex, r1, i1}, {:complex, r2, i2}) do
    (eql(r1, r2) == :t and eql(i1, i2) == :t) |> lisp_bool()
  end

  def eql(x, y), do: (x === y) |> lisp_bool()
  def eqlt(x, y), do: eql(x, y)

  def equal([:vector | elems1], [:vector | elems2]), do: equal(elems1, elems2)

  def equal([:vector | elems], {:array, [_], _} = y) do
    equal(elems, seq_to_list(y))
  end

  def equal({:array, [_], _} = x, [:vector | elems]) do
    equal(seq_to_list(x), elems)
  end

  def equal([h1 | t1], [h2 | t2]) do
    if equal(h1, h2) == :t do
      equal(t1, t2)
    else
      nil
    end
  end

  def equal(x, y) when x in [nil, [], nil] and y in [nil, [], nil], do: :t

  def equal(x, {:array, [_], _} = y) when is_binary(x) do
    (x == to_string_val(y)) |> lisp_bool()
  end

  def equal({:array, [_], _} = x, y) when is_binary(y) do
    (to_string_val(x) == y) |> lisp_bool()
  end

  def equal({:array, d1, _} = x, {:array, d2, _} = y) do
    if d1 == d2 do
      l1 = seq_to_list(x)
      l2 = seq_to_list(y)
      equal(l1, l2)
    else
      nil
    end
  end

  def equal(x, y), do: (x == y) |> lisp_bool()
  def equalt(x, y), do: equal(x, y)

  def equalp(x, y) when x in [nil, [], nil] and y in [nil, [], nil], do: :t

  def equalp(%ExLisp.Ratio{} = x, %ExLisp.Ratio{} = y) do
    (x == y) |> lisp_bool()
  end

  def equalp(%ExLisp.Ratio{} = x, y) when is_number(y) do
    (compare_nums(x, y) == :eq) |> lisp_bool()
  end

  def equalp(x, %ExLisp.Ratio{} = y) when is_number(x) do
    (compare_nums(x, y) == :eq) |> lisp_bool()
  end

  def equalp(x, {:array, [_], _} = y) when is_binary(x) do
    ly = seq_to_list(y)
    chars = String.to_charlist(x)

    if length(chars) == length(ly) do
      Enum.zip(chars, ly)
      |> Enum.all?(fn {a, b} -> equalp(a, b) == :t end)
      |> lisp_bool()
    else
      nil
    end
  end

  def equalp({:array, [_], _} = x, y) when is_binary(y) do
    equalp(y, x)
  end

  def equalp({:array, d1, _} = x, {:array, d2, _} = y) do
    lx = seq_to_list(x)
    ly = seq_to_list(y)

    cond do
      length(d1) == 1 and length(d2) == 1 ->
        if length(lx) == length(ly) do
          Enum.zip(lx, ly)
          |> Enum.all?(fn {a, b} -> equalp(a, b) == :t end)
          |> lisp_bool()
        else
          nil
        end

      d1 == d2 and length(lx) == length(ly) ->
        Enum.zip(lx, ly)
        |> Enum.all?(fn {a, b} -> equalp(a, b) == :t end)
        |> lisp_bool()

      true ->
        nil
    end
  end

  def equalp(x, y) when is_binary(x) and is_binary(y) do
    (String.downcase(x) == String.downcase(y)) |> lisp_bool()
  end

  def equalp(x, y) when is_number(x) and is_number(y) do
    (x == y) |> lisp_bool()
  end

  def equalp(x, y)
      when is_integer(x) and is_integer(y) and x >= 0 and x <= 0x10FFFF and y >= 0 and
             y <= 0x10FFFF do
    (x == y or
       try do
         String.downcase(<<x::utf8>>) == String.downcase(<<y::utf8>>)
       rescue
         _ -> false
       end)
    |> lisp_bool()
  end

  def equalp(x, y) when is_list(x) and is_list(y) do
    if length(x) == length(y) do
      Enum.zip(x, y)
      |> Enum.all?(fn {a, b} -> equalp(a, b) == :t end)
      |> lisp_bool()
    else
      nil
    end
  end

  def equalp(x, y), do: (x == y) |> lisp_bool()

  def atom(x) do
    !(is_list(x) and x != []) |> lisp_bool()
  end

  def consp(x) do
    (is_list(x) and x != []) |> lisp_bool()
  end

  def listp(x) do
    (is_list(x) or x == nil) |> lisp_bool()
  end

  def numberp(%ExLisp.Ratio{}), do: :t
  def numberp(x), do: is_number(x) |> lisp_bool()

  def rationalp(%ExLisp.Ratio{}), do: :t
  def rationalp(x) when is_integer(x), do: :t
  def rationalp(_), do: nil

  def realp(%ExLisp.Ratio{}), do: :t
  def realp(x) when is_number(x), do: :t
  def realp([x]), do: realp(x)
  def realp(_), do: nil

  def integerp(x), do: is_integer(x) |> lisp_bool()
  def floatp(x), do: is_float(x) |> lisp_bool()

  def numerator(%ExLisp.Ratio{numerator: n}), do: n
  def numerator(x) when is_integer(x), do: x

  def denominator(%ExLisp.Ratio{denominator: d}), do: d
  def denominator(x) when is_integer(x), do: 1

  def rational(%ExLisp.Ratio{} = r), do: r
  def rational(x) when is_integer(x), do: x

  def rational(x) when is_float(x) do
    {n, d} = Float.ratio(x)
    ExLisp.Ratio.new(n, d)
  end

  def symbolp(x) do
    (is_atom(x) or is_struct(x, ExLisp.Symbol)) |> lisp_bool()
  end

  def keywordp(nil), do: nil
  def keywordp(:t), do: nil
  def keywordp(:":nil"), do: :t
  def keywordp(:":t"), do: :t

  def keywordp(x) when is_atom(x) do
    str = Atom.to_string(x)

    if String.starts_with?(str, "#:") do
      nil
    else
      ExLisp.Env.keyword?(x) |> lisp_bool()
    end
  end

  def keywordp(_), do: nil

  def stringp(x) do
    cond do
      is_binary(x) ->
        :t

      match?({:array, [_], _}, x) ->
        {:array, _, tid} = x

        case :ets.lookup(tid, :__meta__) do
          [{:__meta__, %{element_type: etype}}] ->
            norm = normalize_type_spec(etype)
            (norm in [:character, :base_char, :standard_char, :extended_char, nil]) |> lisp_bool()

          _ ->
            nil
        end

      true ->
        nil
    end
  end

  def simple_string_p(x) do
    cond do
      is_binary(x) ->
        :t

      match?({:array, [_], _}, x) ->
        {:array, _, tid} = x

        case :ets.lookup(tid, :__meta__) do
          [{:__meta__, meta}] ->
            etype = Map.get(meta, :element_type, :t)
            norm = normalize_type_spec(etype)
            is_char_type = norm in [:character, :base_char, :standard_char, :extended_char, nil]
            adj = Map.get(meta, :adjustable, false)
            fp = Map.get(meta, :fill_pointer, nil)
            disp = Map.get(meta, :displaced_to, nil)
            (is_char_type and not adj and fp == nil and disp == nil) |> lisp_bool()

          _ ->
            nil
        end

      true ->
        nil
    end
  end

  def characterp(x) do
    (is_integer(x) and x >= 0 and x <= 0x10FFFF and
       x not in [
         1,
         2,
         3,
         4,
         5,
         6,
         7,
         8,
         11,
         14,
         15,
         16,
         17,
         18,
         19,
         20,
         21,
         22,
         23,
         24,
         25,
         26,
         28,
         29,
         30,
         31
       ])
    |> lisp_bool()
  end

  def functionp(%ExLisp.Closure{}), do: :t

  def functionp(x),
    do:
      (is_function(x) or (is_atom(x) and (BuiltinFunction.builtin?(x) or ExLisp.Env.has_fun?(x))))
      |> lisp_bool()

  def null(x), do: !truthy?(x) |> lisp_bool()
  def endp(x) when x in [nil, []], do: :t
  def endp(x) when is_list(x), do: nil
  def endp(x), do: raise("type-error: expected list, got #{inspect(x)}")
  def not_fn(x), do: !truthy?(x) |> lisp_bool()

  def zerop([:_values_ | _] = v), do: zerop(unwrap_mv_primary(v))
  def zerop(%ExLisp.Ratio{}), do: nil
  def zerop(x) when is_number(x), do: (x == 0) |> lisp_bool()

  def plusp([:_values_ | _] = v), do: plusp(unwrap_mv_primary(v))
  def plusp(%ExLisp.Ratio{numerator: n}), do: (n > 0) |> lisp_bool()
  def plusp(x) when is_number(x), do: (x > 0) |> lisp_bool()
  def plusp(_), do: nil

  def minusp([:_values_ | _] = v), do: minusp(unwrap_mv_primary(v))
  def minusp(%ExLisp.Ratio{numerator: n}), do: (n < 0) |> lisp_bool()
  def minusp(x) when is_number(x), do: (x < 0) |> lisp_bool()
  def minusp(_), do: nil

  def evenp([:_values_ | _] = v), do: evenp(unwrap_mv_primary(v))
  def evenp(x) when is_integer(x), do: (Kernel.rem(x, 2) == 0) |> lisp_bool()
  def evenp(_), do: nil

  def oddp([:_values_ | _] = v), do: oddp(unwrap_mv_primary(v))
  def oddp(x) when is_integer(x), do: (Kernel.rem(x, 2) != 0) |> lisp_bool()
  def oddp(_), do: nil

  def boundp([sym]), do: boundp(sym)
  def boundp(:t), do: :t
  def boundp(nil), do: :t

  def boundp(%ExLisp.Symbol{} = sym) do
    norm = normalize_sym_prop(sym)
    (norm in [:t, nil] or ExLisp.Env.has_var?(norm)) |> lisp_bool()
  end

  def boundp(sym) when is_atom(sym) do
    str = Atom.to_string(sym)

    if String.starts_with?(str, ":") or
         (String.starts_with?(str, "#:UNINTERNED") == false and ExLisp.Env.keyword?(sym)) do
      :t
    else
      norm = normalize_sym_prop(sym)
      (norm in [:t, nil] or ExLisp.Env.has_var?(norm)) |> lisp_bool()
    end
  end

  def boundp(other) do
    raise ArgumentError, "boundp requires a symbol argument, got: #{inspect(other)}"
  end

  def fboundp(sym) do
    norm = normalize_sym_prop(sym)
    (ExLisp.Env.has_fun?(norm) or BuiltinFunction.builtin?(norm)) |> lisp_bool()
  end

  defp normalize_type_spec(spec) do
    cond do
      is_integer(spec) ->
        spec

      is_list(spec) ->
        Enum.map(spec, &normalize_type_spec/1)

      is_atom(spec) ->
        spec
        |> Atom.to_string()
        |> String.trim_leading(":")
        |> String.downcase()
        |> String.replace("-", "_")
        |> String.to_atom()

      is_binary(spec) ->
        spec
        |> String.trim_leading(":")
        |> String.downcase()
        |> String.replace("-", "_")
        |> String.to_atom()

      match?(%ExLisp.Symbol{}, spec) ->
        spec.name
        |> String.downcase()
        |> String.replace("-", "_")
        |> String.to_atom()

      true ->
        spec
    end
  end

  def subtypep(type1, type2) do
    t1_is_nil_array =
      case type1 do
        [:array, nil | _] -> true
        [:simple_array, nil | _] -> true
        [:vector, nil | _] -> true
        [:simple_vector, nil | _] -> true
        _ -> false
      end

    t1 = normalize_type_spec(type1)
    t2 = normalize_type_spec(type2)

    t2_is_wild_simple_array =
      case type2 do
        :simple_array ->
          true

        [:simple_array] ->
          true

        [:simple_array, :* | _] ->
          true

        [first, second | _] when is_binary(first) and is_binary(second) ->
          normalize_type_spec(first) == :simple_array and second in ["*", :*]

        _ ->
          false
      end

    is_sub =
      cond do
        t1_is_nil_array and
            t2 in [
              :string,
              :simple_string,
              :vector,
              :simple_vector,
              :array,
              :simple_array,
              :sequence
            ] ->
          true

        t1 in [:simple_string, :simple_base_string] and t2_is_wild_simple_array ->
          true

        t1 == :simple_base_string and t2 in [:base_string, :simple_string] ->
          true

        t1 == t2 ->
          true

        t2 in [:t, :common] ->
          true

        t1 in [nil, nil] ->
          true

        t1 == :null and t2 in [:list, :sequence, :symbol, :atom, :t] ->
          true

        t1 == :standard_char and t2 in [:base_char, :character] ->
          true

        t1 == :base_char and t2 == :character ->
          true

        t1 == :extended_char and t2 == :character ->
          true

        t1 in [:simple_string, :base_string, :simple_base_string] and
            t2 in [:string, :vector, :array, :sequence] ->
          true

        t1 == :string and t2 in [:vector, :array, :sequence] ->
          true

        t1 == :simple_vector and t2 in [:vector, :array, :sequence] ->
          true

        t1 == :vector and t2 in [:array, :sequence] ->
          true

        t1 == :cons and t2 in [:list, :sequence] ->
          true

        t1 == :null and t2 in [:list, :sequence, :symbol] ->
          true

        t1 == :list and t2 == :sequence ->
          true

        t1 in [:fixnum, :bignum] and t2 in [:integer, :rational, :real, :number] ->
          true

        t1 == :integer and t2 in [:rational, :real, :number] ->
          true

        t1 == :ratio and t2 in [:rational, :real, :number] ->
          true

        t1 == :rational and t2 in [:real, :number] ->
          true

        t1 == :float and t2 in [:real, :number] ->
          true

        t1 in [:bit, :boolean] ->
          true

        true ->
          false
      end

    [:_values_, [lisp_bool(is_sub), :t]]
  end

  def typep(val, type_spec) do
    cond do
      is_list(type_spec) ->
        case type_spec do
          [] ->
            (val == nil) |> lisp_bool()

          [hd_t | rest_t] ->
            head_norm = normalize_type_spec(hd_t)

            case head_norm do
              :string ->
                if stringp(val) == :t do
                  case rest_t do
                    [size | _] when is_integer(size) -> (length(val) == size) |> lisp_bool()
                    _ -> :t
                  end
                else
                  nil
                end

              :simple_string ->
                if simple_string_p(val) == :t do
                  case rest_t do
                    [size | _] when is_integer(size) -> (length(val) == size) |> lisp_bool()
                    _ -> :t
                  end
                else
                  nil
                end

              :base_string ->
                if stringp(val) == :t do
                  case rest_t do
                    [size | _] when is_integer(size) -> (length(val) == size) |> lisp_bool()
                    _ -> :t
                  end
                else
                  nil
                end

              :simple_base_string ->
                if simple_string_p(val) == :t do
                  case rest_t do
                    [size | _] when is_integer(size) -> (length(val) == size) |> lisp_bool()
                    _ -> :t
                  end
                else
                  nil
                end

              :vector ->
                if is_binary(val) or match?({:array, [_], _}, val) or is_list(val) do
                  case rest_t do
                    [_elem_type, size | _] when is_integer(size) ->
                      (length(val) == size) |> lisp_bool()

                    _ ->
                      :t
                  end
                else
                  nil
                end

              :bit_vector ->
                if bit_vector_p(val) == :t do
                  case rest_t do
                    [size | _] when is_integer(size) -> (length(val) == size) |> lisp_bool()
                    _ -> :t
                  end
                else
                  nil
                end

              :simple_bit_vector ->
                if simple_bit_vector_p(val) == :t do
                  case rest_t do
                    [size | _] when is_integer(size) -> (length(val) == size) |> lisp_bool()
                    _ -> :t
                  end
                else
                  nil
                end

              :simple_vector ->
                if simple_vector_p(val) == :t do
                  case rest_t do
                    [size | _] when is_integer(size) -> (length(val) == size) |> lisp_bool()
                    _ -> :t
                  end
                else
                  nil
                end

              :array ->
                if match?({:array, _, _}, val) or is_binary(val) or is_list(val) do
                  case rest_t do
                    [_elem_t, dims | _] ->
                      dim_match =
                        cond do
                          dims in [:*, :_] -> true
                          is_integer(dims) -> array_rank(val) == dims
                          is_list(dims) -> dims == array_dimensions(val)
                          true -> true
                        end

                      dim_match |> lisp_bool()

                    _ ->
                      :t
                  end
                else
                  nil
                end

              :simple_array ->
                if simple_array_p(val) == :t do
                  case rest_t do
                    [_elem_t, dims | _] ->
                      dim_match =
                        cond do
                          dims in [:*, :_] -> true
                          is_integer(dims) -> array_rank(val) == dims
                          is_list(dims) -> dims == array_dimensions(val)
                          true -> true
                        end

                      dim_match |> lisp_bool()

                    _ ->
                      :t
                  end
                else
                  nil
                end

              :unsigned_byte ->
                if is_integer(val) and val >= 0 do
                  case rest_t do
                    [n | _] when is_integer(n) ->
                      (val < Bitwise.bsl(1, n)) |> lisp_bool()

                    _ ->
                      :t
                  end
                else
                  nil
                end

              :signed_byte ->
                if is_integer(val) do
                  case rest_t do
                    [n | _] when is_integer(n) ->
                      min_val = -Bitwise.bsl(1, n - 1)
                      max_val = Bitwise.bsl(1, n - 1) - 1
                      (val >= min_val and val <= max_val) |> lisp_bool()

                    _ ->
                      :t
                  end
                else
                  nil
                end

              :integer ->
                if is_integer(val) do
                  case rest_t do
                    [min, max | _] when is_integer(min) and is_integer(max) ->
                      (val >= min and val <= max) |> lisp_bool()

                    [min | _] when is_integer(min) ->
                      (val >= min) |> lisp_bool()

                    _ ->
                      :t
                  end
                else
                  nil
                end

              :member ->
                (val in rest_t) |> lisp_bool()

              :eql ->
                case rest_t do
                  [target] -> eql(val, target)
                  _ -> nil
                end

              :or ->
                Enum.any?(rest_t, &(typep(val, &1) == :t)) |> lisp_bool()

              :and ->
                Enum.all?(rest_t, &(typep(val, &1) == :t)) |> lisp_bool()

              :not ->
                case rest_t do
                  [t] -> (typep(val, t) != :t) |> lisp_bool()
                  _ -> :t
                end

              _ ->
                typep(val, head_norm)
            end
        end

      true ->
        norm_type = normalize_type_spec(type_spec)

        case norm_type do
          t when t in [:t, true] ->
            :t

          nil ->
            (val == nil) |> lisp_bool()

          :null ->
            (val == nil) |> lisp_bool()

          :list ->
            (is_list(val) or val == nil) |> lisp_bool()

          :cons ->
            (is_list(val) and val != []) |> lisp_bool()

          :sequence ->
            (is_list(val) or val == nil or is_binary(val) or match?({:array, [_], _}, val))
            |> lisp_bool()

          :vector ->
            (is_binary(val) or match?({:array, [_], _}, val) or is_list(val)) |> lisp_bool()

          :simple_vector ->
            match?({:array, [_], _}, val) |> lisp_bool()

          :string ->
            stringp(val)

          :simple_string ->
            simple_string_p(val)

          :base_string ->
            cond do
              is_binary(val) ->
                :t

              match?({:array, [_], _}, val) ->
                {:array, [_], tid} = val

                case :ets.lookup(tid, :__meta__) do
                  [{:__meta__, meta}] ->
                    norm = normalize_type_spec(Map.get(meta, :element_type, :t))
                    (norm in [:character, :base_char, :standard_char]) |> lisp_bool()

                  _ ->
                    :t
                end

              true ->
                nil
            end

          :simple_base_string ->
            cond do
              is_binary(val) ->
                :t

              match?({:array, [_], _}, val) and simple_string_p(val) == :t ->
                {:array, [_], tid} = val

                case :ets.lookup(tid, :__meta__) do
                  [{:__meta__, meta}] ->
                    norm = normalize_type_spec(Map.get(meta, :element_type, :t))
                    (norm in [:character, :base_char, :standard_char]) |> lisp_bool()

                  _ ->
                    :t
                end

              true ->
                nil
            end

          :character ->
            characterp(val)

          :base_char ->
            (characterp(val) == :t and char_code(val) <= 127) |> lisp_bool()

          :standard_char ->
            standard_char_p(val)

          :extended_char ->
            (characterp(val) == :t and char_code(val) > 127) |> lisp_bool()

          :symbol ->
            symbolp(val)

          :keyword ->
            keywordp(val)

          :integer ->
            is_integer(val) |> lisp_bool()

          :fixnum ->
            (is_integer(val) and val >= -4_611_686_018_427_387_904 and
               val <= 4_611_686_018_427_387_903)
            |> lisp_bool()

          :bignum ->
            (is_integer(val) and
               (val < -4_611_686_018_427_387_904 or val > 4_611_686_018_427_387_903))
            |> lisp_bool()

          :float ->
            is_float(val) |> lisp_bool()

          :number ->
            (is_number(val) or match?(%ExLisp.Ratio{}, val)) |> lisp_bool()

          :ratio ->
            match?(%ExLisp.Ratio{}, val) |> lisp_bool()

          :rational ->
            (is_integer(val) or match?(%ExLisp.Ratio{}, val)) |> lisp_bool()

          :function ->
            (is_function(val) or match?(%ExLisp.Closure{}, val) or
               (is_atom(val) and ExLisp.Env.has_fun?(val)))
            |> lisp_bool()

          :hash_table ->
            match?({:hash_table, _, _}, val) |> lisp_bool()

          :array ->
            match?({:array, _, _}, val) |> lisp_bool()

          :simple_array ->
            simple_array_p(val)

          :bit_vector ->
            bit_vector_p(val)

          :simple_bit_vector ->
            simple_bit_vector_p(val)

          :bit ->
            (val in [0, 1]) |> lisp_bool()

          :structure ->
            match?({:struct, _, _}, val) |> lisp_bool()

          :standard_object ->
            match?({:instance, _, _}, val) |> lisp_bool()

          :unsigned_byte ->
            (is_integer(val) and val >= 0) |> lisp_bool()

          :signed_byte ->
            is_integer(val) |> lisp_bool()

          :boolean ->
            (val in [:t, nil]) |> lisp_bool()

          _ ->
            :t
        end
    end
  end

  def simple_array_p(val) do
    cond do
      is_binary(val) ->
        :t

      match?({:array, _, _}, val) ->
        {:array, _, tid} = val

        case :ets.lookup(tid, :__meta__) do
          [{:__meta__, meta}] ->
            fp = Map.get(meta, :fill_pointer, nil)
            adj = Map.get(meta, :adjustable, false)
            disp = Map.get(meta, :displaced_to, nil)
            (fp == nil and not adj and disp == nil) |> lisp_bool()

          _ ->
            nil
        end

      true ->
        nil
    end
  end

  def bit_vector_p({:array, [_], tid}) do
    case :ets.lookup(tid, :__meta__) do
      [{:__meta__, meta}] ->
        norm = normalize_type_spec(Map.get(meta, :element_type, :t))
        (norm in [:bit, :unsigned_byte_1, [0, 1], [:integer, 0, 1]]) |> lisp_bool()

      _ ->
        nil
    end
  end

  def bit_vector_p(_), do: nil

  def simple_bit_vector_p({:array, [_], tid}) do
    case :ets.lookup(tid, :__meta__) do
      [{:__meta__, meta}] ->
        fp = Map.get(meta, :fill_pointer, nil)
        adj = Map.get(meta, :adjustable, false)
        disp = Map.get(meta, :displaced_to, nil)
        norm = normalize_type_spec(Map.get(meta, :element_type, :t))

        (fp == nil and not adj and disp == nil and
           norm in [:bit, :unsigned_byte_1, [0, 1], [:integer, 0, 1]])
        |> lisp_bool()

      _ ->
        nil
    end
  end

  def simple_bit_vector_p(_), do: nil

  def array_element_type({:array, _, tid}) do
    case :ets.lookup(tid, :__meta__) do
      [{:__meta__, meta}] -> Map.get(meta, :element_type, :t)
      _ -> :t
    end
  end

  def array_element_type(s) when is_binary(s), do: :character
  def array_element_type(_), do: :t

  def array_rank({:array, dims, _}), do: Kernel.length(dims)
  def array_rank(s) when is_binary(s), do: 1
  def array_rank(_), do: 0

  def array_displacement({:array, _, tid}) do
    case :ets.lookup(tid, :__meta__) do
      [{:__meta__, %{displaced_to: target, displaced_index_offset: offset}}] ->
        [:_values_, [target, offset]]

      [{:__meta__, %{displaced_to: target}}] ->
        [:_values_, [target, 0]]

      _ ->
        [:_values_, [nil, 0]]
    end
  end

  def array_displacement(_), do: [:_values_, [nil, 0]]

  def array_row_major_index(args) when is_list(args) do
    case args do
      [{:array, dims, _} | indices] ->
        flat_indices =
          case indices do
            [single] when is_list(single) -> single
            _ -> indices
          end

        compute_flat_index(dims, flat_indices)

      [s, idx] when is_binary(s) and is_integer(idx) ->
        idx

      _ ->
        0
    end
  end

  def array_row_major_index(arr, idx), do: array_row_major_index([arr, idx])

  def bit(arr, idx), do: aref(arr, idx)
  def bit(args) when is_list(args), do: aref(args)
  def sbit(arr, idx), do: aref(arr, idx)
  def sbit(args) when is_list(args), do: aref(args)

  def primary_val([:_values_, [first | _]]), do: first
  def primary_val([:_values_, []]), do: nil
  def primary_val(other), do: other

  # --- List operations ---

  def rplaca([_head | tail], object), do: [object | tail]

  def rplaca(other, _object),
    do: raise(ArgumentError, "rplaca requires a cons cell, got: #{inspect(other)}")

  def rplaca(args) when is_list(args) do
    case args do
      [c, obj] -> rplaca(c, obj)
      _ -> raise ArgumentError, "rplaca requires 2 arguments"
    end
  end

  def rplacd([head | _tail], object), do: [head | object]

  def rplacd(other, _object),
    do: raise(ArgumentError, "rplacd requires a cons cell, got: #{inspect(other)}")

  def rplacd(args) when is_list(args) do
    case args do
      [c, obj] -> rplacd(c, obj)
      _ -> raise ArgumentError, "rplacd requires 2 arguments"
    end
  end

  def cons(head, nil), do: [primary_val(head)]
  def cons(head, []), do: [primary_val(head)]
  def cons(head, tail) when is_list(tail), do: [primary_val(head) | tail]

  def cons(head, tail) do
    h = primary_val(head)
    t = primary_val(tail)
    if t in [nil, []], do: [h], else: [h | t]
  end

  def car([head | _]), do: head
  def car(nil), do: nil
  def car([]), do: nil
  def car(other), do: raise(ArgumentError, "car requires a list or nil, got: #{inspect(other)}")

  def cdr([_ | tail]), do: tail
  def cdr(nil), do: nil
  def cdr([]), do: nil
  def cdr(other), do: raise(ArgumentError, "cdr requires a list or nil, got: #{inspect(other)}")

  def first(list), do: car(list)
  def rest(list), do: cdr(list)

  def caar(x), do: car(car(x))
  def cadr(x), do: car(cdr(x))
  def cdar(x), do: cdr(car(x))
  def cddr(x), do: cdr(cdr(x))

  def second(list), do: cadr(list)

  def caaar(x), do: car(car(car(x)))
  def caadr(x), do: car(car(cdr(x)))
  def cadar(x), do: car(cdr(car(x)))
  def caddr(x), do: car(cdr(cdr(x)))
  def cdaar(x), do: cdr(car(car(x)))
  def cdadr(x), do: cdr(car(cdr(x)))
  def cddar(x), do: cdr(cdr(car(x)))
  def cdddr(x), do: cdr(cdr(cdr(x)))

  def third(list), do: caddr(list)

  def caaaar(x), do: car(caaar(x))
  def caaadr(x), do: car(caadr(x))
  def caadar(x), do: car(cadar(x))
  def caaddr(x), do: car(caddr(x))
  def cadaar(x), do: car(cdaar(x))
  def cadadr(x), do: car(cdadr(x))
  def caddar(x), do: car(cddar(x))
  def cadddr(x), do: car(cdddr(x))
  def cdaaar(x), do: cdr(caaar(x))
  def cdaadr(x), do: cdr(caadr(x))
  def cdadar(x), do: cdr(cadar(x))
  def cdaddr(x), do: cdr(caddr(x))
  def cddaar(x), do: cdr(cdaar(x))
  def cddadr(x), do: cdr(cdadr(x))
  def cdddar(x), do: cdr(cddar(x))
  def cddddr(x), do: cdr(cdddr(x))

  def fourth(list), do: cadddr(list)
  def fifth(list) when is_list(list), do: Enum.at(list, 4, nil)
  def fifth(_), do: nil
  def sixth(list) when is_list(list), do: Enum.at(list, 5, nil)
  def sixth(_), do: nil
  def seventh(list) when is_list(list), do: Enum.at(list, 6, nil)
  def seventh(_), do: nil
  def eighth(list) when is_list(list), do: Enum.at(list, 7, nil)
  def eighth(_), do: nil
  def ninth(list) when is_list(list), do: Enum.at(list, 8, nil)
  def ninth(_), do: nil
  def tenth(list) when is_list(list), do: Enum.at(list, 9, nil)
  def tenth(_), do: nil

  def list(args) when is_list(args), do: Enum.map(args, &primary_val/1)

  def list_star([]), do: nil
  def list_star([x]) when x in [nil, []], do: []
  def list_star([x]), do: primary_val(x)

  def list_star([first | rest]) do
    tail = list_star(rest)

    if tail == [] do
      [primary_val(first)]
    else
      [primary_val(first) | tail]
    end
  end

  def append([]), do: nil
  def append([single]), do: single

  def append(lists) when is_list(lists) do
    norm_lists = normalize_raw_args(lists)

    case norm_lists do
      [] ->
        nil

      [single] ->
        single

      _ ->
        [last | rev_leading] = Enum.reverse(norm_lists)

        leading = Enum.reverse(rev_leading)

        Enum.each(leading, fn item ->
          case item do
            nil ->
              :ok

            [] ->
              :ok

            list when is_list(list) ->
              ensure_proper_list!(list)

            other ->
              raise ArgumentError,
                    "append requires proper list arguments except the last, got: #{inspect(other)}"
          end
        end)

        Enum.reduce(rev_leading, last, fn list, acc ->
          cond do
            list == nil or list == [] ->
              acc

            is_list(list) ->
              clean_list = normalize_raw_args(list)

              cond do
                acc in [nil, []] ->
                  clean_list

                is_list(acc) ->
                  clean_list ++ acc

                true ->
                  Enum.reduce(Enum.reverse(clean_list), acc, fn elem, tail -> [elem | tail] end)
              end

            true ->
              acc
          end
        end)
    end
  end

  defp ensure_proper_list!([]), do: :ok
  defp ensure_proper_list!([_ | tail]) when is_list(tail), do: ensure_proper_list!(tail)

  defp ensure_proper_list!(other),
    do: raise(ArgumentError, "expected proper list, got: #{inspect(other)}")

  def append(a, b), do: append([a, b])

  def nconc([]), do: nil
  def nconc([single]), do: single

  def nconc(lists) when is_list(lists) do
    norm_lists = normalize_raw_args(lists)

    case norm_lists do
      [] ->
        nil

      [single] ->
        single

      _ ->
        [last | rev_leading] = Enum.reverse(norm_lists)
        leading = Enum.reverse(rev_leading)

        Enum.reduce(Enum.reverse(leading), last, fn list, acc ->
          cond do
            list in [nil, []] ->
              acc

            is_list(list) ->
              cars = collect_cars_for_nconc(list, [])

              Enum.reduce(cars, acc, fn elem, tail ->
                [elem | tail]
              end)

            true ->
              raise ArgumentError,
                    "nconc requires list arguments except possibly the last, got: #{inspect(list)}"
          end
        end)
    end
  end

  def nconc(a, b), do: nconc([a, b])
  def nconc(a, b, c), do: nconc([a, b, c])
  def nconc(a, b, c, d), do: nconc([a, b, c, d])

  defp collect_cars_for_nconc([], acc), do: acc
  defp collect_cars_for_nconc([head, :., _tail | _], acc), do: [head | acc]

  defp collect_cars_for_nconc([head | tail], acc) when is_list(tail),
    do: collect_cars_for_nconc(tail, [head | acc])

  defp collect_cars_for_nconc([head | _tail], acc), do: [head | acc]

  def reverse(seq) do
    cond do
      seq in [nil, []] ->
        []

      is_binary(seq) ->
        String.reverse(seq)

      is_list(seq) ->
        try do
          :lists.reverse(seq)
        rescue
          _ -> safe_reverse(seq, [])
        end

      match?({:array, [_len], _tid}, seq) ->
        {:array, [_len], tid} = seq
        items = seq_to_list(seq)

        elem_type =
          case :ets.lookup(tid, :__meta__) do
            [{:__meta__, meta}] -> Map.get(meta, :element_type, :t)
            _ -> :t
          end

        make_array([
          Kernel.length(items),
          :initial_contents,
          Enum.reverse(items),
          :element_type,
          elem_type
        ])

      true ->
        seq
    end
  end

  defp safe_reverse([], acc), do: acc
  defp safe_reverse([head | tail], acc) when is_list(tail), do: safe_reverse(tail, [head | acc])
  defp safe_reverse([head | tail], acc) when tail in [nil, nil], do: [head | acc]
  defp safe_reverse([head | _tail], acc), do: [head | acc]

  def nreverse(seq) do
    cond do
      match?({:array, [_len], _tid}, seq) ->
        {:array, [_len], tid} = seq
        items = seq_to_list(seq)
        rev_items = Enum.reverse(items)

        Enum.with_index(rev_items)
        |> Enum.each(fn {val, idx} -> :ets.insert(tid, {idx, val}) end)

        seq

      true ->
        reverse(seq)
    end
  end

  def length(seq) do
    cond do
      seq in [nil, [], false] ->
        0

      is_list(seq) ->
        Kernel.length(seq)

      is_binary(seq) ->
        String.length(seq)

      match?({:array, _, _}, seq) ->
        {:array, dims, tid} = seq

        case :ets.lookup(tid, :__meta__) do
          [{:__meta__, %{fill_pointer: fp}}] when is_integer(fp) -> fp
          _ -> hd(dims)
        end

      true ->
        0
    end
  end

  defp test_match?(test_fn, item, candidate) do
    case test_fn do
      {:test_not, pred} -> not truthy?(invoke_fn(pred, [item, candidate]))
      pred -> truthy?(invoke_fn(pred, [item, candidate]))
    end
  end

  def nth(args) when is_list(args) do
    case args do
      [n, list] when is_integer(n) and n >= 0 ->
        if is_list(list), do: Enum.at(list, n, nil), else: nil

      [n, _list] when is_integer(n) and n < 0 ->
        raise ArgumentError, "nth index cannot be negative"

      _ ->
        nil
    end
  end

  def nth(n, list), do: nth([n, list])

  def nthcdr(args) when is_list(args) do
    case args do
      [n, list] when is_integer(n) and n >= 0 ->
        do_nthcdr(n, list)

      [n, _list] when is_integer(n) and n < 0 ->
        raise ArgumentError, "nthcdr index cannot be negative"

      [n, _list] ->
        raise ArgumentError, "nthcdr requires a non-negative integer index, got: #{inspect(n)}"

      _ ->
        raise ArgumentError, "nthcdr requires 2 arguments"
    end
  end

  def nthcdr(n, list) when is_integer(n) and n >= 0, do: do_nthcdr(n, list)

  def nthcdr(n, _list) when is_integer(n) and n < 0,
    do: raise(ArgumentError, "nthcdr index cannot be negative")

  def nthcdr(n, _list),
    do: raise(ArgumentError, "nthcdr requires a non-negative integer index, got: #{inspect(n)}")

  defp do_nthcdr(0, list), do: list
  defp do_nthcdr(n, [_, :., tail]) when n > 0, do: do_nthcdr(n - 1, tail)
  defp do_nthcdr(n, [_ | tail]) when n > 0 and is_list(tail), do: do_nthcdr(n - 1, tail)
  defp do_nthcdr(1, [_ | tail]), do: tail
  defp do_nthcdr(n, [_ | _]) when n > 1, do: raise(ArgumentError, "dotted tail in nthcdr")

  defp do_nthcdr(n, other) when n > 0 and other not in [nil, []],
    do: raise(ArgumentError, "expected list in nthcdr, got: #{inspect(other)}")

  defp do_nthcdr(_n, _other), do: nil

  def last(args) when is_list(args) do
    case args do
      [list] ->
        last(list, 1)

      [list, n] when is_integer(n) and n >= 0 ->
        last(list, n)

      [_, n] when is_integer(n) and n < 0 ->
        raise ArgumentError, "last n cannot be negative"

      [_, n] ->
        raise ArgumentError, "last requires a non-negative integer n, got: #{inspect(n)}"

      _ ->
        raise ArgumentError, "last requires 1 or 2 arguments"
    end
  end

  def last(list, n \\ 1)
  def last(list, _n) when list in [nil, []], do: nil

  def last(list, n) when is_integer(n) and n >= 0 do
    if not is_list(list) do
      raise ArgumentError, "last requires a list, got: #{inspect(list)}"
    end

    {tails, terminal} = collect_tails(list, [])
    k = length(tails)

    cond do
      n == 0 -> terminal
      n >= k -> list
      true -> Enum.at(tails, n - 1)
    end
  end

  def last(_list, n) when is_integer(n) and n < 0 do
    raise ArgumentError, "last n cannot be negative"
  end

  def last(_list, n) do
    raise ArgumentError, "last requires a non-negative integer n, got: #{inspect(n)}"
  end

  defp collect_tails([_ | tail] = cons, acc) when is_list(tail) do
    collect_tails(tail, [cons | acc])
  end

  defp collect_tails([_ | tail] = cons, acc) do
    {[cons | acc], tail}
  end

  defp collect_tails(other, acc) do
    {acc, other}
  end

  def butlast(args) when is_list(args) do
    case args do
      [list] ->
        butlast(list, 1)

      [list, n] when is_integer(n) and n >= 0 ->
        butlast(list, n)

      [_, n] when is_integer(n) and n < 0 ->
        raise ArgumentError, "butlast n cannot be negative"

      [_, n] ->
        raise ArgumentError, "butlast requires a non-negative integer n, got: #{inspect(n)}"

      _ ->
        raise ArgumentError, "butlast requires 1 or 2 arguments"
    end
  end

  def butlast(list, n \\ 1)
  def butlast(list, _n) when list in [nil, []], do: []

  def butlast(list, n) when is_integer(n) and n >= 0 do
    if not is_list(list) do
      raise ArgumentError, "butlast requires a list, got: #{inspect(list)}"
    end

    cars = collect_cars(list, [])
    k = length(cars)

    cond do
      n >= k -> []
      true -> Enum.take(cars, k - n)
    end
  end

  def butlast(_list, n) when is_integer(n) and n < 0 do
    raise ArgumentError, "butlast n cannot be negative"
  end

  def butlast(_list, n) do
    raise ArgumentError, "butlast requires a non-negative integer n, got: #{inspect(n)}"
  end

  defp collect_cars([head | tail], acc) when is_list(tail) do
    collect_cars(tail, [head | acc])
  end

  defp collect_cars([head | _non_list_tail], acc) do
    Enum.reverse([head | acc])
  end

  defp collect_cars(_, acc) do
    Enum.reverse(acc)
  end

  def nbutlast(args) when is_list(args), do: butlast(args)
  def nbutlast(list), do: butlast(list)
  def nbutlast(list, n), do: butlast(list, n)

  def member(args) when is_list(args) do
    case args do
      [item, list | rest_opts] when is_list(list) or list == nil ->
        opts = parse_lisp_keywords(rest_opts, [:key, :test, :test_not])
        key_fn = Keyword.get(opts, :key, nil)

        test_fn =
          cond do
            Keyword.has_key?(opts, :test_not) -> {:test_not, Keyword.get(opts, :test_not)}
            Keyword.has_key?(opts, :test) -> Keyword.get(opts, :test)
            true -> :eql
          end

        find_member_rec(item, list || [], test_fn, key_fn)

      [_, other | _] ->
        raise ArgumentError, "member requires a proper list, got: #{inspect(other)}"

      _ ->
        raise ArgumentError, "member requires at least 2 arguments"
    end
  end

  def member(item, list), do: member([item, list])

  defp find_member_rec(_item, [], _test_fn, _key_fn), do: nil

  defp find_member_rec(item, [head | tail] = list, test_fn, key_fn)
       when is_list(tail) or tail == nil do
    h_val = if key_fn, do: invoke_fn(key_fn, [head]), else: head

    if test_match?(test_fn, item, h_val) do
      list
    else
      find_member_rec(item, tail || [], test_fn, key_fn)
    end
  end

  defp find_member_rec(item, [head | tail] = list, test_fn, key_fn) do
    h_val = if key_fn, do: invoke_fn(key_fn, [head]), else: head

    if test_match?(test_fn, item, h_val) do
      list
    else
      raise ArgumentError, "member requires a proper list, got dotted tail: #{inspect(tail)}"
    end
  end

  defp find_member_rec(_item, other, _test_fn, _key_fn) do
    raise ArgumentError, "member requires a proper list, got: #{inspect(other)}"
  end

  def member_if(args) when is_list(args) do
    case args do
      [predicate, list | rest_opts] when is_list(list) or list == nil ->
        opts = parse_lisp_keywords(rest_opts, [:key])
        key_fn = Keyword.get(opts, :key, nil)
        find_member_if_rec(predicate, list || [], key_fn, true)

      [_, other | _] ->
        raise ArgumentError, "member-if requires a proper list, got: #{inspect(other)}"

      _ ->
        raise ArgumentError, "member-if requires at least 2 arguments"
    end
  end

  def member_if(predicate, list), do: member_if([predicate, list])

  def member_if_not(args) when is_list(args) do
    case args do
      [predicate, list | rest_opts] when is_list(list) or list == nil ->
        opts = parse_lisp_keywords(rest_opts, [:key])
        key_fn = Keyword.get(opts, :key, nil)
        find_member_if_rec(predicate, list || [], key_fn, false)

      [_, other | _] ->
        raise ArgumentError, "member-if-not requires a proper list, got: #{inspect(other)}"

      _ ->
        raise ArgumentError, "member-if-not requires at least 2 arguments"
    end
  end

  def member_if_not(predicate, list), do: member_if_not([predicate, list])

  defp find_member_if_rec(_pred, [], _key_fn, _expected), do: nil

  defp find_member_if_rec(pred, [head | tail] = list, key_fn, expected)
       when is_list(tail) or tail == nil do
    h_val = if key_fn, do: invoke_fn(key_fn, [head]), else: head
    res = truthy?(invoke_fn(pred, [h_val]))

    if (res and expected) or (not res and not expected) do
      list
    else
      find_member_if_rec(pred, tail || [], key_fn, expected)
    end
  end

  defp find_member_if_rec(pred, [head | tail] = list, key_fn, expected) do
    h_val = if key_fn, do: invoke_fn(key_fn, [head]), else: head
    res = truthy?(invoke_fn(pred, [h_val]))

    if (res and expected) or (not res and not expected) do
      list
    else
      raise ArgumentError, "member-if requires a proper list, got dotted tail: #{inspect(tail)}"
    end
  end

  defp find_member_if_rec(_pred, other, _key_fn, _expected) do
    raise ArgumentError, "member-if requires a proper list, got: #{inspect(other)}"
  end

  defp alist_key(entry) do
    case entry do
      [k, :., _v | _] -> k
      [k | _] -> k
      {k, _} -> k
      _ -> nil
    end
  end

  defp alist_val(entry) do
    case entry do
      [_, :., v | _] -> v
      [_ | tail] -> tail
      {_, v} -> v
      _ -> nil
    end
  end

  def acons(key, val, alist) do
    [[key | val] | if(alist in [nil, nil], do: [], else: alist)]
  end

  def acons(args) when is_list(args) do
    case args do
      [k, v, alist] -> acons(k, v, alist)
      _ -> raise ArgumentError, "acons requires 3 arguments"
    end
  end

  def assoc(args) when is_list(args) do
    case args do
      [item, alist | rest_opts] when is_list(alist) or alist == nil ->
        opts = parse_lisp_keywords(rest_opts, [:test, :test_not, :key])
        key_fn = Keyword.get(opts, :key, nil)

        test_fn =
          cond do
            Keyword.has_key?(opts, :test_not) -> {:test_not, Keyword.get(opts, :test_not)}
            Keyword.has_key?(opts, :test) -> Keyword.get(opts, :test)
            true -> :eql
          end

        Enum.find(alist || [], fn
          entry when is_list(entry) and entry != [] ->
            k = alist_key(entry)
            k_val = if key_fn, do: invoke_fn(key_fn, [k]), else: k
            test_match?(test_fn, item, k_val)

          {_k, _v} = entry ->
            k = alist_key(entry)
            k_val = if key_fn, do: invoke_fn(key_fn, [k]), else: k
            test_match?(test_fn, item, k_val)

          nil ->
            false

          other ->
            raise ArgumentError, "elements of alist must be cons or nil, got: #{inspect(other)}"
        end)

      [_, other | _] ->
        raise ArgumentError,
              "assoc requires a list or nil as second argument, got: #{inspect(other)}"

      _ ->
        raise ArgumentError, "assoc requires at least 2 arguments"
    end
  end

  def assoc(item, alist), do: assoc([item, alist])

  def assoc_if(args) when is_list(args) do
    case args do
      [predicate, alist | rest_opts] when is_list(alist) or alist == nil ->
        opts = parse_lisp_keywords(rest_opts, [:key])
        key_fn = Keyword.get(opts, :key, nil)

        Enum.find(alist || [], fn
          entry when is_list(entry) and entry != [] ->
            k = alist_key(entry)
            k_val = if key_fn, do: invoke_fn(key_fn, [k]), else: k
            truthy?(invoke_fn(predicate, [k_val]))

          {_k, _v} = entry ->
            k = alist_key(entry)
            k_val = if key_fn, do: invoke_fn(key_fn, [k]), else: k
            truthy?(invoke_fn(predicate, [k_val]))

          nil ->
            false

          other ->
            raise ArgumentError, "elements of alist must be cons or nil, got: #{inspect(other)}"
        end)

      [_, other | _] ->
        raise ArgumentError,
              "assoc-if requires a list or nil as second argument, got: #{inspect(other)}"

      _ ->
        raise ArgumentError, "assoc-if requires at least 2 arguments"
    end
  end

  def assoc_if(predicate, alist), do: assoc_if([predicate, alist])

  def assoc_if_not(args) when is_list(args) do
    case args do
      [predicate, alist | rest_opts] when is_list(alist) or alist == nil ->
        opts = parse_lisp_keywords(rest_opts, [:key])
        key_fn = Keyword.get(opts, :key, nil)

        Enum.find(alist || [], fn
          entry when is_list(entry) and entry != [] ->
            k = alist_key(entry)
            k_val = if key_fn, do: invoke_fn(key_fn, [k]), else: k
            not truthy?(invoke_fn(predicate, [k_val]))

          {_k, _v} = entry ->
            k = alist_key(entry)
            k_val = if key_fn, do: invoke_fn(key_fn, [k]), else: k
            not truthy?(invoke_fn(predicate, [k_val]))

          nil ->
            false

          other ->
            raise ArgumentError, "elements of alist must be cons or nil, got: #{inspect(other)}"
        end)

      [_, other | _] ->
        raise ArgumentError,
              "assoc-if-not requires a list or nil as second argument, got: #{inspect(other)}"

      _ ->
        raise ArgumentError, "assoc-if-not requires at least 2 arguments"
    end
  end

  def assoc_if_not(predicate, alist), do: assoc_if_not([predicate, alist])

  def rassoc(args) when is_list(args) do
    case args do
      [item, alist | rest_opts] when is_list(alist) or alist == nil ->
        opts = parse_lisp_keywords(rest_opts, [:test, :test_not, :key])
        key_fn = Keyword.get(opts, :key, nil)

        test_fn =
          cond do
            Keyword.has_key?(opts, :test_not) -> {:test_not, Keyword.get(opts, :test_not)}
            Keyword.has_key?(opts, :test) -> Keyword.get(opts, :test)
            true -> :eql
          end

        Enum.find(alist || [], fn
          entry when is_list(entry) and entry != [] ->
            v = alist_val(entry)
            v_val = if key_fn, do: invoke_fn(key_fn, [v]), else: v
            test_match?(test_fn, item, v_val)

          {_k, _v} = entry ->
            v = alist_val(entry)
            v_val = if key_fn, do: invoke_fn(key_fn, [v]), else: v
            test_match?(test_fn, item, v_val)

          nil ->
            false

          other ->
            raise ArgumentError, "elements of alist must be cons or nil, got: #{inspect(other)}"
        end)

      [_, other | _] ->
        raise ArgumentError,
              "rassoc requires a list or nil as second argument, got: #{inspect(other)}"

      _ ->
        raise ArgumentError, "rassoc requires at least 2 arguments"
    end
  end

  def rassoc(item, alist), do: rassoc([item, alist])

  def rassoc_if(args) when is_list(args) do
    case args do
      [predicate, alist | rest_opts] when is_list(alist) or alist == nil ->
        opts = parse_lisp_keywords(rest_opts, [:key])
        key_fn = Keyword.get(opts, :key, nil)

        Enum.find(alist || [], fn
          entry when is_list(entry) and entry != [] ->
            v = alist_val(entry)
            v_val = if key_fn, do: invoke_fn(key_fn, [v]), else: v
            truthy?(invoke_fn(predicate, [v_val]))

          {_k, _v} = entry ->
            v = alist_val(entry)
            v_val = if key_fn, do: invoke_fn(key_fn, [v]), else: v
            truthy?(invoke_fn(predicate, [v_val]))

          nil ->
            false

          other ->
            raise ArgumentError, "elements of alist must be cons or nil, got: #{inspect(other)}"
        end)

      [_, other | _] ->
        raise ArgumentError,
              "rassoc-if requires a list or nil as second argument, got: #{inspect(other)}"

      _ ->
        raise ArgumentError, "rassoc-if requires at least 2 arguments"
    end
  end

  def rassoc_if(predicate, alist), do: rassoc_if([predicate, alist])

  def rassoc_if_not(args) when is_list(args) do
    case args do
      [predicate, alist | rest_opts] when is_list(alist) or alist == nil ->
        opts = parse_lisp_keywords(rest_opts, [:key])
        key_fn = Keyword.get(opts, :key, nil)

        Enum.find(alist || [], fn
          entry when is_list(entry) and entry != [] ->
            v = alist_val(entry)
            v_val = if key_fn, do: invoke_fn(key_fn, [v]), else: v
            not truthy?(invoke_fn(predicate, [v_val]))

          {_k, _v} = entry ->
            v = alist_val(entry)
            v_val = if key_fn, do: invoke_fn(key_fn, [v]), else: v
            not truthy?(invoke_fn(predicate, [v_val]))

          nil ->
            false

          other ->
            raise ArgumentError, "elements of alist must be cons or nil, got: #{inspect(other)}"
        end)

      [_, other | _] ->
        raise ArgumentError,
              "rassoc-if-not requires a list or nil as second argument, got: #{inspect(other)}"

      _ ->
        raise ArgumentError, "rassoc-if-not requires at least 2 arguments"
    end
  end

  def rassoc_if_not(predicate, alist), do: rassoc_if_not([predicate, alist])

  def copy_list(args) when is_list(args) do
    case args do
      [list] when is_list(list) -> Enum.to_list(list)
      [other] -> other
      _ -> raise ArgumentError, "copy-list requires 1 argument"
    end
  end

  def copy_list(list) when is_list(list), do: Enum.to_list(list)
  def copy_list(other), do: other

  def copy_alist(args) when is_list(args) do
    case args do
      [alist] when is_list(alist) or alist == nil -> do_copy_alist(alist || [])
      [other] -> raise ArgumentError, "copy-alist requires a proper list, got: #{inspect(other)}"
      _ -> raise ArgumentError, "copy-alist requires 1 argument"
    end
  end

  def copy_alist(alist) when is_list(alist) or alist == nil, do: do_copy_alist(alist || [])

  def copy_alist(other),
    do: raise(ArgumentError, "copy-alist requires a proper list, got: #{inspect(other)}")

  defp do_copy_alist([head | tail]) when is_list(tail) do
    [copy_alist_entry(head) | do_copy_alist(tail)]
  end

  defp do_copy_alist([]), do: []

  defp do_copy_alist(other),
    do: raise(ArgumentError, "copy-alist requires a proper list, got: #{inspect(other)}")

  defp copy_alist_entry([k, :., v | _]), do: [k, :., v]
  defp copy_alist_entry([k | v]), do: [k | v]
  defp copy_alist_entry({k, v}), do: {k, v}
  defp copy_alist_entry(other), do: other

  def revappend(args) when is_list(args) do
    case args do
      [list1, list2] ->
        l1 = if is_list(list1), do: list1, else: []
        l2 = if list2 in [nil, []], do: [], else: list2

        if is_list(l2) do
          Enum.reverse(l1) ++ l2
        else
          Enum.reduce(l1, l2, fn elem, acc -> [elem | acc] end)
        end

      _ ->
        raise ArgumentError, "revappend requires 2 arguments"
    end
  end

  def revappend(list1, list2), do: revappend([list1, list2])
  def nreconc(args) when is_list(args), do: revappend(args)
  def nreconc(list1, list2), do: revappend([list1, list2])

  def tree_equal(args) when is_list(args) do
    case args do
      [tree1, tree2 | rest_opts] ->
        opts = parse_lisp_keywords(rest_opts, [:test, :test_not])

        test_fn =
          cond do
            Keyword.has_key?(opts, :test_not) -> {:test_not, Keyword.get(opts, :test_not)}
            Keyword.has_key?(opts, :test) -> Keyword.get(opts, :test)
            true -> :eql
          end

        tree_equal_rec(tree1, tree2, test_fn) |> lisp_bool()

      _ ->
        raise ArgumentError, "tree-equal requires at least 2 arguments"
    end
  end

  def tree_equal(tree1, tree2), do: tree_equal([tree1, tree2])

  defp tree_equal_rec(tree1, tree2, test_fn) do
    cond do
      is_list(tree1) and is_list(tree2) ->
        case {tree1, tree2} do
          {[], []} ->
            true

          {[h1, :., t1], [h2, :., t2]} ->
            tree_equal_rec(h1, h2, test_fn) and tree_equal_rec(t1, t2, test_fn)

          {[h1 | t1], [h2 | t2]} ->
            tree_equal_rec(h1, h2, test_fn) and tree_equal_rec(t1, t2, test_fn)

          _ ->
            false
        end

      not is_list(tree1) and not is_list(tree2) ->
        test_match?(test_fn, tree1, tree2)

      true ->
        false
    end
  end

  def copy_tree(args) when is_list(args) do
    case args do
      [tree] -> do_copy_tree(tree)
      _ -> raise ArgumentError, "copy-tree requires 1 argument"
    end
  end

  def copy_tree(tree), do: do_copy_tree(tree)

  defp do_copy_tree([head, :., tail]) do
    [do_copy_tree(head), :., do_copy_tree(tail)]
  end

  defp do_copy_tree([head | tail]) when not is_list(tail) do
    [do_copy_tree(head) | do_copy_tree(tail)]
  end

  defp do_copy_tree([head | tail]) do
    [do_copy_tree(head) | do_copy_tree(tail)]
  end

  defp do_copy_tree([]), do: []
  defp do_copy_tree(other), do: other

  def tailp(args) when is_list(args) do
    case args do
      [sublist, list] -> tailp(sublist, list)
      _ -> raise ArgumentError, "tailp requires 2 arguments"
    end
  end

  def tailp(sublist, list) do
    do_tailp(sublist, list) |> lisp_bool()
  end

  defp do_tailp(sublist, curr) do
    cond do
      curr == sublist ->
        true

      curr in [nil, []] ->
        false

      is_list(curr) ->
        case curr do
          [_ | tail] -> do_tailp(sublist, tail)
        end

      true ->
        false
    end
  end

  def ldiff(args) when is_list(args) do
    case args do
      [list, sublist] when is_list(list) or list == nil ->
        ldiff(list, sublist)

      [other, _sublist] ->
        raise ArgumentError, "ldiff requires a list as first argument, got: #{inspect(other)}"

      _ ->
        raise ArgumentError, "ldiff requires 2 arguments"
    end
  end

  def ldiff(list, sublist) when is_list(list) or list == nil do
    do_ldiff(list || [], sublist, [])
  end

  def ldiff(other, _sublist) do
    raise ArgumentError, "ldiff requires a list as first argument, got: #{inspect(other)}"
  end

  defp do_ldiff(curr, object, acc) do
    cond do
      curr === object ->
        Enum.reverse(acc)

      curr in [nil, []] ->
        Enum.reverse(acc)

      is_list(curr) ->
        case curr do
          [head, :., tail] ->
            if [head, :., tail] === object do
              Enum.reverse(acc)
            else
              do_ldiff(tail, object, [head | acc])
            end

          [head | tail] when is_list(tail) ->
            do_ldiff(tail, object, [head | acc])

          [head | tail] ->
            if tail === object do
              Enum.reverse([head | acc])
            else
              reconstruct_improper([head | acc], tail)
            end
        end

      true ->
        reconstruct_improper(acc, curr)
    end
  end

  defp reconstruct_improper([], tail), do: tail

  defp reconstruct_improper([head | rest], tail) do
    reconstruct_improper(rest, [head | tail])
  end

  def list_length(list) when list in [nil, []], do: 0

  def list_length(list) when is_list(list) do
    count_list_length(list, 0)
  end

  def list_length(other),
    do: raise(ArgumentError, "list-length requires a list, got: #{inspect(other)}")

  defp count_list_length([], count), do: count

  defp count_list_length([_ | tail], count) when is_list(tail),
    do: count_list_length(tail, count + 1)

  defp count_list_length([_ | _], _count), do: raise(ArgumentError, "dotted list")

  def adjoin(args) when is_list(args) do
    case args do
      [item, list | rest_opts] when is_list(list) or list == nil ->
        opts = parse_lisp_keywords(rest_opts, [:key, :test, :test_not])
        key_fn = Keyword.get(opts, :key, nil)

        test_fn =
          cond do
            Keyword.has_key?(opts, :test_not) -> {:test_not, Keyword.get(opts, :test_not)}
            Keyword.has_key?(opts, :test) -> Keyword.get(opts, :test)
            true -> :eql
          end

        item_key = if key_fn, do: invoke_fn(key_fn, [item]), else: item

        found =
          Enum.any?(list || [], fn elem ->
            elem_key = if key_fn, do: invoke_fn(key_fn, [elem]), else: elem
            test_match?(test_fn, item_key, elem_key)
          end)

        if found do
          list
        else
          [item | list || []]
        end

      [_, other | _] ->
        raise ArgumentError, "adjoin requires a proper list, got: #{inspect(other)}"

      _ ->
        raise ArgumentError, "adjoin requires at least 2 arguments"
    end
  end

  def adjoin(item, list), do: adjoin([item, list])

  def union(args) when is_list(args) do
    case args do
      [list1, list2 | rest_opts] ->
        opts = parse_lisp_keywords(rest_opts, [:key, :test, :test_not])
        key_fn = Keyword.get(opts, :key, nil)

        test_fn =
          cond do
            Keyword.has_key?(opts, :test_not) -> {:test_not, Keyword.get(opts, :test_not)}
            Keyword.has_key?(opts, :test) -> Keyword.get(opts, :test)
            true -> :eql
          end

        if not (is_list(list1) or list1 == nil) do
          raise ArgumentError, "union requires a proper list, got: #{inspect(list1)}"
        end

        if not (is_list(list2) or list2 == nil) do
          raise ArgumentError, "union requires a proper list, got: #{inspect(list2)}"
        end

        l1 = if is_list(list1), do: list1, else: []
        l2 = if is_list(list2), do: list2, else: []

        Enum.reduce(l1, l2, fn elem, acc ->
          target_key = if key_fn, do: invoke_fn(key_fn, [elem]), else: elem

          exists =
            Enum.any?(l2, fn x ->
              k_val = if key_fn, do: invoke_fn(key_fn, [x]), else: x
              test_match?(test_fn, target_key, k_val)
            end)

          if exists, do: acc, else: [elem | acc]
        end)

      _ ->
        raise ArgumentError, "union requires at least 2 arguments"
    end
  end

  def union(list1, list2), do: union([list1, list2])
  def nunion(args) when is_list(args), do: union(args)
  def nunion(list1, list2), do: union([list1, list2])

  def intersection(args) when is_list(args) do
    case args do
      [list1, list2 | rest_opts] ->
        opts = parse_lisp_keywords(rest_opts, [:key, :test, :test_not])
        key_fn = Keyword.get(opts, :key, nil)

        test_fn =
          cond do
            Keyword.has_key?(opts, :test_not) -> {:test_not, Keyword.get(opts, :test_not)}
            Keyword.has_key?(opts, :test) -> Keyword.get(opts, :test)
            true -> :eql
          end

        l1 = if is_list(list1), do: list1, else: []
        l2 = if is_list(list2), do: list2, else: []

        Enum.filter(l1, fn elem ->
          target_key = if key_fn, do: invoke_fn(key_fn, [elem]), else: elem

          Enum.any?(l2, fn x ->
            k_val = if key_fn, do: invoke_fn(key_fn, [x]), else: x
            test_match?(test_fn, target_key, k_val)
          end)
        end)

      _ ->
        raise ArgumentError, "intersection requires at least 2 arguments"
    end
  end

  def intersection(list1, list2), do: intersection([list1, list2])
  def nintersection(args) when is_list(args), do: intersection(args)
  def nintersection(list1, list2), do: intersection([list1, list2])

  def set_difference(args) when is_list(args) do
    case args do
      [list1, list2 | rest_opts] ->
        opts = parse_lisp_keywords(rest_opts, [:key, :test, :test_not])
        key_fn = Keyword.get(opts, :key, nil)

        test_fn =
          cond do
            Keyword.has_key?(opts, :test_not) -> {:test_not, Keyword.get(opts, :test_not)}
            Keyword.has_key?(opts, :test) -> Keyword.get(opts, :test)
            true -> :eql
          end

        l1 = if is_list(list1), do: list1, else: []
        l2 = if is_list(list2), do: list2, else: []

        Enum.filter(l1, fn elem ->
          target_key = if key_fn, do: invoke_fn(key_fn, [elem]), else: elem

          not Enum.any?(l2, fn x ->
            k_val = if key_fn, do: invoke_fn(key_fn, [x]), else: x
            test_match?(test_fn, target_key, k_val)
          end)
        end)

      _ ->
        raise ArgumentError, "set-difference requires at least 2 arguments"
    end
  end

  def set_difference(list1, list2), do: set_difference([list1, list2])
  def nset_difference(args) when is_list(args), do: set_difference(args)
  def nset_difference(list1, list2), do: set_difference([list1, list2])

  def set_exclusive_or(args) when is_list(args) do
    case args do
      [list1, list2 | rest_opts] ->
        opts = parse_lisp_keywords(rest_opts, [:key, :test, :test_not])
        key_fn = Keyword.get(opts, :key, nil)

        test_fn =
          cond do
            Keyword.has_key?(opts, :test_not) -> {:test_not, Keyword.get(opts, :test_not)}
            Keyword.has_key?(opts, :test) -> Keyword.get(opts, :test)
            true -> :eql
          end

        l1 = if is_list(list1), do: list1, else: []
        l2 = if is_list(list2), do: list2, else: []

        diff1 =
          Enum.filter(l1, fn elem ->
            target_key = if key_fn, do: invoke_fn(key_fn, [elem]), else: elem

            not Enum.any?(l2, fn x ->
              k_val = if key_fn, do: invoke_fn(key_fn, [x]), else: x
              test_match?(test_fn, target_key, k_val)
            end)
          end)

        diff2 =
          Enum.filter(l2, fn elem ->
            target_key = if key_fn, do: invoke_fn(key_fn, [elem]), else: elem

            not Enum.any?(l1, fn x ->
              k_val = if key_fn, do: invoke_fn(key_fn, [x]), else: x
              test_match?(test_fn, k_val, target_key)
            end)
          end)

        diff1 ++ diff2

      _ ->
        raise ArgumentError, "set-exclusive-or requires at least 2 arguments"
    end
  end

  def set_exclusive_or(list1, list2), do: set_exclusive_or([list1, list2])
  def nset_exclusive_or(args) when is_list(args), do: set_exclusive_or(args)
  def nset_exclusive_or(list1, list2), do: set_exclusive_or([list1, list2])

  def subsetp(args) when is_list(args) do
    case args do
      [list1, list2 | rest_opts] ->
        opts = parse_lisp_keywords(rest_opts, [:key, :test, :test_not])
        key_fn = Keyword.get(opts, :key, nil)

        test_fn =
          cond do
            Keyword.has_key?(opts, :test_not) -> {:test_not, Keyword.get(opts, :test_not)}
            Keyword.has_key?(opts, :test) -> Keyword.get(opts, :test)
            true -> :eql
          end

        l1 = if is_list(list1), do: list1, else: []
        l2 = if is_list(list2), do: list2, else: []

        Enum.all?(l1, fn elem ->
          target_key = if key_fn, do: invoke_fn(key_fn, [elem]), else: elem

          Enum.any?(l2, fn x ->
            k_val = if key_fn, do: invoke_fn(key_fn, [x]), else: x
            test_match?(test_fn, target_key, k_val)
          end)
        end)
        |> lisp_bool()

      _ ->
        raise ArgumentError, "subsetp requires at least 2 arguments"
    end
  end

  def subsetp(list1, list2), do: subsetp([list1, list2])

  def pairlis(args) when is_list(args) do
    case args do
      [keys, values] -> pairlis(keys, values, [])
      [keys, values, alist] -> pairlis(keys, values, alist)
      _ -> raise ArgumentError, "pairlis requires 2 or 3 arguments"
    end
  end

  def pairlis(keys, values, alist) do
    k_list = if is_list(keys), do: keys, else: []
    v_list = if is_list(values), do: values, else: []

    if length(k_list) != length(v_list) do
      raise ArgumentError, "pairlis keys and values must have the same length"
    end

    base_alist = if alist in [nil, []], do: [], else: alist

    Enum.zip(k_list, v_list)
    |> Enum.reverse()
    |> Enum.reduce(base_alist, fn {k, v}, acc ->
      [[k | v] | acc]
    end)
  end

  def mapcar(args) when is_list(args) do
    case args do
      [fn_val, single_list] ->
        mapcar(fn_val, single_list)

      [fn_val | lists] when lists != [] ->
        list_arrays = Enum.map(lists, &ensure_list_arg/1)
        do_mapcar_n(list_arrays, fn_val, [])

      _ ->
        raise ArgumentError, "mapcar requires a function and at least one list"
    end
  end

  def mapcar(fn_val, list) when is_list(list) or list == nil do
    do_mapcar1(list || [], fn_val, [])
  end

  def mapcar(fn_val, other) do
    do_mapcar1(ensure_list_arg(other), fn_val, [])
  end

  defp do_mapcar1([], _fn_val, acc), do: Enum.reverse(acc)

  defp do_mapcar1([h | t], fn_val, acc) when is_function(fn_val, 1) do
    do_mapcar1(t, fn_val, [fn_val.(unwrap_mv_primary(h)) | acc])
  end

  defp do_mapcar1([h | t], fn_val, acc) do
    do_mapcar1(t, fn_val, [invoke_fn(fn_val, [h]) | acc])
  end

  defp do_mapcar_n(lists, fn_val, acc) do
    if Enum.any?(lists, &(&1 == [] or &1 == nil)) do
      Enum.reverse(acc)
    else
      heads = Enum.map(lists, fn [h | _] -> h end)
      tails = Enum.map(lists, fn [_ | t] -> t end)
      res = invoke_fn(fn_val, heads)
      do_mapcar_n(tails, fn_val, [res | acc])
    end
  end

  def mapc(args) when is_list(args) do
    case args do
      [fn_val, single_list] ->
        mapc(fn_val, single_list)

      [fn_val | lists] when lists != [] ->
        list_arrays = Enum.map(lists, &ensure_list_arg/1)
        do_mapc_n(list_arrays, fn_val)
        hd(lists)

      _ ->
        raise ArgumentError, "mapc requires a function and at least one list"
    end
  end

  def mapc(fn_val, list) when is_list(list) or list == nil do
    do_mapc1(list || [], fn_val)
    list
  end

  def mapc(fn_val, other) do
    lst = ensure_list_arg(other)
    do_mapc1(lst, fn_val)
    other
  end

  defp do_mapc1([], _fn_val), do: :ok

  defp do_mapc1([h | t], fn_val) when is_function(fn_val, 1) do
    fn_val.(unwrap_mv_primary(h))
    do_mapc1(t, fn_val)
  end

  defp do_mapc1([h | t], fn_val) do
    invoke_fn(fn_val, [h])
    do_mapc1(t, fn_val)
  end

  defp do_mapc_n(lists, fn_val) do
    if Enum.any?(lists, &(&1 == [] or &1 == nil)) do
      :ok
    else
      heads = Enum.map(lists, fn [h | _] -> h end)
      tails = Enum.map(lists, fn [_ | t] -> t end)
      invoke_fn(fn_val, heads)
      do_mapc_n(tails, fn_val)
    end
  end

  def mapcan(args) when is_list(args) do
    case args do
      [_fn_val | lists] when lists != [] ->
        res_lists = mapcar(args)
        append(res_lists)

      _ ->
        raise ArgumentError, "mapcan requires a function and at least one list"
    end
  end

  def mapcan(fn_val, list), do: mapcan([fn_val, list])

  def maplist(args) when is_list(args) do
    case args do
      [fn_val | lists] when lists != [] ->
        list_arrays = Enum.map(lists, &ensure_list_arg/1)
        do_maplist_rec(fn_val, list_arrays, [])

      _ ->
        raise ArgumentError, "maplist requires a function and at least one list"
    end
  end

  def maplist(fn_val, list), do: maplist([fn_val, list])

  defp do_maplist_rec(fn_val, lists, acc) do
    if Enum.any?(lists, &(&1 == [] or &1 == nil)) do
      Enum.reverse(acc)
    else
      res = invoke_fn(fn_val, lists)
      tails = Enum.map(lists, fn [_ | t] -> t end)
      do_maplist_rec(fn_val, tails, [res | acc])
    end
  end

  def mapl(args) when is_list(args) do
    case args do
      [_fn_val | lists] when lists != [] ->
        maplist(args)
        hd(lists)

      _ ->
        raise ArgumentError, "mapl requires a function and at least one list"
    end
  end

  def mapl(fn_val, list), do: mapl([fn_val, list])

  def mapcon(args) when is_list(args) do
    case args do
      [_fn_val | lists] when lists != [] ->
        res_lists = maplist(args)
        append(res_lists)

      _ ->
        raise ArgumentError, "mapcon requires a function and at least one list"
    end
  end

  def mapcon(fn_val, list), do: mapcon([fn_val, list])

  defp ensure_list_arg(l) when is_list(l), do: l
  defp ensure_list_arg(nil), do: []

  defp ensure_list_arg(other),
    do: raise(ArgumentError, "expected a proper list, got: #{inspect(other)}")

  defp is_string_type?(type_spec) do
    norm = normalize_type_spec(type_spec)

    cond do
      norm in [:string, :simple_string, :base_string, :simple_base_string] ->
        true

      is_list(norm) and hd(norm) in [:string, :simple_string, :base_string, :simple_base_string] ->
        true

      is_list(norm) and hd(norm) in [:vector, :simple_vector, :array, :simple_array] ->
        case norm do
          [_hd, et | _] ->
            normalize_type_spec(et) in [:character, :base_char, :standard_char]

          _ ->
            false
        end

      true ->
        false
    end
  end

  defp is_bit_vector_type?(type_spec) do
    norm = normalize_type_spec(type_spec)

    cond do
      norm in [:bit_vector, :simple_bit_vector] ->
        true

      is_list(norm) and hd(norm) in [:bit_vector, :simple_bit_vector] ->
        true

      is_list(norm) and hd(norm) in [:vector, :simple_vector, :array, :simple_array] ->
        case norm do
          [_hd, et | _] ->
            normalize_type_spec(et) in [:bit, :unsigned_byte_1, [0, 1], [:integer, 0, 1]]

          _ ->
            false
        end

      true ->
        false
    end
  end

  def coerce_list_to_type(list, type_spec) do
    norm = normalize_type_spec(type_spec)

    cond do
      norm == :sequence ->
        raise ArgumentError, "Cannot coerce to abstract sequence type"

      norm in [:cons] ->
        if list == [] do
          raise ArgumentError, "Cannot coerce empty list to cons"
        else
          list
        end

      norm in [nil, :null] ->
        if list != [] do
          raise ArgumentError, "Cannot coerce non-empty list to null"
        else
          []
        end

      norm == :list ->
        list

      norm in [
        :fixnum,
        :integer,
        :symbol,
        :number,
        :float,
        :ratio,
        :rational,
        :character,
        :hash_table,
        :function,
        :package,
        :boolean
      ] ->
        raise ArgumentError, "#{inspect(type_spec)} is not a sequence type"

      is_list(norm) ->
        head = hd(norm)

        if head not in [
             :vector,
             :simple_vector,
             :array,
             :simple_array,
             :string,
             :simple_string,
             :base_string,
             :simple_base_string,
             :bit_vector,
             :simple_bit_vector,
             :list,
             :cons,
             :null,
             :values
           ] do
          raise ArgumentError, "#{inspect(type_spec)} is not a sequence type"
        end

        fixed_size =
          case norm do
            [:vector, _et, s | _] when is_integer(s) -> s
            [:vector, s | _] when is_integer(s) -> s
            [:simple_vector, s | _] when is_integer(s) -> s
            [:bit_vector, s | _] when is_integer(s) -> s
            [:simple_bit_vector, s | _] when is_integer(s) -> s
            [:string, s | _] when is_integer(s) -> s
            [:simple_string, s | _] when is_integer(s) -> s
            [:base_string, s | _] when is_integer(s) -> s
            [:simple_base_string, s | _] when is_integer(s) -> s
            [:array, _et, [s | _] | _] when is_integer(s) -> s
            [:simple_array, _et, [s | _] | _] when is_integer(s) -> s
            _ -> nil
          end

        if fixed_size != nil and Kernel.length(list) != fixed_size do
          raise ArgumentError,
                "Sequence length #{Kernel.length(list)} does not match type specifier size #{fixed_size}"
        end

        cond do
          head in [:list, :cons, :null] ->
            if head == :cons and list == [],
              do: raise(ArgumentError, "Cannot coerce empty list to cons")

            if head == :null and list != [],
              do: raise(ArgumentError, "Cannot coerce non-empty list to null")

            list

          is_string_type?(norm) ->
            list
            |> Enum.map(fn
              c when is_integer(c) -> c
              <<c::utf8>> -> c
              c -> char_code(c)
            end)
            |> List.to_string()

          is_bit_vector_type?(norm) ->
            make_array([Kernel.length(list), :initial_contents, list, :element_type, :bit])

          true ->
            elem_type =
              case norm do
                [_h, et | _] when not is_integer(et) -> normalize_type_spec(et)
                _ -> :t
              end

            make_array([Kernel.length(list), :initial_contents, list, :element_type, elem_type])
        end

      is_string_type?(norm) ->
        list
        |> Enum.map(fn
          c when is_integer(c) -> c
          <<c::utf8>> -> c
          c -> char_code(c)
        end)
        |> List.to_string()

      is_bit_vector_type?(norm) ->
        make_array([Kernel.length(list), :initial_contents, list, :element_type, :bit])

      norm in [:vector, :simple_vector] ->
        make_array([Kernel.length(list), :initial_contents, list])

      true ->
        list
    end
  end

  def seq_to_list(seq) do
    cond do
      seq in [nil, [], false] ->
        []

      is_list(seq) ->
        seq

      is_binary(seq) ->
        String.to_charlist(seq)

      match?({:array, _dims, _tid}, seq) ->
        {:array, [dim | _], tid} = seq

        actual_len =
          case :ets.lookup(tid, :__meta__) do
            [{:__meta__, %{fill_pointer: fp}}] when is_integer(fp) -> fp
            [{:__meta__, %{dimensions: [new_dim | _]}}] when is_integer(new_dim) -> new_dim
            _ -> dim
          end

        if actual_len <= 0 do
          []
        else
          for i <- 0..(actual_len - 1), do: aref([seq, i])
        end

      true ->
        []
    end
  end

  def make_list(args) when is_list(args) do
    case args do
      [size | rest] when is_integer(size) and size >= 0 ->
        opts = parse_lisp_keywords(rest, [:initial_element])
        initial_element = Keyword.get(opts, :initial_element, nil)
        if size == 0, do: [], else: List.duplicate(initial_element, size)

      [size] when is_integer(size) and size >= 0 ->
        if size == 0, do: [], else: List.duplicate(nil, size)

      _ ->
        raise ArgumentError, "make-list requires non-negative integer size"
    end
  end

  def make_list(size), do: make_list([size])

  def make_sequence(args) when is_list(args) do
    case args do
      [result_type, size, single_elem]
      when is_integer(size) and size >= 0 and
             single_elem not in [
               :initial_element,
               :_cl_initial_element_,
               :"initial-element",
               :":initial-element"
             ] ->
        make_sequence([result_type, size, :initial_element, single_elem])

      [result_type, size | rest] when is_integer(size) and size >= 0 ->
        opts = parse_lisp_keywords(rest, [:initial_element])
        has_init = Keyword.has_key?(opts, :initial_element)
        init_elem = Keyword.get(opts, :initial_element, nil)

        norm = normalize_type_spec(result_type)

        if norm == :sequence do
          raise ArgumentError, "make-sequence cannot create abstract type sequence"
        end

        if norm in [
             :fixnum,
             :integer,
             :symbol,
             :number,
             :float,
             :ratio,
             :rational,
             :character,
             :hash_table,
             :function,
             :package,
             :boolean
           ] do
          raise ArgumentError, "#{inspect(result_type)} is not a sequence type"
        end

        if is_list(norm) do
          head = hd(norm)

          if head not in [
               :vector,
               :simple_vector,
               :array,
               :simple_array,
               :string,
               :simple_string,
               :base_string,
               :simple_base_string,
               :bit_vector,
               :simple_bit_vector,
               :list,
               :cons,
               :null,
               :values
             ] do
            raise ArgumentError, "#{inspect(result_type)} is not a sequence type"
          end

          fixed_size =
            case norm do
              [:vector, _et, s | _] when is_integer(s) -> s
              [:vector, s | _] when is_integer(s) -> s
              [:simple_vector, s | _] when is_integer(s) -> s
              [:bit_vector, s | _] when is_integer(s) -> s
              [:simple_bit_vector, s | _] when is_integer(s) -> s
              [:string, s | _] when is_integer(s) -> s
              [:simple_string, s | _] when is_integer(s) -> s
              [:base_string, s | _] when is_integer(s) -> s
              [:simple_base_string, s | _] when is_integer(s) -> s
              [:array, _et, [s | _] | _] when is_integer(s) -> s
              [:simple_array, _et, [s | _] | _] when is_integer(s) -> s
              _ -> nil
            end

          if fixed_size != nil and size != fixed_size do
            raise ArgumentError,
                  "size #{size} does not match type specifier size #{fixed_size}"
          end
        end

        cond do
          norm in [:cons] ->
            if size == 0 do
              raise ArgumentError, "make-sequence cannot create cons of size 0"
            else
              List.duplicate(init_elem, size)
            end

          norm in [nil, :null] ->
            if size > 0 do
              raise ArgumentError, "make-sequence cannot create null of size #{size}"
            else
              []
            end

          norm == :list or (is_list(norm) and hd(norm) in [:list, :cons, :null]) ->
            if size == 0, do: [], else: List.duplicate(init_elem, size)

          is_string_type?(norm) ->
            ch =
              cond do
                has_init and is_integer(init_elem) ->
                  init_elem

                has_init and is_binary(init_elem) and byte_size(init_elem) > 0 ->
                  :binary.first(init_elem)

                has_init and characterp(init_elem) == :t ->
                  char_code(init_elem)

                true ->
                  0
              end

            if size == 0, do: "", else: List.duplicate(ch, size) |> List.to_string()

          is_bit_vector_type?(norm) ->
            val = if has_init, do: init_elem, else: 0
            make_array([size, :initial_element, val, :element_type, :bit])

          true ->
            elem_type =
              case norm do
                [_h, et | _] when not is_integer(et) -> normalize_type_spec(et)
                _ -> :t
              end

            if has_init do
              make_array([size, :initial_element, init_elem, :element_type, elem_type])
            else
              make_array([size, :element_type, elem_type])
            end
        end

      [result_type, size] when is_integer(size) and size >= 0 ->
        make_sequence([result_type, size])

      _ ->
        raise ArgumentError, "make-sequence requires result-type and non-negative integer size"
    end
  end

  def make_sequence(type, size), do: make_sequence([type, size])
  def make_sequence(type, size, init), do: make_sequence([type, size, :initial_element, init])

  def concatenate(args) when is_list(args) do
    case args do
      [result_type | seqs] ->
        all_elements =
          seqs
          |> Enum.flat_map(&seq_to_list/1)

        coerce_list_to_type(all_elements, result_type)

      _ ->
        raise ArgumentError, "concatenate requires at least result-type"
    end
  end

  def concatenate(result_type), do: coerce_list_to_type([], result_type)

  def concatenate(result_type, seqs) when is_list(seqs) do
    concatenate([result_type | seqs])
  end

  def map(args) when is_list(args) do
    case args do
      [result_type, fn_arg | seqs] when seqs != [] ->
        lists = Enum.map(seqs, &seq_to_list/1)
        results = do_map_zip(lists, fn_arg, [])
        norm = normalize_type_spec(result_type)

        if norm in [nil, :null] do
          nil
        else
          coerce_list_to_type(results, result_type)
        end

      _ ->
        raise ArgumentError, "map requires result-type, function, and at least one sequence"
    end
  end

  def map(result_type, fn_arg, seq1), do: map([result_type, fn_arg, seq1])
  def map(result_type, fn_arg, seq1, seq2), do: map([result_type, fn_arg, seq1, seq2])

  defp do_map_zip(lists, fn_arg, acc) do
    if Enum.any?(lists, &(&1 == [])) do
      Enum.reverse(acc)
    else
      heads = Enum.map(lists, &hd/1)
      tails = Enum.map(lists, &tl/1)
      res = invoke_fn(fn_arg, heads)
      do_map_zip(tails, fn_arg, [res | acc])
    end
  end

  def map_into(args) when is_list(args) do
    case args do
      [res_seq, fn_arg | sequences] ->
        res_len = length(res_seq)
        seq_lists = Enum.map(sequences, &seq_to_list/1)

        max_count =
          if seq_lists == [] do
            res_len
          else
            Enum.min([res_len | Enum.map(seq_lists, &Kernel.length/1)])
          end

        new_elements =
          if max_count == 0 do
            []
          else
            for i <- 0..(max_count - 1) do
              args_for_i = Enum.map(seq_lists, &Enum.at(&1, i))
              invoke_fn(fn_arg, args_for_i)
            end
          end

        cond do
          match?({:array, [_], _}, res_seq) ->
            {:array, [_], tid} = res_seq

            Enum.with_index(new_elements)
            |> Enum.each(fn {val, idx} -> :ets.insert(tid, {idx, val}) end)

            case :ets.lookup(tid, :__meta__) do
              [{:__meta__, %{fill_pointer: fp} = meta}] when is_integer(fp) ->
                :ets.insert(tid, {:__meta__, %{meta | fill_pointer: Kernel.length(new_elements)}})

              _ ->
                :ok
            end

            res_seq

          is_list(res_seq) ->
            new_elements ++ Enum.drop(res_seq, Kernel.length(new_elements))

          true ->
            res_seq
        end

      _ ->
        raise ArgumentError, "map-into requires result-sequence and function"
    end
  end

  def map_into(res_seq, fn_arg), do: map_into([res_seq, fn_arg])
  def map_into(res_seq, fn_arg, s1), do: map_into([res_seq, fn_arg, s1])

  defp check_start_end!(start_idx, end_idx, total_len) do
    if not is_integer(start_idx) or start_idx < 0 or start_idx > total_len do
      raise ArgumentError,
            "Invalid start index: #{inspect(start_idx)} for sequence of length #{total_len}"
    end

    if end_idx != nil and
         (not is_integer(end_idx) or end_idx < 0 or end_idx > total_len or end_idx < start_idx) do
      raise ArgumentError,
            "Invalid end index: #{inspect(end_idx)} for sequence of length #{total_len} with start #{start_idx}"
    end
  end

  def search(args) when is_list(args) do
    case args do
      [seq1, seq2 | rest_opts] ->
        opts =
          parse_lisp_keywords(rest_opts, [
            :from_end,
            :test,
            :test_not,
            :key,
            :start1,
            :start2,
            :end1,
            :end2
          ])

        key_fn = Keyword.get(opts, :key, nil)
        from_end = truthy?(Keyword.get(opts, :from_end, nil))

        test_fn =
          cond do
            Keyword.has_key?(opts, :test_not) -> {:test_not, Keyword.get(opts, :test_not)}
            Keyword.has_key?(opts, :test) -> Keyword.get(opts, :test)
            true -> :eql
          end

        l1 = seq_to_list(seq1)
        l2 = seq_to_list(seq2)
        len1 = Kernel.length(l1)
        len2 = Kernel.length(l2)

        start1 = Keyword.get(opts, :start1, 0) || 0
        end1_opt = Keyword.get(opts, :end1, nil)
        end1 = if is_integer(end1_opt), do: end1_opt, else: len1
        check_start_end!(start1, end1_opt, len1)

        start2 = Keyword.get(opts, :start2, 0) || 0
        end2_opt = Keyword.get(opts, :end2, nil)
        end2 = if is_integer(end2_opt), do: end2_opt, else: len2
        check_start_end!(start2, end2_opt, len2)

        sub1 = Enum.slice(l1, start1, max(0, end1 - start1))
        sub2 = Enum.slice(l2, start2, max(0, end2 - start2))
        sub1_len = Kernel.length(sub1)
        sub2_len = Kernel.length(sub2)

        if sub1_len == 0 do
          if from_end, do: end2, else: start2
        else
          max_start = sub2_len - sub1_len

          if max_start < 0 do
            nil
          else
            indices =
              if from_end, do: Enum.to_list(max_start..0), else: Enum.to_list(0..max_start)

            match_idx =
              Enum.find(indices, fn i ->
                target_window = Enum.slice(sub2, i, sub1_len)

                Enum.zip(sub1, target_window)
                |> Enum.all?(fn {e1, e2} ->
                  k1 = apply_key(key_fn, e1)
                  k2 = apply_key(key_fn, e2)
                  test_match?(test_fn, k1, k2)
                end)
              end)

            if match_idx != nil do
              start2 + match_idx
            else
              nil
            end
          end
        end

      _ ->
        nil
    end
  end

  def search(seq1, seq2), do: search([seq1, seq2])

  def mismatch(args) when is_list(args) do
    case args do
      [seq1, seq2 | rest_opts] ->
        opts =
          parse_lisp_keywords(rest_opts, [
            :from_end,
            :test,
            :test_not,
            :key,
            :start1,
            :start2,
            :end1,
            :end2
          ])

        key_fn = Keyword.get(opts, :key, nil)
        from_end = truthy?(Keyword.get(opts, :from_end, nil))

        test_fn =
          cond do
            Keyword.has_key?(opts, :test_not) -> {:test_not, Keyword.get(opts, :test_not)}
            Keyword.has_key?(opts, :test) -> Keyword.get(opts, :test)
            true -> :eql
          end

        l1 = seq_to_list(seq1)
        l2 = seq_to_list(seq2)
        len1 = Kernel.length(l1)
        len2 = Kernel.length(l2)

        start1 = Keyword.get(opts, :start1, 0) || 0
        end1_opt = Keyword.get(opts, :end1, nil)
        end1 = if is_integer(end1_opt), do: end1_opt, else: len1
        check_start_end!(start1, end1_opt, len1)

        start2 = Keyword.get(opts, :start2, 0) || 0
        end2_opt = Keyword.get(opts, :end2, nil)
        end2 = if is_integer(end2_opt), do: end2_opt, else: len2
        check_start_end!(start2, end2_opt, len2)

        sub1 = Enum.slice(l1, start1, max(0, end1 - start1))
        sub2 = Enum.slice(l2, start2, max(0, end2 - start2))
        sub1_len = Kernel.length(sub1)
        sub2_len = Kernel.length(sub2)

        if from_end do
          rev1 = Enum.reverse(sub1)
          rev2 = Enum.reverse(sub2)

          match_count =
            Enum.zip(rev1, rev2)
            |> Enum.take_while(fn {e1, e2} ->
              k1 = apply_key(key_fn, e1)
              k2 = apply_key(key_fn, e2)
              test_match?(test_fn, k1, k2)
            end)
            |> Kernel.length()

          if match_count == sub1_len and match_count == sub2_len do
            nil
          else
            end1 - match_count
          end
        else
          min_len = min(sub1_len, sub2_len)

          mismatch_offset =
            if min_len == 0 do
              nil
            else
              Enum.find(0..(min_len - 1), fn i ->
                e1 = Enum.at(sub1, i)
                e2 = Enum.at(sub2, i)
                k1 = apply_key(key_fn, e1)
                k2 = apply_key(key_fn, e2)
                not test_match?(test_fn, k1, k2)
              end)
            end

          cond do
            mismatch_offset != nil ->
              start1 + mismatch_offset

            sub1_len != sub2_len ->
              start1 + min_len

            true ->
              nil
          end
        end

      _ ->
        nil
    end
  end

  def mismatch(seq1, seq2), do: mismatch([seq1, seq2])

  def reduce(args) when is_list(args) do
    case args do
      [fn_val, seq | rest_opts] ->
        opts = parse_lisp_keywords(rest_opts, [:key, :from_end, :start, :end, :initial_value])
        key_fn = Keyword.get(opts, :key, nil)
        from_end = truthy?(Keyword.get(opts, :from_end, nil))
        has_init = Keyword.has_key?(opts, :initial_value)
        init_val = Keyword.get(opts, :initial_value, nil)

        list = seq_to_list(seq)
        len = Kernel.length(list)
        start_idx = Keyword.get(opts, :start, 0) || 0
        end_opt = Keyword.get(opts, :end, nil)
        end_idx = if is_integer(end_opt), do: end_opt, else: len
        check_start_end!(start_idx, end_opt, len)

        sub = Enum.slice(list, start_idx, max(0, end_idx - start_idx))

        case {sub, has_init} do
          {[], true} ->
            init_val

          {[], false} ->
            invoke_fn(fn_val, [])

          {[single], false} ->
            apply_key(key_fn, single)

          {items, true} ->
            if from_end do
              Enum.reduce(Enum.reverse(items), init_val, fn elem, acc ->
                k = apply_key(key_fn, elem)
                invoke_fn(fn_val, [k, acc])
              end)
            else
              Enum.reduce(items, init_val, fn elem, acc ->
                k = apply_key(key_fn, elem)
                invoke_fn(fn_val, [acc, k])
              end)
            end

          {items, false} ->
            if from_end do
              [last_elem | rev_rest] = Enum.reverse(items)
              last_k = apply_key(key_fn, last_elem)

              Enum.reduce(rev_rest, last_k, fn elem, acc ->
                k = apply_key(key_fn, elem)
                invoke_fn(fn_val, [k, acc])
              end)
            else
              [first | rest] = items
              first_k = apply_key(key_fn, first)

              Enum.reduce(rest, first_k, fn elem, acc ->
                k = apply_key(key_fn, elem)
                invoke_fn(fn_val, [acc, k])
              end)
            end
        end

      _ ->
        nil
    end
  end

  def reduce(fn_val, seq), do: reduce([fn_val, seq])
  def reduce(fn_val, seq, initial_val), do: reduce([fn_val, seq, :initial_value, initial_val])

  def subseq(args) when is_list(args) do
    case args do
      [seq, start_idx | rest] ->
        list = seq_to_list(seq)
        len = Kernel.length(list)

        end_opt =
          case rest do
            [e | _] -> e
            _ -> nil
          end

        end_idx = if is_integer(end_opt), do: end_opt, else: len
        check_start_end!(start_idx, end_opt, len)

        sub_items = Enum.slice(list, start_idx, max(0, end_idx - start_idx))

        cond do
          is_binary(seq) ->
            List.to_string(sub_items)

          is_list(seq) ->
            sub_items

          match?({:array, [_], _}, seq) ->
            {:array, [_], tid} = seq

            elem_type =
              case :ets.lookup(tid, :__meta__) do
                [{:__meta__, meta}] -> Map.get(meta, :element_type, :t)
                _ -> :t
              end

            make_array([
              Kernel.length(sub_items),
              :initial_contents,
              sub_items,
              :element_type,
              elem_type
            ])

          true ->
            sub_items
        end

      _ ->
        raise ArgumentError, "subseq requires sequence and start index"
    end
  end

  def subseq(seq, start_idx), do: subseq([seq, start_idx])
  def subseq(seq, start_idx, end_idx), do: subseq([seq, start_idx, end_idx])

  defp do_remove_elements(seq, match_fn, opts) do
    list = seq_to_list(seq)
    len = Kernel.length(list)
    start_idx = Keyword.get(opts, :start, 0) || 0
    end_opt = Keyword.get(opts, :end, nil)
    end_idx = if is_integer(end_opt), do: end_opt, else: len
    check_start_end!(start_idx, end_opt, len)
    from_end = truthy?(Keyword.get(opts, :from_end, nil))
    count_limit =
      case Keyword.get(opts, :count, nil) do
        nil -> nil
        n when is_integer(n) and n < 0 -> 0
        n when is_integer(n) -> n
        other -> raise ArgumentError, "count must be an integer: #{inspect(other)}"
      end

    indexed = Enum.with_index(list)
    {prefix, middle_and_suffix} = Enum.split(indexed, start_idx)
    {middle, suffix} = Enum.split(middle_and_suffix, max(0, end_idx - start_idx))

    target_items = if from_end, do: Enum.reverse(middle), else: middle

    {kept_items_rev, _removed_count} =
      Enum.reduce(target_items, {[], 0}, fn {elem, orig_idx}, {acc, cnt} ->
        if (count_limit == nil or cnt < count_limit) and match_fn.(elem) do
          {acc, cnt + 1}
        else
          {[{elem, orig_idx} | acc], cnt}
        end
      end)

    kept_middle = if from_end, do: kept_items_rev, else: Enum.reverse(kept_items_rev)
    final_indexed = prefix ++ kept_middle ++ suffix
    res_list = Enum.map(final_indexed, &elem(&1, 0))

    cond do
      is_binary(seq) ->
        List.to_string(res_list)

      is_list(seq) ->
        res_list

      match?({:array, [_], _}, seq) ->
        {:array, [_], tid} = seq

        elem_type =
          case :ets.lookup(tid, :__meta__) do
            [{:__meta__, meta}] -> Map.get(meta, :element_type, :t)
            _ -> :t
          end

        make_array([
          Kernel.length(res_list),
          :initial_contents,
          res_list,
          :element_type,
          elem_type
        ])

      true ->
        res_list
    end
  end

  def remove(args) when is_list(args) do
    case args do
      [item, seq | rest_opts] ->
        opts =
          parse_lisp_keywords(rest_opts, [
            :test,
            :test_not,
            :key,
            :start,
            :end,
            :from_end,
            :count
          ])

        key_fn = Keyword.get(opts, :key, nil)

        test_fn =
          cond do
            Keyword.has_key?(opts, :test_not) -> {:test_not, Keyword.get(opts, :test_not)}
            Keyword.has_key?(opts, :test) -> Keyword.get(opts, :test)
            true -> :eql
          end

        match_fn = fn elem ->
          k = apply_key(key_fn, elem)
          test_match?(test_fn, item, k)
        end

        do_remove_elements(seq, match_fn, opts)

      _ ->
        []
    end
  end

  def remove(item, seq), do: remove([item, seq])
  def delete(args) when is_list(args), do: remove(args)
  def delete(item, seq), do: remove([item, seq])

  def remove_if(args) when is_list(args) do
    case args do
      [predicate, seq | rest_opts] ->
        opts = parse_lisp_keywords(rest_opts, [:key, :start, :end, :from_end, :count])
        key_fn = Keyword.get(opts, :key, nil)

        match_fn = fn elem ->
          k = apply_key(key_fn, elem)
          truthy?(invoke_fn(predicate, [k]))
        end

        do_remove_elements(seq, match_fn, opts)

      _ ->
        []
    end
  end

  def remove_if(predicate, seq), do: remove_if([predicate, seq])
  def delete_if(args) when is_list(args), do: remove_if(args)
  def delete_if(predicate, seq), do: remove_if([predicate, seq])

  def remove_if_not(args) when is_list(args) do
    case args do
      [predicate, seq | rest_opts] ->
        opts = parse_lisp_keywords(rest_opts, [:key, :start, :end, :from_end, :count])
        key_fn = Keyword.get(opts, :key, nil)

        match_fn = fn elem ->
          k = apply_key(key_fn, elem)
          not truthy?(invoke_fn(predicate, [k]))
        end

        do_remove_elements(seq, match_fn, opts)

      _ ->
        []
    end
  end

  def remove_if_not(predicate, seq), do: remove_if_not([predicate, seq])
  def delete_if_not(args) when is_list(args), do: remove_if_not(args)
  def delete_if_not(predicate, seq), do: remove_if_not([predicate, seq])

  defp do_substitute_elements(newitem, seq, match_fn, opts) do
    list = seq_to_list(seq)
    len = Kernel.length(list)
    start_idx = Keyword.get(opts, :start, 0) || 0
    end_opt = Keyword.get(opts, :end, nil)
    end_idx = if is_integer(end_opt), do: end_opt, else: len
    check_start_end!(start_idx, end_opt, len)
    from_end = truthy?(Keyword.get(opts, :from_end, nil))
    count_limit =
      case Keyword.get(opts, :count, nil) do
        nil -> nil
        n when is_integer(n) and n < 0 -> 0
        n when is_integer(n) -> n
        other -> raise ArgumentError, "count must be an integer: #{inspect(other)}"
      end

    indexed = Enum.with_index(list)
    {prefix, middle_and_suffix} = Enum.split(indexed, start_idx)
    {middle, suffix} = Enum.split(middle_and_suffix, max(0, end_idx - start_idx))

    target_items = if from_end, do: Enum.reverse(middle), else: middle

    {substituted_rev, _sub_count} =
      Enum.reduce(target_items, {[], 0}, fn {elem, orig_idx}, {acc, cnt} ->
        if (count_limit == nil or cnt < count_limit) and match_fn.(elem) do
          {[{newitem, orig_idx} | acc], cnt + 1}
        else
          {[{elem, orig_idx} | acc], cnt}
        end
      end)

    sub_middle = if from_end, do: substituted_rev, else: Enum.reverse(substituted_rev)
    final_indexed = prefix ++ sub_middle ++ suffix
    res_list = Enum.map(final_indexed, &elem(&1, 0))

    cond do
      is_binary(seq) ->
        List.to_string(res_list)

      is_list(seq) ->
        res_list

      match?({:array, [_], _}, seq) ->
        {:array, [_], tid} = seq

        elem_type =
          case :ets.lookup(tid, :__meta__) do
            [{:__meta__, meta}] -> Map.get(meta, :element_type, :t)
            _ -> :t
          end

        make_array([
          Kernel.length(res_list),
          :initial_contents,
          res_list,
          :element_type,
          elem_type
        ])

      true ->
        res_list
    end
  end

  def substitute(args) when is_list(args) do
    case args do
      [newitem, olditem, seq | rest_opts] ->
        opts =
          parse_lisp_keywords(rest_opts, [
            :test,
            :test_not,
            :key,
            :start,
            :end,
            :from_end,
            :count
          ])

        key_fn = Keyword.get(opts, :key, nil)

        test_fn =
          cond do
            Keyword.has_key?(opts, :test_not) -> {:test_not, Keyword.get(opts, :test_not)}
            Keyword.has_key?(opts, :test) -> Keyword.get(opts, :test)
            true -> :eql
          end

        match_fn = fn elem ->
          k = apply_key(key_fn, elem)
          test_match?(test_fn, olditem, k)
        end

        do_substitute_elements(newitem, seq, match_fn, opts)

      _ ->
        []
    end
  end

  def substitute(newitem, olditem, seq), do: substitute([newitem, olditem, seq])
  def nsubstitute(args) when is_list(args), do: substitute(args)
  def nsubstitute(newitem, olditem, seq), do: substitute([newitem, olditem, seq])

  def substitute_if(args) when is_list(args) do
    case args do
      [newitem, predicate, seq | rest_opts] ->
        opts = parse_lisp_keywords(rest_opts, [:key, :start, :end, :from_end, :count])
        key_fn = Keyword.get(opts, :key, nil)

        match_fn = fn elem ->
          k = apply_key(key_fn, elem)
          truthy?(invoke_fn(predicate, [k]))
        end

        do_substitute_elements(newitem, seq, match_fn, opts)

      _ ->
        []
    end
  end

  def substitute_if(newitem, predicate, seq), do: substitute_if([newitem, predicate, seq])
  def nsubstitute_if(args) when is_list(args), do: substitute_if(args)
  def nsubstitute_if(newitem, predicate, seq), do: substitute_if([newitem, predicate, seq])

  def substitute_if_not(args) when is_list(args) do
    case args do
      [newitem, predicate, seq | rest_opts] ->
        opts = parse_lisp_keywords(rest_opts, [:key, :start, :end, :from_end, :count])
        key_fn = Keyword.get(opts, :key, nil)

        match_fn = fn elem ->
          k = apply_key(key_fn, elem)
          not truthy?(invoke_fn(predicate, [k]))
        end

        do_substitute_elements(newitem, seq, match_fn, opts)

      _ ->
        []
    end
  end

  def substitute_if_not(newitem, predicate, seq), do: substitute_if_not([newitem, predicate, seq])
  def nsubstitute_if_not(args) when is_list(args), do: substitute_if_not(args)

  def nsubstitute_if_not(newitem, predicate, seq),
    do: substitute_if_not([newitem, predicate, seq])

  def remove_duplicates(args) when is_list(args) do
    case args do
      [seq | rest] ->
        opts = parse_lisp_keywords(rest, [:test, :test_not, :key, :from_end, :start, :end])
        key_fn = Keyword.get(opts, :key, nil)
        from_end = truthy?(Keyword.get(opts, :from_end, nil))

        test_fn =
          cond do
            Keyword.has_key?(opts, :test_not) -> {:test_not, Keyword.get(opts, :test_not)}
            Keyword.has_key?(opts, :test) -> Keyword.get(opts, :test)
            true -> :eql
          end

        list = seq_to_list(seq)
        len = Kernel.length(list)
        start_idx = Keyword.get(opts, :start, 0) || 0
        end_opt = Keyword.get(opts, :end, nil)
        end_idx = if is_integer(end_opt), do: end_opt, else: len
        check_start_end!(start_idx, end_opt, len)

        indexed = Enum.with_index(list)
        {prefix, middle_and_suffix} = Enum.split(indexed, start_idx)
        {middle, suffix} = Enum.split(middle_and_suffix, max(0, end_idx - start_idx))

        do_filter_dups = fn items ->
          Enum.reduce(items, [], fn {elem, orig_idx}, acc ->
            k_val = apply_key(key_fn, elem)

            exists =
              Enum.any?(acc, fn {x, _} ->
                k = apply_key(key_fn, x)
                test_match?(test_fn, k_val, k)
              end)

            if exists, do: acc, else: [{elem, orig_idx} | acc]
          end)
          |> Enum.reverse()
        end

        kept_middle =
          if from_end do
            do_filter_dups.(middle)
          else
            Enum.reverse(middle) |> do_filter_dups.() |> Enum.reverse()
          end

        final_indexed = prefix ++ kept_middle ++ suffix
        res_list = Enum.map(final_indexed, &elem(&1, 0))

        cond do
          is_binary(seq) ->
            List.to_string(res_list)

          is_list(seq) ->
            res_list

          match?({:array, [_], _}, seq) ->
            {:array, [_], tid} = seq

            elem_type =
              case :ets.lookup(tid, :__meta__) do
                [{:__meta__, meta}] -> Map.get(meta, :element_type, :t)
                _ -> :t
              end

            make_array([
              Kernel.length(res_list),
              :initial_contents,
              res_list,
              :element_type,
              elem_type
            ])

          true ->
            res_list
        end

      _ ->
        []
    end
  end

  def remove_duplicates(seq), do: remove_duplicates([seq])
  def delete_duplicates(args), do: remove_duplicates(args)

  def find(args) when is_list(args) do
    case args do
      [item, seq | rest_opts] ->
        opts = parse_lisp_keywords(rest_opts, [:test, :test_not, :key, :start, :end, :from_end])
        key_fn = Keyword.get(opts, :key, nil)
        start_idx = Keyword.get(opts, :start, 0) || 0
        from_end = truthy?(Keyword.get(opts, :from_end, nil))

        test_fn =
          cond do
            Keyword.has_key?(opts, :test_not) -> {:test_not, Keyword.get(opts, :test_not)}
            Keyword.has_key?(opts, :test) -> Keyword.get(opts, :test)
            true -> :eql
          end

        list = seq_to_list(seq)
        total_len = Kernel.length(list)
        end_opt = Keyword.get(opts, :end, nil)
        actual_end = if is_integer(end_opt), do: end_opt, else: total_len
        check_start_end!(start_idx, end_opt, total_len)

        sub = Enum.slice(list, start_idx, max(actual_end - start_idx, 0))
        target_list = if from_end, do: Enum.reverse(sub), else: sub

        Enum.find(target_list, nil, fn elem ->
          k_val = apply_key(key_fn, elem)
          test_match?(test_fn, item, k_val)
        end)

      _ ->
        nil
    end
  end

  def find(item, seq), do: find([item, seq])

  def find_if(args) when is_list(args) do
    case args do
      [predicate, seq | rest_opts] ->
        opts = parse_lisp_keywords(rest_opts, [:key, :start, :end, :from_end])
        key_fn = Keyword.get(opts, :key, nil)
        start_idx = Keyword.get(opts, :start, 0) || 0
        from_end = truthy?(Keyword.get(opts, :from_end, nil))

        list = seq_to_list(seq)
        total_len = Kernel.length(list)
        end_opt = Keyword.get(opts, :end, nil)
        actual_end = if is_integer(end_opt), do: end_opt, else: total_len
        check_start_end!(start_idx, end_opt, total_len)

        sub = Enum.slice(list, start_idx, max(actual_end - start_idx, 0))
        target_list = if from_end, do: Enum.reverse(sub), else: sub

        Enum.find(target_list, nil, fn elem ->
          k_val = apply_key(key_fn, elem)
          truthy?(invoke_fn(predicate, [k_val]))
        end)

      _ ->
        nil
    end
  end

  def find_if(predicate, seq), do: find_if([predicate, seq])

  def find_if_not(args) when is_list(args) do
    case args do
      [predicate, seq | rest_opts] ->
        opts = parse_lisp_keywords(rest_opts, [:key, :start, :end, :from_end])
        key_fn = Keyword.get(opts, :key, nil)
        start_idx = Keyword.get(opts, :start, 0) || 0
        from_end = truthy?(Keyword.get(opts, :from_end, nil))

        list = seq_to_list(seq)
        total_len = Kernel.length(list)
        end_opt = Keyword.get(opts, :end, nil)
        actual_end = if is_integer(end_opt), do: end_opt, else: total_len
        check_start_end!(start_idx, end_opt, total_len)

        sub = Enum.slice(list, start_idx, max(actual_end - start_idx, 0))
        target_list = if from_end, do: Enum.reverse(sub), else: sub

        Enum.find(target_list, nil, fn elem ->
          k_val = apply_key(key_fn, elem)
          not truthy?(invoke_fn(predicate, [k_val]))
        end)

      _ ->
        nil
    end
  end

  def find_if_not(predicate, seq), do: find_if_not([predicate, seq])

  def position(args) when is_list(args) do
    case args do
      [item, seq | rest_opts] ->
        opts =
          parse_lisp_keywords(rest_opts, [:test, :test_not, :key, :start, :end, :from_end])

        do_position(item, seq, opts)

      _ ->
        nil
    end
  end

  def position(item, seq), do: do_position(item, seq, [])

  defp do_position(item, seq, opts) do
    list = seq_to_list(seq)
    start_idx = Keyword.get(opts, :start, 0) || 0
    total_len = Kernel.length(list)
    end_opt = Keyword.get(opts, :end, nil)
    end_idx = if is_integer(end_opt), do: end_opt, else: total_len
    check_start_end!(start_idx, end_opt, total_len)
    key_fn = Keyword.get(opts, :key, nil)
    from_end = truthy?(Keyword.get(opts, :from_end, nil))

    test_fn =
      cond do
        Keyword.has_key?(opts, :test_not) -> {:test_not, Keyword.get(opts, :test_not)}
        Keyword.has_key?(opts, :test) -> Keyword.get(opts, :test)
        true -> :eql
      end

    actual_end = min(end_idx, total_len)
    sub = Enum.slice(list, start_idx, max(actual_end - start_idx, 0))

    match_fn = fn elem ->
      k_val = apply_key(key_fn, elem)
      test_match?(test_fn, item, k_val)
    end

    if from_end do
      case Enum.reverse(sub) |> Enum.find_index(match_fn) do
        nil -> nil
        rev_idx -> actual_end - 1 - rev_idx
      end
    else
      case Enum.find_index(sub, match_fn) do
        nil -> nil
        idx -> start_idx + idx
      end
    end
  end

  def position_if(args) when is_list(args) do
    case args do
      [predicate, seq | rest_opts] ->
        opts = parse_lisp_keywords(rest_opts, [:key, :start, :end, :from_end])
        key_fn = Keyword.get(opts, :key, nil)
        start_idx = Keyword.get(opts, :start, 0) || 0
        end_opt = Keyword.get(opts, :end, nil)
        from_end = truthy?(Keyword.get(opts, :from_end, nil))

        list = seq_to_list(seq)
        len = Kernel.length(list)
        eff_end = if is_integer(end_opt), do: end_opt, else: len
        check_start_end!(start_idx, end_opt, len)

        sub_list =
          if start_idx >= len or eff_end <= start_idx do
            []
          else
            Enum.slice(list, start_idx, max(0, eff_end - start_idx))
          end

        match_fn = fn x ->
          elem_val = if key_fn, do: invoke_fn(key_fn, [x]), else: x
          truthy?(invoke_fn(predicate, [elem_val]))
        end

        if from_end do
          sub_len = Kernel.length(sub_list)

          case Enum.reverse(sub_list) |> Enum.find_index(match_fn) do
            nil -> nil
            rev_idx -> start_idx + (sub_len - 1 - rev_idx)
          end
        else
          case Enum.find_index(sub_list, match_fn) do
            nil -> nil
            idx -> start_idx + idx
          end
        end

      _ ->
        nil
    end
  end

  def position_if(predicate, seq), do: position_if([predicate, seq])

  def position_if_not(args) when is_list(args) do
    case args do
      [predicate, seq | rest_opts] ->
        opts = parse_lisp_keywords(rest_opts, [:key, :start, :end, :from_end])
        key_fn = Keyword.get(opts, :key, nil)
        start_idx = Keyword.get(opts, :start, 0) || 0
        end_opt = Keyword.get(opts, :end, nil)
        from_end = truthy?(Keyword.get(opts, :from_end, nil))

        list = seq_to_list(seq)
        len = Kernel.length(list)
        eff_end = if is_integer(end_opt), do: end_opt, else: len
        check_start_end!(start_idx, end_opt, len)

        sub_list =
          if start_idx >= len or eff_end <= start_idx do
            []
          else
            Enum.slice(list, start_idx, max(0, eff_end - start_idx))
          end

        match_fn = fn x ->
          elem_val = if key_fn, do: invoke_fn(key_fn, [x]), else: x
          not truthy?(invoke_fn(predicate, [elem_val]))
        end

        if from_end do
          sub_len = Kernel.length(sub_list)

          case Enum.reverse(sub_list) |> Enum.find_index(match_fn) do
            nil -> nil
            rev_idx -> start_idx + (sub_len - 1 - rev_idx)
          end
        else
          case Enum.find_index(sub_list, match_fn) do
            nil -> nil
            idx -> start_idx + idx
          end
        end

      _ ->
        nil
    end
  end

  def position_if_not(predicate, seq), do: position_if_not([predicate, seq])

  def count(args) when is_list(args) do
    case args do
      [item, seq | rest_opts] ->
        opts =
          parse_lisp_keywords(rest_opts, [:test, :test_not, :key, :start, :end, :from_end])

        key_fn = Keyword.get(opts, :key, nil)
        start_idx = Keyword.get(opts, :start, 0) || 0

        test_fn =
          cond do
            Keyword.has_key?(opts, :test_not) -> {:test_not, Keyword.get(opts, :test_not)}
            Keyword.has_key?(opts, :test) -> Keyword.get(opts, :test)
            true -> :eql
          end

        list = seq_to_list(seq)
        len = Kernel.length(list)
        end_opt = Keyword.get(opts, :end, nil)
        end_idx = if is_integer(end_opt), do: end_opt, else: len
        check_start_end!(start_idx, end_opt, len)

        sub =
          if start_idx >= len or end_idx <= start_idx do
            []
          else
            Enum.slice(list, start_idx, max(0, end_idx - start_idx))
          end

        Enum.count(sub, fn elem ->
          k_val = apply_key(key_fn, elem)
          test_match?(test_fn, item, k_val)
        end)

      _ ->
        0
    end
  end

  def count(item, seq), do: count([item, seq])

  def count_if(args) when is_list(args) do
    case args do
      [predicate, seq | rest_opts] ->
        opts = parse_lisp_keywords(rest_opts, [:key, :start, :end, :from_end])
        key_fn = Keyword.get(opts, :key, nil)
        start_idx = Keyword.get(opts, :start, 0) || 0
        end_opt = Keyword.get(opts, :end, nil)

        list = seq_to_list(seq)
        len = Kernel.length(list)
        eff_end = if is_integer(end_opt), do: end_opt, else: len
        check_start_end!(start_idx, end_opt, len)

        sub_list =
          if start_idx >= len or eff_end <= start_idx do
            []
          else
            Enum.slice(list, start_idx, max(0, eff_end - start_idx))
          end

        Enum.count(sub_list, fn x ->
          elem_val = if key_fn, do: invoke_fn(key_fn, [x]), else: x
          truthy?(invoke_fn(predicate, [elem_val]))
        end)

      _ ->
        0
    end
  end

  def count_if(predicate, seq), do: count_if([predicate, seq])

  def count_if_not(args) when is_list(args) do
    case args do
      [predicate, seq | rest_opts] ->
        opts = parse_lisp_keywords(rest_opts, [:key, :start, :end, :from_end])
        key_fn = Keyword.get(opts, :key, nil)
        start_idx = Keyword.get(opts, :start, 0) || 0
        end_opt = Keyword.get(opts, :end, nil)

        list = seq_to_list(seq)
        len = Kernel.length(list)
        eff_end = if is_integer(end_opt), do: end_opt, else: len
        check_start_end!(start_idx, end_opt, len)

        sub_list =
          if start_idx >= len or eff_end <= start_idx do
            []
          else
            Enum.slice(list, start_idx, max(0, eff_end - start_idx))
          end

        Enum.count(sub_list, fn x ->
          elem_val = if key_fn, do: invoke_fn(key_fn, [x]), else: x
          not truthy?(invoke_fn(predicate, [elem_val]))
        end)

      _ ->
        0
    end
  end

  def count_if_not(predicate, seq), do: count_if_not([predicate, seq])

  def every(args) when is_list(args) do
    case args do
      [predicate | sequences] when sequences != [] ->
        seq_lists = Enum.map(sequences, &seq_to_list/1)

        if Enum.any?(seq_lists, &(&1 == [] or &1 == nil)) do
          :t
        else
          min_len = seq_lists |> Enum.map(&Kernel.length/1) |> Enum.min()

          if min_len == 0 do
            :t
          else
            0..(min_len - 1)
            |> Enum.all?(fn i ->
              curr_args = Enum.map(seq_lists, &Enum.at(&1, i))
              truthy?(invoke_fn(predicate, curr_args))
            end)
            |> lisp_bool()
          end
        end

      _ ->
        raise ArgumentError, "every requires at least 2 arguments"
    end
  end

  def every(predicate, seq), do: every([predicate, seq])
  def every(predicate, s1, s2), do: every([predicate, s1, s2])

  def some(args) when is_list(args) do
    case args do
      [predicate | sequences] when sequences != [] ->
        seq_lists = Enum.map(sequences, &seq_to_list/1)

        if Enum.any?(seq_lists, &(&1 == [] or &1 == nil)) do
          nil
        else
          min_len = seq_lists |> Enum.map(&Kernel.length/1) |> Enum.min()

          if min_len == 0 do
            nil
          else
            Enum.find_value(0..(min_len - 1), nil, fn i ->
              curr_args = Enum.map(seq_lists, &Enum.at(&1, i))
              res = invoke_fn(predicate, curr_args)
              if truthy?(res), do: res, else: nil
            end)
          end
        end

      _ ->
        raise ArgumentError, "some requires at least 2 arguments"
    end
  end

  def some(predicate, seq), do: some([predicate, seq])
  def some(predicate, s1, s2), do: some([predicate, s1, s2])

  def notany(args) when is_list(args) do
    case some(args) do
      nil -> :t
      _ -> nil
    end
  end

  def notany(predicate, seq), do: notany([predicate, seq])
  def notany(predicate, s1, s2), do: notany([predicate, s1, s2])

  def notevery(args) when is_list(args) do
    case every(args) do
      :t -> nil
      _ -> :t
    end
  end

  def notevery(predicate, seq), do: notevery([predicate, seq])
  def notevery(predicate, s1, s2), do: notevery([predicate, s1, s2])

  def fill(args) when is_list(args) do
    case args do
      [seq, item | rest] ->
        opts = parse_lisp_keywords(rest, [:start, :end])
        list = seq_to_list(seq)
        total_len = Kernel.length(list)
        start_idx = Keyword.get(opts, :start, 0) || 0
        end_opt = Keyword.get(opts, :end, nil)
        end_idx = if is_integer(end_opt), do: end_opt, else: total_len
        check_start_end!(start_idx, end_opt, total_len)

        res =
          list
          |> Enum.with_index()
          |> Enum.map(fn {val, i} ->
            if i >= start_idx and i < end_idx, do: item, else: val
          end)

        cond do
          is_binary(seq) ->
            List.to_string(res)

          is_list(seq) ->
            res

          match?({:array, [_], _}, seq) ->
            {:array, [_], tid} = seq
            res |> Enum.with_index() |> Enum.each(fn {v, i} -> :ets.insert(tid, {i, v}) end)
            seq

          true ->
            res
        end

      _ ->
        []
    end
  end

  def fill(seq, item), do: fill([seq, item])

  def replace(args) when is_list(args) do
    case args do
      [seq1, seq2 | rest] ->
        opts = parse_lisp_keywords(rest, [:start1, :end1, :start2, :end2])
        l1 = seq_to_list(seq1)
        total1 = Kernel.length(l1)
        start1 = Keyword.get(opts, :start1, 0) || 0
        end1_opt = Keyword.get(opts, :end1, nil)
        end1 = if is_integer(end1_opt), do: end1_opt, else: total1
        check_start_end!(start1, end1_opt, total1)

        l2 = seq_to_list(seq2)
        total2 = Kernel.length(l2)
        start2 = Keyword.get(opts, :start2, 0) || 0
        end2_opt = Keyword.get(opts, :end2, nil)
        end2 = if is_integer(end2_opt), do: end2_opt, else: total2
        check_start_end!(start2, end2_opt, total2)

        count = min(max(end1 - start1, 0), max(end2 - start2, 0))
        replacement_items = Enum.slice(l2, start2, count)

        res =
          l1
          |> Enum.with_index()
          |> Enum.map(fn {val, i} ->
            if i >= start1 and i < start1 + count do
              Enum.at(replacement_items, i - start1)
            else
              val
            end
          end)

        cond do
          is_binary(seq1) ->
            List.to_string(res)

          is_list(seq1) ->
            res

          match?({:array, [_], _}, seq1) ->
            {:array, [_], tid} = seq1
            res |> Enum.with_index() |> Enum.each(fn {v, i} -> :ets.insert(tid, {i, v}) end)
            seq1

          true ->
            res
        end

      _ ->
        []
    end
  end

  def replace(seq1, seq2), do: replace([seq1, seq2])

  def merge(args) when is_list(args) do
    case args do
      [result_type, seq1, seq2, predicate | rest_opts] ->
        opts = parse_lisp_keywords(rest_opts, [:key])
        key_fn = Keyword.get(opts, :key, nil)
        l1 = seq_to_list(seq1)
        l2 = seq_to_list(seq2)
        merged = do_merge(l1, l2, predicate, key_fn, [])
        coerce_list_to_type(merged, result_type)

      _ ->
        []
    end
  end

  def merge(result_type, seq1, seq2, predicate), do: merge([result_type, seq1, seq2, predicate])

  defp do_merge([], l2, _predicate, _key_fn, acc), do: Enum.reverse(acc) ++ l2
  defp do_merge(l1, [], _predicate, _key_fn, acc), do: Enum.reverse(acc) ++ l1

  defp do_merge([h1 | t1] = l1, [h2 | t2] = l2, predicate, key_fn, acc) do
    k1 = apply_key(key_fn, h1)
    k2 = apply_key(key_fn, h2)

    if truthy?(invoke_fn(predicate, [k2, k1])) do
      do_merge(l1, t2, predicate, key_fn, [h2 | acc])
    else
      do_merge(t1, l2, predicate, key_fn, [h1 | acc])
    end
  end

  def sort(args) when is_list(args) do
    case args do
      [seq, predicate | rest_opts] ->
        opts = parse_lisp_keywords(rest_opts, [:key])
        key_fn = Keyword.get(opts, :key, nil)
        list = seq_to_list(seq)

        sorted =
          list
          |> Enum.with_index()
          |> Enum.sort(fn {a, i}, {b, j} ->
            ka = apply_key(key_fn, a)
            kb = apply_key(key_fn, b)

            cond do
              truthy?(invoke_fn(predicate, [ka, kb])) -> true
              truthy?(invoke_fn(predicate, [kb, ka])) -> false
              true -> i <= j
            end
          end)
          |> Enum.map(fn {val, _idx} -> val end)

        cond do
          match?({:array, [_], _}, seq) ->
            {:array, [_], tid} = seq

            Enum.with_index(sorted)
            |> Enum.each(fn {val, idx} -> :ets.insert(tid, {idx, val}) end)

            seq

          is_binary(seq) ->
            List.to_string(sorted)

          true ->
            sorted
        end

      _ ->
        []
    end
  end

  def sort(seq, predicate), do: sort([seq, predicate])
  def stable_sort(args) when is_list(args), do: sort(args)
  def stable_sort(seq, predicate), do: sort([seq, predicate])

  def copy_seq(seq) do
    cond do
      seq in [nil, []] ->
        []

      is_list(seq) ->
        Enum.to_list(seq)

      is_binary(seq) ->
        seq

      match?({:array, _, _}, seq) ->
        list = seq_to_list(seq)
        {:array, _, tid} = seq

        elem_type =
          case :ets.lookup(tid, :__meta__) do
            [{:__meta__, %{element_type: et}}] -> et
            _ -> :t
          end

        make_array([Kernel.length(list), :initial_contents, list, :element_type, elem_type])

      true ->
        raise ArgumentError, "copy-seq: #{inspect(seq)} is not a sequence"
    end
  end

  def compile(args) when is_list(args) do
    case args do
      [n, definition | _] when n in [nil, []] ->
        ast = ExLisp.Macro.lisp_data_to_ast(definition)
        LispBeam.evaluate_ast(ast)

      [name, definition | _] ->
        ast = ExLisp.Macro.lisp_data_to_ast(definition)
        fun = LispBeam.evaluate_ast(ast)
        sym_name = normalize_sym_prop(name)
        ExLisp.Env.put_fun(sym_name, fun)
        name

      [name] ->
        name

      _ ->
        nil
    end
  end

  def compile(name), do: compile([name])
  def compile(name, definition), do: compile([name, definition])

  defp subst_tree(tree, match_fn, new_val) do
    if match_fn.(tree) do
      new_val
    else
      case tree do
        [car, :., cdr] ->
          new_car = subst_tree(car, match_fn, new_val)
          new_cdr = subst_tree(cdr, match_fn, new_val)
          if new_cdr == nil or new_cdr == [], do: [new_car], else: [new_car, :., new_cdr]

        [car | cdr] when not is_list(cdr) ->
          new_car = subst_tree(car, match_fn, new_val)
          new_cdr = subst_tree(cdr, match_fn, new_val)
          [new_car | new_cdr]

        [car | cdr] ->
          new_car = subst_tree(car, match_fn, new_val)
          new_cdr = subst_tree(cdr, match_fn, new_val)
          [new_car | new_cdr]

        other ->
          other
      end
    end
  end

  def subst(args) when is_list(args) do
    case args do
      [new_val, old_val, tree | rest_opts] ->
        opts = parse_lisp_keywords(rest_opts, [:key, :test, :test_not])
        key_fn = Keyword.get(opts, :key, nil)

        test_fn =
          cond do
            Keyword.has_key?(opts, :test_not) -> {:test_not, Keyword.get(opts, :test_not)}
            Keyword.has_key?(opts, :test) -> Keyword.get(opts, :test)
            true -> :eql
          end

        match_fn = fn node ->
          node_key = if key_fn, do: invoke_fn(key_fn, [node]), else: node
          test_match?(test_fn, old_val, node_key)
        end

        subst_tree(tree, match_fn, new_val)

      _ ->
        raise ArgumentError, "subst requires at least 3 arguments"
    end
  end

  def subst(new_val, old_val, tree), do: subst([new_val, old_val, tree])
  def nsubst(args) when is_list(args), do: subst(args)
  def nsubst(new_val, old_val, tree), do: subst([new_val, old_val, tree])

  def subst_if(args) when is_list(args) do
    case args do
      [new_val, predicate, tree | rest_opts] ->
        opts = parse_lisp_keywords(rest_opts, [:key])
        key_fn = Keyword.get(opts, :key, nil)

        match_fn = fn node ->
          node_key = if key_fn, do: invoke_fn(key_fn, [node]), else: node
          truthy?(invoke_fn(predicate, [node_key]))
        end

        subst_tree(tree, match_fn, new_val)

      _ ->
        raise ArgumentError, "subst-if requires at least 3 arguments"
    end
  end

  def subst_if(new_val, predicate, tree), do: subst_if([new_val, predicate, tree])
  def nsubst_if(args) when is_list(args), do: subst_if(args)
  def nsubst_if(new_val, predicate, tree), do: subst_if([new_val, predicate, tree])

  def subst_if_not(args) when is_list(args) do
    case args do
      [new_val, predicate, tree | rest_opts] ->
        opts = parse_lisp_keywords(rest_opts, [:key])
        key_fn = Keyword.get(opts, :key, nil)

        match_fn = fn node ->
          node_key = if key_fn, do: invoke_fn(key_fn, [node]), else: node
          not truthy?(invoke_fn(predicate, [node_key]))
        end

        subst_tree(tree, match_fn, new_val)

      _ ->
        raise ArgumentError, "subst-if-not requires at least 3 arguments"
    end
  end

  def subst_if_not(new_val, predicate, tree), do: subst_if_not([new_val, predicate, tree])
  def nsubst_if_not(args) when is_list(args), do: subst_if_not(args)
  def nsubst_if_not(new_val, predicate, tree), do: subst_if_not([new_val, predicate, tree])

  defp sublis_tree(tree, alist, test_fn, key_fn) do
    tree_key = if key_fn, do: invoke_fn(key_fn, [tree]), else: tree

    match =
      if is_list(alist) do
        Enum.find(alist, fn
          entry when is_list(entry) and entry != [] ->
            k = alist_key(entry)
            test_match?(test_fn, tree_key, k)

          {k, _v} ->
            test_match?(test_fn, tree_key, k)

          _ ->
            false
        end)
      else
        nil
      end

    if match != nil do
      alist_val(match)
    else
      case tree do
        [car, :., cdr] ->
          new_car = sublis_tree(car, alist, test_fn, key_fn)
          new_cdr = sublis_tree(cdr, alist, test_fn, key_fn)
          if new_cdr == nil or new_cdr == [], do: [new_car], else: [new_car, :., new_cdr]

        [car | cdr] when not is_list(cdr) ->
          new_car = sublis_tree(car, alist, test_fn, key_fn)
          new_cdr = sublis_tree(cdr, alist, test_fn, key_fn)
          [new_car | new_cdr]

        [car | cdr] ->
          new_car = sublis_tree(car, alist, test_fn, key_fn)
          new_cdr = sublis_tree(cdr, alist, test_fn, key_fn)
          [new_car | new_cdr]

        other ->
          other
      end
    end
  end

  def sublis(args) when is_list(args) do
    case args do
      [alist, tree | rest_opts] ->
        opts = parse_lisp_keywords(rest_opts, [:key, :test, :test_not])
        key_fn = Keyword.get(opts, :key, nil)

        test_fn =
          cond do
            Keyword.has_key?(opts, :test_not) -> {:test_not, Keyword.get(opts, :test_not)}
            Keyword.has_key?(opts, :test) -> Keyword.get(opts, :test)
            true -> :eql
          end

        sublis_tree(tree, alist, test_fn, key_fn)

      _ ->
        raise ArgumentError, "sublis requires at least 2 arguments"
    end
  end

  def sublis(alist, tree), do: sublis([alist, tree])
  def nsublis(args) when is_list(args), do: sublis(args)
  def nsublis(alist, tree), do: sublis([alist, tree])

  # --- String & character functions ---

  def string_designator_to_string(val) do
    cond do
      is_binary(val) ->
        val

      is_atom(val) ->
        case val do
          nil -> "NIL"
          :t -> "T"
          _ -> symbol_name(val)
        end

      match?(%ExLisp.Symbol{}, val) ->
        symbol_name(val)

      is_integer(val) and val >= 0 and val <= 0x10FFFF ->
        List.to_string([val])

      match?({:array, [_len], _tid}, val) ->
        to_string_val(val)

      true ->
        raise ArgumentError, "Not a string designator: #{inspect(val)}"
    end
  end

  defp run_string_compare(chars1, chars2, i1, end1, i2, end2, comparison, case_fold) do
    cond do
      i1 == end1 ->
        cond do
          i2 == end2 ->
            if comparison in [:=, :<=, :>=] do
              if comparison == :=, do: :t, else: end1
            else
              nil
            end

          true ->
            if comparison in [:"/=", :<, :<=] do
              end1
            else
              nil
            end
        end

      i2 == end2 ->
        if comparison in [:"/=", :>, :>=] do
          i1
        else
          nil
        end

      true ->
        c1 = Enum.at(chars1, i1)
        c2 = Enum.at(chars2, i2)

        eq? =
          if case_fold do
            char_upcase(c1) == char_upcase(c2)
          else
            c1 == c2
          end

        if eq? do
          run_string_compare(chars1, chars2, i1 + 1, end1, i2 + 1, end2, comparison, case_fold)
        else
          mismatch? =
            case comparison do
              := ->
                false

              :"/=" ->
                true

              :< ->
                if case_fold, do: char_upcase(c1) < char_upcase(c2), else: c1 < c2

              :<= ->
                if case_fold, do: char_upcase(c1) <= char_upcase(c2), else: c1 <= c2

              :> ->
                if case_fold, do: char_upcase(c1) > char_upcase(c2), else: c1 > c2

              :>= ->
                if case_fold, do: char_upcase(c1) >= char_upcase(c2), else: c1 >= c2
            end

          if mismatch? do
            if comparison == :=, do: :t, else: i1
          else
            nil
          end
        end
    end
  end

  defp do_string_compare(args, comparison, case_fold) do
    case args do
      [s1, s2 | rest] ->
        str1 = string_designator_to_string(s1)
        str2 = string_designator_to_string(s2)
        opts = parse_lisp_keywords(rest, [:start1, :end1, :start2, :end2])

        chars1 = String.to_charlist(str1)
        chars2 = String.to_charlist(str2)
        len1 = length(chars1)
        len2 = length(chars2)

        start1 = Keyword.get(opts, :start1, 0) || 0
        end1 = Keyword.get(opts, :end1, len1) || len1
        start2 = Keyword.get(opts, :start2, 0) || 0
        end2 = Keyword.get(opts, :end2, len2) || len2

        run_string_compare(chars1, chars2, start1, end1, start2, end2, comparison, case_fold)

      _ ->
        raise ArgumentError, "String comparison requires at least 2 string arguments"
    end
  end

  def string_eq(args) when is_list(args), do: do_string_compare(args, :=, false)
  def string_eq(s1, s2), do: do_string_compare([s1, s2], :=, false)

  def string_neq(args) when is_list(args), do: do_string_compare(args, :"/=", false)
  def string_neq(s1, s2), do: do_string_compare([s1, s2], :"/=", false)

  def string_lt(args) when is_list(args), do: do_string_compare(args, :<, false)
  def string_lt(s1, s2), do: do_string_compare([s1, s2], :<, false)

  def string_lte(args) when is_list(args), do: do_string_compare(args, :<=, false)
  def string_lte(s1, s2), do: do_string_compare([s1, s2], :<=, false)

  def string_gt(args) when is_list(args), do: do_string_compare(args, :>, false)
  def string_gt(s1, s2), do: do_string_compare([s1, s2], :>, false)

  def string_gte(args) when is_list(args), do: do_string_compare(args, :>=, false)
  def string_gte(s1, s2), do: do_string_compare([s1, s2], :>=, false)

  def string_equal(args) when is_list(args), do: do_string_compare(args, :=, true)
  def string_equal(s1, s2), do: do_string_compare([s1, s2], :=, true)

  def string_not_equal(args) when is_list(args), do: do_string_compare(args, :"/=", true)
  def string_not_equal(s1, s2), do: do_string_compare([s1, s2], :"/=", true)

  def string_lessp(args) when is_list(args), do: do_string_compare(args, :<, true)
  def string_lessp(s1, s2), do: do_string_compare([s1, s2], :<, true)

  def string_greaterp(args) when is_list(args), do: do_string_compare(args, :>, true)
  def string_greaterp(s1, s2), do: do_string_compare([s1, s2], :>, true)

  def string_not_greaterp(args) when is_list(args), do: do_string_compare(args, :<=, true)
  def string_not_greaterp(s1, s2), do: do_string_compare([s1, s2], :<=, true)

  def string_not_lessp(args) when is_list(args), do: do_string_compare(args, :>=, true)
  def string_not_lessp(s1, s2), do: do_string_compare([s1, s2], :>=, true)

  defp alphanumeric_code?(c) do
    (c >= ?a and c <= ?z) or (c >= ?A and c <= ?Z) or (c >= ?0 and c <= ?9)
  end

  def string_upcase(args) when is_list(args) do
    case args do
      [s | rest] ->
        str = string_designator_to_string(s)
        opts = parse_lisp_keywords(rest, [:start, :end])
        chars = String.to_charlist(str)
        len = length(chars)
        start_idx = Keyword.get(opts, :start, 0) || 0
        end_idx = Keyword.get(opts, :end, len) || len

        transformed =
          chars
          |> Enum.with_index()
          |> Enum.map(fn {c, idx} ->
            if idx >= start_idx and idx < end_idx do
              char_upcase(c)
            else
              c
            end
          end)

        List.to_string(transformed)

      _ ->
        raise ArgumentError, "string-upcase requires at least 1 argument"
    end
  end

  def string_upcase(s), do: string_upcase([s])

  def string_downcase(args) when is_list(args) do
    case args do
      [s | rest] ->
        str = string_designator_to_string(s)
        opts = parse_lisp_keywords(rest, [:start, :end])
        chars = String.to_charlist(str)
        len = length(chars)
        start_idx = Keyword.get(opts, :start, 0) || 0
        end_idx = Keyword.get(opts, :end, len) || len

        transformed =
          chars
          |> Enum.with_index()
          |> Enum.map(fn {c, idx} ->
            if idx >= start_idx and idx < end_idx do
              char_downcase(c)
            else
              c
            end
          end)

        List.to_string(transformed)

      _ ->
        raise ArgumentError, "string-downcase requires at least 1 argument"
    end
  end

  def string_downcase(s), do: string_downcase([s])

  def string_capitalize(args) when is_list(args) do
    case args do
      [s | rest] ->
        str = string_designator_to_string(s)
        opts = parse_lisp_keywords(rest, [:start, :end])
        chars = String.to_charlist(str)
        len = length(chars)
        start_idx = Keyword.get(opts, :start, 0) || 0
        end_idx = Keyword.get(opts, :end, len) || len

        {transformed, _in_word} =
          Enum.reduce(Enum.with_index(chars), {[], false}, fn {c, idx}, {acc, in_word} ->
            if idx >= start_idx and idx < end_idx do
              if alphanumeric_code?(c) do
                if in_word do
                  {[char_downcase(c) | acc], true}
                else
                  {[char_upcase(c) | acc], true}
                end
              else
                {[c | acc], false}
              end
            else
              {[c | acc], in_word}
            end
          end)

        transformed |> Enum.reverse() |> List.to_string()

      _ ->
        raise ArgumentError, "string-capitalize requires at least 1 argument"
    end
  end

  def string_capitalize(s), do: string_capitalize([s])

  def nstring_upcase(args) when is_list(args) do
    case args do
      [{:array, _, _tid} = arr | rest] ->
        opts = parse_lisp_keywords(rest, [:start, :end])
        len = length(arr)
        start_idx = Keyword.get(opts, :start, 0) || 0
        end_idx = Keyword.get(opts, :end, len) || len

        for i <- start_idx..(end_idx - 1)//1 do
          c = aref([arr, i])
          if is_integer(c), do: set_aref(arr, i, char_upcase(c))
        end

        arr

      [s | _] when is_binary(s) ->
        string_upcase(args)

      _ ->
        raise ArgumentError, "nstring-upcase requires at least 1 argument"
    end
  end

  def nstring_upcase(s), do: nstring_upcase([s])

  def nstring_downcase(args) when is_list(args) do
    case args do
      [{:array, _, _tid} = arr | rest] ->
        opts = parse_lisp_keywords(rest, [:start, :end])
        len = length(arr)
        start_idx = Keyword.get(opts, :start, 0) || 0
        end_idx = Keyword.get(opts, :end, len) || len

        for i <- start_idx..(end_idx - 1)//1 do
          c = aref([arr, i])
          if is_integer(c), do: set_aref(arr, i, char_downcase(c))
        end

        arr

      [s | _] when is_binary(s) ->
        string_downcase(args)

      _ ->
        raise ArgumentError, "nstring-downcase requires at least 1 argument"
    end
  end

  def nstring_downcase(s), do: nstring_downcase([s])

  def nstring_capitalize(args) when is_list(args) do
    case args do
      [{:array, _, _tid} = arr | rest] ->
        opts = parse_lisp_keywords(rest, [:start, :end])
        len = length(arr)
        start_idx = Keyword.get(opts, :start, 0) || 0
        end_idx = Keyword.get(opts, :end, len) || len

        if start_idx < end_idx do
          Enum.reduce(start_idx..(end_idx - 1)//1, false, fn i, in_w ->
            c = aref([arr, i])

            if is_integer(c) and alphanumeric_code?(c) do
              if in_w do
                set_aref(arr, i, char_downcase(c))
                true
              else
                set_aref(arr, i, char_upcase(c))
                true
              end
            else
              false
            end
          end)
        end

        arr

      [s | _] when is_binary(s) ->
        string_capitalize(args)

      _ ->
        raise ArgumentError, "nstring-capitalize requires at least 1 argument"
    end
  end

  def nstring_capitalize(s), do: nstring_capitalize([s])

  defp char_bag_to_set(bag) do
    codes =
      cond do
        is_binary(bag) ->
          String.to_charlist(bag)

        match?({:array, _, _}, bag) ->
          len = length(bag)
          for i <- 0..(len - 1)//1, do: aref([bag, i]) |> char_code()

        is_list(bag) ->
          Enum.map(bag, &char_code/1)

        is_tuple(bag) ->
          bag |> Tuple.to_list() |> Enum.map(&char_code/1)

        true ->
          []
      end

    MapSet.new(codes)
  end

  def string_trim(args) when is_list(args) do
    case args do
      [bag, s] -> string_trim(bag, s)
      _ -> raise ArgumentError, "string-trim requires exactly 2 arguments"
    end
  end

  def string_trim(bag, s) do
    set = char_bag_to_set(bag)
    chars = String.to_charlist(string_designator_to_string(s))

    trimmed_leading = Enum.drop_while(chars, &MapSet.member?(set, &1))

    trimmed_all =
      trimmed_leading
      |> Enum.reverse()
      |> Enum.drop_while(&MapSet.member?(set, &1))
      |> Enum.reverse()

    List.to_string(trimmed_all)
  end

  def string_left_trim(args) when is_list(args) do
    case args do
      [bag, s] -> string_left_trim(bag, s)
      _ -> raise ArgumentError, "string-left-trim requires exactly 2 arguments"
    end
  end

  def string_left_trim(bag, s) do
    set = char_bag_to_set(bag)
    chars = String.to_charlist(string_designator_to_string(s))
    trimmed = Enum.drop_while(chars, &MapSet.member?(set, &1))
    List.to_string(trimmed)
  end

  def string_right_trim(args) when is_list(args) do
    case args do
      [bag, s] -> string_right_trim(bag, s)
      _ -> raise ArgumentError, "string-right-trim requires exactly 2 arguments"
    end
  end

  def string_right_trim(bag, s) do
    set = char_bag_to_set(bag)
    chars = String.to_charlist(string_designator_to_string(s))

    trimmed =
      chars |> Enum.reverse() |> Enum.drop_while(&MapSet.member?(set, &1)) |> Enum.reverse()

    List.to_string(trimmed)
  end

  def string(x), do: string_designator_to_string(x)

  defp to_string_val(val) when is_binary(val), do: val
  defp to_string_val(%ExLisp.Symbol{} = sym), do: symbol_name(sym)
  defp to_string_val(val) when is_atom(val), do: symbol_name(val)

  defp to_string_val(val) when is_integer(val) and val >= 0 and val <= 0x10FFFF,
    do: List.to_string([val])

  defp to_string_val({:array, [len], tid}) when is_integer(len) do
    meta =
      case :ets.lookup(tid, :__meta__) do
        [{:__meta__, m}] -> m
        _ -> %{}
      end

    actual_len =
      case meta do
        %{fill_pointer: fp} when is_integer(fp) -> fp
        _ -> len
      end

    init_elem = Map.get(meta, :initial_element, ?\s)

    if actual_len <= 0 do
      ""
    else
      try do
        0..(actual_len - 1)//1
        |> Enum.map(fn idx ->
          case :ets.lookup(tid, idx) do
            [{^idx, char_code}]
            when is_integer(char_code) and char_code >= 0 and char_code <= 0x10FFFF ->
              char_code

            [{^idx, <<char_code::utf8>>}] ->
              char_code

            [{^idx, other}] ->
              throw({:not_char, other})

            _ ->
              cond do
                is_integer(init_elem) and init_elem >= 0 and init_elem <= 0x10FFFF ->
                  init_elem

                is_binary(init_elem) and byte_size(init_elem) > 0 ->
                  hd(String.to_charlist(init_elem))

                true ->
                  ?\s
              end
          end
        end)
        |> List.to_string()
      catch
        _, _ -> inspect({:array, [len], tid})
      end
    end
  end

  defp to_string_val(val), do: inspect(val)

  def char(str, idx) when is_integer(idx) and idx >= 0 do
    cond do
      is_binary(str) ->
        case String.at(str, idx) do
          nil -> nil
          ch -> hd(String.to_charlist(ch))
        end

      match?({:array, _, _}, str) ->
        aref([str, idx])

      true ->
        nil
    end
  end

  def char(_, _), do: nil

  def schar(str, idx), do: char(str, idx)

  def set_char(seq, idx, val) do
    cond do
      match?({:array, _, _}, seq) ->
        set_aref(seq, idx, val)

      true ->
        val
    end
  end

  def set_char_update_seq(seq, idx, val) do
    cond do
      match?({:array, _, _}, seq) ->
        set_aref(seq, idx, val)
        seq

      is_binary(seq) and is_integer(idx) and idx >= 0 ->
        char_code =
          cond do
            is_integer(val) -> val
            is_binary(val) -> hd(String.to_charlist(val))
            true -> ?\s
          end

        chars = String.to_charlist(seq)
        List.replace_at(chars, idx, char_code) |> List.to_string()

      true ->
        seq
    end
  end

  def set_elt_update_seq(seq, idx, val) do
    case seq do
      {:array, [len], _} ->
        if not is_integer(idx) or idx < 0 or idx >= len do
          raise ArgumentError, "Index #{inspect(idx)} out of bounds for array of length #{len}"
        end

        set_aref(seq, idx, val)
        seq

      {:array, _dims, _} ->
        set_aref(seq, idx, val)
        seq

      _ when is_list(seq) ->
        len = length(seq)

        if not is_integer(idx) or idx < 0 or idx >= len do
          raise ArgumentError, "Index #{inspect(idx)} out of bounds for list of length #{len}"
        end

        List.replace_at(seq, idx, val)

      _ when is_binary(seq) ->
        len = String.length(seq)

        if not is_integer(idx) or idx < 0 or idx >= len do
          raise ArgumentError, "Index #{inspect(idx)} out of bounds for string of length #{len}"
        end

        set_char_update_seq(seq, idx, val)

      _ ->
        raise ArgumentError, "setf elt requires a sequence, got: #{inspect(seq)}"
    end
  end

  def set_subseq_update_seq(seq, start, val), do: set_subseq_update_seq(seq, start, nil, val)

  def set_subseq_update_seq(seq, start, end_idx, val) do
    start = if is_integer(start), do: max(0, start), else: 0

    case seq do
      {:array, [len], _} ->
        actual_end = if is_integer(end_idx), do: min(len, max(start, end_idx)), else: len
        count = actual_end - start
        val_list =
          cond do
            is_list(val) -> val
            is_binary(val) -> String.to_charlist(val)
            match?({:array, _, _}, val) ->
              for i <- 0..(length(val) - 1), do: aref(val, i)
            true -> []
          end
        val_list = Enum.take(val_list, count)
        Enum.with_index(val_list)
        |> Enum.each(fn {item, i} ->
          set_aref(seq, start + i, item)
        end)
        seq

      _ when is_list(seq) ->
        len = Kernel.length(seq)
        actual_end = if is_integer(end_idx), do: min(len, max(start, end_idx)), else: len
        count = actual_end - start
        val_list =
          cond do
            is_list(val) -> val
            is_binary(val) -> String.to_charlist(val)
            match?({:array, _, _}, val) ->
              for i <- 0..(length(val) - 1), do: aref(val, i)
            true -> []
          end
        val_list = Enum.take(val_list, count)
        prefix = Enum.take(seq, start)
        suffix = Enum.drop(seq, start + length(val_list))
        prefix ++ val_list ++ suffix

      _ when is_binary(seq) ->
        chars = String.to_charlist(seq)
        len = length(chars)
        actual_end = if is_integer(end_idx), do: min(len, max(start, end_idx)), else: len
        count = actual_end - start
        val_chars =
          cond do
            is_binary(val) -> String.to_charlist(val)
            is_list(val) ->
              Enum.map(val, fn
                c when is_integer(c) -> c
                s when is_binary(s) -> hd(String.to_charlist(s))
                _ -> ?\s
              end)
            true -> []
          end
        val_chars = Enum.take(val_chars, count)
        prefix = Enum.take(chars, start)
        suffix = Enum.drop(chars, start + length(val_chars))
        List.to_string(prefix ++ val_chars ++ suffix)

      _ ->
        seq
    end
  end

  def character(ch) do
    cond do
      is_integer(ch) and ch >= 0 and ch <= 0x10FFFF ->
        ch

      is_binary(ch) ->
        case String.to_charlist(ch) do
          [c] -> c
          _ -> raise ArgumentError, "Cannot coerce #{inspect(ch)} to character"
        end

      match?(%ExLisp.Symbol{}, ch) ->
        name = symbol_name(ch)

        case String.to_charlist(name) do
          [c] -> c
          _ -> raise ArgumentError, "Cannot coerce #{inspect(ch)} to character"
        end

      is_atom(ch) ->
        name = symbol_name(ch)

        case String.to_charlist(name) do
          [c] -> c
          _ -> raise ArgumentError, "Cannot coerce #{inspect(ch)} to character"
        end

      true ->
        raise ArgumentError, "Cannot coerce #{inspect(ch)} to character"
    end
  end

  def char_code(ch) do
    cond do
      is_integer(ch) and ch >= 0 and ch <= 0x10FFFF ->
        ch

      is_binary(ch) ->
        case String.to_charlist(ch) do
          [c] -> c
          _ -> raise ArgumentError, "Not a character: #{inspect(ch)}"
        end

      true ->
        raise ArgumentError, "Not a character: #{inspect(ch)}"
    end
  end

  def code_char(code) when is_integer(code) and code >= 0 and code <= 0x10FFFF do
    if code in 0xD800..0xDFFF do
      nil
    else
      code
    end
  end

  def code_char(_), do: nil

  def char_upcase(c) do
    code = char_code(c)
    if code >= ?a and code <= ?z, do: code - 32, else: code
  end

  def char_downcase(c) do
    code = char_code(c)
    if code >= ?A and code <= ?Z, do: code + 32, else: code
  end

  def char_equal([]), do: raise(ArgumentError, "char-equal requires at least 1 argument")
  def char_equal([_]), do: :t

  def char_equal([first | rest]) do
    c1 = char_upcase(first)
    Enum.all?(rest, fn c -> char_upcase(c) == c1 end) |> lisp_bool()
  end

  def char_equal(_c), do: :t
  def char_equal(c1, c2), do: char_equal([c1, c2])

  def char_not_equal([]), do: raise(ArgumentError, "char-not-equal requires at least 1 argument")
  def char_not_equal([_]), do: :t

  def char_not_equal(args) when is_list(args) do
    codes = Enum.map(args, &char_upcase/1)
    (length(codes) == length(Enum.uniq(codes))) |> lisp_bool()
  end

  def char_not_equal(_c), do: :t
  def char_not_equal(c1, c2), do: char_not_equal([c1, c2])

  def char_lessp([]), do: raise(ArgumentError, "char-lessp requires at least 1 argument")
  def char_lessp([_]), do: :t

  def char_lessp(args) when is_list(args) do
    args
    |> Enum.map(&char_upcase/1)
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.all?(fn [a, b] -> a < b end)
    |> lisp_bool()
  end

  def char_lessp(_c), do: :t
  def char_lessp(c1, c2), do: char_lessp([c1, c2])

  def char_greaterp([]), do: raise(ArgumentError, "char-greaterp requires at least 1 argument")
  def char_greaterp([_]), do: :t

  def char_greaterp(args) when is_list(args) do
    args
    |> Enum.map(&char_upcase/1)
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.all?(fn [a, b] -> a > b end)
    |> lisp_bool()
  end

  def char_greaterp(_c), do: :t
  def char_greaterp(c1, c2), do: char_greaterp([c1, c2])

  def char_not_greaterp([]),
    do: raise(ArgumentError, "char-not-greaterp requires at least 1 argument")

  def char_not_greaterp([_]), do: :t

  def char_not_greaterp(args) when is_list(args) do
    args
    |> Enum.map(&char_upcase/1)
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.all?(fn [a, b] -> a <= b end)
    |> lisp_bool()
  end

  def char_not_greaterp(_c), do: :t
  def char_not_greaterp(c1, c2), do: char_not_greaterp([c1, c2])

  def char_not_lessp([]), do: raise(ArgumentError, "char-not-lessp requires at least 1 argument")
  def char_not_lessp([_]), do: :t

  def char_not_lessp(args) when is_list(args) do
    args
    |> Enum.map(&char_upcase/1)
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.all?(fn [a, b] -> a >= b end)
    |> lisp_bool()
  end

  def char_not_lessp(_c), do: :t
  def char_not_lessp(c1, c2), do: char_not_lessp([c1, c2])

  def alpha_char_p(c) do
    code = char_code(c)
    ((code >= ?a and code <= ?z) or (code >= ?A and code <= ?Z)) |> lisp_bool()
  end

  def digit_char_p(c, radix \\ 10) do
    code = char_code(c)
    rad = if is_integer(radix), do: radix, else: 10

    if rad >= 2 and rad <= 36 do
      weight =
        cond do
          code >= ?0 and code <= ?9 -> code - ?0
          code >= ?a and code <= ?z -> code - ?a + 10
          code >= ?A and code <= ?Z -> code - ?A + 10
          true -> nil
        end

      if weight != nil and weight < rad, do: weight, else: nil
    else
      raise ArgumentError, "Invalid radix: #{inspect(radix)}"
    end
  end

  def alphanumericp(c) do
    code = char_code(c)

    ((code >= ?a and code <= ?z) or (code >= ?A and code <= ?Z) or (code >= ?0 and code <= ?9))
    |> lisp_bool()
  end

  def standard_char_p(c) do
    code = char_code(c)
    (code == ?\n or (code >= 32 and code <= 126)) |> lisp_bool()
  end

  def graphic_char_p(c) do
    code = char_code(c)
    (code >= 32 and code <= 126) |> lisp_bool()
  end

  def upper_case_p(c) do
    code = char_code(c)
    (code >= ?A and code <= ?Z) |> lisp_bool()
  end

  def lower_case_p(c) do
    code = char_code(c)
    (code >= ?a and code <= ?z) |> lisp_bool()
  end

  def both_case_p(c) do
    alpha_char_p(c)
  end

  def char_eq([]), do: raise(ArgumentError, "char= requires at least 1 argument")
  def char_eq([_]), do: :t

  def char_eq([first | rest]) do
    c1 = char_code(first)
    Enum.all?(rest, fn c -> char_code(c) == c1 end) |> lisp_bool()
  end

  def char_eq(_c), do: :t
  def char_eq(c1, c2), do: char_eq([c1, c2])

  def char_neq([]), do: raise(ArgumentError, "char/= requires at least 1 argument")
  def char_neq([_]), do: :t

  def char_neq(args) when is_list(args) do
    codes = Enum.map(args, &char_code/1)
    (length(codes) == length(Enum.uniq(codes))) |> lisp_bool()
  end

  def char_neq(_c), do: :t
  def char_neq(c1, c2), do: char_neq([c1, c2])

  def char_lt([]), do: raise(ArgumentError, "char< requires at least 1 argument")
  def char_lt([_]), do: :t

  def char_lt(args) when is_list(args) do
    args
    |> Enum.map(&char_code/1)
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.all?(fn [a, b] -> a < b end)
    |> lisp_bool()
  end

  def char_lt(_c), do: :t
  def char_lt(c1, c2), do: char_lt([c1, c2])

  def char_lte([]), do: raise(ArgumentError, "char<= requires at least 1 argument")
  def char_lte([_]), do: :t

  def char_lte(args) when is_list(args) do
    args
    |> Enum.map(&char_code/1)
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.all?(fn [a, b] -> a <= b end)
    |> lisp_bool()
  end

  def char_lte(_c), do: :t
  def char_lte(c1, c2), do: char_lte([c1, c2])

  def char_gt([]), do: raise(ArgumentError, "char> requires at least 1 argument")
  def char_gt([_]), do: :t

  def char_gt(args) when is_list(args) do
    args
    |> Enum.map(&char_code/1)
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.all?(fn [a, b] -> a > b end)
    |> lisp_bool()
  end

  def char_gt(_c), do: :t
  def char_gt(c1, c2), do: char_gt([c1, c2])

  def char_gte([]), do: raise(ArgumentError, "char>= requires at least 1 argument")
  def char_gte([_]), do: :t

  def char_gte(args) when is_list(args) do
    args
    |> Enum.map(&char_code/1)
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.all?(fn [a, b] -> a >= b end)
    |> lisp_bool()
  end

  def char_gte(_c), do: :t
  def char_gte(c1, c2), do: char_gte([c1, c2])

  # --- Hash tables ---

  def make_hash_table(args \\ []) do
    args_list = if is_list(args), do: args, else: [args]
    opts = parse_lisp_keywords(args_list)
    test = Keyword.get(opts, :test, :eql)
    tid = :ets.new(:lisp_hash_table, [:set, :public])
    {:hash_table, test, tid}
  end

  def gethash(key, hash_table, default \\ nil)

  def gethash(key, {:hash_table, _test, tid}, default) do
    case :ets.lookup(tid, key) do
      [{^key, val}] -> val
      [] -> default
    end
  end

  def gethash(_key, _table, default), do: default

  def gethash_mv(key, hash_table, default \\ nil)

  def gethash_mv(key, {:hash_table, _test, tid}, default) do
    case :ets.lookup(tid, key) do
      [{^key, val}] -> [:_values_, [val, :t]]
      [] -> [:_values_, [default, nil]]
    end
  end

  def gethash_mv(_key, _table, default), do: [:_values_, [default, nil]]

  def set_gethash(key, {:hash_table, _test, tid}, val) do
    :ets.insert(tid, {key, val})
    val
  end

  def remhash(key, {:hash_table, _test, tid}) do
    case :ets.member(tid, key) do
      true ->
        :ets.delete(tid, key)
        :t

      false ->
        nil
    end
  end

  def remhash(_key, _table), do: nil

  def clrhash({:hash_table, _test, tid} = ht) do
    :ets.delete_all_objects(tid)
    ht
  end

  def clrhash(ht), do: ht

  def hash_table_count({:hash_table, _test, tid}) do
    :ets.info(tid, :size) || 0
  end

  def hash_table_count(_), do: 0

  def hash_table_p({:hash_table, _, _}), do: :t
  def hash_table_p(_), do: nil

  def maphash(fun, {:hash_table, _test, tid}) do
    :ets.foldl(
      fn {k, v}, _acc ->
        funcall(fun, [k, v])
        nil
      end,
      nil,
      tid
    )

    nil
  end

  def maphash(_fun, _table), do: nil

  # --- Array / vector ---

  def make_array(args) when is_list(args) do
    case args do
      [dims | rest] ->
        opts = parse_lisp_keywords(rest)

        dimensions =
          cond do
            is_integer(dims) -> [dims]
            is_list(dims) -> dims
            true -> [0]
          end

        total_size = Enum.reduce(dimensions, 1, &Kernel.*/2)
        initial_element = Keyword.get(opts, :initial_element, nil)
        initial_contents = Keyword.get(opts, :initial_contents, nil)
        displaced_to = Keyword.get(opts, :displaced_to, nil)
        displaced_offset = Keyword.get(opts, :displaced_index_offset, 0) || 0
        fill_pointer = Keyword.get(opts, :fill_pointer, nil)
        adjustable = Keyword.get(opts, :adjustable, nil) not in [nil, nil, false]

        tid =
          :ets.new(:lisp_array, [
            :set,
            :public,
            {:read_concurrency, true},
            {:write_concurrency, true}
          ])

        cond do
          displaced_to != nil ->
            src_list = seq_to_list(displaced_to)
            slice = Enum.slice(src_list, displaced_offset, total_size)

            slice
            |> Enum.with_index()
            |> Enum.each(fn {val, idx} -> :ets.insert(tid, {idx, val}) end)

          initial_contents != nil ->
            flat_contents = flatten_initial_contents(initial_contents, dimensions)

            objects =
              Enum.with_index(flat_contents, fn val, idx -> {idx, val} end)

            :ets.insert(tid, objects)

          true ->
            # Default element is stored in metadata; no need to insert total_size items individually!
            :ok
        end

        fill_ptr_val =
          cond do
            fill_pointer == :t -> length(dimensions) == 1 && hd(dimensions)
            is_integer(fill_pointer) -> fill_pointer
            true -> nil
          end

        element_type = Keyword.get(opts, :element_type, :t)

        if initial_element != nil do
          :ets.insert(tid, {:__init__, initial_element})
        else
          :ets.insert(tid, {:__init__, nil})
        end

        if displaced_to != nil do
          :ets.insert(tid, {:__displaced__, displaced_to, displaced_offset})
        end

        :ets.insert(
          tid,
          {:__meta__,
           %{
             dimensions: dimensions,
             fill_pointer: fill_ptr_val,
             adjustable: adjustable,
             initial_element: initial_element,
             element_type: element_type,
             displaced_to: displaced_to,
             displaced_index_offset: displaced_offset
           }}
        )

        {:array, dimensions, tid}

      _ ->
        raise ArgumentError, "make-array requires dimensions"
    end
  end

  def make_array(dims), do: make_array([dims])

  defp flatten_initial_contents(contents, dims) do
    cond do
      is_binary(contents) ->
        String.to_charlist(contents)

      length(dims) <= 1 ->
        if is_list(contents), do: contents, else: seq_to_list(contents)

      true ->
        flatten_multidim_contents(contents, length(dims))
    end
  end

  defp flatten_multidim_contents(contents, depth) when depth > 1 and is_list(contents) do
    Enum.flat_map(contents, &flatten_multidim_contents(&1, depth - 1))
  end

  defp flatten_multidim_contents(contents, _depth) do
    cond do
      is_binary(contents) -> String.to_charlist(contents)
      is_list(contents) -> contents
      true -> [contents]
    end
  end

  def vector(args) when is_list(args) do
    make_array([length(args), :initial_contents, args])
  end

  def aref({:array, [_dim], tid}, idx) when is_integer(idx) do
    case :ets.lookup(tid, idx) do
      [{^idx, val}] ->
        val

      [] ->
        case :ets.lookup(tid, :__init__) do
          [{:__init__, default}] ->
            default

          _ ->
            case :ets.lookup(tid, :__displaced__) do
              [{:__displaced__, target, offset}] ->
                aref(target, offset + idx)

              _ ->
                nil
            end
        end
    end
  end

  def aref(str, idx) when is_binary(str) and is_integer(idx) do
    case String.at(str, idx) do
      nil ->
        nil

      <<char_code::utf8>> ->
        char_code
    end
  end

  def aref([{:array, [dim], tid}, idx]) when is_integer(idx) do
    aref({:array, [dim], tid}, idx)
  end

  def aref([str, idx]) when is_binary(str) and is_integer(idx) do
    aref(str, idx)
  end

  def aref(args) when is_list(args) do
    case args do
      [{:array, dims, tid} | indices] ->
        flat_idx =
          case {dims, indices} do
            {[_single_dim], [single_idx]} when is_integer(single_idx) -> single_idx
            _ -> compute_flat_index(dims, indices)
          end

        case :ets.lookup(tid, flat_idx) do
          [{^flat_idx, val}] ->
            val

          [] ->
            case :ets.lookup(tid, :__init__) do
              [{:__init__, default}] ->
                default

              [] ->
                case :ets.lookup(tid, :__displaced__) do
                  [{:__displaced__, target, offset}] ->
                    aref(target, offset + flat_idx)

                  [] ->
                    case :ets.lookup(tid, :__meta__) do
                      [{:__meta__, %{initial_element: default}}] ->
                        default

                      _ ->
                        nil
                    end
                end
            end
        end

      _ ->
        nil
    end
  end

  def set_aref({:array, [_dim], tid}, index, val) when is_integer(index) do
    :ets.insert(tid, {index, val})
    val
  end

  def set_aref(arr, indices, val) do
    case arr do
      {:array, [_dim], tid} when is_integer(indices) ->
        :ets.insert(tid, {indices, val})
        val

      {:array, dims, tid} ->
        flat_idx =
          case {dims, indices} do
            {[_single_dim], single_idx} when is_integer(single_idx) ->
              single_idx

            {[_single_dim], [single_idx]} ->
              single_idx

            _ ->
              idx_list = if is_list(indices), do: indices, else: [indices]
              compute_flat_index(dims, idx_list)
          end

        case :ets.lookup(tid, :__displaced__) do
          [{:__displaced__, {:array, _, _} = target, offset}] ->
            set_aref(target, offset + flat_idx, val)

          _ ->
            :ets.insert(tid, {flat_idx, val})
            val
        end

      _ ->
        val
    end
  end

  def svref({:array, [_dim], tid}, index) when is_integer(index) do
    case :ets.lookup(tid, index) do
      [{^index, val}] ->
        val

      [] ->
        case :ets.lookup(tid, :__init__) do
          [{:__init__, default}] -> default
          [] ->
            case :ets.lookup(tid, :__meta__) do
              [{:__meta__, %{initial_element: default}}] -> default
              _ -> nil
            end
        end
    end
  end

  def svref(_, _), do: nil

  def elt({:array, _dims, _tid} = arr, index) when is_integer(index) do
    aref([arr, index])
  end

  def elt(list, index) when is_list(list) and is_integer(index) do
    Enum.at(list, index)
  end

  def elt(str, index) when is_binary(str) and is_integer(index) do
    chars = String.to_charlist(str)
    if index >= 0 and index < length(chars), do: Enum.at(chars, index), else: nil
  end

  def elt(_seq, _index), do: nil

  def elt([seq, index]), do: elt(seq, index)
  def elt(_), do: nil

  def set_elt({:array, _dims, _tid} = arr, index, val) when is_integer(index) do
    set_aref(arr, index, val)
  end

  def set_elt(list, index, val) when is_list(list) and is_integer(index) do
    List.replace_at(list, index, val)
  end

  def set_elt(_seq, _index, val), do: val

  def set_svref({:array, [_dim], tid}, index, val) when is_integer(index) do
    :ets.insert(tid, {index, val})
    val
  end

  def arrayp({:array, _, _}), do: :t
  def arrayp(_), do: nil

  def vectorp({:array, [_], _}), do: :t
  def vectorp(_), do: nil

  def simple_vector_p({:array, [_], tid}) do
    case :ets.lookup(tid, :__meta__) do
      [{:__meta__, meta}] ->
        fp = Map.get(meta, :fill_pointer, nil)
        adj = Map.get(meta, :adjustable, false)
        disp = Map.get(meta, :displaced_to, nil)
        norm = normalize_type_spec(Map.get(meta, :element_type, :t))

        (fp == nil and not adj and disp == nil and norm in [:t, :*, :_]) |> lisp_bool()

      _ ->
        nil
    end
  end

  def simple_vector_p(_), do: nil

  def array_dimensions({:array, dims, _}), do: dims
  def array_dimensions(_), do: nil

  def array_dimension({:array, dims, _}, axis) when is_integer(axis) do
    Enum.at(dims, axis)
  end

  def array_dimension(_, _), do: nil

  def array_total_size({:array, dims, _}) do
    Enum.reduce(dims, 1, &Kernel.*/2)
  end

  def array_total_size(_), do: 0

  def vector_push(val, {:array, [max_dim], tid}) do
    case :ets.lookup(tid, :__meta__) do
      [{:__meta__, %{fill_pointer: fp} = meta}] when is_integer(fp) and fp < max_dim ->
        :ets.insert(tid, {fp, val})
        :ets.insert(tid, {:__meta__, %{meta | fill_pointer: fp + 1}})
        fp

      _ ->
        nil
    end
  end

  def vector_push_extend(val, {:array, [max_dim], tid} = arr) do
    case :ets.lookup(tid, :__meta__) do
      [{:__meta__, %{fill_pointer: fp, adjustable: true} = meta}] when is_integer(fp) ->
        new_max = if fp >= max_dim, do: max(max_dim * 2, fp + 1), else: max_dim
        :ets.insert(tid, {fp, val})
        :ets.insert(tid, {:__meta__, %{meta | dimensions: [new_max], fill_pointer: fp + 1}})
        fp

      _ ->
        vector_push(val, arr)
    end
  end

  def vector_pop({:array, [_], tid}) do
    case :ets.lookup(tid, :__meta__) do
      [{:__meta__, %{fill_pointer: fp} = meta}] when is_integer(fp) and fp > 0 ->
        new_fp = fp - 1

        val =
          case :ets.lookup(tid, new_fp) do
            [{^new_fp, v}] -> v
            [] -> nil
          end

        :ets.insert(tid, {:__meta__, %{meta | fill_pointer: new_fp}})
        val

      _ ->
        nil
    end
  end

  def adjust_array([{:array, _old_dims, tid} = arr, new_dims | rest_opts]) do
    opts = parse_lisp_keywords(rest_opts)

    dimensions =
      cond do
        is_integer(new_dims) -> [new_dims]
        is_list(new_dims) -> new_dims
        true -> [0]
      end

    total_size = Enum.reduce(dimensions, 1, &Kernel.*/2)
    initial_element = Keyword.get(opts, :initial_element, nil)
    initial_contents = Keyword.get(opts, :initial_contents, nil)

    if initial_contents != nil do
      flat = flatten_initial_contents(initial_contents, dimensions)

      flat
      |> Enum.with_index()
      |> Enum.each(fn {val, idx} -> :ets.insert(tid, {idx, val}) end)
    else
      current_count = :ets.select_count(tid, [{{:"$1", :_}, [{:is_integer, :"$1"}], [true]}])

      if total_size > current_count do
        for idx <- current_count..(total_size - 1) do
          :ets.insert(tid, {idx, initial_element})
        end
      end
    end

    meta =
      case :ets.lookup(tid, :__meta__) do
        [{:__meta__, m}] -> m
        [] -> %{}
      end

    new_meta = Map.put(meta, :dimensions, dimensions)
    :ets.insert(tid, {:__meta__, new_meta})
    arr
  end

  def adjust_array(arr, new_dims), do: adjust_array([arr, new_dims])

  def coerce([object, result_type | _]) do
    type_str = result_type |> to_string_val() |> String.downcase() |> String.trim_leading("'")

    cond do
      type_str in ["list"] ->
        seq_to_list(object)

      type_str in ["string", "base-string", "simple-string"] ->
        if is_list(object), do: List.to_string(object), else: to_string_val(object)

      type_str in ["character", "base-char", "standard-char"] ->
        char_code(object)

      type_str in ["float", "single-float", "double-float", "short-float", "long-float"] ->
        if is_number(object), do: object * 1.0, else: object

      type_str in ["vector", "simple-vector"] ->
        if is_list(object),
          do: make_array([length(object), :initial_contents, object]),
          else: object

      true ->
        object
    end
  end

  def coerce(object, result_type), do: coerce([object, result_type])

  def fill_pointer({:array, _, tid}) do
    case :ets.lookup(tid, :__meta__) do
      [{:__meta__, %{fill_pointer: fp}}] when is_integer(fp) -> fp
      _ -> raise ArgumentError, "Array has no fill pointer"
    end
  end

  def set_fill_pointer({:array, _, tid}, fp) when is_integer(fp) do
    case :ets.lookup(tid, :__meta__) do
      [{:__meta__, meta}] ->
        :ets.insert(tid, {:__meta__, %{meta | fill_pointer: fp}})
        fp

      _ ->
        fp
    end
  end

  def array_has_fill_pointer_p({:array, _, tid}) do
    case :ets.lookup(tid, :__meta__) do
      [{:__meta__, %{fill_pointer: fp}}] when not is_nil(fp) -> :t
      _ -> nil
    end
  end

  def array_has_fill_pointer_p(_), do: nil

  def adjustable_array_p({:array, _, tid}) do
    case :ets.lookup(tid, :__meta__) do
      [{:__meta__, %{adjustable: true}}] -> :t
      _ -> nil
    end
  end

  def adjustable_array_p(_), do: nil

  defp compute_flat_index(dims, indices) do
    Enum.zip(indices, dims)
    |> Enum.reduce(0, fn {idx, dim}, acc ->
      acc * dim + idx
    end)
  end

  defp parse_lisp_keywords(args, allowed_keys \\ nil) do
    if rem(length(args), 2) != 0 do
      raise ArgumentError, "Odd number of keyword arguments: #{inspect(args)}"
    end

    pairs =
      args
      |> Enum.chunk_every(2)
      |> Enum.map(fn [k, v] ->
        key_atom =
          cond do
            is_atom(k) ->
              k
              |> Atom.to_string()
              |> String.trim_leading(":")
              |> String.replace("-", "_")
              |> String.to_atom()

            true ->
              raise ArgumentError, "Keyword argument name must be a symbol: #{inspect(k)}"
          end

        {key_atom, v}
      end)

    if allowed_keys != nil do
      allow_other_keys =
        case List.keyfind(pairs, :allow_other_keys, 0) do
          {:allow_other_keys, val} -> val not in [nil, nil, false]
          nil -> false
        end

      unless allow_other_keys do
        allowed_set = MapSet.new([:allow_other_keys | allowed_keys])

        for {k, _v} <- pairs do
          unless MapSet.member?(allowed_set, k) do
            raise ArgumentError, "Unrecognized keyword argument: #{inspect(k)}"
          end
        end
      end
    end

    pairs
  end

  # --- Structure & CLOS objects ---

  def make_struct(struct_name, default_slots, args) do
    opts = parse_lisp_keywords(args)
    tid = :ets.new(:lisp_struct, [:set, :public])

    Enum.each(default_slots, fn {slot, default_val} ->
      val = Keyword.get(opts, slot, default_val)
      :ets.insert(tid, {slot, val})
    end)

    {:struct, struct_name, tid}
  end

  def get_struct_slot({:struct, _name, tid}, slot_name) do
    norm_slot =
      cond do
        is_atom(slot_name) ->
          slot_name |> Atom.to_string() |> String.replace("-", "_") |> String.to_atom()

        true ->
          slot_name
      end

    case :ets.lookup(tid, norm_slot) do
      [{^norm_slot, val}] -> val
      _ -> nil
    end
  end

  def get_struct_slot(_other, _slot), do: nil

  def set_struct_slot({:struct, _name, tid}, slot_name, val) do
    norm_slot =
      cond do
        is_atom(slot_name) ->
          slot_name |> Atom.to_string() |> String.replace("-", "_") |> String.to_atom()

        true ->
          slot_name
      end

    :ets.insert(tid, {norm_slot, val})
    val
  end

  def set_struct_slot(_other, _slot, val), do: val

  def copy_struct({:struct, name, tid}) do
    new_tid = :ets.new(:lisp_struct, [:set, :public])
    :ets.foldl(fn {k, v}, _acc -> :ets.insert(new_tid, {k, v}) end, nil, tid)
    {:struct, name, new_tid}
  end

  def copy_struct(other), do: other

  def make_instance(args) when is_list(args) do
    case args do
      [class_name | initargs] ->
        opts = parse_lisp_keywords(initargs)
        tid = :ets.new(:lisp_instance, [:set, :public])
        Enum.each(opts, fn {k, v} -> :ets.insert(tid, {k, v}) end)

        norm_class =
          if is_atom(class_name), do: class_name, else: String.to_atom(to_string(class_name))

        {:instance, norm_class, tid}

      _ ->
        raise ArgumentError, "make-instance requires at least class name"
    end
  end

  def make_instance(class_name), do: make_instance([class_name])

  def slot_value({:instance, _class, tid}, slot_name) do
    norm_slot =
      if is_atom(slot_name),
        do: slot_name |> Atom.to_string() |> String.replace("-", "_") |> String.to_atom(),
        else: slot_name

    case :ets.lookup(tid, norm_slot) do
      [{^norm_slot, val}] -> val
      [] -> nil
    end
  end

  def slot_value({:struct, name, tid}, slot_name) do
    get_struct_slot({:struct, name, tid}, slot_name)
  end

  def slot_value(_other, _slot), do: nil

  def set_slot_value({:instance, _class, tid}, slot_name, val) do
    norm_slot =
      if is_atom(slot_name),
        do: slot_name |> Atom.to_string() |> String.replace("-", "_") |> String.to_atom(),
        else: slot_name

    :ets.insert(tid, {norm_slot, val})
    val
  end

  def set_slot_value({:struct, name, tid}, slot_name, val) do
    set_struct_slot({:struct, name, tid}, slot_name, val)
  end

  def set_slot_value(_other, _slot, val), do: val

  def slot_boundp({:instance, _class, tid}, slot_name) do
    norm_slot =
      if is_atom(slot_name),
        do: slot_name |> Atom.to_string() |> String.replace("-", "_") |> String.to_atom(),
        else: slot_name

    case :ets.member(tid, norm_slot) do
      true -> :t
      false -> nil
    end
  end

  def slot_boundp(_other, _slot), do: nil

  def slot_makunbound({:instance, _class, tid} = inst, slot_name) do
    norm_slot =
      if is_atom(slot_name),
        do: slot_name |> Atom.to_string() |> String.replace("-", "_") |> String.to_atom(),
        else: slot_name

    :ets.delete(tid, norm_slot)
    inst
  end

  def slot_makunbound(other, _slot), do: other

  # --- I/O & formatting ---

  def print(obj) do
    IO.puts("")
    IO.inspect(ExLisp.to_repl_display(obj))
    obj
  end

  def prin1(obj) do
    IO.inspect(ExLisp.to_repl_display(obj))
    obj
  end

  def princ(obj) do
    if is_binary(obj) do
      IO.write(obj)
    else
      IO.write("#{inspect(ExLisp.to_repl_display(obj))}")
    end

    obj
  end

  def write_line(obj, stream \\ nil)

  def write_line(obj, stream) when is_binary(obj) do
    if stream && is_pid(stream), do: IO.puts(stream, obj), else: IO.puts(obj)
    obj
  end

  def write_line(obj, _stream) do
    raise ArgumentError, "The value #{inspect(obj)} is not of type STRING"
  end

  def write_string(obj, stream \\ nil)

  def write_string(obj, stream) when is_binary(obj) do
    if stream && is_pid(stream), do: IO.write(stream, obj), else: IO.write(obj)
    obj
  end

  def write_string(obj, _stream) do
    raise ArgumentError, "The value #{inspect(obj)} is not of type STRING"
  end

  def write_char(char, stream \\ nil) do
    output =
      cond do
        is_binary(char) -> char
        is_integer(char) -> <<char::utf8>>
        true -> "#{inspect(ExLisp.to_repl_display(char))}"
      end

    if stream && is_pid(stream), do: IO.write(stream, output), else: IO.write(output)
    char
  end

  def write(args) when is_list(args) do
    case args do
      [obj | rest] ->
        stream =
          case rest do
            [:stream, s | _] -> s
            [s | _] when is_pid(s) -> s
            _ -> nil
          end

        str_val = inspect(ExLisp.to_repl_display(obj))
        if stream && is_pid(stream), do: IO.write(stream, str_val), else: IO.write(str_val)
        obj

      _ ->
        nil
    end
  end

  def write(obj), do: write([obj])

  def write_to_string(obj) do
    inspect(ExLisp.to_repl_display(obj))
  end

  def open(args) when is_list(args) do
    case args do
      [path | rest] ->
        filename = to_string_val(path)
        opts = parse_open_opts(rest)
        modes = build_file_modes(opts)

        case File.open(filename, modes) do
          {:ok, pid} ->
            pid

          {:error, reason} ->
            if opts[:direction] == :input and opts[:if_does_not_exist] == nil do
              nil
            else
              raise "Error opening file #{filename}: #{inspect(reason)}"
            end
        end

      _ ->
        raise ArgumentError, "open requires at least 1 argument"
    end
  end

  def open(path), do: open([path])

  def close(stream) do
    if is_pid(stream) or is_port(stream) do
      case File.close(stream) do
        :ok ->
          :t

        _ ->
          try do
            GenServer.call(stream, :close, 100)
          rescue
            _ ->
              if is_pid(stream) and Process.alive?(stream) do
                Process.exit(stream, :normal)
              end
          catch
            _, _ ->
              if is_pid(stream) and Process.alive?(stream) do
                Process.exit(stream, :normal)
              end
          end

          :t
      end
    else
      nil
    end
  end

  def eval(form) do
    ast = ExLisp.Macro.lisp_data_to_ast(form)
    LispBeam.evaluate_ast(ast)
  end

  def load(path) do
    file_path = to_string_val(path)

    cond do
      File.exists?(file_path) ->
        ExLisp.load_file(file_path)
        :t

      File.exists?("#{file_path}.lisp") ->
        ExLisp.load_file("#{file_path}.lisp")
        :t

      true ->
        raise "File not found: #{file_path}"
    end
  end

  def compile_file(path, opts \\ []) do
    file_path = to_string_val(path)

    case ExLisp.compile_file(file_path, opts) do
      {:ok, _mod, beam_path} ->
        beam_path

      {:error, reason} ->
        raise "Compilation error for #{file_path}: #{inspect(reason)}"
    end
  end

  def file_length(stream) do
    if is_pid(stream) do
      case :file.position(stream, :eof) do
        {:ok, size} ->
          :file.position(stream, :bof)
          size

        _ ->
          nil
      end
    else
      nil
    end
  end

  def listen(_stream \\ nil), do: nil

  def read_from_string(args) when is_list(args) do
    case args do
      [str | _rest] when is_binary(str) ->
        chars = String.to_charlist(str)

        case scan_first_expr(chars, 0, [], false, false, 0, []) do
          {:ok, expr_str, consumed_count} ->
            values(parse_read_expr(expr_str), consumed_count)

          :eof ->
            values(nil, 0)
        end

      _ ->
        values(nil, 0)
    end
  end

  def read_from_string(str) when is_binary(str), do: read_from_string([str])

  def read(args \\ []) do
    args_list = if is_list(args), do: args, else: [args]

    case args_list do
      [] ->
        case read_one_s_expr(:stdio) do
          {:ok, val} -> val
          :eof -> raise "End of file on standard input"
        end

      [source | rest] ->
        eof_error_p =
          case rest do
            [p | _] -> p not in [nil, nil, false]
            _ -> true
          end

        eof_val =
          case rest do
            [_, val | _] -> val
            _ -> nil
          end

        if is_binary(source) do
          trimmed = String.trim(source)

          if trimmed == "" do
            if eof_error_p, do: raise("End of file on input string"), else: eof_val
          else
            parse_read_expr(trimmed)
          end
        else
          device = if is_pid(source), do: source, else: :stdio

          case read_one_s_expr(device) do
            {:ok, val} ->
              val

            :eof ->
              if eof_error_p, do: raise("End of file on stream"), else: eof_val
          end
        end
    end
  end

  def read_line(args \\ []) do
    args_list = if is_list(args), do: args, else: [args]

    case args_list do
      [] ->
        case IO.read(:line) do
          :eof -> nil
          line -> String.trim_trailing(line, "\n") |> String.trim_trailing("\r")
        end

      [device | rest] ->
        eof_error_p =
          case rest do
            [p | _] -> p not in [nil, nil, false]
            _ -> false
          end

        eof_val =
          case rest do
            [_, val | _] -> val
            _ -> nil
          end

        dev = if is_pid(device), do: device, else: :stdio

        case IO.read(dev, :line) do
          :eof ->
            if eof_error_p, do: raise("End of file on stream"), else: eof_val

          {:error, _} ->
            if eof_error_p, do: raise("Read error"), else: eof_val

          line ->
            String.trim_trailing(line, "\n") |> String.trim_trailing("\r")
        end
    end
  end

  def read_char(args \\ []) do
    args_list = if is_list(args), do: args, else: [args]

    case args_list do
      [] ->
        case IO.getn("", 1) do
          :eof ->
            nil

          char_str when is_binary(char_str) and byte_size(char_str) > 0 ->
            char_str |> String.to_charlist() |> hd()

          _ ->
            nil
        end

      [device | rest] ->
        eof_error_p =
          case rest do
            [p | _] -> p not in [nil, nil, false]
            _ -> false
          end

        eof_val =
          case rest do
            [_, val | _] -> val
            _ -> nil
          end

        dev = if is_pid(device), do: device, else: :stdio

        case IO.getn(dev, "", 1) do
          :eof ->
            if eof_error_p, do: raise("End of file on stream"), else: eof_val

          char_str when is_binary(char_str) and byte_size(char_str) > 0 ->
            char_str |> String.to_charlist() |> hd()

          _ ->
            eof_val
        end
    end
  end

  def peek_char(args \\ []) do
    case args do
      [] -> read_char([])
      [_peek_type | rest] -> read_char(rest)
    end
  end

  defp parse_open_opts([]), do: [direction: :input]

  defp parse_open_opts([k, v | rest]) when is_atom(k) do
    key =
      k
      |> Atom.to_string()
      |> String.trim_leading(":")
      |> String.replace("-", "_")
      |> String.to_atom()

    [{key, v} | parse_open_opts(rest)]
  end

  defp parse_open_opts([_ | rest]), do: parse_open_opts(rest)

  defp build_file_modes(opts) do
    direction = Keyword.get(opts, :direction, :input)
    if_exists = Keyword.get(opts, :if_exists, :supersede)

    base =
      case direction do
        :input ->
          [:read, :utf8]

        :output ->
          case if_exists do
            :append -> [:append, :utf8]
            _ -> [:write, :utf8]
          end

        :io ->
          [:read, :write, :utf8]

        _ ->
          [:read, :utf8]
      end

    base
  end

  defp read_one_s_expr(device) do
    case try_string_io_contents(device) do
      {:ok, {in_str, _out_str}} ->
        read_from_string_buffer(device, in_str)

      _ ->
        read_from_io_device(device)
    end
  end

  defp try_string_io_contents(device) do
    if is_pid(device) do
      try do
        case StringIO.contents(device) do
          {in_str, out_str} when is_binary(in_str) and is_binary(out_str) ->
            {:ok, {in_str, out_str}}

          _ ->
            :error
        end
      rescue
        _ -> :error
      catch
        _, _ -> :error
      end
    else
      :error
    end
  end

  defp read_from_string_buffer(device, in_str) do
    chars = String.to_charlist(in_str)

    case scan_first_expr(chars, 0, [], false, false, 0, []) do
      {:ok, expr_str, consumed_count} ->
        _ = IO.read(device, consumed_count)
        {:ok, parse_read_expr(expr_str)}

      :eof ->
        :eof
    end
  end

  defp scan_first_expr([], consumed, _stack, _in_str, _in_cmt, _block_depth, current) do
    if current != [] do
      {:ok, current |> Enum.reverse() |> List.to_string(), consumed}
    else
      :eof
    end
  end

  # Skipping leading whitespace & comments before expression starts
  defp scan_first_expr([ws | rest], consumed, [], false, false, 0, [])
       when ws in [?\s, ?\t, ?\n, ?\r] do
    scan_first_expr(rest, consumed + 1, [], false, false, 0, [])
  end

  defp scan_first_expr([?; | rest], consumed, [], false, false, 0, []) do
    scan_first_expr(rest, consumed + 1, [], false, true, 0, [])
  end

  defp scan_first_expr([?#, ?| | rest], consumed, [], false, false, 0, []) do
    scan_first_expr(rest, consumed + 2, [], false, false, 1, [])
  end

  # Inside line comment
  defp scan_first_expr([?\n | rest], consumed, stack, _in_str, true, 0, current) do
    if stack == [] and current != [] do
      {:ok, current |> Enum.reverse() |> List.to_string(), consumed}
    else
      scan_first_expr(rest, consumed + 1, stack, false, false, 0, current)
    end
  end

  defp scan_first_expr([_c | rest], consumed, stack, in_str, true, 0, current) do
    scan_first_expr(rest, consumed + 1, stack, in_str, true, 0, current)
  end

  # Inside block comment
  defp scan_first_expr([?#, ?| | rest], consumed, stack, in_str, in_cmt, depth, current)
       when depth > 0 do
    scan_first_expr(rest, consumed + 2, stack, in_str, in_cmt, depth + 1, current)
  end

  defp scan_first_expr([?|, ?# | rest], consumed, stack, in_str, in_cmt, 1, current) do
    scan_first_expr(rest, consumed + 2, stack, in_str, in_cmt, 0, current)
  end

  defp scan_first_expr([?|, ?# | rest], consumed, stack, in_str, in_cmt, depth, current)
       when depth > 1 do
    scan_first_expr(rest, consumed + 2, stack, in_str, in_cmt, depth - 1, current)
  end

  defp scan_first_expr([_c | rest], consumed, stack, in_str, in_cmt, depth, current)
       when depth > 0 do
    scan_first_expr(rest, consumed + 1, stack, in_str, in_cmt, depth, current)
  end

  # Inside string literal
  defp scan_first_expr([?\\, c | rest], consumed, stack, true, false, 0, current) do
    scan_first_expr(rest, consumed + 2, stack, true, false, 0, [c, ?\\ | current])
  end

  defp scan_first_expr([?\" | rest], consumed, stack, true, false, 0, current) do
    new_curr = [?\" | current]

    if stack == [] do
      {:ok, new_curr |> Enum.reverse() |> List.to_string(), consumed + 1}
    else
      scan_first_expr(rest, consumed + 1, stack, false, false, 0, new_curr)
    end
  end

  defp scan_first_expr([c | rest], consumed, stack, true, false, 0, current) do
    scan_first_expr(rest, consumed + 1, stack, true, false, 0, [c | current])
  end

  # String start
  defp scan_first_expr([?\" | rest], consumed, stack, false, false, 0, current) do
    scan_first_expr(rest, consumed + 1, stack, true, false, 0, [?\" | current])
  end

  # Opening bracket
  defp scan_first_expr([open | rest], consumed, stack, false, false, 0, current)
       when open in [?(, ?[, ?{] do
    close =
      case open do
        ?( -> ?)
        ?[ -> ?]
        ?{ -> ?}
      end

    scan_first_expr(rest, consumed + 1, [close | stack], false, false, 0, [open | current])
  end

  # Closing bracket
  defp scan_first_expr(
         [close | rest],
         consumed,
         [expected | stack_rest],
         false,
         false,
         0,
         current
       )
       when close == expected do
    new_curr = [close | current]

    if stack_rest == [] do
      {:ok, new_curr |> Enum.reverse() |> List.to_string(), consumed + 1}
    else
      scan_first_expr(rest, consumed + 1, stack_rest, false, false, 0, new_curr)
    end
  end

  # Delimiter when stack is empty and we already have token characters
  defp scan_first_expr([delim | _rest], consumed, [], false, false, 0, current)
       when delim in [?\s, ?\t, ?\n, ?\r, ?;, ?(, ?)] and current != [] do
    {:ok, current |> Enum.reverse() |> List.to_string(), consumed}
  end

  # General character
  defp scan_first_expr([c | rest], consumed, stack, false, false, 0, current) do
    scan_first_expr(rest, consumed + 1, stack, false, false, 0, [c | current])
  end

  defp read_from_io_device(device) do
    case IO.read(device, :line) do
      :eof -> :eof
      {:error, _} -> :eof
      line -> {:ok, parse_read_expr(line)}
    end
  end

  defp parse_read_expr(str) do
    case ExLisp.LispParser.parse(str) do
      {:ok, ast} -> ast_to_lisp_val(ast)
      _ -> str
    end
  end

  defp ast_to_lisp_val(ast) do
    case ast do
      {:lit, v} ->
        v

      {:integer, _, v} ->
        v

      {:float, _, v} ->
        v

      {:id, _, [name]} ->
        case String.downcase(name) do
          "nil" -> nil
          "t" -> :t
          _ -> String.downcase(name) |> String.to_atom()
        end

      {:list, _, items} ->
        Enum.map(items, &ast_to_lisp_val/1)

      {:quoted, _, items} ->
        Enum.map(items, &ast_to_lisp_val/1)

      _ ->
        ast
    end
  end

  def terpri do
    IO.puts("")
    nil
  end

  def fresh_line do
    IO.puts("")
    :t
  end

  def format(dest, fmt_string, args \\ []) do
    fmt = to_string_val(fmt_string)
    arg_list = if is_list(args), do: args, else: [args]
    formatted = do_format(fmt, arg_list)

    cond do
      dest in [:t, :T, true, "t", "T"] ->
        IO.write(formatted)
        nil

      dest in [nil, false] ->
        formatted

      is_pid(dest) or is_port(dest) ->
        IO.write(dest, formatted)
        nil

      true ->
        formatted
    end
  end

  defp do_format(fmt, args) do
    parse_format(String.to_charlist(fmt), args, [])
  end

  defp parse_format([], _args, acc), do: acc |> Enum.reverse() |> List.to_string()

  defp parse_format([?~, directive | rest], args, acc) do
    case directive do
      d when d in [?A, ?a] ->
        {val, rem_args} = pop_arg(args)
        str_val = if is_binary(val), do: val, else: inspect(ExLisp.to_repl_display(val))
        parse_format(rest, rem_args, Enum.reverse(String.to_charlist(str_val)) ++ acc)

      d when d in [?S, ?s] ->
        {val, rem_args} = pop_arg(args)
        str_val = inspect(ExLisp.to_repl_display(val))
        parse_format(rest, rem_args, Enum.reverse(String.to_charlist(str_val)) ++ acc)

      d when d in [?D, ?d] ->
        {val, rem_args} = pop_arg(args)
        str_val = "#{val}"
        parse_format(rest, rem_args, Enum.reverse(String.to_charlist(str_val)) ++ acc)

      d when d in [?F, ?f] ->
        {val, rem_args} = pop_arg(args)
        str_val = "#{val}"
        parse_format(rest, rem_args, Enum.reverse(String.to_charlist(str_val)) ++ acc)

      ?% ->
        parse_format(rest, args, [?\n | acc])

      ?~ ->
        parse_format(rest, args, [?~ | acc])

      ?& ->
        parse_format(rest, args, [?\n | acc])

      _ ->
        parse_format(rest, args, [directive, ?~ | acc])
    end
  end

  defp parse_format([c | rest], args, acc) do
    parse_format(rest, args, [c | acc])
  end

  defp pop_arg([head | tail]), do: {head, tail}
  defp pop_arg([]), do: {nil, []}

  # --- Utilities ---

  def progv_eval(symbols, values, body_fn) when is_function(body_fn, 0) do
    sym_list = if is_list(symbols), do: symbols, else: [symbols]
    val_list = if is_list(values), do: values, else: [values]

    old_bindings =
      Enum.map(sym_list, fn sym ->
        norm = normalize_sym_prop(sym)

        old_val =
          if ExLisp.Env.has_var?(norm), do: {:ok, ExLisp.Env.get_var(norm)}, else: :unbound

        {norm, old_val}
      end)

    sym_list
    |> Enum.zip_reduce(val_list ++ Stream.cycle([nil]), nil, fn sym, val, _acc ->
      norm = normalize_sym_prop(sym)
      ExLisp.Env.put_var(norm, val)
      nil
    end)

    try do
      body_fn.()
    after
      Enum.each(old_bindings, fn
        {norm, {:ok, old_val}} -> ExLisp.Env.put_var(norm, old_val)
        {norm, :unbound} -> ExLisp.Env.delete_var(norm)
      end)
    end
  end

  def error(msg) do
    raise RuntimeError, to_string_val(msg)
  end

  def error(fmt, a1) do
    formatted =
      if is_binary(fmt) and String.contains?(fmt, "~"),
        do: format(nil, fmt, [a1]),
        else: "#{to_string_val(fmt)}: #{inspect(a1)}"

    raise RuntimeError, formatted
  end

  def error(fmt, a1, a2) do
    formatted =
      if is_binary(fmt) and String.contains?(fmt, "~"),
        do: format(nil, fmt, [a1, a2]),
        else: "#{to_string_val(fmt)} #{inspect(a1)} #{inspect(a2)}"

    raise RuntimeError, formatted
  end

  def error(fmt, a1, a2, a3) do
    formatted =
      if is_binary(fmt) and String.contains?(fmt, "~"),
        do: format(nil, fmt, [a1, a2, a3]),
        else: "#{to_string_val(fmt)} #{inspect(a1)} #{inspect(a2)} #{inspect(a3)}"

    raise RuntimeError, formatted
  end

  def error(fmt, a1, a2, a3, a4) do
    formatted =
      if is_binary(fmt) and String.contains?(fmt, "~"),
        do: format(nil, fmt, [a1, a2, a3, a4]),
        else: "#{to_string_val(fmt)} #{inspect(a1)} #{inspect(a2)} #{inspect(a3)} #{inspect(a4)}"

    raise RuntimeError, formatted
  end

  def error(fmt, a1, a2, a3, a4, a5) do
    formatted =
      if is_binary(fmt) and String.contains?(fmt, "~"),
        do: format(nil, fmt, [a1, a2, a3, a4, a5]),
        else: "#{to_string_val(fmt)} #{inspect([a1, a2, a3, a4, a5])}"

    raise RuntimeError, formatted
  end

  def error(fmt, a1, a2, a3, a4, a5, a6) do
    formatted =
      if is_binary(fmt) and String.contains?(fmt, "~"),
        do: format(nil, fmt, [a1, a2, a3, a4, a5, a6]),
        else: "#{to_string_val(fmt)} #{inspect([a1, a2, a3, a4, a5, a6])}"

    raise RuntimeError, formatted
  end

  def warn(args) when is_list(args) do
    msg =
      case args do
        [fmt | rest] -> format(nil, fmt, rest)
        _ -> "Warning"
      end

    IO.puts(:stderr, "WARNING: #{msg}")
    nil
  end

  def warn(msg), do: warn([msg])

  def cerror(args) when is_list(args) do
    case args do
      [_continue_fmt, error_fmt | rest] ->
        formatted = format(nil, error_fmt, rest)
        raise RuntimeError, formatted

      _ ->
        raise RuntimeError, "Continuable error"
    end
  end

  def cerror(_continue_fmt, error_fmt), do: cerror([nil, error_fmt])

  # --- Symbol & package ---

  defp get_plist_table do
    case :ets.whereis(:lisp_symbol_plist) do
      :undefined ->
        try do
          :ets.new(:lisp_symbol_plist, [:set, :public, :named_table])
        rescue
          _ -> :lisp_symbol_plist
        end

      tid ->
        tid
    end
  end

  defp normalize_sym_prop(%ExLisp.Symbol{id: id, name: name}) do
    if id != nil do
      :"$uninterned_#{id}$"
    else
      normalize_sym_prop(name)
    end
  end

  defp normalize_sym_prop(item) do
    cond do
      is_atom(item) ->
        item
        |> Atom.to_string()
        |> String.downcase()
        |> String.replace("-", "_")
        |> String.to_atom()

      is_binary(item) ->
        item |> String.downcase() |> String.replace("-", "_") |> String.to_atom()

      true ->
        item
    end
  end

  def gensym(args \\ []) do
    args_list = if is_list(args), do: args, else: [args]

    prefix =
      case args_list do
        [p | _] when is_binary(p) -> p
        [p | _] when is_atom(p) -> Atom.to_string(p)
        [p | _] when is_integer(p) -> "G#{p}"
        _ -> "G"
      end

    id = System.unique_integer([:positive, :monotonic])
    :"#{String.downcase(prefix)}#{id}"
  end

  def gentemp(args \\ []), do: gensym(args)

  def make_symbol(args) when is_list(args) do
    case args do
      [name] ->
        make_symbol(name)

      _ ->
        raise ArgumentError, "make-symbol requires 1 string argument"
    end
  end

  def make_symbol(name) do
    str = to_string_val(name)
    %ExLisp.Symbol{name: str, id: System.unique_integer([:positive, :monotonic])}
  end

  def copy_symbol(args) when is_list(args) do
    case args do
      [sym] -> copy_symbol(sym, nil)
      [sym, copy_props] -> copy_symbol(sym, copy_props)
      _ -> raise ArgumentError, "copy-symbol requires 1 or 2 arguments"
    end
  end

  def copy_symbol(sym, copy_props \\ nil) do
    sym = unwrap_mv_primary(sym)
    copy_props = unwrap_mv_primary(copy_props)
    name = symbol_name(sym)
    new_sym = %ExLisp.Symbol{name: name, id: System.unique_integer([:positive, :monotonic])}

    if truthy?(copy_props) do
      old_plist = symbol_plist(sym)
      set_symbol_plist(new_sym, old_plist)

      if truthy?(boundp(sym)) do
        try do
          val = symbol_value(sym)
          set_symbol_value(new_sym, val)
        rescue
          _ -> :ok
        end
      end

      if truthy?(fboundp(sym)) do
        try do
          fun = symbol_function(sym)
          set_symbol_function(new_sym, fun)
        rescue
          _ -> :ok
        end
      end
    end

    new_sym
  end

  @special_operators MapSet.new([
                       :block,
                       :catch,
                       :eval_when,
                       :flet,
                       :function,
                       :go,
                       :if,
                       :labels,
                       :let,
                       :letstar,
                       :"let*",
                       :load_time_value,
                       :locally,
                       :macrolet,
                       :multiple_value_call,
                       :multiple_value_prog1,
                       :progn,
                       :progv,
                       :quote,
                       :return_from,
                       :setq,
                       :symbol_macrolet,
                       :tagbody,
                       :the,
                       :throw,
                       :unwind_protect
                     ])

  def special_operator_p(args) when is_list(args) do
    case args do
      [sym] -> special_operator_p(sym)
      _ -> raise ArgumentError, "special-operator-p requires 1 argument"
    end
  end

  def special_operator_p(sym) do
    norm = normalize_sym_prop(sym)
    MapSet.member?(@special_operators, norm) |> lisp_bool()
  end

  def symbol_name(%ExLisp.Symbol{name: name}), do: name

  def symbol_name(sym) do
    str =
      cond do
        is_atom(sym) ->
          Atom.to_string(sym)

        true ->
          to_string_val(sym)
      end

    str = String.trim_leading(str, ":")

    cleaned =
      case str do
        "#:UNINTERNED_" <> rest ->
          case String.split(rest, "_", parts: 2) do
            [_id, name] ->
              if String.starts_with?(name, "|") and String.ends_with?(name, "|") do
                String.slice(name, 1..-2//1)
              else
                String.replace(name, "_", "-") |> String.upcase()
              end

            _ ->
              rest
          end

        "#:uninterned_" <> rest ->
          case String.split(rest, "_", parts: 2) do
            [_id, name] ->
              if String.starts_with?(name, "|") and String.ends_with?(name, "|") do
                String.slice(name, 1..-2//1)
              else
                String.replace(name, "_", "-") |> String.upcase()
              end

            _ ->
              rest
          end

        "#:" <> rest ->
          rest

        "|" <> rest ->
          String.trim_trailing(rest, "|")

        other ->
          String.upcase(other)
      end

    cleaned
  end

  def symbol_package(%ExLisp.Symbol{}), do: nil
  def symbol_package([sym]), do: symbol_package(sym)

  def symbol_package(sym) when is_atom(sym) do
    if keywordp(sym) == :t do
      :KEYWORD
    else
      :COMMON_LISP_USER
    end
  end

  def symbol_package(_), do: nil

  def symbol_value([sym]), do: symbol_value(sym)
  def symbol_value(nil), do: nil
  def symbol_value(:t), do: :t

  def symbol_value(sym) do
    sym = unwrap_mv_primary(sym)

    case sym do
      nil ->
        nil

      :t ->
        :t

      _ ->
        norm = normalize_sym_prop(sym)
        ExLisp.Env.get_var(norm)
    end
  end

  def set_symbol_value([sym, val]), do: set_symbol_value(sym, val)

  def set_symbol_value(sym, val) do
    sym = unwrap_mv_primary(sym)
    val = unwrap_mv_primary(val)
    norm = normalize_sym_prop(sym)
    ExLisp.Env.set_var(norm, val)
    val
  end

  def symbol_function(sym) do
    norm = normalize_sym_prop(sym)
    ExLisp.Env.get_fun(norm)
  end

  def fdefinition(sym), do: symbol_function(sym)

  def set_symbol_function(sym, fun) do
    norm = normalize_sym_prop(sym)
    ExLisp.Env.put_fun(norm, fun)
    fun
  end

  def set_fdefinition(sym, fun), do: set_symbol_function(sym, fun)

  def fmakunbound(sym) do
    norm = normalize_sym_prop(sym)
    ExLisp.Env.delete_fun(norm)
    sym
  end

  def makunbound(sym) do
    norm = normalize_sym_prop(sym)
    ExLisp.Env.delete_var(norm)
    :erlang.erase(norm)
    sym
  end

  def cell_error_name([c | _]), do: cell_error_name(c)

  def cell_error_name(c) do
    cond do
      is_struct(c) and Map.has_key?(c, :message) ->
        msg = c.message

        cond do
          String.starts_with?(msg, "Unbound variable: ") ->
            name = String.trim_leading(msg, "Unbound variable: ")
            String.to_atom(name)

          String.starts_with?(msg, "Undefined function: ") ->
            name = String.trim_leading(msg, "Undefined function: ")
            String.to_atom(name)

          true ->
            nil
        end

      is_atom(c) ->
        c

      true ->
        nil
    end
  end

  def get_symbol_prop(sym, prop, default \\ nil) do
    sym = unwrap_mv_primary(sym)
    prop = unwrap_mv_primary(prop)
    default = unwrap_mv_primary(default)
    norm_sym = normalize_sym_prop(sym)
    norm_prop = normalize_sym_prop(prop)
    plist = symbol_plist(norm_sym)
    get_plist_prop(plist, norm_prop, default)
  end

  def set_symbol_prop(sym, prop, val) do
    sym = unwrap_mv_primary(sym)
    prop = unwrap_mv_primary(prop)
    val = unwrap_mv_primary(val)
    norm_sym = normalize_sym_prop(sym)
    norm_prop = normalize_sym_prop(prop)
    plist = symbol_plist(norm_sym)
    new_plist = set_plist_prop(plist, norm_prop, val)
    set_symbol_plist(norm_sym, new_plist)
    val
  end

  def remprop(sym, prop) do
    sym = unwrap_mv_primary(sym)
    prop = unwrap_mv_primary(prop)
    norm_sym = normalize_sym_prop(sym)
    norm_prop = normalize_sym_prop(prop)
    plist = symbol_plist(norm_sym)

    case remove_plist_prop(plist, norm_prop) do
      {true, new_plist} ->
        set_symbol_plist(norm_sym, new_plist)
        :t

      {false, _} ->
        nil
    end
  end

  def symbol_plist(sym) do
    sym = unwrap_mv_primary(sym)
    tab = get_plist_table()
    norm_sym = normalize_sym_prop(sym)

    case :ets.lookup(tab, {:plist, norm_sym}) do
      [{_, plist}] when is_list(plist) -> plist
      _ -> []
    end
  end

  def set_symbol_plist(sym, plist) do
    sym = unwrap_mv_primary(sym)
    plist = unwrap_mv_primary(plist)
    tab = get_plist_table()
    norm_sym = normalize_sym_prop(sym)
    plist_list = if is_list(plist), do: plist, else: []
    :ets.insert(tab, {{:plist, norm_sym}, plist_list})
    plist
  end

  defp get_plist_prop([], _prop, default), do: default

  defp get_plist_prop([p, v | rest], prop, default) do
    if p == prop or normalize_sym_prop(p) == prop do
      v
    else
      get_plist_prop(rest, prop, default)
    end
  end

  defp get_plist_prop(_other, _prop, default), do: default

  defp set_plist_prop([], prop, val), do: [prop, val]

  defp set_plist_prop([p, _v | rest], prop, val)
       when p == prop or :erlang.element(1, {p == prop}) == true do
    [prop, val | rest]
  end

  defp set_plist_prop([p, v | rest], prop, val) do
    if p == prop or normalize_sym_prop(p) == prop do
      [prop, val | rest]
    else
      [p, v | set_plist_prop(rest, prop, val)]
    end
  end

  defp set_plist_prop(other, prop, val), do: [prop, val | List.wrap(other)]

  defp remove_plist_prop([], _prop), do: {false, []}

  defp remove_plist_prop([p, _v | rest], prop) when p == prop do
    {true, rest}
  end

  defp remove_plist_prop([p, v | rest], prop) do
    if normalize_sym_prop(p) == prop do
      {true, rest}
    else
      {removed?, new_rest} = remove_plist_prop(rest, prop)
      {removed?, [p, v | new_rest]}
    end
  end

  defp remove_plist_prop(other, _prop), do: {false, other}

  def intern(name, _pkg \\ nil) do
    normalize_sym_prop(name)
  end

  def find_symbol(name, _pkg \\ nil) do
    normalize_sym_prop(name)
  end

  def defpackage(args) do
    case args do
      [pkg | _] -> normalize_sym_prop(pkg)
      pkg -> normalize_sym_prop(pkg)
    end
  end

  def in_package(args) do
    case args do
      [pkg | _] -> normalize_sym_prop(pkg)
      pkg -> normalize_sym_prop(pkg)
    end
  end

  def find_package(args) do
    case args do
      [pkg | _] -> normalize_sym_prop(pkg)
      pkg -> normalize_sym_prop(pkg)
    end
  end

  # --- Bitwise & math operations ---

  def logand(args) when is_list(args) do
    Enum.reduce(args, -1, &band/2)
  end

  def logand, do: -1
  def logand(a, b), do: band(a, b)

  def logior(args) when is_list(args) do
    Enum.reduce(args, 0, &bor/2)
  end

  def logior, do: 0
  def logior(a, b), do: bor(a, b)

  def logxor(args) when is_list(args) do
    Enum.reduce(args, 0, &bxor/2)
  end

  def logxor, do: 0
  def logxor(a, b), do: bxor(a, b)

  def lognot(n) when is_integer(n), do: bnot(n)

  def logeqv(args) when is_list(args) do
    case args do
      [] -> -1
      [single] -> single
      [first | rest] -> Enum.reduce(rest, first, fn elem, acc -> bnot(bxor(acc, elem)) end)
    end
  end

  def logeqv, do: -1
  def logeqv(a, b), do: bnot(bxor(a, b))

  def lognand(a, b) when is_integer(a) and is_integer(b), do: bnot(band(a, b))
  def lognor(a, b) when is_integer(a) and is_integer(b), do: bnot(bor(a, b))
  def logandc1(a, b) when is_integer(a) and is_integer(b), do: band(bnot(a), b)
  def logandc2(a, b) when is_integer(a) and is_integer(b), do: band(a, bnot(b))
  def logorc1(a, b) when is_integer(a) and is_integer(b), do: bor(bnot(a), b)
  def logorc2(a, b) when is_integer(a) and is_integer(b), do: bor(a, bnot(b))

  def ash(n, count) when is_integer(n) and is_integer(count) do
    if count >= 0 do
      bsl(n, count)
    else
      bsr(n, -count)
    end
  end

  def logbitp(index, n) when is_integer(index) and is_integer(n) do
    if band(bsr(n, index), 1) == 1, do: :t, else: nil
  end

  def logcount(0), do: 0
  def logcount(-1), do: 0

  def logcount(n) when is_integer(n) and n > 0 do
    bin = :binary.encode_unsigned(n)
    count_byte_bits(bin, 0)
  end

  def logcount(n) when is_integer(n) and n < 0 do
    logcount(bnot(n))
  end

  defp count_byte_bits(<<>>, acc), do: acc

  defp count_byte_bits(<<byte, rest::binary>>, acc) do
    count_byte_bits(rest, acc + byte_popcount(byte))
  end

  defp byte_popcount(b) do
    b1 = b - band(bsr(b, 1), 0x55)
    b2 = band(b1, 0x33) + band(bsr(b1, 2), 0x33)
    band(b2 + bsr(b2, 4), 0x0F)
  end

  def integer_length(0), do: 0
  def integer_length(-1), do: 0

  def integer_length(n) when is_integer(n) and n > 0 do
    bin = :binary.encode_unsigned(n)
    <<first, _rest::binary>> = bin
    (byte_size(bin) - 1) * 8 + byte_len_bits(first)
  end

  def integer_length(n) when is_integer(n) and n < 0 do
    integer_length(bnot(n))
  end

  defp byte_len_bits(b) when b >= 128, do: 8
  defp byte_len_bits(b) when b >= 64, do: 7
  defp byte_len_bits(b) when b >= 32, do: 6
  defp byte_len_bits(b) when b >= 16, do: 5
  defp byte_len_bits(b) when b >= 8, do: 4
  defp byte_len_bits(b) when b >= 4, do: 3
  defp byte_len_bits(b) when b >= 2, do: 2
  defp byte_len_bits(b) when b >= 1, do: 1
  defp byte_len_bits(0), do: 0

  def isqrt(n) when is_integer(n) and n >= 0 do
    if n == 0 do
      0
    else
      do_isqrt(n, n)
    end
  end

  defp do_isqrt(n, x0) do
    x1 = div(x0 + div(n, x0), 2)

    if x1 < x0 do
      do_isqrt(n, x1)
    else
      x0
    end
  end

  def byte(size, pos) when is_integer(size) and is_integer(pos), do: {:byte, size, pos}

  def ldb({:byte, size, pos}, integer)
      when is_integer(size) and is_integer(pos) and is_integer(integer) do
    mask = bsl(1, size) - 1
    shifted = if pos >= 0, do: bsr(integer, pos), else: bsl(integer, -pos)
    band(shifted, mask)
  end

  def random(arg1, arg2 \\ nil)

  def random(args, _state) when is_list(args) do
    case args do
      [limit, state | _] -> random(limit, state)
      [limit | _] -> random(limit, nil)
      _ -> 0
    end
  end

  def random(limit, _state) when is_integer(limit) and limit > 0 do
    :rand.uniform(limit) - 1
  end

  def random(limit, _state) when is_float(limit) and limit > 0.0 do
    :rand.uniform() * limit
  end

  def make_random_state(_state \\ nil) do
    :":*random_state*:"
  end

  def make_string(args) when is_list(args) do
    case args do
      [size | rest] ->
        unless is_integer(size) and size >= 0 do
          raise ArgumentError,
                "make-string requires non-negative integer size, got: #{inspect(size)}"
        end

        opts = parse_lisp_keywords(rest, [:initial_element, :element_type])

        initial_element =
          case List.keyfind(opts, :initial_element, 0) do
            {:initial_element, elem} ->
              cond do
                is_integer(elem) -> elem
                is_binary(elem) and byte_size(elem) > 0 -> hd(String.to_charlist(elem))
                true -> ?\s
              end

            nil ->
              ?\s
          end

        String.duplicate(<<initial_element::utf8>>, size)

      _ ->
        raise ArgumentError, "make-string requires at least 1 argument"
    end
  end

  def make_string(size, opts \\ []) when is_integer(size) and size >= 0 do
    opt_list = if is_list(opts), do: opts, else: [opts]
    make_string([size | opt_list])
  end

  @char_names %{
    ?\s => "Space",
    ?\n => "Newline",
    ?\t => "Tab",
    ?\r => "Return",
    ?\f => "Page",
    ?\b => "Backspace",
    27 => "Escape",
    127 => "Rubout",
    0 => "Null"
  }

  @name_chars Map.new(@char_names, fn {code, name} -> {String.downcase(name), code} end)
              |> Map.put("linefeed", ?\n)

  def char_name(char) do
    code = char_code(char)
    Map.get(@char_names, code, nil)
  end

  def name_char(name) do
    str = string_designator_to_string(name) |> String.downcase()
    Map.get(@name_chars, str, nil)
  end

  def digit_char(arg1, arg2 \\ 10)

  def digit_char(args, _radix) when is_list(args) do
    case args do
      [weight, radix | _] -> digit_char(weight, radix)
      [weight | _] -> digit_char(weight, 10)
      _ -> nil
    end
  end

  def digit_char(weight, radix) when is_integer(weight) and is_integer(radix) do
    if weight >= 0 and weight < radix and radix >= 2 and radix <= 36 do
      cond do
        weight < 10 -> ?0 + weight
        true -> ?A + (weight - 10)
      end
    else
      nil
    end
  end

  def char_int(char), do: char_code(char)
  def int_char(int), do: code_char(int)

  def sxhash(obj) do
    :erlang.phash2(obj)
  end

  def make_string_input_stream(string, arg2 \\ 0, arg3 \\ nil) do
    str = to_string_val(string)

    {start, end_pos} =
      cond do
        is_integer(arg2) ->
          {arg2, arg3}

        is_list(arg2) ->
          opts = parse_lisp_keywords(arg2)
          s = Keyword.get(opts, :start, 0)
          e = Keyword.get(opts, :end, nil)
          {s, e}

        arg2 in [:start, :":start"] ->
          {arg3, nil}

        true ->
          {0, nil}
      end

    s = if is_integer(start) and start > 0, do: start, else: 0

    sliced =
      if is_integer(end_pos) and end_pos >= s do
        String.slice(str, s, end_pos - s)
      else
        String.slice(str, s..-1//1)
      end

    {:ok, pid} = StringIO.open(sliced)
    pid
  end

  def make_string_output_stream(_opts \\ []) do
    {:ok, pid} = StringIO.open("")
    pid
  end

  def get_output_stream_string(stream) do
    if is_pid(stream) do
      StringIO.flush(stream)
    else
      ""
    end
  end

  def boole(op, integer1, integer2)
      when is_integer(op) and is_integer(integer1) and is_integer(integer2) do
    case op do
      0 -> 0
      1 -> -1
      2 -> integer1
      3 -> integer2
      4 -> bnot(integer1)
      5 -> bnot(integer2)
      6 -> band(integer1, integer2)
      7 -> bor(integer1, integer2)
      8 -> bxor(integer1, integer2)
      9 -> bnot(bxor(integer1, integer2))
      10 -> bnot(band(integer1, integer2))
      11 -> bnot(bor(integer1, integer2))
      12 -> band(bnot(integer1), integer2)
      13 -> band(integer1, bnot(integer2))
      14 -> bor(bnot(integer1), integer2)
      15 -> bor(integer1, bnot(integer2))
      _ -> raise ArgumentError, "Invalid boole operation: #{op}"
    end
  end

  def logtest(integer1, integer2) when is_integer(integer1) and is_integer(integer2) do
    if band(integer1, integer2) != 0, do: :t, else: nil
  end

  def signum(%ExLisp.Ratio{numerator: n}) do
    cond do
      n > 0 -> 1
      n < 0 -> -1
      true -> 0
    end
  end

  def signum({:complex, r, i}) do
    if r == 0 and i == 0 do
      {:complex, 0, 0}
    else
      # z / abs(z)
      abs_val = :math.sqrt(r * r + i * i)
      {:complex, r / abs_val, i / abs_val}
    end
  end

  def signum([number]), do: signum(number)

  def signum(number) when is_integer(number) do
    cond do
      number > 0 -> 1
      number < 0 -> -1
      true -> 0
    end
  end

  def signum(number) when is_float(number) do
    cond do
      number > 0.0 -> 1.0
      number < 0.0 -> -1.0
      true -> 0.0
    end
  end

  def parse_integer(args) when is_list(args) do
    case args do
      [str | rest] ->
        str_val = to_string_val(str)
        opts = parse_lisp_keywords(rest)
        start_idx = Keyword.get(opts, :start, 0)
        end_idx = Keyword.get(opts, :end, nil)
        radix = Keyword.get(opts, :radix, 10)

        junk_allowed =
          truthy?(Keyword.get(opts, :junk_allowed, Keyword.get(opts, :"junk-allowed", nil)))

        do_parse_integer(str_val, start_idx, end_idx, radix, junk_allowed)

      str ->
        str_val = to_string_val(str)
        do_parse_integer(str_val, 0, nil, 10, false)
    end
  end

  def parse_integer(str, opts) when is_list(opts) do
    parse_integer([str | opts])
  end

  defp do_parse_integer(str, start_idx, end_idx, radix, junk_allowed) do
    str_len = String.length(str)
    s = if is_integer(start_idx) and start_idx >= 0, do: start_idx, else: 0
    e = if is_integer(end_idx) and end_idx <= str_len, do: end_idx, else: str_len

    if s > e or s > str_len do
      raise ArgumentError, "invalid bounding index: start=#{s}, end=#{e}"
    end

    target_chars =
      str
      |> String.slice(s, e - s)
      |> String.to_charlist()

    {trimmed_chars, ws_count} = skip_leading_ws(target_chars, 0)
    current_offset = s + ws_count

    case trimmed_chars do
      [] ->
        if junk_allowed do
          [:_values_, [nil, current_offset]]
        else
          raise ArgumentError, "parse-integer: no digits found"
        end

      [first_char | rest_after_sign] when first_char in [?+, ?-] ->
        sign = if first_char == ?-, do: -1, else: 1
        sign_offset = current_offset + 1
        {digits, rest_after_digits} = read_digits(rest_after_sign, radix, [])

        if digits == [] do
          if junk_allowed do
            [:_values_, [nil, current_offset]]
          else
            raise ArgumentError, "parse-integer: no digits after sign"
          end
        else
          int_val = Integer.undigits(digits, radix) * sign
          parsed_end_offset = sign_offset + length(digits)

          if junk_allowed do
            [:_values_, [int_val, parsed_end_offset]]
          else
            {trailing_rest, _trailing_ws_count} = skip_leading_ws(rest_after_digits, 0)

            if trailing_rest != [] do
              raise ArgumentError, "parse-integer: junk found in string"
            else
              [:_values_, [int_val, e]]
            end
          end
        end

      chars ->
        {digits, rest_after_digits} = read_digits(chars, radix, [])

        if digits == [] do
          if junk_allowed do
            [:_values_, [nil, current_offset]]
          else
            raise ArgumentError, "parse-integer: no digits found"
          end
        else
          int_val = Integer.undigits(digits, radix)
          parsed_end_offset = current_offset + length(digits)

          if junk_allowed do
            [:_values_, [int_val, parsed_end_offset]]
          else
            {trailing_rest, _trailing_ws_count} = skip_leading_ws(rest_after_digits, 0)

            if trailing_rest != [] do
              raise ArgumentError, "parse-integer: junk found in string"
            else
              [:_values_, [int_val, e]]
            end
          end
        end
    end
  end

  defp skip_leading_ws([c | rest], count) when c in [?\s, ?\t, ?\n, ?\r, 12] do
    skip_leading_ws(rest, count + 1)
  end

  defp skip_leading_ws(chars, count), do: {chars, count}

  defp read_digits([c | rest], radix, acc) do
    digit_val = char_to_digit_val(c)

    if digit_val != nil and digit_val < radix do
      read_digits(rest, radix, acc ++ [digit_val])
    else
      {acc, [c | rest]}
    end
  end

  defp read_digits([], _radix, acc), do: {acc, []}

  defp char_to_digit_val(c) do
    cond do
      c >= ?0 and c <= ?9 -> c - ?0
      c >= ?A and c <= ?Z -> c - ?A + 10
      c >= ?a and c <= ?z -> c - ?a + 10
      true -> nil
    end
  end

  def dpb(newbyte, {:byte, size, pos}, integer)
      when is_integer(newbyte) and is_integer(size) and is_integer(pos) and is_integer(integer) do
    mask = bsl(1, size) - 1
    masked_val = band(newbyte, mask)
    shifted_val = bsl(masked_val, pos)
    clear_mask = bnot(bsl(mask, pos))
    bor(band(integer, clear_mask), shifted_val)
  end

  # --- REPL history & re-execution ---

  def r(args \\ []) do
    n =
      case args do
        [num | _] when is_integer(num) -> num
        num when is_integer(num) -> num
        _ -> -1
      end

    case ExLisp.Env.get_history_code(n) do
      nil ->
        IO.puts(:stderr, "No history code found for index #{n}")
        nil

      code ->
        IO.puts("==> #{code}")
        ExLisp.eval_repl(code)
    end
  end

  def v(args \\ []) do
    n =
      case args do
        [num | _] when is_integer(num) -> num
        num when is_integer(num) -> num
        _ -> -1
      end

    ExLisp.Env.get_history_result(n)
  end

  # --- Property list (plist) & macro expansion ---

  def getf(args) when is_list(args) do
    case args do
      [plist, indicator] -> getf(plist, indicator, nil)
      [plist, indicator, default] -> getf(plist, indicator, default)
      _ -> raise ArgumentError, "getf requires 2 or 3 arguments"
    end
  end

  def getf(plist, indicator, default \\ nil)

  def getf(plist, indicator, default) when is_list(plist) do
    do_getf(plist, indicator, default)
  end

  def getf(_other, _indicator, default), do: default

  defp do_getf(nil, _indicator, default), do: default
  defp do_getf([], _indicator, default), do: default
  defp do_getf([_single], _indicator, default), do: default

  defp do_getf([k, v | rest], indicator, default) do
    if eq(k, indicator) == :t do
      v
    else
      do_getf(rest, indicator, default)
    end
  end

  defp do_getf(_other, _indicator, default), do: default

  def get_properties(args) when is_list(args) do
    case args do
      [plist, indicator_list]
      when (is_list(plist) or plist == nil) and (is_list(indicator_list) or indicator_list == nil) ->
        ensure_proper_list!(plist || [])
        ensure_proper_list!(indicator_list || [])
        do_get_properties(plist || [], indicator_list || [])

      [plist, indicator_list] ->
        ensure_proper_list!(plist || [])
        ensure_proper_list!(indicator_list || [])
        do_get_properties(plist || [], indicator_list || [])

      _ ->
        raise ArgumentError, "get-properties requires 2 arguments"
    end
  end

  def get_properties(plist, indicator_list), do: get_properties([plist, indicator_list])

  defp do_get_properties([], _ind_list), do: [:_values_, [nil, nil, nil]]
  defp do_get_properties([_single], _ind_list), do: [:_values_, [nil, nil, nil]]

  defp do_get_properties([ind, val | rest] = tail, ind_list) do
    if is_list(rest) do
      if Enum.any?(ind_list, fn target -> eq(ind, target) == :t end) do
        [:_values_, [ind, val, tail]]
      else
        do_get_properties(rest, ind_list)
      end
    else
      raise ArgumentError,
            "get-properties requires a proper list, got dotted tail: #{inspect(rest)}"
    end
  end

  def rem_plist(plist, indicator) when is_list(plist) do
    case do_rem_plist(plist, indicator) do
      {:removed, new_list} -> [new_list, :t]
      :not_found -> [plist, nil]
    end
  end

  def rem_plist(other, _indicator), do: [other, nil]

  defp do_rem_plist(nil, _indicator), do: :not_found
  defp do_rem_plist([], _indicator), do: :not_found
  defp do_rem_plist([_single], _indicator), do: :not_found

  defp do_rem_plist([k, v | rest], indicator) do
    if eq(k, indicator) == :t do
      {:removed, rest}
    else
      case do_rem_plist(rest, indicator) do
        {:removed, new_rest} -> {:removed, [k, v | new_rest]}
        :not_found -> :not_found
      end
    end
  end

  defp do_rem_plist(_other, _indicator), do: :not_found

  def exlisp_check_key_args(args, allowed_keys, allow_other_keys) do
    if is_list(args) do
      pairs = Enum.chunk_every(args, 2)

      explicit_allow =
        Enum.find_value(pairs, nil, fn
          [k, v] ->
            norm_k =
              case k do
                a when is_atom(a) ->
                  Atom.to_string(a)
                  |> String.trim_leading(":")
                  |> String.downcase()
                  |> String.replace("-", "_")

                s when is_binary(s) ->
                  s
                  |> String.trim_leading(":")
                  |> String.downcase()
                  |> String.replace("-", "_")

                _ ->
                  ""
              end

            if norm_k in ["allow_other_keys", "allow-other-keys"] do
              {:ok, truthy?(v)}
            else
              nil
            end

          _ ->
            nil
        end)

      allowed? =
        case explicit_allow do
          {:ok, val} -> val
          nil -> truthy?(allow_other_keys)
        end

      unless allowed? do
        norm_allowed =
          Enum.map(allowed_keys, fn ak ->
            case ak do
              a when is_atom(a) ->
                Atom.to_string(a)
                |> String.trim_leading(":")
                |> String.downcase()
                |> String.replace("-", "_")

              s when is_binary(s) ->
                s
                |> String.trim_leading(":")
                |> String.downcase()
                |> String.replace("-", "_")

              _ ->
                ""
            end
          end)

        Enum.each(pairs, fn
          [k | _] when is_atom(k) or is_binary(k) ->
            norm_k =
              case k do
                a when is_atom(a) ->
                  Atom.to_string(a)
                  |> String.trim_leading(":")
                  |> String.downcase()
                  |> String.replace("-", "_")

                s when is_binary(s) ->
                  s
                  |> String.trim_leading(":")
                  |> String.downcase()
                  |> String.replace("-", "_")
              end

            unless norm_k in norm_allowed or norm_k in ["allow_other_keys", "allow-other-keys"] do
              raise RuntimeError, "Unrecognized keyword argument: #{inspect(k)}"
            end

          _ ->
            :ok
        end)
      end
    end

    :t
  end

  def put_plist(args) when is_list(args) do
    case args do
      [plist, indicator, value] -> put_plist(plist, indicator, value)
      _ -> raise ArgumentError, "put-plist requires 3 arguments"
    end
  end

  def put_plist(plist, indicator, value) when is_list(plist) do
    case do_put_plist(plist, indicator, value) do
      {:updated, new_list} -> new_list
      :not_found -> [indicator, value | plist]
    end
  end

  def put_plist(nil, indicator, value), do: [indicator, value]
  def put_plist(_other, indicator, value), do: [indicator, value]

  defp do_put_plist(nil, _indicator, _value), do: :not_found
  defp do_put_plist([], _indicator, _value), do: :not_found
  defp do_put_plist([_single], _indicator, _value), do: :not_found

  defp do_put_plist([k, v | rest], indicator, value) do
    if eq(k, indicator) == :t do
      {:updated, [k, value | rest]}
    else
      case do_put_plist(rest, indicator, value) do
        {:updated, new_rest} -> {:updated, [k, v | new_rest]}
        :not_found -> :not_found
      end
    end
  end

  defp do_put_plist(_other, _indicator, _value), do: :not_found

  def set_nth(args) when is_list(args) do
    case args do
      [idx, list, val] -> set_nth(idx, list, val)
      _ -> raise ArgumentError, "set-nth requires 3 arguments"
    end
  end

  def set_nth(idx, list, val) when is_integer(idx) and idx >= 0 and is_list(list) do
    do_set_nth(idx, list, val)
  end

  def set_nth(_idx, list, _val), do: list

  defp do_set_nth(0, [_ | tail], val), do: [val | tail]

  defp do_set_nth(n, [head | tail], val) when n > 0 and is_list(tail) do
    [head | do_set_nth(n - 1, tail, val)]
  end

  defp do_set_nth(_n, list, _val), do: list

  @builtin_macro_names [
    :push,
    :pop,
    :pushnew,
    :remf,
    :incf,
    :decf,
    :setf,
    :psetf,
    :shiftf,
    :rotatef,
    :when,
    :unless,
    :cond,
    :case,
    :typecase,
    :ecase,
    :etypecase,
    :ccase,
    :ctypecase,
    :dotimes,
    :dolist,
    :do,
    :do_star,
    :loop,
    :multiple_value_bind,
    :multiple_value_setq,
    :multiple_value_list,
    :nth_value,
    :prog,
    :prog_star,
    :prog1,
    :prog2,
    :return,
    :with_open_file,
    :with_input_from_string,
    :with_output_to_string,
    :handler_case,
    :handler_bind,
    :ignore_errors,
    :restart_case,
    :restart_bind,
    :destructuring_bind,
    :defmacro,
    :defun,
    :defvar,
    :defparameter,
    :defconstant,
    :defstruct,
    :deftype,
    :define_modify_macro,
    :define_setf_expander,
    :defsetf,
    :check_type,
    :assert
  ]

  def macro_function(sym, _env \\ nil) do
    macro_name =
      case sym do
        a when is_atom(a) ->
          a
          |> Atom.to_string()
          |> String.downcase()
          |> String.replace("-", "_")
          |> String.to_atom()

        %ExLisp.Symbol{name: n} ->
          String.downcase(n) |> String.replace("-", "_") |> String.to_atom()

        s when is_binary(s) ->
          String.downcase(s) |> String.replace("-", "_") |> String.to_atom()

        _ ->
          nil
      end

    cond do
      macro_name && ExLisp.Env.has_macro?(macro_name) ->
        ExLisp.Env.get_macro(macro_name)

      macro_name && macro_name in @builtin_macro_names ->
        %ExLisp.Closure{name: macro_name, fun: fn _ -> nil end, variadic: true}

      true ->
        nil
    end
  end

  def macroexpand_1(form, _env \\ nil) do
    case form do
      [op | args] when is_list(args) ->
        op_name =
          case op do
            a when is_atom(a) -> a
            %ExLisp.Symbol{name: n} -> String.downcase(n) |> String.to_atom()
            s when is_binary(s) -> String.downcase(s) |> String.to_atom()
            _ -> nil
          end

        if op_name && ExLisp.Env.has_macro?(op_name) do
          macro_fun = ExLisp.Env.get_macro(op_name)

          expanded =
            if is_function(macro_fun, 2) do
              macro_fun.(args, form)
            else
              macro_fun.(args)
            end

          expanded
        else
          form
        end

      _ ->
        form
    end
  end

  def macroexpand(form, env \\ nil) do
    expanded = macroexpand_1(form, env)

    if expanded == form do
      form
    else
      macroexpand(expanded, env)
    end
  end

  # --- Package operations & module management ---

  def export(_args), do: :t
  def use_package(_args), do: :t
  def shadow(_args), do: :t
  def shadowing_import(_args), do: :t
  def import(_args), do: :t
  def provide(_args), do: :t
  def require(_args), do: :t

  # --- Quicklisp / ASDF ---

  def quickload(args) when is_list(args) do
    case args do
      [system | _] -> ExLisp.Quicklisp.quickload(system)
      system -> ExLisp.Quicklisp.quickload(system)
    end
  end

  def quickload(system), do: ExLisp.Quicklisp.quickload(system)

  def system_apropos(args) when is_list(args) do
    case args do
      [query | _] -> ExLisp.Quicklisp.system_apropos(query)
      query -> ExLisp.Quicklisp.system_apropos(query)
    end
  end

  def system_apropos(query), do: ExLisp.Quicklisp.system_apropos(query)

  def where_is_system(args) when is_list(args) do
    case args do
      [system | _] -> ExLisp.Quicklisp.where_is_system(system)
      system -> ExLisp.Quicklisp.where_is_system(system)
    end
  end

  def where_is_system(system), do: ExLisp.Quicklisp.where_is_system(system)

  # --- Hex.pm ---

  def hex_install(args) when is_list(args) do
    case args do
      [pkg, req | _] when is_binary(req) ->
        ExLisp.Hex.install(pkg, req)

      [pkg, opts | _] when is_list(opts) ->
        ExLisp.Hex.install(pkg, opts)

      [pkg] ->
        ExLisp.Hex.install(pkg)

      packages ->
        ExLisp.Hex.install(packages)
    end
  end

  def hex_install(package), do: ExLisp.Hex.install(package)

  def hex_install(package, req_or_opts), do: ExLisp.Hex.install(package, req_or_opts)

  def hex_search(args) when is_list(args) do
    case args do
      [query | _] -> ExLisp.Hex.search(query)
      query -> ExLisp.Hex.search(query)
    end
  end

  def hex_search(query), do: ExLisp.Hex.search(query)

  def hex_info(args) when is_list(args) do
    case args do
      [package | _] -> ExLisp.Hex.info(package)
      package -> ExLisp.Hex.info(package)
    end
  end

  def hex_info(package), do: ExLisp.Hex.info(package)

  def hex_where_is_package(args) when is_list(args) do
    case args do
      [package | _] -> ExLisp.Hex.where_is_package(package)
      package -> ExLisp.Hex.where_is_package(package)
    end
  end

  def hex_where_is_package(package), do: ExLisp.Hex.where_is_package(package)

  # --- SBCL / System exit ---

  @doc """
  SBCL-compatible quit function.
  Terminates the process with the specified exit code (default: 0).
  Accepts keyword arguments :unix-status or :code, or a single integer.
  """
  def quit(args \\ [])

  def quit(args) when is_list(args) do
    code = parse_quit_code(args)
    System.halt(code)
  end

  def quit(code) when is_integer(code) do
    System.halt(code)
  end

  def quit(_), do: System.halt(0)

  defp parse_quit_code(code) when is_integer(code), do: code
  defp parse_quit_code([]), do: 0
  defp parse_quit_code([code]) when is_integer(code), do: code
  defp parse_quit_code([code | _]) when is_integer(code), do: code

  defp parse_quit_code(args) when is_list(args) do
    opts = parse_lisp_keywords(args)

    cond do
      Keyword.has_key?(opts, :unix_status) ->
        val = Keyword.get(opts, :unix_status)
        if is_integer(val), do: val, else: 0

      Keyword.has_key?(opts, :"unix-status") ->
        val = Keyword.get(opts, :"unix-status")
        if is_integer(val), do: val, else: 0

      Keyword.has_key?(opts, :code) ->
        val = Keyword.get(opts, :code)
        if is_integer(val), do: val, else: 0

      Keyword.has_key?(opts, :status) ->
        val = Keyword.get(opts, :status)
        if is_integer(val), do: val, else: 0

      true ->
        0
    end
  end

  defp parse_quit_code(_), do: 0

  # --- Time functions ---
  def get_internal_real_time do
    :erlang.system_time(:microsecond)
  end

  def get_internal_real_time([]), do: get_internal_real_time()

  def get_internal_run_time do
    :erlang.system_time(:microsecond)
  end

  def get_internal_run_time([]), do: get_internal_run_time()

  def get_universal_time do
    :erlang.system_time(:second) + 719_528 * 86_400
  end

  def get_universal_time([]), do: get_universal_time()
end
