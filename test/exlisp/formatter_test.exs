defmodule ExLisp.FormatterTest do
  use ExUnit.Case, async: true

  describe "ExLisp.Formatter.format/2" do
    test "formats simple single-line expression" do
      input = "(+  1   2   3)"
      expected = "(+ 1 2 3)\n"
      assert ExLisp.Formatter.format(input) == expected
    end

    test "formats multi-line defun with closing parentheses rolled up" do
      input = """
      (defun factorial (n)
        (
          if (<= n 1)
             1
             (* n (factorial (- n 1)))
        )
      )
      """

      expected = """
      (defun factorial (n)
        (if (<= n 1)
            1
            (* n (factorial (- n 1)))))
      """

      assert ExLisp.Formatter.format(input) == expected
    end

    test "formats let bindings and body with proper 2-space indentation" do
      input = """
      (defun example-function (x y)
      (let (
      (a (+ x 1))
      (b (* y 2))
      )
      (if (> a b)
      (list a b)
      (list b a)
      )
      )
      )
      """

      expected = """
      (defun example-function (x y)
        (let ((a (+ x 1))
              (b (* y 2)))
          (if (> a b)
              (list a b)
              (list b a))))
      """

      assert ExLisp.Formatter.format(input) == expected
    end

    test "formats cond clauses properly" do
      input = """
      (cond
      ((= x 1)
      :one)
      ((= x 2)
      :two)
      (t
      :other))
      """

      expected = """
      (cond
        ((= x 1)
         :one)
        ((= x 2)
         :two)
        (t
         :other))
      """

      assert ExLisp.Formatter.format(input) == expected
    end

    test "formats when and unless" do
      input = """
      (when (> x 0)
      (setq y (+ y 1))
      (print y))
      """

      expected = """
      (when (> x 0)
        (setq y (+ y 1))
        (print y))
      """

      assert ExLisp.Formatter.format(input) == expected
    end

    test "preserves comments and places closing parenthesis before inline comment" do
      input = """
      ;;;; Math library

      ;;; Factorial function
      (defun factorial (n)
        ;; Check base case
        (if (<= n 1)
            1 ; return 1
            (* n (factorial (- n 1)))))
      """

      expected = """
      ;;;; Math library

      ;;; Factorial function
      (defun factorial (n)
        ;; Check base case
        (if (<= n 1)
            1  ; return 1
            (* n (factorial (- n 1)))))
      """

      assert ExLisp.Formatter.format(input) == expected
    end

    test "formats nested quotes, characters, and strings" do
      input = """
      (defun test-syntax ()
        '(:a :b :c)
        #'my-fun
        #\\Space
        "hello \\"world\\""
        #(1 2 3))
      """

      expected = """
      (defun test-syntax ()
        '(:a :b :c)
        #'my-fun
        #\\Space
        "hello \\"world\\""
        #(1 2 3))
      """

      assert ExLisp.Formatter.format(input) == expected
    end

    test "formats with-open-file and dolist" do
      input = """
      (with-open-file (stream "test.txt")
      (dolist (item (read stream))
      (print item)))
      """

      expected = """
      (with-open-file (stream "test.txt")
        (dolist (item (read stream))
          (print item)))
      """

      assert ExLisp.Formatter.format(input) == expected
    end

    test "formats defparameter and case" do
      input = """
      (defparameter *config*
      '(:env :prod))

      (case (get-env)
      (:prod
      (connect-db))
      (:dev
      (mock-db)))
      """

      expected = """
      (defparameter *config*
        '(:env :prod))

      (case (get-env)
        (:prod
         (connect-db))
        (:dev
         (mock-db)))
      """

      assert ExLisp.Formatter.format(input) == expected
    end

    test "formats single-line defun breaking line at function body" do
      input = """
      (defun main () (write-line "Hello world!"))
      (main)
      """

      expected = """
      (defun main ()
        (write-line "Hello world!"))
      (main)
      """

      assert ExLisp.Formatter.format(input) == expected
    end

    test "formats via ExLisp.format/2 and format_file/2" do
      input = "(defun square (x) (* x x))"
      assert ExLisp.format(input) == "(defun square (x)\n  (* x x))\n"

      tmp_path = Path.join(System.tmp_dir!(), "exlisp_format_test.lisp")
      File.write!(tmp_path, "(+   1    2)\n")

      {:ok, formatted} = ExLisp.format_file(tmp_path, in_place: true)
      assert formatted == "(+ 1 2)\n"
      assert File.read!(tmp_path) == "(+ 1 2)\n"

      File.rm!(tmp_path)
    end

    test "CLI -f and --format overwrite file in-place" do
      tmp_path = Path.join(System.tmp_dir!(), "exlisp_cli_format_test.lisp")
      File.write!(tmp_path, "(defun foo (x)\n  (\n    + x 1\n  )\n)\n")

      ExLisp.CLI.main(["-f", tmp_path])
      assert File.read!(tmp_path) == "(defun foo (x)\n  (+ x 1))\n"

      File.write!(tmp_path, "(defun foo (x)\n  (\n    + x 2\n  )\n)\n")
      ExLisp.CLI.main(["--format", tmp_path])
      assert File.read!(tmp_path) == "(defun foo (x)\n  (+ x 2))\n"

      File.rm!(tmp_path)
    end
  end
end
