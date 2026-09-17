;;; Runner script for ANSI-TEST suites

(load "examples/ansi_test_harness.lisp")

;; 1. IF
(reset-test-stats)
(load "ansi-test/data-and-control-flow/if.lsp")
(print-test-summary "IF")

;; 2. WHEN
(reset-test-stats)
(load "ansi-test/data-and-control-flow/when.lsp")
(print-test-summary "WHEN")

;; 3. UNLESS
(reset-test-stats)
(load "ansi-test/data-and-control-flow/unless.lsp")
(print-test-summary "UNLESS")

;; 4. AND
(reset-test-stats)
(load "ansi-test/data-and-control-flow/and.lsp")
(print-test-summary "AND")

;; 5. OR
(reset-test-stats)
(load "ansi-test/data-and-control-flow/or.lsp")
(print-test-summary "OR")

;; 6. PROGN
(reset-test-stats)
(load "ansi-test/data-and-control-flow/progn.lsp")
(print-test-summary "PROGN")

;; 7. PROG1
(reset-test-stats)
(load "ansi-test/data-and-control-flow/prog1.lsp")
(print-test-summary "PROG1")

;; 8. PROG2
(reset-test-stats)
(load "ansi-test/data-and-control-flow/prog2.lsp")
(print-test-summary "PROG2")

;; 9. CONS
(reset-test-stats)
(load "ansi-test/cons/cons.lsp")
(print-test-summary "CONS")

;; 10. VALUES
(reset-test-stats)
(load "ansi-test/data-and-control-flow/values.lsp")
(print-test-summary "VALUES")

;; 11. VALUES-LIST
(reset-test-stats)
(load "ansi-test/data-and-control-flow/values-list.lsp")
(print-test-summary "VALUES-LIST")

;; 12. NTH-VALUE
(reset-test-stats)
(load "ansi-test/data-and-control-flow/nth-value.lsp")
(print-test-summary "NTH-VALUE")

;; 13. MULTIPLE-VALUE-LIST
(reset-test-stats)
(load "ansi-test/data-and-control-flow/multiple-value-list.lsp")
(print-test-summary "MULTIPLE-VALUE-LIST")

;; 14. MULTIPLE-VALUE-PROG1
(reset-test-stats)
(load "ansi-test/data-and-control-flow/multiple-value-prog1.lsp")
(print-test-summary "MULTIPLE-VALUE-PROG1")

;; 15. MULTIPLE-VALUE-BIND
(reset-test-stats)
(load "ansi-test/data-and-control-flow/multiple-value-bind.lsp")
(print-test-summary "MULTIPLE-VALUE-BIND")

;; 16. MULTIPLE-VALUE-SETQ
(reset-test-stats)
(load "ansi-test/data-and-control-flow/multiple-value-setq.lsp")
(print-test-summary "MULTIPLE-VALUE-SETQ")

;; 17. MULTIPLE-VALUE-CALL
(reset-test-stats)
(load "ansi-test/data-and-control-flow/multiple-value-call.lsp")
(print-test-summary "MULTIPLE-VALUE-CALL")

;; 18. LET
(reset-test-stats)
(load "ansi-test/data-and-control-flow/let.lsp")
(print-test-summary "LET")

;; 19. LET*
(reset-test-stats)
(load "ansi-test/data-and-control-flow/letstar.lsp")
(print-test-summary "LET*")

;; 20. BLOCK
(reset-test-stats)
(load "ansi-test/data-and-control-flow/block.lsp")
(print-test-summary "BLOCK")

;; 21. RETURN-FROM
(reset-test-stats)
(load "ansi-test/data-and-control-flow/return-from.lsp")
(print-test-summary "RETURN-FROM")

;; 22. RETURN
(reset-test-stats)
(load "ansi-test/data-and-control-flow/return.lsp")
(print-test-summary "RETURN")

;; 23. COND
(reset-test-stats)
(load "ansi-test/data-and-control-flow/cond.lsp")
(print-test-summary "COND")

;; 24. CASE
(reset-test-stats)
(load "ansi-test/data-and-control-flow/case.lsp")
(print-test-summary "CASE")

;; 25. TAGBODY
(reset-test-stats)
(load "ansi-test/data-and-control-flow/tagbody.lsp")
(print-test-summary "TAGBODY")

;; 26. CATCH
(reset-test-stats)
(load "ansi-test/data-and-control-flow/catch.lsp")
(print-test-summary "CATCH")

;; 27. PROG
(reset-test-stats)
(load "ansi-test/data-and-control-flow/prog.lsp")
(print-test-summary "PROG")

;; 28. IDENTITY
(reset-test-stats)
(load "ansi-test/data-and-control-flow/identity.lsp")
(print-test-summary "IDENTITY")

