defmodule ExLisp.Package do
  @moduledoc """
  ANSI Common Lisp Package System for ExLisp.
  Supports:
  - defpackage, in-package, find-package, make-package, delete-package, rename-package
  - export, unexport, import, shadow, shadowing-import, use-package, unuse-package
  - intern, find-symbol, unintern, symbol-package
  - package-name, package-nicknames, package-use-list, package-used-by-list, package-shadowing-symbols, list-all-packages
  - package-qualified symbols (pkg:sym, pkg::sym, :keyword)
  """

  defstruct name: "",
            nicknames: [],
            use_list: [],
            used_by_list: [],
            internal_symbols: MapSet.new(),
            external_symbols: MapSet.new(),
            shadowing_symbols: MapSet.new()

  @table :lisp_packages_table

  def ensure_tables do
    case :ets.whereis(@table) do
      :undefined ->
        try do
          :ets.new(@table, [:set, :public, :named_table])
          init_standard_packages()
        rescue
          _ -> :ok
        end

      _ ->
        :ok
    end
  end

  def current_package do
    ensure_tables()
    Process.get(:exlisp_current_package, "COMMON-LISP-USER")
  end

  def set_current_package(pkg_designator) do
    ensure_tables()
    pkg = find_package!(pkg_designator)
    Process.put(:exlisp_current_package, pkg.name)
    pkg
  end

  # --- Standard Packages Initialization ---

  def init_standard_packages do
    cl_exports = [
      "*", "+", "-", "/", "1+", "1-", "<", "<=", "=", ">", ">=",
      "ABS", "ACOS", "ACOSH", "ADJOIN", "ADJUST-ARRAY", "ADJUSTABLE-ARRAY-P",
      "ALLOCATE-INSTANCE", "ALPHA-CHAR-P", "ALPHANUMERICP", "AND", "APPEND", "APPLY",
      "APPLY-METHOD-COMBINATION", "APROPOS", "APROPOS-LIST", "AREF", "ARITHMETIC-ERROR",
      "ARRAY", "ARRAY-DIMENSION", "ARRAY-DIMENSIONS", "ARRAY-DISPLACEMENT",
      "ARRAY-ELEMENT-TYPE", "ARRAY-HAS-FILL-POINTER-P", "ARRAY-IN-BOUNDS-P",
      "ARRAY-RANK", "ARRAY-ROW-MAJOR-INDEX", "ARRAY-TOTAL-SIZE", "ARRAYP",
      "ASH", "ASIN", "ASINH", "ASSERT", "ASSOC", "ASSOC-IF", "ASSOC-IF-NOT",
      "ATAN", "ATANH", "ATOM", "BIT", "BIT-AND", "BIT-ANDC1", "BIT-ANDC2", "BIT-EQV",
      "BIT-IOR", "BIT-NAND", "BIT-NOR", "BIT-NOT", "BIT-ORC1", "BIT-ORC2",
      "BIT-VECTOR", "BIT-VECTOR-P", "BIT-XOR", "BLOCK", "BOOLE", "BOTH-CASE-P",
      "BOUNDP", "BREAK", "BROADCAST-STREAM", "BUILT-IN-CLASS", "BUTLAST", "BYTE",
      "BYTE-POSITION", "BYTE-SIZE", "CAAAAR", "CAAADR", "CAAAR", "CAADAR", "CAADDR",
      "CAADR", "CAAR", "CADAAR", "CADADR", "CADAR", "CADDAR", "CADDDR", "CADDR",
      "CADR", "CALL-METHOD", "CALL-NEXT-METHOD", "CAR", "CASE", "CATCH", "CCASE",
      "CDAAAR", "CDAADR", "CDAAR", "CDADAR", "CDADDR", "CDADR", "CDAR", "CDDAAR",
      "CDDADR", "CDDAR", "CDDDAR", "CDDDDR", "CDDDR", "CDDR", "CDR", "CEILING",
      "CELL-ERROR", "CELL-ERROR-NAME", "CERROR", "CHANGE-CLASS", "CHAR", "CHAR-CODE",
      "CHAR-DOWNCASE", "CHAR-EQUAL", "CHAR-GREATERP", "CHAR-INT", "CHAR-LESSP",
      "CHAR-NAME", "CHAR-NOT-EQUAL", "CHAR-NOT-GREATERP", "CHAR-NOT-LESSP",
      "CHAR-UPCASE", "CHAR/=", "CHAR<", "CHAR<=", "CHAR=", "CHAR>", "CHAR>=",
      "CHARACTER", "CHARACTERP", "CHECK-TYPE", "CIS", "CLASS", "CLASS-NAME",
      "CLASS-OF", "CLOSE", "CLRHASH", "CODE-CHAR", "COERCE", "COMPILATION-SPEED",
      "COMPILE", "COMPILE-FILE", "COMPILE-FILE-PATHNAME", "COMPILED-FUNCTION",
      "COMPILED-FUNCTION-P", "COMPILER-MACRO", "COMPILER-MACRO-FUNCTION", "COMPLEMENT",
      "COMPLEX", "COMPLEXP", "COMPUTE-APPLICABLE-METHODS", "COMPUTE-RESTARTS",
      "CONCATENATE", "CONCATENATED-STREAM", "COND", "CONDITION", "CONJUGATE",
      "CONS", "CONSP", "CONSTANTLY", "CONSTANTP", "CONTINUE", "CONTROL-ERROR",
      "COPY-ALIST", "COPY-LIST", "COPY-PPRINT-DISPATCH", "COPY-READTABLE",
      "COPY-SEQ", "COPY-STRUCTURE", "COPY-SYMBOL", "COPY-TREE", "COS", "COSH",
      "COUNT", "COUNT-IF", "COUNT-IF-NOT", "CTYPECASE", "DEBUG", "DECF",
      "DECLAIM", "DECLARATION", "DECLARE", "DECODE-FLOAT", "DECODE-UNIVERSAL-TIME",
      "DEFCLASS", "DEFCONSTANT", "DEFGENERIC", "DEFGLOBAL", "DEFINE-COMPILER-MACRO",
      "DEFINE-CONDITION", "DEFINE-METHOD-COMBINATION", "DEFINE-MODIFY-MACRO",
      "DEFINE-SETF-EXPANDER", "DEFINE-SYMBOL-MACRO", "DEFMACRO", "DEFMETHOD",
      "DEFPACKAGE", "DEFPARAMETER", "DEFSETF", "DEFSTRUCT", "DEFTYPE", "DEFUN",
      "DEFVAR", "DELETE", "DELETE-DUPLICATES", "DELETE-FILE", "DELETE-IF",
      "DELETE-IF-NOT", "DELETE-PACKAGE", "DENOMINATOR", "DEPOSIT-FIELD",
      "DESCRIBE", "DESCRIBE-OBJECT", "DESTRUCTURING-BIND", "DIGIT-CHAR",
      "DIGIT-CHAR-P", "DIRECTORY", "DIRECTORY-NAMESTRING", "DISASSEMBLE",
      "DIVISION-BY-ZERO", "DO", "DO*", "DO-ALL-SYMBOLS", "DO-EXTERNAL-SYMBOLS",
      "DO-SYMBOLS", "DOCUMENTATION", "DOLIST", "DOTIMES", "DOUBLE-FLOAT",
      "DPB", "DRY-RUN", "DYNAMIC-EXTENT", "ECASE", "ECHO-STREAM", "ED",
      "EIGHTH", "ELT", "ENCODE-UNIVERSAL-TIME", "ENDP", "ENOUGH-NAMESTRING",
      "ENSURE-DIRECTORIES-EXIST", "ENSURE-GENERIC-FUNCTION", "EQ", "EQL", "EQUAL",
      "EQUALP", "ERROR", "ETYPECASE", "EVAL", "EVAL-WHEN", "EVENP", "EVERY",
      "EXP", "EXPORT", "EXPT", "EXTENDED-CHAR", "FBOUNDP", "FCEILING", "FDEFINITION",
      "FFLOOR", "FIFTH", "FILE-AUTHOR", "FILE-ERROR", "FILE-ERROR-PATHNAME",
      "FILE-LENGTH", "FILE-NAMESTRING", "FILE-POSITION", "FILE-STREAM",
      "FILE-STRING-LENGTH", "FILE-WRITE-DATE", "FILL", "FILL-POINTER",
      "FIND", "FIND-ALL-SYMBOLS", "FIND-CLASS", "FIND-IF", "FIND-IF-NOT",
      "FIND-METHOD", "FIND-PACKAGE", "FIND-RESTART", "FIND-SYMBOL", "FINISH-OUTPUT",
      "FIRST", "FIXNUM", "FLET", "FLOAT", "FLOAT-DIGITS", "FLOAT-PRECISION",
      "FLOAT-RADIX", "FLOAT-SIGN", "FLOATING-POINT-INEXACT", "FLOATING-POINT-INVALID-OPERATION",
      "FLOATING-POINT-OVERFLOW", "FLOATING-POINT-UNDERFLOW", "FLOATP", "FLOOR",
      "FMAKUNBOUND", "FORCE-OUTPUT", "FORMAT", "FORMATTER", "FOURTH", "FRESH-LINE",
      "FROUND", "FTRUNCATE", "FTYPE", "FUNCALL", "FUNCTION", "FUNCTION-KEYWORDS",
      "FUNCTION-LAMBDA-EXPRESSION", "FUNCTIONP", "GCD", "GENERIC-FUNCTION",
      "GENSYM", "GENTEMP", "GET", "GET-DECODED-TIME", "GET-DISPATCH-MACRO-CHARACTER",
      "GET-INTERNAL-REAL-TIME", "GET-INTERNAL-RUN-TIME", "GET-MACRO-CHARACTER",
      "GET-OUTPUT-STREAM-STRING", "GET-PROPERTIES", "GET-SETF-EXPANSION",
      "GET-UNIVERSAL-TIME", "GETF", "GETHASH", "GO", "GRAPHIC-CHAR-P",
      "HANDLER-BIND", "HANDLER-CASE", "HASH-TABLE", "HASH-TABLE-COUNT",
      "HASH-TABLE-P", "HASH-TABLE-REHASH-SIZE", "HASH-TABLE-REHASH-THRESHOLD",
      "HASH-TABLE-SIZE", "HASH-TABLE-TEST", "HOST-NAMESTRING", "IDENTITY",
      "IF", "IGNORABLE", "IGNORE", "IGNORE-ERRORS", "IMAGPART", "IMPORT",
      "IN-PACKAGE", "INCF", "INITIALIZE-INSTANCE", "INLINE", "INPUT-STREAM-P",
      "INSPECT", "INTEGER", "INTEGER-DECODE-FLOAT", "INTEGER-LENGTH", "INTEGERP",
      "INTERACTIVE-STREAM-P", "INTERN", "INTERNAL-TIME-UNITS-PER-SECOND",
      "INTERSECTION", "INVALID-METHOD-ERROR", "INVOKE-DEBUGGER", "INVOKE-RESTART",
      "INVOKE-RESTART-INTERACTIVELY", "ISQRT", "KEYWORD", "KEYWORDP", "LABELS",
      "LAMBDA", "LAMBDA-LIST-KEYWORDS", "LAMBDA-PARAMETERS-LIMIT", "LAST",
      "LCM", "LDB", "LDB-TEST", "LDIFF", "LEAST-NEGATIVE-DOUBLE-FLOAT",
      "LEAST-NEGATIVE-LONG-FLOAT", "LEAST-NEGATIVE-NORMALIZED-DOUBLE-FLOAT",
      "LEAST-NEGATIVE-NORMALIZED-LONG-FLOAT", "LEAST-NEGATIVE-NORMALIZED-SHORT-FLOAT",
      "LEAST-NEGATIVE-NORMALIZED-SINGLE-FLOAT", "LEAST-NEGATIVE-SHORT-FLOAT",
      "LEAST-NEGATIVE-SINGLE-FLOAT", "LEAST-POSITIVE-DOUBLE-FLOAT",
      "LEAST-POSITIVE-LONG-FLOAT", "LEAST-POSITIVE-NORMALIZED-DOUBLE-FLOAT",
      "LEAST-POSITIVE-NORMALIZED-LONG-FLOAT", "LEAST-POSITIVE-NORMALIZED-SHORT-FLOAT",
      "LEAST-POSITIVE-NORMALIZED-SINGLE-FLOAT", "LEAST-POSITIVE-SHORT-FLOAT",
      "LEAST-POSITIVE-SINGLE-FLOAT", "LENGTH", "LET", "LET*", "LISP-IMPLEMENTATION-TYPE",
      "LISP-IMPLEMENTATION-VERSION", "LIST", "LIST*", "LIST-ALL-PACKAGES",
      "LIST-LENGTH", "LISTEN", "LISTP", "LOAD", "LOAD-LOGICAL-PATHNAME-TRANSLATIONS",
      "LOAD-TIME-VALUE", "LOCALLY", "LOG", "LOGAND", "LOGANDC1", "LOGANDC2",
      "LOGBITP", "LOGCOUNT", "LOGEQV", "LOGIOR", "LOGNAND", "LOGNOR",
      "LOGNOT", "LOGORC1", "LOGORC2", "LOGTEST", "LOGXOR", "LONG-FLOAT",
      "LONG-FLOAT-NEGATIVE-EPSILON", "LONG-FLOAT-EPSILON", "LOOP", "LOOP-FINISH",
      "LOWER-CASE-P", "MACHINE-INSTANCE", "MACHINE-TYPE", "MACHINE-VERSION",
      "MACRO-FUNCTION", "MACROEXPAND", "MACROEXPAND-1", "MACROLET", "MAKE-ARRAY",
      "MAKE-BROADCAST-STREAM", "MAKE-CONCATENATED-STREAM", "MAKE-CONDITION",
      "MAKE-DISPATCH-MACRO-CHARACTER", "MAKE-ECHO-STREAM", "MAKE-HASH-TABLE",
      "MAKE-INSTANCE", "MAKE-INSTANCES-OBSOLETE", "MAKE-LIST", "MAKE-LOAD-FORM",
      "MAKE-LOAD-FORM-SAVING-SLOTS", "MAKE-METHOD", "MAKE-PACKAGE", "MAKE-PATHNAME",
      "MAKE-RANDOM-STATE", "MAKE-SEQUENCE", "MAKE-STRING", "MAKE-STRING-INPUT-STREAM",
      "MAKE-STRING-OUTPUT-STREAM", "MAKE-SYMBOL", "MAKE-SYNONYM-STREAM",
      "MAKE-TWO-WAY-STREAM", "MAKUNBOUND", "MAP", "MAP-INTO", "MAPC", "MAPCAN",
      "MAPCAR", "MAPCON", "MAPHASH", "MAPL", "MAPLIST", "MASK-FIELD", "MAX",
      "MEMBER", "MEMBER-IF", "MEMBER-IF-NOT", "MERGE", "MERGE-PATHNAMES",
      "METHOD", "METHOD-COMBINATION", "METHOD-COMBINATION-ERROR", "METHOD-QUALIFIERS",
      "MIN", "MINUSP", "MISMATCH", "MOD", "MUFFLE-WARNING", "MULTIPLE-VALUE-BIND",
      "MULTIPLE-VALUE-CALL", "MULTIPLE-VALUE-LIST", "MULTIPLE-VALUE-PROG1",
      "MULTIPLE-VALUE-SETQ", "MULTIPLE-VALUES-LIMIT", "NAME-CHAR", "NAMESTRING",
      "NBOUNDP", "NCONC", "NEXT-METHOD-P", "NIL", "NINTERSECTION", "NINTH",
      "NO-APPLICABLE-METHOD", "NO-NEXT-METHOD", "NOT", "NOTANY", "NOTEVERY",
      "NOTINLINE", "NRECONC", "NREVERSE", "NSET-DIFFERENCE", "NSET-EXCLUSIVE-OR",
      "NSTRING-CAPITALIZE", "NSTRING-DOWNCASE", "NSTRING-UPCASE", "NSUBLIS",
      "NSUBST", "NSUBST-IF", "NSUBST-IF-NOT", "NSUBSTITUTE", "NSUBSTITUTE-IF",
      "NSUBSTITUTE-IF-NOT", "NTH", "NTH-VALUE", "NTHCDR", "NULL", "NUMBER",
      "NUMBERP", "NUMERATOR", "NUNION", "ODDP", "OPEN", "OPEN-STREAM-P",
      "OPTIMIZE", "OR", "OTHERWISE", "OUTPUT-STREAM-P", "PACKAGE", "PACKAGE-ERROR",
      "PACKAGE-ERROR-PACKAGE", "PACKAGE-NAME", "PACKAGE-NICKNAMES", "PACKAGE-SHADOWING-SYMBOLS",
      "PACKAGE-USE-LIST", "PACKAGE-USED-BY-LIST", "PACKAGEP", "PAIRLIS",
      "PARSE-ERROR", "PARSE-INTEGER", "PARSE-NAMESTRING", "PATHNAME", "PATHNAME-DEVICE",
      "PATHNAME-DIRECTORY", "PATHNAME-HOST", "PATHNAME-MATCH-P", "PATHNAME-NAME",
      "PATHNAME-TYPE", "PATHNAME-VERSION", "PATHNAMEP", "PEEK-CHAR", "PHASE",
      "PI", "PLUSP", "POP", "POSITION", "POSITION-IF", "POSITION-IF-NOT",
      "PPRINT", "PPRINT-DISPATCH", "PPRINT-EXIT-IF-LIST-EXHAUSTED", "PPRINT-FILL",
      "PPRINT-INDENT", "PPRINT-LINEAR", "PPRINT-LOGICAL-BLOCK", "PPRINT-NEWLINE",
      "PPRINT-POP", "PPRINT-TAB", "PPRINT-TABULAR", "PRIN1", "PRIN1-TO-STRING",
      "PRINC", "PRINC-TO-STRING", "PRINT", "PRINT-NOT-READABLE", "PRINT-NOT-READABLE-OBJECT",
      "PRINT-OBJECT", "PRINT-UNREADABLE-OBJECT", "PROBE-FILE", "PROCLAMATION",
      "PROCLAIM", "PROG", "PROG*", "PROG1", "PROG2", "PROGN", "PROGRAM-ERROR",
      "PROGV", "PROVIDE", "PSETF", "PSETQ", "PUSH", "PUSHNEW", "RANDOM",
      "RANDOM-STATE", "RANDOM-STATE-P", "RASSOR", "RASSOC-IF", "RASSOC-IF-NOT",
      "RATIO", "RATIONAL", "RATIONALIZE", "RATIONALP", "READ", "READ-BYTE",
      "READ-CHAR", "READ-CHAR-NO-HANG", "READ-DELIMITED-LIST", "READ-FROM-STRING",
      "READ-LINE", "READ-PRESERVING-WHITESPACE", "READ-SEQUENCE", "READTABLE",
      "READTABLE-CASE", "READTABLEP", "REAL", "REALP", "REALPART", "REDUCE",
      "REINITIALIZE-INSTANCE", "REM", "REMF", "REMHASH", "REMOVE", "REMOVE-DUPLICATES",
      "REMOVE-IF", "REMOVE-IF-NOT", "REMOVE-METHOD", "REMPROP", "RENAME-FILE",
      "RENAME-PACKAGE", "REPLACE", "REQUIRE", "REST", "RESTART", "RESTART-BIND",
      "RESTART-CASE", "RESTART-NAME", "RETURN", "RETURN-FROM", "REVAPPEND",
      "REVERSE", "ROOM", "ROTATEF", "ROUND", "ROW-MAJOR-AREF", "RPLACA", "RPLACD",
      "SAFETY", "SATISFIES", "SBIT", "SCALE-FLOAT", "SCHAR", "SEARCH", "SECOND",
      "SEQUENCE", "SERIOUS-CONDITION", "SET", "SET-DIFFERENCE", "SET-DISPATCH-MACRO-CHARACTER",
      "SET-EXCLUSIVE-OR", "SET-MACRO-CHARACTER", "SET-PPRINT-DISPATCH", "SET-SYNTAX-FROM-CHAR",
      "SETF", "SETQ", "SEVENTH", "SHADOW", "SHADOWING-IMPORT", "SHARED-INITIALIZE",
      "SHIFTF", "SHORT-FLOAT", "SHORT-FLOAT-EPSILON", "SHORT-FLOAT-NEGATIVE-EPSILON",
      "SHORT-SITE-NAME", "SIGNAL", "SIGNED-BYTE", "SIGNUM", "SIMPLE-ARRAY",
      "SIMPLE-BASE-STRING", "SIMPLE-BIT-VECTOR", "SIMPLE-BIT-VECTOR-P", "SIMPLE-CONDITION",
      "SIMPLE-CONDITION-FORMAT-ARGUMENTS", "SIMPLE-CONDITION-FORMAT-CONTROL",
      "SIMPLE-ERROR", "SIMPLE-STRING", "SIMPLE-STRING-P", "SIMPLE-TYPE-ERROR",
      "SIMPLE-VECTOR", "SIMPLE-VECTOR-P", "SIMPLE-WARNING", "SIN", "SINGLE-FLOAT",
      "SINGLE-FLOAT-EPSILON", "SINGLE-FLOAT-NEGATIVE-EPSILON", "SINH", "SIXTH",
      "SLEEP", "SLOT-BOUNDP", "SLOT-EXISTS-P", "SLOT-MAKUNBOUND", "SLOT-MISSING",
      "SLOT-UNBOUND", "SLOT-VALUE", "SOFTWARE-TYPE", "SOFTWARE-VERSION", "SOME",
      "SORT", "SPACE", "SPECIAL", "SPECIAL-OPERATOR-P", "SPEED", "SQRT",
      "STABLE-SORT", "STANDARD", "STANDARD-CHAR", "STANDARD-CHAR-P", "STANDARD-CLASS",
      "STANDARD-GENERIC-FUNCTION", "STANDARD-METHOD", "STANDARD-OBJECT",
      "STEP", "STORAGE-CONDITION", "STORE-VALUE", "STREAM", "STREAM-ELEMENT-TYPE",
      "STREAM-ERROR", "STREAM-ERROR-STREAM", "STREAM-EXTERNAL-FORMAT", "STRING",
      "STRING-CAPITALIZE", "STRING-CHAR", "STRING-CHAR-P", "STRING-DOWNCASE",
      "STRING-EQUAL", "STRING-GREATERP", "STRING-LEFT-TRIM", "STRING-LESSP",
      "STRING-NOT-EQUAL", "STRING-NOT-GREATERP", "STRING-NOT-LESSP", "STRING-RIGHT-TRIM",
      "STRING-STREAM", "STRING-TRIM", "STRING-UPCASE", "STRING/=", "STRING<",
      "STRING<=", "STRING=", "STRING>", "STRING>=", "STRINGP", "STRUCTURE",
      "STRUCTURE-CLASS", "STRUCTURE-OBJECT", "STYLE-WARNING", "SUBLIS", "SUBSEQ",
      "SUBSETP", "SUBST", "SUBST-IF", "SUBST-IF-NOT", "SUBSTITUTE", "SUBSTITUTE-IF",
      "SUBSTITUTE-IF-NOT", "SUBTYPEP", "SVREF", "SXHASH", "SYMBOL", "SYMBOL-FUNCTION",
      "SYMBOL-MACROLET", "SYMBOL-NAME", "SYMBOL-PACKAGE", "SYMBOL-PLIST",
      "SYMBOL-VALUE", "SYMBOLP", "SYNONYM-STREAM", "SYNONYM-STREAM-SYMBOL", "T",
      "TAGBODY", "TAILP", "TAN", "TANH", "TENTH", "TERPRI", "THE", "THIRD",
      "TIME", "TRACE", "TRANSLATE-LOGICAL-PATHNAME", "TRANSLATE-PATHNAME",
      "TREE-EQUAL", "TRUENAME", "TRUNCATE", "TWO-WAY-STREAM", "TWO-WAY-STREAM-INPUT-STREAM",
      "TWO-WAY-STREAM-OUTPUT-STREAM", "TYPE", "TYPE-ERROR", "TYPE-ERROR-DATUM",
      "TYPE-ERROR-EXPECTED-TYPE", "TYPE-OF", "TYPECASE", "TYPEP", "UNBOUND-SLOT",
      "UNBOUND-SLOT-INSTANCE", "UNBOUND-VARIABLE", "UNDEFINED-FUNCTION", "UNEXPORT",
      "UNINTERN", "UNION", "UNLESS", "UNREAD-CHAR", "UNSIGNED-BYTE", "UNTRACE",
      "UNUSE-PACKAGE", "UNWIND-PROTECT", "UPDATE-INSTANCE-FOR-DIFFERENT-CLASS",
      "UPDATE-INSTANCE-FOR-REDEFINED-CLASS", "UPGRADED-ARRAY-ELEMENT-TYPE",
      "UPGRADED-COMPLEX-PART-TYPE", "UPPER-CASE-P", "USE-PACKAGE", "USE-VALUE",
      "USER-HOMEDIR-PATHNAME", "VALUES", "VALUES-LIST", "VARIABLE", "VECTOR",
      "VECTOR-POP", "VECTOR-PUSH", "VECTOR-PUSH-EXTEND", "VECTORP", "WARN",
      "WARNING", "WHEN", "WILD-PATHNAME-P", "WITH-ACCESSORS", "WITH-COMPILATION-UNIT",
      "WITH-CONDITION-RESTARTS", "WITH-HASH-TABLE-ITERATOR", "WITH-INPUT-FROM-STRING",
      "WITH-OPEN-FILE", "WITH-OPEN-STREAM", "WITH-OUTPUT-TO-STRING", "WITH-PACKAGE-ITERATOR",
      "WITH-SIMPLE-RESTART", "WITH-SLOTS", "WITH-STANDARD-IO-SYNTAX", "WRITE",
      "WRITE-BYTE", "WRITE-CHAR", "WRITE-LINE", "WRITE-SEQUENCE", "WRITE-STRING",
      "WRITE-TO-STRING", "Y-OR-N-P", "YES-OR-NO-P", "ZEROP"
    ]

    cl_pkg = %ExLisp.Package{
      name: "COMMON-LISP",
      nicknames: ["CL"],
      use_list: [],
      used_by_list: ["COMMON-LISP-USER"],
      external_symbols: MapSet.new(cl_exports),
      internal_symbols: MapSet.new()
    }

    cl_user_pkg = %ExLisp.Package{
      name: "COMMON-LISP-USER",
      nicknames: ["CL-USER"],
      use_list: ["COMMON-LISP"],
      used_by_list: [],
      external_symbols: MapSet.new(),
      internal_symbols: MapSet.new()
    }

    kw_pkg = %ExLisp.Package{
      name: "KEYWORD",
      nicknames: [],
      use_list: [],
      used_by_list: [],
      external_symbols: MapSet.new(),
      internal_symbols: MapSet.new()
    }

    save_package(cl_pkg)
    save_package(cl_user_pkg)
    save_package(kw_pkg)
  end

  defp save_package(%ExLisp.Package{name: name, nicknames: nicks} = pkg) do
    :ets.insert(@table, {name, pkg})
    Enum.each(nicks, fn n -> :ets.insert(@table, {n, pkg}) end)
  end

  # --- Package Lookup ---

  def find_package(pkg_designator) do
    ensure_tables()

    case pkg_designator do
      %ExLisp.Package{} = p ->
        p

      name when is_atom(name) or is_binary(name) ->
        str = name |> to_string() |> clean_uninterned() |> String.trim_leading(":") |> String.upcase()
        str_hyphen = String.replace(str, "_", "-")
        str_under = String.replace(str, "-", "_")

        case :ets.lookup(@table, str) do
          [{_key, %ExLisp.Package{} = pkg}] ->
            pkg

          _ ->
            case :ets.lookup(@table, str_hyphen) do
              [{_key, %ExLisp.Package{} = pkg}] ->
                pkg

              _ ->
                case :ets.lookup(@table, str_under) do
                  [{_key, %ExLisp.Package{} = pkg}] -> pkg
                  _ -> nil
                end
            end
        end

      _ ->
        nil
    end
  end

  def find_package!(pkg_designator) do
    case find_package(pkg_designator) do
      nil ->
        str = to_string(pkg_designator)
        raise RuntimeError, "Package #{str} not found"

      pkg ->
        pkg
    end
  end

  def packagep(pkg) do
    case pkg do
      %ExLisp.Package{} -> :t
      _ -> nil
    end
  end

  def package_name(pkg_designator) do
    case find_package(pkg_designator) do
      %ExLisp.Package{name: n} -> n
      _ -> nil
    end
  end

  def package_nicknames(pkg_designator) do
    case find_package(pkg_designator) do
      %ExLisp.Package{nicknames: n} -> n
      _ -> []
    end
  end

  def package_use_list(pkg_designator) do
    case find_package(pkg_designator) do
      %ExLisp.Package{use_list: u} ->
        Enum.map(u, &find_package/1) |> Enum.reject(&is_nil/1)

      _ ->
        []
    end
  end

  def package_used_by_list(pkg_designator) do
    case find_package(pkg_designator) do
      %ExLisp.Package{used_by_list: u} ->
        Enum.map(u, &find_package/1) |> Enum.reject(&is_nil/1)

      _ ->
        []
    end
  end

  def package_shadowing_symbols(pkg_designator) do
    case find_package(pkg_designator) do
      %ExLisp.Package{shadowing_symbols: s} ->
        Enum.map(s, fn name ->
          String.downcase(name) |> String.replace("-", "_") |> String.to_atom()
        end)

      _ ->
        []
    end
  end

  def list_all_packages do
    ensure_tables()

    :ets.tab2list(@table)
    |> Enum.map(fn {_k, pkg} -> pkg end)
    |> Enum.uniq_by(& &1.name)
  end

  # --- Package Operations ---

  def make_package(name_designator, options \\ []) do
    ensure_tables()
    name = name_designator |> to_string() |> clean_uninterned() |> String.trim_leading(":") |> String.upcase() |> String.replace("_", "-")

    if find_package(name) do
      raise RuntimeError, "Package #{name} already exists"
    end

    nicks =
      case Keyword.get(options, :nicknames, []) do
        list when is_list(list) -> Enum.map(list, &(&1 |> to_string() |> clean_uninterned() |> String.trim_leading(":") |> String.upcase() |> String.replace("_", "-")))
        single -> [single |> to_string() |> clean_uninterned() |> String.trim_leading(":") |> String.upcase() |> String.replace("_", "-")]
      end

    uses =
      case Keyword.get(options, :use, ["COMMON-LISP"]) do
        list when is_list(list) ->
          Enum.map(list, fn u ->
            pkg = find_package!(u)
            pkg.name
          end)

        single ->
          pkg = find_package!(single)
          [pkg.name]
      end

    pkg = %ExLisp.Package{
      name: name,
      nicknames: nicks,
      use_list: uses,
      used_by_list: [],
      internal_symbols: MapSet.new(),
      external_symbols: MapSet.new(),
      shadowing_symbols: MapSet.new()
    }

    save_package(pkg)

    # Update used_by_list on used packages
    Enum.each(uses, fn u_name ->
      if u_pkg = find_package(u_name) do
        save_package(%{u_pkg | used_by_list: Enum.uniq([name | u_pkg.used_by_list])})
      end
    end)

    pkg
  end

  def delete_package(pkg_designator) do
    ensure_tables()

    case find_package(pkg_designator) do
      nil ->
        nil

      %ExLisp.Package{name: name, nicknames: nicks, use_list: uses} ->
        :ets.delete(@table, name)
        Enum.each(nicks, fn n -> :ets.delete(@table, n) end)

        Enum.each(uses, fn u_name ->
          if u_pkg = find_package(u_name) do
            save_package(%{u_pkg | used_by_list: List.delete(u_pkg.used_by_list, name)})
          end
        end)

        :t
    end
  end

  def rename_package(pkg_designator, new_name_desig, new_nicknames_desig \\ []) do
    ensure_tables()
    old_pkg = find_package!(pkg_designator)

    new_name = new_name_desig |> to_string() |> String.trim_leading(":") |> String.upcase()
    new_nicks =
      (if is_list(new_nicknames_desig), do: new_nicknames_desig, else: [new_nicknames_desig])
      |> Enum.map(&(&1 |> to_string() |> String.trim_leading(":") |> String.upcase()))

    # Remove old entries
    :ets.delete(@table, old_pkg.name)
    Enum.each(old_pkg.nicknames, fn n -> :ets.delete(@table, n) end)

    updated_pkg = %{old_pkg | name: new_name, nicknames: new_nicks}
    save_package(updated_pkg)
    updated_pkg
  end

  # --- Defpackage Macro Backend ---

  def defpackage(name_desig, options \\ []) do
    ensure_tables()
    name = name_desig |> to_string() |> clean_uninterned() |> String.trim_leading(":") |> String.upcase() |> String.replace("_", "-")

    pkg = find_package(name) || make_package(name, use: [])

    # Process options
    pkg =
      Enum.reduce(options, pkg, fn opt, acc_pkg ->
        case opt do
          [opt_key | opt_args] ->
            apply_defpackage_option(acc_pkg, opt_key, opt_args)

          {opt_key, opt_args} ->
            apply_defpackage_option(acc_pkg, opt_key, if(is_list(opt_args), do: opt_args, else: [opt_args]))

          _ ->
            acc_pkg
        end
      end)

    save_package(pkg)
    pkg
  end

  defp apply_defpackage_option(pkg, key, args) do
    norm_key = key |> to_string() |> clean_uninterned() |> String.trim_leading(":") |> String.upcase() |> String.replace("_", "-")

    case norm_key do
      "NICKNAMES" ->
        nicks = Enum.map(args, &(&1 |> to_string() |> clean_uninterned() |> String.trim_leading(":") |> String.upcase() |> String.replace("_", "-")))
        %{pkg | nicknames: Enum.uniq(pkg.nicknames ++ nicks)}

      "USE" ->
        uses = Enum.map(args, fn u ->
          u_pkg = find_package!(u)
          u_pkg.name
        end)
        # Update used_by
        Enum.each(uses, fn u_name ->
          if u_pkg = find_package(u_name) do
            save_package(%{u_pkg | used_by_list: Enum.uniq([pkg.name | u_pkg.used_by_list])})
          end
        end)
        %{pkg | use_list: Enum.uniq(pkg.use_list ++ uses)}

      "EXPORT" ->
        syms = Enum.map(args, &symbol_to_str/1)
        %{pkg | external_symbols: MapSet.union(pkg.external_symbols, MapSet.new(syms))}

      "IMPORT_FROM" ->
        case args do
          [_from_pkg_desig | sym_names] ->
            syms = Enum.map(sym_names, &symbol_to_str/1)
            %{pkg | internal_symbols: MapSet.union(pkg.internal_symbols, MapSet.new(syms))}
          _ ->
            pkg
        end

      "SHADOW" ->
        syms = Enum.map(args, &symbol_to_str/1)
        %{pkg |
          shadowing_symbols: MapSet.union(pkg.shadowing_symbols, MapSet.new(syms)),
          internal_symbols: MapSet.union(pkg.internal_symbols, MapSet.new(syms))
        }

      "SHADOWING_IMPORT_FROM" ->
        case args do
          [_from_pkg_desig | sym_names] ->
            syms = Enum.map(sym_names, &symbol_to_str/1)
            %{pkg |
              shadowing_symbols: MapSet.union(pkg.shadowing_symbols, MapSet.new(syms)),
              internal_symbols: MapSet.union(pkg.internal_symbols, MapSet.new(syms))
            }
          _ ->
            pkg
        end

      _ ->
        pkg
    end
  end

  # --- Export / Import / Shadow / Use ---

  def export(symbols, pkg_desig \\ nil) do
    pkg = if is_nil(pkg_desig), do: find_package!(current_package()), else: find_package!(pkg_desig)
    sym_list = if is_list(symbols), do: symbols, else: [symbols]
    sym_strs = Enum.map(sym_list, &symbol_to_str/1)

    updated = %{pkg | external_symbols: MapSet.union(pkg.external_symbols, MapSet.new(sym_strs))}
    save_package(updated)
    :t
  end

  def unexport(symbols, pkg_desig \\ nil) do
    pkg = if is_nil(pkg_desig), do: find_package!(current_package()), else: find_package!(pkg_desig)
    sym_list = if is_list(symbols), do: symbols, else: [symbols]
    sym_strs = Enum.map(sym_list, &symbol_to_str/1)

    updated = %{pkg | external_symbols: MapSet.difference(pkg.external_symbols, MapSet.new(sym_strs))}
    save_package(updated)
    :t
  end

  def import(symbols, pkg_desig \\ nil) do
    pkg = if is_nil(pkg_desig), do: find_package!(current_package()), else: find_package!(pkg_desig)
    sym_list = if is_list(symbols), do: symbols, else: [symbols]
    sym_strs = Enum.map(sym_list, &symbol_to_str/1)

    updated = %{pkg | internal_symbols: MapSet.union(pkg.internal_symbols, MapSet.new(sym_strs))}
    save_package(updated)
    :t
  end

  def shadow(symbols, pkg_desig \\ nil) do
    pkg = if is_nil(pkg_desig), do: find_package!(current_package()), else: find_package!(pkg_desig)
    sym_list = if is_list(symbols), do: symbols, else: [symbols]
    sym_strs = Enum.map(sym_list, &symbol_to_str/1)

    updated = %{pkg |
      shadowing_symbols: MapSet.union(pkg.shadowing_symbols, MapSet.new(sym_strs)),
      internal_symbols: MapSet.union(pkg.internal_symbols, MapSet.new(sym_strs))
    }
    save_package(updated)
    :t
  end

  def shadowing_import(symbols, pkg_desig \\ nil) do
    shadow(symbols, pkg_desig)
  end

  def use_package(packages_to_use, pkg_desig \\ nil) do
    pkg = if is_nil(pkg_desig), do: find_package!(current_package()), else: find_package!(pkg_desig)
    pkgs = if is_list(packages_to_use), do: packages_to_use, else: [packages_to_use]
    use_names = Enum.map(pkgs, fn p -> find_package!(p).name end)

    Enum.each(use_names, fn u_name ->
      if u_pkg = find_package(u_name) do
        save_package(%{u_pkg | used_by_list: Enum.uniq([pkg.name | u_pkg.used_by_list])})
      end
    end)

    updated = %{pkg | use_list: Enum.uniq(pkg.use_list ++ use_names)}
    save_package(updated)
    :t
  end

  def unuse_package(packages_to_unuse, pkg_desig \\ nil) do
    pkg = if is_nil(pkg_desig), do: find_package!(current_package()), else: find_package!(pkg_desig)
    pkgs = if is_list(packages_to_unuse), do: packages_to_unuse, else: [packages_to_unuse]
    unuse_names = Enum.map(pkgs, fn p -> find_package!(p).name end)

    Enum.each(unuse_names, fn u_name ->
      if u_pkg = find_package(u_name) do
        save_package(%{u_pkg | used_by_list: List.delete(u_pkg.used_by_list, pkg.name)})
      end
    end)

    updated = %{pkg | use_list: pkg.use_list -- unuse_names}
    save_package(updated)
    :t
  end

  # --- Intern & Find-Symbol ---

  @doc """
  Finds or creates a symbol in the specified package.
  Returns `[:_values_, [symbol, status]]` where status is `:internal`, `:external`, `:inherited`, or `nil`.
  """
  def intern(name_desig, pkg_desig \\ nil) do
    pkg = if is_nil(pkg_desig), do: find_package!(current_package()), else: find_package!(pkg_desig)
    name = symbol_to_str(name_desig)

    case find_symbol_in_pkg(name, pkg) do
      {:found, sym, status} ->
        [:_values_, [sym, status]]

      :not_found ->
        # Add to internal symbols of pkg
        updated = %{pkg | internal_symbols: MapSet.put(pkg.internal_symbols, name)}
        save_package(updated)
        sym = str_to_symbol(name)
        [:_values_, [sym, nil]]
    end
  end

  @doc """
  Finds a symbol in package without creating it.
  Returns `[:_values_, [symbol, status]]` or `[:_values_, [nil, nil]]`.
  """
  def find_symbol(name_desig, pkg_desig \\ nil) do
    pkg = if is_nil(pkg_desig), do: find_package!(current_package()), else: find_package!(pkg_desig)
    name = symbol_to_str(name_desig)

    case find_symbol_in_pkg(name, pkg) do
      {:found, sym, status} ->
        [:_values_, [sym, status]]

      :not_found ->
        [:_values_, [nil, nil]]
    end
  end

  def unintern(symbol_desig, pkg_desig \\ nil) do
    pkg = if is_nil(pkg_desig), do: find_package!(current_package()), else: find_package!(pkg_desig)
    name = symbol_to_str(symbol_desig)

    if MapSet.member?(pkg.internal_symbols, name) or MapSet.member?(pkg.external_symbols, name) do
      updated = %{
        pkg
        | internal_symbols: MapSet.delete(pkg.internal_symbols, name),
          external_symbols: MapSet.delete(pkg.external_symbols, name),
          shadowing_symbols: MapSet.delete(pkg.shadowing_symbols, name)
      }

      save_package(updated)
      :t
    else
      nil
    end
  end

  def symbol_package(sym_desig) do
    ensure_tables()

    case sym_desig do
      nil -> nil
      :t -> find_package("COMMON-LISP")
      %ExLisp.Symbol{name: _} -> nil
      sym when is_atom(sym) ->
        str = Atom.to_string(sym)
        cond do
          ExLisp.Env.keyword?(sym) or String.starts_with?(str, ":") ->
            find_package("KEYWORD")

          true ->
            # Search packages
            name = symbol_to_str(sym)
            curr = find_package(current_package())
            if curr && (MapSet.member?(curr.internal_symbols, name) or MapSet.member?(curr.external_symbols, name)) do
              curr
            else
              # Search CL package
              cl = find_package("COMMON-LISP")
              if cl && MapSet.member?(cl.external_symbols, name) do
                cl
              else
                curr || cl
              end
            end
        end

      _ -> nil
    end
  end

  # --- Package Qualified Symbol Resolution ---

  @doc """
  Resolves a package-qualified symbol like `MY-PKG:FOO` or `MY-PKG::BAR`.
  strict_external: true requires exported symbol if single colon.
  """
  def resolve_qualified_symbol(pkg_name_str, sym_name_str, internal_allowed? \\ false) do
    pkg = find_package!(pkg_name_str)
    sym_up = String.upcase(sym_name_str)

    if internal_allowed? do
      str_to_symbol(sym_up)
    else
      if MapSet.member?(pkg.external_symbols, sym_up) do
        str_to_symbol(sym_up)
      else
        raise RuntimeError, "Symbol #{sym_up} is not external in package #{pkg.name}"
      end
    end
  end

  # --- Helper functions ---

  defp find_symbol_in_pkg(name_up, %ExLisp.Package{} = pkg) do
    cond do
      MapSet.member?(pkg.external_symbols, name_up) ->
        {:found, str_to_symbol(name_up), :external}

      MapSet.member?(pkg.internal_symbols, name_up) ->
        {:found, str_to_symbol(name_up), :internal}

      true ->
        # Search inherited symbols from use_list
        Enum.find_value(pkg.use_list, :not_found, fn u_name ->
          if u_pkg = find_package(u_name) do
            if MapSet.member?(u_pkg.external_symbols, name_up) do
              {:found, str_to_symbol(name_up), :inherited}
            end
          end
        end)
    end
  end

  defp clean_uninterned(str) do
    case Regex.run(~r/^#:UNINTERNED_\d+_(.*)$/i, str) do
      [_, orig] -> orig
      _ -> str
    end
  end

  defp symbol_to_str(sym) do
    case sym do
      s when is_binary(s) ->
        clean_uninterned(s) |> String.trim_leading(":") |> String.upcase() |> String.replace("_", "-")

      a when is_atom(a) ->
        a |> Atom.to_string() |> clean_uninterned() |> String.trim_leading(":") |> String.upcase() |> String.replace("_", "-")

      %ExLisp.Symbol{name: n} ->
        n |> clean_uninterned() |> String.trim_leading(":") |> String.upcase() |> String.replace("_", "-")

      _ ->
        to_string(sym) |> clean_uninterned() |> String.trim_leading(":") |> String.upcase() |> String.replace("_", "-")
    end
  end

  defp str_to_symbol(str) do
    str
    |> String.downcase()
    |> String.replace("-", "_")
    |> String.to_atom()
  end
end
