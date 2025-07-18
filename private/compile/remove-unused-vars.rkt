#lang racket/base

(require syntax/parse
         syntax-spec-v2/private/ee-lib/main
         (only-in racket/sequence in-syntax)
         (for-template racket/base "../forms.rkt")
         (only-in "prop-vars.rkt" TERM-VARS-IN-SCOPE)
         "../syntax-classes.rkt"
         syntax/id-set)

(provide remove-unused-vars/entry)

(define (remove-unused-vars/entry g fvs fvs-fresh?)
  (let-values ([(g^ _) (remove-unused-vars g fvs)])
    g^))

;; produce a new goal where only referenced logic variables get freshened
;; and a set of referenced free identifiers.
;; EFFECT annotates goal from expression form w/syntax property listing vars in scope at that expression
;; (goal? [Listof identifier] -> (values goal? immutable-bound-id-set?))
(define (remove-unused-vars g vars-in-scope)
  (syntax-parse g
    #:literal-sets (mk-literals)
    [c:primitive-goal (values this-syntax (immutable-bound-id-set))]
    [(c:unary-constraint t) (values this-syntax (term-refs #'t vars-in-scope))]
    [(c:binary-constraint t1 t2)
     (values this-syntax (bound-id-set-union (term-refs #'t1 vars-in-scope)
                                            (term-refs #'t2 vars-in-scope)))]
    [(disj g ...)
     (define-values (g^ g-refs)
       (for/lists (g^ g-refs)
                  ([g (attribute g)])
         (remove-unused-vars g vars-in-scope)))
     (values #`(disj . #,g^) (apply bound-id-set-union g-refs))]
    [(conj g1 g2)
     (let-values ([(g1^ g1-refs) (remove-unused-vars #'g1 vars-in-scope)]
                  [(g2^ g2-refs) (remove-unused-vars #'g2 vars-in-scope)])
       (values #`(conj #,g1^ #,g2^) (bound-id-set-union g1-refs g2-refs)))]
    [(fresh (x ...) g)
     (let-values ([(g^ g-refs) (remove-unused-vars #'g (append (attribute x) vars-in-scope))])
       (define vars-to-keep (filter (λ (lv) (bound-id-set-member? g-refs lv)) (syntax->list #'(x ...))))
       (define free-refs (bound-id-set-subtract g-refs (immutable-bound-id-set vars-to-keep)))
       (values #`(fresh (#,@vars-to-keep) #,g^) free-refs))]
    [(#%rel-app n t ...)
     (values this-syntax
             (for/fold ([var-refs (immutable-bound-id-set)])
                       ([t (in-syntax #'(t ...))])
               (bound-id-set-union var-refs (term-refs t vars-in-scope))))]
    [(goal-from-expression e)
     (values (syntax-property this-syntax TERM-VARS-IN-SCOPE (map flip-intro-scope vars-in-scope)) (immutable-bound-id-set vars-in-scope))]
    [(apply-relation e t ...)
     (values this-syntax
             (for/fold ([var-refs (immutable-bound-id-set)])
                       ([t (in-syntax #'(t ...))])
               (bound-id-set-union var-refs (term-refs t vars-in-scope))))]))

(define (term-refs t vars-in-scope)
  (syntax-parse t #:literal-sets (mk-literals) #:literals (cons quote)
    [(#%lv-ref v)
     (immutable-bound-id-set (list #'v))]
    [(term-from-expression _) (immutable-bound-id-set vars-in-scope)]
    [(quote _) (immutable-bound-id-set)]
    [(cons t1 t2)
     (bound-id-set-union (term-refs #'t1 vars-in-scope) (term-refs #'t2 vars-in-scope))]))

(module* test racket/base
  (require "./test/unit-test-progs.rkt"
           "../forms.rkt"
           (except-in rackunit fail)
           (for-syntax racket/base
                       syntax/parse
                       "./test/unit-test-progs.rkt"
                       (submod "..")))

  (begin-for-syntax
    (define (remove-unused-vars/rel stx)
      (syntax-parse stx
        [(ir-rel (x ...) g)
         #`(ir-rel (x ...) #,(remove-unused-vars/entry #'g (attribute x) #f))])))

  (progs-equal?
    (remove-unused-vars/rel
      (generate-prog
        (ir-rel ((~binders a))
          (fresh ((~binders x y))
            (== (#%lv-ref x) (#%lv-ref a))))))
    (generate-prog
      (ir-rel ((~binders a))
        (fresh ((~binders x))
          (== (#%lv-ref x) (#%lv-ref a))))))

;; When there's a goal from expression; we must assume that every
;; variable is refrered to from within that expression.
  (progs-equal?
    (remove-unused-vars/rel
      (generate-prog
        (ir-rel ((~binders a))
          (fresh ((~binders x y))
            (conj
              ;; This isn't a valid program ofc; just compiler pass test
              (goal-from-expression #t)
              (== (#%lv-ref x) (#%lv-ref a)))))))
    (generate-prog
      (ir-rel ((~binders a))
        (fresh ((~binders x y))
          (conj
            ;; This isn't a valid program ofc; just compiler pass test
            (goal-from-expression #t)
            (== (#%lv-ref x) (#%lv-ref a)))))))

  (progs-equal?
    (remove-unused-vars/rel
      (generate-prog
        (ir-rel ()
          (fresh ((~binder a))
            (== (#%lv-ref a) (quote 5))))))
    (generate-prog
      (ir-rel ()
        (fresh ((~binder a))
          (== (#%lv-ref a) (quote 5))))))

  (progs-equal?
    (remove-unused-vars/rel
      (generate-prog
        (ir-rel ()
          (disj
            (fresh ((~binder x))
              (== (#%lv-ref x) (#%lv-ref x)))
            (fresh ((~binder y))
              (== (quote 5) (quote 6)))))))

    (generate-prog
      (ir-rel ()
        (disj
          (fresh ((~binder x))
            (== (#%lv-ref x) (#%lv-ref x)))
          (fresh ()
            (== (quote 5) (quote 6)))))))

  (progs-equal?
    (remove-unused-vars/rel
      (generate-prog
        (ir-rel ((~binder q))
          (fresh ((~binder x))
            (fresh ((~binder y))
              (conj
                (== (#%lv-ref x) (quote 5))
                (fresh ((~binder z))
                  (== (#%lv-ref z) (#%lv-ref y)))))))))
    (generate-prog
      (ir-rel ((~binder q))
        (fresh ((~binder x))
              (fresh ((~binder y))
                (conj
                  (== (#%lv-ref x) (quote 5))
                  (fresh ((~binder z))
                    (== (#%lv-ref z) (#%lv-ref y)))))))))



(progs-equal?
 (remove-unused-vars/rel
   (with-syntax ([a1 ((make-syntax-introducer) #'a)]
                 [a2 ((make-syntax-introducer) #'a)]
                 [b ((make-syntax-introducer) #'b)])
     (with-syntax ([a1b (syntax-property #'a1 'binder #t)]
                   [a2b (syntax-property #'a2 'binder #t)]
                   [bb (syntax-property #'b 'binder #t)])
       #'(ir-rel (bb)
           (fresh (a1b a2b)
             (== (#%lv-ref a1) (cons (#%lv-ref b) '())))))))
  (generate-prog
    (ir-rel ((~binder b))
      (fresh ((~binder a1))
        (== (#%lv-ref a1) (cons (#%lv-ref b) '()))))))



  )
