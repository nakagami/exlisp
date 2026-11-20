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
