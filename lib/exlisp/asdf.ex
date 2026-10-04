defmodule ExLisp.ASDF do
  @moduledoc """
  Lightweight loader for Common Lisp ASDF (Another System Definition Facility).
  Parses defsystem definitions in `.asd` files, resolves dependencies,
  and loads components (`.lisp` files) in sequential order.
  """

  @doc """
  Parses the specified `.asd` file and returns a map of system definitions.
  """
  def parse_asd(asd_path) do
    content = File.read!(asd_path)

    case ExLisp.LispParser.parse_multiple(content) do
      {:ok, asts} ->
        Enum.reduce(asts, %{}, fn ast, acc ->
          case extract_defsystem(ast) do
            {:ok, sys_info} -> Map.put(acc, sys_info.name, sys_info)
            :error -> acc
          end
        end)

      _ ->
        %{}
    end
  end

  defp extract_defsystem({:list, _pos, [op_node, name_node | rest_args]}) do
    op_name = LispBeam.extract_symbol_name(op_node)

    if op_name in [:defsystem, :"asdf.defsystem", :"asdf:defsystem"] do
      sys_name = normalize_name(name_node)
      opts = parse_defsystem_options(rest_args)

      sys_info = %{
        name: sys_name,
        version: opts[:version],
        depends_on: opts[:depends_on] || [],
        defsystem_depends_on: opts[:defsystem_depends_on] || [],
        components: opts[:components] || [],
        pathname: opts[:pathname],
        serial: opts[:serial] || false
      }

      {:ok, sys_info}
    else
      :error
    end
  end

  defp extract_defsystem(_), do: :error

  defp parse_defsystem_options(args) do
    parse_options_kv(args, %{
      depends_on: [],
      defsystem_depends_on: [],
      components: [],
      serial: false,
      pathname: nil
    })
  end

  defp parse_options_kv([], acc), do: acc

  defp parse_options_kv([k_node, v_node | rest], acc) do
    key =
      case k_node do
        {:lit, k} when is_atom(k) -> k
        {:id, _, [name]} -> String.downcase(name) |> String.to_atom()
        _ -> nil
      end

    case key do
      :depends_on ->
        deps = extract_list_of_names(v_node)
        parse_options_kv(rest, Map.put(acc, :depends_on, deps))

      k when k in [:defsystem_depends_on, :"defsystem-depends-on"] ->
        deps = extract_list_of_names(v_node)
        parse_options_kv(rest, Map.put(acc, :defsystem_depends_on, deps))

      :components ->
        comps = parse_components(v_node)
        parse_options_kv(rest, Map.put(acc, :components, comps))

      :pathname ->
        path_str = normalize_name(v_node)
        parse_options_kv(rest, Map.put(acc, :pathname, path_str))

      :serial ->
        serial_val = v_node in [{:lit, :t}, {:lit, true}, :t, true]
        parse_options_kv(rest, Map.put(acc, :serial, serial_val))

      :version ->
        ver =
          case v_node do
            v when is_binary(v) -> v
            {:lit, v} when is_binary(v) -> v
            _ -> nil
          end

        parse_options_kv(rest, Map.put(acc, :version, ver))

      _ ->
        parse_options_kv(rest, acc)
    end
  end

  defp parse_options_kv([_single | rest], acc), do: parse_options_kv(rest, acc)

  defp extract_list_of_names({:list, _pos, elems}) do
    Enum.flat_map(elems, &extract_single_dep/1)
  end

  defp extract_list_of_names({:quoted, _pos, elems}) do
    extract_list_of_names(elems)
  end

  defp extract_list_of_names(elems) when is_list(elems) do
    Enum.flat_map(elems, &extract_single_dep/1)
  end

  defp extract_list_of_names(single) do
    extract_single_dep(single)
  end

  defp extract_single_dep({:list, _pos, [{:id, _, [op]} | rest]})
       when op in ["feature", "FEATURE", ":feature"] do
    case rest do
      [feat_expr, dep_form | _] ->
        if ExLisp.LispParser.feature_matches?(feat_expr) do
          extract_list_of_names(dep_form)
        else
          []
        end

      _ ->
        []
    end
  end

  defp extract_single_dep({:list, _pos, [{:lit, :feature} | rest]}) do
    case rest do
      [feat_expr, dep_form | _] ->
        if ExLisp.LispParser.feature_matches?(feat_expr) do
          extract_list_of_names(dep_form)
        else
          []
        end

      _ ->
        []
    end
  end

  defp extract_single_dep({:list, _pos, [{:id, _, [op]} | [first | _]]})
       when op in ["require", "REQUIRE", ":require"] do
    case normalize_name(first) do
      nil -> []
      name -> [name]
    end
  end

  defp extract_single_dep({:list, _pos, [{:lit, :require} | [first | _]]}) do
    case normalize_name(first) do
      nil -> []
      name -> [name]
    end
  end

  defp extract_single_dep(node) do
    case normalize_name(node) do
      nil -> []
      "" -> []
      name -> [name]
    end
  end

  defp normalize_name({:list, _pos, [{:id, _, [op]} | [first | _]]})
       when op in ["version", "VERSION", ":version"] do
    normalize_name(first)
  end

  defp normalize_name({:list, _pos, [{:lit, :version} | [first | _]]}) do
    normalize_name(first)
  end

  defp normalize_name([op | [first | _]]) when op in [:version, "version", ":version"] do
    normalize_name(first)
  end

  defp normalize_name({:id, _pos, [name]}), do: String.downcase(name)
  defp normalize_name({:id, _pos, parts}), do: Enum.join(parts, ".") |> String.downcase()
  defp normalize_name({:lit, val}) when is_atom(val), do: Atom.to_string(val) |> String.downcase()
  defp normalize_name({:lit, val}) when is_binary(val), do: String.downcase(val)
  defp normalize_name(val) when is_atom(val), do: Atom.to_string(val) |> String.downcase()
  defp normalize_name(val) when is_binary(val), do: String.downcase(val)
  defp normalize_name(_), do: nil

  defp parse_components({:list, _pos, elems}), do: Enum.flat_map(elems, &parse_single_component/1)

  defp parse_components({:quoted, _pos, elems}),
    do: Enum.flat_map(elems, &parse_single_component/1)

  defp parse_components(elems) when is_list(elems),
    do: Enum.flat_map(elems, &parse_single_component/1)

  defp parse_components(_), do: []

  defp parse_single_component({:list, _pos, [type_node, name_node | rest_opts]}) do
    type_str =
      case type_node do
        {:lit, t} when is_atom(t) -> Atom.to_string(t)
        {:id, _, [t]} -> t
        t when is_atom(t) -> Atom.to_string(t)
        _ -> ""
      end
      |> String.downcase()
      |> String.replace_prefix(":", "")

    name = normalize_name(name_node)
    opts = parse_component_opts(rest_opts)
    path_name = opts[:pathname] || name

    if Map.has_key?(opts, :if_feature) and
         not ExLisp.LispParser.feature_matches?(opts[:if_feature]) do
      []
    else
      cond do
        type_str in ["file", "cl-source-file", "asdf:cl-source-file", "asdf/cl-source-file:cl-source-file", "asdf.cl-source-file"] ->
          [{:file, path_name, opts[:depends_on] || []}]

        type_str in ["module", "asdf:module"] ->
          sub_comps = opts[:components] || []
          [{:module, path_name, sub_comps, opts[:depends_on] || []}]

        true ->
          []
      end
    end
  end

  defp parse_single_component(_), do: []

  defp parse_component_opts(opts_list) do
    parse_component_opts_kv(opts_list, %{depends_on: [], components: []})
  end

  defp parse_component_opts_kv([], acc), do: acc

  defp parse_component_opts_kv([k_node, v_node | rest], acc) do
    key =
      case k_node do
        {:lit, k} when is_atom(k) -> k
        {:id, _, [name]} -> String.downcase(name) |> String.to_atom()
        _ -> nil
      end

    case key do
      :depends_on ->
        deps = extract_list_of_names(v_node)
        parse_component_opts_kv(rest, Map.put(acc, :depends_on, deps))

      :pathname ->
        path_str = normalize_name(v_node)
        parse_component_opts_kv(rest, Map.put(acc, :pathname, path_str))

      k when k in [:if_feature, :"if-feature"] ->
        parse_component_opts_kv(rest, Map.put(acc, :if_feature, v_node))

      :components ->
        comps = parse_components(v_node)
        parse_component_opts_kv(rest, Map.put(acc, :components, comps))

      _ ->
        parse_component_opts_kv(rest, acc)
    end
  end

  defp parse_component_opts_kv([_ | rest], acc), do: parse_component_opts_kv(rest, acc)

  @doc """
  Returns an ordered list of `.lisp` file paths to load from system definition and base directory.
  """
  def get_load_order(system_info) do
    components = system_info.components
    prefix = system_info[:pathname] || ""
    flatten_components(components, prefix)
  end

  defp flatten_components(components, prefix) do
    Enum.flat_map(components, fn
      {:file, name, _deps} ->
        file_name =
          if String.ends_with?(name, ".lisp") or String.ends_with?(name, ".lsp") do
            name
          else
            "#{name}.lisp"
          end

        rel_path = if prefix == "", do: file_name, else: Path.join(prefix, file_name)
        [rel_path]

      {:module, mod_name, sub_comps, _deps} ->
        new_prefix = if prefix == "", do: mod_name, else: Path.join(prefix, mod_name)
        flatten_components(sub_comps, new_prefix)
    end)
  end

  @doc """
  Loads all `.lisp` files in the system sequentially from the base directory.
  """
  def load_system(system_info, base_dir) do
    prev_pkg = ExLisp.Package.current_package()
    files = get_load_order(system_info)

    Enum.each(files, fn rel_file ->
      full_path = Path.join(base_dir, rel_file)

      if File.exists?(full_path) do
        load_lisp_file(full_path)
      else
        # Try without extension, etc.
        alt_path = Path.join(base_dir, String.replace_suffix(rel_file, ".lisp", ""))

        if File.exists?(alt_path) do
          load_lisp_file(alt_path)
        end
      end
    end)

    # Use package in COMMON-LISP-USER if system matches package
    sys_name = system_info.name
    if pkg = ExLisp.Package.find_package(sys_name) do
      try do
        ExLisp.Package.use_package(pkg.name, "COMMON-LISP-USER")
      rescue
        _ -> :ok
      end
    end

    ExLisp.Package.set_current_package(prev_pkg)
    :ok
  end

  @doc """
  Finds the system definition for the given system designator.
  """
  def find_system(system) do
    sys_name = normalize_name(system)

    case ExLisp.Quicklisp.where_is_system(sys_name) do
      nil ->
        cwd = File.cwd!()
        asd_path = Path.join(cwd, "#{sys_name}.asd")

        if File.exists?(asd_path) do
          defs = parse_asd(asd_path)
          Map.get(defs, sys_name) || Map.values(defs) |> List.first()
        else
          nil
        end

      dir ->
        case Path.wildcard(Path.join(dir, "*.asd")) do
          [asd_path | _] ->
            defs = parse_asd(asd_path)
            Map.get(defs, sys_name) || Map.values(defs) |> List.first()

          [] ->
            nil
        end
    end
  end

  @doc """
  Returns the source directory of the specified system.
  """
  def system_source_directory(system) do
    sys_name = normalize_name(system)

    case ExLisp.Quicklisp.where_is_system(sys_name) do
      nil ->
        cwd = File.cwd!()
        if File.exists?(Path.join(cwd, "#{sys_name}.asd")), do: cwd, else: nil

      dir ->
        dir
    end
  end

  @doc """
  Returns the pathname of a file relative to the specified system's source directory.
  """
  def system_relative_pathname(system, rel_path) do
    case system_source_directory(system) do
      nil -> nil
      dir -> Path.join(dir, to_string(rel_path))
    end
  end

  @doc """
  Loads a single `.lisp` source file and evaluates each top-level expression.
  """
  def load_lisp_file(path) do
    content = File.read!(path)

    case ExLisp.LispParser.parse_multiple(content) do
      {:ok, asts} ->
        try do
          LispBeam.evaluate_asts(asts)
        rescue
          _ -> :ok
        end

      _ ->
        :ok
    end

    :ok
  end
end
