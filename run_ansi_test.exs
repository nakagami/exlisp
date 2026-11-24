# Runner script for ANSI-TEST suites in ExLisp

ansi_test_dir =
  (System.get_env("ANSI_TEST_DIR") || Path.expand("../ansi-test", __DIR__))
  |> Path.expand(__DIR__)

if not File.dir?(ansi_test_dir) do
  IO.puts(:stderr, "Error: ansi-test directory not found at #{ansi_test_dir}")

  IO.puts(
    :stderr,
    "Please clone it with: git clone https://github.com/sbcl/ansi-test #{ansi_test_dir}"
  )

  System.halt(1)
end

suites = [
  {"IF", "data-and-control-flow/if.lsp"},
  {"WHEN", "data-and-control-flow/when.lsp"},
  {"UNLESS", "data-and-control-flow/unless.lsp"},
  {"AND", "data-and-control-flow/and.lsp"},
  {"OR", "data-and-control-flow/or.lsp"},
  {"PROGN", "data-and-control-flow/progn.lsp"},
  {"PROG1", "data-and-control-flow/prog1.lsp"},
  {"PROG2", "data-and-control-flow/prog2.lsp"},
  {"VALUES", "data-and-control-flow/values.lsp"},
  {"VALUES-LIST", "data-and-control-flow/values-list.lsp"},
  {"NTH-VALUE", "data-and-control-flow/nth-value.lsp"},
  {"MULTIPLE-VALUE-LIST", "data-and-control-flow/multiple-value-list.lsp"},
  {"MULTIPLE-VALUE-PROG1", "data-and-control-flow/multiple-value-prog1.lsp"},
  {"MULTIPLE-VALUE-BIND", "data-and-control-flow/multiple-value-bind.lsp"},
  {"MULTIPLE-VALUE-SETQ", "data-and-control-flow/multiple-value-setq.lsp"},
  {"MULTIPLE-VALUE-CALL", "data-and-control-flow/multiple-value-call.lsp"},
  {"LET", "data-and-control-flow/let.lsp"},
  {"LET*", "data-and-control-flow/letstar.lsp"},
  {"BLOCK", "data-and-control-flow/block.lsp"},
  {"RETURN-FROM", "data-and-control-flow/return-from.lsp"},
  {"RETURN", "data-and-control-flow/return.lsp"},
  {"COND", "data-and-control-flow/cond.lsp"},
  {"CASE", "data-and-control-flow/case.lsp"},
  {"TAGBODY", "data-and-control-flow/tagbody.lsp"},
  {"CATCH", "data-and-control-flow/catch.lsp"},
  {"PROG", "data-and-control-flow/prog.lsp"},
  {"IDENTITY", "data-and-control-flow/identity.lsp"},
  {"CONSTANTLY", "data-and-control-flow/constantly.lsp"},
  {"COMPLEMENT", "data-and-control-flow/complement.lsp"},
  {"EVERY", "data-and-control-flow/every.lsp"},
  {"SOME", "data-and-control-flow/some.lsp"},
  {"NOTANY", "data-and-control-flow/notany.lsp"},
  {"NOTEVERY", "data-and-control-flow/notevery.lsp"},
  {"CONSP", "cons/consp.lsp"},
  {"ATOM", "cons/atom.lsp"},
  {"LISTP", "cons/listp.lsp"},
  {"LIST", "cons/list.lsp"},
  {"APPEND", "cons/append.lsp"},
  {"SYMBOLP", "symbols/symbolp.lsp"},
  {"KEYWORDP", "symbols/keywordp.lsp"},
  {"ENDP", "cons/endp.lsp"},
  {"REST", "cons/rest.lsp"},
  {"REVAPPEND", "cons/revappend.lsp"},
  {"NRECONC", "cons/nreconc.lsp"},
  {"CONS-TEST-03", "cons/cons-test-03.lsp"},
  {"LAMBDA-PARAMETERS-LIMIT", "data-and-control-flow/lambda-parameters-limit.lsp"},
  {"NUMBERP", "numbers/numberp.lsp"},
  {"FLOATP", "numbers/floatp.lsp"},
  {"COMPLEXP", "numbers/complexp.lsp"},
  {"INTEGER-LENGTH", "numbers/integer-length.lsp"},
  {"HASH-TABLE-P", "hash-tables/hash-table-p.lsp"},
  {"HASH-TABLE-COUNT", "hash-tables/hash-table-count.lsp"},
  {"HASH-TABLE-SIZE", "hash-tables/hash-table-size.lsp"},
  {"CLRHASH", "hash-tables/clrhash.lsp"},
  {"REMHASH", "hash-tables/remhash.lsp"},
  {"EVAL", "eval-and-compile/eval.lsp"},
  {"LOCALLY", "eval-and-compile/locally.lsp"},
  {"DECLARATION", "eval-and-compile/declaration.lsp"},
  {"DEFINE-SYMBOL-MACRO", "eval-and-compile/define-symbol-macro.lsp"},
  {"OPTIMIZE", "eval-and-compile/optimize.lsp"},
  {"SPECIAL", "eval-and-compile/special.lsp"},
  {"IGNORE", "eval-and-compile/ignore.lsp"},
  {"APPLY", "data-and-control-flow/apply.lsp"},
  {"ACONS", "cons/acons.lsp"},
  {"COPY-TREE", "cons/copy-tree.lsp"},
  {"INTEGERP", "numbers/integerp.lsp"},
  {"LOGNOT", "numbers/lognot.lsp"},
  {"LOGTEST", "numbers/logtest.lsp"},
  {"LOGAND", "numbers/logand.lsp"},
  {"LOGIOR", "numbers/logior.lsp"},
  {"LOGXOR", "numbers/logxor.lsp"},
  {"LOGEQV", "numbers/logeqv.lsp"},
  {"LOGNAND", "numbers/lognand.lsp"},
  {"LOGNOR", "numbers/lognor.lsp"},
  {"LOGANDC1", "numbers/logandc1.lsp"},
  {"LOGANDC2", "numbers/logandc2.lsp"},
  {"LOGORC1", "numbers/logorc1.lsp"},
  {"LOGORC2", "numbers/logorc2.lsp"},
  {"LOGCOUNT", "numbers/logcount.lsp"},
  {"ABS", "numbers/abs.lsp"},
  {"ACOS", "numbers/acos.lsp"},
  {"ACOSH", "numbers/acosh.lsp"},
  {"ARITHMETIC-ERROR", "numbers/arithmetic-error.lsp"},
  {"ASH", "numbers/ash.lsp"},
  {"ASIN", "numbers/asin.lsp"},
  {"ASINH", "numbers/asinh.lsp"},
  {"ATAN", "numbers/atan.lsp"},
  {"ATANH", "numbers/atanh.lsp"},
  {"BOOLE", "numbers/boole.lsp"},
  {"BYTE", "numbers/byte.lsp"},
  {"CEILING", "numbers/ceiling.lsp"},
  {"CIS", "numbers/cis.lsp"},
  {"COMPLEX", "numbers/complex.lsp"},
  {"CONJUGATE", "numbers/conjugate.lsp"},
  {"COS", "numbers/cos.lsp"},
  {"COSH", "numbers/cosh.lsp"},
  {"DECF", "numbers/decf.lsp"},
  {"DEPOSIT-FIELD", "numbers/deposit-field.lsp"},
  {"DIVIDE", "numbers/divide.lsp"},
  {"DPB", "numbers/dpb.lsp"},
  {"EPSILONS", "numbers/epsilons.lsp"},
  {"EVENP", "numbers/evenp.lsp"},
  {"EXP", "numbers/exp.lsp"},
  {"EXPT", "numbers/expt.lsp"},
  {"FCEILING", "numbers/fceiling.lsp"},
  {"FFLOOR", "numbers/ffloor.lsp"},
  {"FLOAT", "numbers/float.lsp"},
  {"FLOOR", "numbers/floor.lsp"},
  {"FROUND", "numbers/fround.lsp"},
  {"FTRUNCATE", "numbers/ftruncate.lsp"},
  {"GCD", "numbers/gcd.lsp"},
  {"IMAGPART", "numbers/imagpart.lsp"},
  {"INCF", "numbers/incf.lsp"},
  {"ISQRT", "numbers/isqrt.lsp"},
  {"LCM", "numbers/lcm.lsp"},
  {"LDB", "numbers/ldb.lsp"},
  {"LOG", "numbers/log.lsp"},
  {"LOGBITP", "numbers/logbitp.lsp"},
  {"MAKE-RANDOM-STATE", "numbers/make-random-state.lsp"},
  {"MASK-FIELD", "numbers/mask-field.lsp"},
  {"MAX", "numbers/max.lsp"},
  {"MIN", "numbers/min.lsp"},
  {"MINUS", "numbers/minus.lsp"},
  {"MINUSP", "numbers/minusp.lsp"},
  {"NUMBER-COMPARISON", "numbers/number-comparison.lsp"},
  {"NUMERATOR-DENOMINATOR", "numbers/numerator-denominator.lsp"},
  {"ODDP", "numbers/oddp.lsp"},
  {"ONEMINUS", "numbers/oneminus.lsp"},
  {"ONEPLUS", "numbers/oneplus.lsp"},
  {"PARSE-INTEGER", "numbers/parse-integer.lsp"},
  {"PHASE", "numbers/phase.lsp"},
  {"PLUS", "numbers/plus.lsp"},
  {"PLUSP", "numbers/plusp.lsp"},
  {"RANDOM-STATE-P", "numbers/random-state-p.lsp"},
  {"RANDOM", "numbers/random.lsp"},
  {"RATIONAL", "numbers/rational.lsp"},
  {"RATIONALIZE", "numbers/rationalize.lsp"},
  {"RATIONALP", "numbers/rationalp.lsp"},
  {"REAL", "numbers/real.lsp"},
  {"REALP", "numbers/realp.lsp"},
  {"REALPART", "numbers/realpart.lsp"},
  {"ROUND", "numbers/round.lsp"},
  {"SIGNUM", "numbers/signum.lsp"},
  {"SIN", "numbers/sin.lsp"},
  {"SINH", "numbers/sinh.lsp"},
  {"SQRT", "numbers/sqrt.lsp"},
  {"TAN", "numbers/tan.lsp"},
  {"TANH", "numbers/tanh.lsp"},
  {"TIMES", "numbers/times.lsp"},
  {"TRUNCATE", "numbers/truncate.lsp"},
  {"UPGRADED-COMPLEX-PART-TYPE", "numbers/upgraded-complex-part-type.lsp"},
  {"ZEROP", "numbers/zerop.lsp"},
  {"MAKUNBOUND", "symbols/makunbound.lsp"},
  {"SYMBOL-FUNCTION", "symbols/symbol-function.lsp"},
  {"BOUNDP", "symbols/boundp.lsp"},
  {"COPY-SYMBOL", "symbols/copy-symbol.lsp"},
  {"GET", "symbols/get.lsp"},
  {"MAKE-SYMBOL", "symbols/make-symbol.lsp"},
  {"REMPROP", "symbols/remprop.lsp"},
  {"SET", "symbols/set.lsp"},
  {"SPECIAL-OPERATOR-P", "symbols/special-operator-p.lsp"},
  {"SYMBOL-NAME", "symbols/symbol-name.lsp"},
  # Character suites
  {"CHAR-COMPARE", "characters/char-compare.lsp"},
  {"CHARACTER", "characters/character.lsp"},
  {"NAME-CHAR", "characters/name-char.lsp"},
  # String suites
  {"BASE-STRING", "strings/base-string.lsp"},
  {"CHAR-SCHAR", "strings/char-schar.lsp"},
  {"MAKE-STRING", "strings/make-string.lsp"},
  {"NSTRING-CAPITALIZE", "strings/nstring-capitalize.lsp"},
  {"NSTRING-DOWNCASE", "strings/nstring-downcase.lsp"},
  {"NSTRING-UPCASE", "strings/nstring-upcase.lsp"},
  {"SIMPLE-BASE-STRING", "strings/simple-base-string.lsp"},
  {"SIMPLE-STRING", "strings/simple-string.lsp"},
  {"SIMPLE-STRING-P", "strings/simple-string-p.lsp"},
  {"STRING", "strings/string.lsp"},
  {"STRING-CAPITALIZE", "strings/string-capitalize.lsp"},
  {"STRING-COMPARISONS", "strings/string-comparisons.lsp"},
  {"STRING-DOWNCASE", "strings/string-downcase.lsp"},
  {"STRING-LEFT-TRIM", "strings/string-left-trim.lsp"},
  {"STRING-RIGHT-TRIM", "strings/string-right-trim.lsp"},
  {"STRING-TRIM", "strings/string-trim.lsp"},
  {"STRING-UPCASE", "strings/string-upcase.lsp"},
  {"STRINGP", "strings/stringp.lsp"},
  # Array suites
  {"ARRAYP", "arrays/arrayp.lsp"},
  {"VECTORP", "arrays/vectorp.lsp"},
  {"ARRAY-RANK", "arrays/array-rank.lsp"},
  {"ARRAY-DIMENSION", "arrays/array-dimension.lsp"},
  {"ARRAY-DIMENSIONS", "arrays/array-dimensions.lsp"},
  {"ARRAY-TOTAL-SIZE", "arrays/array-total-size.lsp"},
  {"AREF", "arrays/aref.lsp"},
  {"ROW-MAJOR-AREF", "arrays/row-major-aref.lsp"},
  {"ARRAY-IN-BOUNDS-P", "arrays/array-in-bounds-p.lsp"},
  {"MAKE-ARRAY", "arrays/make-array.lsp"},
  {"ADJUST-ARRAY", "arrays/adjust-array.lsp"},
  {"ARRAY-ROW-MAJOR-INDEX", "arrays/array-row-major-index.lsp"},
  {"FILL-POINTER", "arrays/fill-pointer.lsp"},
  {"VECTOR-PUSH", "arrays/vector-push.lsp"},
  {"VECTOR-POP", "arrays/vector-pop.lsp"},
  {"VECTOR-PUSH-EXTEND", "arrays/vector-push-extend.lsp"},
  {"ADJUSTABLE-ARRAY-P", "arrays/adjustable-array-p.lsp"},
  {"ARRAY-DISPLACEMENT", "arrays/array-displacement.lsp"},
  {"ARRAY-ELEMENT-TYPE", "arrays/array-element-type.lsp"},
  {"ARRAY-HAS-FILL-POINTER-P", "arrays/array-has-fill-pointer-p.lsp"},
  {"ARRAY-AS-CLASS", "arrays/array-as-class.lsp"},
  {"ARRAY-MISC", "arrays/array-misc.lsp"},
  {"ARRAY-T", "arrays/array-t.lsp"},
  {"ARRAY", "arrays/array.lsp"},
  {"BIT-AND", "arrays/bit-and.lsp"},
  {"BIT-ANDC1", "arrays/bit-andc1.lsp"},
  {"BIT-ANDC2", "arrays/bit-andc2.lsp"},
  {"BIT-EQV", "arrays/bit-eqv.lsp"},
  {"BIT-IOR", "arrays/bit-ior.lsp"},
  {"BIT-NAND", "arrays/bit-nand.lsp"},
  {"BIT-NOR", "arrays/bit-nor.lsp"},
  {"BIT-NOT", "arrays/bit-not.lsp"},
  {"BIT-ORC1", "arrays/bit-orc1.lsp"},
  {"BIT-ORC2", "arrays/bit-orc2.lsp"},
  {"BIT-XOR", "arrays/bit-xor.lsp"},
  {"BIT", "arrays/bit.lsp"},
  {"SBIT", "arrays/sbit.lsp"},
  {"BIT-VECTOR-P", "arrays/bit-vector-p.lsp"},
  {"BIT-VECTOR", "arrays/bit-vector.lsp"},
  {"SIMPLE-BIT-VECTOR-P", "arrays/simple-bit-vector-p.lsp"},
  {"SIMPLE-BIT-VECTOR", "arrays/simple-bit-vector.lsp"},
  {"SIMPLE-VECTOR-P", "arrays/simple-vector-p.lsp"},
  {"SIMPLE-ARRAY-T", "arrays/simple-array-t.lsp"},
  {"SIMPLE-ARRAY", "arrays/simple-array.lsp"},
  {"SVREF", "arrays/svref.lsp"},
  {"UPGRADED-ARRAY-ELEMENT-TYPE", "arrays/upgraded-array-element-type.lsp"},
  {"VECTOR", "arrays/vector.lsp"},
  {"DEFPACKAGE", "packages/defpackage.lsp"},
  {"DELETE-PACKAGE", "packages/delete-package.lsp"},
  {"DO-ALL-SYMBOLS", "packages/do-all-symbols.lsp"},
  {"DO-EXTERNAL-SYMBOLS", "packages/do-external-symbols.lsp"},
  {"DO-SYMBOLS", "packages/do-symbols.lsp"},
  {"EXPORT", "packages/export.lsp"},
  {"FIND-ALL-SYMBOLS", "packages/find-all-symbols.lsp"},
  {"FIND-PACKAGE", "packages/find-package.lsp"},
  {"FIND-SYMBOL", "packages/find-symbol.lsp"},
  {"IMPORT", "packages/import.lsp"},
  {"IN-PACKAGE", "packages/in-package.lsp"},
  {"INTERN", "packages/intern.lsp"},
  {"KEYWORD", "packages/keyword.lsp"},
  {"LIST-ALL-PACKAGES", "packages/list-all-packages.lsp"},
  {"MAKE-PACKAGE", "packages/make-package.lsp"},
  {"PACKAGE-ERROR", "packages/package-error.lsp"},
  {"PACKAGE-ERROR-PACKAGE", "packages/package-error-package.lsp"},
  {"PACKAGE-NAME", "packages/package-name.lsp"},
  {"PACKAGE-NICKNAMES", "packages/package-nicknames.lsp"},
  {"PACKAGEP", "packages/packagep.lsp"},
  {"PACKAGE-SHADOWING-SYMBOLS", "packages/package-shadowing-symbols.lsp"},
  {"PACKAGE-USED-BY-LIST", "packages/package-used-by-list.lsp"},
  {"PACKAGE-USE-LIST", "packages/package-use-list.lsp"},
  {"RENAME-PACKAGE", "packages/rename-package.lsp"},
  {"SHADOWING-IMPORT", "packages/shadowing-import.lsp"},
  {"SHADOW", "packages/shadow.lsp"},
  {"UNEXPORT", "packages/unexport.lsp"},
  {"UNINTERN", "packages/unintern.lsp"},
  {"UNUSE-PACKAGE", "packages/unuse-package.lsp"},
  {"USE-PACKAGE", "packages/use-package.lsp"},
  {"WITH-PACKAGE-ITERATOR", "packages/with-package-iterator.lsp"},
  {"ABORT", "conditions/abort.lsp"},
  {"ASSERT", "conditions/assert.lsp"},
  {"CELL-ERROR-NAME", "conditions/cell-error-name.lsp"},
  {"CERROR", "conditions/cerror.lsp"},
  {"CHECK-TYPE", "conditions/check-type.lsp"},
  {"COMPUTE-RESTARTS", "conditions/compute-restarts.lsp"},
  {"CONDITION", "conditions/condition.lsp"},
  {"CONTINUE", "conditions/continue.lsp"},
  {"DEFINE-CONDITION", "conditions/define-condition.lsp"},
  {"ERROR", "conditions/error.lsp"},
  {"HANDLER-BIND", "conditions/handler-bind.lsp"},
  {"HANDLER-CASE", "conditions/handler-case.lsp"},
  {"IGNORE-ERRORS", "conditions/ignore-errors.lsp"},
  {"INVOKE-DEBUGGER", "conditions/invoke-debugger.lsp"},
  {"MAKE-CONDITION", "conditions/make-condition.lsp"},
  {"MUFFLE-WARNING", "conditions/muffle-warning.lsp"},
  {"RESTART-BIND", "conditions/restart-bind.lsp"},
  {"RESTART-CASE", "conditions/restart-case.lsp"},
  {"STORE-VALUE", "conditions/store-value.lsp"},
  {"USE-VALUE", "conditions/use-value.lsp"},
  {"WARN", "conditions/warn.lsp"},
  {"WITH-CONDITION-RESTARTS", "conditions/with-condition-restarts.lsp"},
  {"WITH-SIMPLE-RESTART", "conditions/with-simple-restart.lsp"},
  {"COPY-READTABLE", "reader/copy-readtable.lsp"},
  {"DISPATCH-MACRO-CHARACTERS", "reader/dispatch-macro-characters.lsp"},
  {"GET-MACRO-CHARACTER", "reader/get-macro-character.lsp"},
  {"READ-DELIMITED-LIST", "reader/read-delimited-list.lsp"},
  {"READ-FROM-STRING", "reader/read-from-string.lsp"},
  {"READ-PRESERVING-WHITESPACE", "reader/read-preserving-whitespace.lsp"},
  {"READ-SUPPRESS", "reader/read-suppress.lsp"},
  {"READ", "reader/read.lsp"},
  {"READTABLE-CASE", "reader/readtable-case.lsp"},
  {"READTABLEP", "reader/readtablep.lsp"},
  {"SET-MACRO-CHARACTER", "reader/set-macro-character.lsp"},
  {"BROADCAST-STREAM-STREAMS", "streams/broadcast-stream-streams.lsp"},
  {"CLEAR-INPUT", "streams/clear-input.lsp"},
  {"CLEAR-OUTPUT", "streams/clear-output.lsp"},
  {"CONCATENATED-STREAM-STREAMS", "streams/concatenated-stream-streams.lsp"},
  {"ECHO-STREAM-INPUT-STREAM", "streams/echo-stream-input-stream.lsp"},
  {"ECHO-STREAM-OUTPUT-STREAM", "streams/echo-stream-output-stream.lsp"},
  {"FILE-LENGTH", "streams/file-length.lsp"},
  {"FILE-POSITION", "streams/file-position.lsp"},
  {"FILE-STRING-LENGTH", "streams/file-string-length.lsp"},
  {"FINISH-OUTPUT", "streams/finish-output.lsp"},
  {"FORCE-OUTPUT", "streams/force-output.lsp"},
  {"FRESH-LINE", "streams/fresh-line.lsp"},
  {"GET-OUTPUT-STREAM-STRING", "streams/get-output-stream-string.lsp"},
  {"INPUT-STREAM-P", "streams/input-stream-p.lsp"},
  {"INTERACTIVE-STREAM-P", "streams/interactive-stream-p.lsp"},
  {"LISTEN", "streams/listen.lsp"},
  {"MAKE-BROADCAST-STREAM", "streams/make-broadcast-stream.lsp"},
  {"MAKE-CONCATENATED-STREAM", "streams/make-concatenated-stream.lsp"},
  {"MAKE-ECHO-STREAM", "streams/make-echo-stream.lsp"},
  {"MAKE-STRING-INPUT-STREAM", "streams/make-string-input-stream.lsp"},
  {"MAKE-STRING-OUTPUT-STREAM", "streams/make-string-output-stream.lsp"},
  {"MAKE-SYNONYM-STREAM", "streams/make-synonym-stream.lsp"},
  {"MAKE-TWO-WAY-STREAM", "streams/make-two-way-stream.lsp"},
  {"OPEN-STREAM-P", "streams/open-stream-p.lsp"},
  {"OPEN", "streams/open.lsp"},
  {"OUTPUT-STREAM-P", "streams/output-stream-p.lsp"},
  {"PEEK-CHAR", "streams/peek-char.lsp"},
  {"READ-BYTE", "streams/read-byte.lsp"},
  {"READ-CHAR-NO-HANG", "streams/read-char-no-hang.lsp"},
  {"READ-CHAR", "streams/read-char.lsp"},
  {"READ-LINE", "streams/read-line.lsp"},
  {"READ-SEQUENCE", "streams/read-sequence.lsp"},
  {"STREAM-ELEMENT-TYPE", "streams/stream-element-type.lsp"},
  {"STREAM-ERROR-STREAM", "streams/stream-error-stream.lsp"},
  {"STREAM-EXTERNAL-FORMAT", "streams/stream-external-format.lsp"},
  {"STREAMP", "streams/streamp.lsp"},
  {"SYNONYM-STREAM-SYMBOL", "streams/synonym-stream-symbol.lsp"},
  {"TERPRI", "streams/terpri.lsp"},
  {"TWO-WAY-STREAM-INPUT-STREAM", "streams/two-way-stream-input-stream.lsp"},
  {"TWO-WAY-STREAM-OUTPUT-STREAM", "streams/two-way-stream-output-stream.lsp"},
  {"UNREAD-CHAR", "streams/unread-char.lsp"},
  {"WITH-INPUT-FROM-STRING", "streams/with-input-from-string.lsp"},
  {"WITH-OPEN-FILE", "streams/with-open-file.lsp"},
  {"WITH-OPEN-STREAM", "streams/with-open-stream.lsp"},
  {"WITH-OUTPUT-TO-STRING", "streams/with-output-to-string.lsp"},
  {"WRITE-CHAR", "streams/write-char.lsp"},
  {"WRITE-LINE", "streams/write-line.lsp"},
  {"WRITE-SEQUENCE", "streams/write-sequence.lsp"},
  {"WRITE-STRING", "streams/write-string.lsp"},
  {"LOOP", "iteration/loop.lsp"},
  {"LOOP6", "iteration/loop6.lsp"},
  {"LOOP7", "iteration/loop7.lsp"},
  {"DRIBBLE", "environment/dribble.lsp"},
  {"ED", "environment/ed.lsp"},
  {"INSPECT", "environment/inspect.lsp"},
  # Cons and List suites (Step 4)
  {"ADJOIN", "cons/adjoin.lsp"},
  {"ASSOC", "cons/assoc.lsp"},
  {"ASSOC-IF", "cons/assoc-if.lsp"},
  {"ASSOC-IF-NOT", "cons/assoc-if-not.lsp"},
  {"BUTLAST", "cons/butlast.lsp"},
  {"CONS", "cons/cons.lsp"},
  {"CONS-TEST-01", "cons/cons-test-01.lsp"},
  {"CONS-TEST-05", "cons/cons-test-05.lsp"},
  {"COPY-ALIST", "cons/copy-alist.lsp"},
  {"COPY-LIST", "cons/copy-list.lsp"},
  {"CXR", "cons/cxr.lsp"},
  {"GETF", "cons/getf.lsp"},
  {"GET-PROPERTIES", "cons/get-properties.lsp"},
  {"INTERSECTION", "cons/intersection.lsp"},
  {"LAST", "cons/last.lsp"},
  {"LDIFF", "cons/ldiff.lsp"},
  {"LIST-LENGTH", "cons/list-length.lsp"},
  {"MAKE-LIST", "cons/make-list.lsp"},
  {"MAPC", "cons/mapc.lsp"},
  {"MAPCAN", "cons/mapcan.lsp"},
  {"MAPCAR", "cons/mapcar.lsp"},
  {"MAPCON", "cons/mapcon.lsp"},
  {"MAPL", "cons/mapl.lsp"},
  {"MAPLIST", "cons/maplist.lsp"},
  {"MEMBER", "cons/member.lsp"},
  {"MEMBER-IF", "cons/member-if.lsp"},
  {"MEMBER-IF-NOT", "cons/member-if-not.lsp"},
  {"NBUTLAST", "cons/nbutlast.lsp"},
  {"NCONC", "cons/nconc.lsp"},
  {"NINTERSECTION", "cons/nintersection.lsp"},
  {"NSET-DIFFERENCE", "cons/nset-difference.lsp"},
  {"NSET-EXCLUSIVE-OR", "cons/nset-exclusive-or.lsp"},
  {"NSUBLIS", "cons/nsublis.lsp"},
  {"NSUBST", "cons/nsubst.lsp"},
  {"NSUBST-IF", "cons/nsubst-if.lsp"},
  {"NSUBST-IF-NOT", "cons/nsubst-if-not.lsp"},
  {"NTH", "cons/nth.lsp"},
  {"NTHCDR", "cons/nthcdr.lsp"},
  {"NUNION", "cons/nunion.lsp"},
  {"PAIRLIS", "cons/pairlis.lsp"},
  {"POP", "cons/pop.lsp"},
  {"PUSH", "cons/push.lsp"},
  {"PUSHNEW", "cons/pushnew.lsp"},
  {"RASSOC", "cons/rassoc.lsp"},
  {"RASSOC-IF", "cons/rassoc-if.lsp"},
  {"RASSOC-IF-NOT", "cons/rassoc-if-not.lsp"},
  {"REMF", "cons/remf.lsp"},
  {"RPLACA", "cons/rplaca.lsp"},
  {"RPLACD", "cons/rplacd.lsp"},
  {"SET-DIFFERENCE", "cons/set-difference.lsp"},
  {"SET-EXCLUSIVE-OR", "cons/set-exclusive-or.lsp"},
  {"SUBLIS", "cons/sublis.lsp"},
  {"SUBSETP", "cons/subsetp.lsp"},
  {"SUBST", "cons/subst.lsp"},
  {"SUBST-IF", "cons/subst-if.lsp"},
  {"SUBST-IF-NOT", "cons/subst-if-not.lsp"},
  {"TAILP", "cons/tailp.lsp"},
  {"TREE-EQUAL", "cons/tree-equal.lsp"},
  {"UNION", "cons/union.lsp"},
  # Sequence suites (Step 5)
  {"CONCATENATE", "sequences/concatenate.lsp"},
  {"COPY-SEQ", "sequences/copy-seq.lsp"},
  {"COUNT", "sequences/count.lsp"},
  {"COUNT-IF", "sequences/count-if.lsp"},
  {"COUNT-IF-NOT", "sequences/count-if-not.lsp"},
  {"ELT", "sequences/elt.lsp"},
  {"FILL", "sequences/fill.lsp"},
  {"FILL-STRINGS", "sequences/fill-strings.lsp"},
  {"FIND", "sequences/find.lsp"},
  {"FIND-IF", "sequences/find-if.lsp"},
  {"FIND-IF-NOT", "sequences/find-if-not.lsp"},
  {"LENGTH", "sequences/length.lsp"},
  {"MAKE-SEQUENCE", "sequences/make-sequence.lsp"},
  {"MAP", "sequences/map.lsp"},
  {"MAP-INTO", "sequences/map-into.lsp"},
  {"MERGE", "sequences/merge.lsp"},
  {"MISMATCH", "sequences/mismatch.lsp"},
  {"NREVERSE", "sequences/nreverse.lsp"},
  {"NSUBSTITUTE", "sequences/nsubstitute.lsp"},
  {"NSUBSTITUTE-IF", "sequences/nsubstitute-if.lsp"},
  {"NSUBSTITUTE-IF-NOT", "sequences/nsubstitute-if-not.lsp"},
  {"POSITION", "sequences/position.lsp"},
  {"POSITION-IF", "sequences/position-if.lsp"},
  {"POSITION-IF-NOT", "sequences/position-if-not.lsp"},
  {"REDUCE", "sequences/reduce.lsp"},
  {"REMOVE", "sequences/remove.lsp"},
  {"REMOVE-DUPLICATES", "sequences/remove-duplicates.lsp"},
  {"REPLACE", "sequences/replace.lsp"},
  {"REVERSE", "sequences/reverse.lsp"},
  {"SEARCH-BITVECTOR", "sequences/search-bitvector.lsp"},
  {"SEARCH-LIST", "sequences/search-list.lsp"},
  {"SEARCH-STRING", "sequences/search-string.lsp"},
  {"SEARCH-VECTOR", "sequences/search-vector.lsp"},
  {"SORT", "sequences/sort.lsp"},
  {"STABLE-SORT", "sequences/stable-sort.lsp"},
  {"SUBSEQ", "sequences/subseq.lsp"},
  {"SUBSTITUTE", "sequences/substitute.lsp"},
  {"SUBSTITUTE-IF", "sequences/substitute-if.lsp"},
  {"SUBSTITUTE-IF-NOT", "sequences/substitute-if-not.lsp"}
]

