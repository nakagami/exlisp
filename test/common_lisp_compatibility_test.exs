defmodule ExLisp.CommonLispCompatibilityTest do
  use ExUnit.Case

  setup do
    ExLisp.Env.reset()
    :ok
  end

  test "floating-point CL functions match double-float semantics" do
    assert ExLisp.eval("(multiple-value-list (ffloor -3.5 2))") == [-2.0, 0.5]
    assert ExLisp.eval("(multiple-value-list (fceiling -3.5 2))") == [-1.0, -1.5]
    assert ExLisp.eval("(multiple-value-list (fround 2.5))") == [2.0, 0.5]
    assert ExLisp.eval("(multiple-value-list (ftruncate -3.5 2))") == [-1.0, -1.5]

    assert ExLisp.eval("(multiple-value-list (decode-float 6.0))") == [0.75, 3, 1.0]

    assert ExLisp.eval("(multiple-value-list (integer-decode-float 6.0))") ==
             [6_755_399_441_055_744, -50, 1]

    assert ExLisp.eval("(list (float-radix 1.0) (float-digits 1.0))") == [2, 53]
    assert ExLisp.eval("(float-precision 0.0)") == 0
    assert ExLisp.eval("(scale-float 1.5 3)") == 12.0
    assert ExLisp.eval("(float-sign -1.0 2.5)") == -2.5
  end

  test "rationalize and standard floating-point constants are available" do
    assert ExLisp.eval("(rationalize 0.5)") == ExLisp.Ratio.new(1, 2)
    assert ExLisp.eval("(rationalize 0.1)") == ExLisp.Ratio.new(1, 10)
    assert ExLisp.eval("(> most-positive-double-float 1.0)") == :t
    assert ExLisp.eval("(> double-float-epsilon 0.0)") == :t
  end

  test "floating-point signs are preserved for signed zero" do
    assert ExLisp.eval("(float-sign -0.0 2.0)") == -2.0
    assert ExLisp.eval("(multiple-value-list (decode-float -0.0))") == [0.0, 0, -1.0]
  end

  test "define-symbol-macro expands in expressions and setf places" do
    code = """
    (progn
      (defparameter *symbol-macro-target* 0)
      (define-symbol-macro counter *symbol-macro-target*)
      (list counter
            (incf counter)
            (let ((counter 7)) counter)
            (progn (setf counter 9) *symbol-macro-target*)))
    """

    assert ExLisp.eval(code) == [0, 1, 7, 9]
  end

  test "load-time-value is evaluated once when a closure is created" do
    ExLisp.eval("(defparameter *load-time-count* 0)")

    code = """
    (progn
      (defun loaded-value ()
        (load-time-value (incf *load-time-count*)))
      (list (loaded-value) (loaded-value) *load-time-count*))
    """

    assert ExLisp.eval(code) == [1, 1, 1]
  end

  test "load-time-value is prepared before repeated runtime evaluation" do
    ExLisp.eval("(defparameter *loop-load-count* 0)")

    code = """
    (progn
      (dotimes (i 3)
        (load-time-value (incf *loop-load-count*)))
      *loop-load-count*)
    """

    assert ExLisp.eval(code) == 1
  end

  test "compiler macros can be defined and retrieved" do
    code = """
    (progn
      (define-compiler-macro compatibility-fold (x) (if (numberp x) (* x 2) x))
      (list (compiler-macro-function 'compatibility-fold)
            (functionp (compiler-macro-function 'compatibility-fold))))
    """

    [macro, predicate] = ExLisp.eval(code)
    assert is_function(macro) or match?(%ExLisp.Closure{}, macro)
    assert predicate == :t
  end

  test "compiled code honors symbol macros and load-time values" do
    ExLisp.eval("""
    (progn
      (defparameter *compiled-load-count* 0)
      (define-symbol-macro compiled-global-value 41))
    """)

    {:ok, module, _binary} =
      ExLisp.Compiler.compile_string(
        """
        (defun compiled-symbol-value () (1+ compiled-global-value))
        (defun compiled-load-value ()
          (load-time-value (incf *compiled-load-count*)))
        """,
        module: CompatibilityCompiledModule,
        write_beam: false
      )

    assert apply(module, :compiled_symbol_value, []) == 42
    assert apply(module, :compiled_load_value, []) == 1
    assert apply(module, :compiled_load_value, []) == 1
    assert ExLisp.eval("*compiled-load-count*") == 1
  end

  test "compiler macros participate in BEAM compilation" do
    {:ok, module, _binary} =
      ExLisp.Compiler.compile_string(
        """
        (defun expanded-add (x) (+ x 1))
        (define-compiler-macro expanded-add (x) `(* ,x 10))
        (defun use-expanded-add () (expanded-add 4))
        (defun local-expansion-shadow ()
          (flet ((expanded-add (x) (+ x 1)))
            (expanded-add 4)))
        """,
        module: CompatibilityCompilerMacroModule,
        write_beam: false
      )

    assert apply(module, :use_expanded_add, []) == 40
    assert apply(module, :local_expansion_shadow, []) == 5
  end

  test "standard string conversion functions distinguish prin1 and princ" do
    assert ExLisp.eval(~s|(prin1-to-string "hello")|) == ~s|"hello"|
    assert ExLisp.eval(~s|(princ-to-string "hello")|) == "hello"
    assert ExLisp.eval("(princ-to-string 'some-symbol)") == "SOME_SYMBOL"
  end

  test "standard pathname file operations create rename and delete files" do
    root =
      Path.join(
        System.tmp_dir!(),
        "exlisp-cl-compat-#{System.unique_integer([:positive, :monotonic])}"
      )

    on_exit(fn -> File.rm_rf(root) end)

    path = Path.join(root, "nested/original.txt")
    renamed = Path.join(root, "nested/renamed.txt")

    [ensured_path, created] =
      ExLisp.eval("(multiple-value-list (ensure-directories-exist #{inspect(path)}))")

    assert ExLisp.Pathname.namestring(ensured_path) == path
    assert created == :t

    File.write!(path, "content")

    [new_path, old_path, new_true] =
      ExLisp.eval(
        "(multiple-value-list (rename-file #{inspect(path)} #{inspect(renamed)}))"
      )

    assert ExLisp.Pathname.namestring(new_path) == renamed
    assert ExLisp.Pathname.namestring(old_path) == path
    assert ExLisp.Pathname.namestring(new_true) == renamed
    assert File.read!(renamed) == "content"
    assert ExLisp.eval("(delete-file #{inspect(renamed)})") == :t
    refute File.exists?(renamed)
  end
end
