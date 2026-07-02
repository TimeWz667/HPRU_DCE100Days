library(tidyverse)
library(idefix)
library(jsonlite)



sub_sel <- c(1, 2, 6, 7)

attributes <- jsonlite::read_json(here::here("def", "attributes.json"))[sub_sel]


list_features <- sapply(attributes, \(x) x$name)
list_features


lvls <- sapply(attributes, \(x) {x$levels %>% length})
code <- lapply(attributes, \(x) {x$levels %>% sapply(\(d) d$value)})

tab_attr <- lapply(attributes, \(x) {
  tibble(
    name = x$name,
    nickname = x$name_short,
    code = x$levels %>% sapply(\(d) d$value),
    text = x$levels %>% sapply(\(d) d$text)
  )
}) %>% 
  bind_rows() %>% 
  left_join(tibble(name = list_features, Var = paste0("Var", 1:length(list_features))))

tab_attr


cs <- Profiles(lvls = lvls, coding = rep("C", length(lvls)), c.lvls = code)

cs %>% head()


priors <- local({
  n_pars <- ncol(cs)
  mu <- rep(0, n_pars)
  v <- diag(length(mu))
  pd <- MASS::mvrnorm(n = 50, mu = mu, Sigma = v) # 10 draws.
  #p.d <- list(matrix(pd[,1], ncol = 1), pd[,2:n_pars])
  #p.d
  pd
})


# optionA.PHSM = 0 AND optionA.FINANCES = 50,
# optionA.PHSM = 0 AND optionA.EDUCATION = 40,
# optionA.PHSM = 0 AND optionA.INFECTION = 10,
# optionA.PHSM = 0 AND optionA.DEATHS = 50,
# ? -------- PHSM = 0 constraints (optionB) --------
#   optionB.PHSM = 0 AND optionB.FINANCES = 50,
# optionB.PHSM = 0 AND optionB.EDUCATION = 40,
# optionB.PHSM = 0 AND optionB.INFECTION = 10,
# optionB.PHSM = 0 AND optionB.DEATHS = 50,
# 
# ? -------- PHSM = 2 constraints (optionA) --------
#   optionA.PHSM = 2 AND optionA.FINANCES = 100,
# optionA.PHSM = 2 AND optionA.EDUCATION = 4,
# optionA.PHSM = 2 AND optionA.INFECTION = 90,
# optionA.PHSM = 2 AND optionA.DEATHS = 200,
# ? -------- PHSM = 2 constraints (optionB) --------
#   optionB.PHSM = 2 AND optionB.FINANCES = 100,
# optionB.PHSM = 2 AND optionB.EDUCATION = 4,
# optionB.PHSM = 2 AND optionB.INFECTION = 90,
# optionB.PHSM = 2 AND optionB.DEATHS = 200,
# 
# ? -------- Cross-alternative restrictions  -------- alternative with the highest level of restrictions must have fewer deaths/infection risk 
# optionA.PHSM > optionB.PHSM AND optionA.DEATHS > optionB.DEATHS,
# optionA.PHSM > optionB.PHSM AND optionA.INFECTION > optionB.INFECTION,
# 
# optionB.PHSM > optionA.PHSM AND optionB.DEATHS > optionA.DEATHS,
# optionB.PHSM > optionA.PHSM AND optionB.INFECTION > optionA.INFECTION,
# 
# optionA.PHSM = optionB.PHSM ?adding in this restriction as issues with dominance where PHSM is the same across alternatives 
# 
# ;require:
#   optionA.VACCINE = optionB.VACCINE


cnts <- list(
  "Alt1.Att1 != Alt2.Att1",
  "Alt1.Att2 = Alt2.Att2",
  "if Alt1.Att1 = 0 then Alt1.Att3 > 50",
  "if Alt2.Att1 = 0 then Alt2.Att3 > 50",
  "if Alt1.Att1 <= Alt2.Att1 then Alt1.Att3 > Alt2.Att3",
  "if Alt1.Att1 <= Alt2.Att1 then Alt1.Att4 > Alt2.Att4",
  "if Alt2.Att1 <= Alt1.Att1 then Alt2.Att3 > Alt1.Att3",
  "if Alt2.Att1 <= Alt1.Att1 then Alt2.Att4 > Alt1.Att4"
)


mf_cs <- Modfed(
  cs,
  n.set = 12, 
  n.alts = 2,
  n.blocks = 2,
  alt.cte = c(0, 0),
  par.draws = priors,
  parallel = T,
  constraints = cnts
)


# mf_cs2 <- Modfed(
#   as_tibble(cs) %>% 
#     filter(!(Var1 == 0 & Var3 <= 50)) %>% as.matrix(),
#   n.set = 24, 
#   n.alts = 2,
#   n.blocks = 6,
#   alt.cte = c(0, 0),
#   par.draws = priors,
#   parallel = T,
#   constraints = cnts
# )


mf_cs
mf_cs$BestDesign$DB.error
# mf_cs2$BestDesign$DB.error


questions_data <- lapply(1:length(mf_cs$BestDesign$Blocks), \(key_blk) {
  blk <- mf_cs$BestDesign$Blocks[[key_blk]]
  
  tibble(Row = rownames(blk)) %>% bind_cols(blk) %>% 
    pivot_longer(-Row, names_to = "Var") %>% 
    left_join(tab_attr %>% select(Var, text, name, value = code)) %>% 
    extract(Row, c("Set", "Alt"), "(set\\d+).(alt\\d+)") %>% 
    mutate(
      Feature = paste0(name, ": ", text),
      Block = paste0("blk", key_blk)
    )
}) %>% 
  bind_rows()


questions <- lapply(1:length(mf_cs$BestDesign$Blocks), \(key_blk) {
  blk <- mf_cs$BestDesign$Blocks[[key_blk]]
  
  tibble(Row = rownames(blk)) %>% bind_cols(blk) %>% 
    pivot_longer(-Row, names_to = "Var") %>% 
    left_join(tab_attr %>% select(Var, text, name, value = code)) %>% 
    extract(Row, c("Set", "Alt"), "(set\\d+).(alt\\d+)") %>% 
    mutate(
      Feature = paste0(name, ": ", text),
      Block = paste0("blk", key_blk)
    ) %>% 
    select(Block, Set, Alt, Feature) %>% 
    group_by(Block, Set, Alt) %>% 
    summarise(
      Feature = paste0(Feature, collapse = ", ")
    ) %>% 
    ungroup()
  
}) %>% 
  bind_rows()


questions %>% 
  write_csv(here::here("Surveys", "test_surveys.csv"))

questions_data %>% 
  write_csv(here::here("Surveys", "test_surveys_data.csv"))

