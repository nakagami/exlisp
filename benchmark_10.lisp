;;; 10 Micro-benchmarks for Common Lisp / ExLisp

;; 1. Fibonacci (Recursive function calls)
(defun fib (n)
  (if (<= n 1)
      n
      (+ (fib (- n 1)) (fib (- n 2)))))

;; 2. Takeuchi (TAK) benchmark (Heavy recursion)
(defun tak (x y z)
  (if (<= x y)
      z
      (tak (tak (- x 1) y z)
           (tak (- y 1) z x)
           (tak (- z 1) x y))))

;; 3. Ackermann function
(defun ackermann (m n)
  (cond ((= m 0) (+ n 1))
        ((= n 0) (ackermann (- m 1) 1))
        (t (ackermann (- m 1) (ackermann m (- n 1))))))

;; 4. Sum with dotimes (Integer loop with accumulator)
(defun sum-loop (n)
  (let ((s 0))
    (dotimes (i n s)
      (setq s (+ s i)))))

;; 5. Sum with dolist (List traversal & iteration)
(defun sum-dolist (lst)
  (let ((s 0))
    (dolist (x lst s)
      (setq s (+ s x)))))

;; 6. List creation and reverse
(defun make-num-list (n)
  (let ((lst nil))
    (dotimes (i n lst)
      (setq lst (cons i lst)))))

(defun list-reverse-bench (n)
  (let ((lst (make-num-list n)))
    (length (reverse lst))))

;; 7. Mapcar with lambda
(defun mapcar-bench (lst)
  (length (mapcar (lambda (x) (+ x 1)) lst)))

;; 8. Bignum Factorial
(defun bignum-fact (n)
  (let ((acc 1))
    (dotimes (i n acc)
      (setq acc (* acc (+ i 1))))))

;; 9. Sieve of Eratosthenes (Array / Bit / Vector mutation)
(defun sieve-primes (limit)
  (let ((primes (make-array limit :initial-element t))
        (count 0))
    (setf (aref primes 0) nil)
    (setf (aref primes 1) nil)
    (dotimes (i limit)
      (when (aref primes i)
        (setq count (+ count 1))
        (let ((j (* i 2)))
          (tagbody
           loop
             (when (< j limit)
               (setf (aref primes j) nil)
               (setq j (+ j i))
               (go loop))))))
    count))

;; 10. Vector / Array read (svref / aref traversal)
(defun array-sum-bench (n)
  (let ((arr (make-array n :initial-element 1))
        (s 0))
    (dotimes (i n s)
      (setq s (+ s (aref arr i))))))

;; --- Benchmark Runner ---
(defun run-bench (name fn)
  (let ((t0 (get-internal-real-time)))
    (let ((res (funcall fn)))
      (let ((t1 (get-internal-real-time)))
        (let ((elapsed-ms (/ (* (- t1 t0) 1000.0) internal-time-units-per-second)))
          (format t "[~A] result: ~A (~F ms)~%" name res elapsed-ms))))))

(format t "=================== Benchmark Suite (10 Tests) ===================~%")
(run-bench "1. fib(34)" (lambda () (fib 34)))
(run-bench "2. tak(22,14,8)" (lambda () (tak 22 14 8)))
(run-bench "3. ackermann(3,10)" (lambda () (ackermann 3 10)))
(run-bench "4. sum-loop(10,000,000)" (lambda () (sum-loop 10000000)))

(let ((lst1m (make-num-list 1000000))
      (lst500k (make-num-list 500000)))
  (run-bench "5. sum-dolist(1,000,000)" (lambda () (sum-dolist lst1m)))
  (run-bench "6. list-reverse(1,000,000)" (lambda () (list-reverse-bench 1000000)))
  (run-bench "7. mapcar(500,000)" (lambda () (mapcar-bench lst500k))))

(run-bench "8. bignum-fact(10,000)" (lambda () (integer-length (bignum-fact 10000))))
(run-bench "9. sieve-primes(500,000)" (lambda () (sieve-primes 500000)))
(run-bench "10. array-sum(1,000,000)" (lambda () (array-sum-bench 1000000)))
(format t "==================================================================~%")
