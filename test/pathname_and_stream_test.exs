defmodule PathnameAndStreamTest do
  use ExUnit.Case

  describe "Pathname functionality" do
    test "pathnamep and make-pathname" do
      assert ExLisp.eval("(pathnamep (make-pathname :name \"test\" :type \"lisp\"))") == :t
      assert ExLisp.eval("(pathnamep \"/foo/bar.txt\")") == nil
      assert ExLisp.eval("(pathnamep 123)") == nil

      code = """
      (let ((p (make-pathname :directory '(:absolute "tmp" "sub") :name "foo" :type "txt")))
        (list (pathnamep p)
              (pathname-directory p)
              (pathname-name p)
              (pathname-type p)))
      """
      assert ExLisp.eval(code) == [:t, [:absolute, "tmp", "sub"], "foo", "txt"]
    end

    test "parse-namestring and namestring" do
      code = """
      (let ((p (parse-namestring "/usr/local/bin/clisp")))
        (list (pathname-directory p)
              (pathname-name p)
              (namestring p)))
      """
      assert ExLisp.eval(code) == [[:absolute, "usr", "local", "bin"], "clisp", "/usr/local/bin/clisp"]

      assert ExLisp.eval("(namestring (make-pathname :directory '(:relative \"src\") :name \"app\" :type \"ex\"))") == "src/app.ex"
      assert ExLisp.eval("(file-namestring (make-pathname :directory '(:absolute \"tmp\") :name \"app\" :type \"ex\"))") == "app.ex"
      assert ExLisp.eval("(directory-namestring (make-pathname :directory '(:absolute \"tmp\" \"sub\") :name \"app\"))") == "/tmp/sub/"
    end

    test "merge-pathnames" do
      code = """
      (let ((merged (merge-pathnames "foo.txt" "/var/log/bar.lisp")))
        (list (pathname-directory merged)
              (pathname-name merged)
              (pathname-type merged)))
      """
      assert ExLisp.eval(code) == [[:absolute, "var", "log"], "foo", "txt"]
    end

    test "wild-pathname-p and pathname-match-p" do
      assert ExLisp.eval("(wild-pathname-p (make-pathname :name :wild))") == :t
      assert ExLisp.eval("(wild-pathname-p (make-pathname :name \"foo\"))") == nil
      assert ExLisp.eval("(pathname-match-p \"foo.txt\" (make-pathname :name :wild :type \"txt\"))") == :t
      assert ExLisp.eval("(pathname-match-p \"foo.lisp\" (make-pathname :name :wild :type \"txt\"))") == nil
    end

    test "probe-file and truename" do
      assert ExLisp.eval("(pathnamep (probe-file \"mix.exs\"))") == :t
      assert ExLisp.eval("(probe-file \"non_existent_file_12345.xyz\")") == nil
      assert ExLisp.eval("(pathnamep (truename \"mix.exs\"))") == :t
    end
  end

  describe "Stream I/O functionality" do
    test "streamp predicates" do
      code = """
      (let ((in (make-string-input-stream "abc"))
            (out (make-string-output-stream)))
        (unwind-protect
          (list (streamp in)
                (open-stream-p in)
                (input-stream-p in)
                (output-stream-p in)
                (streamp out)
                (open-stream-p out)
                (input-stream-p out)
                (output-stream-p out))
          (close in)
          (close out)))
      """
      assert ExLisp.eval(code) == [:t, :t, :t, nil, :t, :t, nil, :t]
    end

    test "read-char, unread-char, peek-char, read-line" do
      code = """
      (let ((s (make-string-input-stream "a\\nhello world")))
        (unwind-protect
          (let* ((c1 (read-char s))
                 (c2 (peek-char nil s)))
            (unread-char c1 s)
            (let* ((c3 (read-char s))
                   (c4 (read-char s)))
              (multiple-value-bind (line missing-p) (read-line s)
                (list c1 c2 c3 c4 line missing-p))))
          (close s)))
      """
      assert ExLisp.eval(code) == [?a, 10, ?a, 10, "hello world", :t]
    end

    test "write-char, write-string, write-line, terpri, fresh-line" do
      code = """
      (let ((s (make-string-output-stream)))
        (unwind-protect
          (progn
            (write-char #\\H s)
            (write-string "ello" s)
            (terpri s)
            (write-line "World" s)
            (fresh-line s)
            (write-string "!" s)
            (get-output-stream-string s))
          (close s)))
      """
      assert ExLisp.eval(code) == "Hello\nWorld\n!"
    end

    test "make-broadcast-stream" do
      code = """
      (let* ((s1 (make-string-output-stream))
             (s2 (make-string-output-stream))
             (b (make-broadcast-stream s1 s2)))
        (unwind-protect
          (progn
            (write-string "broadcast test" b)
            (list (get-output-stream-string s1)
                  (get-output-stream-string s2)))
          (close b)
          (close s1)
          (close s2)))
      """
      assert ExLisp.eval(code) == ["broadcast test", "broadcast test"]
    end

    test "make-concatenated-stream" do
      code = """
      (let* ((s1 (make-string-input-stream "foo "))
             (s2 (make-string-input-stream "bar"))
             (c (make-concatenated-stream s1 s2)))
        (unwind-protect
          (read-line c)
          (close c)
          (close s1)
          (close s2)))
      """
      assert ExLisp.eval(code) == "foo bar"
    end

    test "make-two-way-stream" do
      code = """
      (let* ((in (make-string-input-stream "hello"))
             (out (make-string-output-stream))
             (tw (make-two-way-stream in out)))
        (unwind-protect
          (let ((line (read-line tw)))
            (write-string line tw)
            (get-output-stream-string out))
          (close tw)
          (close in)
          (close out)))
      """
      assert ExLisp.eval(code) == "hello"
    end

    test "with-open-stream macro" do
      code = """
      (with-open-stream (s (make-string-input-stream "macro test"))
        (read-line s))
      """
      assert ExLisp.eval(code) == "macro test"
    end

    test "with-open-file macro" do
      code = """
      (with-open-file (s "mix.exs" :direction :input)
        (streamp s))
      """
      assert ExLisp.eval(code) == :t
    end
  end
end
