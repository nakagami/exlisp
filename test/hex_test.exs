defmodule HexTest do
  use ExUnit.Case
  @moduletag timeout: 180_000

  test "Hex.pm search and info" do
    # hex:search
    results = ExLisp.eval(~s|(hex:search "jason")|)
    assert is_list(results)
    assert Enum.any?(results, fn sym -> to_string(sym) == "JASON" end)

    # hex:info
    info = ExLisp.eval(~s|(hex:info :jason)|)
    assert is_list(info)

    assert Enum.any?(info, fn
             [key, val] -> to_string(key) == "NAME" and val == "jason"
             _ -> false
           end)
  end

  test "Hex.pm dynamic install and use library" do
    # Install jason library
    jason_res = ExLisp.eval(~s|(hex:install :jason "~> 1.4")|)
    assert is_list(jason_res)
    assert Enum.map(jason_res, &to_string/1) == ["Jason"]

    # Verify Jason is callable from ExLisp
    assert ExLisp.eval(~s|(Jason.encode! [1 2 3])|) == "[1,2,3]"

    # Verify where-is-package
    assert ExLisp.eval(~s|(hex:where-is-package :jason)|) != nil

    # Install multiple libraries or library without version
    floki_res = ExLisp.eval(~s|(hex:install :floki)|)
    assert is_list(floki_res)
    assert Enum.map(floki_res, &to_string/1) == ["Floki"]
    assert ExLisp.eval(~s|(Floki.parse_document! "<p>hello</p>")|) != nil
  end
end
