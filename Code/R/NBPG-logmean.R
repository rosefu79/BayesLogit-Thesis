
################################################################################
                             ## When Modeling MU ##
################################################################################

df.llh <- function(d, mu, G, ymax)
{
  p =  1 / (1 + d / mu)
  sum( log(d+0:(ymax-1)) * G[1:ymax] ) + d * sum(log(1-p)) + sum(y * log(p)) ;
}

draw.df <- function(d.prev, mu, G, ymax)
{
  ## optim.out <- optim(d.prev, fn=df.llh, gr = NULL,
  ##                    mu, G, ymax,                              ## for minimization
  ##                    method="L-BFGS-B", lower=1, hessian=TRUE, control=list(fnscale=-1));
  
  ## mle = optim.out$par
  ## fim = -1 / optim.out$hessian

  ## cat("d.prev:", d.prev, "mle:", mle, "fim:", fim, "\n");

  d.new = d.prev
  
  ## Mixture of MH kernels.
  ## w = c(0.5, 0.5);
  ## k = sample.int(2, 1, prob=w);
  k = 1
  
  if (k==1) {
    ## Kernel 1: RW MH.
    rw.lower = max(d.prev - 1, 1);
    rw.upper = d.prev + 1;
    rw.grid  = rw.lower:rw.upper;
    rw.n     = length(rw.grid)
    rw.p     = rep(1/rw.n, rw.n);
    
    d.prop = sample(rw.grid, 1, prob=rw.p);
    
    ltarget = df.llh(d.prop, mu, G, ymax) - df.llh(d.prev, mu, G, ymax)
    lppsl = log(ifelse(d.prop==1, 1/2, 1/3)) - log(ifelse(d.prev==1, 1/2, 1/3));
    lratio = ltarget + lppsl
    
    if (runif(1) < exp(lratio)) d.new = d.prop
  }

  if (k==2) {
    ## Kernel 2: Ind MH.
    d.m = max(1, mle);
    d.prop = rpois(1, d.m);

    if (d.prop==0) return(d.prev);
    
    p.prop = 1 / (1 + d.prop / mu)
    p.prev = 1 / (1 + d.prev / mu)
    ltarget = df.llh(d.prop, mu, G, ymax) - df.llh(d.prev, mu, G, ymax)
    lppsl   = dpois(d.prev, d.m, log=TRUE) - dpois(d.prop, d.m, log=TRUE)
    lratio  = ltarget + lppsl

    if (runif(1) < exp(lratio)) d.new = d.prop
  }
    
  d.new
}

################################################################################

draw.beta <- function(X, kappa, d, w, b.0=NULL, B.0=NULL, P.0=NULL)
{
  ## X: N x P design matrix.
  ## b.0: prior mean for beta
  ## B.0: prior variance for beta
  ## P.0: prior precision for beta.
  
  N = nrow(X);
  P = ncol(X);

  if (is.null(b.0)) b.0 = rep(0.0, P);
  if (is.null(P.0)) P.0 = matrix(0.0, P, P);
  if (!is.null(B.0)) P.0 = solve(B.0);

  P.N = t(X) %*% (X * w) + P.0;
  a.L = t(X) %*% (kappa + w * log(d));
  ## S = solve(PC); ## chol2inv works better for larger P?
  S = chol2inv(chol(P.N));
  m = S %*% (a.L + P.0 %*% b.0);
  beta = m + t(chol(S)) %*% rnorm(P);

} ## draw.beta

NB.PG.gibbs <- function(y, X,
                        b.0=NULL, B.0 = NULL, P.0 = NULL,
                        samp=1000, burn=500, verbose=500,
                        beta.true = NULL, w.true = NULL, d.true=NULL)
{
  ## X: n by p matrix
  ## y: n by 1 vector, counts.

  X = as.matrix(X);
  y = as.matrix(y);
  
  P = ncol(X)
  N = nrow(X)
  
  ## Default prior parameters.
  if (is.null(b.0)) b.0 = rep(0.0, P);
  if (is.null(P.0)) P.0 = matrix(0.0, P, P);
  if (!is.null(B.0)) P.0 = solve(B.0);
  
  ## Initialize.
  beta = rep(0.0, P)
  d = 1;

  ## Set known.
  if (!is.null(beta.true)) beta = beta.true;
  if (!is.null(w.true))    w    = w.true;
  if (!is.null(d.true))    d    = d.true;

  ## Preprocess
  ymax = max(y);
  F = cumsum(hist(y, breaks=0:(ymax+1)-0.5, plot=FALSE)$counts)
  G = N - F;
  
  out <- list(w = matrix(nrow=samp, ncol=N),
                 beta = matrix(nrow=samp, ncol=P),
                 d = rep(0, samp)
                 )

  start.time = proc.time()
  
  ## Sample
  for ( j in 1:(samp+burn) )
  {
    if (j==burn+1) start.ess = proc.time()

    ## WARNING: JOINT DRAW.
    ## draw (d, w | beta)
    ## draw (d | beta)
    phi = drop(X%*%beta)
    mu  = exp(phi)
    d = draw.df(d, mu, G, ymax);
    ## draw (w | d, beta)
    psi = phi - log(d);
    w = rpg.devroye(N, y+d, psi);

    ## draw beta
    kappa = 0.5 * (y-d)
    beta = draw.beta(X, kappa, d, w, b.0=b.0, P.0=P.0);
    
    # Record if we are past burn-in.
    if (j>burn) {
        out$w[j-burn,]    = w
        out$beta[j-burn,] = beta
        out$d[j-burn]     = d
    }

    if (j %% verbose == 0) { print(paste("NBPG-logmean: Iteration", j)); }
  }

  end.time = proc.time()
  out$total.time = end.time - start.time
  out$ess.time   = end.time - start.ess
  
  out
} ## logit.PG.gibbs

################################################################################

if (FALSE) {

  library("BayesLogit")
  
  N = 500
  X = cbind(1, rnorm(N))

  beta = c(1.0, 1.5);

  ## Poisson-Gamma mixture.
  phi = X %*% beta;
  mu = exp(phi);
  d  = 3
  p  = (mu / (mu + d));
  alpha = p / (1-p)
  lambda = rgamma(N, d, scale=alpha);
  y = rpois(N, lambda);

  samp = 1000
  burn = 500
  verbose = 500
  
  out <- logit.PG.gibbs(y, X,
                        samp=samp, burn=burn, verbose=verbose,
                        beta.true = NULL, w.true = NULL, d.true=NULL)
  
}

