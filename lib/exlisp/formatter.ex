defmodule ExLisp.Formatter do
  @moduledoc """
  Code formatter for Common Lisp.

  Based on CST (Concrete Syntax Tree), handles indentation, parenthesis placement,
  and comment preservation according to standard Common Lisp conventions.

  ## Features
  1. **Parenthesis placement**: Does not place closing `)` on separate lines, collecting them at line ends.
  2. **Standard indentation**:
     - Body of definition forms like `defun`, `defmacro`, `defmethod`: 2 spaces
     - Binding forms like `let`, `let*`, `flet`, `labels`: binding part and 2-space body
     - Control structures like `if`, `when`, `unless`, `cond`, `case`: appropriate indentation
     - Blocks like `with-*`, `dolist`, `dotimes`, `loop`, `progn`: 2 spaces
     - General function calls: aligned with first argument or 2 spaces
  3. **Preserving comments and blank lines**:
     - Preserves positions of `;;;;`, `;;;`, `;;`, `;` and inline comments.
     - Preserves intentional blank lines (compresses consecutive blank lines to one).
  """

  @default_max_width 80
  @default_indent 2

  @type format_opts :: [
          max_width: pos_integer(),
          indent: pos_integer()
        ]

  @doc """
  Formats and returns a Lisp code string.
  """
  @spec format(String.t(), format_opts()) :: String.t()
  def format(input, opts \\ []) when is_binary(input) do
    case tokenize(input) do
      {:ok, tokens} ->
        case parse_cst(tokens) do
          {:ok, cst_nodes} ->
            render_cst(cst_nodes, opts)

          {:error, _reason} ->
            # Return original input if parsing fails (safe fallback)
            input
        end

      {:error, _reason} ->
        input
    end
  end

  @doc """
  Reads a Lisp file, writes back formatted content, or returns as a string.
  """
  @spec format_file(Path.t(), keyword()) :: {:ok, String.t()} | {:error, term()}
  def format_file(path, opts \\ []) do
    case File.read(path) do
      {:ok, content} ->
        formatted = format(content, opts)

        if Keyword.get(opts, :in_place, false) or Keyword.get(opts, :write, false) do
          case File.write(path, formatted) do
            :ok -> {:ok, formatted}
            {:error, reason} -> {:error, reason}
          end
        else
          {:ok, formatted}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  # =========================================================================
  # 1. Lexical Analysis (Tokenizer)
  # =========================================================================

  @doc """
  Splits source code into a token stream for CST generation.
  """
  def tokenize(input) when is_binary(input) do
    tokenize_chars(String.to_charlist(input), 1, 1, false, [])
  end

  defp tokenize_chars([], _line, _col, _line_has_tokens, acc) do
    {:ok, Enum.reverse(acc)}
  end

  # Handling newlines
  defp tokenize_chars([?\n | rest], line, _col, _line_has_tokens, acc) do
    # Count consecutive newlines
    {consecutive_newlines, remaining} = count_newlines(rest, 1)
    new_acc = [{:newline, line, consecutive_newlines} | acc]
    tokenize_chars(remaining, line + consecutive_newlines, 1, false, new_acc)
  end

  defp tokenize_chars([?\r, ?\n | rest], line, _col, _line_has_tokens, acc) do
    {consecutive_newlines, remaining} = count_newlines(rest, 1)
    new_acc = [{:newline, line, consecutive_newlines} | acc]
    tokenize_chars(remaining, line + consecutive_newlines, 1, false, new_acc)
  end

  # Whitespace (space, tab)
  defp tokenize_chars([c | rest], line, col, line_has_tokens, acc) when c in [?\s, ?\t, ?\r] do
    tokenize_chars(rest, line, col + 1, line_has_tokens, acc)
  end

  # Comments (; to end of line)
  defp tokenize_chars([?; | rest], line, col, line_has_tokens, acc) do
    {comment_chars, remaining} = read_until_newline(rest, [?;])
    comment_text = List.to_string(comment_chars)
    type = if line_has_tokens, do: :inline, else: :standalone
    tok = {:comment, line, col, comment_text, type}

    tokenize_chars(remaining, line, col + String.length(comment_text), line_has_tokens, [
      tok | acc
    ])
  end

  # String literal ("...")
  defp tokenize_chars([?\" | rest], line, col, _line_has_tokens, acc) do
    case read_string_literal(rest, [?\"], line) do
      {:ok, str_chars, remaining, lines_consumed} ->
        raw_str = List.to_string(str_chars)
        tok = {:string, line, col, raw_str}

        tokenize_chars(
          remaining,
          line + lines_consumed,
          col + String.length(raw_str),
          true,
          [tok | acc]
        )

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Function quote (#'form)
  defp tokenize_chars([?#, ?' | rest], line, col, _line_has_tokens, acc) do
    tok = {:prefix, line, col, "#'"}
    tokenize_chars(rest, line, col + 2, true, [tok | acc])
  end

  # Vector start (#(...)
  defp tokenize_chars([?#, ?( | rest], line, col, _line_has_tokens, acc) do
    tok = {:open, line, col, "#(", ")"}
    tokenize_chars(rest, line, col + 2, true, [tok | acc])
  end

  # Character literal (#\...)
  defp tokenize_chars([?#, ?\\ | rest], line, col, _line_has_tokens, acc) do
    {char_tok_str, remaining} = read_char_literal_token(rest)
    tok = {:atom, line, col, "#\\" <> char_tok_str}

    tokenize_chars(
      remaining,
      line,
      col + 2 + String.length(char_tok_str),
      true,
      [tok | acc]
    )
  end

  # Quote ('form)
  defp tokenize_chars([?' | rest], line, col, _line_has_tokens, acc) do
    tok = {:prefix, line, col, "'"}
    tokenize_chars(rest, line, col + 1, true, [tok | acc])
  end

  # Backquote (`form)
  defp tokenize_chars([?` | rest], line, col, _line_has_tokens, acc) do
    tok = {:prefix, line, col, "`"}
    tokenize_chars(rest, line, col + 1, true, [tok | acc])
  end

  # Comma-at (,@form)
  defp tokenize_chars([?,, ?@ | rest], line, col, _line_has_tokens, acc) do
    tok = {:prefix, line, col, ",@"}
    tokenize_chars(rest, line, col + 2, true, [tok | acc])
  end

  # Comma (,form)
  defp tokenize_chars([?, | rest], line, col, _line_has_tokens, acc) do
    tok = {:prefix, line, col, ","}
    tokenize_chars(rest, line, col + 1, true, [tok | acc])
  end

  # Opening delimiters
  defp tokenize_chars([?( | rest], line, col, _line_has_tokens, acc) do
    tok = {:open, line, col, "(", ")"}
    tokenize_chars(rest, line, col + 1, true, [tok | acc])
  end

  defp tokenize_chars([?[ | rest], line, col, _line_has_tokens, acc) do
    tok = {:open, line, col, "[", "]"}
    tokenize_chars(rest, line, col + 1, true, [tok | acc])
  end

  defp tokenize_chars([?{ | rest], line, col, _line_has_tokens, acc) do
    tok = {:open, line, col, "{", "}"}
    tokenize_chars(rest, line, col + 1, true, [tok | acc])
  end

  # Closing delimiters
  defp tokenize_chars([?) | rest], line, col, _line_has_tokens, acc) do
    tok = {:close, line, col, ")"}
    tokenize_chars(rest, line, col + 1, true, [tok | acc])
  end

  defp tokenize_chars([?] | rest], line, col, _line_has_tokens, acc) do
    tok = {:close, line, col, "]"}
    tokenize_chars(rest, line, col + 1, true, [tok | acc])
  end

  defp tokenize_chars([?} | rest], line, col, _line_has_tokens, acc) do
    tok = {:close, line, col, "}"}
    tokenize_chars(rest, line, col + 1, true, [tok | acc])
  end

  # Other tokens (symbol, number, keyword, etc.)
  defp tokenize_chars(chars, line, col, _line_has_tokens, acc) do
    {tok_chars, remaining} = read_atom_chars(chars, [])
    tok_str = List.to_string(tok_chars)
    tok = {:atom, line, col, tok_str}
    tokenize_chars(remaining, line, col + String.length(tok_str), true, [tok | acc])
  end

  defp count_newlines([?\n | rest], count), do: count_newlines(rest, count + 1)
  defp count_newlines([?\r, ?\n | rest], count), do: count_newlines(rest, count + 1)
  defp count_newlines(rest, count), do: {count, rest}

  defp read_until_newline([], acc), do: {Enum.reverse(acc), []}
  defp read_until_newline([?\n | _] = rest, acc), do: {Enum.reverse(acc), rest}
  defp read_until_newline([?\r, ?\n | _] = rest, acc), do: {Enum.reverse(acc), rest}
  defp read_until_newline([c | rest], acc), do: read_until_newline(rest, [c | acc])

  defp read_string_literal([], _acc, line) do
    {:error, "unclosed string literal at line #{line}"}
  end

  defp read_string_literal([?\\, c | rest], acc, line) do
    read_string_literal(rest, [c, ?\\ | acc], line)
  end

  defp read_string_literal([?\" | rest], acc, _line) do
    {:ok, Enum.reverse([?\" | acc]), rest, 0}
  end

  defp read_string_literal([?\n | rest], acc, line) do
    case read_string_literal(rest, [?\n | acc], line + 1) do
      {:ok, full_acc, rem, lines} -> {:ok, full_acc, rem, lines + 1}
      err -> err
    end
  end

  defp read_string_literal([c | rest], acc, line) do
    read_string_literal(rest, [c | acc], line)
  end

  defp read_char_literal_token([]) do
    {"", []}
  end

  defp read_char_literal_token([c | rest])
       when c in [?(, ?), ?[, ?], ?{, ?}, ?\", ?;, ?\s, ?\t, ?\n, ?\r, ?', ?`, ?,] do
    # Single character literal symbol (e.g. #\(, #\))
    {<<c::utf8>>, rest}
  end

  defp read_char_literal_token(chars) do
    read_atom_chars(chars, [])
    |> then(fn {c_list, rem} -> {List.to_string(c_list), rem} end)
  end

  defp read_atom_chars([], acc), do: {Enum.reverse(acc), []}

  defp read_atom_chars([c | _] = chars, acc)
       when c in [?\s, ?\t, ?\n, ?\r, ?(, ?), ?[, ?], ?{, ?}, ?\", ?;, ?', ?`, ?,] do
    {Enum.reverse(acc), chars}
  end

  defp read_atom_chars([c | rest], acc), do: read_atom_chars(rest, [c | acc])

  # =========================================================================
  # 2. CST Parsing
  # =========================================================================

  @doc """
  Generates a Concrete Syntax Tree (CST) from a token stream.
  """
  def parse_cst(tokens) do
    parse_items(tokens, [])
  end

  defp parse_items([], acc) do
    {:ok, Enum.reverse(acc)}
  end

  defp parse_items([{:newline, _line, count} | rest], acc) do
    if count >= 2 do
      parse_items(rest, [{:blank_line} | acc])
    else
      parse_items(rest, acc)
    end
  end

  defp parse_items([{:comment, _l, _c, text, type} | rest], acc) do
    parse_items(rest, [{:comment, text, type} | acc])
  end

  defp parse_items([{:open, _l, _c, open_str, close_str} | rest], acc) do
    case parse_list_items(rest, close_str, [], false) do
      {:ok, inner_items, remaining, has_newlines} ->
        list_node = {:list, open_str, close_str, inner_items, has_newlines}
        parse_items(remaining, [list_node | acc])

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp parse_items([{:prefix, _l, _c, prefix_str} | rest], acc) do
    case parse_single_item(rest) do
      {:ok, inner_node, remaining} ->
        prefix_node = {:prefix, prefix_str, inner_node}
        parse_items(remaining, [prefix_node | acc])

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp parse_items([{:string, _l, _c, raw_str} | rest], acc) do
    parse_items(rest, [{:string, raw_str} | acc])
  end

  defp parse_items([{:atom, _l, _c, text} | rest], acc) do
    parse_items(rest, [{:atom, text} | acc])
  end

  defp parse_items([{:close, _l, _c, unexpected} | _rest], _acc) do
    {:error, "unexpected closing delimiter #{unexpected}"}
  end

  # Get single CST element
  defp parse_single_item([]) do
    {:error, "unexpected EOF after prefix"}
  end

  defp parse_single_item([{:newline, _, _} | rest]) do
    parse_single_item(rest)
  end

  defp parse_single_item([{:comment, _, _, text, type} | rest]) do
    # Skip comments while searching for elements
    case parse_single_item(rest) do
      {:ok, node, rem} -> {:ok, node, [{:comment, text, type} | rem]}
      err -> err
    end
  end

  defp parse_single_item([{:open, _l, _c, open_str, close_str} | rest]) do
    case parse_list_items(rest, close_str, [], false) do
      {:ok, inner_items, remaining, has_newlines} ->
        {:ok, {:list, open_str, close_str, inner_items, has_newlines}, remaining}

      err ->
        err
    end
  end

  defp parse_single_item([{:prefix, _l, _c, prefix_str} | rest]) do
    case parse_single_item(rest) do
      {:ok, inner_node, remaining} ->
        {:ok, {:prefix, prefix_str, inner_node}, remaining}

      err ->
        err
    end
  end

  defp parse_single_item([{:string, _l, _c, raw_str} | rest]) do
    {:ok, {:string, raw_str}, rest}
  end

  defp parse_single_item([{:atom, _l, _c, text} | rest]) do
    {:ok, {:atom, text}, rest}
  end

  defp parse_single_item([{:close, _l, _c, unexpected} | _rest]) do
    {:error, "unexpected delimiter #{unexpected}"}
  end

  # Parse list internals
  defp parse_list_items([], expected_close, _acc, _has_nl) do
    {:error, "unclosed list, expected #{expected_close}"}
  end

  defp parse_list_items([{:close, _l, _c, close_str} | rest], expected_close, acc, has_nl)
       when close_str == expected_close do
    {:ok, Enum.reverse(acc), rest, has_nl}
  end

  defp parse_list_items([{:newline, _l, count} | rest], expected_close, acc, _has_nl) do
    if count >= 2 do
      parse_list_items(rest, expected_close, [{:blank_line} | acc], true)
    else
      parse_list_items(rest, expected_close, acc, true)
    end
  end

  defp parse_list_items([{:comment, _l, _c, text, type} | rest], expected_close, acc, has_nl) do
    parse_list_items(rest, expected_close, [{:comment, text, type} | acc], has_nl)
  end

  defp parse_list_items(
         [{:open, _l, _c, open_str, inner_close} | rest],
         expected_close,
         acc,
         has_nl
       ) do
    case parse_list_items(rest, inner_close, [], false) do
      {:ok, inner_items, remaining, inner_has_nl} ->
        list_node = {:list, open_str, inner_close, inner_items, inner_has_nl}
        parse_list_items(remaining, expected_close, [list_node | acc], has_nl)

      err ->
        err
    end
  end

  defp parse_list_items([{:prefix, _l, _c, prefix_str} | rest], expected_close, acc, has_nl) do
    case parse_single_item(rest) do
      {:ok, inner_node, remaining} ->
        prefix_node = {:prefix, prefix_str, inner_node}
        parse_list_items(remaining, expected_close, [prefix_node | acc], has_nl)

      err ->
        err
    end
  end

  defp parse_list_items([{:string, _l, _c, raw_str} | rest], expected_close, acc, has_nl) do
    parse_list_items(rest, expected_close, [{:string, raw_str} | acc], has_nl)
  end

  defp parse_list_items([{:atom, _l, _c, text} | rest], expected_close, acc, has_nl) do
    parse_list_items(rest, expected_close, [{:atom, text} | acc], has_nl)
  end

  # =========================================================================
  # 3. CST Rendering (Formatter & Pretty-Printer)
  # =========================================================================

  defp render_cst(nodes, opts) do
    max_width = Keyword.get(opts, :max_width, @default_max_width)
    indent_step = Keyword.get(opts, :indent, @default_indent)
    config = %{max_width: max_width, indent_step: indent_step}

    lines = render_top_level_nodes(nodes, config)
    Enum.join(lines, "\n") <> "\n"
  end

  defp render_top_level_nodes(nodes, config) do
    Enum.reduce(nodes, [], fn node, acc ->
      case node do
        {:blank_line} ->
          # Compress consecutive blank lines to one
          case acc do
            ["" | _] -> acc
            [] -> acc
            _ -> ["" | acc]
          end

        {:comment, text, :standalone} ->
          [text | acc]

        _ ->
          rendered_lines = format_node_lines(node, 0, config)
          Enum.reverse(rendered_lines) ++ acc
      end
    end)
    |> Enum.reverse()
    |> trim_trailing_blank_lines()
  end

  defp trim_trailing_blank_lines([]), do: []

  defp trim_trailing_blank_lines(lines) do
    lines
    |> Enum.reverse()
    |> Enum.drop_while(&(&1 == ""))
    |> Enum.reverse()
  end

  # Format node as list of lines
  defp format_node_lines(node, indent, config) do
    # Check if fits on a single line
    case single_line_format(node) do
      {:ok, single_str} ->
        if indent + String.length(single_str) <= config.max_width do
          [indent_str(indent) <> single_str]
        else
          multiline_format(node, indent, config)
        end

      :multiline ->
        multiline_format(node, indent, config)
    end
  end

  # Check if single line representation is possible
  defp single_line_format(node) do
    case node do
      {:atom, text} ->
        {:ok, text}

      {:string, text} ->
        if String.contains?(text, "\n"), do: :multiline, else: {:ok, text}

      {:prefix, prefix_str, inner} ->
        case single_line_format(inner) do
          {:ok, inner_str} -> {:ok, prefix_str <> inner_str}
          :multiline -> :multiline
        end

      {:list, open_str, close_str, items, has_nl} ->
        # Treat as multiline if comments or blank lines are present
        has_special =
          Enum.any?(items, fn
            {:blank_line} -> true
            {:comment, _, _} -> true
            _ -> false
          end)

        if has_special do
          :multiline
        else
          # Expand to multiline if function definition has body, or if block structure / multiple lists contained newlines
          should_break_block =
            is_function_definition_with_body?(items) or
              (has_nl and should_break_multiline?(items))

          if should_break_block do
            :multiline
          else
            results =
              Enum.reduce_while(items, [], fn item, acc ->
                case single_line_format(item) do
                  {:ok, s} -> {:cont, [s | acc]}
                  :multiline -> {:halt, :multiline}
                end
              end)

            case results do
              :multiline ->
                :multiline

              list when is_list(list) ->
                joined = list |> Enum.reverse() |> Enum.join(" ")
                {:ok, open_str <> joined <> close_str}
            end
          end
        end

      _ ->
        :multiline
    end
  end

  defp is_function_definition_with_body?(items) do
    code_items = extract_code_items(items)

    case code_items do
      [{:atom, name}, _name_item, _params_item, _first_body | _rest] ->
        determine_indent_rule(String.downcase(name)) == :defun

      _ ->
        false
    end
  end

  defp should_break_multiline?(items) do
    is_block_structure?(items) or contains_multiple_lists?(items)
  end

  defp contains_multiple_lists?(items) do
    code_items = extract_code_items(items)

    length(code_items) > 1 and
      Enum.all?(code_items, fn
        {:list, _, _, _, _} -> true
        _ -> false
      end)
  end

  # Check if block/control structure
  defp is_block_structure?(items) do
    first_code =
      Enum.find(items, fn
        {:comment, _, _} -> false
        {:blank_line} -> false
        _ -> true
      end)

    case first_code do
      {:atom, name} ->
        determine_indent_rule(String.downcase(name)) in [
          :defun,
          :defvar,
          :let,
          :if,
          :when,
          :cond,
          :case,
          :progn,
          :dolist,
          :with_macro,
          :binding_macro,
          :lambda
        ]

      _ ->
        false
    end
  end

  # Multiline format
  defp multiline_format({:atom, text}, indent, _config) do
    [indent_str(indent) <> text]
  end

  defp multiline_format({:string, text}, indent, _config) do
    lines = String.split(text, "\n")

    case lines do
      [single] ->
        [indent_str(indent) <> single]

      [first | rest] ->
        [indent_str(indent) <> first | rest]
    end
  end

  defp multiline_format({:prefix, prefix_str, inner}, indent, config) do
    inner_lines = format_node_lines(inner, indent + String.length(prefix_str), config)

    case inner_lines do
      [first | rest] ->
        trimmed_first = String.trim_leading(first)
        [indent_str(indent) <> prefix_str <> trimmed_first | rest]

      [] ->
        [indent_str(indent) <> prefix_str]
    end
  end

  defp multiline_format({:list, open_str, close_str, items, _has_nl}, indent, config) do
    format_list_multiline(open_str, close_str, items, indent, config)
  end

  defp multiline_format({:comment, text, :standalone}, indent, _config) do
    cond do
      String.starts_with?(text, ";;;;") -> [text]
      String.starts_with?(text, ";;;") and indent == 0 -> [text]
      true -> [indent_str(indent) <> text]
    end
  end

  defp multiline_format({:comment, text, :inline}, _indent, _config) do
    ["  " <> text]
  end

  defp multiline_format({:blank_line}, _indent, _config) do
    [""]
  end

  # =========================================================================
  # 4. Multiline list formatting and indentation rules
  # =========================================================================

  defp format_list_multiline(open_str, close_str, items, indent, config) do
    # Empty list
    if items == [] do
      [indent_str(indent) <> open_str <> close_str]
    else
      # Get first code element (non-comment)
      first_code_idx =
        Enum.find_index(items, fn
          {:comment, _, _} -> false
          {:blank_line} -> false
          _ -> true
        end)

      if first_code_idx == nil do
        # Comment-only list
        format_items_block(items, indent + config.indent_step, open_str, close_str, config)
      else
        first_item = Enum.at(items, first_code_idx)

        case first_item do
          {:atom, name} ->
            op = String.downcase(name)
            rule = determine_indent_rule(op)
            format_list_by_rule(rule, open_str, close_str, items, indent, config)

          _ ->
            # When first element is a list or vector (data list, etc.)
            format_generic_list(open_str, close_str, items, indent, config)
        end
      end
    end
  end

  # Determine indentation rule
  defp determine_indent_rule(op) do
    cond do
      op in [
        "defun",
        "defmacro",
        "defmethod",
        "defgeneric",
        "define-compiler-macro",
        "define-modify-macro",
        "define-setf-expander",
        "defsetf"
      ] ->
        :defun

      op in [
        "defvar",
        "defparameter",
        "defconstant",
        "defstruct",
        "deftype",
        "defclass"
      ] ->
        :defvar

      op in [
        "let",
        "let*",
        "flet",
        "labels",
        "macrolet",
        "symbol-macrolet"
      ] ->
        :let

      op == "if" ->
        :if

      op in ["when", "unless"] ->
        :when

      op == "cond" ->
        :cond

      op in ["case", "ecase", "ccase", "typecase", "etypecase", "ctypecase"] ->
        :case

      op in [
        "progn",
        "block",
        "locally",
        "tagbody",
        "catch",
        "unwind-protect",
        "prog1",
        "prog2",
        "eval-when"
      ] ->
        :progn

      op in ["dolist", "dotimes", "do", "do*"] ->
        :dolist

      op in ["destructuring-bind", "multiple-value-bind", "multiple-value-setq"] ->
        :binding_macro

      op == "loop" ->
        :loop

      op == "lambda" ->
        :lambda

      String.starts_with?(op, "with-") ->
        :with_macro

      true ->
        :function_call
    end
  end

  # --- Rule-specific formatters ---

  # 1. defun family: (defun name (params...) ...body)
  defp format_list_by_rule(:defun, open_str, close_str, items, indent, config) do
    code_items = extract_code_items(items)

    case code_items do
      [op_item, name_item, params_item | body_items] ->
        op_str = render_simple(op_item)
        name_str = render_simple(name_item)

        # Check if parameter list fits on a single line
        case single_line_format(params_item) do
          {:ok, params_str} ->
            header = "#{open_str}#{op_str} #{name_str} #{params_str}"
            body_indent = indent + config.indent_step

            # Format remaining body items
            all_remaining = drop_until_after(items, params_item)

            render_header_and_body(
              header,
              all_remaining,
              body_items,
              indent,
              body_indent,
              close_str,
              config
            )

          :multiline ->
            # When parameters span multiple lines
            header = "#{open_str}#{op_str} #{name_str}"
            params_lines = format_node_lines(params_item, indent + 4, config)
            body_indent = indent + config.indent_step
            all_remaining = drop_until_after(items, params_item)
            body_lines = format_body_items(all_remaining, body_indent, config)

            combine_lines_with_close(
              [indent_str(indent) <> header | params_lines] ++ body_lines,
              close_str
            )
        end

      _ ->
        format_generic_list(open_str, close_str, items, indent, config)
    end
  end

  # 2. defvar / defparameter family
  defp format_list_by_rule(:defvar, open_str, close_str, items, indent, config) do
    code_items = extract_code_items(items)

    case code_items do
      [op_item, name_item | rest_items] ->
        op_str = render_simple(op_item)
        name_str = render_simple(name_item)
        header = "#{open_str}#{op_str} #{name_str}"
        body_indent = indent + config.indent_step
        all_remaining = drop_until_after(items, name_item)

        render_header_and_body(
          header,
          all_remaining,
          rest_items,
          indent,
          body_indent,
          close_str,
          config
        )

      _ ->
        format_generic_list(open_str, close_str, items, indent, config)
    end
  end

  # 3. let family: (let ((x 1) (y 2)) ...body)
  defp format_list_by_rule(:let, open_str, close_str, items, indent, config) do
    code_items = extract_code_items(items)

    case code_items do
      [op_item, bindings_item | body_items] ->
        op_str = render_simple(op_item)
        body_indent = indent + config.indent_step
        all_remaining = drop_until_after(items, bindings_item)

        case bindings_item do
          {:list, b_open, b_close, b_sub_items, _} ->
            case single_line_format(bindings_item) do
              {:ok, b_str} ->
                # When bindings fit on a single line
                header = "#{open_str}#{op_str} #{b_str}"

                render_header_and_body(
                  header,
                  all_remaining,
                  body_items,
                  indent,
                  body_indent,
                  close_str,
                  config
                )

              :multiline ->
                # Align bindings across multiple lines
                # (let ((a 1)
                #       (b 2))
                #   body)
                header_prefix = "#{open_str}#{op_str} #{b_open}"
                b_indent = indent + String.length(header_prefix)

                b_lines =
                  format_binding_sub_items(b_sub_items, b_indent, header_prefix, b_close, config)

                # Add indentation to first line
                full_b_lines =
                  case b_lines do
                    [first | rest] -> [indent_str(indent) <> first | rest]
                    [] -> [indent_str(indent) <> header_prefix <> b_close]
                  end

                body_lines = format_body_items(all_remaining, body_indent, config)
                combine_lines_with_close(full_b_lines ++ body_lines, close_str)
            end

          _ ->
            header = "#{open_str}#{op_str} #{render_simple(bindings_item)}"

            render_header_and_body(
              header,
              all_remaining,
              body_items,
              indent,
              body_indent,
              close_str,
              config
            )
        end

      _ ->
        format_generic_list(open_str, close_str, items, indent, config)
    end
  end

  # 4. if: (if test then else)
  defp format_list_by_rule(:if, open_str, close_str, items, indent, config) do
    code_items = extract_code_items(items)

    case code_items do
      [op_item, test_item | branches] ->
        op_str = render_simple(op_item)

        case single_line_format(test_item) do
          {:ok, test_str} ->
            header = "#{open_str}#{op_str} #{test_str}"
            # Align if then/else to (if (indent + 4)
            branch_indent = indent + String.length(open_str <> op_str <> " ")
            all_remaining = drop_until_after(items, test_item)

            render_header_and_body(
              header,
              all_remaining,
              branches,
              indent,
              branch_indent,
              close_str,
              config
            )

          :multiline ->
            header = "#{open_str}#{op_str}"
            test_lines = format_node_lines(test_item, indent + 4, config)
            all_remaining = drop_until_after(items, test_item)
            branch_lines = format_body_items(all_remaining, indent + 2, config)

            combine_lines_with_close(
              [indent_str(indent) <> header | test_lines] ++ branch_lines,
              close_str
            )
        end

      _ ->
        format_generic_list(open_str, close_str, items, indent, config)
    end
  end

  # 5. when / unless / lambda / with-*
  defp format_list_by_rule(rule, open_str, close_str, items, indent, config)
       when rule in [:when, :lambda, :with_macro, :dolist, :binding_macro] do
    code_items = extract_code_items(items)

    case code_items do
      [op_item, arg1_item | body_items] ->
        op_str = render_simple(op_item)
        body_indent = indent + config.indent_step

        case single_line_format(arg1_item) do
          {:ok, arg1_str} ->
            header = "#{open_str}#{op_str} #{arg1_str}"
            all_remaining = drop_until_after(items, arg1_item)

            render_header_and_body(
              header,
              all_remaining,
              body_items,
              indent,
              body_indent,
              close_str,
              config
            )

          :multiline ->
            header = "#{open_str}#{op_str}"
            arg1_lines = format_node_lines(arg1_item, indent + 4, config)
            all_remaining = drop_until_after(items, arg1_item)
            body_lines = format_body_items(all_remaining, body_indent, config)

            combine_lines_with_close(
              [indent_str(indent) <> header | arg1_lines] ++ body_lines,
              close_str
            )
        end

      _ ->
        format_generic_list(open_str, close_str, items, indent, config)
    end
  end

  # 6. cond: (cond ((test1) (act1)) ((test2) (act2)))
  defp format_list_by_rule(:cond, open_str, close_str, items, indent, config) do
    code_items = extract_code_items(items)

    case code_items do
      [op_item | _clauses] ->
        op_str = render_simple(op_item)
        header = "#{open_str}#{op_str}"
        clause_indent = indent + config.indent_step
        all_remaining = drop_until_after(items, op_item)

        clause_lines =
          Enum.reduce(all_remaining, [], fn item, acc ->
            case item do
              {:blank_line} ->
                case acc do
                  ["" | _] -> acc
                  _ -> ["" | acc]
                end

              {:comment, text, :standalone} ->
                [indent_str(clause_indent) <> text | acc]

              {:comment, text, :inline} ->
                case acc do
                  [prev | rest] -> ["#{prev}  #{text}" | rest]
                  [] -> [indent_str(clause_indent) <> text]
                end

              {:list, c_open, c_close, c_items, c_nl} ->
                c_lines = format_clause(c_open, c_close, c_items, c_nl, clause_indent, config)
                Enum.reverse(c_lines) ++ acc

              other ->
                c_lines = format_node_lines(other, clause_indent, config)
                Enum.reverse(c_lines) ++ acc
            end
          end)
          |> Enum.reverse()

        first_line = indent_str(indent) <> header
        combine_lines_with_close([first_line | clause_lines], close_str)

      _ ->
        format_generic_list(open_str, close_str, items, indent, config)
    end
  end

  # 7. case: (case keyform (v1 ...) (v2 ...))
  defp format_list_by_rule(:case, open_str, close_str, items, indent, config) do
    code_items = extract_code_items(items)

    case code_items do
      [op_item, keyform_item | _clauses] ->
        op_str = render_simple(op_item)
        clause_indent = indent + config.indent_step
        all_remaining = drop_until_after(items, keyform_item)

        clause_lines =
          Enum.reduce(all_remaining, [], fn item, acc ->
            case item do
              {:blank_line} ->
                case acc do
                  ["" | _] -> acc
                  _ -> ["" | acc]
                end

              {:comment, text, :standalone} ->
                [indent_str(clause_indent) <> text | acc]

              {:comment, text, :inline} ->
                case acc do
                  [prev | rest] -> ["#{prev}  #{text}" | rest]
                  [] -> [indent_str(clause_indent) <> text]
                end

              {:list, c_open, c_close, c_items, c_nl} ->
                c_lines = format_clause(c_open, c_close, c_items, c_nl, clause_indent, config)
                Enum.reverse(c_lines) ++ acc

              other ->
                c_lines = format_node_lines(other, clause_indent, config)
                Enum.reverse(c_lines) ++ acc
            end
          end)
          |> Enum.reverse()

        case single_line_format(keyform_item) do
          {:ok, k_str} ->
            first_line = indent_str(indent) <> "#{open_str}#{op_str} #{k_str}"
            combine_lines_with_close([first_line | clause_lines], close_str)

          :multiline ->
            header = "#{open_str}#{op_str}"
            k_lines = format_node_lines(keyform_item, indent + 4, config)

            combine_lines_with_close(
              [indent_str(indent) <> header | k_lines] ++ clause_lines,
              close_str
            )
        end

      _ ->
        format_generic_list(open_str, close_str, items, indent, config)
    end
  end

  # 8. progn / loop
  defp format_list_by_rule(rule, open_str, close_str, items, indent, config)
       when rule in [:progn, :loop] do
    code_items = extract_code_items(items)

    case code_items do
      [op_item | body_items] ->
        op_str = render_simple(op_item)
        header = "#{open_str}#{op_str}"
        body_indent = indent + config.indent_step
        all_remaining = drop_until_after(items, op_item)

        render_header_and_body(
          header,
          all_remaining,
          body_items,
          indent,
          body_indent,
          close_str,
          config
        )

      _ ->
        format_generic_list(open_str, close_str, items, indent, config)
    end
  end

  # 9. General function call: (func arg1 arg2 ...)
  defp format_list_by_rule(:function_call, open_str, close_str, items, indent, config) do
    code_items = extract_code_items(items)

    case code_items do
      [func_item, arg1_item | rest_args] ->
        func_str = render_simple(func_item)

        # When first argument fits on a single line, align to first argument column
        case single_line_format(arg1_item) do
          {:ok, arg1_str} ->
            header = "#{open_str}#{func_str} #{arg1_str}"
            arg_indent = indent + String.length(open_str <> func_str <> " ")
            all_remaining = drop_until_after(items, arg1_item)

            render_header_and_body(
              header,
              all_remaining,
              rest_args,
              indent,
              arg_indent,
              close_str,
              config
            )

          :multiline ->
            header = "#{open_str}#{func_str}"
            all_remaining = drop_until_after(items, func_item)
            arg_indent = indent + config.indent_step
            body_lines = format_body_items(all_remaining, arg_indent, config)

            combine_lines_with_close(
              [indent_str(indent) <> header | body_lines],
              close_str
            )
        end

      [func_item] ->
        func_str = render_simple(func_item)
        [indent_str(indent) <> open_str <> func_str <> close_str]

      _ ->
        format_generic_list(open_str, close_str, items, indent, config)
    end
  end

  # Format clause (clauses in cond or case)
  defp format_clause(open_str, close_str, items, has_nl, indent, config) do
    if not has_nl do
      case single_line_format({:list, open_str, close_str, items, false}) do
        {:ok, s} ->
          if indent + String.length(s) <= config.max_width do
            [indent_str(indent) <> s]
          else
            format_multiline_clause(open_str, close_str, items, indent, config)
          end

        :multiline ->
          format_multiline_clause(open_str, close_str, items, indent, config)
      end
    else
      format_multiline_clause(open_str, close_str, items, indent, config)
    end
  end

  defp format_multiline_clause(open_str, close_str, items, indent, config) do
    code_items = extract_code_items(items)

    case code_items do
      [test_item | _rest_items] ->
        case single_line_format(test_item) do
          {:ok, test_str} ->
            first_line = indent_str(indent) <> open_str <> test_str
            # Align remaining actions to test (indent + length of open_str)
            act_indent = indent + String.length(open_str)
            all_remaining = drop_until_after(items, test_item)
            body_lines = format_body_items(all_remaining, act_indent, config)
            combine_lines_with_close([first_line | body_lines], close_str)

          :multiline ->
            header = indent_str(indent) <> open_str
            test_lines = format_node_lines(test_item, indent + String.length(open_str), config)
            all_remaining = drop_until_after(items, test_item)
            body_lines = format_body_items(all_remaining, indent + config.indent_step, config)
            combine_lines_with_close([header | test_lines] ++ body_lines, close_str)
        end

      [] ->
        [indent_str(indent) <> open_str <> close_str]
    end
  end

  # Generic list (data list, vector, etc.)
  defp format_generic_list(open_str, close_str, items, indent, config) do
    code_items = extract_code_items(items)

    case code_items do
      [first_item | rest_items] ->
        case single_line_format(first_item) do
          {:ok, first_str} ->
            header = "#{open_str}#{first_str}"
            elem_indent = indent + String.length(open_str)
            all_remaining = drop_until_after(items, first_item)

            render_header_and_body(
              header,
              all_remaining,
              rest_items,
              indent,
              elem_indent,
              close_str,
              config
            )

          :multiline ->
            header = open_str
            elem_indent = indent + String.length(open_str)
            body_lines = format_body_items(items, elem_indent, config)

            combine_lines_with_close(
              [indent_str(indent) <> header | body_lines],
              close_str
            )
        end

      _ ->
        [indent_str(indent) <> open_str <> close_str]
    end
  end

  # Alignment of binding list ((a 1) (b 2))
  defp format_binding_sub_items(items, indent, header_prefix, close_delim, config) do
    code_items = extract_code_items(items)

    case code_items do
      [first_binding | _rest_bindings] ->
        first_lines = format_node_lines(first_binding, 0, config)
        all_remaining = drop_until_after(items, first_binding)
        rest_lines = format_body_items(all_remaining, indent, config)

        case first_lines do
          [single_first] ->
            combined_first = header_prefix <> String.trim_leading(single_first)
            combine_lines_with_close([combined_first | rest_lines], close_delim)

          [multi_first | multi_rest] ->
            combined_first = header_prefix <> String.trim_leading(multi_first)

            indented_multi =
              Enum.map(multi_rest, &(indent_str(indent) <> String.trim_leading(&1)))

            combine_lines_with_close([combined_first | indented_multi] ++ rest_lines, close_delim)
        end

      [] ->
        [header_prefix <> close_delim]
    end
  end

  # =========================================================================
  # 5. Helper functions
  # =========================================================================

  defp render_header_and_body(
         header,
         all_remaining,
         _remaining_code_items,
         indent,
         body_indent,
         close_str,
         config
       ) do
    if all_remaining == [] do
      [indent_str(indent) <> header <> close_str]
    else
      body_lines = format_body_items(all_remaining, body_indent, config)
      first_line = indent_str(indent) <> header
      combine_lines_with_close([first_line | body_lines], close_str)
    end
  end

  defp format_body_items(items, indent, config) do
    Enum.reduce(items, [], fn item, acc ->
      case item do
        {:blank_line} ->
          case acc do
            ["" | _] -> acc
            [] -> acc
            _ -> ["" | acc]
          end

        {:comment, text, :standalone} ->
          cond do
            String.starts_with?(text, ";;;;") -> [text | acc]
            String.starts_with?(text, ";;;") and indent == 0 -> [text | acc]
            true -> [indent_str(indent) <> text | acc]
          end

        {:comment, text, :inline} ->
          # Append inline comment to end of previous line
          case acc do
            [prev_line | rest_acc] ->
              ["#{prev_line}  #{text}" | rest_acc]

            [] ->
              [indent_str(indent) <> text]
          end

        node ->
          rendered = format_node_lines(node, indent, config)
          Enum.reverse(rendered) ++ acc
      end
    end)
    |> Enum.reverse()
  end

  defp format_items_block(items, indent, open_str, close_str, config) do
    body_lines = format_body_items(items, indent, config)
    first_line = indent_str(indent - config.indent_step) <> open_str
    combine_lines_with_close([first_line | body_lines], close_str)
  end

  # Append closing delimiter to end of line
  defp combine_lines_with_close([], close_str), do: [close_str]

  defp combine_lines_with_close(lines, close_str) do
    case Enum.reverse(lines) do
      [last_line | rest] ->
        # Check if line ends with inline comment
        updated_last = append_close_delimiter(last_line, close_str)
        Enum.reverse([updated_last | rest])

      [] ->
        [close_str]
    end
  end

  defp append_close_delimiter(line, close_str) do
    # If inline comment `;...` is included, insert closing delimiter right before comment
    case find_comment_start_in_line(line) do
      nil ->
        line <> close_str

      pos ->
        code_part = String.slice(line, 0, pos) |> String.trim_trailing()
        comment_part = String.slice(line, pos..-1//1)
        "#{code_part}#{close_str}  #{comment_part}"
    end
  end

  defp find_comment_start_in_line(line) do
    chars = String.to_charlist(line)
    find_comment_pos(chars, 0, false)
  end

  defp find_comment_pos([], _idx, _in_str), do: nil

  defp find_comment_pos([?\\, _c | rest], idx, true) do
    find_comment_pos(rest, idx + 2, true)
  end

  defp find_comment_pos([?\" | rest], idx, in_str) do
    find_comment_pos(rest, idx + 1, not in_str)
  end

  defp find_comment_pos([?; | _rest], idx, false) do
    idx
  end

  defp find_comment_pos([_ | rest], idx, in_str) do
    find_comment_pos(rest, idx + 1, in_str)
  end

  defp extract_code_items(items) do
    Enum.filter(items, fn
      {:comment, _, _} -> false
      {:blank_line} -> false
      _ -> true
    end)
  end

  defp drop_until_after(items, target_item) do
    Enum.drop_while(items, fn
      item when item == target_item -> false
      _ -> true
    end)
    |> case do
      [_target | rest] -> rest
      [] -> []
    end
  end

  defp render_simple({:atom, text}), do: text
  defp render_simple({:string, text}), do: text
  defp render_simple({:prefix, p, inner}), do: p <> render_simple(inner)
  defp render_simple(_), do: ""

  defp indent_str(n) when n > 0, do: String.duplicate(" ", n)
  defp indent_str(_), do: ""
end
