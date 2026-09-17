;;;; =========================================================================
;;;; utils.lisp - Utilities and Formatting
;;;; =========================================================================

(in-package #:calculator)

(defun format-result (operation a b result)
  (format nil "~a ~a ~a = ~a" a operation b result))

(defun print-header (title)
  (format t "~%=== ~a ===~%" title))
