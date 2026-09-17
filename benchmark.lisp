(defun fib (n)
  (if (<= n 1)
      n
      (+ (fib (- n 1)) (fib (- n 2)))))

(defun sum-loop (n)
  (let ((s 0))
    (dotimes (i n s)
      (setq s (+ s i)))))

(defun list-test (n)
  (let ((lst nil))
    (dotimes (i n (length lst))
      (setq lst (cons i lst)))))

(defun run-bench (name fn)
  (let ((t0 (get-internal-real-time)))
    (let ((res (funcall fn)))
      (let ((t1 (get-internal-real-time)))
        (let ((elapsed-ms (/ (* (- t1 t0) 1000.0) internal-time-units-per-second)))
          (format t "[~A] result: ~A (~F ms)~%" name res elapsed-ms))))))

(format t "===== Benchmark Start =====~%")
(run-bench "fib(30)" (lambda () (fib 30)))
(run-bench "sum-loop(1,000,000)" (lambda () (sum-loop 1000000)))
(run-bench "list-test(500,000)" (lambda () (list-test 500000)))
(format t "===== Benchmark End =====~%")
