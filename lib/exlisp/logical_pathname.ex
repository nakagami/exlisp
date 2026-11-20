defmodule ExLisp.LogicalPathname do
  @moduledoc """
  Storage and wildcard translation for Common Lisp logical pathnames.
  """

  alias ExLisp.Pathname

  @table :exlisp_logical_pathname_translations

  def logical_pathname(pathspec) do
    path = Pathname.pathname(pathspec)

    if path.host do
      path
    else
      raise ArgumentError, "not a logical pathname: #{Pathname.namestring(path)}"
    end
  end

  def logical_pathname_p(pathspec) do
    case pathname_if_possible(pathspec) do
      %Pathname{host: host} when host not in [nil, :unspecific] -> :t
      _ -> nil
    end
  end

  def logical_pathname_translations(host) do
    ensure_table()

    case :ets.lookup(@table, host_name(host)) do
      [{_, translations}] -> translations
      [] -> nil
    end
  end

  def logical_pathname_translations(host, translations) do
    ensure_table()
    :ets.insert(@table, {host_name(host), normalize_translations(translations)})
    :t
  end

  def load_logical_pathname_translations(host) do
    ensure_table()
    if logical_pathname_translations(host), do: :t, else: nil
  end

  def translate_logical_pathname(pathspec) do
    path = logical_pathname(pathspec)
    translations = logical_pathname_translations(path.host)

    if translations == nil or translations == [] do
      raise ArgumentError, "no logical pathname translations for #{path.host}"
    end

    Enum.find_value(translations, fn {from, to} ->
      case match_pathname(path, Pathname.pathname(from)) do
        {:ok, captures} -> substitute_pathname(captures, Pathname.pathname(to))
        :error -> nil
      end
    end)
    |> case do
      nil -> raise ArgumentError, "no translation matches #{Pathname.namestring(path)}"
      translated -> translated
    end
  end

  def translate_pathname(source, from, to) do
    source_path = Pathname.pathname(source)
    from_path = Pathname.pathname(from)
    to_path = Pathname.pathname(to)

    case match_pathname(source_path, from_path) do
      {:ok, captures} -> substitute_pathname(captures, to_path)
      :error -> raise ArgumentError, "pathname does not match translation pattern"
    end
  end

  defp match_pathname(source, pattern) do
    source_parts = wildcard_components(source)
    pattern_parts = wildcard_components(pattern)

    with {:ok, captures} <- match_parts(source_parts.directory, pattern_parts.directory, []),
         {:ok, captures} <- match_component(source.name, pattern.name, captures),
         {:ok, captures} <- match_component(source.type, pattern.type, captures) do
      {:ok, captures}
    end
  end

  defp wildcard_components(path) do
    dirs =
      case path.directory do
        [_kind | rest] -> rest
        other when is_list(other) -> other
        _ -> []
      end

    %{directory: dirs, name: path.name, type: path.type}
  end

  defp match_parts([], [], captures), do: {:ok, captures}

  defp match_parts([], [:wild_inferiors | rest], captures),
    do: match_parts([], rest, captures)

  defp match_parts(source, [:wild_inferiors | rest], captures) do
    Enum.reduce_while(0..length(source), :error, fn count, _acc ->
      taken = Enum.take(source, count)

      case match_parts(Enum.drop(source, count), rest, [{:inferiors, taken} | captures]) do
        {:ok, _} = ok -> {:halt, ok}
        :error -> {:cont, :error}
      end
    end)
  end

  defp match_parts([s | source], [:wild | rest], captures),
    do: match_parts(source, rest, [{:directory, s} | captures])

  defp match_parts([s | source], [p | rest], captures) do
    if equal_component?(s, p), do: match_parts(source, rest, captures), else: :error
  end

  defp match_parts(_, _, _), do: :error

  defp match_component(value, :wild, captures), do: {:ok, [{:component, value} | captures]}
  defp match_component(value, value, captures), do: {:ok, captures}

  defp match_component(value, pattern, captures) do
    if equal_component?(value, pattern), do: {:ok, captures}, else: :error
  end

  defp equal_component?(a, b) do
    String.downcase(to_string(a)) == String.downcase(to_string(b))
  end

  defp substitute_pathname(captures, template) do
    directory_captures =
      captures
      |> Enum.filter(&(elem(&1, 0) == :directory))
      |> Enum.map(&elem(&1, 1))
      |> Enum.reverse()

    component_captures =
      captures
      |> Enum.filter(&(elem(&1, 0) == :component))
      |> Enum.map(&elem(&1, 1))
      |> Enum.reverse()

    inferior =
      captures
      |> Enum.find_value([], fn
        {:inferiors, values} -> values
        _ -> nil
      end)

    {directories, _remaining_directories} =
      template_directory(template.directory)
      |> Enum.flat_map_reduce(directory_captures, fn
        :wild_inferiors, acc -> {inferior, acc}
        :wild, [value | acc] -> {[value], acc}
        :wild, [] -> {[:wild], []}
        part, acc -> {[part], acc}
      end)

    {name, remaining} = substitute_one(template.name, component_captures)
    {type, _remaining} = substitute_one(template.type, remaining)

    %{
      template
      | directory: directory_with_kind(template.directory, directories),
        name: name,
        type: type
    }
  end

  defp template_directory([kind | rest]) when kind in [:absolute, :relative], do: rest
  defp template_directory(other) when is_list(other), do: other
  defp template_directory(_), do: []

  defp directory_with_kind([kind | _], dirs) when kind in [:absolute, :relative],
    do: [kind | dirs]

  defp directory_with_kind(_, dirs), do: dirs

  defp substitute_one(:wild, [value | rest]), do: {value, rest}
  defp substitute_one(value, rest), do: {value, rest}

  defp normalize_translations(translations) do
    Enum.map(translations, fn
      {from, to} ->
        {from, to}

      [from, to] ->
        {from, to}

      other when is_list(other) ->
        case other do
          [from, to | _] -> {from, to}
          _ -> raise ArgumentError, "invalid logical pathname translation"
        end
    end)
  end

  defp host_name(host) do
    host
    |> to_string()
    |> String.trim_leading(":")
    |> String.upcase()
  end

  defp pathname_if_possible(pathspec) do
    Pathname.pathname(pathspec)
  rescue
    _ -> nil
  end

  defp ensure_table do
    case :ets.whereis(@table) do
      :undefined ->
        try do
          :ets.new(@table, [:set, :public, :named_table])
        rescue
          ArgumentError -> :ok
        end

      _ ->
        :ok
    end
  end
end
