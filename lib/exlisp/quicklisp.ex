defmodule ExLisp.Quicklisp do
  @moduledoc """
  Quicklisp client module.
  Fetches and manages Quicklisp dist metadata for Common Lisp, and handles
  automatic downloading, unpacking, dependency resolution, and loading
  of third-party libraries via `ql:quickload`.
  """

  @distinfo_url "http://beta.quicklisp.org/dist/quicklisp.txt"
  @loaded_table :exlisp_loaded_systems

  @doc """
  Returns the base directory path for Quicklisp.
  """
  def quicklisp_dir do
    System.get_env("EXLISP_QUICKLISP_HOME") || Path.expand("~/.exlisp/quicklisp")
  end

  def dist_dir do
    Path.join(quicklisp_dir(), "dists/quicklisp")
  end

  def archive_dir do
    Path.join(quicklisp_dir(), "cache/archives")
  end

  def software_dir do
    Path.join(quicklisp_dir(), "software")
  end

  @doc """
  Downloads, resolves dependencies, and loads the specified system (single or list).
  Equivalent to Common Lisp `(ql:quickload :system-name)`.
  """
  def quickload(systems, opts \\ [])

  def quickload(systems, opts) when is_list(systems) do
    ensure_loaded_table()
    ensure_dist()
    {systems_map, releases_map} = load_indices()

    norm_systems =
      Enum.map(systems, &normalize_system_name/1)
      |> Enum.reject(&(&1 == nil or &1 == ""))

    loaded_list =
      Enum.flat_map(norm_systems, fn sys_name ->
        do_quickload(sys_name, systems_map, releases_map, opts)
      end)

    # Return value: list of loaded system symbols
    Enum.map(loaded_list, &String.upcase/1)
    |> Enum.map(&ExLisp.Symbol.new/1)
  end

  def quickload(system, opts) do
    quickload([system], opts)
  end

  @doc """
  Searches for libraries whose system names contain the query string.
  Equivalent to `(ql:system-apropos "query")`.
  """
  def system_apropos(query) when is_binary(query) or is_atom(query) do
    ensure_dist()
    {systems_map, _} = load_indices()
    q = query |> to_string() |> String.downcase()

    systems_map
    |> Map.keys()
    |> Enum.filter(&String.contains?(&1, q))
    |> Enum.sort()
    |> Enum.map(&String.upcase/1)
    |> Enum.map(&ExLisp.Symbol.new/1)
  end

  @doc """
  Returns the installation directory path for the specified system.
  """
  def where_is_system(system) do
    ensure_dist()
    {systems_map, releases_map} = load_indices()
    sys_name = normalize_system_name(system)

    case lookup_system_entry(systems_map, sys_name) do
      nil ->
        nil

      %{project: project_name} ->
        case Map.get(releases_map, project_name) do
          nil ->
            nil

          %{prefix: prefix} ->
            path = Path.join(software_dir(), prefix)
            if File.dir?(path), do: path, else: nil
        end
    end
  end

  # --- Internal processing ---

  defp do_quickload(sys_name, systems_map, releases_map, opts) do
    if is_system_loaded?(sys_name) and not Keyword.get(opts, :force, false) do
      [sys_name]
    else
      case lookup_system_entry(systems_map, sys_name) do
        nil ->
          case find_local_asd(sys_name) do
            {:ok, asd_path} ->
              load_local_asd_system(asd_path, sys_name, systems_map, releases_map, opts)

            :error ->
              raise RuntimeError, "Quicklisp system '#{sys_name}' not found in dist"
          end

        %{project: project_name, file: asd_filename} ->
          rel_info = Map.get(releases_map, project_name)

          if rel_info == nil do
            raise RuntimeError,
                  "Quicklisp release info for project '#{project_name}' not found"
          end

          # 1. Download & extract archive
          install_path = ensure_project_installed(rel_info)

          # 2. Find and parse .asd file
          asd_path = find_asd_file(install_path, asd_filename, sys_name)

          if asd_path == nil or not File.exists?(asd_path) do
            raise RuntimeError,
                  "ASDF definition file for '#{sys_name}' not found in #{install_path}"
          end

          sys_defs = ExLisp.ASDF.parse_asd(asd_path)

          primary_sys_def =
            case lookup_sys_def(sys_defs, sys_name, project_name) do
              nil ->
                case Map.values(sys_defs) do
                  [first | _] -> first
                  [] -> %{name: sys_name, depends_on: [], components: [], serial: true}
                end

              found ->
                found
            end

          # 3. Recursively load dependencies
          deps = primary_sys_def.depends_on |> Enum.reject(&skip_dependency?/1)

          Enum.each(deps, fn dep_sys ->
            do_quickload(dep_sys, systems_map, releases_map, opts)
          end)

          # 4. Load component files
          asd_dir = Path.dirname(asd_path)
          ExLisp.ASDF.load_system(primary_sys_def, asd_dir)

          # Record as loaded
          mark_system_loaded(sys_name)
          [sys_name]
      end
    end
  end

  defp find_local_asd(sys_name) do
    cwd = File.cwd!()

    candidates =
      [
        "#{sys_name}.asd",
        Path.join(cwd, "#{sys_name}.asd"),
        Path.join([cwd, sys_name, "#{sys_name}.asd"]),
        Path.join([cwd, "examples", sys_name, "#{sys_name}.asd"])
      ]

    case Enum.find(candidates, &File.exists?/1) do
      nil -> :error
      found -> {:ok, Path.expand(found)}
    end
  end

  defp load_local_asd_system(asd_path, sys_name, systems_map, releases_map, opts) do
    sys_defs = ExLisp.ASDF.parse_asd(asd_path)

    primary_sys_def =
      case Map.get(sys_defs, sys_name) do
        nil ->
          case Map.values(sys_defs) do
            [first | _] -> first
            [] -> %{name: sys_name, depends_on: [], components: [], serial: true}
          end

        found ->
          found
      end

    deps = primary_sys_def.depends_on |> Enum.reject(&skip_dependency?/1)

    Enum.each(deps, fn dep_sys ->
      do_quickload(dep_sys, systems_map, releases_map, opts)
    end)

    asd_dir = Path.dirname(asd_path)
    ExLisp.ASDF.load_system(primary_sys_def, asd_dir)
    mark_system_loaded(sys_name)
    [sys_name]
  end

  defp lookup_system_entry(systems_map, sys_name) do
    candidates =
      [
        sys_name,
        String.replace(sys_name, "_", "-"),
        String.replace(sys_name, "-", "_")
      ]
      |> Enum.uniq()

    Enum.find_value(candidates, fn k -> Map.get(systems_map, k) end)
  end

  defp lookup_sys_def(sys_defs, sys_name, project_name) do
    candidates =
      [
        sys_name,
        String.replace(sys_name, "_", "-"),
        String.replace(sys_name, "-", "_"),
        project_name,
        String.replace(project_name, "_", "-"),
        String.replace(project_name, "-", "_")
      ]
      |> Enum.uniq()

    Enum.find_value(candidates, fn k -> Map.get(sys_defs, k) end)
  end

  defp skip_dependency?(dep) do
    d = String.downcase(to_string(dep))
    d in ["asdf", "sb-rt", "rt", "sb-bsd-sockets", "uiop"]
  end

  defp ensure_project_installed(%{url: url, prefix: prefix}) do
    File.mkdir_p!(archive_dir())
    File.mkdir_p!(software_dir())

    target_dir = Path.join(software_dir(), prefix)

    if not File.dir?(target_dir) do
      archive_filename = Path.basename(url)
      archive_path = Path.join(archive_dir(), archive_filename)

      # Download
      if not File.exists?(archive_path) do
        download_file(url, archive_path)
      end

      # Extract
      extract_archive(archive_path, software_dir())
    end

    target_dir
  end

  defp download_file(url, target_path) do
    # Download using curl
    case System.cmd("curl", ["-sSL", "-o", target_path, url]) do
      {_, 0} ->
        :ok

      {err, code} ->
        raise RuntimeError, "Failed to download #{url} (exit #{code}): #{err}"
    end
  end

  defp extract_archive(archive_path, dest_dir) do
    # Extract with :erl_tar or tar command
    char_archive = String.to_charlist(archive_path)
    char_dest = String.to_charlist(dest_dir)

    case :erl_tar.extract(char_archive, [:compressed, {:cwd, char_dest}]) do
      :ok ->
        :ok

      _error ->
        case System.cmd("tar", ["-xzf", archive_path, "-C", dest_dir]) do
          {_, 0} ->
            :ok

          {err, code} ->
            raise RuntimeError,
                  "Failed to extract #{archive_path} (exit #{code}): #{err}"
        end
    end
  end

  defp find_asd_file(install_path, asd_filename, sys_name) do
    candidates = [
      Path.join(install_path, "#{asd_filename}.asd"),
      Path.join(install_path, asd_filename),
      Path.join(install_path, "#{sys_name}.asd")
    ]

    Enum.find(candidates, &File.exists?/1) ||
      case Path.wildcard(Path.join(install_path, "*.asd")) do
        [first | _] -> first
        [] -> nil
      end
  end

  # --- dist metadata management ---

  defp ensure_dist do
    File.mkdir_p!(dist_dir())
    distinfo_file = Path.join(dist_dir(), "quicklisp.txt")
    systems_file = Path.join(dist_dir(), "systems.txt")
    releases_file = Path.join(dist_dir(), "releases.txt")

    if not File.exists?(distinfo_file) or not File.exists?(systems_file) or
         not File.exists?(releases_file) do
      # Fetch quicklisp.txt
      download_file(@distinfo_url, distinfo_file)
      dist_info = parse_distinfo(File.read!(distinfo_file))

      if dist_info["system-index-url"] do
        download_file(dist_info["system-index-url"], systems_file)
      end

      if dist_info["release-index-url"] do
        download_file(dist_info["release-index-url"], releases_file)
      end
    end

    :ok
  end

  defp parse_distinfo(content) do
    content
    |> String.split("\n", trim: true)
    |> Enum.reduce(%{}, fn line, acc ->
      case String.split(line, ~r/:\s*/, parts: 2) do
        [key, val] -> Map.put(acc, String.trim(key), String.trim(val))
        _ -> acc
      end
    end)
  end

  defp load_indices do
    systems_file = Path.join(dist_dir(), "systems.txt")
    releases_file = Path.join(dist_dir(), "releases.txt")

    systems_map =
      File.read!(systems_file)
      |> String.split("\n", trim: true)
      |> Enum.reject(&String.starts_with?(&1, "#"))
      |> Enum.reduce(%{}, fn line, acc ->
        case String.split(line, ~r/\s+/) do
          [proj, file, sys | deps] ->
            Map.put(acc, String.downcase(sys), %{
              project: String.downcase(proj),
              file: file,
              deps: Enum.map(deps, &String.downcase/1)
            })

          _ ->
            acc
        end
      end)

    releases_map =
      File.read!(releases_file)
      |> String.split("\n", trim: true)
      |> Enum.reject(&String.starts_with?(&1, "#"))
      |> Enum.reduce(%{}, fn line, acc ->
        case String.split(line, ~r/\s+/) do
          [proj, url, size, md5, sha1, prefix | sys_files] ->
            Map.put(acc, String.downcase(proj), %{
              url: url,
              size: String.to_integer(size),
              md5: md5,
              sha1: sha1,
              prefix: prefix,
              system_files: sys_files
            })

          _ ->
            acc
        end
      end)

    {systems_map, releases_map}
  end

  # --- Loaded system management (ETS) ---

  defp ensure_loaded_table do
    case :ets.info(@loaded_table) do
      :undefined ->
        try do
          :ets.new(@loaded_table, [:set, :public, :named_table])
        rescue
          _ -> :ok
        end

      _ ->
        :ok
    end
  end

  defp is_system_loaded?(sys_name) do
    ensure_loaded_table()

    candidates =
      [
        sys_name,
        String.replace(sys_name, "_", "-"),
        String.replace(sys_name, "-", "_")
      ]
      |> Enum.uniq()

    Enum.any?(candidates, &:ets.member(@loaded_table, &1))
  end

  defp mark_system_loaded(sys_name) do
    ensure_loaded_table()

    candidates =
      [
        sys_name,
        String.replace(sys_name, "_", "-"),
        String.replace(sys_name, "-", "_")
      ]
      |> Enum.uniq()

    Enum.each(candidates, fn k -> :ets.insert(@loaded_table, {k, true}) end)
  end

  defp normalize_system_name(sys) do
    cond do
      is_atom(sys) ->
        sys |> Atom.to_string() |> String.trim_leading(":") |> String.downcase()

      is_binary(sys) ->
        sys |> String.trim_leading(":") |> String.downcase()

      true ->
        nil
    end
  end
end
