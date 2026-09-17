;;;; =========================================================================
;;;; main.lisp - Entry Point and Orchestration
;;;; =========================================================================

(in-package #:calculator)

(defun calculate-and-print (op-sym a b)
  (let ((result (case op-sym
                  (:+ (add a b))
                  (:- (subtract a b))
                  (:* (multiply a b))
                  (:/ (divide a b))
                  (t (error "Unknown operator: ~a" op-sym)))))
    (format t "~a~%" (format-result op-sym a b result))
    result))

(defun run-demo ()
  (print-header "Calculator ASDF Multi-File Demo")
  (calculate-and-print :+ 10 20)
  (calculate-and-print :- 100 42)
  (calculate-and-print :* 6 7)
  (calculate-and-print :/ 50 5)
  (format t "~%All calculations completed successfully!~%")
  :t)
