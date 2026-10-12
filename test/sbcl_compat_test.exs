defmodule ExLisp.SBCLCompatTest do
  use ExUnit.Case

  setup do
    ExLisp.Env.reset()
    :ok
  end

  describe "SB-THREAD threading primitives" do
    test "make-thread and join-thread" do
      result =
        ExLisp.eval("""
        (let ((th (sb-thread:make-thread (lambda () (+ 10 20)) :name "worker-1")))
          (sb-thread:join-thread th))
        """)

      assert result == 30
    end

    test "make-thread with arguments and thread properties" do
      result =
        ExLisp.eval("""
        (let ((th (sb-thread:make-thread (lambda (a b) (* a b)) :arguments '(6 7) :name "calc")))
          (list (sb-thread:thread-name th)
                (sb-thread:join-thread th)))
        """)

      assert result == ["calc", 42]
    end

    test "current-thread and list-all-threads" do
      result =
        ExLisp.eval("""
        (let ((cur (sb-thread:current-thread))
              (all (sb-thread:list-all-threads)))
          (list (sb-thread:thread-p cur)
                (> (length all) 0)))
        """)

      assert result == [:t, :t]
    end

    test "thread-alive-p and destroy-thread" do
      result =
        ExLisp.eval("""
        (let ((th (sb-thread:make-thread (lambda () (sleep 2) :done) :name "sleeper")))
          (let ((alive-before (sb-thread:thread-alive-p th)))
            (sb-thread:destroy-thread th)
            (sleep 0.05)
            (list alive-before (sb-thread:thread-alive-p th))))
        """)

      assert result == [:t, nil]
    end

    test "thread-yield" do
      assert ExLisp.eval("(sb-thread:thread-yield)") == :t
    end
  end

  describe "SB-THREAD mutex and with-mutex" do
    test "make-mutex, grab-mutex, release-mutex and mutex properties" do
      result =
        ExLisp.eval("""
        (let ((m (sb-thread:make-mutex :name "test-lock")))
          (let ((name (sb-thread:mutex-name m))
                (val-before (sb-thread:mutex-value m)))
            (sb-thread:grab-mutex m)
            (let ((val-held (sb-thread:mutex-value m)))
              (sb-thread:release-mutex m)
              (let ((val-after (sb-thread:mutex-value m)))
                (list name val-before (not (null val-held)) val-after)))))
        """)

      assert result == ["test-lock", nil, :t, nil]
    end

    test "with-mutex macro" do
      result =
        ExLisp.eval("""
        (let ((m (sb-thread:make-mutex :name "m1"))
              (x 100))
          (sb-thread:with-mutex (m)
            (setq x (+ x 50)))
          x)
        """)

      assert result == 150
    end

    test "with-mutex unwinds and releases mutex on error" do
      result =
        ExLisp.eval("""
        (let ((m (sb-thread:make-mutex :name "m2")))
          (ignore-errors
            (sb-thread:with-mutex (m)
              (error "something went wrong")))
          (sb-thread:mutex-value m))
        """)

      assert result == nil
    end
  end

  describe "SB-THREAD semaphore" do
    test "make-semaphore, wait-on-semaphore and signal-semaphore" do
      result =
        ExLisp.eval("""
        (let ((sem (sb-thread:make-semaphore :name "sem" :count 1)))
          (let ((w1 (sb-thread:wait-on-semaphore sem :timeout 0.1))
                (w2 (sb-thread:wait-on-semaphore sem :timeout 0.05)))
            (sb-thread:signal-semaphore sem 1)
            (let ((w3 (sb-thread:wait-on-semaphore sem :timeout 0.1)))
              (list w1 w2 w3))))
        """)

      assert result == [:t, nil, :t]
    end
  end

  describe "SB-EXT and SB-POSIX environment variables" do
    test "sb-ext:posix-getenv, sb-posix:setenv, sb-posix:unsetenv" do
      result =
        ExLisp.eval("""
        (progn
          (sb-posix:setenv "EXLISP_SBCL_TEST" "hello_sbcl" 1)
          (let ((val (sb-ext:posix-getenv "EXLISP_SBCL_TEST")))
            (sb-posix:unsetenv "EXLISP_SBCL_TEST")
            (let ((val-after (sb-posix:getenv "EXLISP_SBCL_TEST")))
              (list val val-after))))
        """)

      assert result == ["hello_sbcl", nil]
    end

    test "sb-ext:*posix-argv*" do
      result = ExLisp.eval("sb-ext:*posix-argv*")
      assert is_list(result)
      assert hd(result) == "exlisp"
    end
  end

  describe "SB-EXT process execution and system utilities" do
    test "sb-ext:run-program synchronous" do
      result =
        ExLisp.eval("""
        (let ((p (sb-ext:run-program "echo" '("hello") :wait t :search t)))
          (list (sb-ext:process-p p)
                (sb-ext:process-exit-code p)
                (sb-ext:process-alive-p p)))
        """)

      assert result == [:t, 0, nil]
    end

    test "sb-ext:get-time-of-day" do
      result = ExLisp.eval("(multiple-value-list (sb-ext:get-time-of-day))")
      assert is_list(result)
      assert length(result) == 2
      [sec, usec] = result
      assert is_integer(sec) and sec > 0
      assert is_integer(usec) and usec >= 0
    end

    test "sb-ext:gc and bytes-consed-between-gcs" do
      result =
        ExLisp.eval("""
        (list (sb-ext:gc)
              (sb-ext:bytes-consed-between-gcs))
        """)

      assert result == [nil, 12_582_912]
    end
  end

  describe "Package switching and symbol resolution" do
    test "in-package :sb-thread and unprefixed calls" do
      result =
        ExLisp.eval("""
        (progn
          (in-package :sb-thread)
          (let ((th (make-thread (lambda () 99))))
            (join-thread th)))
        """)

      assert result == 99
    end

    test "in-package :sb-ext" do
      result =
        ExLisp.eval("""
        (progn
          (in-package :sb-ext)
          (multiple-value-bind (sec usec) (get-time-of-day)
            (> sec 0)))
        """)

      assert result == :t
    end
  end
end
