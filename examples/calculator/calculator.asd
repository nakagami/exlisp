;;;; =========================================================================
;;;; calculator.asd - ASDF System Definition
;;;; =========================================================================

(asdf:defsystem #:calculator
  :description "Sample multi-file Common Lisp project using ASDF"
  :version "0.1.0"
  :author "ExLisp Example"
  :license "MIT"
  :serial t
  :components ((:file "package")
               (:file "math")
               (:file "utils")
               (:file "main")))
