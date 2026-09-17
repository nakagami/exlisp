defmodule ExLisp.SequencesAndListsTest do
  use ExUnit.Case, async: false

  test "set operations: union, intersection, set-difference, set-exclusive-or, subsetp" do
    assert ExLisp.eval("(union '(1 2 3) '(2 3 4))") == [1, 2, 3, 4]
    assert ExLisp.eval("(intersection '(1 2 3 4) '(2 4 6))") == [2, 4]
    assert ExLisp.eval("(set-difference '(1 2 3 4) '(2 4))") == [1, 3]
    assert ExLisp.eval("(set-exclusive-or '(1 2 3) '(2 3 4))") == [1, 4]
    assert ExLisp.eval("(subsetp '(1 2) '(1 2 3))") == :t
    assert ExLisp.eval("(subsetp '(1 4) '(1 2 3))") == nil
  end

  test "association list operations: assoc-if, rassoc-if, copy-alist" do
    assert ExLisp.eval("(assoc-if #'evenp '((1 . a) (2 . b) (3 . c)))") == [2 | :b]
    assert ExLisp.eval("(rassoc-if #'oddp '((a . 2) (b . 3) (c . 4)))") == [:b | 3]
    assert ExLisp.eval("(copy-alist '((a . 1) (b . 2)))") == [[:a | 1], [:b | 2]]
  end

  test "mapping operations: maplist, mapl, mapcon" do
    assert ExLisp.eval("(maplist #'length '(1 2 3))") == [3, 2, 1]
    assert ExLisp.eval("(mapcon #'copy-list '(1 2 3))") == [1, 2, 3, 2, 3, 3]
  end

  test "tree operations: tree-equal, sublis, subst-if" do
    assert ExLisp.eval("(tree-equal '(1 (2 3)) '(1 (2 3)))") == :t
    assert ExLisp.eval("(tree-equal '(1 (2 3)) '(1 (2 4)))") == nil
    assert ExLisp.eval("(sublis '((a . 1) (b . 2)) '(a (b c)))") == [1, [2, :c]]
    assert ExLisp.eval("(subst-if 99 #'evenp '(1 (2 (3 4))))") == [1, [99, [3, 99]]]
  end

  test "sequence operations: remove-duplicates, substitute, mismatch, replace, fill, make-sequence, merge" do
    assert ExLisp.eval("(remove-duplicates '(1 2 1 3 2 4))") == [1, 3, 2, 4]
    assert ExLisp.eval("(substitute 9 2 '(1 2 3 2 1))") == [1, 9, 3, 9, 1]
    assert ExLisp.eval("(substitute-if 0 #'evenp '(1 2 3 4 5))") == [1, 0, 3, 0, 5]
    assert ExLisp.eval("(mismatch '(1 2 3 4) '(1 2 9 4))") == 2
    assert ExLisp.eval("(mismatch '(1 2 3) '(1 2 3))") == nil
    assert ExLisp.eval("(fill '(1 2 3 4 5) 0 :start 1 :end 3)") == [1, 0, 0, 4, 5]
    assert ExLisp.eval("(replace '(1 2 3 4 5) '(9 8 7) :start1 1)") == [1, 9, 8, 7, 5]
    assert ExLisp.eval("(make-sequence 'list 3 7)") == [7, 7, 7]
    assert ExLisp.eval("(merge 'list '(1 3 5) '(2 4 6) #'<)") == [1, 2, 3, 4, 5, 6]
    assert ExLisp.eval("(copy-seq '(1 2 3))") == [1, 2, 3]
  end
end