aux_files = [
  Path.join(ansi_test_dir, "auxiliary/ansi-aux-macros.lsp"),
  Path.join(ansi_test_dir, "auxiliary/cl-symbols-aux.lsp"),
  Path.join(ansi_test_dir, "auxiliary/random-aux.lsp"),
  Path.join(ansi_test_dir, "auxiliary/types-aux.lsp"),
  Path.join(ansi_test_dir, "auxiliary/array-aux.lsp"),
  Path.join(ansi_test_dir, "auxiliary/bit-aux.lsp"),
  Path.join(ansi_test_dir, "auxiliary/char-aux.lsp"),
  Path.join(ansi_test_dir, "auxiliary/string-aux.lsp"),
  Path.join(ansi_test_dir, "auxiliary/cons-aux.lsp"),
  Path.join(ansi_test_dir, "auxiliary/remove-aux.lsp"),
  Path.join(ansi_test_dir, "auxiliary/remove-duplicates-aux.lsp"),
  Path.join(ansi_test_dir, "auxiliary/search-aux.lsp"),
  Path.join(ansi_test_dir, "auxiliary/sort-aux.lsp"),
  Path.join(ansi_test_dir, "auxiliary/subseq-aux.lsp"),
  Path.join(ansi_test_dir, "auxiliary/package-aux.lsp"),
  Path.join(ansi_test_dir, "auxiliary/packages00-aux.lsp"),
  Path.join(ansi_test_dir, "auxiliary/define-condition-aux.lsp"),
  Path.join(ansi_test_dir, "auxiliary/numbers-aux.lsp"),
  Path.join(ansi_test_dir, "auxiliary/times-aux.lsp"),
  Path.join(ansi_test_dir, "auxiliary/gcd-aux.lsp"),
  Path.join(ansi_test_dir, "auxiliary/reader-aux.lsp"),
  Path.join(ansi_test_dir, "auxiliary/floor-aux.lsp"),
  Path.join(ansi_test_dir, "auxiliary/ceiling-aux.lsp"),
  Path.join(ansi_test_dir, "auxiliary/truncate-aux.lsp"),
  Path.join(ansi_test_dir, "auxiliary/round-aux.lsp"),
  Path.join(ansi_test_dir, "auxiliary/ffloor-aux.lsp"),
  Path.join(ansi_test_dir, "auxiliary/fceiling-aux.lsp"),
  Path.join(ansi_test_dir, "auxiliary/ftruncate-aux.lsp"),
  Path.join(ansi_test_dir, "auxiliary/fround-aux.lsp"),
  Path.join(ansi_test_dir, "cl-symbol-names.lsp"),
  Path.join(ansi_test_dir, "universe.lsp"),
  Path.join(ansi_test_dir, "auxiliary/ansi-aux.lsp"),
  Path.join(ansi_test_dir, "cons-aux.lsp")
]

