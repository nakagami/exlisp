defmodule ExLisp.Character do
  @moduledoc """
  Struct representing Common Lisp character (#\\...).
  """

  defstruct [:code]

  @type t :: %__MODULE__{code: non_neg_integer()}

  @doc """
  Creates a new character from a codepoint integer or single-character UTF-8 binary.
  """
  def new(code) when is_integer(code) and code >= 0 and code <= 0x10FFFF do
    %__MODULE__{code: code}
  end

  def new(<<c::utf8>>) do
    %__MODULE__{code: c}
  end

  @doc """
  Returns the integer codepoint of the character.
  """
  def code(%__MODULE__{code: code}), do: code
  def to_integer(%__MODULE__{code: code}), do: code

  @standard_char_names %{
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

  @standard_name_chars %{
    "SPACE" => ?\s,
    "NEWLINE" => ?\n,
    "LINEFEED" => ?\n,
    "TAB" => ?\t,
    "RETURN" => ?\r,
    "PAGE" => ?\f,
    "BACKSPACE" => ?\b,
    "ESCAPE" => 27,
    "ESC" => 27,
    "RUBOUT" => 127,
    "NULL" => 0,
    "NUL" => 0
  }

  @doc """
  Returns the name of a character code, or nil if not named (e.g. ASCII graphic chars 33..126).
  """
  def code_to_name(code) when is_integer(code) do
    case Map.get(@standard_char_names, code) do
      name when is_binary(name) ->
        name

      nil ->
        if code in 33..126 do
          nil
        else
          ExLisp.UnicodeData.code_to_name(code)
        end
    end
  end

  @doc """
  Resolves a character name string to integer codepoint, or nil if unknown.
  """
  def name_to_code(name) when is_binary(name) do
    norm =
      name
      |> String.upcase()
      |> String.replace(" ", "_")
      |> String.replace("-", "_")

    case Map.get(@standard_name_chars, norm) do
      code when is_integer(code) ->
        code

      nil ->
        case norm do
          "U+" <> hex ->
            case Integer.parse(hex, 16) do
              {code, ""} -> code
              _ -> nil
            end

          "U" <> hex when byte_size(hex) in [4, 5, 6] ->
            case Integer.parse(hex, 16) do
              {code, ""} -> code
              _ -> nil
            end

          _ ->
            ExLisp.UnicodeData.name_to_code(norm)
        end
    end
  end

  defimpl Inspect do
    def inspect(%ExLisp.Character{code: code}, _opts) do
      cond do
        code == ?\s ->
          "#\\Space"

        code >= 33 and code <= 126 ->
          "#\\" <> <<code::utf8>>

        true ->
          case ExLisp.Character.code_to_name(code) do
            name when is_binary(name) ->
              "#\\" <> name

            nil ->
              "#\\U" <> Integer.to_string(code, 16)
          end
      end
    end
  end

  defimpl String.Chars do
    def to_string(%ExLisp.Character{code: code}) do
      <<code::utf8>>
    end
  end

  defimpl List.Chars do
    def to_charlist(%ExLisp.Character{code: code}) do
      [code]
    end
  end
end
