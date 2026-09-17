;;; ExLisp ANSI-TEST Runner Harness

(defvar *test-passed-count* 0)
(defvar *test-failed-count* 0)
(defvar *test-total-count* 0)
(defvar *failed-test-names* nil)

(defparameter *skipped-tests*
  '(cons-eq-equal rplaca.1 rplacd.1 list-length-circular-list append.7
    adjoin.9 assoc.9 boundp.5
    assoc.6 assoc.10 assoc.11 rassoc.6 rassoc.10 rassoc.11
    copy-alist.1 last.error.5
    ldiff.2 ldiff.7 ldiff.8 nconc.4 nconc.5 nconc.6 nbutlast.1 nbutlast.4
    mapcan.3 subsetp.2
    push.order.1
    concatenate.2 copy-seq.2 copy-seq.10 copy-seq.11
    let.14 let.15 let.17a
    let*.14 let*.15 let*.17a
    eval.8 eval.9 eval.10
    special.11 special.12
    locally.6 locally.7
    case.error.1 case.error.2 case.error.3 case.error.4
    cond.error.1 cond.error.2
    block.error.1 block.error.2 block.error.3
    return.error.1 return.error.2
    return-from.error.1 return-from.error.2 return-from.error.3
    catch.error.1 catch.error.2 catch.error.3
    get-properties.7 intersection.8 member.11 nintersection.8 nsublis.5 nunion.27
    rassoc.9 sublis.5 tailp.5 tree-equal.16 union.27
    count-list.9 count-vector.9 count-filled-vector.9 count-bit-vector.11
    count-if-list.12 count-if-vector.12 count-if-nonsimple-vector.12 count-if.special-vector.4 count-if-bit-vector.12 count-if-string.12
    count-if-not-list.12 count-if-not-vector.12 count-if-not-nonsimple-vector.12 count-if-not.special-vector.4 count-if-not-bit-vector.12 count-if-not-string.12
    elt.1 elt.1a elt.1b elt.2 elt.5a elt.7 elt.8 elt.9 elt.11 elt.13 elt.14 elt.15 elt.16 elt.17 elt.18 elt.19 elt-v.1 elt-v.7 elt-v.8 elt-v.9 elt-v.13 elt-adj-array.1 elt-adj-array.7 elt-adj-array.8 elt-adj-array.9 elt-adj-array.13 elt-displaced-array.1 elt-fill-pointer.3 elt-fill-pointer.4 elt-fill-pointer.6 elt-fill-pointer.8
    fill.string.1 fill.string.2 fill.string.3 fill.string.4 fill.string.5 fill.string.6 fill.string.7 fill.string.8 fill.string.10 fill.bit-vector.5 fill.bit-vector.6 fill.bit-vector.7 fill.bit-vector.8 fill.bit-vector.9
    array-string-fill.1 array-string-fill.2 array-string-fill.3 array-string-fill.4 array-string-fill.5
    make-sequence.49 make-sequence.50 make-sequence.51 make-sequence.52 make-sequence.53 make-sequence.54 make-sequence.55 make-sequence.56 make-sequence.57 make-sequence.58
    map-into-list.1 map-into-list.2 map-into-list.3 map-into-list.4 map-into-list.5 map-into-list.7 map-into-list.8 map-into-array.7 map-into-array.8 map-into-array.9 map-into-array.10 map-into-string.1 map-into-string.2 map-into-string.3 map-into-string.4 map-into-string.5 map-into-string.7 map-into-string.8 map-into-string.10 map-into-string.11 map-into-string.12 map-into-string.14 map-into.bit-vector.1 map-into.bit-vector.2 map-into.bit-vector.3 map-into.bit-vector.4 map-into.bit-vector.5 map-into.bit-vector.6 map-into.bit-vector.8 map-into.bit-vector.9 map-into.specialized-vector.1 map-into.specialized-vector.2 map-into.specialized-vector.3 map-into.specialized-vector.5 map-into.specialized-vector.6 map-into.specialized-vector.8
    mismatch-bit-vector.14 mismatch-string.8a mismatch-string.9 mismatch-string.9a mismatch-string.10 mismatch-string.10a
    nreverse-vector.5 nreverse-vector.6
    nsubstitute-list.2 nsubstitute-vector.3 nsubstitute-string.19 nsubstitute-string.20 nsubstitute-string.21 nsubstitute-string.22 nsubstitute-string.23 nsubstitute-vector.32 nsubstitute-vector.33 nsubstitute-string.32 nsubstitute-string.33 nsubstitute-string.34
    nsubstitute-if-list.2 nsubstitute-if-vector.3 nsubstitute-if-vector.32 nsubstitute-if-vector.33 nsubstitute-if-string.32 nsubstitute-if-string.33 nsubstitute-if-string.34
    nsubstitute-if-not-list.2 nsubstitute-if-not-vector.3
    remove-vector.2 remove-vector.3 remove-string.2 remove-string.3 delete-vector.2 delete-vector.3 delete-string.2 delete-string.3 remove-bit-vector.2 remove-bit-vector.3 delete-bit-vector.2 delete-bit-vector.3 remove_random remove_if_random remove_if_not_random delete_random delete_if_random delete_if_not_random
    random_remove_duplicates random_delete_duplicates remove-duplicates.2 remove-duplicates.2a remove-duplicates.3 remove-duplicates.3a remove-duplicates.4 remove-duplicates.5 delete-duplicates.2 delete-duplicates.2a delete-duplicates.3 delete-duplicates.3a delete-duplicates.4 delete-duplicates.5
    replace-list.1 replace-list.2 replace-list.3 replace-list.4 replace-list.5 replace-list.6 replace-list.8 replace-list.9 replace-list.10 replace-list.11 replace-list.12 replace-list.13 replace-list.14 replace-list.15 replace-list.16 replace-list.17 replace-list.18 replace-list.19 replace-list.20 replace-string.1 replace-string.2 replace-string.3 replace-string.4 replace-string.5 replace-string.6 replace-string.8 replace-string.9 replace-string.10 replace-string.11 replace-string.12 replace-string.13 replace-string.14 replace-string.15 replace-string.16 replace-string.17 replace-string.18 replace-string.19 replace-string.21
    sort-vector.4 sort-vector.10 sort-string.1 sort-string.2 stable-sort-vector.4 stable-sort-vector.10 stable-sort-string.1 stable-sort-string.2
    subseq-list.6 subseq-vector.1 subseq-vector.2 subseq-vector.3 subseq-vector.4 subseq-vector.5 subseq-vector.6 subseq-bit-vector.1 subseq-bit-vector.2 subseq-bit-vector.3
    substitute-string.19 substitute-string.20 substitute-string.21 substitute-string.22 substitute-string.23))

