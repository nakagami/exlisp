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
        static_defs =
          Enum.reduce(asts, %{}, fn ast, acc ->
            case extract_defsystem(ast) do
              {:ok, sys_info} -> Map.put(acc, sys_info.name, sys_info)
              :error -> acc
            end
          end)

        defs = collect_macro_defsystems(asts, static_defs)
        add_package_inferred_systems(defs, Path.dirname(asd_path))

      {:error, reason} ->
        raise SyntaxError, description: inspect(reason), file: asd_path, line: 1
    end
  end

  defp collect_macro_defsystems(asts, definitions) do
    Process.put(:exlisp_asdf_definitions, definitions)

    try do
      Enum.each(asts, fn
        {:list, _pos, [op | _]} = ast ->
          if LispBeam.extract_symbol_name(op) in [:defmacro, :_cl_defmacro_] do
            ExLisp.Evaluator.eval(ast, %{})
          end

        _ ->
          :ok
      end)

      Enum.each(asts, fn
        {:list, _pos, [op | _]} = ast ->
          op_name = LispBeam.extract_symbol_name(op)

          if ExLisp.Env.has_macro?(op_name) do
            ExLisp.Evaluator.eval(ast, %{})
          end

        _ ->
          :ok
      end)

      Process.get(:exlisp_asdf_definitions, definitions)
    after
      Process.delete(:exlisp_asdf_definitions)
    end
  end

  def capture_defsystem(name_node, rest_args) do
    case extract_defsystem({:list, 1, [{:id, 1, ["defsystem"]}, name_node | rest_args]}) do
      {:ok, system_info} ->
        definitions = Process.get(:exlisp_asdf_definitions, %{})

        Process.put(
          :exlisp_asdf_definitions,
          Map.put(definitions, system_info.name, system_info)
        )

        :t

      :error ->
        :t
    end
  end

  defp add_package_inferred_systems(defs, base_dir) do
    Enum.reduce(defs, defs, fn {name, system}, acc ->
      if system.package_inferred do
        infer_package_systems(acc, name, system, base_dir)
      else
        acc
      end
    end)
  end

  defp infer_package_systems(defs, parent_name, parent, base_dir) do
    candidates =
      Path.wildcard(Path.join(base_dir, "*.lisp")) ++
        Path.wildcard(Path.join([base_dir, "*", "*.lisp"]))

    Enum.reduce(candidates, defs, fn path, acc ->
      relative = Path.relative_to(path, base_dir) |> String.replace_suffix(".lisp", "")

      if valid_inferred_component?(relative) do
        system_name = "#{parent_name}/#{relative}"
        dependencies = infer_package_dependencies(path)

        system = %{
          name: system_name,
          version: parent.version,
          depends_on: dependencies,
          defsystem_depends_on: [],
          components: [{:file, relative, []}],
          pathname: nil,
          serial: false,
          package_inferred: true
        }

        Map.put_new(acc, system_name, system)
      else
        acc
      end
    end)
  end

  defp valid_inferred_component?(relative) do
    parts = Path.split(relative)
    length(parts) <= 2 and not Enum.any?(parts, &(&1 in ["test", "tests", "contrib", "vendor"]))
  end

  defp infer_package_dependencies(path) do
    case ExLisp.LispParser.parse_multiple(File.read!(path)) do
      {:ok, asts} ->
        asts
        |> Enum.find_value([], &package_dependency_form/1)

      {:error, reason} ->
        raise SyntaxError, description: inspect(reason), file: path, line: 1
    end
  end

  defp package_dependency_form({:list, _, [op | options]}) do
    op = LispBeam.extract_symbol_name(op)

    if op in [:defpackage, :define_package, :"uiop:define-package", :"uiop.define-package"] do
      options
      |> Enum.flat_map(fn
        {:list, _, [kind | names]} ->
          key = LispBeam.extract_symbol_name(kind)

          cond do
            key in [:use, :use_reexport, :"use-reexport"] ->
              extract_list_of_names(names)

            key in [
              :import_from,
              :"import-from",
              :shadowing_import_from,
              :"shadowing-import-from"
            ] ->
              extract_list_of_names(Enum.take(names, 1))

            true ->
              []
          end

        _ ->
          []
      end)
      |> Enum.reject(&(&1 in ["common_lisp", "common-lisp", "cl"]))
    else
      []
    end
  end

  defp package_dependency_form(_), do: []

  defp extract_defsystem({:list, _pos, [op_node, name_node | rest_args]}) do
    op_name = LispBeam.extract_symbol_name(op_node)

    if op_name in [:defsystem, :"asdf.defsystem", :"asdf:defsystem"] do
      sys_name = normalize_name(name_node)
      previous = Process.get(:exlisp_asdf_backend_system)
      Process.put(:exlisp_asdf_backend_system, sys_name)

      opts =
        try do
          parse_defsystem_options(rest_args)
        after
          if previous,
            do: Process.put(:exlisp_asdf_backend_system, previous),
            else: Process.delete(:exlisp_asdf_backend_system)
        end

      sys_info = %{
        name: sys_name,
        version: opts[:version],
        depends_on: opts[:depends_on] || [],
        defsystem_depends_on: opts[:defsystem_depends_on] || [],
        components: opts[:components] || [],
        pathname: opts[:pathname],
        serial: opts[:serial] || false,
        package_inferred:
          opts[:class] in [
            "package-inferred-system",
            "package_inferred_system",
            "asdf:package-inferred-system",
            "asdf:package_inferred_system"
          ]
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
      pathname: nil,
      class: nil
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

      :class ->
        parse_options_kv(rest, Map.put(acc, :class, normalize_name(v_node)))

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

  defp normalize_name({:id, _pos, names}),
    do:
      Enum.map_join(names, ".", &to_string/1)
      |> String.replace(~r/^#:UNINTERNED_\d+_/i, "")
      |> String.downcase()

  defp normalize_name({:lit, val}) when is_atom(val), do: Atom.to_string(val) |> String.downcase()
  defp normalize_name({:lit, val}) when is_binary(val), do: String.downcase(val)
  defp normalize_name({:lit, val}), do: normalize_name(val)

  defp normalize_name(%ExLisp.Pathname{} = pathname) do
    pathname |> ExLisp.Pathname.namestring() |> String.trim_trailing("/")
  end

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
         not asdf_feature_matches?(opts[:if_feature]) do
      []
    else
      cond do
        type_str in [
          "file",
          "cl-source-file",
          "asdf:cl-source-file",
          "asdf/cl-source-file:cl-source-file",
          "asdf.cl-source-file"
        ] ->
          [{:file, path_name, opts[:depends_on] || []}]

        type_str in ["module", "asdf:module"] ->
          sub_comps =
            opts[:components]
            |> then(fn components ->
              if opts[:serial],
                do: add_serial_component_dependencies(components),
                else: components
            end)

          [{:module, path_name, sub_comps, opts[:depends_on] || []}]

        true ->
          []
      end
    end
  end

  defp parse_single_component(_), do: []

  defp asdf_feature_matches?(feature) do
    ExLisp.LispParser.feature_matches?(feature) or
      (Process.get(:exlisp_asdf_backend_system) in [
         "bordeaux-threads",
         "bordeaux_threads",
         "bordeaux-threads/test",
         "bordeaux_threads/test"
       ] and feature_includes_sbcl?(feature))
  end

  defp feature_includes_sbcl?({:id, _pos, names}),
    do: Enum.any?(names, &(String.downcase(to_string(&1)) in ["sbcl", ":sbcl"]))

  defp feature_includes_sbcl?({:lit, atom}),
    do: String.downcase(to_string(atom)) in ["sbcl", ":sbcl"]

  defp feature_includes_sbcl?(_), do: false

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

      :serial ->
        serial_val = v_node in [{:lit, :t}, {:lit, true}, :t, true]
        parse_component_opts_kv(rest, Map.put(acc, :serial, serial_val))

      _ ->
        parse_component_opts_kv(rest, acc)
    end
  end

  defp parse_component_opts_kv([_ | rest], acc), do: parse_component_opts_kv(rest, acc)

  defp add_serial_component_dependencies(components) do
    components
    |> Enum.reduce({[], nil}, fn component, {result, previous_name} ->
      component =
        if previous_name do
          case component do
            {:file, name, deps} ->
              {:file, name, Enum.uniq(deps ++ [previous_name])}

            {:module, name, subcomponents, deps} ->
              {:module, name, subcomponents, Enum.uniq(deps ++ [previous_name])}
          end
        else
          component
        end

      {result ++ [component], component |> normalize_component_name()}
    end)
    |> elem(0)
  end

  @doc """
  Returns an ordered list of `.lisp` file paths to load from system definition and base directory.
  """
  def get_load_order(system_info) do
    prefix = system_info[:pathname] || ""

    {nodes, aliases} =
      collect_component_nodes(
        system_info.components,
        prefix,
        Map.get(system_info, :serial, false)
      )

    topological_component_order(nodes, aliases)
  end

  defp collect_component_nodes(components, prefix, serial) do
    {groups, aliases} =
      Enum.map_reduce(components, %{}, fn component, aliases ->
        {nodes, aliases, name_ids} =
          collect_single_component(component, prefix, aliases)

        aliases =
          Map.update(
            aliases,
            normalize_component_name(component),
            name_ids,
            &Enum.uniq(&1 ++ name_ids)
          )

        {{nodes, name_ids}, aliases}
      end)

    groups = add_serial_dependencies(groups, serial)
    {Enum.flat_map(groups, &elem(&1, 0)), aliases}
  end

  defp collect_single_component({:file, name, deps}, prefix, aliases) do
    file_name =
      if String.ends_with?(name, ".lisp") or String.ends_with?(name, ".lsp"),
        do: name,
        else: "#{name}.lisp"

    path = if prefix == "", do: file_name, else: Path.join(prefix, file_name)
    id = normalize_component_name(path)
    node = %{id: id, path: path, deps: Enum.map(deps, &normalize_name/1)}
    {[node], aliases, [id]}
  end

  defp collect_single_component(
         {:module, name, sub_components, deps},
         prefix,
         aliases
       ) do
    module_prefix = if prefix == "", do: name, else: Path.join(prefix, name)
    {nodes, child_aliases} = collect_component_nodes(sub_components, module_prefix, false)

    aliases =
      Map.merge(aliases, child_aliases, fn _key, left, right -> Enum.uniq(left ++ right) end)

    ids = Enum.map(nodes, & &1.id)
    dependencies = Enum.map(deps, &normalize_name/1)

    nodes =
      case nodes do
        [first | rest] ->
          first = %{first | deps: Enum.uniq(first.deps ++ dependencies)}
          [first | rest]

        [] ->
          []
      end

    {nodes, aliases, ids}
  end

  defp add_serial_dependencies(groups, false), do: groups

  defp add_serial_dependencies(groups, true) do
    groups
    |> Enum.reduce({[], []}, fn {nodes, ids}, {out, previous_ids} ->
      nodes =
        case nodes do
          [first | rest] ->
            [%{first | deps: Enum.uniq(first.deps ++ previous_ids)} | rest]

          [] ->
            []
        end

      {out ++ [{nodes, ids}], ids}
    end)
    |> elem(0)
  end

  defp normalize_component_name({:file, name, _deps}), do: normalize_component_name(name)

  defp normalize_component_name({:module, name, _components, _deps}),
    do: normalize_component_name(name)

  defp normalize_component_name(name) do
    name
    |> normalize_name()
    |> to_string()
    |> String.replace(".lisp", "")
    |> String.replace(".lsp", "")
  end

  defp topological_component_order(nodes, aliases) do
    index = Map.new(nodes, &{&1.id, &1})

    deps_by_id =
      Map.new(nodes, fn node ->
        deps =
          Enum.flat_map(node.deps, fn dep ->
            candidates =
              Map.get(aliases, normalize_component_name(dep), [
                normalize_component_name(dep)
              ])

            local_candidates =
              Enum.filter(candidates, &(Path.dirname(&1) == Path.dirname(node.id)))

            exact_candidates =
              Enum.filter(local_candidates, &(Path.basename(&1) == normalize_component_name(dep)))

            cond do
              exact_candidates != [] -> exact_candidates
              local_candidates != [] -> local_candidates
              true -> candidates
            end
          end)
          |> Enum.filter(&Map.has_key?(index, &1))

        {node.id, Enum.uniq(deps)}
      end)

    topo_component_visit(
      Enum.map(nodes, & &1.id),
      deps_by_id,
      index,
      [],
      MapSet.new(),
      MapSet.new()
    )
    |> Enum.reverse()
    |> Enum.map(&index[&1].path)
  end

  defp topo_component_visit([], _deps, _index, order, _visiting, _visited), do: order

  defp topo_component_visit([id | rest], deps, index, order, visiting, visited) do
    if MapSet.member?(visited, id) do
      topo_component_visit(rest, deps, index, order, visiting, visited)
    else
      {order, visiting, visited} =
        topo_component_visit_one(id, deps, index, order, visiting, visited)

      topo_component_visit(rest, deps, index, order, visiting, visited)
    end
  end

  defp topo_component_visit_one(id, deps, index, order, visiting, visited) do
    cond do
      MapSet.member?(visited, id) ->
        {order, visiting, visited}

      MapSet.member?(visiting, id) ->
        raise "ASDF component dependency cycle involving #{inspect(id)}"

      true ->
        visiting = MapSet.put(visiting, id)

        {order, visiting, visited} =
          Enum.reduce(Map.get(deps, id, []), {order, visiting, visited}, fn dep, {o, v, d} ->
            topo_component_visit_one(dep, deps, index, o, v, d)
          end)

        {[id | order], MapSet.delete(visiting, id), MapSet.put(visited, id)}
    end
  end

  @doc """
  Loads all `.lisp` files in the system sequentially from the base directory.
  """
  def load_system(system_info, base_dir) do
    prev_pkg = ExLisp.Package.current_package()
    files = get_load_order(system_info)

    try do
      with_system_load_features(system_info, fn ->
        Enum.each(files, fn rel_file ->
          full_path = Path.join(base_dir, rel_file)

          if File.exists?(full_path) do
            load_lisp_file(full_path)
          else
            alt_path = Path.join(base_dir, String.replace_suffix(rel_file, ".lisp", ""))

            if File.exists?(alt_path) do
              load_lisp_file(alt_path)
            else
              raise "ASDF component file not found: #{full_path}"
            end
          end
        end)
      end)

      sys_name = system_info.name

      if pkg = ExLisp.Package.find_package(String.upcase(sys_name)) do
        ExLisp.Package.use_package(pkg.name, "COMMON-LISP-USER")
      end

      :ok
    after
      ExLisp.Package.set_current_package(prev_pkg)
    end
  end

  defp with_system_load_features(system_info, fun) do
    if normalize_system_family(system_info.name) in [
         "bordeaux-threads",
         "trivial-garbage"
       ] do
      features = ExLisp.Env.get_var(:features)
      ExLisp.Env.with_special_bindings([features: Enum.uniq(features ++ [:sbcl])], fun)
    else
      fun.()
    end
  end

  defp normalize_system_family(name) do
    name |> String.replace("_", "-") |> String.downcase()
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
    ExLisp.load_file(path)
  end
end
