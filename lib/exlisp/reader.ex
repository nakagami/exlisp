defmodule ExLisp.Reader do
  @moduledoc """
  Module to split Lisp source code into top-level S-expressions (per expression).
  """

  @doc """
  Splits a Lisp string containing multiple expressions into a list of expression strings.
  """
  def split_expressions(input) do
    chars = String.to_charlist(input)
    scan(chars, [], false, false, 0, [], [])
  end

  defp scan([], _stack, _in_str, _in_cmt, _block_cmt_depth, current, acc) do
    chunk = current |> Enum.reverse() |> List.to_string() |> String.trim()
    if chunk != "", do: Enum.reverse([chunk | acc]), else: Enum.reverse(acc)
  end

  # Block comment handling (supports nested #| ... |#)
  defp scan([?#, ?| | rest], stack, false, false, block_cmt_depth, current, acc) do
    scan(rest, stack, false, false, block_cmt_depth + 1, current, acc)
  end

  defp scan([?|, ?# | rest], stack, false, false, 1, current, acc) do
    scan(rest, stack, false, false, 0, current, acc)
  end

  defp scan([?|, ?# | rest], stack, false, false, block_cmt_depth, current, acc)
       when block_cmt_depth > 1 do
    scan(rest, stack, false, false, block_cmt_depth - 1, current, acc)
  end

  defp scan([_c | rest], stack, false, false, block_cmt_depth, current, acc)
       when block_cmt_depth > 0 do
    scan(rest, stack, false, false, block_cmt_depth, current, acc)
  end

  # End comment on newline
  defp scan([?\n | rest], [], false, true, 0, _current, acc) do
    scan(rest, [], false, false, 0, [], acc)
  end

  defp scan([?\n | rest], stack, false, true, 0, current, acc) do
    scan(rest, stack, false, false, 0, [?\n | current], acc)
  end

  # Skip chars inside comment
  defp scan([c | rest], stack, false, true, 0, current, acc) do
    scan(rest, stack, false, true, 0, [c | current], acc)
  end

  # String escape
  defp scan([?\\, c | rest], stack, true, false, 0, current, acc) do
    scan(rest, stack, true, false, 0, [c, ?\\ | current], acc)
  end

  # End string
  defp scan([?\" | rest], stack, true, false, 0, current, acc) do
    scan(rest, stack, false, false, 0, [?\" | current], acc)
  end

  # Chars inside string
  defp scan([c | rest], stack, true, false, 0, current, acc) do
    scan(rest, stack, true, false, 0, [c | current], acc)
  end

  # Start comment
  defp scan([?; | rest], [], false, false, 0, current, acc) do
    chunk = current |> Enum.reverse() |> List.to_string() |> String.trim()

    if chunk != "" do
      scan(rest, [], false, true, 0, [], [chunk | acc])
    else
      scan(rest, [], false, true, 0, [], acc)
    end
  end

  defp scan([?; | rest], stack, false, false, 0, current, acc) do
    scan(rest, stack, false, true, 0, [?; | current], acc)
  end

  # Start string
  defp scan([?\" | rest], stack, false, false, 0, current, acc) do
    scan(rest, stack, true, false, 0, [?\" | current], acc)
  end

  # Opening delimiter
  defp scan([open | rest], stack, false, false, 0, current, acc) when open in [?(, ?[, ?{] do
    close =
      case open do
        ?( -> ?)
        ?[ -> ?]
        ?{ -> ?}
      end

    scan(rest, [close | stack], false, false, 0, [open | current], acc)
  end

  # Closing delimiter
  defp scan([close | rest], [expected | stack], false, false, 0, current, acc)
       when close == expected do
    new_current = [close | current]

    if stack == [] do
      chunk = new_current |> Enum.reverse() |> List.to_string() |> String.trim()
      scan(rest, [], false, false, 0, [], [chunk | acc])
    else
      scan(rest, stack, false, false, 0, new_current, acc)
    end
  end

  # Delimit whitespace when stack is empty
  defp scan([ws | rest], [], false, false, 0, current, acc) when ws in [?\s, ?\t, ?\n, ?\r] do
    chunk = current |> Enum.reverse() |> List.to_string() |> String.trim()

    cond do
      chunk == "" ->
        scan(rest, [], false, false, 0, [], acc)

      incomplete_prefix?(chunk) ->
        scan(rest, [], false, false, 0, [ws | current], acc)

      true ->
        scan(rest, [], false, false, 0, [], [chunk | acc])
    end
  end

  # Normal char
  defp scan([c | rest], stack, false, false, 0, current, acc) do
    scan(rest, stack, false, false, 0, [c | current], acc)
  end

  defp incomplete_prefix?(str) do
    cond do
      str in ["'", "#'", "`", ",", ",@", "#.", "#+", "#-"] ->
        true

      String.starts_with?(str, "#+") or String.starts_with?(str, "#-") ->
        parts = String.split(str, ~r/\s+/, trim: true)
        length(parts) < 2

      true ->
        false
    end
  end
end
