defmodule ExLisp.PackageIterationLogicalPathnameTest do
  use ExUnit.Case, async: false

  test "package iteration observes present and inherited symbols" do
    name = "ITERATION-TEST-#{System.unique_integer([:positive])}"
    package = ExLisp.Package.make_package(name, use: [])
    ExLisp.Package.intern("LOCAL", package)
    ExLisp.Package.export("VISIBLE", package)

    on_exit(fn -> ExLisp.Package.delete_package(name) end)

    symbols = []
    {:ok, agent} = Agent.start_link(fn -> symbols end)

    assert :done ==
             ExLisp.Package.do_symbols(
               package,
               fn symbol, status ->
                 Agent.update(agent, &[{symbol, status} | &1])
               end,
               :done
             )

    assert {:local, :internal} in Agent.get(agent, & &1)
    assert {:visible, :external} in Agent.get(agent, & &1)

    iterator = ExLisp.Package.package_iterator(package, [:external])
    assert [:_values_, [:t, :visible, :external, _]] = iterator.()
    assert [:_values_, [nil, nil, nil, nil]] = iterator.()
    assert :visible in ExLisp.Package.find_all_symbols("VISIBLE")
  end

  test "symbol home lookup cache invalidates after package changes" do
    suffix = System.unique_integer([:positive])
    first = "CACHE-A-#{suffix}"
    second = "CACHE-B-#{suffix}"
    symbol = "CACHED-SYMBOL-#{suffix}"
    package_a = ExLisp.Package.make_package(first, use: [])
    package_b = ExLisp.Package.make_package(second, use: [])

    on_exit(fn ->
      ExLisp.Package.delete_package(first)
      ExLisp.Package.delete_package(second)
    end)

    ExLisp.Package.intern(symbol, package_a)
    ExLisp.Package.intern(symbol, package_b)

    assert [:_values_, [qualified, :internal]] = ExLisp.Package.intern(symbol, package_a)

    expected_symbol = String.downcase(symbol) |> String.replace("-", "_")
    assert Atom.to_string(qualified) == "#{String.downcase(first)}.#{expected_symbol}"
  end

  test "closures fall back to their definition package when the caller package is deleted" do
    name = "DELETED-CALLER-#{System.unique_integer([:positive])}"
    ExLisp.Package.make_package(name, use: [])
    ExLisp.Package.set_current_package(name)

    closure =
      ExLisp.Closure.new(
        fn _args ->
          ExLisp.Package.delete_package(name)
          :ok
        end,
        :delete_caller_package,
        package: "COMMON-LISP-USER"
      )

    assert ExLisp.Builtins.invoke_fn(closure, []) == :ok
    assert ExLisp.Package.current_package() == "COMMON-LISP-USER"
  end

  test "logical pathnames retain hosts and apply translations" do
    pathname = ExLisp.Pathname.pathname("SYS:SRC;**;*.LISP")

    assert pathname.host == "SYS"
    assert pathname.directory == [:absolute, "SRC", :wild_inferiors]
    assert ExLisp.Pathname.namestring(pathname) == "SYS:SRC;**;*.LISP"
    assert ExLisp.Pathname.logical_pathname_p(pathname) == :t

    ExLisp.Pathname.logical_pathname_translations("SYS", [
      {"SYS:SRC;**;*.LISP", "/project/lib/**/*.ex"}
    ])

    assert ExLisp.Pathname.namestring(
             ExLisp.Pathname.translate_logical_pathname("SYS:SRC;CORE;PACKAGE;ITERATOR.LISP")
           ) == "/project/lib/CORE/PACKAGE/ITERATOR.ex"
  end

  test "translate-pathname substitutes wildcard components" do
    translated =
      ExLisp.Pathname.translate_pathname(
        "/src/parser/token.lisp",
        "/src/*/*.lisp",
        "/build/*/*.beam"
      )

    assert ExLisp.Pathname.namestring(translated) == "/build/parser/token.beam"
  end
end
