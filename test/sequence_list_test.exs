defmodule ExLisp.SequenceListTest do
  use ExUnit.Case

  describe "List operations" do
    test "copy-alist" do
      assert ExLisp.eval("""
      (let* ((orig '((a . 1) (b . 2)))
             (copied (copy-alist orig)))
        (equal orig copied))
      """) == :t
    end

    test "pairlis" do
      assert ExLisp.eval("""
      (pairlis '(a b c) '(1 2 3) '((d . 4)))
      """) == [[{:a, 1}, {:b, 2}, {:c, 3}, {:d, 4}]] or
        # pairlis may prepend in order
        ExLisp.eval("""
        (cdr (assoc 'b (pairlis '(a b c) '(1 2 3) '((d . 4)))))
        """) == 2
    end

    test "sublis with key and test" do
      assert ExLisp.eval("""
      (sublis '((x . 1) (y . 2)) '(+ x (* y 3)))
      """) == [:+ , 1, [:*, 2, 3]]
    end

    test "subst, subst-if, subst-if-not" do
      assert ExLisp.eval("""
      (subst 10 'x '(+ x (* x 2)))
      """) == [:+ , 10, [:*, 10, 2]]

      assert ExLisp.eval("""
      (subst-if 0 #'numberp '(a (1 (b 2))))
      """) == [:a, [0, [:b, 0]]]

      assert ExLisp.eval("""
      (subst-if-not 0 (lambda (x) (or (consp x) (symbolp x))) '(a (1 (b 2))))
      """) == [:a, [0, [:b, 0]]]
    end

    test "tree-equal" do
      assert ExLisp.eval("""
      (tree-equal '(1 (2 3)) '(1 (2 3)))
      """) == :t

      assert ExLisp.eval("""
      (tree-equal '(1 (2 3)) '(1 (2 4)))
      """) == nil

      assert ExLisp.eval("""
      (tree-equal '("a" ("b")) '("A" ("B")) :test #'string-equal)
      """) == :t
    end

    test "revappend and nreconc" do
      assert ExLisp.eval("""
      (revappend '(1 2 3) '(4 5))
      """) == [3, 2, 1, 4, 5]

      assert ExLisp.eval("""
      (nreconc (list 1 2 3) '(4 5))
      """) == [3, 2, 1, 4, 5]
    end

    test "ldiff and tailp" do
      assert ExLisp.eval("""
      (let* ((l2 '(c d))
             (l1 (cons 'a (cons 'b l2))))
        (list (tailp l2 l1)
              (tailp '(x y) l1)
              (ldiff l1 l2)))
      """) == [:t, nil, [:a, :b]]
    end

    test "butlast and nbutlast" do
      assert ExLisp.eval("""
      (butlast '(a b c d))
      """) == [:a, :b, :c]

      assert ExLisp.eval("""
      (butlast '(a b c d) 2)
      """) == [:a, :b]
    end
  end

  describe "Sequence operations" do
    test "map-into on lists" do
      assert ExLisp.eval("""
      (map-into (list 1 2 3 4) #'+ '(1 2 3 4) '(10 20 30 40))
      """) == [11, 22, 33, 44]
    end

    test "map-into on vectors" do
      assert ExLisp.eval("""
      (let ((v (vector 1 2 3 4)))
        (map-into v #'* v #(10 10 10 10))
        (list (elt v 0) (elt v 1) (elt v 2) (elt v 3)))
      """) == [10, 20, 30, 40]
    end

    test "substitute and substitute-if" do
      assert ExLisp.eval("""
      (substitute 9 2 '(1 2 3 2 1))
      """) == [1, 9, 3, 9, 1]

      assert ExLisp.eval("""
      (substitute 9 2 '(1 2 3 2 1) :count 1)
      """) == [1, 9, 3, 2, 1]

      assert ExLisp.eval("""
      (substitute 9 2 '(1 2 3 2 1) :count 1 :from-end t)
      """) == [1, 2, 3, 9, 1]

      assert ExLisp.eval("""
      (substitute-if 0 #'evenp '(1 2 3 4 5))
      """) == [1, 0, 3, 0, 5]
    end

    test "remove-duplicates" do
      assert ExLisp.eval("""
      (remove-duplicates '(1 2 1 3 2 4))
      """) == [1, 3, 2, 4]

      assert ExLisp.eval("""
      (remove-duplicates '(1 2 1 3 2 4) :from-end t)
      """) == [1, 2, 3, 4]
    end

    test "find, position, count with keyword arguments" do
      assert ExLisp.eval("""
      (find 3 '(1 2 3 4 3 2 1))
      """) == 3

      assert ExLisp.eval("""
      (position 3 '(1 2 3 4 3 2 1))
      """) == 2

      assert ExLisp.eval("""
      (position 3 '(1 2 3 4 3 2 1) :from-end t)
      """) == 4

      assert ExLisp.eval("""
      (count 3 '(1 2 3 4 3 2 1))
      """) == 2

      assert ExLisp.eval("""
      (count-if #'evenp '(1 2 3 4 5 6))
      """) == 3
    end

    test "search and mismatch" do
      assert ExLisp.eval("""
      (search '(2 3) '(1 2 3 4 2 3 5))
      """) == 1

      assert ExLisp.eval("""
      (search '(2 3) '(1 2 3 4 2 3 5) :from-end t)
      """) == 4

      assert ExLisp.eval("""
      (mismatch '(1 2 3 4) '(1 2 5 4))
      """) == 2

      assert ExLisp.eval("""
      (mismatch '(1 2 3) '(1 2 3))
      """) == nil
    end

    test "fill and replace" do
      assert ExLisp.eval("""
      (fill (list 1 2 3 4 5) 0 :start 1 :end 3)
      """) == [1, 0, 0, 4, 5]

      assert ExLisp.eval("""
      (replace (list 1 2 3 4 5) '(8 9) :start1 1)
      """) == [1, 8, 9, 4, 5]
    end

    test "merge sequences" do
      assert ExLisp.eval("""
      (merge 'list '(1 3 5) '(2 4 6) #'<)
      """) == [1, 2, 3, 4, 5, 6]
    end

    test "reduce with keys" do
      assert ExLisp.eval("""
      (reduce #'+ '(1 2 3 4))
      """) == 10

      assert ExLisp.eval("""
      (reduce #'+ '(1 2 3 4) :initial-value 10)
      """) == 20

      assert ExLisp.eval("""
      (reduce #'cons '(1 2 3 4) :from-end t :initial-value nil)
      """) == [1, 2, 3, 4]
    end

    test "every, some, notany, notevery" do
      assert ExLisp.eval("(every #'evenp '(2 4 6))") == :t
      assert ExLisp.eval("(every #'evenp '(2 3 6))") == nil
      assert ExLisp.eval("(some #'evenp '(1 3 4 5))") == :t
      assert ExLisp.eval("(some #'evenp '(1 3 5))") == nil
      assert ExLisp.eval("(notany #'evenp '(1 3 5))") == :t
      assert ExLisp.eval("(notevery #'evenp '(2 3 4))") == :t
    end

    test "mapc, mapcar, maplist, mapl, mapcan, mapcon" do
      assert ExLisp.eval("""
      (mapcar #'+ '(1 2 3) '(10 20 30))
      """) == [11, 22, 33]

      assert ExLisp.eval("""
      (mapcan (lambda (x) (if (evenp x) (list x x) nil)) '(1 2 3 4))
      """) == [2, 2, 4, 4]

      assert ExLisp.eval("""
      (maplist #'length '(a b c d))
      """) == [4, 3, 2, 1]
    end

    test "sort and stable-sort" do
      assert ExLisp.eval("""
      (sort '(3 1 4 1 5 9 2 6) #'<)
      """) == [1, 1, 2, 3, 4, 5, 6, 9]

      assert ExLisp.eval("""
      (stable-sort '((3 . a) (1 . b) (2 . c) (1 . d)) #'< :key #'car)
      """) == [[{:car, 1}, {:cdr, :b}], [{:car, 1}, {:cdr, :d}], [{:car, 2}, {:cdr, :c}], [{:car, 3}, {:cdr, :a}]] or
        ExLisp.eval("""
        (mapcar #'car (stable-sort '((3 . a) (1 . b) (2 . c) (1 . d)) #'< :key #'car))
        """) == [1, 1, 2, 3]
    end
  end
end
