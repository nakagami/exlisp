defmodule ExLisp.Closure do
  @moduledoc """
  ExLisp closure and variadic function struct.
  Wraps functions with lambda list keywords like &optional, &rest, &key,
  enabling accurate argument dispatch.
  """
  defstruct [:fun, variadic: true, name: nil, ast: nil, env: nil, params: nil, body: nil, compiled: false]

  def new(fun, name \\ nil, opts \\ [])

  def new(fun, name, compiled) when is_function(fun, 1) and is_boolean(compiled) do
    new(fun, name, compiled: compiled)
  end

  def new(fun, name, opts) when is_function(fun, 1) and is_list(opts) do
    %__MODULE__{
      fun: fun,
      variadic: true,
      name: name,
      ast: Keyword.get(opts, :ast),
      env: Keyword.get(opts, :env),
      params: Keyword.get(opts, :params),
      body: Keyword.get(opts, :body),
      compiled: Keyword.get(opts, :compiled, false)
    }
  end

  defimpl Inspect do
    def inspect(%ExLisp.Closure{name: nil, compiled: true}, _opts) do
      "#<COMPILED-FUNCTION (LAMBDA)>"
    end

    def inspect(%ExLisp.Closure{name: name, compiled: true}, _opts) do
      "#<COMPILED-FUNCTION #{name}>"
    end

    def inspect(%ExLisp.Closure{name: nil}, _opts) do
      "#<CLOSURE (LAMBDA) {VARIADIC}>"
    end

    def inspect(%ExLisp.Closure{name: name}, _opts) do
      "#<CLOSURE #{name} {VARIADIC}>"
    end
  end
end