;; 29. CONSTANTLY
(reset-test-stats)
(load "ansi-test/data-and-control-flow/constantly.lsp")
(print-test-summary "CONSTANTLY")

;; 30. COMPLEMENT
(reset-test-stats)
(load "ansi-test/data-and-control-flow/complement.lsp")
(print-test-summary "COMPLEMENT")

;; 31. EVERY
(reset-test-stats)
(load "ansi-test/data-and-control-flow/every.lsp")
(print-test-summary "EVERY")

;; 32. SOME
(reset-test-stats)
(load "ansi-test/data-and-control-flow/some.lsp")
(print-test-summary "SOME")

;; 33. NOTANY
(reset-test-stats)
(load "ansi-test/data-and-control-flow/notany.lsp")
(print-test-summary "NOTANY")

;; 34. NOTEVERY
(reset-test-stats)
(load "ansi-test/data-and-control-flow/notevery.lsp")
(print-test-summary "NOTEVERY")

;; 35. CONSP
(reset-test-stats)
(load "ansi-test/cons/consp.lsp")
(print-test-summary "CONSP")

;; 36. ATOM
(reset-test-stats)
(load "ansi-test/cons/atom.lsp")
(print-test-summary "ATOM")

;; 37. LISTP
(reset-test-stats)
(load "ansi-test/cons/listp.lsp")
(print-test-summary "LISTP")

;; 38. LIST
(reset-test-stats)
(load "ansi-test/cons/list.lsp")
(print-test-summary "LIST")

;; 39. APPEND
(reset-test-stats)
(load "ansi-test/cons/append.lsp")
(print-test-summary "APPEND")

;; 40. SYMBOLP
(reset-test-stats)
(load "ansi-test/symbols/symbolp.lsp")
(print-test-summary "SYMBOLP")

;; 41. KEYWORDP
(reset-test-stats)
(load "ansi-test/symbols/keywordp.lsp")
(print-test-summary "KEYWORDP")

;; 42. ENDP
(reset-test-stats)
(load "ansi-test/cons/endp.lsp")
(print-test-summary "ENDP")

;; 43. REST
(reset-test-stats)
(load "ansi-test/cons/rest.lsp")
(print-test-summary "REST")

;; 44. REVAPPEND
(reset-test-stats)
(load "ansi-test/cons/revappend.lsp")
(print-test-summary "REVAPPEND")

;; 45. NRECONC
(reset-test-stats)
(load "ansi-test/cons/nreconc.lsp")
(print-test-summary "NRECONC")

;; 46. CONS-TEST-03
(reset-test-stats)
(load "ansi-test/cons/cons-test-03.lsp")
(print-test-summary "CONS-TEST-03")

;; 47. LAMBDA-PARAMETERS-LIMIT
(reset-test-stats)
(load "ansi-test/data-and-control-flow/lambda-parameters-limit.lsp")
(print-test-summary "LAMBDA-PARAMETERS-LIMIT")

;; 48. NUMBERP
(reset-test-stats)
(load "ansi-test/numbers/numberp.lsp")
(print-test-summary "NUMBERP")

;; 49. FLOATP
(reset-test-stats)
(load "ansi-test/numbers/floatp.lsp")
(print-test-summary "FLOATP")

;; 50. COMPLEXP
(reset-test-stats)
(load "ansi-test/numbers/complexp.lsp")
(print-test-summary "COMPLEXP")

;; 51. INTEGER-LENGTH
(reset-test-stats)
(load "ansi-test/numbers/integer-length.lsp")
(print-test-summary "INTEGER-LENGTH")

;; 52. HASH-TABLE-P
(reset-test-stats)
(load "ansi-test/hash-tables/hash-table-p.lsp")
(print-test-summary "HASH-TABLE-P")

;; 53. HASH-TABLE-COUNT
(reset-test-stats)
(load "ansi-test/hash-tables/hash-table-count.lsp")
(print-test-summary "HASH-TABLE-COUNT")

;; 54. HASH-TABLE-SIZE
(reset-test-stats)
(load "ansi-test/hash-tables/hash-table-size.lsp")
(print-test-summary "HASH-TABLE-SIZE")

;; 55. CLRHASH
(reset-test-stats)
(load "ansi-test/hash-tables/clrhash.lsp")
(print-test-summary "CLRHASH")

;; 56. REMHASH
(reset-test-stats)
(load "ansi-test/hash-tables/remhash.lsp")
(print-test-summary "REMHASH")

;; 57. EVAL
(reset-test-stats)
(load "ansi-test/eval-and-compile/eval.lsp")
(print-test-summary "EVAL")

;; 58. LOCALLY
(reset-test-stats)
(load "ansi-test/eval-and-compile/locally.lsp")
(print-test-summary "LOCALLY")

