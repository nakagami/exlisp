defmodule HashTablesAndStreamsTest do
  use ExUnit.Case

  test "sxhash returns non-negative integer" do
    h1 = ExLisp.eval("(sxhash 123)")
    h2 = ExLisp.eval("(sxhash \"hello\")")
    h3 = ExLisp.eval("(sxhash 'foo)")
    h4 = ExLisp.eval("(sxhash '(1 2 3))")

    assert is_integer(h1) and h1 >= 0
    assert is_integer(h2) and h2 >= 0
    assert is_integer(h3) and h3 >= 0
    assert is_integer(h4) and h4 >= 0
    assert ExLisp.eval("(sxhash \"hello\")") == h2
  end

  test "gethash multiple values support" do
    code = """
    (let ((ht (make-hash-table)))
      (setf (gethash :a ht) 100)
      (multiple-value-bind (val present-p) (gethash :a ht)
        (multiple-value-bind (val2 present2-p) (gethash :b ht)
          (list val present-p val2 present2-p))))
    """

    assert ExLisp.eval(code) == [100, :t, nil, nil]
  end

  test "make-string-input-stream and reading" do
    code = """
    (let ((s (make-string-input-stream "123 456")))
      (unwind-protect
        (list (read s) (read s))
        (close s)))
    """

    assert ExLisp.eval(code) == [123, 456]
  end

  test "make-string-output-stream and writing" do
    code = """
    (let ((s (make-string-output-stream)))
      (unwind-protect
        (progn
          (format s "Hello ~A, count: ~D" "World" 42)
          (get-output-stream-string s))
        (close s)))
    """

    assert ExLisp.eval(code) == "Hello World, count: 42"
  end

  test "with-input-from-string macro" do
    code = """
    (with-input-from-string (s "hello 42 (1 2)")
      (list (read s) (read s) (read s)))
    """

    assert ExLisp.eval(code) == [:hello, 42, [1, 2]]
  end

  test "with-output-to-string macro" do
    code = """
    (with-output-to-string (s)
      (format s "Item ~A = ~D" "A" 10)
      (format s "; Item ~A = ~D" "B" 20))
    """

    assert ExLisp.eval(code) == "Item A = 10; Item B = 20"
  end
end
