#lang racket
(require (except-in rackunit fail))
(require "./demo-compiler.rkt")

(check-equal?
 (run 1 (x) (== x x))
 '(_.0))

(check-equal?
 (run 1 (q) (== q 'cat))
 '(cat))

(defrel (foo x y z)
  (== x y))

(check-equal?
 (run 1 (p q r) (foo p q r))
 '((_.0 _.0 _.1)))

(check-equal? 
 (run 1 (q) (absento 'cat q))
 '((_.0 (absento (cat _.0)))))

(check-equal?
 (run 1 (q) (== q (term-from-expression 'cat)))
 '(cat))

(check-equal?
 (run 1 (q) (== q (term-from-expression (expression-from-term 'cat))))
 '(cat))

(check-equal?
 (run 1 (q) (== q (term-from-expression (expression-from-term q))))
 '(_.0))

(test-equal?
 "The `expression-from-term` isn't necessary here b/c with-reference-compilers puts it for us"
 (run 1 (q) (== q (term-from-expression q)))
 '(_.0))

(check-equal?
 (run 1 (q) (goal-from-expression (expression-from-goal succeed)))
 '(_.0))

(test-exn
 "goal-from-expression only accepts sealed goal values produced by expression-from-goal"
 #rx"expected: mk-goal?"
 (λ ()
   (run 1 (q)
     (goal-from-expression
      (λ (st) st)))))

(test-equal?
 "expression-from-goal produces sealed goal values"
 (with-output-to-string
   (λ ()
     (displayln
      (run 1 (q)
        (goal-from-expression
         (let ()
           (printf "this is a goal: ~s:\n" (expression-from-goal succeed))
           (expression-from-goal succeed)))))))
 "this is a goal: #<mk-goal>:\n(_.0)\n")

(test-equal?
 "expression-from-term translates term values and seals logic variables"
 (with-output-to-string
   (λ ()
     (displayln
      (run 1 (q)
        (fresh (x)
          (== q (list x x))
          (goal-from-expression
           (let ()
             (printf "q is ~s:\n" (expression-from-term q))
             (expression-from-goal succeed))))))))
 "q is (#<mk-lvar> #<mk-lvar>):\n((_.0 _.0))\n")

(test-equal? "The list macro expands correctly"
 (test-goal-syntax (fresh (y) (absento (list 'cat 'cat 'cat) y)))
 '(fresh1 (y)
    (conj (absento
            (cons
             (core-quote cat)
             (cons (core-quote cat) (cons (core-quote cat) (core-quote ()))))
            y))))

(test-equal? "Quasiquote and comma work"
 (test-goal-syntax (fresh (y) (absento `(,y fish) y)))
 '(fresh1 (y)
    (conj (absento (cons y (cons (core-quote fish) (core-quote ()))) y))))

(test-equal? "Conj is included for a single goal"
 (test-goal-syntax (fresh (x y) (== y x)))
 '(fresh1 (x y) (conj (== y x))))

(check-equal? 
 (test-goal-syntax (fresh (y) (foo 'cat 'cat y)))
 '(fresh1 (y) (conj (foo (core-quote cat) (core-quote cat) y))))
