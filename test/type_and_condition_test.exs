defmodule ExLisp.TypeAndConditionTest do
  use ExUnit.Case

  setup do
    ExLisp.Env.reset()
    ExLisp.CLOS.reset()
    ExLisp.Condition.init_condition_hierarchy()
    :ok
  end

  describe "Type system and COERCE" do
    test "coerce sequence between list, vector, string, bit-vector" do
      assert ExLisp.eval("(coerce '(1 2 3) 'vector)") |> ExLisp.Builtins.seq_to_list() == [1, 2, 3]
      assert ExLisp.eval("(coerce #(1 2 3) 'list)") == [1, 2, 3]
      assert ExLisp.eval("(coerce '(#\\a #\\b #\\c) 'string)") == "abc"
      assert ExLisp.eval("(coerce \"xyz\" 'list)") == [
               ExLisp.Character.new(?x),
               ExLisp.Character.new(?y),
               ExLisp.Character.new(?z)
             ]
      assert ExLisp.eval("(equal (coerce '(1 0 1) 'bit-vector) #*101)") == :t
    end

    test "coerce numbers to float, complex and characters" do
      assert ExLisp.eval("(coerce 42 'float)") == 42.0
      assert ExLisp.eval("(coerce 10 'complex)") == {:complex, 10, 0}
      assert ExLisp.eval("(coerce 65 'character)") == ExLisp.Character.new(65)
    end

    test "coerce symbol to function" do
      result = ExLisp.eval("(funcall (coerce '+ 'function) 10 20)")
      assert result == 30
    end

    test "upgraded-array-element-type and upgraded-complex-part-type" do
      assert ExLisp.eval("(upgraded-array-element-type 'base-char)") == :character
      assert ExLisp.eval("(upgraded-array-element-type 'bit)") == :bit
      assert ExLisp.eval("(upgraded-complex-part-type 'single-float)") == :single_float
      assert ExLisp.eval("(upgraded-complex-part-type 'integer)") == :rational
    end

    test "deftype and subtypep" do
      ExLisp.eval("""
      (deftype byte8 () '(unsigned-byte 8))
      """)

      assert ExLisp.eval("(typep 255 'byte8)") == :t
      assert ExLisp.eval("(typep 256 'byte8)") == nil
      assert ExLisp.eval("(multiple-value-list (subtypep 'byte8 'integer))") == [:t, :t]
    end

    test "typecase and etypecase" do
      result1 =
        ExLisp.eval("""
        (typecase 42
          (string "str")
          (integer "int")
          (t "other"))
        """)

      assert result1 == "int"

      result2 =
        ExLisp.eval("""
        (etypecase "hello"
          (integer 1)
          (string 2))
        """)

      assert result2 == 2
    end
  end

  describe "Condition system and accessors" do
    test "make-condition and slot accessors" do
      ExLisp.eval("""
      (defparameter *err*
        (make-condition 'type-error :datum 42 :expected-type 'string))
      """)

      assert ExLisp.eval("(type-error-datum *err*)") == 42
      assert ExLisp.eval("(type-error-expected-type *err*)") == :string
    end

    test "cell-error and unbound-variable accessors" do
      ExLisp.eval("""
      (defparameter *cell-err*
        (make-condition 'unbound-variable :name 'foo))
      """)

      assert ExLisp.eval("(cell-error-name *cell-err*)") == :foo
    end

    test "file-error and stream-error accessors" do
      ExLisp.eval("""
      (defparameter *f-err*
        (make-condition 'file-error :pathname "/path/to/file"))
      """)

      assert ExLisp.eval("(file-error-pathname *f-err*)") == "/path/to/file"
    end

    test "arithmetic-error accessors" do
      ExLisp.eval("""
      (defparameter *a-err*
        (make-condition 'division-by-zero :operation '/ :operands '(10 0)))
      """)

      assert ExLisp.eval("(arithmetic-error-operation *a-err*)") == :/
      assert ExLisp.eval("(arithmetic-error-operands *a-err*)") == [10, 0]
    end

    test "handler-case and type-error handling" do
      result =
        ExLisp.eval("""
        (handler-case
            (error (make-condition 'type-error :datum 100 :expected-type 'list))
          (type-error (c)
            (list (type-error-datum c)
                  (type-error-expected-type c))))
        """)

      assert result == [100, :list]
    end

    test "restart-case and invoke-restart" do
      result =
        ExLisp.eval("""
        (restart-case
            (invoke-restart 'use-value 999)
          (use-value (v) v))
        """)

      assert result == 999
    end

    test "cerror and continue restart" do
      result =
        ExLisp.eval("""
        (handler-bind ((error (lambda (c) (continue c))))
          (cerror "Keep going" "Something happened")
          :resumed)
        """)

      assert result == :resumed
    end

    test "define-condition with inheritance and custom report" do
      ExLisp.eval("""
      (define-condition my-custom-error (error)
        ((code :initarg :code :reader my-code)))
      """)

      result =
        ExLisp.eval("""
        (handler-case
            (error (make-condition 'my-custom-error :code 404))
          (my-custom-error (c) :caught))
        """)

      assert result == :caught
    end
  end
end
