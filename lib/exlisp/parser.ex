defmodule ExLisp.Parser do
  @moduledoc """
  IEx parser. Inspects nested parentheses of input strings and generates AST
  that invokes `ExLisp.eval/1` once top-level parentheses are closed.
  """

  @doc """
  Custom parser callback for IEx.
  """
  def parse(input, _opts, parser_state) do
    buffer =
      case parser_state do
        {buf, _} when is_binary(buf) -> buf
        buf when is_binary(buf) -> buf
        _ -> ""
      end

    full_input = buffer <> input

    if input == "#iex:break\n" do
      if buffer == "" do
        {:incomplete, {"", :other}}
      else
        raise SyntaxError, description: "incomplete expression", file: "nofile", line: 1
      end
    else
      trimmed = String.trim(full_input)

      if trimmed == "" do
        expr = quote do: IEx.dont_display_result()
        {:ok, expr, {"", :other}}
      else
        case parse_history_command(trimmed) do
          {:rerun, n} ->
            case ExLisp.Env.get_history_code(n) do
              nil ->
                raise SyntaxError,
                  description: "No history entry found for index #{n}",
                  file: "nofile",
                  line: 1

              code ->
                IO.puts("==> #{code}")
                expr = quote do: ExLisp.eval_repl(unquote(code))
                {:ok, expr, {"", :other}}
            end

          :not_history ->
            case check_delimiters(full_input) do
              {:incomplete, _} ->
                {:incomplete, {full_input, :other}}

              {:error, reason} ->
                raise SyntaxError, description: reason, file: "nofile", line: 1

              :complete ->
                case ExLisp.LispParser.parse(trimmed) do
                  {:ok, _ast} ->
                    expr = quote do: ExLisp.eval_repl(unquote(trimmed))
                    {:ok, expr, {"", :other}}

                  {:error, reason} ->
                    raise SyntaxError,
                      description: "Parse error: #{reason}",
                      file: "nofile",
                      line: 1
                end
            end
        end
      end
    end
  end

  defp parse_history_command(str) do
    case str do
      "!" <> num_str ->
        case Integer.parse(num_str) do
          {n, ""} -> {:rerun, n}
          _ -> :not_history
        end

      _ ->
        :not_history
    end
  end

  @doc """
  Checks balance of delimiters such as parentheses and quotes in input string.
  """
  def check_delimiters(input) do
    chars = String.to_charlist(input)
    scan(chars, [], false, false, false)
  end

  # Reached end
  defp scan([], _stack, true, _in_comment, _has_content) do
    {:incomplete, :in_string}
  end

  defp scan([], [], false, _in_comment, has_content) do
    if has_content, do: :complete, else: :empty
  end

  defp scan([], stack, false, _in_comment, _has_content) when length(stack) > 0 do
    {:incomplete, length(stack)}
  end

  # In comment (skip until newline)
  defp scan([?\n | rest], stack, false, true, has_content) do
    scan(rest, stack, false, false, has_content)
  end

  defp scan([_ | rest], stack, false, true, has_content) do
    scan(rest, stack, false, true, has_content)
  end

  # In string (escape and double quote)
  defp scan([?\\, _ | rest], stack, true, false, has_content) do
    scan(rest, stack, true, false, has_content)
  end

  defp scan([?\" | rest], stack, true, false, _has_content) do
    scan(rest, stack, false, false, true)
  end

  defp scan([_ | rest], stack, true, false, has_content) do
    scan(rest, stack, true, false, has_content)
  end

  # Normal code
  defp scan([?; | rest], stack, false, false, has_content) do
    scan(rest, stack, false, true, has_content)
  end

  defp scan([?\" | rest], stack, false, false, _has_content) do
    scan(rest, stack, true, false, true)
  end

  defp scan([?( | rest], stack, false, false, _has_content) do
    scan(rest, [?) | stack], false, false, true)
  end

  defp scan([?[ | rest], stack, false, false, _has_content) do
    scan(rest, [?] | stack], false, false, true)
  end

  defp scan([?{ | rest], stack, false, false, _has_content) do
    scan(rest, [?} | stack], false, false, true)
  end

  defp scan([close | rest], [expected | stack], false, false, _has_content)
       when close in [?), ?], ?}] and close == expected do
    scan(rest, stack, false, false, true)
  end

  defp scan([close | _rest], _stack, false, false, _has_content)
       when close in [?), ?], ?}] do
    {:error, "unexpected delimiter #{<<close>>}"}
  end

  defp scan([c | rest], stack, false, false, has_content) do
    is_ws = c in [?\s, ?\t, ?\n, ?\r]
    scan(rest, stack, false, false, has_content or not is_ws)
  end
end
