defmodule ExLisp.IterationTest do
  use ExUnit.Case

  test "dotimes simple count and return" do
    assert ExLisp.eval("""
    (let ((acc 0))
      (dotimes (i 5 acc)
        (setq acc (+ acc i))))
    """) == 10
  end

  test "dotimes return value without result-form is nil" do
    assert ExLisp.eval("""
    (dotimes (i 5)
      i)
    """) == nil
  end

  test "dotimes with explicit return" do
    assert ExLisp.eval("""
    (dotimes (i 10 999)
      (when (= i 3)
        (return i)))
    """) == 3
  end

  test "dotimes var value in result-form is count" do
    assert ExLisp.eval("""
    (dotimes (i 5 i))
    """) == 5
  end

  test "dolist simple iteration" do
    assert ExLisp.eval("""
    (let ((acc 0))
      (dolist (x '(1 2 3 4) acc)
        (setq acc (+ acc x))))
    """) == 10
  end

  test "dolist with explicit return" do
    assert ExLisp.eval("""
    (dolist (x '(1 2 3 4 5) :not-found)
      (when (= x 3)
        (return (* x 10))))
    """) == 30
  end

  test "dolist var value in result-form is nil" do
    assert ExLisp.eval("""
    (dolist (x '(1 2 3) x))
    """) == nil
  end

  test "do parallel binding and stepping" do
    assert ExLisp.eval("""
    (do ((i 0 (1+ i))
         (acc 0 (+ acc i)))
        ((> i 4) acc))
    """) == 10
  end

  test "do swap variables in step (parallel evaluation)" do
    assert ExLisp.eval("""
    (do ((a 1 b)
         (b 2 a)
         (step 0 (1+ step)))
        ((= step 3) (list a b)))
    """) == [2, 1]
  end

  test "do with return" do
    assert ExLisp.eval("""
    (do ((i 0 (1+ i)))
        ((> i 100) :never)
      (when (= i 5)
        (return (* i 2))))
    """) == 10
  end

  test "do* sequential binding and stepping" do
    assert ExLisp.eval("""
    (do* ((x 1 (1+ x))
          (y (* x 2) (* x 2)))
         ((> x 3) y))
    """) == 8
  end

  test "loop simple with return" do
    assert ExLisp.eval("""
    (let ((x 0))
      (loop
        (incf x)
        (when (> x 5)
          (return x))))
    """) == 6
  end

  test "extended loop clauses" do
    assert ExLisp.eval("""
    (loop for x in '(1 2 3 4 5)
          when (oddp x)
          collect x)
    """) == [1, 3, 5]

    assert ExLisp.eval("""
    (loop for i from 1 to 10 sum i)
    """) == 55

    assert ExLisp.eval("""
    (loop for x in '(3 1 4 1 5 9 2 6)
          maximize x)
    """) == 9
  end

  test "dotimes with count <= 0" do
    assert ExLisp.eval("""
    (let ((run nil))
      (dotimes (i 0 :done)
        (setq run t)))
    """) == :done

    assert ExLisp.eval("""
    (dotimes (i -5 :negative)
      :body)
    """) == :negative
  end

  test "dolist with empty list" do
    assert ExLisp.eval("""
    (dolist (x '() :empty)
      :body)
    """) == :empty
  end

  test "do with tagbody and go" do
    assert ExLisp.eval("""
    (let ((acc 0))
      (do ((i 0 (1+ i)))
          ((>= i 5) acc)
        (when (= i 2)
          (go skip))
        (setq acc (+ acc i))
        skip))
    """) == 8
  end

  test "do* with return" do
    assert ExLisp.eval("""
    (do* ((x 1 (1+ x))
          (y (* x 10) (* x 10)))
         ((> x 10) :done)
      (when (= y 30)
        (return (+ x y))))
    """) == 33
  end

  test "dotimes with tagbody and go" do
    assert ExLisp.eval("""
    (let ((acc 0))
      (dotimes (i 5 acc)
        (when (= i 2)
          (go skip))
        (setq acc (+ acc i))
        skip))
    """) == 8
  end

  test "dolist with tagbody and go" do
    assert ExLisp.eval("""
    (let ((acc 0))
      (dolist (x '(1 2 3 4) acc)
        (when (= x 2)
          (go skip))
        (setq acc (+ acc x))
        skip))
    """) == 8
  end

  test "loop with loop-finish" do
    assert ExLisp.eval("""
    (loop for x in '(1 2 3 4 5)
          do (when (= x 4) (loop-finish))
          collect (* x 10))
    """) == [10, 20, 30]
  end
end
