defmodule ExLisp.CLFormat do
  @moduledoc """
  ANSI Common Lisp `format` control string engine for ExLisp.
  Supports:
  - ~A, ~S, ~C, ~W (Aesthetic, Standard, Character, Write)
  - ~D, ~B, ~O, ~X, ~R (Decimal, Binary, Octal, Hex, Radix/English/Roman)
  - ~P (Pluralization: s, ies, with modifiers)
  - ~F, ~E, ~G, ~$ (Floating point, Exponential, Monetary)
  - ~%, ~&, ~|, ~~ (Newlines, Fresh-line, Page, Tilde)
  - ~* (Argument navigation: forward, backward, absolute)
  - ~? (Indirection / nested format)
  - ~[ ... ~] (Conditional selection: index, boolean, truthy)
  - ~{ ... ~} (Iteration: list, sublists, remaining args, max iterations)
  - ~^ (Escape / termination check)
  - ~( ... ~) (Case conversion: downcase, capitalize, upcase)
  """

  @doc """
  Formats arguments according to Common Lisp control string.
  """
  def format(fmt_control, args) do
    fmt_str = to_string(fmt_control)
    arg_list = if is_list(args), do: args, else: [args]
    {res, _rem_args} = format_internal(fmt_str, arg_list, arg_list, %{})
    res
  end

  # Main formatting engine
  # Returns {output_string, remaining_args}
  defp format_internal(fmt_str, args, all_top_args, context \\ %{}) do
    chars = String.to_charlist(fmt_str)
    do_format_chars(chars, args, all_top_args, [], context)
  end

  defp do_format_chars([], args, _all_args, acc, _ctx) do
    {acc |> Enum.reverse() |> List.to_string(), args}
  end

  defp do_format_chars([?~ | rest], args, all_args, acc, ctx) do
    {params, rest_after_params} = parse_directive_params(rest, args)
    {colons, ats, rest_after_mods} = parse_directive_modifiers(rest_after_params)

    case rest_after_mods do
      [] ->
        {acc |> Enum.reverse() |> List.to_string(), args}

      # --- Conditional: ~[ ... ~] ---
      [?[ | after_bracket] ->
        handle_conditional(after_bracket, params, colons, ats, args, all_args, acc, ctx)

      # --- Iteration: ~{ ... ~} ---
      [?{ | after_brace] ->
        handle_iteration(after_brace, params, colons, ats, args, all_args, acc, ctx)

      # --- Case conversion: ~( ... ~) ---
      [?( | after_paren] ->
        handle_case_conversion(after_paren, colons, ats, args, all_args, acc, ctx)

      # --- Escape: ~^ ---
      [?^ | after_caret] ->
        escape_now =
          if colons do
            # ~:^ checks outer remaining items if present
            case Map.get(ctx, :outer_args) do
              nil -> should_escape?(params, args)
              outer -> outer == []
            end
          else
            should_escape?(params, args)
          end

        if escape_now do
          # Stop processing rest of this format segment
          {acc |> Enum.reverse() |> List.to_string(), args}
        else
          do_format_chars(after_caret, args, all_args, acc, ctx)
        end

      # --- Standard directives ---
      [d | after_dir] ->
        dir_char = if d >= ?a and d <= ?z, do: d - 32, else: d
        {out_str, new_args} = execute_directive(dir_char, params, colons, ats, args, all_args, acc)
        new_acc = Enum.reverse(String.to_charlist(out_str)) ++ acc
        do_format_chars(after_dir, new_args, all_args, new_acc, ctx)
    end
  end

  defp do_format_chars([c | rest], args, all_args, acc, ctx) do
    do_format_chars(rest, args, all_args, [c | acc], ctx)
  end

  # --- Directive execution ---

  defp execute_directive(?A, params, colons, _ats, args, _all_args, _acc) do
    {val, rem_args} = pop_arg(args)
    str =
      cond do
        colons and val == nil -> "()"
        is_binary(val) -> val
        is_atom(val) -> val |> Atom.to_string() |> String.upcase()
        is_integer(val) -> "#{val}"
        is_float(val) -> "#{val}"
        true -> lisp_display(val)
      end

    padded = pad_string(str, params)
    {padded, rem_args}
  end

  defp execute_directive(?S, params, colons, _ats, args, _all_args, _acc) do
    {val, rem_args} = pop_arg(args)
    str =
      cond do
        colons and val == nil -> "()"
        true -> lisp_display(val)
      end

    padded = pad_string(str, params)
    {padded, rem_args}
  end

  defp execute_directive(?W, _params, _colons, _ats, args, _all_args, _acc) do
    {val, rem_args} = pop_arg(args)
    {lisp_display(val), rem_args}
  end

  defp execute_directive(?C, _params, colons, ats, args, _all_args, _acc) do
    {val, rem_args} = pop_arg(args)
    char_str =
      case val do
        c when is_integer(c) ->
          cond do
            ats -> "#\\#{char_name(c)}"
            colons -> char_name(c)
            true -> <<c::utf8>>
          end
        <<c::utf8>> ->
          cond do
            ats -> "#\\#{char_name(c)}"
            colons -> char_name(c)
            true -> <<c::utf8>>
          end
        _ ->
          "#{val}"
      end
    {char_str, rem_args}
  end

  defp execute_directive(?D, params, colons, ats, args, _all_args, _acc) do
    {val, rem_args} = pop_arg(args)
    str = format_integer(val, 10, params, colons, ats)
    {str, rem_args}
  end

  defp execute_directive(?B, params, colons, ats, args, _all_args, _acc) do
    {val, rem_args} = pop_arg(args)
    str = format_integer(val, 2, params, colons, ats)
    {str, rem_args}
  end

  defp execute_directive(?O, params, colons, ats, args, _all_args, _acc) do
    {val, rem_args} = pop_arg(args)
    str = format_integer(val, 8, params, colons, ats)
    {str, rem_args}
  end

  defp execute_directive(?X, params, colons, ats, args, _all_args, _acc) do
    {val, rem_args} = pop_arg(args)
    str = format_integer(val, 16, params, colons, ats)
    {str, rem_args}
  end

  defp execute_directive(?R, params, colons, ats, args, _all_args, _acc) do
    {val, rem_args} = pop_arg(args)
    str =
      case params do
        [radix | rest_params] when is_integer(radix) ->
          format_integer(val, radix, rest_params, colons, ats)

        _ ->
          # Word / Roman numeral
          cond do
            ats and colons ->
              # Old Roman numeral
              to_roman_numeral(val, true)
            ats ->
              # Roman numeral
              to_roman_numeral(val, false)
            colons ->
              # Ordinal English word (e.g. fourth)
              to_ordinal_word(val)
            true ->
              # Cardinal English word (e.g. four)
              to_cardinal_word(val)
          end
      end
    {str, rem_args}
  end

  defp execute_directive(?P, _params, colons, ats, args, all_args, _acc) do
    target_val =
      if colons do
        # Look at previous argument
        idx = max(0, length(all_args) - length(args) - 1)
        Enum.at(all_args, idx)
      else
        {v, _} = pop_arg(args)
        v
      end

    rem_args = if colons, do: args, else: tl_or_empty(args)

    plural? = target_val != 1 and target_val != 1.0

    out =
      cond do
        ats and plural? -> "ies"
        ats -> "y"
        plural? -> "s"
        true -> ""
      end

    {out, rem_args}
  end

  defp execute_directive(?F, params, _colons, ats, args, _all_args, _acc) do
    {val, rem_args} = pop_arg(args)
    str = format_float_f(val, params, ats)
    {str, rem_args}
  end

  defp execute_directive(?E, params, _colons, ats, args, _all_args, _acc) do
    {val, rem_args} = pop_arg(args)
    str = format_float_e(val, params, ats)
    {str, rem_args}
  end

  defp execute_directive(?G, params, _colons, ats, args, _all_args, _acc) do
    {val, rem_args} = pop_arg(args)
    str = format_float_g(val, params, ats)
    {str, rem_args}
  end

  defp execute_directive(?$, params, colons, ats, args, _all_args, _acc) do
    {val, rem_args} = pop_arg(args)
    str = format_monetary(val, params, colons, ats)
    {str, rem_args}
  end

  defp execute_directive(?%, params, _colons, _ats, args, _all_args, _acc) do
    n = case params do [count | _] when is_integer(count) and count >= 0 -> count; _ -> 1 end
    {String.duplicate("\n", n), args}
  end

  defp execute_directive(?&, params, _colons, _ats, args, _all_args, acc) do
    n = case params do [count | _] when is_integer(count) and count >= 0 -> count; _ -> 1 end
    if n == 0 do
      {"", args}
    else
      # If start of output or previous char is newline, output n-1 newlines
      at_newline? = acc == [] or hd(acc) == ?\n
      count = if at_newline?, do: n - 1, else: n
      {String.duplicate("\n", max(0, count)), args}
    end
  end

  defp execute_directive(?|, params, _colons, _ats, args, _all_args, _acc) do
    n = case params do [count | _] when is_integer(count) and count >= 0 -> count; _ -> 1 end
    {String.duplicate("\f", n), args}
  end

  defp execute_directive(?~, params, _colons, _ats, args, _all_args, _acc) do
    n = case params do [count | _] when is_integer(count) and count >= 0 -> count; _ -> 1 end
    {String.duplicate("~", n), args}
  end

  defp execute_directive(?*, params, colons, ats, args, all_args, _acc) do
    n = case params do [count | _] when is_integer(count) -> count; _ -> 1 end

    new_args =
      cond do
        ats ->
          # Absolute 0-indexed position in all_args
          Enum.drop(all_args, max(0, n))

        colons ->
          # Backwards n positions
          current_consumed = length(all_args) - length(args)
          new_consumed = max(0, current_consumed - n)
          Enum.drop(all_args, new_consumed)

        true ->
          # Forwards n positions
          Enum.drop(args, max(0, n))
      end

    {"", new_args}
  end

  defp execute_directive(??, _params, _colons, ats, args, all_args, _acc) do
    {fmt_arg, rem1} = pop_arg(args)
    if ats do
      # ~@? takes fmt_control and uses remaining args
      {sub_out, new_args} = format_internal(to_string(fmt_arg), rem1, all_args)
      {sub_out, new_args}
    else
      # ~? takes fmt_control and a list of args
      {sub_args, rem2} = pop_arg(rem1)
      sub_list = if is_list(sub_args), do: sub_args, else: [sub_args]
      {sub_out, _} = format_internal(to_string(fmt_arg), sub_list, sub_list)
      {sub_out, rem2}
    end
  end

  defp execute_directive(?T, params, colons, _ats, args, _all_args, acc) do
    current_col =
      case Enum.find_index(acc, &(&1 == ?\n)) do
        nil -> length(acc)
        idx -> idx
      end

    colnum = case params do [c | _] when is_integer(c) -> c; _ -> 1 end
    colinc = case params do [_, inc | _] when is_integer(inc) and inc > 0 -> inc; _ -> 1 end

    spaces =
      if colons do
        # Relative tab
        k = rem(current_col + colnum, colinc)
        count = if k == 0, do: colnum, else: colnum + (colinc - k)
        String.duplicate(" ", max(1, count))
      else
        if current_col >= colnum do
          k = rem(current_col - colnum, colinc)
          count = if k == 0, do: 0, else: colinc - k
          String.duplicate(" ", count)
        else
          String.duplicate(" ", colnum - current_col)
        end
      end

    {spaces, args}
  end

  defp execute_directive(_other, _params, _colons, _ats, args, _all_args, _acc) do
    {"", args}
  end

  # --- Conditionals (~[ ... ~]) ---

  defp handle_conditional(after_bracket, params, colons, ats, args, all_args, acc, ctx) do
    {clauses, rest_after_close} = extract_matching_clauses(after_bracket, ?[, ?])

    cond do
      colons ->
        # ~:[false-clause~;true-clause~]
        {val, rem_args} = pop_arg(args)
        clause_idx = if val == nil or val == false, do: 0, else: 1
        clause_str = Enum.at(clauses, clause_idx, "")
        {out_str, _} = format_internal(clause_str, rem_args, all_args, ctx)
        new_acc = Enum.reverse(String.to_charlist(out_str)) ++ acc
        do_format_chars(rest_after_close, rem_args, all_args, new_acc, ctx)

      ats ->
        # ~@[true-clause~]
        case args do
          [head | _] when head != nil and head != false ->
            # Truthy: do not consume arg, format clause with current args
            clause_str = hd(clauses)
            {out_str, rem_args} = format_internal(clause_str, args, all_args, ctx)
            new_acc = Enum.reverse(String.to_charlist(out_str)) ++ acc
            do_format_chars(rest_after_close, rem_args, all_args, new_acc, ctx)

          _ ->
            # Falsey / nil: consume arg and do not execute clause
            {_val, rem_args} = pop_arg(args)
            do_format_chars(rest_after_close, rem_args, all_args, acc, ctx)
        end

      true ->
        # ~n[ ... ~] or arg-indexed conditional
        {idx, rem_args} =
          case params do
            [n | _] when is_integer(n) -> {n, args}
            _ -> pop_arg(args)
          end

        clause_str =
          cond do
            is_integer(idx) and idx >= 0 and idx < length(clauses) ->
              Enum.at(clauses, idx)

            true ->
              # Check for default clause (~:; in last clause)
              case List.last(clauses) do
                {:default, def_str} -> def_str
                _ -> ""
              end
          end

        actual_str =
          case clause_str do
            {:default, s} -> s
            s when is_binary(s) -> s
            _ -> ""
          end

        {out_str, _} = format_internal(actual_str, rem_args, all_args, ctx)
        new_acc = Enum.reverse(String.to_charlist(out_str)) ++ acc
        do_format_chars(rest_after_close, rem_args, all_args, new_acc, ctx)
    end
  end

  # --- Iteration (~{ ... ~}) ---

  defp handle_iteration(after_brace, params, colons, ats, args, all_args, acc, ctx) do
    {body_chars, rest_after_close} = extract_matching_body(after_brace, ?{, ?})
    body_str = List.to_string(body_chars)

    max_iter = case params do [n | _] when is_integer(n) -> n; _ -> :infinity end

    {out_str, new_args} =
      cond do
        ats and colons ->
          # ~:@{...~}: iterate over remaining args, each is a sublist
          run_sublist_iteration(body_str, args, max_iter, all_args)

        ats ->
          # ~@{...~}: iterate over remaining args directly
          run_flat_iteration(body_str, args, max_iter, all_args)

        colons ->
          # ~:{...~}: iterate over sublists in a list argument
          {list_arg, rem_args} = pop_arg(args)
          target_list = if is_list(list_arg), do: list_arg, else: []
          {sub_out, _} = run_sublist_iteration(body_str, target_list, max_iter, target_list)
          {sub_out, rem_args}

        true ->
          # ~{...~}: iterate over elements in a list argument
          {list_arg, rem_args} = pop_arg(args)
          target_list = if is_list(list_arg), do: list_arg, else: []
          {sub_out, _} = run_flat_iteration(body_str, target_list, max_iter, target_list)
          {sub_out, rem_args}
      end

    new_acc = Enum.reverse(String.to_charlist(out_str)) ++ acc
    do_format_chars(rest_after_close, new_args, all_args, new_acc, ctx)
  end

  defp run_flat_iteration(body_str, items, max_iter, all_args) do
    do_run_flat_iter(body_str, items, 0, max_iter, all_args, [])
  end

  defp do_run_flat_iter(_body_str, [], _count, _max_iter, _all_args, acc) do
    {acc |> Enum.reverse() |> Enum.join(""), []}
  end

  defp do_run_flat_iter(_body_str, items, count, max_iter, _all_args, acc)
       when max_iter != :infinity and count >= max_iter do
    {acc |> Enum.reverse() |> Enum.join(""), items}
  end

  defp do_run_flat_iter(body_str, items, count, max_iter, all_args, acc) do
    # Format one iteration
    actual_body = if body_str == "", do: to_string(hd(items)), else: body_str
    actual_items = if body_str == "", do: tl(items), else: items

    {sub_out, rem_items} = format_internal(actual_body, actual_items, all_args, %{outer_args: tl_or_empty(items)})

    if rem_items == actual_items do
      # Avoid infinite loop if no items were consumed
      {acc |> Enum.reverse() |> Enum.join(""), rem_items}
    else
      do_run_flat_iter(body_str, rem_items, count + 1, max_iter, all_args, [sub_out | acc])
    end
  end

  defp run_sublist_iteration(body_str, items, max_iter, all_args) do
    do_run_sublist_iter(body_str, items, 0, max_iter, all_args, [])
  end

  defp do_run_sublist_iter(_body_str, [], _count, _max_iter, _all_args, acc) do
    {acc |> Enum.reverse() |> Enum.join(""), []}
  end

  defp do_run_sublist_iter(_body_str, items, count, max_iter, _all_args, acc)
       when max_iter != :infinity and count >= max_iter do
    {acc |> Enum.reverse() |> Enum.join(""), items}
  end

  defp do_run_sublist_iter(body_str, [sub | rest], count, max_iter, all_args, acc) do
    sub_list = if is_list(sub), do: sub, else: [sub]
    {sub_out, _} = format_internal(body_str, sub_list, all_args, %{outer_args: rest})
    do_run_sublist_iter(body_str, rest, count + 1, max_iter, all_args, [sub_out | acc])
  end

  # --- Case conversion (~( ... ~)) ---

  defp handle_case_conversion(after_paren, colons, ats, args, all_args, acc, ctx) do
    {body_chars, rest_after_close} = extract_matching_body(after_paren, ?(, ?))
    body_str = List.to_string(body_chars)

    {out_str, rem_args} = format_internal(body_str, args, all_args, ctx)

    converted =
      cond do
        colons and ats ->
          # ~:@(...~): all upcase
          String.upcase(out_str)

        colons ->
          # ~:(...~): capitalize all words
          String.split(out_str, ~r/\b/) |> Enum.map(&String.capitalize/1) |> Enum.join("")

        ats ->
          # ~@(...~): capitalize first word only
          capitalize_first(out_str)

        true ->
          # ~(...~): all downcase
          String.downcase(out_str)
      end

    new_acc = Enum.reverse(String.to_charlist(converted)) ++ acc
    do_format_chars(rest_after_close, rem_args, all_args, new_acc, ctx)
  end

  defp capitalize_first(""), do: ""
  defp capitalize_first(str) do
    case String.next_grapheme(str) do
      {first, rest} -> String.upcase(first) <> String.downcase(rest)
      nil -> str
    end
  end

  # --- Directive parameter & modifier parsing ---

  defp parse_directive_params(chars, args) do
    parse_params_loop(chars, args, [])
  end

  defp parse_params_loop([], _args, acc), do: {Enum.reverse(acc), []}

  defp parse_params_loop([c | rest], args, acc) when c in [?v, ?V] do
    {val, rem_args} = pop_arg(args)
    next_rest = skip_comma(rest)
    parse_params_loop(next_rest, rem_args, [val | acc])
  end

  defp parse_params_loop([?# | rest], args, acc) do
    count = length(args)
    next_rest = skip_comma(rest)
    parse_params_loop(next_rest, args, [count | acc])
  end

  defp parse_params_loop([c | _rest] = chars, args, acc) when (c >= ?0 and c <= ?9) or c == ?- or c == ?+ or c == ?' do
    case parse_single_param(chars) do
      {:ok, val, remaining} ->
        next_rest = skip_comma(remaining)
        parse_params_loop(next_rest, args, [val | acc])

      :error ->
        {Enum.reverse(acc), chars}
    end
  end

  defp parse_params_loop(chars, _args, acc), do: {Enum.reverse(acc), chars}

  defp parse_single_param([?' , char_val | rest]) do
    {:ok, char_val, rest}
  end

  defp parse_single_param([c | _] = chars) when (c >= ?0 and c <= ?9) or c == ?- or c == ?+ do
    {digits, rest} = Enum.split_while(chars, fn ch -> (ch >= ?0 and ch <= ?9) or ch == ?- or ch == ?+ end)
    str = List.to_string(digits)
    case Integer.parse(str) do
      {num, ""} -> {:ok, num, rest}
      _ -> :error
    end
  end

  defp parse_single_param(_), do: :error

  defp skip_comma([?, | rest]), do: rest
  defp skip_comma(other), do: other

  defp parse_directive_modifiers(chars) do
    parse_mods_loop(chars, false, false)
  end

  defp parse_mods_loop([?: | rest], _colons, ats), do: parse_mods_loop(rest, true, ats)
  defp parse_mods_loop([?@ | rest], colons, _ats), do: parse_mods_loop(rest, colons, true)
  defp parse_mods_loop(rest, colons, ats), do: {colons, ats, rest}

  # --- Delimiter matching helpers ---

  defp extract_matching_clauses(chars, open_char, close_char) do
    do_extract_clauses(chars, open_char, close_char, 0, [], [], false)
  end

  defp do_extract_clauses([], _open, _close, _depth, current, clauses, is_default) do
    raw_str = current |> Enum.reverse() |> List.to_string()
    clause_str = if is_default, do: {:default, raw_str}, else: raw_str
    all = Enum.reverse([clause_str | clauses])
    {all, []}
  end

  defp do_extract_clauses([?~, ?:, ?; | rest], open, close, 0, current, clauses, is_default) do
    raw_str = current |> Enum.reverse() |> List.to_string()
    clause_str = if is_default, do: {:default, raw_str}, else: raw_str
    do_extract_clauses(rest, open, close, 0, [], [clause_str | clauses], true)
  end

  defp do_extract_clauses([?~, ?; | rest], open, close, 0, current, clauses, is_default) do
    raw_str = current |> Enum.reverse() |> List.to_string()
    clause_str = if is_default, do: {:default, raw_str}, else: raw_str
    do_extract_clauses(rest, open, close, 0, [], [clause_str | clauses], is_default)
  end

  defp do_extract_clauses([?~, close | rest], _open, close, 0, current, clauses, is_default) do
    raw_str = current |> Enum.reverse() |> List.to_string()
    clause_str = if is_default, do: {:default, raw_str}, else: raw_str
    all = Enum.reverse([clause_str | clauses])
    {all, rest}
  end

  defp do_extract_clauses([?~, open | rest], open, close, depth, current, clauses, is_default) do
    do_extract_clauses(rest, open, close, depth + 1, [open, ?~ | current], clauses, is_default)
  end

  defp do_extract_clauses([?~, close | rest], open, close, depth, current, clauses, is_default) do
    do_extract_clauses(rest, open, close, depth - 1, [close, ?~ | current], clauses, is_default)
  end

  defp do_extract_clauses([c | rest], open, close, depth, current, clauses, is_default) do
    do_extract_clauses(rest, open, close, depth, [c | current], clauses, is_default)
  end

  defp extract_matching_body(chars, open_char, close_char) do
    do_extract_body(chars, open_char, close_char, 0, [])
  end

  defp do_extract_body([], _open, _close, _depth, acc) do
    {Enum.reverse(acc), []}
  end

  defp do_extract_body([?~, close | rest], _open, close, 0, acc) do
    {Enum.reverse(acc), rest}
  end

  defp do_extract_body([?~, open | rest], open, close, depth, acc) do
    do_extract_body(rest, open, close, depth + 1, [open, ?~ | acc])
  end

  defp do_extract_body([?~, close | rest], open, close, depth, acc) do
    do_extract_body(rest, open, close, depth - 1, [close, ?~ | acc])
  end

  defp do_extract_body([c | rest], open, close, depth, acc) do
    do_extract_body(rest, open, close, depth, [c | acc])
  end

  # --- Integer formatting helper ---

  defp format_integer(val, radix, params, colons, ats) do
    if not is_integer(val) do
      "#{val}"
    else
      raw_str = Integer.to_string(abs(val), radix) |> String.upcase()

      with_commas =
        if colons do
          commachar = case params do [_, _, c | _] when is_integer(c) -> <<c::utf8>>; _ -> "," end
          interval = case params do [_, _, _, inv | _] when is_integer(inv) and inv > 0 -> inv; _ -> 3 end
          insert_commas(raw_str, commachar, interval)
        else
          raw_str
        end

      with_sign =
        cond do
          val < 0 -> "-" <> with_commas
          ats and val >= 0 -> "+" <> with_commas
          true -> with_commas
        end

      mincol = case params do [m | _] when is_integer(m) -> m; _ -> 0 end
      padchar = case params do [_, p | _] when is_integer(p) -> <<p::utf8>>; _ -> " " end

      if String.length(with_sign) < mincol do
        String.duplicate(padchar, mincol - String.length(with_sign)) <> with_sign
      else
        with_sign
      end
    end
  end

  defp insert_commas(str, commachar, interval) do
    str
    |> String.reverse()
    |> Stream.unfold(fn
      "" -> nil
      s -> String.split_at(s, interval)
    end)
    |> Enum.join(commachar)
    |> String.reverse()
  end

  defp pad_string(str, params) do
    mincol = case params do [m | _] when is_integer(m) -> m; _ -> 0 end
    padchar = case params do [_, p | _] when is_integer(p) -> <<p::utf8>>; _ -> " " end

    if String.length(str) < mincol do
      String.duplicate(padchar, mincol - String.length(str)) <> str
    else
      str
    end
  end

  # --- Float formatters ---

  defp format_float_f(val, params, ats) do
    f_val = to_float_val(val)
    d = case params do [_, digits | _] when is_integer(digits) -> digits; _ -> nil end

    str =
      if d != nil do
        :erlang.float_to_binary(f_val, decimals: d)
      else
        "#{f_val}"
      end

    with_sign = if ats and f_val >= 0, do: "+" <> str, else: str
    pad_string(with_sign, params)
  end

  defp format_float_e(val, params, ats) do
    f_val = to_float_val(val)
    str = :erlang.float_to_binary(f_val, [:scientific, decimals: 6])
    with_sign = if ats and f_val >= 0, do: "+" <> str, else: str
    pad_string(with_sign, params)
  end

  defp format_float_g(val, params, ats) do
    f_val = to_float_val(val)
    str = "#{f_val}"
    with_sign = if ats and f_val >= 0, do: "+" <> str, else: str
    pad_string(with_sign, params)
  end

  defp format_monetary(val, params, colons, ats) do
    f_val = to_float_val(val)
    d = case params do [digits | _] when is_integer(digits) -> digits; _ -> 2 end
    str = :erlang.float_to_binary(abs(f_val), decimals: d)

    with_commas =
      if colons do
        [int_part, frac_part] = String.split(str, ".", parts: 2)
        insert_commas(int_part, ",", 3) <> "." <> frac_part
      else
        str
      end

    with_sign =
      cond do
        f_val < 0 -> "-" <> with_commas
        ats and f_val >= 0 -> "+" <> with_commas
        true -> with_commas
      end

    pad_string(with_sign, params)
  end

  defp to_float_val(v) when is_float(v), do: v
  defp to_float_val(v) when is_integer(v), do: v * 1.0
  defp to_float_val(%ExLisp.Ratio{} = r), do: ExLisp.Ratio.to_float(r)
  defp to_float_val(_), do: 0.0

  # --- English words & Roman numerals ---

  defp to_cardinal_word(0), do: "zero"
  defp to_cardinal_word(n) when n < 0, do: "negative " <> to_cardinal_word(-n)
  defp to_cardinal_word(n) when is_integer(n) do
    do_cardinal(n) |> String.trim()
  end
  defp to_cardinal_word(other), do: "#{other}"

  @ones_words %{
    1 => "one", 2 => "two", 3 => "three", 4 => "four", 5 => "five",
    6 => "six", 7 => "seven", 8 => "eight", 9 => "nine", 10 => "ten",
    11 => "eleven", 12 => "twelve", 13 => "thirteen", 14 => "fourteen",
    15 => "fifteen", 16 => "sixteen", 17 => "seventeen", 18 => "eighteen", 19 => "nineteen"
  }

  @tens_words %{
    2 => "twenty", 3 => "thirty", 4 => "forty", 5 => "fifty",
    6 => "sixty", 7 => "seventy", 8 => "eighty", 9 => "ninety"
  }

  defp do_cardinal(n) when n >= 1_000_000_000 do
    b = div(n, 1_000_000_000)
    rem_n = rem(n, 1_000_000_000)
    res = do_cardinal(b) <> " billion"
    if rem_n > 0, do: res <> " " <> do_cardinal(rem_n), else: res
  end

  defp do_cardinal(n) when n >= 1_000_000 do
    m = div(n, 1_000_000)
    rem_n = rem(n, 1_000_000)
    res = do_cardinal(m) <> " million"
    if rem_n > 0, do: res <> " " <> do_cardinal(rem_n), else: res
  end

  defp do_cardinal(n) when n >= 1_000 do
    th = div(n, 1_000)
    rem_n = rem(n, 1_000)
    res = do_cardinal(th) <> " thousand"
    if rem_n > 0, do: res <> " " <> do_cardinal(rem_n), else: res
  end

  defp do_cardinal(n) when n >= 100 do
    h = div(n, 100)
    rem_n = rem(n, 100)
    res = @ones_words[h] <> " hundred"
    if rem_n > 0, do: res <> " " <> do_cardinal(rem_n), else: res
  end

  defp do_cardinal(n) when n >= 20 do
    t = div(n, 10)
    rem_n = rem(n, 10)
    res = @tens_words[t]
    if rem_n > 0, do: res <> "-" <> @ones_words[rem_n], else: res
  end

  defp do_cardinal(n) when n >= 1 do
    @ones_words[n]
  end

  defp do_cardinal(0), do: ""

  @ordinal_exceptions %{
    "one" => "first", "two" => "second", "three" => "third", "four" => "fourth",
    "five" => "fifth", "eight" => "eighth", "nine" => "ninth", "twelve" => "twelfth"
  }

  defp to_ordinal_word(n) when is_integer(n) do
    card = to_cardinal_word(n)
    words = String.split(card, ~r/([\s-])/, include_captures: true)
    {last_word, prefix_words} = List.pop_at(words, -1)

    ord_last =
      case Map.fetch(@ordinal_exceptions, last_word) do
        {:ok, ord} ->
          ord

        :error ->
          cond do
            String.ends_with?(last_word, "y") ->
              String.slice(last_word, 0..-2//1) <> "ieth"

            true ->
              last_word <> "th"
          end
      end

    Enum.join(prefix_words ++ [ord_last], "")
  end
  defp to_ordinal_word(other), do: "#{other}"

  @roman_table [
    {1000, "M"}, {900, "CM"}, {500, "D"}, {400, "CD"},
    {100, "C"}, {90, "XC"}, {50, "L"}, {40, "XL"},
    {10, "X"}, {9, "IX"}, {5, "V"}, {4, "IV"}, {1, "I"}
  ]

  @old_roman_table [
    {1000, "M"}, {500, "D"}, {100, "C"}, {50, "L"},
    {10, "X"}, {5, "V"}, {1, "I"}
  ]

  defp to_roman_numeral(n, old?) when is_integer(n) and n > 0 do
    table = if old?, do: @old_roman_table, else: @roman_table
    do_roman(n, table, "")
  end
  defp to_roman_numeral(n, _), do: "#{n}"

  defp do_roman(0, _table, acc), do: acc
  defp do_roman(_n, [], acc), do: acc
  defp do_roman(n, [{val, str} | rest], acc) do
    if n >= val do
      count = div(n, val)
      rem_n = rem(n, val)
      do_roman(rem_n, rest, acc <> String.duplicate(str, count))
    else
      do_roman(n, rest, acc)
    end
  end

  # --- Helpers ---

  defp should_escape?([], args), do: args == []
  defp should_escape?([p1 | _], _args) when is_integer(p1), do: p1 == 0
  defp should_escape?(_, args), do: args == []

  defp pop_arg([head | tail]), do: {head, tail}
  defp pop_arg([]), do: {nil, []}

  defp tl_or_empty([_ | tail]), do: tail
  defp tl_or_empty([]), do: []

  defp char_name(c) do
    case c do
      ?\s -> "Space"
      ?\n -> "Newline"
      ?\t -> "Tab"
      ?\r -> "Return"
      12 -> "Page"
      8 -> "Backspace"
      _ -> <<c::utf8>>
    end
  end

  defp lisp_display(val) do
    case val do
      nil -> "NIL"
      :t -> "T"
      str when is_binary(str) -> "\"#{str}\""
      _ -> inspect(ExLisp.to_repl_display(val))
    end
  end
end