ExLisp.eval("""
(progn
  (unless (find-package "REGRESSION-TEST")
    (make-package "REGRESSION-TEST" :nicknames '("RT" "RTEST") :use '("COMMON-LISP")))
  (unless (find-package "CL-TEST")
    (make-package "CL-TEST" :use '("COMMON-LISP" "REGRESSION-TEST" "COMMON-LISP-USER"))))
""")

ExLisp.eval("(in-package \"CL-TEST\")")
ExLisp.load_file(Path.expand("examples/ansi_test_harness.lisp", __DIR__))

Enum.each(aux_files, fn f ->
  if File.exists?(f) do
    try do
      ExLisp.load_file(f)
    rescue
      _ -> :ok
    end
  end
end)

ExLisp.eval("(defmacro expand-in-current-env (form) form)")

previous_package = ExLisp.Package.current_package()
ExLisp.Package.set_current_package("COMMON-LISP-USER")

try do
  ExLisp.Env.put_fun(:safely_delete_package, fn package ->
    if found = ExLisp.Package.find_package(package) do
      Enum.each(found.used_by_list, fn using_name ->
        ExLisp.Package.unuse_package(found, using_name)
      end)

      ExLisp.Package.delete_package(package)
    end
  end)

  ExLisp.Env.put_fun(:delete_package, &ExLisp.Package.delete_package/1)
  ExLisp.Env.put_fun(:package_name, &ExLisp.Package.package_name/1)

  ExLisp.Env.put_fun(:unexport, fn symbols, package ->
    ExLisp.Package.unexport(symbols, package)
  end)

  ExLisp.Env.put_fun(
    :unintern,
    ExLisp.Closure.new(
      fn
        [symbol] -> ExLisp.Package.unintern(symbol)
        [symbol, package] -> ExLisp.Package.unintern(symbol, package)
      end,
      :unintern
    )
  )