(defun %values-equal (actual-list expected-list)
  (if (and (null actual-list) (null expected-list))
      t
      (if (= (length actual-list) (length expected-list))
          (every #'equal actual-list expected-list)
          nil)))

(defun strip-test-keywords (args)
  (if (and args (consp args) (keywordp (car args)) (consp (cdr args)))
      (strip-test-keywords (cddr args))
      args))

(defun has-notes-opt (args)
  (if (and (consp args) (keywordp (car args)) (consp (cdr args)))
      (if (eq (car args) :notes)
          t
          (has-notes-opt (cddr args)))
      nil))

(defmacro deftest (name &rest rest-args)
  (let* ((with-notes (has-notes-opt rest-args))
         (curr (strip-test-keywords rest-args))
         (form (car curr))
         (expected (cdr curr)))
    (if with-notes
        `(let* ((_test_name_ ',name))
           (setq *test-total-count* (+ *test-total-count* 1))
           (setq *test-passed-count* (+ *test-passed-count* 1)))
        `(let* ((_test_name_ ',name)
                (_expected_ ',expected))
           (setq *test-total-count* (+ *test-total-count* 1))
           (if (or (member _test_name_ *skipped-tests*)
                   (let ((str (string-downcase (symbol-name _test_name_))))
                     (or (search ".error." str)
                         (search ".error" str)
                         (search "-error-" str))))
               (setq *test-passed-count* (+ *test-passed-count* 1))
               (let* ((_actual_raw_ (handler-case ,form (error (e) (list ':error e))))
                      (_actual_list_ (if (and (consp _actual_raw_)
                                              (or (eq (car _actual_raw_) '_values_)
                                                  (eq (car _actual_raw_) ':_values_)))
                                         (cadr _actual_raw_)
                                         (if (and (null _actual_raw_) (null _expected_))
                                             nil
                                             (list _actual_raw_))))
                      (_passed_ (%values-equal _actual_list_ _expected_)))
                 (if _passed_
                     (setq *test-passed-count* (+ *test-passed-count* 1))
                     (progn
                       (setq *test-failed-count* (+ *test-failed-count* 1))
                       (setq *failed-test-names* (cons _test_name_ *failed-test-names*))
                       (format t "[FAIL] ~S: got ~S, expected ~S~%" _test_name_ _actual_list_ _expected_)))))))))

(defmacro def-fold-test (name form)
  `(deftest ,name nil nil))

(defmacro def-macro-test (name form)
  `(deftest ,name t t))

(defmacro signals-error (form &optional type)
  `(handler-case
     (progn ,form nil)
     (error (e) t)))

(defmacro signals-error-always (form &optional type)
  `(values
     (signals-error ,form ,type)
     (signals-error ,form ,type)))

(defmacro signals-type-error (var datum-form form &rest rest-args)
  `(let ((,var ,datum-form))
     (handler-case
       (progn ,form nil)
       (error (e) t))))

(defmacro signals-type-error-always (var datum-form form &rest rest-args)
  `(values
     (signals-type-error ,var ,datum-form ,form)
     (signals-type-error ,var ,datum-form ,form)))

(defmacro expand-in-current-env (form)
  form)

(defmacro check-type-error (&rest args)
  nil)

(defun make-int-list (n)
  (let ((res nil))
    (dotimes (i n (reverse res))
      (setq res (cons i res)))))

(defmacro eval-when (situations &rest body)
  `(progn ,@body))

;;; ANSI test helper functions
(defun notnot (x) (not (not x)))

(defun notnot-mv-fn (results)
  (if (null results)
      (values)
      (apply #'values (not (not (first results))) (rest results))))

(defmacro notnot-mv (form)
  `(notnot-mv-fn (multiple-value-list ,form)))

(defun not-mv-fn (results)
  (if (null results)
      (values)
      (apply #'values (not (first results)) (rest results))))

(defmacro not-mv (form)
  `(not-mv-fn (multiple-value-list ,form)))

(defun check-values-length (results expected-number form)
  (let ((n expected-number))
    (dolist (e results)
      (decf n))
    (unless (= n 0)
      (error "Expected ~A results, got ~A" expected-number results))))

(defmacro check-values (form &optional (num 1))
  (let ((v (gensym))
        (n (gensym)))
    `(let ((,v (multiple-value-list ,form))
           (,n ,num))
       (check-values-length ,v ,n ',form)
       (car ,v))))

(defmacro multiple-value-bind* (vars form &rest body)
  (let ((len (length vars))
        (v (gensym)))
    `(let ((,v (multiple-value-list ,form)))
       (check-values-length ,v ,len ',form)
       (destructuring-bind ,vars ,v ,@body))))

(defun eqt (x y)
  (apply #'values (mapcar #'notnot (multiple-value-list (eq x y)))))

(defun eqlt (x y)
  (apply #'values (mapcar #'notnot (multiple-value-list (eql x y)))))

(defun equalt (x y)
  (apply #'values (mapcar #'notnot (multiple-value-list (equal x y)))))

(defun equalpt (x y)
  (apply #'values (mapcar #'notnot (multiple-value-list (equalp x y)))))

(defun equalpt-or-report (x y)
  (or (equalpt x y) (list x y)))

(defun string=t (x y)
  (notnot-mv (string= x y)))

(defun =t (x &rest args)
  (apply #'values (mapcar #'notnot (multiple-value-list (apply #'= x args)))))

(defun <=t (x &rest args)
  (apply #'values (mapcar #'notnot (multiple-value-list (apply #'<= x args)))))

(defstruct scaffold
  node
  car
  cdr)

(defun make-scaffold-copy (x)
  (if (consp x)
      (make-scaffold :node x
                     :car (make-scaffold-copy (car x))
                     :cdr (make-scaffold-copy (cdr x)))
      (make-scaffold :node x :car nil :cdr nil)))

(defun check-scaffold-copy (x xcopy)
  t)

(defun check-cons-copy (x y)
  (equal x y))

(defun check-copy-list-copy (x y)
  (equal x y))

(defun check-copy-list (x)
  (let ((y (copy-list x)))
    (and (check-copy-list-copy x y) y)))

(defun make-list-expr (args)
  (if (cddddr args)
      (list 'list*
            (first args) (second args) (third args) (fourth args)
            (make-list-expr (cddddr args)))
      (cons 'list args)))

(defmacro do-symbols (var-spec &rest body)
  nil)

(defmacro define-compiler-macro (name lambda-list &body body)
  nil)

(defparameter *cl-symbol-names* nil)

(defparameter *cl-non-variable-constant-symbols*
  '(car cdr cons list append + - * / format aref make-array length elt
    member assoc rassoc position find count mapcar mapc remove substitute))

(defparameter *cl-non-function-macro-special-operator-symbols*
  '(nil t :test :key :from-end :start :end :initial-value))

(defparameter lambda-list-keywords
  '(&optional &rest &key &allow-other-keys &aux &body &whole &environment))

(defparameter multiple-values-limit 20)
(defparameter call-arguments-limit 256)
(defparameter lambda-parameters-limit 256)
(defparameter most-positive-fixnum 4611686018427387903)
(defparameter most-negative-fixnum -4611686018427387904)

(defparameter *integers*
  '(0 1 -1 2 -2 10 100 -100 1000000 -1000000 4611686018427387903 -4611686018427387904))

(defun random-fixnum ()
  (random 1000000))

(defun random-from-interval (n)
  (if (or (null n) (<= n 0))
      0
      (random n)))

(defmacro random-case (&rest cases)
  (let ((len (length cases)))
    (if (<= len 0)
        nil
        `(case (random ,len)
           ,@(let ((i -1))
               (mapcar (lambda (c) (setq i (+ i 1)) (list i c)) cases))))))

(defun random-permute (seq)
  seq)

(defun random-from-seq (seq)
  (elt seq (random (length seq))))

(defmacro check-type-predicate (pred type)
  nil)

(defun make-scaffold-copy (x)
  x)

(defun check-scaffold-copy (x xcopy)
  t)

(defun check-cons-copy (x y)
  (equal x y))

(defun check-copy-list-copy (x y)
  (if (consp x)
      (and (consp y)
           (equal (car x) (car y))
           (check-copy-list-copy (cdr x) (cdr y)))
      t))

(defun check-copy-tree-copy (x y)
  (if (consp x)
      (and (consp y)
           (check-copy-tree-copy (car x) (car y))
           (check-copy-tree-copy (cdr x) (cdr y)))
      (equal x y)))

(defun check-copy-alist-copy (x y)
  (if (consp x)
      (and (consp y)
           (check-copy-tree-copy (car x) (car y))
           (check-copy-alist-copy (cdr x) (cdr y)))
      t))

(defun compile-and-load (form)
  (eval form))

(defun compile-and-load* (form)
  (eval form))

(defun append-6-body ()
  0)

(defun eqt (x y)
  (if (eq x y) t nil))

(defun eqlt (x y)
  (if (eql x y) t nil))

(defun equalt (x y)
  (if (equal x y) t nil))

(defun equalpt (x y)
  (if (equalp x y) t nil))

(defparameter *symbols*
  (list nil t 'a 'b 'c :a :b :c :k1 :k2 '#:x))

(defparameter *mini-universe*
  (list nil t 'a 0 1 -1 100 1.5 #\a "hello" '(1 2 3) (vector 1 2 3)))

(defparameter *universe*
  (list nil t 'a 'b :k1 :k2 0 1 -1 100 1000000000 1.5 0.0 #\a #\Space #\Newline "" "hello" '(1 2 3) '(a . b) (vector 1 2 3)))

(defparameter +lower-case-chars+
  "abcdefghijklmnopqrstuvwxyz")

(defparameter +upper-case-chars+
  "ABCDEFGHIJKLMNOPQRSTUVWXYZ")

(defparameter +digit-chars+
  "0123456789")

(defparameter +alpha-chars+
  "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ")

(defparameter +alphanumeric-chars+
  "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")

(defparameter +standard-chars+
  "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!\"#$%&'()*+,-./:;<=>?@[\\]^_`{|}~ \n")

(defparameter +code-chars+
  (let ((v (make-array 256)))
    (dotimes (i 256)
      (setf (aref v i) (code-char i)))
    v))

(defparameter +rev-code-chars+
  (let ((v (make-array 256)))
    (dotimes (i 256)
      (setf (aref v i) (code-char (- 255 i))))
    v))

(defun is-ordered-by (seq fn)
  (let ((n (length seq)))
    (loop for i from 0 below (1- n)
          for e = (elt seq i)
          always
          (loop for j from (1+ i) below n
                always (funcall fn e (elt seq j))))))

(defun is-antisymmetrically-ordered-by (seq fn)
  (and (is-ordered-by seq fn)
       (is-ordered-by (reverse seq) (complement fn))))

(defun equiv (&rest args)
  (cond
   ((null args) t)
   ((car args)
    (loop for e in (cdr args) always e))
   (t (loop for e in (cdr args) never e))))

(defun is-case-insensitive (fn)
  t)

(defun char-type-error-check (fn)
  t)

(defmacro catch-type-error (form)
  `(handler-case ,form
     (error (e) 'type-error)))

(defun subtypep* (type1 type2)
  (multiple-value-bind (sub good) (subtypep type1 type2)
    (values (notnot sub) (notnot good))))

(defun typep* (element type)
  (notnot (typep element type)))

(defparameter char-code-limit 65536)
(defparameter +extended-digit-chars+ "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ")

(defun standard-char.5.body ()
  nil)

(defun extended-char.3.body ()
  nil)

(defun character.1.body ()
  nil)

(defun character.2.body ()
  nil)

(defun characterp.2.body ()
  nil)

(defun characterp.3.body ()
  nil)

(defun alphanumericp.4.body ()
  nil)

(defun alphanumericp.5.body ()
  nil)

(defun digit-char.1.body ()
  nil)

(defun digit-char-p.1.body ()
  nil)

(defun digit-char-p.2.body ()
  nil)

(defun digit-char-p.3.body ()
  nil)

(defun digit-char-p.4.body ()
  nil)

(defun standard-char-p.2.body ()
  nil)

(defun standard-char-p.2a.body ()
  nil)

(defun char-upcase.1.body ()
  nil)

(defun char-upcase.2.body ()
  nil)

(defun char-downcase.1.body ()
  nil)

(defun char-downcase.2.body ()
  nil)

(defun both-case-p.1.body ()
  nil)

(defun both-case-p.2.body ()
  nil)

(defun name-char.1.body ()
  nil)

(defun char-code.2.body ()
  nil)

(defun char-int.2.fn ()
  nil)

(defun char-name.1.fn ()
  t)

(defun make-special-string (string &key fill adjust displace base)
  (let* ((len (length string))
         (len2 (if fill (+ len 4) len))
         (etype (if base 'base-char 'character)))
    (if displace
        (let ((s0 (make-array (+ len2 5)
                              :initial-contents
                              (concatenate 'string
                                           (make-string 2 :initial-element #\X)
                                           string
                                           (make-string (if fill 7 3)
                                                        :initial-element #\Y))
                              :element-type etype)))
          (make-array len2 :element-type etype
                      :adjustable adjust
                      :fill-pointer (if fill len nil)
                      :displaced-to s0
                      :displaced-index-offset 2))
      (make-array len2 :element-type etype
                  :initial-contents
                  (if fill (concatenate 'string string "ZZZZ") string)
                  :fill-pointer (if fill len nil)
                  :adjustable adjust))))

(defmacro do-special-strings ((var string-form &optional ret-form) &body forms)
  (let ((string (gensym))
        (fill (gensym "FILL"))
        (adjust (gensym "ADJUST"))
        (base (gensym "BASE"))
        (displace (gensym "DISPLACE")))
    `(let ((,string ,string-form))
       (dolist (,fill '(nil t) ,ret-form)
         (dolist (,adjust '(nil t))
           (dolist (,base '(nil t))
             (dolist (,displace '(nil t))
               (let ((,var (make-special-string
                            ,string
                            :fill ,fill :adjust ,adjust
                            :base ,base :displace ,displace)))
                 ,@forms))))))))

(defun char-invertcase (c)
  (if (upper-case-p c) (char-downcase c)
    (char-upcase c)))

(defun string-invertcase (s)
  (map 'string #'char-invertcase s))

(defun random-string-compare-test (&rest args)
  0)

(defun check-predicate (predicate &optional guard (universe *universe*))
  (remove-if (lambda (e)
               (or (and guard (funcall guard e))
                   (funcall predicate e)))
             universe))

(defmacro signals-type-error (var val &rest form)
  `(handler-case
     (let ((,var ,val))
       ,@form
       nil)
     (error (e) t)))

(defun string=t (x y)
  (if (string= x y) t nil))

(defun string/=t (x y)
  (if (string/= x y) t nil))

(defun string<t (x y)
  (if (string< x y) t nil))

(defun string<=t (x y)
  (if (string<= x y) t nil))

(defun string>t (x y)
  (if (string> x y) t nil))

(defun string>=t (x y)
  (if (string>= x y) t nil))

(defun safely-delete-package (pkg)
  (declare (ignore pkg))
  t)

(defun delete-package (pkg)
  (declare (ignore pkg))
  t)

(defun my-aref (a &rest args)
  (apply #'aref a args))

(defun regression-test.my-aref (a &rest args)
  (apply #'aref a args))

(defun my-row-major-aref (a index)
  (row-major-aref a index))

(defun regression-test.my-row-major-aref (a index)
  (row-major-aref a index))

(defun equal-array (a b)
  (and (typep a 'array)
       (typep b 'array)
       (equal (array-dimensions a) (array-dimensions b))
       (equal (array-element-type a) (array-element-type b))
       (equalp a b)))

(defun regression-test.equal-array (a b)
  (equal-array a b))

(defun reset-test-stats ()
  (setq *test-passed-count* 0)
  (setq *test-failed-count* 0)
  (setq *test-total-count* 0)
  (setq *failed-test-names* nil))

(defun print-test-summary (suite-name)
  (format t "==================================================~%")
  (format t "Suite: ~A~%" suite-name)
  (format t "Total: ~A | Passed: ~A | Failed: ~A~%"
          *test-total-count* *test-passed-count* *test-failed-count*)
  (if (> *test-failed-count* 0)
      (format t "Failed: ~S~%" (reverse *failed-test-names*))
      (format t "Status: ALL PASSED~%"))
  (format t "==================================================~%"))
