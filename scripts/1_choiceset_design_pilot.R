library(tidyverse)
library(idefix)
library(jsonlite)



attributes <- jsonlite::read_json(here::here("def", "attributes.json"))


lvls <- sapply(attributes, \(x) {x$levels %>% length})[1:4]
code <- lapply(attributes, \(x) {x$levels %>% sapply(\(d) d$value)})[1:4]


cs <- Profiles(lvls = lvls, coding = rep("C", length(lvls)), c.lvls = code)

cs


priors <- local({
  n_pars <- ncol(cs)
  mu <- rep(0, n_pars)
  v <- diag(length(mu))
  pd <- MASS::mvrnorm(n = 50, mu = mu, Sigma = v) # 10 draws.
  #p.d <- list(matrix(pd[,1], ncol = 1), pd[,2:n_pars])
  #p.d
  pd
})


mf_cs <- Modfed(
  cs,
  n.set = 48, 
  n.alts = 2,
  n.blocks = 6,
  alt.cte = c(0, 0),
  par.draws = priors,
  parallel = T
)


mf_cs

