;;;; =========================================================================
;;;; math.lisp - Arithmetic Operations
;;;; =========================================================================

(in-package #:calculator)

(defun add (a b)
  (+ a b))

(defun subtract (a b)
  (- a b))

(defun multiply (a b)
  (* a b))

(defun divide (a b)
  (if (zerop b)
      (error "Division by zero")
      (/ a b)))
