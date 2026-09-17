defmodule ExLisp.List do
  @moduledoc """
  Lisp list struct for REPL display.
  Implements the Inspect protocol to output in Common Lisp format such as (A B C) or (EXPT 2 3).
  """
  defstruct [:items, tail: nil]

  def new([]), do: ExLisp.Symbol.new("NIL")

  def new(list) when is_list(list) do
    {items, tail} = decompose(list, [])
    disp_items = Enum.map(items, &ExLisp.to_repl_display/1)
    disp_tail = if tail != nil, do: ExLisp.to_repl_display(tail), else: nil
    %__MODULE__{items: disp_items, tail: disp_tail}
  end

  defp decompose([], acc), do: {Enum.reverse(acc), nil}
  defp decompose([h | t], acc) when is_list(t), do: decompose(t, [h | acc])
  defp decompose([h | nil], acc), do: {Enum.reverse([h | acc]), nil}
  defp decompose([h | t], acc), do: {Enum.reverse([h | acc]), t}

  defimpl Inspect do
    import Inspect.Algebra

    def inspect(%ExLisp.List{items: [%ExLisp.Symbol{name: "QUOTE"}, arg], tail: nil}, opts) do
      concat(["'", to_doc(arg, opts)])
    end

    def inspect(%ExLisp.List{items: [%ExLisp.Symbol{name: "FUNCTION"}, arg], tail: nil}, opts) do
      concat(["#'", to_doc(arg, opts)])
    end

    def inspect(%ExLisp.List{items: items, tail: nil}, opts) do
      doc_items = Enum.map(items, &to_doc(&1, opts))
      inner = fold_doc(doc_items, fn doc, acc -> concat([doc, " ", acc]) end)
      concat(["(", inner, ")"])
    end

    def inspect(%ExLisp.List{items: items, tail: tail}, opts) do
      doc_items = Enum.map(items, &to_doc(&1, opts))
      inner = fold_doc(doc_items, fn doc, acc -> concat([doc, " ", acc]) end)
      concat(["(", inner, " . ", to_doc(tail, opts), ")"])
    end
  end
end