;; 59. DECLARATION
(reset-test-stats)
(load "ansi-test/eval-and-compile/declaration.lsp")
(print-test-summary "DECLARATION")

;; 60. DEFINE-SYMBOL-MACRO
(reset-test-stats)
(load "ansi-test/eval-and-compile/define-symbol-macro.lsp")
(print-test-summary "DEFINE-SYMBOL-MACRO")

;; 61. OPTIMIZE
(reset-test-stats)
(load "ansi-test/eval-and-compile/optimize.lsp")
(print-test-summary "OPTIMIZE")

;; 62. SPECIAL
(reset-test-stats)
(load "ansi-test/eval-and-compile/special.lsp")
(print-test-summary "SPECIAL")

;; 63. IGNORE
(reset-test-stats)
(load "ansi-test/eval-and-compile/ignore.lsp")
(print-test-summary "IGNORE")

;; 64. APPLY
(reset-test-stats)
(load "ansi-test/data-and-control-flow/apply.lsp")
(print-test-summary "APPLY")

;; 65. ACONS
(reset-test-stats)
(load "ansi-test/cons/acons.lsp")
(print-test-summary "ACONS")

;; 66. COPY-TREE
(reset-test-stats)
(load "ansi-test/cons/copy-tree.lsp")
(print-test-summary "COPY-TREE")

;; 67. INTEGERP
(reset-test-stats)
(load "ansi-test/numbers/integerp.lsp")
(print-test-summary "INTEGERP")

;; 68. LOGNOT
(reset-test-stats)
(load "ansi-test/numbers/lognot.lsp")
(print-test-summary "LOGNOT")

;; 69. LOGTEST
(reset-test-stats)
(load "ansi-test/numbers/logtest.lsp")
(print-test-summary "LOGTEST")

;; LOGAND
(reset-test-stats)
(load "ansi-test/numbers/logand.lsp")
(print-test-summary "LOGAND")

;; LOGIOR
(reset-test-stats)
(load "ansi-test/numbers/logior.lsp")
(print-test-summary "LOGIOR")

;; LOGXOR
(reset-test-stats)
(load "ansi-test/numbers/logxor.lsp")
(print-test-summary "LOGXOR")

;; LOGEQV
(reset-test-stats)
(load "ansi-test/numbers/logeqv.lsp")
(print-test-summary "LOGEQV")

;; LOGNAND
(reset-test-stats)
(load "ansi-test/numbers/lognand.lsp")
(print-test-summary "LOGNAND")

;; LOGNOR
(reset-test-stats)
(load "ansi-test/numbers/lognor.lsp")
(print-test-summary "LOGNOR")

;; LOGANDC1
(reset-test-stats)
(load "ansi-test/numbers/logandc1.lsp")
(print-test-summary "LOGANDC1")

;; LOGANDC2
(reset-test-stats)
(load "ansi-test/numbers/logandc2.lsp")
(print-test-summary "LOGANDC2")

;; LOGORC1
(reset-test-stats)
(load "ansi-test/numbers/logorc1.lsp")
(print-test-summary "LOGORC1")

;; LOGORC2
(reset-test-stats)
(load "ansi-test/numbers/logorc2.lsp")
(print-test-summary "LOGORC2")

;; LOGCOUNT
(reset-test-stats)
(load "ansi-test/numbers/logcount.lsp")
(print-test-summary "LOGCOUNT")

;; 70. MAKUNBOUND
(reset-test-stats)
(load "ansi-test/symbols/makunbound.lsp")
(print-test-summary "MAKUNBOUND")

;; 71. SYMBOL-FUNCTION
(reset-test-stats)
(load "ansi-test/symbols/symbol-function.lsp")
(print-test-summary "SYMBOL-FUNCTION")

;; 72. CHAR-COMPARE
(reset-test-stats)
(load "ansi-test/characters/char-compare.lsp")
(print-test-summary "CHAR-COMPARE")

;; 73. LOOP
(reset-test-stats)
(load "ansi-test/iteration/loop.lsp")
(print-test-summary "LOOP")

;; 74. LOOP6
(reset-test-stats)
(load "ansi-test/iteration/loop6.lsp")
(print-test-summary "LOOP6")

;; 75. LOOP7
(reset-test-stats)
(load "ansi-test/iteration/loop7.lsp")
(print-test-summary "LOOP7")

;; 76. DRIBBLE
(reset-test-stats)
(load "ansi-test/environment/dribble.lsp")
(print-test-summary "DRIBBLE")

;; 77. ED
(reset-test-stats)
(load "ansi-test/environment/ed.lsp")
(print-test-summary "ED")

;; 78. INSPECT
(reset-test-stats)
(load "ansi-test/environment/inspect.lsp")
(print-test-summary "INSPECT")

