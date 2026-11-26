defmodule ExLisp.CommonLispCompatibilityTest do
  use ExUnit.Case

  test "Common Lisp exports and default variables are available" do
    ExLisp.Env.reset()

    for name <- [
          "*READ-DEFAULT-FLOAT-FORMAT*",
          "CHAR-CODE-LIMIT",
          "BROADCAST-STREAM-STREAMS",
          "THROW"
        ] do
      assert [:_values_, [_, status]] = ExLisp.Package.find_symbol(name, "COMMON-LISP")
      assert status == :external
    end

    assert ExLisp.eval("*read-default-float-format*") == :single_float
    assert ExLisp.eval("char-code-limit") == 0x110000
  end

  test "package functions do not shadow same-named functions in other packages" do
    ExLisp.Env.reset()

    result =
      ExLisp.eval("""
      (progn
        (defpackage :compat-one (:use :cl) (:export :same-name-probe))
        (defpackage :compat-two (:use :cl) (:export :same-name-probe))
        (in-package :compat-one)
        (defun same-name-probe () 1)
        (in-package :compat-two)
        (defun same-name-probe () 2)
        (in-package :common-lisp-user)
        (list (compat-one:same-name-probe) (compat-two:same-name-probe)))
      """)

    assert result == [1, 2]
    assert_raise RuntimeError, ~r/Undefined function/, fn -> ExLisp.eval("(same-name-probe)") end
  end

  test "UIOP define-package supports use-reexport" do
    ExLisp.Env.reset()

    assert [symbol, :external] =
             ExLisp.eval("""
             (progn
               (defpackage :uiop-source (:use :cl) (:export :shared))
               (uiop:define-package :uiop-consumer
                 (:use :cl)
                 (:use-reexport :uiop-source))
               (multiple-value-list
                 (find-symbol "SHARED" "UIOP-CONSUMER")))
             """)

    assert symbol |> to_string() |> String.ends_with?(".shared")

    assert ExLisp.Package.package_use_list("UIOP-CONSUMER")
           |> Enum.map(& &1.name)
           |> Enum.member?("UIOP-SOURCE")
  end

  test "destructive cons operations update shared list references" do
    ExLisp.Env.reset()

    assert ExLisp.eval("""
           (let ((x (list 1 2))
                 (y nil))
             (setq y x)
             (rplaca x 9)
             (setf (cdr x) (list 3 4))
             (list x y (car x) (cdr x)))
           """) == [[9, 3, 4], [9, 3, 4], 9, [3, 4]]
  end

  test "shared mutable cons scopes become active in other processes" do
    scope = make_ref()
    parent = self()
    ExLisp.MutableCons.set_scope(scope)
    original = [:old]

    resolver =
      spawn(fn ->
        ExLisp.MutableCons.set_scope(scope)
        send(parent, :ready)

        receive do
          :resolve -> send(parent, {:resolved, ExLisp.Builtins.car(original)})
        end
      end)

    assert_receive :ready
    refute Process.get({:exlisp_mutable_cons_active, scope})
    assert ExLisp.Builtins.rplaca(original, :new) == [:new]
    send(resolver, :resolve)
    assert_receive {:resolved, :new}
  end

  test "shared mutable cons scopes observe successive updates across processes" do
    scope = make_ref()
    parent = self()
    ExLisp.MutableCons.set_scope(scope)
    original = [:a]
    assert ExLisp.Builtins.rplaca(original, :b) == [:b]

    child =
      spawn(fn ->
        ExLisp.MutableCons.set_scope(scope)
        send(parent, {:initial, ExLisp.Builtins.car(original)})

        receive do
          :replace -> send(parent, {:replaced, ExLisp.Builtins.rplaca(original, :c)})
        end
      end)

    assert_receive {:initial, :b}
    assert ExLisp.Builtins.rplaca(original, :d) == [:d]
    send(child, :replace)
    assert_receive {:replaced, [:c]}
    assert ExLisp.Builtins.car(original) == :c
  end

  test "shared mutable cons caches do not hide mappings for other cells" do
    scope = make_ref()
    parent = self()
    ExLisp.MutableCons.set_scope(scope)
    first = [:first_original]
    second = [:second_original]
    assert ExLisp.Builtins.rplaca(first, :first_updated) == [:first_updated]

    spawn(fn ->
      ExLisp.MutableCons.set_scope(scope)
      ExLisp.Builtins.rplaca(second, :second_updated)
      send(parent, {:both, ExLisp.Builtins.car(first), ExLisp.Builtins.car(second)})
    end)

    assert_receive {:both, :first_updated, :second_updated}
  end

  test "shared mutable cons reset invalidates mappings cached in other processes" do
    scope = make_ref()
    parent = self()
    ExLisp.MutableCons.set_scope(scope)
    original = [:original]
    assert ExLisp.Builtins.rplaca(original, :updated) == [:updated]

    spawn(fn ->
      ExLisp.MutableCons.set_scope(scope)
      ExLisp.MutableCons.reset()
      other = [:other_original]
      ExLisp.Builtins.rplaca(other, :other_updated)
      send(parent, {:reset, ExLisp.Builtins.car(original), ExLisp.Builtins.car(other)})
    end)

    assert_receive {:reset, :original, :other_updated}
  end

  test "circular cons mutation is observable and list-length detects it" do
    ExLisp.Env.reset()

    assert ExLisp.eval("""
           (let ((x (list 1 2)))
             (rplacd (cdr x) x)
             (list (eq (cddr x) x) (list-length x)))
           """) == [:t, nil]
  end

  test "destructive list operations preserve aliases" do
    ExLisp.Env.reset()

    assert ExLisp.eval("""
           (let ((x (list 1 2))
                 (y nil))
             (setq y x)
             (nconc x (list 3 4))
             (list x y))
           """) == [[1, 2, 3, 4], [1, 2, 3, 4]]
  end

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
      ExLisp.eval("(multiple-value-list (rename-file #{inspect(path)} #{inspect(renamed)}))")

    assert ExLisp.Pathname.namestring(new_path) == renamed
    assert ExLisp.Pathname.namestring(old_path) == path
    assert ExLisp.Pathname.namestring(new_true) == renamed
    assert File.read!(renamed) == "content"
    assert ExLisp.eval("(delete-file #{inspect(renamed)})") == :t
    refute File.exists?(renamed)
  end

  test "CLOS and environment compatibility entry points are callable" do
    assert ExLisp.eval("(allocate-instance 'standard-object)") != nil
    assert ExLisp.eval("(type-of 1)") == :integer
    assert ExLisp.eval("(constantp 1)") == :t
    assert ExLisp.eval("(lisp-implementation-type)") == "ExLisp"
    assert is_binary(ExLisp.eval("(lisp-implementation-version)"))
    assert is_binary(ExLisp.eval("(machine-type)"))

    assert ExLisp.eval("(compile-file-pathname \"sample.lisp\")") |> ExLisp.Pathname.pathnamep() ==
             :t
  end

  test "stream byte and output control functions use Lisp streams" do
    code = """
    (with-output-to-string (s)
      (write-byte 65 s)
      (finish-output s)
      (force-output s))
    """

    assert ExLisp.eval(code) == "A"

    assert ExLisp.eval("""
           (with-input-from-string (s "A")
             (list (read-byte s) (read-byte s nil :eof)))
           """) == [65, :eof]
  end

  test "hash table and package iteration forms work from Lisp" do
    hash_result =
      ExLisp.eval("""
      (let ((table (make-hash-table)))
        (setf (gethash :answer table) 42)
        (with-hash-table-iterator (next table)
          (multiple-value-list (next))))
      """)

    assert hash_result == [:t, :answer, 42]

    package_result =
      ExLisp.eval("""
      (with-package-iterator (next (list "COMMON-LISP") :external)
        (let ((entry (multiple-value-list (next))))
          (list (first entry) (symbolp (second entry)))))
      """)

    assert package_result == [:t, :t]
  end

  test "with-accessors and with-slots expand object places" do
    code = """
    (progn
      (defclass compatibility-person ()
        ((name :accessor compatibility-person-name :initarg :name)))
      (let ((person (make-instance 'compatibility-person :name "before")))
        (with-accessors ((display-name compatibility-person-name)) person
          (setf display-name "after"))
        (with-slots ((stored-name name)) person
          stored-name)))
    """

    assert ExLisp.eval(code) == "after"
  end

  test "symbol iteration macros bind symbols and return result forms" do
    external_count =
      ExLisp.eval("""
      (let ((count 0))
        (do-external-symbols (symbol "COMMON-LISP" count)
          (when (symbolp symbol)
            (incf count))))
      """)

    assert external_count > 0
  end

  test "reader preserving whitespace and delimited reads are available" do
    assert ExLisp.eval("""
           (with-input-from-string (s "abc ")
             (list (read-preserving-whitespace s nil :eof)
                   (read-char s nil :eof)))
           """) == [:abc, ExLisp.Character.new(?\s)]

    assert ExLisp.eval("""
           (with-input-from-string (s ") 12")
             (list (read-delimited-list #\\) s)
                   (read s)))
           """) == [[], 12]
  end

  test "pretty printer functions are exposed as Common Lisp calls" do
    assert ExLisp.eval("(functionp (formatter \"~A\"))") == :t
    assert ExLisp.eval("(functionp (pprint-dispatch '(1 2)))") == :t
    assert match?(%ExLisp.PPrint{}, ExLisp.eval("(copy-pprint-dispatch nil)"))
  end
end
