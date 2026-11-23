defmodule ExLisp.CLPPCRE do
  @moduledoc false

  def install do
    ExLisp.Package.ensure_tables()
    package = ExLisp.Package.find_package!("CL-PPCRE")

    functions = %{
      scan: &scan/1,
      scan_to_strings: &scan_to_strings/1,
      split: &split/1,
      regex_replace: &regex_replace/1,
      regex_replace_all: &regex_replace_all/1,
      quote_meta_chars: &quote_meta_chars/1,
      create_scanner: &create_scanner/1,
      count_matches: &count_matches/1,
      all_matches: &all_matches/1,
      all_matches_as_strings: &all_matches_as_strings/1
    }

    Enum.each(functions, fn {name, function} ->
      closure = ExLisp.Closure.new(function, name, package: package.name)

      for package_name <- [package.name | package.nicknames],
          prefix <- [
            String.downcase(package_name),
            String.replace(String.downcase(package_name), "_", "-")
          ],
          separator <- [".", ":"] do
        ExLisp.Env.put_fun(:"#{prefix}#{separator}#{name}", closure)
      end
    end)

    :t
  end

  def create_scanner(pattern) when is_list(pattern), do: compile_pattern(hd(pattern))
  def create_scanner(pattern), do: compile_pattern(pattern)

  def scan(args) do
    {regex, target, opts} = scanner_args(args)
    range = target_range(target, opts)

    case Regex.run(regex, range, return: :index, capture: :all) do
      nil ->
        nil

      [match | captures] ->
        offset = Keyword.get(opts, :start, 0)
        {start, length} = match
        starts = Enum.map(captures, &capture_start(&1, offset))
        ends = Enum.map(captures, &capture_end(&1, offset))

        [:_values_, [start + offset, start + offset + length, starts, ends]]
    end
  end

  def scan_to_strings(args) do
    {regex, target, opts} = scanner_args(args)

    case Regex.run(regex, target_range(target, opts), capture: :all) do
      nil -> [:_values_, [nil, nil]]
      [match | captures] -> [:_values_, [match, captures]]
    end
  end

  def split(args) do
    {regex, target, opts} = scanner_args(args)

    values =
      Regex.split(regex, target_range(target, opts),
        trim: false,
        include_captures: option?(opts, :with_registers_p)
      )

    case Keyword.get(opts, :limit) do
      nil -> values
      0 -> values
      limit when is_integer(limit) and limit > 0 -> Enum.take(values, limit)
      _ -> values
    end
  end

  def count_matches(args), do: args |> all_match_indexes() |> length()

  def all_matches(args) do
    args
    |> all_match_indexes()
    |> Enum.flat_map(fn {start, size} -> [start, start + size] end)
  end

  def all_matches_as_strings(args) do
    {regex, target, opts} = scanner_args(args)

    Regex.scan(regex, target_range(target, opts), capture: :first)
    |> Enum.map(fn
      [whole] -> whole
      [] -> ""
    end)
  end

  def regex_replace([pattern, target, replacement | opts]) do
    Regex.replace(compile_pattern(pattern), target, replace_lisp_args(replacement),
      global: false,
      opts: parse_options(opts)
    )
  end

  def regex_replace_all([pattern, target, replacement | opts]) do
    Regex.replace(compile_pattern(pattern), target, replace_lisp_args(replacement),
      global: true,
      opts: parse_options(opts)
    )
  end

  def quote_meta_chars([value]), do: Regex.escape(to_string(value))
  def quote_meta_chars(value), do: Regex.escape(to_string(value))

  defp scanner_args([regex, target | opts]),
    do: {compile_pattern(regex), to_string(target), parse_options(opts)}

  defp all_match_indexes(args) do
    {regex, target, opts} = scanner_args(args)
    offset = Keyword.get(opts, :start, 0) || 0

    Regex.scan(regex, target_range(target, opts), return: :index, capture: :first)
    |> Enum.map(fn [match] ->
      {start, size} = match
      {start + offset, size}
    end)
  end

  defp capture_start({-1, _size}, _offset), do: nil
  defp capture_start({index, _size}, offset), do: index + offset
  defp capture_end({-1, _size}, _offset), do: nil
  defp capture_end({index, size}, offset), do: index + size + offset

  defp option?(opts, name), do: Keyword.get(opts, name) not in [nil, false, 0]

  defp compile_pattern(%Regex{} = regex), do: regex

  defp compile_pattern(pattern) do
    pattern
    |> to_string()
    |> String.replace("\\A", "^")
    |> String.replace("\\Z", "$")
    |> Regex.compile!("u")
  end

  defp target_range(target, opts) do
    start = Keyword.get(opts, :start, 0) || 0
    finish = Keyword.get(opts, :end, String.length(target))
    String.slice(target, start, finish - start)
  end

  defp parse_options(opts) do
    ExLisp.Builtins.parse_lisp_keywords(opts)
  rescue
    _ -> []
  end

  defp replace_lisp_args(replacement) when is_binary(replacement), do: replacement
  defp replace_lisp_args(replacement), do: ExLisp.Builtins.to_string_val(replacement)
end
