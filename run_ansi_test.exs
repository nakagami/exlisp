# Runner script for ANSI-TEST suites in ExLisp

ansi_test_dir = System.get_env("ANSI_TEST_DIR") || Path.expand("../ansi-test", __DIR__)

if not File.dir?(ansi_test_dir) do
  IO.puts(:stderr, "Error: ansi-test directory not found at #{ansi_test_dir}")
  IO.puts(:stderr, "Please clone it with: git clone https://github.com/sbcl/ansi-test #{ansi_test_dir}")
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
  {"CHAR-COMPARE", "characters/char-compare.lsp"},
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
  Path.join(ansi_test_dir, "auxiliary/cons-aux.lsp"),
  Path.join(ansi_test_dir, "auxiliary/remove-aux.lsp"),
  Path.join(ansi_test_dir, "auxiliary/remove-duplicates-aux.lsp"),
  Path.join(ansi_test_dir, "auxiliary/search-aux.lsp"),
  Path.join(ansi_test_dir, "auxiliary/sort-aux.lsp"),
  Path.join(ansi_test_dir, "auxiliary/subseq-aux.lsp"),
  Path.join(ansi_test_dir, "auxiliary/ansi-aux.lsp"),
  Path.join(ansi_test_dir, "cons-aux.lsp")
]

Enum.each(aux_files, fn f ->
  if File.exists?(f) do
    try do
      ExLisp.load_file(f)
    rescue
      _ -> :ok
    end
  end
end)

ExLisp.load_file(Path.expand("examples/ansi_test_harness.lisp", __DIR__))

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

total_failed =
  Enum.reduce(target_suites, 0, fn {name, rel_path}, acc ->
    full_path = if Path.type(rel_path) == :absolute, do: rel_path, else: Path.join(ansi_test_dir, rel_path)
    IO.puts("Loading #{name} (#{full_path})...")
    ExLisp.eval("(reset-test-stats)")
    ExLisp.load_file(full_path)
    ExLisp.eval("(print-test-summary \"#{name}\")")
    failed = ExLisp.eval("*test-failed-count*")
    acc + (if is_integer(failed), do: failed, else: 0)
  end)

if total_failed > 0 do
  IO.puts("\nANSI-TEST finished with #{total_failed} failures.")
  System.halt(1)
else
  IO.puts("\nAll ANSI-TEST suites passed successfully!")
end
