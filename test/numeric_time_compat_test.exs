defmodule ExLisp.NumericTimeCompatTest do
  use ExUnit.Case, async: true

  alias ExLisp.Builtins

  test "byte accessors and byte-field operations follow Common Lisp semantics" do
    bytespec = Builtins.byte(4, 4)

    assert Builtins.byte_size(bytespec) == 4
    assert Builtins.byte_position(bytespec) == 4
    assert Builtins.ldb_test(bytespec, 0xA50) == :t
    assert Builtins.ldb_test(bytespec, 0x05) == nil
    assert Builtins.mask_field(bytespec, 0xABCD) == 0xC0
    assert Builtins.deposit_field(0x2D, bytespec, 0xABCD) == 0xAB2D
  end

  test "universal time round trips in a fixed timezone" do
    universal =
      Builtins.encode_universal_time(30, 45, 12, 17, 6, 2020, -5.5)

    assert Builtins.decode_universal_time(universal, -5.5) ==
             [:_values_, [30, 45, 12, 17, 6, 2020, 2, nil, -5.5]]

    assert Builtins.encode_universal_time(
             30,
             45,
             12,
             17,
             6,
             2020,
             0
           ) == 3_801_386_730
  end

  test "internal clocks use the advertised unit" do
    assert Builtins.internal_time_units_per_second() == 1_000_000
    assert is_integer(Builtins.get_internal_real_time())
    assert is_integer(Builtins.get_internal_run_time())
  end
end