after
  ExLisp.Package.set_current_package(previous_package)
end

ExLisp.Condition.init_condition_hierarchy()
ExLisp.Env.put_var(:"regression-test.*compile-tests*", nil)
ExLisp.Env.put_var(:"regression-test.*compile_tests*", nil)

ExLisp.Env.put_fun(:has_non_abort_restart, fn condition ->
  result =
    if Enum.any?(ExLisp.Condition.compute_restarts(condition), fn restart ->
         ExLisp.Builtins.restart_name(restart) != :abort
       end) do
      :success
    else
      :fail
    end

  throw({:lisp_throw, :handled, result})
end)

functions_to_compile = [
  "%values-equal",
  "%normalize-expected-val",
  "subseq-equalp",
  "search-check",
  "remove-check",
  "remove-duplicates-check",
  "sort-check",
  "subseq-check",
  "substitute-check",
  "make-random-element",
  "make-random-remove-input"
]

Enum.each(functions_to_compile, fn f ->
  try do
    ExLisp.eval("(compile '#{f})")
  rescue
    _ -> :ok
  end
end)

cli_args = System.argv()

target_suites =
  if cli_args != [] do
    Enum.map(cli_args, fn arg ->
      base = Path.basename(arg, ".lsp")
      suite_name = String.upcase(base)

      case Enum.find(suites, fn {n, p} ->
             n == suite_name or p == arg or Path.basename(p, ".lsp") == base
           end) do
        {n, p} -> {n, p}
        nil -> {suite_name, arg}
      end
    end)
  else
    suites
  end

File.mkdir_p!(Path.join(ansi_test_dir, "sandbox/scratch"))

total_failed =
  Enum.reduce(target_suites, 0, fn {name, rel_path}, acc ->
    full_path =
      if Path.type(rel_path) == :absolute, do: rel_path, else: Path.join(ansi_test_dir, rel_path)

    IO.puts("Loading #{name} (#{full_path})...")
    ExLisp.MutableCons.reset()
    ExLisp.eval("(reset-test-stats)")

    File.cd!(Path.join(ansi_test_dir, "sandbox"), fn ->
      full_path
      |> File.read!()
      |> ExLisp.Reader.split_expressions()
      |> Enum.each(fn source ->
        ExLisp.MutableCons.reset()
        source |> ExLisp.LispParser.parse!() |> LispBeam.evaluate_ast()
      end)
    end)

    ExLisp.eval("(print-test-summary \"#{name}\")")
    failed = ExLisp.eval("*test-failed-count*")
    acc + if is_integer(failed), do: failed, else: 0
  end)

if total_failed > 0 do
  IO.puts("\nANSI-TEST finished with #{total_failed} failures.")
  System.halt(1)
else
  IO.puts("\nAll ANSI-TEST suites passed successfully!")
end
