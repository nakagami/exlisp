defmodule ConditionRestartTest do
  use ExUnit.Case

  describe "Condition & Restart System" do
    test "restart-case and invoke-restart" do
      code = """
      (restart-case
        (error "something failed")
        (return-zero () 0)
        (use-value (v) v))
      """
      # When error is raised without handler, it throws
      assert_raise RuntimeError, fn ->
        ExLisp.eval(code)
      end
    end

    test "handler-bind with invoke-restart" do
      code = """
      (handler-bind ((error (lambda (c)
                              (invoke-restart 'use-value 42))))
        (restart-case
          (error "failed")
          (use-value (v) v)
          (abort () :aborted)))
      """
      assert ExLisp.eval(code) == 42
    end

    test "handler-bind with standard restart use-value / store-value" do
      code = """
      (handler-bind ((error (lambda (c)
                              (use-value 100))))
        (restart-case
          (error "failed")
          (use-value (v) (* v 2))))
      """
      assert ExLisp.eval(code) == 200
    end

    test "find-restart and compute-restarts" do
      code = """
      (restart-case
        (let ((r-names (mapcar #'restart-name (compute-restarts))))
          (list (not (null (find-restart 'my-restart)))
                (not (null (member 'my-restart r-names)))))
        (my-restart () :done))
      """
      assert ExLisp.eval(code) == [:t, :t]
    end

    test "with-simple-restart normal execution" do
      code = """
      (with-simple-restart (skip-calc "Skip calculating")
        (+ 10 20))
      """
      assert ExLisp.eval(code) == 30
    end

    test "with-simple-restart invoked returns nil and t" do
      code = """
      (handler-bind ((error (lambda (c)
                              (invoke-restart 'skip-calc))))
        (with-simple-restart (skip-calc "Skip calculating")
          (error "an error occurred")))
      """
      assert ExLisp.eval(code) == nil
    end

    test "define-condition and make-condition inheritance" do
      ExLisp.eval("""
      (define-condition my-custom-error (error)
        ((code :initarg :code :reader my-custom-error-code))
        (:report (lambda (c stream)
                   (format stream "Custom error with code ~A" (my-custom-error-code c)))))
      """)

      code = """
      (handler-case
        (error 'my-custom-error :code 404)
        (my-custom-error (c)
          (my-custom-error-code c)))
      """
      assert ExLisp.eval(code) == 404
    end

    test "cerror continuable error" do
      code = """
      (handler-bind ((error (lambda (c)
                              (continue))))
        (cerror "Continue past this error" "A continuable error")
        :resumed)
      """
      assert ExLisp.eval(code) == :resumed
    end

    test "warn and muffle-warning" do
      code = """
      (handler-bind ((warning (lambda (w)
                                (muffle-warning))))
        (warn "This is a warning")
        :warning-muffled)
      """
      assert ExLisp.eval(code) == :warning_muffled
    end
  end
end
