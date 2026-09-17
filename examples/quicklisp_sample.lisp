;;;; =========================================================================
;;;; Sample Usage of Quicklisp Libraries (Pure Common Lisp)
;;;;
;;;; How to run:
;;;;   exlisp --script examples/quicklisp_sample.lisp
;;;; =========================================================================

(format t "=== 1. Loading Alexandria ===~%")
(ql:quickload :alexandria)

(format t "~%--- Testing Alexandria functions ---~%")
;; clamp: Clamp value within the specified [min, max] range
(format t "clamp(15, 0, 10)  => ~a~%" (clamp 15 0 10))
(format t "clamp(-5, 0, 10)  => ~a~%" (clamp -5 0 10))
(format t "clamp(7, 0, 10)   => ~a~%" (clamp 7 0 10))

;; flatten: Flatten nested list
(format t "flatten('((1 2) (3 (4 5)))) => ~a~%" (flatten '((1 2) (3 (4 5)))))

;; iota: Generate sequence of numbers
(format t "iota(5, start=1, step=2)   => ~a~%" (iota 5 :start 1 :step 2))


(format t "~%=== 2. Loading split-sequence ===~%")
(ql:quickload :split-sequence)

(format t "~%--- Testing split-sequence functions ---~%")
;; Split string by space
(format t "split-sequence by space => ~s~%"
        (split-sequence #\Space "Common Lisp running on BEAM"))

;; Split string by comma
(format t "split-sequence by comma => ~s~%"
        (split-sequence #\, "apple,banana,cherry,orange"))

(format t "~%=== Sample script finished ===~%")
