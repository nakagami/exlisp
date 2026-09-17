defmodule ExLisp.Closure do
  @moduledoc """
  ExLisp closure and variadic function struct.
  Wraps functions with lambda list keywords like &optional, &rest, &key,
  enabling accurate argument dispatch.
  """
  defstruct [:fun, variadic: true, name: nil]

  def new(fun, name \\ nil) when is_function(fun, 1) do
    %__MODULE__{fun: fun, variadic: true, name: name}
  end

  defimpl Inspect do
    def inspect(%ExLisp.Closure{name: nil}, _opts) do
      "#<CLOSURE (LAMBDA) {VARIADIC}>"
    end

    def inspect(%ExLisp.Closure{name: name}, _opts) do
      "#<CLOSURE #{name} {VARIADIC}>"
    end
  end
end
