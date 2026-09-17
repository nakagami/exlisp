defmodule ExLisp.Symbol do
  @moduledoc """
  Lisp symbol struct for REPL display.
  Implements the Inspect protocol to output symbol names without colons or quotes.
  """
  defstruct [:name, :id]

  def new(name) when is_atom(name) do
    %__MODULE__{name: Atom.to_string(name)}
  end

  def new(name) when is_binary(name) do
    %__MODULE__{name: name}
  end

  def uninterned(name) when is_binary(name) do
    %__MODULE__{name: name, id: System.unique_integer([:positive, :monotonic])}
  end

  def uninterned(name) when is_atom(name) do
    %__MODULE__{name: Atom.to_string(name), id: System.unique_integer([:positive, :monotonic])}
  end

  defimpl Inspect do
    def inspect(%ExLisp.Symbol{name: name}, _opts) do
      name
    end
  end

  defimpl String.Chars do
    def to_string(%ExLisp.Symbol{name: name}) do
      name
    end
  end
end
