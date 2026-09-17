defmodule CommonLispTest do
  use ExUnit.Case, async: false

  describe "special forms and syntax" do
    test "quote and ' syntax" do
      assert ExLisp.eval("(quote (1 2 3))") == [1, 2, 3]
      assert ExLisp.eval("'(1 2 3)") == [1, 2, 3]
      assert ExLisp.eval("'a") == :a
      assert ExLisp.eval("'(a b c)") == [:a, :b, :c]
      assert ExLisp.eval("'()") == []
      assert ExLisp.eval("nil") == nil
      assert ExLisp.eval("t") == :t
    end

    test "if, when, unless" do
      assert ExLisp.eval("(if t 1 2)") == 1
      assert ExLisp.eval("(if nil 1 2)") == 2
      assert ExLisp.eval("(if (= 1 1) (+ 10 20) 0)") == 30
      assert ExLisp.eval("(if (= 1 2) 10)") == nil

      assert ExLisp.eval("(when t 10)") == 10
      assert ExLisp.eval("(when nil 10)") == nil
      assert ExLisp.eval("(when t (+ 1 2) (* 3 4))") == 12

      assert ExLisp.eval("(unless nil 20)") == 20
      assert ExLisp.eval("(unless t 20)") == nil
      assert ExLisp.eval("(unless nil (+ 1 2) (* 3 4))") == 12
    end

    test "cond" do
      code = """
      (cond
        ((= 1 2) "no")
        ((= 2 2) "yes")
        (t "fallback"))
      """

      assert ExLisp.eval(code) == "yes"

      fallback = """
      (cond
        ((= 1 2) "no")
        (t "fallback"))
      """

      assert ExLisp.eval(fallback) == "fallback"
    end

    test "let and let*" do
      assert ExLisp.eval("(let ((x 10) (y 20)) (+ x y))") == 30

      # let is parallel binding
      parallel = """
      (let ((x 1))
        (let ((x 2) (y x))
          (+ x y)))
      """

      assert ExLisp.eval(parallel) == 3

      # let* is sequential binding
      sequential = """
      (let* ((x 2) (y (+ x 3)))
        (* x y))
      """

      assert ExLisp.eval(sequential) == 10
    end

    test "progn, prog1, prog2" do
      assert ExLisp.eval("(progn 1 2 3)") == 3
      assert ExLisp.eval("(prog1 1 2 3)") == 1
      assert ExLisp.eval("(prog2 1 2 3)") == 2
    end

    test "and, or" do
      assert ExLisp.eval("(and)") == :t
      assert ExLisp.eval("(and 1 2 3)") == 3
      assert ExLisp.eval("(and 1 nil 3)") == nil

      assert ExLisp.eval("(or)") == nil
      assert ExLisp.eval("(or nil 2 3)") == 2
      assert ExLisp.eval("(or nil nil)") == nil
    end

    test "lambda and funcall and apply" do
      assert ExLisp.eval("((lambda (x y) (+ x y)) 3 4)") == 7
      assert ExLisp.eval("(funcall (lambda (x) (* x x)) 5)") == 25
      assert ExLisp.eval("(funcall #'+ 1 2 3)") == 6
      assert ExLisp.eval("(apply #'+ '(1 2 3 4))") == 10
      assert ExLisp.eval("(apply #'+ 1 2 '(3 4))") == 10
    end

    test "setq and setf" do
      ExLisp.eval("(setq my-var 100)")
      assert ExLisp.eval("my-var") == 100
      ExLisp.eval("(setf my-var 200)")
      assert ExLisp.eval("my-var") == 200
    end

    test "flet and labels" do
      flet_code = """
      (flet ((f (n) (+ n 10)))
        (f 5))
      """

      assert ExLisp.eval(flet_code) == 15

      flet_multi = """
      (flet ((f (n) (+ n 10))
             (g (n) (* n 2)))
        (+ (f 5) (g 5)))
      """

      assert ExLisp.eval(flet_multi) == 25

      labels_rec = """
      (labels ((fact (n)
                 (if (<= n 1)
                     1
                     (* n (fact (- n 1))))))
        (fact 5))
      """

      assert ExLisp.eval(labels_rec) == 120

      labels_mutual = """
      (labels ((my-even (n)
                 (if (= n 0)
                     t
                     (my-odd (- n 1))))
               (my-odd (n)
                 (if (= n 0)
                     nil
                     (my-even (- n 1)))))
        (my-even 10))
      """

      assert ExLisp.eval(labels_mutual) == :t

      flet_closure = """
      (let ((x 100))
        (flet ((f (n) (+ n x)))
          (f 5)))
      """

      assert ExLisp.eval(flet_closure) == 105

      flet_funcall = """
      (flet ((add10 (n) (+ n 10)))
        (funcall #'add10 5))
      """

      assert ExLisp.eval(flet_funcall) == 15
    end

    test "defmacro, backquote, and macroexpand" do
      ExLisp.eval("""
      (defmacro my-when (test &body body)
        `(if ,test (progn ,@body)))
      """)

      assert ExLisp.eval("(my-when (= 1 1) (+ 10 20))") == 30
      assert ExLisp.eval("(my-when (= 1 2) (+ 10 20))") == nil

      ExLisp.eval("""
      (defmacro my-unless (test &body body)
        `(if (not ,test) (progn ,@body)))
      """)

      assert ExLisp.eval("(my-unless (= 1 2) 42)") == 42
      assert ExLisp.eval("(my-unless (= 1 1) 42)") == nil

      # macroexpand-1 & macroexpand
      assert ExLisp.eval("(macroexpand-1 '(my-when (= x 1) (+ x 2)))") == [
               :if,
               [:=, :x, 1],
               [:progn, [:+, :x, 2]]
             ]

      assert ExLisp.eval("(macroexpand '(my-when (= x 1) (+ x 2)))") == [
               :if,
               [:=, :x, 1],
               [:progn, [:+, :x, 2]]
             ]

      # macro-function
      assert ExLisp.eval("(if (macro-function 'my-when) 'yes 'no)") == :yes
      assert ExLisp.eval("(if (macro-function 'not-a-macro) 'yes 'no)") == :no

      # gensym in macro
      ExLisp.eval("""
      (defmacro square-macro (x)
        (let ((g (gensym)))
          `(let ((,g ,x))
             (* ,g ,g))))
      """)

      assert ExLisp.eval("(square-macro 6)") == 36

      # &optional with default and supplied-p
      ExLisp.eval("""
      (defmacro opt-macro (a &optional (b 10 b-p))
        `(list ,a ,b ,b-p))
      """)

      assert ExLisp.eval("(opt-macro 1)") == [1, 10, nil]
      assert ExLisp.eval("(opt-macro 1 2)") == [1, 2, :t]

      # &key with default and supplied-p
      ExLisp.eval("""
      (defmacro key-macro (a &key (b 10 b-p))
        `(list ,a ,b ,b-p))
      """)

      assert ExLisp.eval("(key-macro 1)") == [1, 10, nil]
      assert ExLisp.eval("(key-macro 1 :b 2)") == [1, 2, :t]

      # macro with multiple evaluations of argument with side effect
      ExLisp.eval("(defmacro dbl (x) (list '+ x x))")
      ExLisp.eval("(defparameter a1 2)")
      assert ExLisp.eval("(dbl (incf a1))") == 7

      # &whole
      ExLisp.eval("""
      (defmacro whole-macro (&whole form a b)
        `(list ',form ,a ,b))
      """)

      assert ExLisp.eval("(whole-macro 10 20)") == [[:whole_macro, 10, 20], 10, 20]

      # nested destructuring
      ExLisp.eval("""
      (defmacro destruct-macro (((a b) c) &body body)
        `(list ,a ,b ,c (progn ,@body)))
      """)

      assert ExLisp.eval("(destruct-macro ((1 2) 3) 4 5)") == [1, 2, 3, 5]

      # macrolet
      macrolet_code = """
      (macrolet ((add-five (x) `(+ ,x 5)))
        (add-five 10))
      """

      assert ExLisp.eval(macrolet_code) == 15

      # symbol-macrolet
      sym_macrolet_code = """
      (symbol-macrolet ((pi-approx 3.14))
        (* 2 pi-approx))
      """

      assert ExLisp.eval(sym_macrolet_code) == 6.28
    end

    test "defconstant and defun" do
      ExLisp.eval("(defconstant +my-const+ 42)")
      assert ExLisp.eval("+my-const+") == 42

      ExLisp.eval("(defun square (x) (* x x))")
      assert ExLisp.eval("(square 6)") == 36
    end

    test "dotimes and dolist" do
      dotimes_code = """
      (progn
        (setq sum 0)
        (dotimes (i 5 sum)
          (setq sum (+ sum i))))
      """

      assert ExLisp.eval(dotimes_code) == 10

      dolist_code = """
      (progn
        (setq total 0)
        (dolist (item '(10 20 30) total)
          (setq total (+ total item))))
      """

      assert ExLisp.eval(dolist_code) == 60
    end

    test "extended loop facility" do
      assert ExLisp.eval("(loop for i below 5 sum i)") == 10
      assert ExLisp.eval("(loop for i from 1 to 5 collect i)") == [1, 2, 3, 4, 5]
      assert ExLisp.eval("(loop for i from 0 to 10 by 2 collect i)") == [0, 2, 4, 6, 8, 10]
      assert ExLisp.eval("(loop for i from 5 downto 1 collect i)") == [5, 4, 3, 2, 1]
      assert ExLisp.eval("(loop for x in '(10 20 30) sum x)") == 60
      assert ExLisp.eval("(loop for x in '(a b c) collect x)") == [:a, :b, :c]
      assert ExLisp.eval("(loop for x on '(a b c) collect x)") == [[:a, :b, :c], [:b, :c], [:c]]
      assert ExLisp.eval("(loop repeat 3 collect 'hello)") == [:hello, :hello, :hello]
      assert ExLisp.eval("(loop for i from 1 to 10 when (oddp i) collect i)") == [1, 3, 5, 7, 9]
      assert ExLisp.eval("(loop for i from 1 to 10 count (oddp i))") == 5
      assert ExLisp.eval("(loop for i in '(3 1 4 1 5 9 2 6) maximize i)") == 9
      assert ExLisp.eval("(loop for i in '(3 1 4 1 5 9 2 6) minimize i)") == 1
      assert ExLisp.eval("(loop for i from 1 to 10 while (< i 5) collect i)") == [1, 2, 3, 4]
      assert ExLisp.eval("(loop for i in '(2 4 6) always (evenp i))") == :t
      assert ExLisp.eval("(loop for i in '(2 3 6) always (evenp i))") == nil
      assert ExLisp.eval("(loop for i in '(1 2 3) thereis (if (evenp i) i))") == 2
      assert ExLisp.eval("(loop with a = 10 for i from 1 to 3 collect (+ a i))") == [11, 12, 13]
      assert ExLisp.eval("(loop (return 42))") == 42
    end
  end

  describe "Common Lisp arithmetic functions" do
    test "1+, 1-" do
      assert ExLisp.eval("(1+ 5)") == 6
      assert ExLisp.eval("(1- 5)") == 4
    end

    test "mod and rem" do
      assert ExLisp.eval("(mod 10 3)") == 1
      assert ExLisp.eval("(rem 10 3)") == 1
      assert ExLisp.eval("(mod -10 3)") == 2
      assert ExLisp.eval("(rem -10 3)") == -1
    end

    test "predicates: zerop, plusp, minusp, evenp, oddp" do
      assert ExLisp.eval("(zerop 0)") == :t
      assert ExLisp.eval("(zerop 1)") == nil
      assert ExLisp.eval("(plusp 5)") == :t
      assert ExLisp.eval("(plusp -5)") == nil
      assert ExLisp.eval("(minusp -5)") == :t
      assert ExLisp.eval("(minusp 5)") == nil
      assert ExLisp.eval("(evenp 4)") == :t
      assert ExLisp.eval("(evenp 5)") == nil
      assert ExLisp.eval("(oddp 5)") == :t
      assert ExLisp.eval("(oddp 4)") == nil
    end

    test "abs, min, max" do
      assert ExLisp.eval("(abs -42)") == 42
      assert ExLisp.eval("(min 3 1 4 1 5)") == 1
      assert ExLisp.eval("(max 3 1 4 1 5)") == 5
    end

    test "floor, ceiling, round, truncate" do
      assert ExLisp.eval("(floor 3.7)") == 3
      assert ExLisp.eval("(ceiling 3.2)") == 4
      assert ExLisp.eval("(round 3.6)") == 4
      assert ExLisp.eval("(round 3.2)") == 3
      assert ExLisp.eval("(truncate -3.7)") == -3
    end

    test "sqrt, expt" do
      assert ExLisp.eval("(sqrt 16)") == 4.0
      assert ExLisp.eval("(expt 2 3)") == 8
    end
  end

  describe "Common Lisp predicates and comparisons" do
    test "=, /=, <, <=, >, >=" do
      assert ExLisp.eval("(= 5 5)") == :t
      assert ExLisp.eval("(= 5 6)") == nil
      assert ExLisp.eval("(/= 5 6)") == :t
      assert ExLisp.eval("(/= 5 5)") == nil
      assert ExLisp.eval("(< 1 2 3)") == :t
      assert ExLisp.eval("(< 1 3 2)") == nil
      assert ExLisp.eval("(<= 1 2 2 3)") == :t
      assert ExLisp.eval("(> 3 2 1)") == :t
      assert ExLisp.eval("(>= 3 3 2 1)") == :t
    end

    test "equal, eql, eq, equalp" do
      assert ExLisp.eval("(equal '(1 2) '(1 2))") == :t
      assert ExLisp.eval("(equal \"abc\" \"abc\")") == :t
      assert ExLisp.eval("(eql 42 42)") == :t
      assert ExLisp.eval("(eq 'a 'a)") == :t
      assert ExLisp.eval("(equalp \"ABC\" \"abc\")") == :t
    end

    test "type predicates: null, not, atom, consp, listp, numberp, integerp, floatp, stringp, symbolp, functionp" do
      assert ExLisp.eval("(null nil)") == :t
      assert ExLisp.eval("(null '())") == :t
      assert ExLisp.eval("(null '(1))") == nil
      assert ExLisp.eval("(not nil)") == :t
      assert ExLisp.eval("(not t)") == nil

      assert ExLisp.eval("(atom 42)") == :t
      assert ExLisp.eval("(atom 'a)") == :t
      assert ExLisp.eval("(atom '(1 2))") == nil

      assert ExLisp.eval("(consp '(1 2))") == :t
      assert ExLisp.eval("(consp '())") == nil

      assert ExLisp.eval("(listp '(1 2))") == :t
      assert ExLisp.eval("(listp '())") == :t
      assert ExLisp.eval("(listp 42)") == nil

      assert ExLisp.eval("(numberp 42)") == :t
      assert ExLisp.eval("(numberp 3.14)") == :t
      assert ExLisp.eval("(integerp 42)") == :t
      assert ExLisp.eval("(integerp 3.14)") == nil
      assert ExLisp.eval("(floatp 3.14)") == :t

      assert ExLisp.eval("(stringp \"hello\")") == :t
      assert ExLisp.eval("(stringp 42)") == nil

      assert ExLisp.eval("(symbolp 'foo)") == :t
      assert ExLisp.eval("(symbolp 42)") == nil

      assert ExLisp.eval("(functionp (lambda (x) x))") == :t
    end
  end

  describe "Common Lisp list functions" do
    test "car, cdr, cxr" do
      assert ExLisp.eval("(car '(1 2 3))") == 1
      assert ExLisp.eval("(cdr '(1 2 3))") == [2, 3]
      assert ExLisp.eval("(caar '((1 2) 3))") == 1
      assert ExLisp.eval("(cadr '(1 2 3))") == 2
      assert ExLisp.eval("(cdar '((1 2) 3))") == [2]
      assert ExLisp.eval("(cddr '(1 2 3))") == [3]
    end

    test "positional access: first through tenth, rest, last, nth, nthcdr" do
      assert ExLisp.eval("(first '(a b c d e f g h i j))") == :a
      assert ExLisp.eval("(second '(a b c d e f g h i j))") == :b
      assert ExLisp.eval("(third '(a b c d e f g h i j))") == :c
      assert ExLisp.eval("(fourth '(a b c d e f g h i j))") == :d
      assert ExLisp.eval("(fifth '(a b c d e f g h i j))") == :e
      assert ExLisp.eval("(sixth '(a b c d e f g h i j))") == :f
      assert ExLisp.eval("(seventh '(a b c d e f g h i j))") == :g
      assert ExLisp.eval("(eighth '(a b c d e f g h i j))") == :h
      assert ExLisp.eval("(ninth '(a b c d e f g h i j))") == :i
      assert ExLisp.eval("(tenth '(a b c d e f g h i j))") == :j

      assert ExLisp.eval("(rest '(1 2 3))") == [2, 3]
      assert ExLisp.eval("(last '(1 2 3))") == [3]
      assert ExLisp.eval("(nth 2 '(a b c d))") == :c
      assert ExLisp.eval("(nthcdr 2 '(a b c d))") == [:c, :d]
    end

    test "list construction and manipulation: list, list*, append, reverse, length" do
      assert ExLisp.eval("(list 1 2 3)") == [1, 2, 3]
      assert ExLisp.eval("(list* 1 2 '(3 4))") == [1, 2, 3, 4]
      assert ExLisp.eval("(append '(1 2) '(3 4))") == [1, 2, 3, 4]
      assert ExLisp.eval("(reverse '(1 2 3))") == [3, 2, 1]
      assert ExLisp.eval("(length '(1 2 3 4))") == 4
    end

    test "member, assoc, rassoc, subst" do
      assert ExLisp.eval("(member 2 '(1 2 3))") == [2, 3]
      assert ExLisp.eval("(member 4 '(1 2 3))") == nil

      assert ExLisp.eval("(assoc 'b '((a 1) (b 2) (c 3)))") == [:b, 2]
      assert ExLisp.eval("(assoc 'z '((a 1) (b 2)))") == nil

      assert ExLisp.eval("(rassoc 2 '((a . 1) (b . 2) (c . 3)))") == [:b | 2]

      assert ExLisp.eval("(subst 0 1 '(1 (2 1) 3))") == [0, [2, 0], 3]
      assert ExLisp.eval("(copy-list '(1 2 3))") == [1, 2, 3]
      assert ExLisp.eval("(copy-tree '((1 2) 3))") == [[1, 2], 3]
      assert ExLisp.eval("(butlast '(1 2 3 4) 1)") == [1, 2, 3]
    end

    test "higher-order list functions: mapcar, mapc, remove-if, count-if, find-if, position-if, every, some" do
      assert ExLisp.eval("(mapcar (lambda (x) (* x 2)) '(1 2 3))") == [2, 4, 6]
      assert ExLisp.eval("(mapcar #'+ '(1 2 3) '(4 5 6))") == [5, 7, 9]

      assert ExLisp.eval("(remove 2 '(1 2 3 2 4))") == [1, 3, 4]
      assert ExLisp.eval("(remove-if #'evenp '(1 2 3 4 5))") == [1, 3, 5]
      assert ExLisp.eval("(remove-if-not #'evenp '(1 2 3 4 5))") == [2, 4]

      assert ExLisp.eval("(count 2 '(1 2 3 2 4))") == 2
      assert ExLisp.eval("(count-if #'evenp '(1 2 3 4 5))") == 2

      assert ExLisp.eval("(find 3 '(1 2 3 4))") == 3
      assert ExLisp.eval("(find-if #'evenp '(1 3 4 5))") == 4

      assert ExLisp.eval("(position 3 '(1 2 3 4))") == 2
      assert ExLisp.eval("(position-if #'evenp '(1 3 4 5))") == 2

      assert ExLisp.eval("(every #'evenp '(2 4 6))") == :t
      assert ExLisp.eval("(every #'evenp '(2 3 6))") == nil
      assert ExLisp.eval("(some #'evenp '(1 3 4 5))") == :t
      assert ExLisp.eval("(some #'evenp '(1 3 5))") == nil
      assert ExLisp.eval("(notevery #'evenp '(2 3 6))") == :t
      assert ExLisp.eval("(notany #'evenp '(1 3 5))") == :t
    end
  end

  describe "Common Lisp strings and characters" do
    test "string comparison and manipulation" do
      assert ExLisp.eval("(string= \"foo\" \"foo\")") == :t
      assert ExLisp.eval("(string= \"foo\" \"bar\")") == nil
      assert ExLisp.eval("(string/= \"foo\" \"bar\")") == 0
      assert ExLisp.eval("(string< \"abc\" \"def\")") == 0
      assert ExLisp.eval("(string-equal \"ABC\" \"abc\")") == :t

      assert ExLisp.eval("(string-upcase \"hello\")") == "HELLO"
      assert ExLisp.eval("(string-downcase \"HELLO\")") == "hello"
      assert ExLisp.eval("(string-capitalize \"hello world\")") == "Hello World"
      assert ExLisp.eval("(string-trim \" \" \"  hello  \")") == "hello"

      assert ExLisp.eval("(concatenate 'string \"foo\" \"bar\")") == "foobar"
      assert ExLisp.eval("(subseq \"hello world\" 0 5)") == "hello"
      assert ExLisp.eval("(char \"hello\" 1)") == ?e
    end

    test "character operations" do
      assert ExLisp.eval("(char= (char \"a\" 0) (char \"a\" 0))") == :t
      assert ExLisp.eval("(char-equal (char \"A\" 0) (char \"a\" 0))") == :t
      assert ExLisp.eval("(char-code (char \"A\" 0))") == 65
      assert ExLisp.eval("(code-char 65)") == 65
      assert ExLisp.eval("(alpha-char-p (char \"a\" 0))") == :t
      assert ExLisp.eval("(digit-char-p (char \"5\" 0))") == 5
      assert ExLisp.eval("(alphanumericp (char \"x\" 0))") == :t
    end
  end

  describe "Common Lisp format and IO" do
    test "format to string" do
      assert ExLisp.eval("(format nil \"Hello, ~a!\" \"world\")") == "Hello, world!"
      assert ExLisp.eval("(format nil \"~d + ~d = ~d\" 1 2 3)") == "1 + 2 = 3"
      assert ExLisp.eval("(format nil \"~s\" \"quoted\")") == "\"quoted\""
      assert ExLisp.eval("(format nil \"~%line1~%line2\")") == "\nline1\nline2"
    end

    test "write-line, write-string, and write-char" do
      import ExUnit.CaptureIO

      assert capture_io(fn ->
               assert ExLisp.eval("(write-line \"Hello world!\")") == "Hello world!"
             end) == "Hello world!\n"

      assert capture_io(fn ->
               assert ExLisp.eval("(write-string \"Hello world!\")") == "Hello world!"
             end) == "Hello world!"

      assert capture_io(fn ->
               assert ExLisp.eval("(write-char (code-char 65))") == 65
             end) == "A"

      assert_raise ArgumentError, fn ->
        ExLisp.eval("(write-line 123)")
      end

      assert_raise ArgumentError, fn ->
        ExLisp.eval("(write-string 123)")
      end
    end

    test "read, write-to-string, and file IO with with-open-file" do
      assert ExLisp.eval("(read \"(+ 1 2)\")") == [:+, 1, 2]
      assert ExLisp.eval("(write-to-string '(1 2 3))") == "(1 2 3)"

      tmp_path =
        Path.join(System.tmp_dir!(), "exlisp_io_test_#{System.unique_integer([:positive])}.txt")

      write_code = """
      (with-open-file (s "#{tmp_path}" :direction :output)
        (write-line "hello file" s)
        (write-line "second line" s))
      """

      ExLisp.eval(write_code)

      read_code = """
      (with-open-file (s "#{tmp_path}" :direction :input)
        (list (read-line s) (read-line s)))
      """

      assert ExLisp.eval(read_code) == ["hello file", "second line"]

      File.rm(tmp_path)
    end
  end

  describe "Common Lisp Collections (Hash Tables, Arrays, Vectors)" do
    test "hash tables" do
      code = """
      (let ((ht (make-hash-table)))
        (setf (gethash :a ht) 100)
        (setf (gethash :b ht) 200)
        (list (hash-table-p ht)
              (hash-table-count ht)
              (gethash :a ht)
              (gethash :c ht 999)
              (remhash :a ht)
              (hash-table-count ht)
              (gethash :a ht)))
      """

      assert ExLisp.eval(code) == [:t, 2, 100, 999, :t, 1, nil]
    end

    test "vectors and arrays" do
      code = """
      (let ((v (vector 10 20 30))
            (arr (make-array '(2 3) :initial-element 0)))
        (setf (svref v 1) 99)
        (setf (aref arr 0 2) 77)
        (list (vectorp v)
              (arrayp arr)
              (svref v 1)
              (aref arr 0 2)
              (array-dimensions arr)
              (array-total-size arr)))
      """

      assert ExLisp.eval(code) == [:t, :t, 99, 77, [2, 3], 6]
    end

    test "vector fill-pointer and push/pop" do
      code = """
      (let ((v (make-array 5 :fill-pointer 0 :adjustable t)))
        (vector-push 10 v)
        (vector-push 20 v)
        (list (svref v 0) (svref v 1) (vector-pop v)))
      """

      assert ExLisp.eval(code) == [10, 20, 20]
    end
  end

  describe "Common Lisp Iteration & Control (loop, block, return-from, do, tagbody, unwind-protect)" do
    test "block and return-from" do
      code = """
      (block my-block
        (let ((x 10))
          (when (= x 10)
            (return-from my-block 42))
          99))
      """

      assert ExLisp.eval(code) == 42
    end

    test "defun with early return-from" do
      code = """
      (defun test-early-ret (n)
        (when (< n 0)
          (return-from test-early-ret :negative))
        (* n 2))
      """

      ExLisp.eval(code)
      assert ExLisp.eval("(test-early-ret -5)") == :negative
      assert ExLisp.eval("(test-early-ret 5)") == 10
    end

    test "loop with return" do
      code = """
      (progn
        (defparameter *loop_i* 0)
        (defparameter *loop_sum* 0)
        (loop
          (setf *loop_sum* (+ *loop_sum* *loop_i*))
          (setf *loop_i* (+ *loop_i* 1))
          (when (> *loop_i* 5)
            (return *loop_sum*))))
      """

      assert ExLisp.eval(code) == 15
    end

    test "unwind-protect" do
      code = """
      (progn
        (defparameter *cleanup* nil)
        (unwind-protect
          (+ 1 2)
          (setf *cleanup* :done))
        *cleanup*)
      """

      assert ExLisp.eval(code) == :done
      assert ExLisp.eval("(unwind-protect (* 3 4) nil)") == 12
    end

    test "do loop" do
      code = """
      (do ((i 0 (+ i 1))
           (acc 0 (+ acc i)))
          ((> i 4) acc))
      """

      assert ExLisp.eval(code) == 10
    end

    test "tagbody and go" do
      code = """
      (progn
        (defparameter *tagbody_acc* 0)
        (defparameter *tagbody_i* 0)
        (tagbody
          start
            (setf *tagbody_acc* (+ *tagbody_acc* *tagbody_i*))
            (setf *tagbody_i* (+ *tagbody_i* 1))
            (when (<= *tagbody_i* 3)
              (go start)))
        *tagbody_acc*)
      """

      assert ExLisp.eval(code) == 6

      code_skip = """
      (let ((x 0))
        (tagbody
          (setq x 1)
          (go a)
          (setq x 2)
          a)
        x)
      """

      assert ExLisp.eval(code_skip) == 1
    end
  end

  describe "Common Lisp Structures and CLOS (defstruct, defclass, defmethod, slot-value)" do
    test "defstruct, make-<struct>, accessors, setf, and predicate" do
      code = """
      (progn
        (defstruct person name (age 0))
        (let ((p (make-person :name "Alice" :age 30)))
          (setf (person-name p) "Bob")
          (list (person-p p)
                (person-name p)
                (person-age p))))
      """

      assert ExLisp.eval(code) == [:t, "Bob", 30]
    end

    test "make-instance, slot-value, setf, and slot-boundp" do
      code = """
      (progn
        (defclass point () (x y))
        (let ((pt (make-instance 'point :x 10 :y 20)))
          (setf (slot-value pt :x) 100)
          (list (slot-value pt :x)
                (slot-value pt :y)
                (slot-boundp pt :x)
                (slot-boundp pt :z))))
      """

      assert ExLisp.eval(code) == [100, 20, :t, nil]
    end

    test "defgeneric and defmethod" do
      code = """
      (progn
        (defgeneric greet (obj))
        (defmethod greet (name) (format nil "Hello, ~a!" name))
        (greet "World"))
      """

      assert ExLisp.eval(code) == "Hello, World!"
    end
  end

  describe "Common Lisp Conditions & Error Handling (handler-case, ignore-errors, warn)" do
    test "ignore-errors" do
      assert ExLisp.eval("(ignore-errors (+ 1 2))") == 3
      assert ExLisp.eval("(ignore-errors (/ 1 0))") == nil
    end

    test "handler-case" do
      code = """
      (handler-case
        (/ 1 0)
        (error (c) :handled-error))
      """

      assert ExLisp.eval(code) == :handled_error

      code_no_err = """
      (handler-case
        (+ 10 20)
        (error (c) :not-called))
      """

      assert ExLisp.eval(code_no_err) == 30
    end

    test "warn" do
      import ExUnit.CaptureIO

      assert capture_io(:stderr, fn ->
               assert ExLisp.eval("(warn \"Something is wrong ~a\" 123)") == nil
             end) =~ "WARNING: Something is wrong 123"
    end
  end

  describe "Common Lisp Symbols & Packages (gensym, symbol-name, get, setf get, intern, defpackage)" do
    test "gensym and symbol-name" do
      sym = ExLisp.eval("(gensym \"VAR\")")
      assert is_atom(sym)
      assert String.starts_with?(Atom.to_string(sym), "var")

      assert ExLisp.eval("(symbol-name 'hello)") == "HELLO"
      assert ExLisp.eval("(symbol-package 'hello)") == :COMMON_LISP_USER
    end

    test "symbol-value and set" do
      ExLisp.eval("(defparameter *sym_val_test* 123)")
      assert ExLisp.eval("(symbol-value '*sym_val_test*)") == 123
      ExLisp.eval("(set '*sym_val_test* 456)")
      assert ExLisp.eval("*sym_val_test*") == 456
    end

    test "boundp, make-symbol, copy-symbol, special-operator-p, symbol-plist" do
      assert ExLisp.eval("(boundp 't)") == :t
      assert ExLisp.eval("(boundp nil)") == :t
      assert ExLisp.eval("(boundp :foo)") == :t
      assert ExLisp.eval("(boundp '#:unbound_sym)") == nil

      assert ExLisp.eval("(symbolp (make-symbol \"my-uninterned\"))") == :t
      assert ExLisp.eval("(symbol-name (make-symbol \"my-uninterned\"))") == "my-uninterned"
      assert ExLisp.eval("(eq (make-symbol \"A\") (make-symbol \"A\"))") == nil

      assert ExLisp.eval("(special-operator-p 'if)") == :t
      assert ExLisp.eval("(special-operator-p 'let)") == :t
      assert ExLisp.eval("(special-operator-p 'let*)") == :t
      assert ExLisp.eval("(special-operator-p 'cons)") == nil

      code = """
      (let ((s (copy-symbol 'my-base-sym t)))
        (setf (symbol-plist s) '(a 1 b 2))
        (list (symbolp s) (symbol-plist s) (get s 'a)))
      """

      assert ExLisp.eval(code) == [:t, [:a, 1, :b, 2], 1]
    end

    test "property lists (get, setf get, remprop)" do
      code = """
      (progn
        (setf (get 'my-sym :doc) "Documentation string")
        (setf (get 'my-sym :score) 95)
        (list (get 'my-sym :doc)
              (get 'my-sym :score)
              (get 'my-sym :unknown :default-val)
              (remprop 'my-sym :doc)
              (get 'my-sym :doc)))
      """

      assert ExLisp.eval(code) == ["Documentation string", 95, :default_val, :t, nil]
    end

    test "intern, find-symbol, defpackage, in-package" do
      assert ExLisp.eval("(intern \"MY-NEW-SYM\")") == :my_new_sym
      assert ExLisp.eval("(find-symbol \"MY-NEW-SYM\")") == :my_new_sym
      assert ExLisp.eval("(defpackage :my-pkg)") == :my_pkg
      assert ExLisp.eval("(in-package :my-pkg)") == :my_pkg
      assert ExLisp.eval("(find-package :my-pkg)") == :my_pkg
    end
  end

  describe "Common Lisp Bitwise & Numerical Operations (Step 7)" do
    test "logand, logior, logxor, lognot" do
      assert ExLisp.eval("(logand)") == -1
      assert ExLisp.eval("(logand 12 10)") == 8
      assert ExLisp.eval("(logand 15 14 6)") == 6

      assert ExLisp.eval("(logior)") == 0
      assert ExLisp.eval("(logior 12 10)") == 14
      assert ExLisp.eval("(logior 1 2 4 8)") == 15

      assert ExLisp.eval("(logxor)") == 0
      assert ExLisp.eval("(logxor 12 10)") == 6
      assert ExLisp.eval("(logxor 12 10 6)") == 0

      assert ExLisp.eval("(lognot 0)") == -1
      assert ExLisp.eval("(lognot -1)") == 0
      assert ExLisp.eval("(lognot 5)") == -6
    end

    test "extended boolean bitwise operations" do
      assert ExLisp.eval("(logeqv)") == -1
      assert ExLisp.eval("(logeqv 12 10)") == ExLisp.eval("(lognot (logxor 12 10))")
      assert ExLisp.eval("(lognand 12 10)") == ExLisp.eval("(lognot (logand 12 10))")
      assert ExLisp.eval("(lognor 12 10)") == ExLisp.eval("(lognot (logior 12 10))")
      assert ExLisp.eval("(logandc1 12 10)") == ExLisp.eval("(logand (lognot 12) 10)")
      assert ExLisp.eval("(logandc2 12 10)") == ExLisp.eval("(logand 12 (lognot 10))")
      assert ExLisp.eval("(logorc1 12 10)") == ExLisp.eval("(logior (lognot 12) 10)")
      assert ExLisp.eval("(logorc2 12 10)") == ExLisp.eval("(logior 12 (lognot 10))")
    end

    test "ash (arithmetic shift)" do
      assert ExLisp.eval("(ash 16 1)") == 32
      assert ExLisp.eval("(ash 16 2)") == 64
      assert ExLisp.eval("(ash 16 -1)") == 8
      assert ExLisp.eval("(ash 16 -2)") == 4
      assert ExLisp.eval("(ash -16 -1)") == -8
      assert ExLisp.eval("(ash 16 0)") == 16
    end

    test "logbitp, logcount, integer-length" do
      assert ExLisp.eval("(logbitp 0 1)") == :t
      assert ExLisp.eval("(logbitp 1 1)") == nil
      assert ExLisp.eval("(logbitp 3 8)") == :t
      assert ExLisp.eval("(logbitp 2 8)") == nil

      assert ExLisp.eval("(logcount 0)") == 0
      assert ExLisp.eval("(logcount 7)") == 3
      assert ExLisp.eval("(logcount 15)") == 4
      assert ExLisp.eval("(logcount -1)") == 0
      assert ExLisp.eval("(logcount -8)") == 3

      assert ExLisp.eval("(integer-length 0)") == 0
      assert ExLisp.eval("(integer-length 1)") == 1
      assert ExLisp.eval("(integer-length 7)") == 3
      assert ExLisp.eval("(integer-length 8)") == 4
      assert ExLisp.eval("(integer-length -1)") == 0
      assert ExLisp.eval("(integer-length -9)") == 4
    end

    test "isqrt" do
      assert ExLisp.eval("(isqrt 0)") == 0
      assert ExLisp.eval("(isqrt 1)") == 1
      assert ExLisp.eval("(isqrt 4)") == 2
      assert ExLisp.eval("(isqrt 9)") == 3
      assert ExLisp.eval("(isqrt 15)") == 3
      assert ExLisp.eval("(isqrt 16)") == 4
      assert ExLisp.eval("(isqrt 100)") == 10
      assert ExLisp.eval("(isqrt 1000000000000)") == 1_000_000
    end

    test "byte, ldb, dpb, setf ldb" do
      assert ExLisp.eval("(byte 4 2)") == {:byte, 4, 2}
      assert ExLisp.eval("(ldb (byte 4 2) #b11010110)") == 5
      assert ExLisp.eval("(dpb 0 (byte 4 2) #b11010110)") == 194

      code = """
      (progn
        (defparameter *ldb_x* 0)
        (setf (ldb (byte 4 0) *ldb_x*) 5)
        (setf (ldb (byte 4 4) *ldb_x*) 3)
        *ldb_x*)
      """

      # (3 << 4) | 5 = 48 | 5 = 53
      assert ExLisp.eval(code) == 53
    end
  end

  describe "Elixir and Erlang Interop" do
    test "calls Elixir module functions" do
      assert ExLisp.eval("(Enum.map '(1 2 3) (lambda (x) (* x 10)))") == [10, 20, 30]
      assert ExLisp.eval("(String.upcase \"elixir\")") == "ELIXIR"
      assert ExLisp.eval("(Path.join \"foo\" \"bar\")") == "foo/bar"
    end

    test "calls Erlang module functions" do
      assert ExLisp.eval("(:math.sqrt 25)") == 5.0
      assert ExLisp.eval("(:erlang.integer_to_list 42)") == ~c"42"
    end
  end

  describe "Common Lisp Rational Numbers & Fractions" do
    test "division (/) produces reduced ratios or integers" do
      assert ExLisp.eval("(/ 4 6)") == ExLisp.Ratio.new(2, 3)
      assert ExLisp.eval("(/ 6 2)") == 3
      assert ExLisp.eval("(/ 4)") == ExLisp.Ratio.new(1, 4)
      assert ExLisp.eval("(/ -4)") == ExLisp.Ratio.new(-1, 4)
      assert ExLisp.eval("(/ -4 6)") == ExLisp.Ratio.new(-2, 3)
      assert ExLisp.eval("(/ 4 -6)") == ExLisp.Ratio.new(-2, 3)
      assert ExLisp.eval("(/ -4 -6)") == ExLisp.Ratio.new(2, 3)
      assert ExLisp.eval("(/ 4 6 2)") == ExLisp.Ratio.new(1, 3)
      assert ExLisp.eval("(/ 4.0 6)") == 4.0 / 6
    end

    test "parses ratio literals" do
      assert ExLisp.eval("2/3") == ExLisp.Ratio.new(2, 3)
      assert ExLisp.eval("4/6") == ExLisp.Ratio.new(2, 3)
      assert ExLisp.eval("-2/3") == ExLisp.Ratio.new(-2, 3)
      assert ExLisp.eval("+1/2") == ExLisp.Ratio.new(1, 2)
      assert ExLisp.eval("6/3") == 2
      assert ExLisp.eval("'2/3") == ExLisp.Ratio.new(2, 3)

      assert ExLisp.eval("'(1/2 2/3 3/4)") == [
               ExLisp.Ratio.new(1, 2),
               ExLisp.Ratio.new(2, 3),
               ExLisp.Ratio.new(3, 4)
             ]
    end

    test "arithmetic operations (+, -, *, /) with ratios" do
      assert ExLisp.eval("(+ 1/2 1/3)") == ExLisp.Ratio.new(5, 6)
      assert ExLisp.eval("(+ 1/2 1/2)") == 1
      assert ExLisp.eval("(+ 1/2 1)") == ExLisp.Ratio.new(3, 2)
      assert ExLisp.eval("(+ 1/2 0.5)") == 1.0

      assert ExLisp.eval("(- 1 1/3)") == ExLisp.Ratio.new(2, 3)
      assert ExLisp.eval("(- 2/3)") == ExLisp.Ratio.new(-2, 3)
      assert ExLisp.eval("(- 1/2 1/3)") == ExLisp.Ratio.new(1, 6)

      assert ExLisp.eval("(* 2/3 3/4)") == ExLisp.Ratio.new(1, 2)
      assert ExLisp.eval("(* 2/3 3)") == 2
      assert ExLisp.eval("(* 2/3 0)") == 0

      assert ExLisp.eval("(/ 2/3 4/5)") == ExLisp.Ratio.new(5, 6)
      assert ExLisp.eval("(1+ 2/3)") == ExLisp.Ratio.new(5, 3)
      assert ExLisp.eval("(1- 2/3)") == ExLisp.Ratio.new(-1, 3)
      assert ExLisp.eval("(abs -2/3)") == ExLisp.Ratio.new(2, 3)
    end

    test "numeric comparisons (=, /=, <, <=, >, >=, min, max)" do
      assert ExLisp.eval("(= 2/3 4/6)") == :t
      assert ExLisp.eval("(= 1/2 0.5)") == :t
      assert ExLisp.eval("(/= 1/2 1/3)") == :t
      assert ExLisp.eval("(< 1/3 1/2)") == :t
      assert ExLisp.eval("(<= 1/3 1/3)") == :t
      assert ExLisp.eval("(> 1/2 1/3)") == :t
      assert ExLisp.eval("(>= 1/2 1/2)") == :t
      assert ExLisp.eval("(min 1/3 1/2)") == ExLisp.Ratio.new(1, 3)
      assert ExLisp.eval("(max 1/3 1/2)") == ExLisp.Ratio.new(1, 2)
    end

    test "predicates and accessors (numberp, rationalp, numerator, denominator, etc.)" do
      assert ExLisp.eval("(numberp 2/3)") == :t
      assert ExLisp.eval("(rationalp 2/3)") == :t
      assert ExLisp.eval("(rationalp 5)") == :t
      assert ExLisp.eval("(integerp 2/3)") == nil
      assert ExLisp.eval("(floatp 2/3)") == nil
      assert ExLisp.eval("(numerator 2/3)") == 2
      assert ExLisp.eval("(denominator 2/3)") == 3
      assert ExLisp.eval("(numerator 5)") == 5
      assert ExLisp.eval("(denominator 5)") == 1
      assert ExLisp.eval("(zerop 2/3)") == nil
      assert ExLisp.eval("(plusp 2/3)") == :t
      assert ExLisp.eval("(minusp -2/3)") == :t
    end

    test "expt, rounding, and equality functions" do
      assert ExLisp.eval("(expt 2/3 2)") == ExLisp.Ratio.new(4, 9)
      assert ExLisp.eval("(expt 2/3 -2)") == ExLisp.Ratio.new(9, 4)
      assert ExLisp.eval("(expt 2/3 0)") == 1

      assert ExLisp.eval("(floor 5/3)") == 1
      assert ExLisp.eval("(ceiling 5/3)") == 2
      assert ExLisp.eval("(round 5/3)") == 2
      assert ExLisp.eval("(truncate 5/3)") == 1

      assert ExLisp.eval("(eql 2/3 2/3)") == :t
      assert ExLisp.eval("(eql 2/3 4/6)") == :t
      assert ExLisp.eval("(equal 2/3 2/3)") == :t
      assert ExLisp.eval("(equalp 1/2 0.5)") == :t
    end

    test "formatting and string output" do
      assert inspect(ExLisp.eval("(/ 4 6)")) == "2/3"
      assert inspect(ExLisp.eval_repl("(/ 4 6)")) == "2/3"
      assert ExLisp.eval(~s{(format nil "~a" (/ 4 6))}) == "2/3"
      assert ExLisp.eval(~s{(format nil "~s" (/ 4 6))}) == "2/3"
      assert ExLisp.eval(~s{(format nil "~d" (/ 4 6))}) == "2/3"
      assert ExLisp.eval("(write-to-string (/ 4 6))") == "2/3"
    end
  end

  describe "SBCL quit and exit functions" do
    @tag timeout: 300_000
    test "sb-ext:quit and quit exit with expected status codes" do
      {_, 0} = System.cmd("mix", ["run", "-e", ~s{ExLisp.eval("(sb-ext:quit)")}])
      {_, 42} = System.cmd("mix", ["run", "-e", ~s{ExLisp.eval("(sb-ext:quit :unix-status 42)")}])
      {_, 7} = System.cmd("mix", ["run", "-e", ~s{ExLisp.eval("(sb-ext:quit :code 7)")}])

      {_, 10} =
        System.cmd("mix", ["run", "-e", ~s{ExLisp.eval("(sb-ext::quit :unix-status 10)")}])

      {_, 15} = System.cmd("mix", ["run", "-e", ~s{ExLisp.eval("(quit 15)")}])
      {_, 99} = System.cmd("mix", ["run", "-e", ~s{ExLisp.eval("(exit :code 99)")}])
      {_, 3} = System.cmd("mix", ["run", "-e", ~s{ExLisp.eval("(sb-ext:exit :code 3 :abort t)")}])
    end
  end
end
