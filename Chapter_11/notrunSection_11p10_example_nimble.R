#---(begin AHMnimble header)---
# This file contains code adapted from the file R_BUGS_code_AHM_Vol_1_20170519.R
# available at https://www.mbr-pwrc.usgs.gov/pubanalysis/keryroylebook/, with
# permission of the authors.  It may have been modified so that examples originally
# written to work with JAGS or WinBUGS will work with NIMBLE.  More information
# about NIMBLE can be found at https://r-nimble.org, https://github.com/nimble-dev/nimble,
# and https://cran.r-project.org/web/packages/nimble/index.html.
#
# The file  R_BUGS_code_AHM_Vol_1_20170519.R contains the following header:
# -----(begin R_BUGS_code_AHM_Vol_1_20170519.R header)-----
# =========================================================================
#
#   Applied hierarchical modeling in ecology
#   Modeling distribution, abundance and species richness using R and BUGS
#   Volume 1: Prelude and Static models
#
#   Marc Kéry & J. Andy Royle
#
#   *** This is the text file with all R and BUGS code from the book ***
#
#   Created 2 Dec 2015 based on draft from 21 Oct 2015
#
# =========================================================================
### Last change: 19 May 2017 by Mike Meredith
# Incorporated errata up to 19 May 2017
# Code updated to implement new names and changes to functions in AHMbook package 0.1.4
# Use built-in data sets instead of .csv files
# In Chapter 11, replaced 'Y', 'Ysum' and 'Yaug' with lower case 'y', 'ysum' and 'yaug'
#  to match the code in the printed book.
#
# -----(end R_BUGS_code_AHM_Vol_1_20170519.R header)-----

# This file was created by:
#
# Jacob Levine and Perry de Valpine
#
#---(end AHMnimble header)---
# 11.10 Community N-mixture models
# ------------------------------------------------------------------------

# Organize counts in 3D array: site x rep x species
COUNTS <- data$counts  # Counts 2014
nsite <- 267                    # number of sites in Swiss MHB
nrep <- 3                       # number of replicate surveys per season
nspec <- length(species.list)   # 158 species occur in the 2014 data
Yc <- array(NA, dim = c(nsite, nrep, nspec))
for(i in 1:nspec){
  Yc[,,i] <- COUNTS[((i-1)*nsite+1):(i*nsite),]  # 'c' for counts
}

# Observed maximum and mean maximum count per species
tmp <- apply(Yc, c(1,3), max, na.rm = TRUE)
tmp[tmp == -Inf] <- NA         # 1 quadrat with NA data in 2014
sort(round(meanmax <- apply(tmp, 2, mean, na.rm = TRUE), 3)) # mean of max
sort(obs.max.C <- apply(tmp, 2, max, na.rm = TRUE))          # max

# Spatio-temporal patterns in counts (mean over sites)
tmp <- apply(Yc, c(2,3), mean, na.rm = TRUE)

# Drop data from 13 species not observed in 2014
toss.out <- which(obs.max.C == 0)   # list of species not seen
Yc <- Yc[,,-toss.out]               # toss them out
obs.max.C <- obs.max.C[-toss.out]
nspec <- dim(Yc)[3]                 # Redefine nspec as 145

# So here are our data
str(Yc)

# Bundle and summarize data set
str(win.data <- list(Yc = Yc, nsite = dim(Yc)[1], nrep = dim(Yc)[2], 
                     nspec = dim(Yc)[3], ele = elev, forest = sites$forest, DAT = dat, DUR = dur))


