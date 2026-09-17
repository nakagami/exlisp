;;;; =========================================================================
;;;; run.lisp - Runner Script for Calculator ASDF Project
;;;;
;;;; How to run:
;;;;   ./exlisp --script examples/calculator/run.lisp
;;;; =========================================================================

;; Load ASDF system
(asdf:load-system :calculator)

;; Run demo
(in-package #:calculator)
(run-demo)
