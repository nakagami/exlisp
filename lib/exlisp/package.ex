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

  defstruct id: nil,
            name: "",
            nicknames: [],
            use_list: [],
            used_by_list: [],
            internal_symbols: MapSet.new(),
            external_symbols: MapSet.new(),
            shadowing_symbols: MapSet.new(),
            symbol_packages: %{},
            symbol_values: %{}

  @table :lisp_packages_table
  @revision_key :exlisp_package_revision
  @home_count_cache_key :exlisp_symbol_home_count_cache
  @missing_cl_exports [
    "**",
    "***",
    "*BREAK-ON-SIGNALS*",
    "*COMPILE-FILE-PATHNAME*",
    "*COMPILE-FILE-TRUENAME*",
    "*COMPILE-PRINT*",
    "*COMPILE-VERBOSE*",
    "*DEBUG-IO*",
    "*DEBUGGER-HOOK*",
    "*DEFAULT-PATHNAME-DEFAULTS*",
    "*ERROR-OUTPUT*",
    "*FEATURES*",
    "*GENSYM-COUNTER*",
    "*LOAD-PATHNAME*",
    "*LOAD-PRINT*",
    "*LOAD-TRUENAME*",
    "*LOAD-VERBOSE*",
    "*MACROEXPAND-HOOK*",
    "*MODULES*",
    "*PACKAGE*",
    "*PRINT-ARRAY*",
    "*PRINT-BASE*",
    "*PRINT-CASE*",
    "*PRINT-CIRCLE*",
    "*PRINT-ESCAPE*",
    "*PRINT-GENSYM*",
    "*PRINT-LENGTH*",
    "*PRINT-LEVEL*",
    "*PRINT-LINES*",
    "*PRINT-MISER-WIDTH*",
    "*PRINT-PPRINT-DISPATCH*",
    "*PRINT-PRETTY*",
    "*PRINT-RADIX*",
    "*PRINT-READABLY*",
    "*PRINT-RIGHT-MARGIN*",
    "*QUERY-IO*",
    "*RANDOM-STATE*",
    "*READ-BASE*",
    "*READ-DEFAULT-FLOAT-FORMAT*",
    "*READ-EVAL*",
    "*READ-SUPPRESS*",
    "*READTABLE*",
    "*STANDARD-INPUT*",
    "*STANDARD-OUTPUT*",
    "*TERMINAL-IO*",
    "*TRACE-OUTPUT*",
    "++",
    "+++",
    "//",
    "///",
    "/=",
    "ABORT",
    "ACONS",
    "ADD-METHOD",
    "ARITHMETIC-ERROR-OPERANDS",
    "ARITHMETIC-ERROR-OPERATION",
    "ARRAY-DIMENSION-LIMIT",
    "ARRAY-RANK-LIMIT",
    "ARRAY-TOTAL-SIZE-LIMIT",
    "BASE-STRING",
    "BIGNUM",
    "BOOLEAN",
    "BROADCAST-STREAM-STREAMS",
    "CALL-ARGUMENTS-LIMIT",
    "CHAR-CODE-LIMIT",
    "CLEAR-INPUT",
    "CLEAR-OUTPUT",
    "CONCATENATED-STREAM-STREAMS",
    "DOUBLE-FLOAT-EPSILON",
    "DOUBLE-FLOAT-NEGATIVE-EPSILON",
    "DRIBBLE",
    "ECHO-STREAM-INPUT-STREAM",
    "ECHO-STREAM-OUTPUT-STREAM",
    "END-OF-FILE",
    "LOGICAL-PATHNAME",
    "LOGICAL-PATHNAME-TRANSLATIONS",
    "LONG-SITE-NAME",
    "MOST-NEGATIVE-DOUBLE-FLOAT",
    "MOST-NEGATIVE-FIXNUM",
    "MOST-NEGATIVE-LONG-FLOAT",
    "MOST-NEGATIVE-SHORT-FLOAT",
    "MOST-NEGATIVE-SINGLE-FLOAT",
    "MOST-POSITIVE-DOUBLE-FLOAT",
    "MOST-POSITIVE-FIXNUM",
    "MOST-POSITIVE-LONG-FLOAT",
    "MOST-POSITIVE-SHORT-FLOAT",
    "MOST-POSITIVE-SINGLE-FLOAT",
    "NBUTLAST",
    "NIL",
    "QUOTE",
    "RASSOC",
    "READER-ERROR",
    "STREAMP",
    "THROW"
  ]
  @nonstandard_cl_exports [
    "APPLY-METHOD-COMBINATION",
    "DEFGLOBAL",
    "DRY-RUN",
    "NBOUNDP",
    "PROCLAMATION",
    "RASSOR",
    "STRING-CHAR",
    "STRING-CHAR-P"
  ]

  def ensure_tables do
    if Process.get(:exlisp_package_tables_ready, false) do
      :ok
    else
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

      Process.put(:exlisp_package_tables_ready, true)
      :ok
    end
  end

  def current_package do
    special_key = {:"$special$", :"*package*"}
    special = :erlang.get(special_key)

    cond do
      special != :undefined ->
        package_name(special)

      true ->
        case Process.get(:exlisp_current_package, :undefined) do
          :undefined ->
            ensure_tables()

            try do
              package = ExLisp.Env.get_var(:"*package*")

              case find_package(package) do
                %__MODULE__{name: name} ->
                  Process.put(:exlisp_current_package, name)
                  name

                nil ->
                  "COMMON-LISP-USER"
              end
            rescue
              _ -> "COMMON-LISP-USER"
            end

          cached ->
            cached
        end
    end
  end

  def set_current_package(pkg_designator) do
    ensure_tables()

    pkg =
      case find_package(pkg_designator) do
        nil ->
          ExLisp.Condition.error(:package_error, package: pkg_designator)
          nil

        found ->
          found
      end

    special_key = {:"$special$", ExLisp.Env.normalize_name(:"*package*")}

    if :erlang.get(special_key) != :undefined do
      :erlang.put(special_key, pkg)
      Process.put(:exlisp_current_package, pkg.name)
    else
      Process.put(:exlisp_current_package, pkg.name)
      ExLisp.Env.put_var(:"*package*", pkg)
    end

    pkg
  end

  # --- Standard Packages Initialization ---

  def init_standard_packages do
    cl_exports = [
      "*",
      "+",
      "-",
      "/",
      "1+",
      "1-",
      "<",
      "<=",
      "=",
      ">",
      ">=",
      "ABS",
      "ACOS",
      "ACOSH",
      "ADJOIN",
      "&ALLOW-OTHER-KEYS",
      "&AUX",
      "&BODY",
      "&ENVIRONMENT",
      "&KEY",
      "&OPTIONAL",
      "&REST",
      "&WHOLE",
      "ADJUST-ARRAY",
      "ADJUSTABLE-ARRAY-P",
      "ALLOCATE-INSTANCE",
      "ALPHA-CHAR-P",
      "ALPHANUMERICP",
      "AND",
      "APPEND",
      "APPLY",
      "APPLY-METHOD-COMBINATION",
      "APROPOS",
      "APROPOS-LIST",
      "AREF",
      "ARITHMETIC-ERROR",
      "ARRAY",
      "ARRAY-DIMENSION",
      "ARRAY-DIMENSIONS",
      "ARRAY-DISPLACEMENT",
      "ARRAY-ELEMENT-TYPE",
      "ARRAY-HAS-FILL-POINTER-P",
      "ARRAY-IN-BOUNDS-P",
      "ARRAY-RANK",
      "ARRAY-ROW-MAJOR-INDEX",
      "ARRAY-TOTAL-SIZE",
      "ARRAYP",
      "ASH",
      "ASIN",
      "ASINH",
      "ASSERT",
      "ASSOC",
      "ASSOC-IF",
      "ASSOC-IF-NOT",
      "ATAN",
      "ATANH",
      "ATOM",
      "BASE-CHAR",
      "BIT",
      "BIT-AND",
      "BIT-ANDC1",
      "BIT-ANDC2",
      "BIT-EQV",
      "BIT-IOR",
      "BIT-NAND",
      "BIT-NOR",
      "BIT-NOT",
      "BIT-ORC1",
      "BIT-ORC2",
      "BIT-VECTOR",
      "BIT-VECTOR-P",
      "BIT-XOR",
      "BLOCK",
      "BOOLE",
      "BOOLE-1",
      "BOOLE-2",
      "BOOLE-AND",
      "BOOLE-ANDC1",
      "BOOLE-ANDC2",
      "BOOLE-C1",
      "BOOLE-C2",
      "BOOLE-CLR",
      "BOOLE-EQV",
      "BOOLE-IOR",
      "BOOLE-NAND",
      "BOOLE-NOR",
      "BOOLE-ORC1",
      "BOOLE-ORC2",
      "BOOLE-SET",
      "BOOLE-XOR",
      "BOTH-CASE-P",
      "BOUNDP",
      "BREAK",
      "BROADCAST-STREAM",
      "BUILT-IN-CLASS",
      "BUTLAST",
      "BYTE",
      "BYTE-POSITION",
      "BYTE-SIZE",
      "CAAAAR",
      "CAAADR",
      "CAAAR",
      "CAADAR",
      "CAADDR",
      "CAADR",
      "CAAR",
      "CADAAR",
      "CADADR",
      "CADAR",
      "CADDAR",
      "CADDDR",
      "CADDR",
      "CADR",
      "CALL-METHOD",
      "CALL-NEXT-METHOD",
      "CAR",
      "CASE",
      "CATCH",
      "CCASE",
      "CDAAAR",
      "CDAADR",
      "CDAAR",
      "CDADAR",
      "CDADDR",
      "CDADR",
      "CDAR",
      "CDDAAR",
      "CDDADR",
      "CDDAR",
      "CDDDAR",
      "CDDDDR",
      "CDDDR",
      "CDDR",
      "CDR",
      "CEILING",
      "CELL-ERROR",
      "CELL-ERROR-NAME",
      "CERROR",
      "CHANGE-CLASS",
      "CHAR",
      "CHAR-CODE",
      "CHAR-DOWNCASE",
      "CHAR-EQUAL",
      "CHAR-GREATERP",
      "CHAR-INT",
      "CHAR-LESSP",
      "CHAR-NAME",
      "CHAR-NOT-EQUAL",
      "CHAR-NOT-GREATERP",
      "CHAR-NOT-LESSP",
      "CHAR-UPCASE",
      "CHAR/=",
      "CHAR<",
      "CHAR<=",
      "CHAR=",
      "CHAR>",
      "CHAR>=",
      "CHARACTER",
      "CHARACTERP",
      "CHECK-TYPE",
      "CIS",
      "CLASS",
      "CLASS-NAME",
      "CLASS-OF",
      "CLOSE",
      "CLRHASH",
      "CODE-CHAR",
      "COERCE",
      "COMPILATION-SPEED",
      "COMPILE",
      "COMPILE-FILE",
      "COMPILE-FILE-PATHNAME",
      "COMPILED-FUNCTION",
      "COMPILED-FUNCTION-P",
      "COMPILER-MACRO",
      "COMPILER-MACRO-FUNCTION",
      "COMPLEMENT",
      "COMPLEX",
      "COMPLEXP",
      "COMPUTE-APPLICABLE-METHODS",
      "COMPUTE-RESTARTS",
      "CONCATENATE",
      "CONCATENATED-STREAM",
      "COND",
      "CONDITION",
      "CONJUGATE",
      "CONS",
      "CONSP",
      "CONSTANTLY",
      "CONSTANTP",
      "CONTINUE",
      "CONTROL-ERROR",
      "COPY-ALIST",
      "COPY-LIST",
      "COPY-PPRINT-DISPATCH",
      "COPY-READTABLE",
      "COPY-SEQ",
      "COPY-STRUCTURE",
      "COPY-SYMBOL",
      "COPY-TREE",
      "COS",
      "COSH",
      "COUNT",
      "COUNT-IF",
      "COUNT-IF-NOT",
      "CTYPECASE",
      "DEBUG",
      "DECF",
      "DECLAIM",
      "DECLARATION",
      "DECLARE",
      "DECODE-FLOAT",
      "DECODE-UNIVERSAL-TIME",
      "DEFCLASS",
      "DEFCONSTANT",
      "DEFGENERIC",
      "DEFGLOBAL",
      "DEFINE-COMPILER-MACRO",
      "DEFINE-CONDITION",
      "DEFINE-METHOD-COMBINATION",
      "DEFINE-MODIFY-MACRO",
      "DEFINE-SETF-EXPANDER",
      "DEFINE-SYMBOL-MACRO",
      "DEFMACRO",
      "DEFMETHOD",
      "DEFPACKAGE",
      "DEFPARAMETER",
      "DEFSETF",
      "DEFSTRUCT",
      "DEFTYPE",
      "DEFUN",
      "DEFVAR",
      "DELETE",
      "DELETE-DUPLICATES",
      "DELETE-FILE",
      "DELETE-IF",
      "DELETE-IF-NOT",
      "DELETE-PACKAGE",
      "DENOMINATOR",
      "DEPOSIT-FIELD",
      "DESCRIBE",
      "DESCRIBE-OBJECT",
      "DESTRUCTURING-BIND",
      "DIGIT-CHAR",
      "DIGIT-CHAR-P",
      "DIRECTORY",
      "DIRECTORY-NAMESTRING",
      "DISASSEMBLE",
      "DIVISION-BY-ZERO",
      "DO",
      "DO*",
      "DO-ALL-SYMBOLS",
      "DO-EXTERNAL-SYMBOLS",
      "DO-SYMBOLS",
      "DOCUMENTATION",
      "DOLIST",
      "DOTIMES",
      "DOUBLE-FLOAT",
      "DPB",
      "DRY-RUN",
      "DYNAMIC-EXTENT",
      "ECASE",
      "ECHO-STREAM",
      "ED",
      "EIGHTH",
      "ELT",
      "ENCODE-UNIVERSAL-TIME",
      "ENDP",
      "ENOUGH-NAMESTRING",
      "ENSURE-DIRECTORIES-EXIST",
      "ENSURE-GENERIC-FUNCTION",
      "EQ",
      "EQL",
      "EQUAL",
      "EQUALP",
      "ERROR",
      "ETYPECASE",
      "EVAL",
      "EVAL-WHEN",
      "EVENP",
      "EVERY",
      "EXP",
      "EXPORT",
      "EXPT",
      "EXTENDED-CHAR",
      "FBOUNDP",
      "FCEILING",
      "FDEFINITION",
      "FFLOOR",
      "FIFTH",
      "FILE-AUTHOR",
      "FILE-ERROR",
      "FILE-ERROR-PATHNAME",
      "FILE-LENGTH",
      "FILE-NAMESTRING",
      "FILE-POSITION",
      "FILE-STREAM",
      "FILE-STRING-LENGTH",
      "FILE-WRITE-DATE",
      "FILL",
      "FILL-POINTER",
      "FIND",
      "FIND-ALL-SYMBOLS",
      "FIND-CLASS",
      "FIND-IF",
      "FIND-IF-NOT",
      "FIND-METHOD",
      "FIND-PACKAGE",
      "FIND-RESTART",
      "FIND-SYMBOL",
      "FINISH-OUTPUT",
      "FIRST",
      "FIXNUM",
      "FLET",
      "FLOAT",
      "FLOAT-DIGITS",
      "FLOAT-PRECISION",
      "FLOAT-RADIX",
      "FLOAT-SIGN",
      "FLOATING-POINT-INEXACT",
      "FLOATING-POINT-INVALID-OPERATION",
      "FLOATING-POINT-OVERFLOW",
      "FLOATING-POINT-UNDERFLOW",
      "FLOATP",
      "FLOOR",
      "FMAKUNBOUND",
      "FORCE-OUTPUT",
      "FORMAT",
      "FORMATTER",
      "FOURTH",
      "FRESH-LINE",
      "FROUND",
      "FTRUNCATE",
      "FTYPE",
      "FUNCALL",
      "FUNCTION",
      "FUNCTION-KEYWORDS",
      "FUNCTION-LAMBDA-EXPRESSION",
      "FUNCTIONP",
      "GCD",
      "GENERIC-FUNCTION",
      "GENSYM",
      "GENTEMP",
      "GET",
      "GET-DECODED-TIME",
      "GET-DISPATCH-MACRO-CHARACTER",
      "GET-INTERNAL-REAL-TIME",
      "GET-INTERNAL-RUN-TIME",
      "GET-MACRO-CHARACTER",
      "GET-OUTPUT-STREAM-STRING",
      "GET-PROPERTIES",
      "GET-SETF-EXPANSION",
      "GET-UNIVERSAL-TIME",
      "GETF",
      "GETHASH",
      "GO",
      "GRAPHIC-CHAR-P",
      "HANDLER-BIND",
      "HANDLER-CASE",
      "HASH-TABLE",
      "HASH-TABLE-COUNT",
      "HASH-TABLE-P",
      "HASH-TABLE-REHASH-SIZE",
      "HASH-TABLE-REHASH-THRESHOLD",
      "HASH-TABLE-SIZE",
      "HASH-TABLE-TEST",
      "HOST-NAMESTRING",
      "IDENTITY",
      "IF",
      "IGNORABLE",
      "IGNORE",
      "IGNORE-ERRORS",
      "IMAGPART",
      "IMPORT",
      "IN-PACKAGE",
      "INCF",
      "INITIALIZE-INSTANCE",
      "INLINE",
      "INPUT-STREAM-P",
      "INSPECT",
      "INTEGER",
      "INTEGER-DECODE-FLOAT",
      "INTEGER-LENGTH",
      "INTEGERP",
      "INTERACTIVE-STREAM-P",
      "INTERN",
      "INTERNAL-TIME-UNITS-PER-SECOND",
      "INTERSECTION",
      "INVALID-METHOD-ERROR",
      "INVOKE-DEBUGGER",
      "INVOKE-RESTART",
      "INVOKE-RESTART-INTERACTIVELY",
      "ISQRT",
      "KEYWORD",
      "KEYWORDP",
      "LABELS",
      "LAMBDA",
      "LAMBDA-LIST-KEYWORDS",
      "LAMBDA-PARAMETERS-LIMIT",
      "LAST",
      "LCM",
      "LDB",
      "LDB-TEST",
      "LDIFF",
      "LEAST-NEGATIVE-DOUBLE-FLOAT",
      "LEAST-NEGATIVE-LONG-FLOAT",
      "LEAST-NEGATIVE-NORMALIZED-DOUBLE-FLOAT",
      "LEAST-NEGATIVE-NORMALIZED-LONG-FLOAT",
      "LEAST-NEGATIVE-NORMALIZED-SHORT-FLOAT",
      "LEAST-NEGATIVE-NORMALIZED-SINGLE-FLOAT",
      "LEAST-NEGATIVE-SHORT-FLOAT",
      "LEAST-NEGATIVE-SINGLE-FLOAT",
      "LEAST-POSITIVE-DOUBLE-FLOAT",
      "LEAST-POSITIVE-LONG-FLOAT",
      "LEAST-POSITIVE-NORMALIZED-DOUBLE-FLOAT",
      "LEAST-POSITIVE-NORMALIZED-LONG-FLOAT",
      "LEAST-POSITIVE-NORMALIZED-SHORT-FLOAT",
      "LEAST-POSITIVE-NORMALIZED-SINGLE-FLOAT",
      "LEAST-POSITIVE-SHORT-FLOAT",
      "LEAST-POSITIVE-SINGLE-FLOAT",
      "LENGTH",
      "LET",
      "LET*",
      "LISP-IMPLEMENTATION-TYPE",
      "LISP-IMPLEMENTATION-VERSION",
      "LIST",
      "LIST*",
      "LIST-ALL-PACKAGES",
      "LIST-LENGTH",
      "LISTEN",
      "LISTP",
      "LOAD",
      "LOAD-LOGICAL-PATHNAME-TRANSLATIONS",
      "LOAD-TIME-VALUE",
      "LOCALLY",
      "LOG",
      "LOGAND",
      "LOGANDC1",
      "LOGANDC2",
      "LOGBITP",
      "LOGCOUNT",
      "LOGEQV",
      "LOGIOR",
      "LOGNAND",
      "LOGNOR",
      "LOGNOT",
      "LOGORC1",
      "LOGORC2",
      "LOGTEST",
      "LOGXOR",
      "LONG-FLOAT",
      "LONG-FLOAT-NEGATIVE-EPSILON",
      "LONG-FLOAT-EPSILON",
      "LOOP",
      "LOOP-FINISH",
      "LOWER-CASE-P",
      "MACHINE-INSTANCE",
      "MACHINE-TYPE",
      "MACHINE-VERSION",
      "MACRO-FUNCTION",
      "MACROEXPAND",
      "MACROEXPAND-1",
      "MACROLET",
      "MAKE-ARRAY",
      "MAKE-BROADCAST-STREAM",
      "MAKE-CONCATENATED-STREAM",
      "MAKE-CONDITION",
      "MAKE-DISPATCH-MACRO-CHARACTER",
      "MAKE-ECHO-STREAM",
      "MAKE-HASH-TABLE",
      "MAKE-INSTANCE",
      "MAKE-INSTANCES-OBSOLETE",
      "MAKE-LIST",
      "MAKE-LOAD-FORM",
      "MAKE-LOAD-FORM-SAVING-SLOTS",
      "MAKE-METHOD",
      "MAKE-PACKAGE",
      "MAKE-PATHNAME",
      "MAKE-RANDOM-STATE",
      "MAKE-SEQUENCE",
      "MAKE-STRING",
      "MAKE-STRING-INPUT-STREAM",
      "MAKE-STRING-OUTPUT-STREAM",
      "MAKE-SYMBOL",
      "MAKE-SYNONYM-STREAM",
      "MAKE-TWO-WAY-STREAM",
      "MAKUNBOUND",
      "MAP",
      "MAP-INTO",
      "MAPC",
      "MAPCAN",
      "MAPCAR",
      "MAPCON",
      "MAPHASH",
      "MAPL",
      "MAPLIST",
      "MASK-FIELD",
      "MAX",
      "MEMBER",
      "MEMBER-IF",
      "MEMBER-IF-NOT",
      "MERGE",
      "MERGE-PATHNAMES",
      "METHOD",
      "METHOD-COMBINATION",
      "METHOD-COMBINATION-ERROR",
      "METHOD-QUALIFIERS",
      "MIN",
      "MINUSP",
      "MISMATCH",
      "MOD",
      "MUFFLE-WARNING",
      "MULTIPLE-VALUE-BIND",
      "MULTIPLE-VALUE-CALL",
      "MULTIPLE-VALUE-LIST",
      "MULTIPLE-VALUE-PROG1",
      "MULTIPLE-VALUE-SETQ",
      "MULTIPLE-VALUES-LIMIT",
      "NAME-CHAR",
      "NAMESTRING",
      "NBOUNDP",
      "NCONC",
      "NEXT-METHOD-P",
      "NIL",
      "NINTERSECTION",
      "NINTH",
      "NO-APPLICABLE-METHOD",
      "NO-NEXT-METHOD",
      "NOT",
      "NOTANY",
      "NOTEVERY",
      "NOTINLINE",
      "NRECONC",
      "NREVERSE",
      "NSET-DIFFERENCE",
      "NSET-EXCLUSIVE-OR",
      "NSTRING-CAPITALIZE",
      "NSTRING-DOWNCASE",
      "NSTRING-UPCASE",
      "NSUBLIS",
      "NSUBST",
      "NSUBST-IF",
      "NSUBST-IF-NOT",
      "NSUBSTITUTE",
      "NSUBSTITUTE-IF",
      "NSUBSTITUTE-IF-NOT",
      "NTH",
      "NTH-VALUE",
      "NTHCDR",
      "NULL",
      "NUMBER",
      "NUMBERP",
      "NUMERATOR",
      "NUNION",
      "ODDP",
      "OPEN",
      "OPEN-STREAM-P",
      "OPTIMIZE",
      "OR",
      "OTHERWISE",
      "OUTPUT-STREAM-P",
      "PACKAGE",
      "PACKAGE-ERROR",
      "PACKAGE-ERROR-PACKAGE",
      "PACKAGE-NAME",
      "PACKAGE-NICKNAMES",
      "PACKAGE-SHADOWING-SYMBOLS",
      "PACKAGE-USE-LIST",
      "PACKAGE-USED-BY-LIST",
      "PACKAGEP",
      "PAIRLIS",
      "PARSE-ERROR",
      "PARSE-INTEGER",
      "PARSE-NAMESTRING",
      "PATHNAME",
      "PATHNAME-DEVICE",
      "PATHNAME-DIRECTORY",
      "PATHNAME-HOST",
      "PATHNAME-MATCH-P",
      "PATHNAME-NAME",
      "PATHNAME-TYPE",
      "PATHNAME-VERSION",
      "PATHNAMEP",
      "PEEK-CHAR",
      "PHASE",
      "PI",
      "PLUSP",
      "POP",
      "POSITION",
      "POSITION-IF",
      "POSITION-IF-NOT",
      "PPRINT",
      "PPRINT-DISPATCH",
      "PPRINT-EXIT-IF-LIST-EXHAUSTED",
      "PPRINT-FILL",
      "PPRINT-INDENT",
      "PPRINT-LINEAR",
      "PPRINT-LOGICAL-BLOCK",
      "PPRINT-NEWLINE",
      "PPRINT-POP",
      "PPRINT-TAB",
      "PPRINT-TABULAR",
      "PRIN1",
      "PRIN1-TO-STRING",
      "PRINC",
      "PRINC-TO-STRING",
      "PRINT",
      "PRINT-NOT-READABLE",
      "PRINT-NOT-READABLE-OBJECT",
      "PRINT-OBJECT",
      "PRINT-UNREADABLE-OBJECT",
      "PROBE-FILE",
      "PROCLAMATION",
      "PROCLAIM",
      "PROG",
      "PROG*",
      "PROG1",
      "PROG2",
      "PROGN",
      "PROGRAM-ERROR",
      "PROGV",
      "PROVIDE",
      "PSETF",
      "PSETQ",
      "PUSH",
      "PUSHNEW",
      "RANDOM",
      "RANDOM-STATE",
      "RANDOM-STATE-P",
      "RASSOR",
      "RASSOC-IF",
      "RASSOC-IF-NOT",
      "RATIO",
      "RATIONAL",
      "RATIONALIZE",
      "RATIONALP",
      "READ",
      "READ-BYTE",
      "READ-CHAR",
      "READ-CHAR-NO-HANG",
      "READ-DELIMITED-LIST",
      "READ-FROM-STRING",
      "READ-LINE",
      "READ-PRESERVING-WHITESPACE",
      "READ-SEQUENCE",
      "READTABLE",
      "READTABLE-CASE",
      "READTABLEP",
      "REAL",
      "REALP",
      "REALPART",
      "REDUCE",
      "REINITIALIZE-INSTANCE",
      "REM",
      "REMF",
      "REMHASH",
      "REMOVE",
      "REMOVE-DUPLICATES",
      "REMOVE-IF",
      "REMOVE-IF-NOT",
      "REMOVE-METHOD",
      "REMPROP",
      "RENAME-FILE",
      "RENAME-PACKAGE",
      "REPLACE",
      "REQUIRE",
      "REST",
      "RESTART",
      "RESTART-BIND",
      "RESTART-CASE",
      "RESTART-NAME",
      "RETURN",
      "RETURN-FROM",
      "REVAPPEND",
      "REVERSE",
      "ROOM",
      "ROTATEF",
      "ROUND",
      "ROW-MAJOR-AREF",
      "RPLACA",
      "RPLACD",
      "SAFETY",
      "SATISFIES",
      "SBIT",
      "SCALE-FLOAT",
      "SCHAR",
      "SEARCH",
      "SECOND",
      "SEQUENCE",
      "SERIOUS-CONDITION",
      "SET",
      "SET-DIFFERENCE",
      "SET-DISPATCH-MACRO-CHARACTER",
      "SET-EXCLUSIVE-OR",
      "SET-MACRO-CHARACTER",
      "SET-PPRINT-DISPATCH",
      "SET-SYNTAX-FROM-CHAR",
      "SETF",
      "SETQ",
      "SEVENTH",
      "SHADOW",
      "SHADOWING-IMPORT",
      "SHARED-INITIALIZE",
      "SHIFTF",
      "SHORT-FLOAT",
      "SHORT-FLOAT-EPSILON",
      "SHORT-FLOAT-NEGATIVE-EPSILON",
      "SHORT-SITE-NAME",
      "SIGNAL",
      "SIGNED-BYTE",
      "SIGNUM",
      "SIMPLE-ARRAY",
      "SIMPLE-BASE-STRING",
      "SIMPLE-BIT-VECTOR",
      "SIMPLE-BIT-VECTOR-P",
      "SIMPLE-CONDITION",
      "SIMPLE-CONDITION-FORMAT-ARGUMENTS",
      "SIMPLE-CONDITION-FORMAT-CONTROL",
      "SIMPLE-ERROR",
      "SIMPLE-STRING",
      "SIMPLE-STRING-P",
      "SIMPLE-TYPE-ERROR",
      "SIMPLE-VECTOR",
      "SIMPLE-VECTOR-P",
      "SIMPLE-WARNING",
      "SIN",
      "SINGLE-FLOAT",
      "SINGLE-FLOAT-EPSILON",
      "SINGLE-FLOAT-NEGATIVE-EPSILON",
      "SINH",
      "SIXTH",
      "SLEEP",
      "SLOT-BOUNDP",
      "SLOT-EXISTS-P",
      "SLOT-MAKUNBOUND",
      "SLOT-MISSING",
      "SLOT-UNBOUND",
      "SLOT-VALUE",
      "SOFTWARE-TYPE",
      "SOFTWARE-VERSION",
      "SOME",
      "SORT",
      "SPACE",
      "SPECIAL",
      "SPECIAL-OPERATOR-P",
      "SPEED",
      "SQRT",
      "STABLE-SORT",
      "STANDARD",
      "STANDARD-CHAR",
      "STANDARD-CHAR-P",
      "STANDARD-CLASS",
      "STANDARD-GENERIC-FUNCTION",
      "STANDARD-METHOD",
      "STANDARD-OBJECT",
      "STEP",
      "STORAGE-CONDITION",
      "STORE-VALUE",
      "STREAM",
      "STREAM-ELEMENT-TYPE",
      "STREAM-ERROR",
      "STREAM-ERROR-STREAM",
      "STREAM-EXTERNAL-FORMAT",
      "STRING",
      "STRING-CAPITALIZE",
      "STRING-CHAR",
      "STRING-CHAR-P",
      "STRING-DOWNCASE",
      "STRING-EQUAL",
      "STRING-GREATERP",
      "STRING-LEFT-TRIM",
      "STRING-LESSP",
      "STRING-NOT-EQUAL",
      "STRING-NOT-GREATERP",
      "STRING-NOT-LESSP",
      "STRING-RIGHT-TRIM",
      "STRING-STREAM",
      "STRING-TRIM",
      "STRING-UPCASE",
      "STRING/=",
      "STRING<",
      "STRING<=",
      "STRING=",
      "STRING>",
      "STRING>=",
      "STRINGP",
      "STRUCTURE",
      "STRUCTURE-CLASS",
      "STRUCTURE-OBJECT",
      "STYLE-WARNING",
      "SUBLIS",
      "SUBSEQ",
      "SUBSETP",
      "SUBST",
      "SUBST-IF",
      "SUBST-IF-NOT",
      "SUBSTITUTE",
      "SUBSTITUTE-IF",
      "SUBSTITUTE-IF-NOT",
      "SUBTYPEP",
      "SVREF",
      "SXHASH",
      "SYMBOL",
      "SYMBOL-FUNCTION",
      "SYMBOL-MACROLET",
      "SYMBOL-NAME",
      "SYMBOL-PACKAGE",
      "SYMBOL-PLIST",
      "SYMBOL-VALUE",
      "SYMBOLP",
      "SYNONYM-STREAM",
      "SYNONYM-STREAM-SYMBOL",
      "T",
      "TAGBODY",
      "TAILP",
      "TAN",
      "TANH",
      "TENTH",
      "TERPRI",
      "THE",
      "THIRD",
      "TIME",
      "TRACE",
      "TRANSLATE-LOGICAL-PATHNAME",
      "TRANSLATE-PATHNAME",
      "TREE-EQUAL",
      "TRUENAME",
      "TRUNCATE",
      "TWO-WAY-STREAM",
      "TWO-WAY-STREAM-INPUT-STREAM",
      "TWO-WAY-STREAM-OUTPUT-STREAM",
      "TYPE",
      "TYPE-ERROR",
      "TYPE-ERROR-DATUM",
      "TYPE-ERROR-EXPECTED-TYPE",
      "TYPE-OF",
      "TYPECASE",
      "TYPEP",
      "UNBOUND-SLOT",
      "UNBOUND-SLOT-INSTANCE",
      "UNBOUND-VARIABLE",
      "UNDEFINED-FUNCTION",
      "UNEXPORT",
      "UNINTERN",
      "UNION",
      "UNLESS",
      "UNREAD-CHAR",
      "UNSIGNED-BYTE",
      "UNTRACE",
      "UNUSE-PACKAGE",
      "UNWIND-PROTECT",
      "UPDATE-INSTANCE-FOR-DIFFERENT-CLASS",
      "UPDATE-INSTANCE-FOR-REDEFINED-CLASS",
      "UPGRADED-ARRAY-ELEMENT-TYPE",
      "UPGRADED-COMPLEX-PART-TYPE",
      "UPPER-CASE-P",
      "USE-PACKAGE",
      "USE-VALUE",
      "USER-HOMEDIR-PATHNAME",
      "VALUES",
      "VALUES-LIST",
      "VARIABLE",
      "VECTOR",
      "VECTOR-POP",
      "VECTOR-PUSH",
      "VECTOR-PUSH-EXTEND",
      "VECTORP",
      "WARN",
      "WARNING",
      "WHEN",
      "WILD-PATHNAME-P",
      "WITH-ACCESSORS",
      "WITH-COMPILATION-UNIT",
      "WITH-CONDITION-RESTARTS",
      "WITH-HASH-TABLE-ITERATOR",
      "WITH-INPUT-FROM-STRING",
      "WITH-OPEN-FILE",
      "WITH-OPEN-STREAM",
      "WITH-OUTPUT-TO-STRING",
      "WITH-PACKAGE-ITERATOR",
      "WITH-SIMPLE-RESTART",
      "WITH-SLOTS",
      "WITH-STANDARD-IO-SYNTAX",
      "WRITE",
      "WRITE-BYTE",
      "WRITE-CHAR",
      "WRITE-LINE",
      "WRITE-SEQUENCE",
      "WRITE-STRING",
      "WRITE-TO-STRING",
      "Y-OR-N-P",
      "YES-OR-NO-P",
      "ZEROP"
    ]

    cl_symbols =
      cl_exports
      |> MapSet.new()
      |> MapSet.union(MapSet.new(@missing_cl_exports))
      |> MapSet.difference(MapSet.new(@nonstandard_cl_exports))

    cl_pkg = %ExLisp.Package{
      name: "COMMON-LISP",
      nicknames: ["CL"],
      use_list: [],
      used_by_list: ["COMMON-LISP-USER"],
      external_symbols: cl_symbols,
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

    uiop_exports = [
      "DEFINE-PACKAGE",
      "ENSURE-LIST",
      "SYMBOL-CALL",
      "FILE-EXISTS-P",
      "DIRECTORY-EXISTS-P",
      "DIRECTORY-PATHNAME-P",
      "DIRECTORY-FILES",
      "SUBDIRECTORIES",
      "UNIX-NAMESTRING",
      "DELETE-FILE-IF-EXISTS",
      "GETCWD",
      "DEFAULT-TEMPORARY-DIRECTORY",
      "ENSURE-DIRECTORY-PATHNAME",
      "WITH-TEMPORARY-FILE",
      "RUN-PROGRAM",
      "QUIT"
    ]

    uiop_pkg = %ExLisp.Package{
      name: "UIOP",
      nicknames: [],
      use_list: ["COMMON-LISP"],
      used_by_list: [],
      external_symbols: MapSet.new(uiop_exports),
      internal_symbols: MapSet.new()
    }

    asdf_pkg = %ExLisp.Package{
      name: "ASDF",
      nicknames: [],
      use_list: ["COMMON-LISP"],
      used_by_list: [],
      external_symbols:
        MapSet.new([
          "LOAD-SYSTEM",
          "FIND-SYSTEM",
          "COMPONENT-PATHNAME",
          "SYSTEM-SOURCE-DIRECTORY",
          "SYSTEM-RELATIVE-PATHNAME",
          "REGISTER-SYSTEM-PACKAGES"
        ]),
      internal_symbols: MapSet.new()
    }

    uiop_image_pkg = %ExLisp.Package{
      name: "UIOP/IMAGE",
      nicknames: ["UIOP.IMAGE"],
      use_list: ["COMMON-LISP"],
      used_by_list: [],
      external_symbols: MapSet.new(["PRINT-CONDITION-BACKTRACE"]),
      internal_symbols: MapSet.new()
    }

    swank_pkg = %ExLisp.Package{
      name: "SWANK",
      nicknames: [],
      use_list: ["COMMON-LISP"],
      used_by_list: [],
      external_symbols: MapSet.new(["CREATE-SERVER", "STOP-SERVER"]),
      internal_symbols: MapSet.new()
    }

    ppcre_pkg = %ExLisp.Package{
      name: "CL-PPCRE",
      nicknames: ["PPCRE"],
      use_list: ["COMMON-LISP"],
      used_by_list: [],
      external_symbols:
        MapSet.new([
          "CREATE-SCANNER",
          "SCAN",
          "SCAN-TO-STRINGS",
          "SPLIT",
          "REGEX-REPLACE",
          "REGEX-REPLACE-ALL",
          "QUOTE-META-CHARS"
        ]),
      internal_symbols: MapSet.new()
    }

    babel_encodings_pkg = %ExLisp.Package{
      name: "BABEL-ENCODINGS",
      nicknames: [],
      use_list: ["COMMON-LISP", "ALEXANDRIA"],
      used_by_list: [],
      external_symbols:
        MapSet.new([
          "LIST-CHARACTER-ENCODINGS",
          "GET-CHARACTER-ENCODING",
          "*DEFAULT-CHARACTER-ENCODING*"
        ]),
      internal_symbols: MapSet.new()
    }

    babel_pkg = %ExLisp.Package{
      name: "BABEL",
      nicknames: [],
      use_list: ["COMMON-LISP", "BABEL-ENCODINGS"],
      used_by_list: [],
      external_symbols:
        MapSet.new([
          "STRING-TO-OCTETS",
          "OCTETS-TO-STRING",
          "STRING-SIZE-IN-OCTETS",
          "VECTOR-SIZE-IN-CHARS",
          "LIST-CHARACTER-ENCODINGS",
          "*DEFAULT-CHARACTER-ENCODING*"
        ]),
      internal_symbols: MapSet.new()
    }

    quri_pkg = %ExLisp.Package{
      name: "QURI",
      nicknames: [],
      use_list: ["COMMON-LISP"],
      used_by_list: [],
      external_symbols:
        MapSet.new([
          "URI",
          "URI-SCHEME",
          "URI-HOST",
          "URI-PORT",
          "URI-PATH",
          "URI-QUERY",
          "URL-ENCODE",
          "URL-DECODE",
          "URL-ENCODE-PARAMS",
          "URL-DECODE-PARAMS",
          "MERGE-URIS"
        ]),
      internal_symbols: MapSet.new()
    }

    yason_pkg = %ExLisp.Package{
      name: "YASON",
      nicknames: [],
      use_list: ["COMMON-LISP"],
      used_by_list: [],
      external_symbols:
        MapSet.new([
          "PARSE",
          "ENCODE",
          "ENCODE-ALIST",
          "ENCODE-PLIST",
          "ENCODE-SCALAR",
          "MAKE-JSON-OUTPUT-STREAM",
          "WITH-OUTPUT",
          "WITH-OUTPUT-TO-STRING*"
        ]),
      internal_symbols: MapSet.new()
    }

    ironclad_pkg = %ExLisp.Package{
      name: "IRONCLAD",
      nicknames: ["CRYPTO"],
      use_list: ["COMMON-LISP"],
      used_by_list: [],
      external_symbols:
        MapSet.new([
          "RANDOM-DATA",
          "BYTE-ARRAY-TO-HEX-STRING",
          "HEX-STRING-TO-BYTE-ARRAY",
          "DIGEST-SEQUENCE",
          "DIGEST-FILE",
          "MAKE-DIGEST",
          "SHA1",
          "SHA224",
          "SHA256",
          "SHA384",
          "SHA512",
          "MD5"
        ]),
      internal_symbols: MapSet.new()
    }

    gray_streams_pkg = %ExLisp.Package{
      name: "TRIVIAL-GRAY-STREAMS",
      nicknames: [],
      use_list: ["COMMON-LISP"],
      used_by_list: [],
      external_symbols:
        MapSet.new([
          "FUNDAMENTAL-STREAM",
          "FUNDAMENTAL-OUTPUT-STREAM",
          "FUNDAMENTAL-INPUT-STREAM",
          "FUNDAMENTAL-CHARACTER-STREAM",
          "FUNDAMENTAL-BINARY-STREAM",
          "STREAM-WRITE-BYTE",
          "STREAM-WRITE-SEQUENCE",
          "STREAM-WRITE-CHAR",
          "STREAM-WRITE-STRING",
          "STREAM-ELEMENT-TYPE",
          "STREAM-FINISH-OUTPUT",
          "STREAM-FILE-POSITION",
          "OPEN-STREAM-P"
        ]),
      internal_symbols: MapSet.new()
    }

    flexi_streams_pkg = %ExLisp.Package{
      name: "FLEXI-STREAMS",
      nicknames: ["FLEX"],
      use_list: ["COMMON-LISP", "TRIVIAL-GRAY-STREAMS"],
      used_by_list: [],
      external_symbols:
        MapSet.new([
          "VECTOR-STREAM",
          "VECTOR-STREAM-VECTOR",
          "MAKE-IN-MEMORY-INPUT-STREAM",
          "MAKE-IN-MEMORY-OUTPUT-STREAM",
          "GET-OUTPUT-STREAM-SEQUENCE",
          "STRING-TO-OCTETS",
          "OCTETS-TO-STRING"
        ]),
      internal_symbols: MapSet.new()
    }

    sb_thread_exports = [
      "MAKE-THREAD",
      "JOIN-THREAD",
      "CURRENT-THREAD",
      "THREAD-ALIVE-P",
      "THREAD-NAME",
      "LIST-ALL-THREADS",
      "DESTROY-THREAD",
      "TERMINATE-THREAD",
      "THREAD-YIELD",
      "MAKE-MUTEX",
      "GRAB-MUTEX",
      "GET-MUTEX",
      "RELEASE-MUTEX",
      "WITH-MUTEX",
      "MAKE-SEMAPHORE",
      "WAIT-ON-SEMAPHORE",
      "SIGNAL-SEMAPHORE",
      "MUTEX-NAME",
      "MUTEX-VALUE",
      "MUTEX-OWNER"
    ]

    sb_thread_pkg = %ExLisp.Package{
      name: "SB-THREAD",
      nicknames: ["SB_THREAD"],
      use_list: ["COMMON-LISP"],
      used_by_list: [],
      external_symbols: MapSet.new(sb_thread_exports),
      internal_symbols: MapSet.new()
    }

    sb_ext_exports = [
      "EXIT",
      "QUIT",
      "POSIX-GETENV",
      "RUN-PROGRAM",
      "PROCESS-EXIT-CODE",
      "PROCESS-P",
      "PROCESS-ALIVE-P",
      "PROCESS-KILL",
      "PROCESS-WAIT",
      "PROCESS-CLOSE",
      "GC",
      "BYTES-CONSED-BETWEEN-GCS",
      "GET-TIME-OF-DAY",
      "*POSIX-ARGV*"
    ]

    sb_ext_pkg = %ExLisp.Package{
      name: "SB-EXT",
      nicknames: ["SB_EXT"],
      use_list: ["COMMON-LISP"],
      used_by_list: [],
      external_symbols: MapSet.new(sb_ext_exports),
      internal_symbols: MapSet.new()
    }

    sb_posix_exports = ["GETENV", "SETENV", "UNSETENV"]

    sb_posix_pkg = %ExLisp.Package{
      name: "SB-POSIX",
      nicknames: ["SB_POSIX"],
      use_list: ["COMMON-LISP"],
      used_by_list: [],
      external_symbols: MapSet.new(sb_posix_exports),
      internal_symbols: MapSet.new()
    }

    sb_sys_exports = ["*STDOUT*", "*STDIN*", "*STDERR*"]

    sb_sys_pkg = %ExLisp.Package{
      name: "SB-SYS",
      nicknames: ["SB_SYS"],
      use_list: ["COMMON-LISP"],
      used_by_list: [],
      external_symbols: MapSet.new(sb_sys_exports),
      internal_symbols: MapSet.new()
    }

    save_package(cl_pkg)
    save_package(cl_user_pkg)
    save_package(kw_pkg)
    save_package(uiop_pkg)
    save_package(asdf_pkg)
    save_package(uiop_image_pkg)
    save_package(swank_pkg)
    save_package(ppcre_pkg)
    save_package(babel_encodings_pkg)
    save_package(babel_pkg)
    save_package(quri_pkg)
    save_package(yason_pkg)
    save_package(ironclad_pkg)
    save_package(gray_streams_pkg)
    save_package(flexi_streams_pkg)
    save_package(sb_thread_pkg)
    save_package(sb_ext_pkg)
    save_package(sb_posix_pkg)
    save_package(sb_sys_pkg)
  end

  defp save_package(%ExLisp.Package{name: name, nicknames: nicks} = pkg) do
    :ets.insert(@table, {name, pkg})
    Enum.each(nicks, fn n -> :ets.insert(@table, {n, pkg}) end)
    bump_revision()
    ExLisp.Env.invalidate_resolution_cache()
  end

  # --- Package Lookup ---

  def find_package(pkg_designator) do
    ensure_tables()

    case pkg_designator do
      %ExLisp.Package{id: id} = p ->
        case :ets.lookup(@table, p.name) do
          [{_key, %ExLisp.Package{} = stored}] ->
            stored

          _ ->
            if id do
              :ets.tab2list(@table)
              |> Enum.map(&elem(&1, 1))
              |> Enum.uniq_by(& &1.name)
              |> Enum.find(&(&1.id == id))
            else
              nil
            end
        end

      name ->
        str = package_designator_string(name) |> String.upcase()

        [str, String.replace(str, "_", "-"), String.replace(str, "-", "_")]
        |> Enum.uniq()
        |> Enum.find_value(fn variant ->
          case :ets.lookup(@table, variant) do
            [{_key, %ExLisp.Package{} = pkg}] -> pkg
            _ -> nil
          end
        end)
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
      %ExLisp.Package{name: n} ->
        n

      nil when is_struct(pkg_designator, ExLisp.Package) ->
        nil

      _ ->
        ExLisp.Condition.error(:package_error, package: pkg_designator)
    end
  end

  def package_nicknames(pkg_designator) do
    if is_number(pkg_designator) and not is_struct(pkg_designator, ExLisp.Character) do
      ExLisp.Condition.error(:type_error, "")
    end

    case find_package(pkg_designator) do
      %ExLisp.Package{nicknames: n} ->
        n

      nil when is_struct(pkg_designator, ExLisp.Package) ->
        []

      _ ->
        ExLisp.Condition.error(:package_error, package: pkg_designator)
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
        Enum.map(s, &str_to_symbol/1)

      _ ->
        []
    end
  end

  def present_symbols_list(pkg_desig) do
    pkg = find_package!(pkg_desig)

    MapSet.union(pkg.internal_symbols, pkg.external_symbols)
    |> Enum.map(&symbol_in_package(&1, pkg))
  end

  def external_symbols_list(pkg_desig) do
    pkg = find_package!(pkg_desig)

    pkg.external_symbols
    |> Enum.map(&symbol_in_package(&1, pkg))
  end

  def all_symbols_list(pkg_desig) do
    pkg = find_package!(pkg_desig)

    used_externals =
      Enum.flat_map(pkg.use_list, fn u_name ->
        if u_pkg = find_package(u_name) do
          MapSet.to_list(u_pkg.external_symbols)
        else
          []
        end
      end)

    MapSet.union(pkg.internal_symbols, pkg.external_symbols)
    |> MapSet.union(MapSet.new(used_externals))
    |> Enum.map(&symbol_in_package(&1, pkg))
  end

  @doc """
  Iterates over the symbols accessible in a package, calling `fun` for each
  symbol.  The optional result is returned after iteration.
  """
  def do_symbols(pkg_desig \\ nil, fun \\ nil, result \\ nil)

  def do_symbols(pkg_desig, fun, result) when is_function(fun, 1) do
    package_iterator_entries(pkg_desig, [:internal, :external, :inherited])
    |> Enum.each(fn {symbol, _status, _package} -> fun.(symbol) end)

    result
  end

  def do_symbols(pkg_desig, fun, result) when is_function(fun, 2) do
    package_iterator_entries(pkg_desig, [:internal, :external, :inherited])
    |> Enum.each(fn {symbol, status, _package} -> fun.(symbol, status) end)

    result
  end

  def do_symbols(nil, nil, result), do: result

  @doc """
  Iterates only over the external symbols of a package.
  """
  def do_external_symbols(pkg_desig \\ nil, fun \\ nil, result \\ nil)

  def do_external_symbols(pkg_desig, fun, result) when is_function(fun, 1) do
    package_iterator_entries(pkg_desig, [:external])
    |> Enum.each(fn {symbol, _status, _package} -> fun.(symbol) end)

    result
  end

  def do_external_symbols(pkg_desig, fun, result) when is_function(fun, 2) do
    package_iterator_entries(pkg_desig, [:external])
    |> Enum.each(fn {symbol, status, _package} -> fun.(symbol, status) end)

    result
  end

  def do_external_symbols(nil, nil, result), do: result

  @doc """
  Iterates once over every symbol present in any registered package.
  """
  def do_all_symbols(fun, result \\ nil)

  def do_all_symbols(fun, result) when is_function(fun, 1) do
    package_iterator_entries(list_all_packages(), [:internal, :external])
    |> Enum.each(fn {symbol, _status, _package} -> fun.(symbol) end)

    result
  end

  def do_all_symbols(fun, result) when is_function(fun, 2) do
    package_iterator_entries(list_all_packages(), [:internal, :external])
    |> Enum.each(fn {symbol, status, _package} -> fun.(symbol, status) end)

    result
  end

  @doc """
  Returns symbols with the given name from every registered package.
  """
  def find_all_symbols(name_designator) do
    name = symbol_to_str(name_designator)

    Enum.flat_map(list_all_packages(), fn pkg ->
      present_symbols =
        if pkg.name == "KEYWORD" do
          MapSet.union(pkg.internal_symbols, pkg.external_symbols)
        else
          MapSet.union(
            MapSet.difference(pkg.internal_symbols, pkg.external_symbols),
            pkg.external_symbols
          )
        end

      if MapSet.member?(present_symbols, name), do: [symbol_in_package(name, pkg)], else: []
    end)
  end

  @doc """
  Calls `fun` with a zero-arity Common Lisp package iterator.

  Each iterator invocation returns
  `[:_values_, [more_p, symbol, accessibility, package]]`.
  """
  def with_package_iterator(pkg_designators, symbol_types, fun)
      when is_function(fun, 1) do
    iterator = package_iterator(pkg_designators, symbol_types)
    fun.(iterator)
  end

  @doc """
  Creates the stateful generator used by `with-package-iterator/3`.
  """
  def package_iterator(pkg_designators \\ nil, symbol_types \\ [:internal, :external, :inherited]) do
    entries = package_iterator_entries(pkg_designators, symbol_types)
    agent = :atomics.new(1, [])

    fn ->
      index = :atomics.add_get(agent, 1, 1) - 1

      case Enum.fetch(entries, index) do
        {:ok, {symbol, status, package}} ->
          [:_values_, [:t, symbol, status, package]]

        :error ->
          [:_values_, [nil, nil, nil, nil]]
      end
    end
  end

  defp package_iterator_entries(pkg_designators, symbol_types) do
    packages =
      cond do
        is_nil(pkg_designators) -> [find_package!(current_package())]
        is_list(pkg_designators) -> Enum.map(pkg_designators, &refresh_package/1)
        true -> [refresh_package(pkg_designators)]
      end

    types =
      symbol_types
      |> List.wrap()
      |> Enum.flat_map(&iterator_types/1)
      |> Enum.uniq()

    Enum.flat_map(packages, fn package ->
      Enum.flat_map([:internal, :external, :inherited], fn type ->
        if type in types, do: symbols_for_type(package, type), else: []
      end)
    end)
    |> Enum.uniq_by(fn {symbol, _status, package} -> {package.name, symbol} end)
  end

  defp refresh_package(%__MODULE__{name: name}), do: find_package!(name)
  defp refresh_package(designator), do: find_package!(designator)

  defp iterator_types(type) do
    case type |> to_string() |> String.trim_leading(":") |> String.downcase() do
      "internal" -> [:internal]
      "external" -> [:external]
      "inherited" -> [:inherited]
      "present" -> [:internal, :external]
      _ -> [:internal, :external, :inherited]
    end
  end

  defp symbols_for_type(package, :internal) do
    if package.name == "KEYWORD" do
      []
    else
      package.internal_symbols
      |> MapSet.difference(package.external_symbols)
      |> Enum.map(&{symbol_in_package(&1, package), :internal, package})
    end
  end

  defp symbols_for_type(package, :external) do
    symbols =
      if package.name == "KEYWORD" do
        MapSet.union(package.external_symbols, package.internal_symbols)
      else
        package.external_symbols
      end

    if package.name == "KEYWORD" do
      Enum.each(symbols, &ExLisp.Env.register_keyword(str_to_symbol(&1)))
    end

    Enum.map(symbols, &{symbol_in_package(&1, package), :external, package})
  end

  defp symbols_for_type(package, :inherited) do
    present =
      MapSet.union(package.internal_symbols, package.external_symbols)

    package.use_list
    |> Enum.flat_map(fn used_name ->
      case find_package(used_name) do
        nil ->
          []

        used ->
          Enum.map(used.external_symbols, &{&1, used, package})
      end
    end)
    |> Enum.reject(fn {name, _source, _package} -> MapSet.member?(present, name) end)
    |> Enum.uniq_by(&elem(&1, 0))
    |> Enum.map(fn {name, source, pkg} ->
      {symbol_in_package(name, source), :inherited, pkg}
    end)
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

    name = package_designator_string(name_designator)

    if find_package(name) do
      raise RuntimeError, "Package #{name} already exists"
    end

    nicks =
      case Keyword.get(options, :nicknames, []) do
        nil ->
          []

        list when is_list(list) ->
          Enum.map(list, &package_designator_string/1)

        single ->
          [package_designator_string(single)]
      end

    uses =
      case Keyword.get(options, :use, ["COMMON-LISP"]) do
        nil ->
          []

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
      id: System.unique_integer([:positive, :monotonic]),
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
        case pkg_designator do
          %ExLisp.Package{} ->
            nil

          _ ->
            signal_deletable_package_error(pkg_designator)
            nil
        end

      %ExLisp.Package{
        name: name,
        nicknames: nicks,
        use_list: uses,
        used_by_list: used_by
      } ->
        if used_by != [] do
          signal_deletable_package_error(find_package(name))
        end

        :ets.delete(@table, name)
        Enum.each(nicks, fn n -> :ets.delete(@table, n) end)

        Enum.each(used_by, fn using_name ->
          if using_pkg = find_package(using_name) do
            save_package(%{using_pkg | use_list: List.delete(using_pkg.use_list, name)})
          end
        end)

        Enum.each(uses, fn u_name ->
          if u_pkg = find_package(u_name) do
            save_package(%{u_pkg | used_by_list: List.delete(u_pkg.used_by_list, name)})
          end
        end)

        bump_revision()
        ExLisp.Env.invalidate_resolution_cache()
        :t
    end
  end

  defp signal_deletable_package_error(package) do
    condition = ExLisp.Condition.make_condition(:package_error, package: package)

    restart = %{
      name: :continue,
      fun: fn -> nil end,
      report: fn stream -> IO.write(stream, "Continue deleting the package") end,
      test: fn _ -> true end
    }

    ExLisp.Condition.push_restarts([restart], fn ->
      ExLisp.Condition.signal(condition)
    end)
  end

  def rename_package(pkg_designator, new_name_desig, new_nicknames_desig \\ []) do
    ensure_tables()
    old_pkg = find_package!(pkg_designator)

    new_name = package_designator_string(new_name_desig)

    new_nicknames =
      cond do
        is_nil(new_nicknames_desig) -> []
        is_list(new_nicknames_desig) -> new_nicknames_desig
        true -> [new_nicknames_desig]
      end

    new_nicks = Enum.map(new_nicknames, &package_designator_string/1)

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
    name = package_designator_string(name_desig)
    validate_defpackage_options!(name, options)

    pkg = find_package(name) || make_package(name, use: [])

    # Process options
    pkg =
      options
      |> Enum.sort_by(fn opt ->
        if defpackage_option_key(opt) == "USE", do: 0, else: 1
      end)
      |> Enum.reduce(pkg, fn opt, acc_pkg ->
        case opt do
          {:list, _, [opt_key | opt_args]} ->
            apply_defpackage_option(acc_pkg, opt_key, opt_args)

          {:quoted, _, [opt_key | opt_args]} ->
            apply_defpackage_option(acc_pkg, opt_key, opt_args)

          {:dotted_list, _, [opt_key | opt_args], _tail} ->
            apply_defpackage_option(acc_pkg, opt_key, opt_args)

          [opt_key | opt_args] ->
            apply_defpackage_option(acc_pkg, opt_key, opt_args)

          {opt_key, opt_args} ->
            apply_defpackage_option(
              acc_pkg,
              opt_key,
              if(is_list(opt_args), do: opt_args, else: [opt_args])
            )

          _ ->
            acc_pkg
        end
      end)

    save_package(pkg)
    pkg
  end

  defp apply_defpackage_option(pkg, key, args) do
    norm_key = symbol_to_str(key)

    case norm_key do
      "NICKNAMES" ->
        nicks = Enum.map(args, &package_designator_string/1) |> Enum.reject(&(&1 == ""))
        %{pkg | nicknames: Enum.uniq(pkg.nicknames ++ nicks)}

      "USE" ->
        uses =
          args
          |> Enum.map(&package_designator_string/1)
          |> Enum.reject(&(&1 == ""))
          |> Enum.map(fn u ->
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

      "USE-REEXPORT" ->
        uses =
          args
          |> Enum.map(&package_designator_string/1)
          |> Enum.reject(&(&1 == ""))
          |> Enum.map(fn source ->
            find_package!(source)
          end)

        Enum.each(uses, fn source_pkg ->
          save_package(%{
            source_pkg
            | used_by_list: Enum.uniq([pkg.name | source_pkg.used_by_list])
          })
        end)

        %{
          pkg
          | use_list: Enum.uniq(pkg.use_list ++ Enum.map(uses, & &1.name)),
            external_symbols:
              Enum.reduce(uses, pkg.external_symbols, fn source_pkg, symbols ->
                MapSet.union(symbols, source_pkg.external_symbols)
              end)
        }

      "EXPORT" ->
        syms = Enum.map(args, &symbol_to_str/1) |> Enum.reject(&(&1 == ""))

        %{
          pkg
          | external_symbols: MapSet.union(pkg.external_symbols, MapSet.new(syms)),
            symbol_packages: add_inherited_sources(pkg, syms)
        }

      "INTERN" ->
        syms = Enum.map(args, &symbol_to_str/1) |> Enum.reject(&(&1 == ""))

        own_syms =
          Enum.reject(syms, fn name ->
            case find_symbol_in_pkg(name, pkg) do
              {:found, _symbol, _status} -> true
              :not_found -> false
            end
          end)

        %{
          pkg
          | internal_symbols: MapSet.union(pkg.internal_symbols, MapSet.new(own_syms)),
            symbol_packages: Map.drop(pkg.symbol_packages, own_syms)
        }

      "IMPORT-FROM" ->
        case args do
          [from_pkg_desig | sym_names] ->
            syms = Enum.map(sym_names, &symbol_to_str/1) |> Enum.reject(&(&1 == ""))
            source_pkg = find_package!(from_pkg_desig)

            %{
              pkg
              | internal_symbols: MapSet.union(pkg.internal_symbols, MapSet.new(syms)),
                symbol_packages:
                  Map.merge(pkg.symbol_packages, Map.new(syms, &{&1, source_pkg.name}))
            }

          _ ->
            pkg
        end

      "SHADOW" ->
        syms = Enum.map(args, &symbol_to_str/1) |> Enum.reject(&(&1 == ""))

        %{
          pkg
          | shadowing_symbols: MapSet.union(pkg.shadowing_symbols, MapSet.new(syms)),
            internal_symbols: MapSet.union(pkg.internal_symbols, MapSet.new(syms))
        }

      "SHADOWING-IMPORT-FROM" ->
        case args do
          [from_pkg_desig | sym_names] ->
            syms = Enum.map(sym_names, &symbol_to_str/1) |> Enum.reject(&(&1 == ""))
            source_pkg = find_package!(from_pkg_desig)

            %{
              pkg
              | shadowing_symbols: MapSet.union(pkg.shadowing_symbols, MapSet.new(syms)),
                internal_symbols: MapSet.union(pkg.internal_symbols, MapSet.new(syms)),
                symbol_packages:
                  Map.merge(pkg.symbol_packages, Map.new(syms, &{&1, source_pkg.name}))
            }

          _ ->
            pkg
        end

      _ ->
        pkg
    end
  end

  defp validate_defpackage_options!(name, options) do
    option_groups =
      Enum.reduce(options, %{}, fn option, groups ->
        key = defpackage_option_key(option)
        args = defpackage_option_args(option)
        Map.update(groups, key, [args], &[args | &1])
      end)

    Enum.each(["SIZE", "DOCUMENTATION"], fn key ->
      if length(Map.get(option_groups, key, [])) > 1 do
        ExLisp.Condition.error(:program_error, "DEFPACKAGE option #{key} may occur only once")
      end
    end)

    Enum.each(List.flatten(Map.get(option_groups, "NICKNAMES", [])), fn nickname ->
      nickname = package_designator_string(nickname)

      existing = find_package(nickname)

      if (nickname != name and existing) && existing.name != name do
        ExLisp.Condition.error(:package_error, package: existing)
      end
    end)

    shadow = defpackage_option_names(option_groups, "SHADOW")
    shadow_import = defpackage_import_names(option_groups, "SHADOWING-IMPORT-FROM")
    import_from = defpackage_import_names(option_groups, "IMPORT-FROM")
    intern = defpackage_option_names(option_groups, "INTERN")
    all_names = shadow ++ shadow_import ++ import_from ++ intern

    if length(all_names) != length(Enum.uniq(all_names)) do
      ExLisp.Condition.error(:program_error, "DEFPACKAGE symbol-name options overlap")
    end

    exported = defpackage_option_names(option_groups, "EXPORT")

    if MapSet.intersection(MapSet.new(exported), MapSet.new(intern)) |> MapSet.size() > 0 do
      ExLisp.Condition.error(:program_error, "DEFPACKAGE :EXPORT and :INTERN overlap")
    end

    Enum.each(["SHADOWING-IMPORT-FROM", "IMPORT-FROM"], fn key ->
      Enum.each(Map.get(option_groups, key, []), fn
        [source | symbol_designators] ->
          source_pkg = find_package!(source)

          Enum.each(symbol_designators, fn symbol_designator ->
            name = symbol_to_str(symbol_designator)

            case find_symbol_in_pkg(name, source_pkg) do
              :not_found ->
                signal_missing_import(source_pkg)

              {:found, _symbol, _status} ->
                :ok
            end
          end)

        _ ->
          :ok
      end)
    end)
  end

  defp signal_missing_import(_package) do
    condition =
      ExLisp.Condition.make_condition(:simple_error, format_control: "Missing package symbol")

    restart = %{
      name: :continue,
      fun: fn -> nil end,
      report: fn stream -> IO.write(stream, "Continue defining the package") end,
      test: fn _ -> true end
    }

    ExLisp.Condition.push_restarts([restart], fn ->
      ExLisp.Condition.signal(condition)
    end)
  end

  defp defpackage_option_key(option) do
    case defpackage_option_parts(option) do
      [key | _] -> symbol_to_str(key)
      _ -> ""
    end
  end

  defp defpackage_option_args(option) do
    case defpackage_option_parts(option) do
      [_key | args] -> args
      _ -> []
    end
  end

  defp defpackage_option_parts({:list, _, parts}), do: parts
  defp defpackage_option_parts({:quoted, _, parts}), do: parts
  defp defpackage_option_parts({:dotted_list, _, parts, _tail}), do: parts
  defp defpackage_option_parts({key, args}) when is_list(args), do: [key | args]
  defp defpackage_option_parts(parts) when is_list(parts), do: parts
  defp defpackage_option_parts(_), do: []

  defp defpackage_option_names(groups, key) do
    groups
    |> Map.get(key, [])
    |> List.flatten()
    |> Enum.map(&symbol_to_str/1)
    |> Enum.reject(&(&1 == ""))
  end

  defp defpackage_import_names(groups, key) do
    groups
    |> Map.get(key, [])
    |> Enum.flat_map(fn
      [_source | names] -> Enum.map(names, &symbol_to_str/1)
      _ -> []
    end)
    |> Enum.reject(&(&1 == ""))
  end

  # --- Export / Import / Shadow / Use ---

  def export(symbols, pkg_desig \\ nil) do
    pkg =
      if is_nil(pkg_desig), do: find_package!(current_package()), else: find_package!(pkg_desig)

    sym_list = if is_list(symbols), do: symbols, else: [symbols]
    sym_strs = Enum.map(sym_list, &symbol_to_str/1)

    missing_binary_names =
      sym_list
      |> Enum.zip(sym_strs)
      |> Enum.filter(fn {symbol, name} ->
        is_binary(symbol) and find_symbol_in_pkg(name, pkg) == :not_found
      end)

    if missing_binary_names != [] do
      missing =
        Enum.map(missing_binary_names, fn {_symbol, name} -> name end)

      updated_pkg = %{
        pkg
        | internal_symbols: MapSet.union(pkg.internal_symbols, MapSet.new(missing))
      }

      save_package(updated_pkg)
      export(symbols, updated_pkg)
    else
      do_export(sym_list, sym_strs, pkg)
    end
  end

  defp do_export(sym_list, sym_strs, pkg) do
    Enum.zip(sym_strs, sym_list)
    |> Enum.each(fn {name, symbol} ->
      case find_symbol_in_pkg(name, pkg) do
        :not_found ->
          ExLisp.Condition.error(:package_error, package: pkg)

        {:found, accessible, _status} ->
          if not is_binary(symbol) and ExLisp.Builtins.eq(accessible, symbol) != :t do
            ExLisp.Condition.error(:package_error, package: pkg)
          end
      end

      Enum.each(pkg.used_by_list, fn using_name ->
        case find_package(using_name) do
          nil ->
            :ok

          using ->
            case find_symbol_in_pkg(name, using) do
              {:found, existing, status}
              when status in [:internal, :external] ->
                if not MapSet.member?(using.shadowing_symbols, name) and
                     ExLisp.Builtins.eq(existing, symbol) != :t do
                  ExLisp.Condition.error(:package_error, package: using)
                end

              _ ->
                :ok
            end
        end
      end)
    end)

    sources =
      Enum.zip(sym_strs, sym_list)
      |> Enum.reduce(pkg.symbol_packages, fn {name, symbol}, acc ->
        case symbol_package(symbol) do
          %ExLisp.Package{name: source_name} when source_name != pkg.name ->
            Map.put(acc, name, source_name)

          _ ->
            acc
        end
      end)

    updated = %{
      pkg
      | external_symbols: MapSet.union(pkg.external_symbols, MapSet.new(sym_strs)),
        symbol_packages: sources
    }

    save_package(updated)
    :t
  end

  def add_nickname(pkg_desig, nickname) do
    pkg = find_package!(pkg_desig)
    nick = package_designator_string(nickname)
    updated = %{pkg | nicknames: Enum.uniq(pkg.nicknames ++ [nick])}
    save_package(updated)
    updated
  end

  def unexport(symbols, pkg_desig \\ nil) do
    pkg =
      if is_nil(pkg_desig), do: find_package!(current_package()), else: find_package!(pkg_desig)

    sym_list = if is_list(symbols), do: symbols, else: [symbols]
    sym_strs = Enum.map(sym_list, &symbol_to_str/1)

    Enum.each(sym_strs, fn name ->
      if find_symbol_in_pkg(name, pkg) == :not_found do
        ExLisp.Condition.error(:package_error, package: pkg)
      end
    end)

    updated = %{
      pkg
      | external_symbols: MapSet.difference(pkg.external_symbols, MapSet.new(sym_strs))
    }

    save_package(updated)
    :t
  end

  def import(symbols, pkg_desig \\ nil) do
    pkg =
      if is_nil(pkg_desig), do: find_package!(current_package()), else: find_package!(pkg_desig)

    sym_list = if is_list(symbols), do: symbols, else: [symbols]
    sym_strs = Enum.map(sym_list, &symbol_to_str/1)

    sources =
      Enum.zip(sym_strs, sym_list)
      |> Map.new(fn {name, symbol} ->
        source = symbol_package(symbol) || pkg
        {name, source.name}
      end)

    values = Enum.zip(sym_strs, sym_list) |> Map.new()

    updated = %{
      pkg
      | internal_symbols: MapSet.union(pkg.internal_symbols, MapSet.new(sym_strs)),
        symbol_packages: Map.merge(pkg.symbol_packages, sources),
        symbol_values: Map.merge(pkg.symbol_values, values)
    }

    save_package(updated)
    :t
  end

  def shadow(symbols, pkg_desig \\ nil) do
    pkg =
      if is_nil(pkg_desig), do: find_package!(current_package()), else: find_package!(pkg_desig)

    sym_list = if is_list(symbols), do: symbols, else: [symbols]
    sym_strs = Enum.map(sym_list, &symbol_to_str/1)

    updated = %{
      pkg
      | shadowing_symbols: MapSet.union(pkg.shadowing_symbols, MapSet.new(sym_strs)),
        internal_symbols: MapSet.union(pkg.internal_symbols, MapSet.new(sym_strs))
    }

    save_package(updated)
    :t
  end

  def shadowing_import(symbols, pkg_desig \\ nil) do
    pkg =
      if is_nil(pkg_desig), do: find_package!(current_package()), else: find_package!(pkg_desig)

    sym_list = if is_list(symbols), do: symbols, else: [symbols]
    sym_strs = Enum.map(sym_list, &symbol_to_str/1)

    sources =
      Enum.zip(sym_strs, sym_list)
      |> Map.new(fn {name, symbol} ->
        source = symbol_package(symbol) || pkg
        {name, source.name}
      end)

    updated = %{
      pkg
      | internal_symbols: MapSet.union(pkg.internal_symbols, MapSet.new(sym_strs)),
        shadowing_symbols: MapSet.union(pkg.shadowing_symbols, MapSet.new(sym_strs)),
        symbol_packages: Map.merge(pkg.symbol_packages, sources),
        symbol_values: Map.merge(pkg.symbol_values, Enum.zip(sym_strs, sym_list) |> Map.new())
    }

    save_package(updated)
    :t
  end

  def use_package(packages_to_use, pkg_desig \\ nil) do
    pkg =
      if is_nil(pkg_desig), do: find_package!(current_package()), else: find_package!(pkg_desig)

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
    pkg =
      if is_nil(pkg_desig), do: find_package!(current_package()), else: find_package!(pkg_desig)

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
    pkg =
      if is_nil(pkg_desig), do: find_package!(current_package()), else: find_package!(pkg_desig)

    name = reader_symbol_to_str(name_desig)

    case find_symbol_in_pkg(name, pkg) do
      {:found, sym, status} ->
        [:_values_, [sym, status]]

      :not_found ->
        updated =
          if pkg.name == "KEYWORD" do
            %{pkg | external_symbols: MapSet.put(pkg.external_symbols, name)}
          else
            %{pkg | internal_symbols: MapSet.put(pkg.internal_symbols, name)}
          end

        save_package(updated)

        sym =
          if pkg.name == "KEYWORD" do
            ExLisp.Env.register_keyword(str_to_symbol(name))
          else
            symbol_in_package(name, pkg)
          end

        status = if pkg.name == "KEYWORD", do: :external, else: nil
        [:_values_, [sym, status]]
    end
  end

  @doc """
  Finds a symbol in package without creating it.
  Returns `[:_values_, [symbol, status]]` or `[:_values_, [nil, nil]]`.
  """
  def find_symbol(name_desig, pkg_desig \\ nil) do
    pkg =
      if is_nil(pkg_desig), do: find_package!(current_package()), else: find_package!(pkg_desig)

    name = reader_symbol_to_str(name_desig)

    case find_symbol_in_pkg(name, pkg) do
      {:found, sym, status} ->
        [:_values_, [sym, status]]

      :not_found ->
        [:_values_, [nil, nil]]
    end
  end

  def unintern(symbol_desig, pkg_desig \\ nil) do
    pkg =
      if is_nil(pkg_desig), do: find_package!(current_package()), else: find_package!(pkg_desig)

    name = symbol_to_str(symbol_desig)

    if MapSet.member?(pkg.internal_symbols, name) or MapSet.member?(pkg.external_symbols, name) do
      inherited =
        Enum.flat_map(pkg.use_list, fn used_name ->
          case find_package(used_name) do
            nil ->
              []

            used ->
              if MapSet.member?(used.external_symbols, name) do
                [symbol_in_package(name, used)]
              else
                []
              end
          end
        end)
        |> Enum.uniq()

      if length(inherited) > 1 do
        ExLisp.Condition.error(:package_error, package: pkg)
      end

      updated = %{
        pkg
        | internal_symbols: MapSet.delete(pkg.internal_symbols, name),
          external_symbols: MapSet.delete(pkg.external_symbols, name),
          shadowing_symbols: MapSet.delete(pkg.shadowing_symbols, name),
          symbol_packages: Map.delete(pkg.symbol_packages, name),
          symbol_values: Map.delete(pkg.symbol_values, name)
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
      nil ->
        nil

      :t ->
        find_package("COMMON-LISP")

      %ExLisp.Symbol{id: id, name: name} = symbol ->
        Enum.find_value(list_all_packages(), fn pkg ->
          if Enum.any?(pkg.symbol_values, fn {_key, value} ->
               value == symbol or match?(%ExLisp.Symbol{id: ^id, name: ^name}, value)
             end) do
            pkg
          end
        end)

      sym when is_atom(sym) ->
        str = Atom.to_string(sym)
        qualified_package = qualified_symbol_package(str)
        remembered_package = Process.get({:exlisp_symbol_package, sym})
        name = symbol_to_str(sym)
        uninterned? = String.starts_with?(str, "#:")
        reader_package = Process.get(:exlisp_current_package, "COMMON-LISP-USER")
        current_package = find_package(reader_package)

        owning_package =
          if uninterned? do
            Enum.find_value(list_all_packages(), fn package ->
              if Enum.any?(package.symbol_values || %{}, fn {_key, value} -> value == sym end) do
                find_symbol_package(package, name)
              end
            end)
          end

        current_symbol_package =
          if (not uninterned? and current_package) &&
               (MapSet.member?(current_package.internal_symbols, name) or
                  MapSet.member?(current_package.external_symbols, name) or
                  Map.has_key?(current_package.symbol_packages || %{}, name)) do
            find_symbol_package(current_package, name)
          end

        cond do
          owning_package ->
            owning_package

          uninterned? ->
            nil

          is_binary(remembered_package) ->
            find_package(remembered_package) ||
              if(remembered_package == "KEYWORD", do: find_package("KEYWORD"))

          qualified_package ->
            qualified_name = symbol_to_str(sym)

            if MapSet.member?(qualified_package.internal_symbols, qualified_name) or
                 MapSet.member?(qualified_package.external_symbols, qualified_name) or
                 Map.has_key?(qualified_package.symbol_values || %{}, qualified_name) do
              qualified_package
            end

          current_symbol_package ->
            current_symbol_package

          ExLisp.Env.keyword?(sym) or String.starts_with?(str, ":") ->
            find_package("KEYWORD")

          true ->
            # Search packages
            cl = find_package("COMMON-LISP")

            if cl && MapSet.member?(cl.external_symbols, name) do
              cl
            else
              current_package || cl
            end
        end

      _ ->
        nil
    end
  end

  def register_read_symbol(symbol) when is_atom(symbol) do
    package_name = Process.get(:exlisp_current_package, "COMMON-LISP-USER")
    cache_key = {:"$exlisp_read_symbol$", package_name, symbol}

    result =
      case Process.get(cache_key, :not_cached) do
        :not_cached ->
          result = do_register_read_symbol(symbol)
          Process.put(cache_key, result)
          result

        result ->
          result
      end

    remember_registered_read_symbol(result, package_name)
    result
  end

  def register_read_symbol(symbol), do: symbol

  defp remember_registered_read_symbol(symbol, package_name) do
    package = find_package(package_name)
    name = symbol_to_str(symbol)

    if package && not String.starts_with?(Atom.to_string(symbol), "#:") do
      source =
        find_symbol_package(package, name)
        |> case do
          nil -> if package == find_package("COMMON-LISP"), do: package
          found -> found
        end

      if source, do: remember_symbol_package(symbol, source)
    end

    symbol
  end

  defp do_register_read_symbol(symbol) do
    atom_name = Atom.to_string(symbol)

    cond do
      symbol in [nil, :t] or String.starts_with?(atom_name, "#:") ->
        symbol

      qualified_symbol_package(atom_name) ->
        [package_name, symbol_name] = String.split(atom_name, ".", parts: 2)
        pkg = find_package!(String.upcase(package_name) |> String.replace("_", "-"))

        case find_symbol_in_pkg(string_symbol_name(symbol_name), pkg) do
          {:found, resolved, _status} ->
            resolved

          :not_found ->
            name = string_symbol_name(symbol_name)
            save_package(%{pkg | internal_symbols: MapSet.put(pkg.internal_symbols, name)})
            symbol_in_package(name, pkg)
        end

      true ->
        pkg =
          find_package(Process.get(:exlisp_current_package, "COMMON-LISP-USER")) ||
            find_package!("COMMON-LISP-USER")

        name = symbol_to_str(symbol)

        {resolved, own_symbol?} =
          case find_symbol_in_pkg(name, pkg) do
            {:found, found_symbol, status} ->
              {found_symbol, status == :internal}

            :not_found ->
              save_package(%{pkg | internal_symbols: MapSet.put(pkg.internal_symbols, name)})
              {symbol, true}
          end

        result =
          if own_symbol? and ExLisp.Env.keyword?(symbol) and
               pkg.name not in ["COMMON-LISP", "COMMON-LISP-USER", "KEYWORD"] do
            String.to_atom("#{String.downcase(pkg.name)}.#{atom_name}")
          else
            resolved
          end

        remember_symbol_package(result, pkg)
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
      symbol_in_package(sym_up, pkg)
    else
      if MapSet.member?(pkg.external_symbols, sym_up) do
        symbol_in_package(sym_up, pkg)
      else
        raise RuntimeError, "Symbol #{sym_up} is not external in package #{pkg.name}"
      end
    end
  end

  # --- Helper functions ---

  defp find_symbol_in_pkg(name_up, %ExLisp.Package{} = pkg) do
    cond do
      pkg.name == "KEYWORD" and
          (ExLisp.Env.keyword?(str_to_symbol(name_up)) or
             MapSet.member?(pkg.external_symbols, name_up) or
             MapSet.member?(pkg.internal_symbols, name_up)) ->
        symbol = ExLisp.Env.register_keyword(str_to_symbol(name_up))
        {:found, symbol, :external}

      MapSet.member?(pkg.external_symbols, name_up) ->
        {:found, symbol_in_package(name_up, pkg), :external}

      MapSet.member?(pkg.internal_symbols, name_up) ->
        {:found, symbol_in_package(name_up, pkg), :internal}

      true ->
        # Search inherited symbols from use_list
        Enum.find_value(pkg.use_list, :not_found, fn u_name ->
          if u_pkg = find_package(u_name) do
            if MapSet.member?(u_pkg.external_symbols, name_up) do
              {:found, symbol_in_package(name_up, u_pkg), :inherited}
            end
          end
        end)
    end
  end

  def clean_uninterned(str) do
    case Regex.run(~r/^#:UNINTERNED_\d+_(.*)$/i, str) do
      [_, orig] -> orig
      _ -> str
    end
  end

  defp symbol_to_str(sym) do
    case sym do
      {:id, _, [n]} when is_binary(n) ->
        n |> clean_uninterned() |> string_symbol_name()

      {:id, _, [n]} when is_atom(n) ->
        n |> Atom.to_string() |> clean_uninterned() |> string_symbol_name()

      {:id, _, parts} when is_list(parts) ->
        parts
        |> Enum.map_join(".", fn
          part when is_atom(part) -> Atom.to_string(part)
          part -> to_string(part)
        end)
        |> clean_uninterned()
        |> string_symbol_name()

      {:keyword, _, kw} when is_atom(kw) ->
        atom_symbol_name(kw)

      {:keyword, _, kw} when is_binary(kw) ->
        kw |> clean_uninterned() |> string_symbol_name()

      {:lit, s} when is_binary(s) ->
        clean_uninterned(s)

      {:lit, a} when is_atom(a) ->
        atom_symbol_name(a)

      {:list, _, _} ->
        ""

      {:dotted_list, _, _, _} ->
        ""

      s when is_binary(s) ->
        clean_uninterned(s)

      a when is_atom(a) ->
        atom_symbol_name(a)

      %ExLisp.Symbol{name: n} ->
        n |> clean_uninterned() |> string_symbol_name()

      %ExLisp.Character{code: code} ->
        List.to_string([code])

      {:array, _, _} = array ->
        ExLisp.Builtins.to_string_val(array)

      _ ->
        ""
    end
  end

  defp reader_symbol_to_str(symbol) do
    if is_binary(symbol), do: symbol, else: symbol_to_str(symbol)
  end

  defp package_designator_string(%ExLisp.Package{name: name}), do: name
  defp package_designator_string(designator) when is_binary(designator), do: designator

  defp package_designator_string(designator) when is_atom(designator) do
    name = designator |> Atom.to_string() |> clean_uninterned()

    if String.starts_with?(name, "|") && String.ends_with?(name, "|") do
      string_symbol_name(name)
    else
      name
      |> String.trim_leading(":")
      |> String.upcase()
      |> String.replace("_", "-")
    end
  end

  defp package_designator_string(designator) do
    case symbol_to_str(designator) do
      "" -> ExLisp.Builtins.to_string_val(designator)
      name -> name
    end
  end

  defp atom_symbol_name(atom) do
    atom
    |> Atom.to_string()
    |> clean_uninterned()
    |> string_symbol_name()
  end

  defp string_symbol_name(str) do
    str = String.trim_leading(str, ":")

    case str do
      "|" <> rest ->
        String.trim_trailing(rest, "|")

      "#:UNINTERNED_" <> rest ->
        case String.split(rest, "_", parts: 2) do
          [_id, name] -> string_symbol_name(name)
          _ -> rest
        end

      qualified ->
        case String.split(qualified, ".", parts: 2) do
          [package, name] ->
            if find_package(package |> String.upcase() |> String.replace("_", "-")) do
              string_symbol_name(name)
            else
              String.upcase(qualified) |> String.replace("_", "-")
            end

          [name] ->
            String.upcase(name) |> String.replace("_", "-")
        end
    end
  end

  defp symbol_in_package(name, pkg_designator) do
    pkg = find_package!(pkg_designator)
    source_pkg = find_symbol_package(pkg, name)

    case Map.get(pkg.symbol_values || %{}, name) do
      nil ->
        base = str_to_symbol(name)

        if source_pkg.name in ["COMMON-LISP", "COMMON-LISP-USER", "KEYWORD"] or
             symbol_home_count(name, source_pkg) == 1 do
          remember_symbol_package(base, source_pkg)
          base
        else
          package_prefix = String.downcase(source_pkg.name)
          String.to_atom("#{package_prefix}.#{Atom.to_string(base)}")
        end

      symbol ->
        symbol
    end
  end

  defp find_symbol_package(pkg, name) do
    case Map.get(pkg.symbol_packages || %{}, name) do
      nil -> pkg
      package_name -> find_package(package_name) || pkg
    end
  end

  defp qualified_symbol_package(str) do
    case String.split(str, ".", parts: 2) do
      [package, _name] ->
        find_package(String.upcase(package) |> String.replace("_", "-"))

      _ ->
        nil
    end
  end

  def remember_symbol_package(symbol, %ExLisp.Package{name: name}) do
    Process.put({:exlisp_symbol_package, symbol}, name)
    symbol
  end

  def remember_symbol_package(symbol, package_name) do
    Process.put({:exlisp_symbol_package, symbol}, package_name)
    symbol
  end

  defp symbol_home_count(name, _source_pkg) do
    revision = :persistent_term.get(@revision_key, 0)

    {^revision, counts} =
      case Process.get(@home_count_cache_key) do
        {^revision, cached_counts} -> {revision, cached_counts}
        _ -> {revision, %{}}
      end

    case Map.fetch(counts, name) do
      {:ok, count} ->
        count

      :error ->
        count =
          list_all_packages()
          |> Enum.count(fn package ->
            MapSet.member?(package.internal_symbols, name) or
              MapSet.member?(package.external_symbols, name)
          end)

        Process.put(@home_count_cache_key, {revision, Map.put(counts, name, count)})
        count
    end
  end

  defp bump_revision do
    :persistent_term.put(@revision_key, System.unique_integer([:positive, :monotonic]))
  end

  defp add_inherited_sources(pkg, names) do
    Enum.reduce(names, pkg.symbol_packages, fn name, sources ->
      cond do
        Map.has_key?(sources, name) ->
          sources

        MapSet.member?(pkg.internal_symbols, name) or
            MapSet.member?(pkg.external_symbols, name) ->
          sources

        true ->
          case inherited_symbol_source(pkg, name) do
            nil -> sources
            source -> Map.put(sources, name, source.name)
          end
      end
    end)
  end

  defp inherited_symbol_source(pkg, name) do
    Enum.find_value(pkg.use_list, fn used_name ->
      case find_package(used_name) do
        %ExLisp.Package{} = used ->
          if MapSet.member?(used.external_symbols, name), do: used

        nil ->
          nil
      end
    end)
  end

  defp str_to_symbol(str) do
    if str == "NIL" do
      nil
    else
      normalized =
        if String.contains?(str, ".") do
          String.downcase(str)
        else
          str |> String.downcase() |> String.replace("-", "_")
        end

      if str == String.upcase(str) and
           Regex.match?(~r/^[A-Z0-9+*\/:=<>?!$%&.-]+$/, str) do
        String.to_atom(normalized)
      else
        String.to_atom("|#{str}|")
      end
    end
  end
end
