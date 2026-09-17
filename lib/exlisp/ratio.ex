defmodule ExLisp.Ratio do
  @moduledoc """
  Struct representing rational numbers (fractions) in ExLisp.
  """

  defstruct [:numerator, :denominator]

  @type t :: %__MODULE__{
          numerator: integer(),
          denominator: pos_integer()
        }

  @doc """
  Creates a reduced fraction from numerator and denominator.
  Returns an integer when denominator is 1.
  Raises ArithmeticError when denominator is 0.
  """
  def new(_num, 0) do
    raise ArithmeticError, "division by zero"
  end

  def new(0, _den) do
    0
  end

  def new(num, den) when is_integer(num) and is_integer(den) do
    {n, d} = if den < 0, do: {-num, -den}, else: {num, den}
    g = Integer.gcd(abs(n), d)
    n_reduced = div(n, g)
    d_reduced = div(d, g)

    if d_reduced == 1 do
      n_reduced
    else
      %__MODULE__{numerator: n_reduced, denominator: d_reduced}
    end
  end

  @doc """
  Addition.
  """
  def add(a, b) do
    {an, ad} = to_fraction(a)
    {bn, bd} = to_fraction(b)
    new(an * bd + bn * ad, ad * bd)
  end

  @doc """
  Subtraction.
  """
  def sub(a, b) do
    {an, ad} = to_fraction(a)
    {bn, bd} = to_fraction(b)
    new(an * bd - bn * ad, ad * bd)
  end

  @doc """
  Multiplication.
  """
  def mul(a, b) do
    {an, ad} = to_fraction(a)
    {bn, bd} = to_fraction(b)
    new(an * bn, ad * bd)
  end

  @doc """
  Division.
  """
  def divide(a, b) do
    {an, ad} = to_fraction(a)
    {bn, bd} = to_fraction(b)
    new(an * bd, ad * bn)
  end

  @doc """
  Negation.
  """
  def negate(%__MODULE__{numerator: n, denominator: d}) do
    %__MODULE__{numerator: -n, denominator: d}
  end

  def negate(n) when is_integer(n), do: -n

  @doc """
  Converts to float.
  """
  def to_float(%__MODULE__{numerator: n, denominator: d}), do: n / d
  def to_float(x) when is_number(x), do: x * 1.0

  @doc """
  Converts to a `{numerator, denominator}` tuple.
  """
  def to_fraction(%__MODULE__{numerator: n, denominator: d}), do: {n, d}
  def to_fraction(n) when is_integer(n), do: {n, 1}

  defimpl Inspect do
    def inspect(%ExLisp.Ratio{numerator: num, denominator: den}, _opts) do
      "#{num}/#{den}"
    end
  end

  defimpl String.Chars do
    def to_string(%ExLisp.Ratio{numerator: num, denominator: den}) do
      "#{num}/#{den}"
    end
  end
end
