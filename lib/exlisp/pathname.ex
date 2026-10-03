defmodule ExLisp.Pathname do
  @moduledoc """
  ANSI Common Lisp Pathnames implementation for ExLisp.
  Supports:
  - make-pathname, pathname, pathnamep
  - pathname-host, pathname-device, pathname-directory, pathname-name, pathname-type, pathname-version
  - namestring, file-namestring, directory-namestring, host-namestring, enough-namestring
  - parse-namestring, merge-pathnames
  - truename, probe-file, file-author, file-write-date, directory, user-homedir-pathname
  - wild-pathname-p, pathname-match-p
  """

  defstruct host: nil,
            device: nil,
            directory: nil,
            name: nil,
            type: nil,
            version: nil

  @type t :: %__MODULE__{
          host: any(),
          device: any(),
          directory: list() | nil,
          name: any(),
          type: any(),
          version: any()
        }

  @doc """
  Returns :t if object is a pathname, nil otherwise.
  """
  def pathnamep(%__MODULE__{}), do: :t
  def pathnamep([%__MODULE__{}]), do: :t
  def pathnamep(_), do: nil

  @doc """
  Coerces pathspec (string, symbol, stream, or pathname) into a Pathname struct.
  """
  def pathname(%__MODULE__{} = p), do: p
  def pathname([%__MODULE__{} = p]), do: p

  def pathname(pathspec) when is_binary(pathspec) do
    parse_namestring_internal(pathspec)
  end

  def pathname(pathspec) when is_atom(pathspec) do
    str = Atom.to_string(pathspec)
    parse_namestring_internal(str)
  end

  def pathname(%ExLisp.Symbol{name: name}) do
    parse_namestring_internal(name)
  end

  def pathname(%ExLisp.Stream{extra: %{pathname: %__MODULE__{} = p}}), do: p
  def pathname(%ExLisp.Stream{extra: %{path: path}}) when is_binary(path), do: pathname(path)

  def pathname([:_values_, [p | _]]), do: pathname(p)
  def pathname([:_values_, []]), do: %__MODULE__{}
  def pathname(nil), do: %__MODULE__{}

  def pathname([pathspec]), do: pathname(pathspec)

  def pathname(other) do
    raise ArgumentError, "Cannot coerce #{inspect(other)} to a pathname"
  end

  @doc """
  Constructs a Pathname from keyword arguments.
  """
  def make_pathname(args \\ [])

  def make_pathname(args) when is_list(args) do
    opts = ExLisp.Builtins.parse_lisp_keywords(args)

    defaults =
      case Keyword.get(opts, :defaults) do
        nil -> %__MODULE__{}
        d -> pathname(d)
      end

    host = Keyword.get(opts, :host, defaults.host)
    device = Keyword.get(opts, :device, defaults.device)
    directory = normalize_directory_arg(Keyword.get(opts, :directory, defaults.directory))
    name = normalize_component(Keyword.get(opts, :name, defaults.name))
    type = normalize_component(Keyword.get(opts, :type, defaults.type))
    version = Keyword.get(opts, :version, defaults.version)

    %__MODULE__{
      host: host,
      device: device,
      directory: directory,
      name: name,
      type: type,
      version: version
    }
  end

  defp normalize_component(:unspecific), do: :unspecific
  defp normalize_component(:wild), do: :wild
  defp normalize_component(nil), do: nil
  defp normalize_component(str) when is_binary(str), do: str
  defp normalize_component(atom) when is_atom(atom), do: Atom.to_string(atom)
  defp normalize_component(%ExLisp.Symbol{name: n}), do: n
  defp normalize_component(other), do: to_string(other)

  defp normalize_directory_arg(nil), do: nil
  defp normalize_directory_arg(:unspecific), do: :unspecific
  defp normalize_directory_arg(:wild), do: [:relative, :wild]

  defp normalize_directory_arg(str) when is_binary(str) do
    p = parse_namestring_internal(str)
    p.directory
  end

  defp normalize_directory_arg(list) when is_list(list) do
    Enum.map(list, fn
      :absolute -> :absolute
      :relative -> :relative
      :wild -> :wild
      :wild_inferiors -> :wild_inferiors
      :up -> :up
      :back -> :back
      atom when is_atom(atom) ->
        str = Atom.to_string(atom) |> String.downcase()
        case str do
          "absolute" -> :absolute
          "relative" -> :relative
          "wild" -> :wild
          "wild-inferiors" -> :wild_inferiors
          "up" -> :up
          "back" -> :back
          _ -> str
        end
      str when is_binary(str) -> str
      other -> to_string(other)
    end)
  end

  defp normalize_directory_arg(other), do: other

  # --- Component Accessors ---

  def pathname_host(p) do
    (pathname(p)).host
  end

  def pathname_device(p) do
    (pathname(p)).device
  end

  def pathname_directory(p) do
    (pathname(p)).directory
  end

  def pathname_name(p) do
    (pathname(p)).name
  end

  def pathname_type(p) do
    (pathname(p)).type
  end

  def pathname_version(p) do
    (pathname(p)).version
  end

  # --- Namestrings ---

  @doc """
  Returns the full namestring representation of a pathname.
  """
  def namestring(p) do
    path = pathname(p)
    dir_str = directory_namestring(path)
    file_str = file_namestring(path)
    dir_str <> file_str
  end

  @doc """
  Returns only the directory part as a string (with trailing slash).
  """
  def directory_namestring(p) do
    path = pathname(p)

    case path.directory do
      nil ->
        ""

      :unspecific ->
        ""

      [:absolute | dirs] ->
        "/" <> Enum.map_join(dirs, "/", &dir_part_to_string/1) <> (if dirs != [], do: "/", else: "")

      [:relative | dirs] ->
        if dirs == [] do
          ""
        else
          Enum.map_join(dirs, "/", &dir_part_to_string/1) <> "/"
        end

      _ ->
        ""
    end
  end

  defp dir_part_to_string(:wild), do: "*"
  defp dir_part_to_string(:wild_inferiors), do: "**"
  defp dir_part_to_string(:up), do: ".."
  defp dir_part_to_string(:back), do: ".."
  defp dir_part_to_string(str) when is_binary(str), do: str
  defp dir_part_to_string(atom) when is_atom(atom), do: Atom.to_string(atom)
  defp dir_part_to_string(other), do: to_string(other)

  @doc """
  Returns the file name and type part as a string (e.g. "foo.lisp").
  """
  def file_namestring(p) do
    path = pathname(p)
    name = path.name
    type = path.type

    name_str =
      case name do
        nil -> ""
        :unspecific -> ""
        :wild -> "*"
        s -> to_string(s)
      end

    type_str =
      case type do
        nil -> ""
        :unspecific -> ""
        :wild -> ".*"
        s -> "." <> to_string(s)
      end

    name_str <> type_str
  end

  @doc """
  Returns the host namestring.
  """
  def host_namestring(p) do
    case (pathname(p)).host do
      nil -> ""
      :unspecific -> ""
      h -> to_string(h)
    end
  end

  @doc """
  Returns enough namestring relative to defaults.
  """
  def enough_namestring(p, defaults \\ nil) do
    path = pathname(p)
    def_path = if defaults, do: pathname(defaults), else: pathname(Path.expand("."))

    full_path = namestring(path)
    def_full = directory_namestring(def_path)

    if def_full != "" and String.starts_with?(full_path, def_full) do
      String.replace_prefix(full_path, def_full, "")
    else
      full_path
    end
  end

  # --- Parsing and Merging ---

  @doc """
  Parses a namestring into a Pathname struct.
  """
  def parse_namestring(args) when is_list(args) do
    case parse_namestring_mv(args) do
      [:_values_, [p | _]] -> p
      other -> other
    end
  end

  def parse_namestring(thing), do: parse_namestring([thing])

  @doc """
  Parses a namestring into a Pathname struct.
  Returns multiple values: `(values pathname end_index)`.
  """
  def parse_namestring_mv(args) when is_list(args) do
    case args do
      [thing | rest] ->
        opts = ExLisp.Builtins.parse_lisp_keywords(rest)
        start_idx = Keyword.get(opts, :start, 0) || 0
        end_idx = Keyword.get(opts, :end, nil)

        str =
          case thing do
            s when is_binary(s) -> s
            a when is_atom(a) -> Atom.to_string(a)
            %__MODULE__{} = p -> namestring(p)
            other -> to_string(other)
          end

        total_len = String.length(str)
        actual_end = if is_integer(end_idx), do: min(end_idx, total_len), else: total_len
        slice = String.slice(str, start_idx, actual_end - start_idx)

        parsed = parse_namestring_internal(slice)
        [:_values_, [parsed, actual_end]]

      _ ->
        raise ArgumentError, "parse-namestring requires at least 1 argument"
    end
  end

  def parse_namestring_mv(thing), do: parse_namestring_mv([thing])

  defp parse_namestring_internal(str) when is_binary(str) do
    # Remove surrounding double quotes or #P"..." if present
    clean_str =
      cond do
        String.starts_with?(str, "#P\"") and String.ends_with?(str, "\"") ->
          String.slice(str, 3..-2//1)

        String.starts_with?(str, "#p\"") and String.ends_with?(str, "\"") ->
          String.slice(str, 3..-2//1)

        String.starts_with?(str, "\"") and String.ends_with?(str, "\"") and String.length(str) >= 2 ->
          String.slice(str, 1..-2//1)

        true ->
          str
      end

    is_abs = String.starts_with?(clean_str, "/")
    ends_with_slash = String.ends_with?(clean_str, "/") and clean_str != "/"

    parts =
      clean_str
      |> String.split("/", trim: true)

    {dir_parts, file_part} =
      cond do
        clean_str == "/" ->
          {[], nil}

        ends_with_slash ->
          {parts, nil}

        parts == [] ->
          {[], nil}

        true ->
          {Enum.slice(parts, 0..-2//1), List.last(parts)}
      end

    parsed_dirs =
      Enum.map(dir_parts, fn
        "*" -> :wild
        "**" -> :wild_inferiors
        ".." -> :up
        "." -> :back
        d -> d
      end)

    directory =
      cond do
        clean_str == "/" -> [:absolute]
        is_abs -> [:absolute | parsed_dirs]
        parsed_dirs != [] -> [:relative | parsed_dirs]
        true -> nil
      end

    {name, type} =
      case file_part do
        nil ->
          {nil, nil}

        "*" ->
          {:wild, :wild}

        "*.*" ->
          {:wild, :wild}

        filename ->
          cond do
            String.starts_with?(filename, ".") and not String.contains?(String.slice(filename, 1..-1//1), ".") ->
              # e.g. ".gitignore" -> name = ".gitignore", type = nil
              {filename, nil}

            String.contains?(filename, ".") ->
              tokens = String.split(filename, ".")
              t = List.last(tokens)
              n = Enum.join(Enum.slice(tokens, 0..-2//1), ".")
              n_val = if n == "*", do: :wild, else: n
              t_val = if t == "*", do: :wild, else: t
              {n_val, t_val}

            true ->
              {filename, nil}
          end
      end

    %__MODULE__{
      host: nil,
      device: nil,
      directory: directory,
      name: name,
      type: type,
      version: :newest
    }
  end

  @doc """
  Merges pathname with default_pathname according to ANSI CL merge-pathnames rules.
  """
  def merge_pathnames(args) when is_list(args) do
    case args do
      [pathname] ->
        merge_pathnames(pathname, defaults_pathname())

      [pathname, default_pathname] ->
        merge_pathnames(pathname, default_pathname, :newest)

      [pathname, default_pathname, default_version] ->
        p = pathname(pathname)
        def_p = pathname(default_pathname)

        merged_host = p.host || def_p.host
        merged_device = p.device || def_p.device

        merged_directory =
          merge_directories(p.directory, def_p.directory)

        merged_name = p.name || def_p.name
        merged_type = p.type || def_p.type
        merged_version = p.version || def_p.version || default_version

        %__MODULE__{
          host: merged_host,
          device: merged_device,
          directory: merged_directory,
          name: merged_name,
          type: merged_type,
          version: merged_version
        }

      _ ->
        raise ArgumentError, "merge-pathnames requires 1 to 3 arguments"
    end
  end

  def merge_pathnames(pathname, default_pathname, default_version \\ :newest) do
    merge_pathnames([pathname, default_pathname, default_version])
  end

  defp defaults_pathname do
    case ExLisp.Env.get_var(:"*default-pathname-defaults*") do
      %__MODULE__{} = p -> p
      s when is_binary(s) -> pathname(s)
      _ -> pathname(Path.expand("."))
    end
  end

  defp merge_directories(nil, def_dir), do: def_dir
  defp merge_directories([:absolute | _] = p_dir, _def_dir), do: p_dir

  defp merge_directories([:relative | rel_dirs], [:absolute | base_dirs]) do
    [:absolute | base_dirs ++ rel_dirs]
  end

  defp merge_directories([:relative | rel_dirs], [:relative | base_dirs]) do
    [:relative | base_dirs ++ rel_dirs]
  end

  defp merge_directories([:relative | _] = p_dir, nil), do: p_dir
  defp merge_directories(p_dir, _), do: p_dir

  # --- Filesystem Queries ---

  @doc """
  Returns the truename (expanded, canonical pathname) of an existing file.
  Signals an error if file does not exist.
  """
  def truename(filespec) do
    path = pathname(filespec)
    str = namestring(path)
    expanded = Path.expand(str)

    if File.exists?(expanded) or File.dir?(expanded) do
      pathname(expanded <> (if File.dir?(expanded), do: "/", else: ""))
    else
      raise "File error: #{str} does not exist"
    end
  end

  @doc """
  Returns the truename if filespec exists, nil otherwise.
  """
  def probe_file(filespec) do
    path = pathname(filespec)
    str = namestring(path)
    expanded = Path.expand(str)

    if File.exists?(expanded) or File.dir?(expanded) do
      pathname(expanded <> (if File.dir?(expanded), do: "/", else: ""))
    else
      nil
    end
  end

  @doc """
  Returns the author / owner of the file.
  """
  def file_author(filespec) do
    path = pathname(filespec)
    str = namestring(path)
    expanded = Path.expand(str)

    case File.stat(expanded) do
      {:ok, stat} ->
        stat.uid |> to_string()

      _ ->
        nil
    end
  end

  @doc """
  Returns the file modification time in universal time format.
  """
  def file_write_date(filespec) do
    path = pathname(filespec)
    str = namestring(path)
    expanded = Path.expand(str)

    case File.stat(expanded, time: :posix) do
      {:ok, stat} ->
        # POSIX seconds to Universal Time (add 70 years = 719528 days)
        stat.mtime + 719_528 * 86_400

      _ ->
        nil
    end
  end

  @doc """
  Returns the list of pathnames matching pathspec.
  """
  def directory(pathspec \\ "*") do
    p = pathname(pathspec)
    glob_str = namestring(p)

    Path.wildcard(glob_str, match_dot: true)
    |> Enum.map(&pathname/1)
  end

  @doc """
  Returns the pathname of the user's home directory.
  """
  def user_homedir_pathname do
    home = System.user_home!()
    pathname(Path.join(home, ""))
  end

  @doc """
  Checks if pathname contains wild components.
  """
  def wild_pathname_p(p, field_key \\ nil) do
    path = pathname(p)

    case field_key do
      nil ->
        (path.name == :wild or path.type == :wild or
           (is_list(path.directory) and (:wild in path.directory or :wild_inferiors in path.directory)))
        |> lisp_bool()

      k when k in [:name, :":name"] -> (path.name == :wild) |> lisp_bool()
      k when k in [:type, :":type"] -> (path.type == :wild) |> lisp_bool()
      k when k in [:directory, :":directory"] ->
        (is_list(path.directory) and (:wild in path.directory or :wild_inferiors in path.directory))
        |> lisp_bool()
      k when k in [:host, :":host"] -> (path.host == :wild) |> lisp_bool()
      k when k in [:device, :":device"] -> (path.device == :wild) |> lisp_bool()
      _ -> nil
    end
  end

  @doc """
  Tests if pathname matches a wildcard pathname.
  """
  def pathname_match_p(p, wildcard) do
    path_str = namestring(p)
    wild_str = namestring(wildcard)

    regex_pattern =
      wild_str
      |> Regex.escape()
      |> String.replace("\\*\\*", ".*")
      |> String.replace("\\*", "[^/]*")

    case Regex.compile("^" <> regex_pattern <> "$") do
      {:ok, regex} -> Regex.match?(regex, path_str) |> lisp_bool()
      _ -> nil
    end
  end

  defp lisp_bool(true), do: :t
  defp lisp_bool(false), do: nil
end