# Specify model in BUGS language
sink("model11.txt")
cat("
    model {
    
    # Community priors (with hyperparameters) for species-specific parameters
    for(k in 1:nspec){
    phi[k] ~ dunif(0,1)                              # Zero-inflation
    alpha0[k] ~ dnorm(mu.alpha0, tau.alpha0)         # Detection intercepts
    beta0[k] ~ dnorm(mu.beta0, tau.beta0)            # Abundance intercepts
    for(v in 1:3){
    alpha[k, v] ~ dnorm(mu.alpha[v], tau.alpha[v]) # Slopes detection
    beta[k, v] ~ dnorm(mu.beta[v], tau.beta[v])    # Slopes abundance
    }
    }
    
    # Hyperpriors for community hyperparameters
    # abundance model
    mu.beta0 ~ dunif(-1, 2)
    tau.beta0 <- pow(sd.beta0, -2)
    sd.beta0 ~ dunif(0, 3)
    for(v in 1:3){
    mu.beta[v] ~ dunif(-1.5, 1)
    tau.beta[v] <- pow(sd.beta[v], -2)
    }
    sd.beta[1] ~ dunif(0, 3)
    sd.beta[2] ~ dunif(0, 1.5)
    sd.beta[3] ~ dunif(0, 1)
    
    # detection model
    mu.alpha0 ~ dunif(-2, 0)
    tau.alpha0 <- pow(sd.alpha0, -2)
    sd.alpha0 ~ dunif(0, 2)
    for(v in 1:3){
    mu.alpha[v] ~ dunif(-0.5, 0.5)
    tau.alpha[v] <- pow(sd.alpha[v], -2)
    }
    sd.alpha[1] ~ dunif(0, 0.8)
    sd.alpha[2] ~ dunif(0, 0.5)
    sd.alpha[3] ~ dunif(0, 0.3)
    
    # Ecological model for true abundance (process model)
    for(k in 1:nspec){
    for (i in 1:nsite){
    a[i,k] ~ dbern(phi[k])   # zero-inflation
    N[i,k] ~ dpois(a[i,k] * lambda[i,k])
    log(lambda[i,k]) <- beta0[k] + beta[k,1] * ele[i] + 
    beta[k,2] * pow(ele[i],2) + beta[k,3] * forest[i]
    # Compute presence/absence matrix z (for N > 0) from latent abundance
    z[i,k] <- step(N[i,k]-1)  # returns TRUE if N >= 0
    }
    }
    
    # Observation model for replicated counts
    for(k in 1:nspec){
    for (i in 1:nsite){
    for (j in 1:nrep){
    Yc[i,j,k] ~ dbin(p[i,j,k], N[i,k])
    logit(p[i,j,k]) <- alpha0[k] + alpha[k,1] * DAT[i,j] + 
    alpha[k,2] * pow(DAT[i,j],2) + alpha[k,3] * DUR[i,j]
    }
    }
    }
    
    # Other derived quantities
    for(k in 1:nspec){
    mlambda[k] <- phi[k] * exp(beta0[k]) # Expected abundance on natural scale
    logit(mp[k]) <- alpha0[k]     # Mean detection on natural scale
    Nocc.fs[k] <- sum(z[,k])      # Number of occupied sites among the 267
    }
    for (i in 1:nsite) {
    Nsite[i] <- sum(z[i,])        # Number of occurring species at each site
    }
    }
    ",fill = TRUE)
sink()

# Initial values
ast <- matrix(rep(1, nspec*nsite), nrow = nsite)
some.more <- 5          # May have to play with this until JAGS is happy
Nst <- apply(Yc, c(1,3), max, na.rm = T) + some.more
Nst[Nst == '-Inf'] <- 20          # May have to play with this, too
Nst <- Nst
inits <- function()list(a = ast, N = Nst)

# OR: use inits at earlier solutions (greatly speeds up convergence)
pm <- out11$mean     # Pull out posterior means from earlier run
inits <- function() list(a = ast, N = Nst, alpha0 = rnorm(nspec), beta0 = rnorm(nspec), alpha = matrix(rnorm(n = nspec*3), ncol = 3), beta = matrix(rnorm(n = nspec*3), ncol = 3), mu.beta0 = pm$mu.beta0, sd.beta0 = pm$sd.beta0, mu.beta = pm$mu.beta, sd.beta = pm$sd.beta, mu.alpha0 = pm$mu.alpha0, sd.alpha0 = pm$sd.alpha0, mu.alpha = pm$mu.alpha, sd.alpha = pm$sd.alpha )

# Parameters monitored
params <- c("phi", "mp", "mlambda", "alpha0", "beta0", "alpha", "beta", "mu.beta0", "sd.beta0", "mu.beta", "sd.beta", "mu.alpha0", "sd.alpha0", "mu.alpha", "sd.alpha", "Nsite")

# MCMC settings
ni <- 60000   ;   nt <- 30   ;   nb <- 30000   ;   nc <- 3

# Call JAGS from R (BRT XXX min), check convergence and summarize posteriors
out11 <- jags(win.data, inits, params, "model11.txt", n.chains = nc, 
              n.thin = nt, n.iter = ni, n.burnin = nb, parallel = FALSE)
par(mfrow = c(3,3))   ;    traceplot(out11, c("mu.beta0", "sd.beta0", "mu.beta", "sd.beta", "mu.alpha0", "sd.alpha0", "mu.alpha", "sd.alpha") )
print(out11, 2)


summary(p.sample <- plogis(rnorm(10^6, mean = -1.170, sd = 0.980)) )
hist(p.sample, breaks = 50, col = "grey", xlab = "Per-individual detection probability", freq = FALSE)


# Predict detection for date and duration and occupancy for elevation and forest
# for each of the 145 observed species
predI <- array(NA, dim = c(500, nspec, 4))   # covariate value x species x response, "I" for 'individual' (as opposed to 'species' in model 10)
pm <- out11$mean            # Grab posterior means from model 11
for(i in 1:nspec){          # Loop over 145 observed species
  predI[,i,1] <- plogis(pm$alpha0[i] + pm$alpha[i,1] * dat.pred + 
                          pm$alpha[i,2] * dat.pred^2 )     # p ~ date
  predI[,i,2] <- plogis(pm$alpha0[i] + pm$alpha[i,3] * dur.pred) # p ~ duration
  predI[,i,3] <- pm$phi[i] * exp(pm$beta0[i] + pm$beta[i,1] * ele.pred + 
                                   pm$beta[i,2] * ele.pred^2 )     # psi ~ elevation
  predI[,i,4] <- pm$phi[i] * exp(pm$beta0[i] + pm$beta[i,3] * for.pred) # psi ~ forest
}

# Plots for detection probability and survey date and duration (Fig. 11-29)
par(mfrow = c(1,2), cex.lab = 1.3, cex.axis = 1.3)
plot(o.dat, predI[,1,1], lwd = 3, type = 'l', lty = 1, frame = F, 
     ylim = c(0, 1), xlab = "Survey date (1 = 1 April)", 
     ylab = "Per-individual detection probability")
for(i in 2:145){
  lines(o.dat, predI[,i,1], col = i, lwd = 3)
}

plot(o.dur, predI[,1,2], lwd = 3, type = 'l', lty = 1, frame = F, 
     ylim = c(0, 1), xlab = "Survey duration (min)", 
     ylab = "Per-individual detection probability")
for(i in 2:145){
  lines(o.dur, predI[,i,2], col = i, lwd = 3)
}


# Plots for expected abundance and elevation and forest cover (Fig. 11-30)
par(mfrow = c(1,2), cex.lab = 1.3, cex.axis = 1.3)
plot(o.ele, predI[,1,3], lwd = 3, type = 'l', lty = 1, frame = F, 
     ylim = c(0, 60), xlab = "Elevation (m a.s.l.)",ylab = "Expected abundance")
for(i in 2:145){
  lines(o.ele, predI[,i,3], col = i, lwd = 3)
}

plot(o.for, predI[,1,4], lwd = 3, type = 'l', lty = 1, frame = F, 
     ylim = c(0, 60), xlab = "Forest cover (%)", ylab = "Expected abundance")
for(i in 2:145){
  lines(o.for, predI[,i,4], col = i, lwd = 3)
}
