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

  @doc """
  Normalizes Lisp identifiers for internal atom-based lookup.
  """
  def normalize_name(name) when is_atom(name) do
    name |> Atom.to_string() |> normalize_name()
  end

  def normalize_name(name) when is_binary(name) do
    name
    |> String.downcase()
    |> String.replace("-", "_")
    |> String.to_atom()
  end

  def normalize_name(%__MODULE__{name: name}), do: normalize_name(name)
  def normalize_name(other), do: other

  @doc false
  def downcase(binary) when is_binary(binary) do
    if ascii_lowercase?(binary), do: binary, else: String.downcase(binary)
  end

  @doc false
  def downcase_atom(binary) when is_binary(binary) do
    cache_key = {:"$exlisp_downcase_atom$", binary}

    case Process.get(cache_key, :not_cached) do
      :not_cached ->
        atom = binary |> downcase() |> String.to_atom()
        Process.put(cache_key, atom)
        atom

      atom ->
        atom
    end
  end

  defp ascii_lowercase?(<<>>), do: true
  defp ascii_lowercase?(<<char, _::binary>>) when char in ?A..?Z, do: false
  defp ascii_lowercase?(<<char, _::binary>>) when char >= 128, do: false
  defp ascii_lowercase?(<<_char, rest::binary>>), do: ascii_lowercase?(rest)

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
