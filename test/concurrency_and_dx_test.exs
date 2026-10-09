defmodule ConcurrencyAndDxTest do
  use ExUnit.Case
  import ExUnit.CaptureIO

  setup do
    ExLisp.Env.reset()
    :ok
  end

  describe "BEAM/OTP concurrency primitives" do
    test "self and pidp" do
      res = ExLisp.eval("(self)")
      assert is_pid(res)
      assert res == self()
      assert ExLisp.eval("(pidp (self))") == :t
      assert ExLisp.eval("(pidp 123)") == nil
      assert ExLisp.eval("(pidp \"foo\")") == nil
    end

    test "spawn, send, and receive" do
      code = """
      (let ((parent (self)))
        (spawn (lambda ()
                 (send parent 42)))
        (receive))
      """
      assert ExLisp.eval(code) == 42
    end

    test "! as alias for send" do
      code = """
      (let ((parent (self)))
        (spawn (lambda ()
                 (! parent :hello)))
        (receive))
      """
      assert ExLisp.eval(code) == :hello
    end

    test "receive with timeout" do
      assert ExLisp.eval("(receive 10 :timed_out)") == :timed_out
    end

    test "process-alive-p and alivep" do
      assert ExLisp.eval("(process-alive-p (self))") == :t
      assert ExLisp.eval("(alivep (self))") == :t

      code = """
      (let ((p (spawn (lambda () (sleep 0.05)))))
        (list (process-alive-p p) (alivep p)))
      """
      assert ExLisp.eval(code) == [:t, :t]
    end

    test "sleep" do
      start = :erlang.monotonic_time(:millisecond)
      ExLisp.eval("(sleep 0.02)")
      elapsed = :erlang.monotonic_time(:millisecond) - start
      assert elapsed >= 15
    end
  end

  describe "REPL / DX features" do
    test "defun with docstring and documentation function" do
      ExLisp.eval("""
      (defun add-two (x)
        "Adds two to a number."
        (+ x 2))
      """)

      assert ExLisp.eval("(add-two 5)") == 7
      assert ExLisp.eval("(documentation 'add-two 'function)") == "Adds two to a number."
    end

    test "defvar and defparameter with docstring" do
      ExLisp.eval(~s{(defvar *my-var* 100 "Global configuration counter.")})
      assert ExLisp.eval("*my-var*") == 100
      assert ExLisp.eval("(documentation '*my-var* 'variable)") == "Global configuration counter."

      ExLisp.eval(~s{(defparameter *my-param* 200 "Parameter doc.")})
      assert ExLisp.eval("*my-param*") == 200
      assert ExLisp.eval("(documentation '*my-param* 'variable)") == "Parameter doc."
    end

    test "setf documentation" do
      ExLisp.eval("(defun helper (x) x)")
      ExLisp.eval(~s{(setf (documentation 'helper 'function) "Custom helper doc")})
      assert ExLisp.eval("(documentation 'helper 'function)") == "Custom helper doc"
    end

    test "apropos and apropos-list" do
      ExLisp.eval(~s{(defun find-my-unique-test-fn (x) "Unique doc" x)})
      list = ExLisp.eval(~s{(apropos-list "unique-test")})
      assert is_list(list)
      assert :find_my_unique_test_fn in list or :"find-my-unique-test-fn" in list

      output = capture_io(fn ->
        ExLisp.eval(~s{(apropos "unique-test")})
      end)
      assert output =~ "FIND-MY-UNIQUE-TEST-FN"
    end

    test "describe" do
      output = capture_io(fn ->
        ExLisp.eval("(describe 42)")
      end)
      assert output =~ "Integer: 42"

      output2 = capture_io(fn ->
        ExLisp.eval(~s{(describe "hello")})
      end)
      assert output2 =~ "String: \"hello\""
    end

    test "room" do
      output = capture_io(fn ->
        ExLisp.eval("(room)")
      end)
      assert output =~ "Memory usage:"
      assert output =~ "Processes:"
    end

    test "time special form" do
      output = capture_io(fn ->
        res = ExLisp.eval("(time (+ 10 20))")
        assert res == 30
      end)
      assert output =~ "Evaluation took:"
      assert output =~ "seconds of real time"
    end
  end
end
