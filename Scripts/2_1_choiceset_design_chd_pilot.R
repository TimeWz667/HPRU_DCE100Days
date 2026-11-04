library(tidyverse)
library(idefix)
library(jsonlite)




attributes <- jsonlite::read_json(here::here("def", "attributes_chd.json"))


list_features <- sapply(attributes, \(x) x$name)
list_features


lvls <- sapply(attributes, \(x) {x$levels %>% length})
code <- lapply(attributes, \(x) {x$levels %>% sapply(\(d) d$value)})
lvls_names <- lapply(attributes, \(x) {x$levels %>% sapply(\(d) d$text)})

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


map_attr <- tab_attr %>% 
  select(nickname, Var) %>%
  distinct() %>% 
  with({ set_names(paste0("V", 1:length(nickname)), nickname)})


cs <- Profiles(lvls = lvls, coding = rep("D", length(lvls)))

cs_cont <- Profiles(lvls = lvls, coding = rep("C", length(lvls)), c.lvls = code)
colnames(cs_cont) <- tab_attr$nickname %>% unique()


cs %>% head()
nrow(cs)

priors <- local({
  n_pars <- ncol(cs)
  mu <- rep(0, n_pars)
  v <- diag(length(mu))
  pd <- MASS::mvrnorm(n = 50, mu = mu, Sigma = v) # 10 draws.
  #p.d <- list(matrix(pd[,1], ncol = 1), pd[,2:n_pars])
  #p.d
  pd
})





# Within alternative constraints
# optionA.PHSM = 0 AND optionA.FINANCES = 50,
# optionA.PHSM = 0 AND optionA.EDUCATION = 40,
# optionA.PHSM = 0 AND optionA.INFECTION = 10,
# optionA.PHSM = 0 AND optionA.HOSP = 50,
# 
# ? -------- PHSM = 2 constraints (optionA) --------
#   optionA.PHSM = 2 AND optionA.FINANCES = 100,
# optionA.PHSM = 2 AND optionA.EDUCATION = 4,
# optionA.PHSM = 2 AND optionA.INFECTION = 90,
# optionA.PHSM = 2 AND optionA.HOSP = 200,

within_eli <- cs_cont %>% 
  as_tibble() %>% 
  mutate(
    eli = case_when(
      PHSM == 0 ~ case_when(
        HOSP == 150 ~ F,
        INFECTION == 90 ~ F,
        T ~ T
      ),
      PHSM == 2 ~ case_when(
        HOSP == 50 ~ F,
        INFECTION == 25 ~ F,
        T ~ T
      ),
      T ~ T
    )
  ) %>% 
  pull(eli)

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
ttes <- cross_join(
  cs_cont %>% 
    as_tibble() %>% 
    filter(within_eli) %>% 
    select(PHSM, INFECTION, HOSP) %>% 
    distinct(),
  cs_cont %>% 
    as_tibble() %>% 
    filter(within_eli) %>% 
    select(PHSM, INFECTION, HOSP) %>% 
    distinct()
) %>% 
  filter(!(PHSM.x > PHSM.y & HOSP.x > HOSP.y)) %>% 
  filter(!(PHSM.y > PHSM.x & HOSP.y > HOSP.x)) %>% 
  filter(!(PHSM.x > PHSM.y & INFECTION.x > INFECTION.y)) %>% 
  filter(!(PHSM.y > PHSM.x & INFECTION.y > INFECTION.x)) %>% 
  filter(PHSM.y != PHSM.x)

ttes %>% 
  filter(PHSM.x == 1)


# optionA.PHSM > optionB.PHSM AND optionA.DEATHS > optionB.DEATHS,
# optionA.PHSM > optionB.PHSM AND optionA.INFECTION > optionB.INFECTION,
# 
# optionB.PHSM > optionA.PHSM AND optionB.DEATHS > optionA.DEATHS,
# optionB.PHSM > optionA.PHSM AND optionB.INFECTION > optionA.INFECTION,
# 
# optionA.PHSM = optionB.PHSM ?adding in this restriction as issues with dominance where PHSM is the same across alternatives 



cnts = list(
  "Alt1.Att1 != Alt2.Att1", 
  "if Alt1.Att1 = list(1A) AND Alt2.Att2 = list(1B) AND Alt1.Att3 = list(3A) then Alt2.Att3 = list(3A)",
  "if Alt1.Att1 = list(1A) AND Alt2.Att2 = list(1B) AND Alt1.Att3 = list(3B) then Alt2.Att3 = list(3A, 3B)",
  "if Alt1.Att1 = list(1A) AND Alt2.Att2 = list(1B) AND Alt1.Att4 = list(4A) then Alt2.Att4 = list(4A)",
  "if Alt1.Att1 = list(1A) AND Alt2.Att2 = list(1B) AND Alt1.Att4 = list(4B) then Alt2.Att4 = list(4A, 4B)",
  
  "if Alt1.Att1 = list(1A) AND Alt2.Att2 = list(1C) then Alt1.Att3 = list(3B) AND Alt2.Att3 = list(3B) AND Alt1.Att4 = list(4B) AND Alt2.Att4 = list(4B)",
  
  
  "if Alt1.Att1 = list(1B) AND Alt2.Att2 = list(1A) AND Alt1.Att3 = list(3A) then Alt2.Att3 = list(3A, 3B)",
  "if Alt1.Att1 = list(1B) AND Alt2.Att2 = list(1A) AND Alt1.Att3 = list(3B) then Alt2.Att3 = list(3B)",
  "if Alt1.Att1 = list(1B) AND Alt2.Att2 = list(1A) AND Alt1.Att4 = list(4A) then Alt2.Att4 = list(4A, 4B)",
  "if Alt1.Att1 = list(1B) AND Alt2.Att2 = list(1A) AND Alt1.Att4 = list(4B) then Alt2.Att4 = list(4B)",
  
  "if Alt1.Att1 = list(1B) AND Alt2.Att2 = list(1C) AND Alt1.Att3 = list(3B) then Alt2.Att3 = list(3B)",
  "if Alt1.Att1 = list(1B) AND Alt2.Att2 = list(1C) AND Alt1.Att3 = list(3C) then Alt2.Att3 = list(3B, 3C)",
  "if Alt1.Att1 = list(1B) AND Alt2.Att2 = list(1C) AND Alt1.Att4 = list(4B) then Alt2.Att4 = list(4B)",
  "if Alt1.Att1 = list(1B) AND Alt2.Att2 = list(1C) AND Alt1.Att4 = list(4C) then Alt2.Att4 = list(4B, 4C)", 
  
  
  "if Alt1.Att1 = list(1C) AND Alt2.Att2 = list(1A) then Alt1.Att3 = list(3B) AND Alt2.Att3 = list(3B) AND Alt1.Att4 = list(4B) AND Alt2.Att4 = list(4B)",
  
  "if Alt1.Att1 = list(1C) AND Alt2.Att2 = list(1B) AND Alt1.Att3 = list(3B) then Alt2.Att3 = list(3B, 3C)",
  "if Alt1.Att1 = list(1C) AND Alt2.Att2 = list(1B) AND Alt1.Att3 = list(3C) then Alt2.Att3 = list(3C)",
  "if Alt1.Att1 = list(1C) AND Alt2.Att2 = list(1B) AND Alt1.Att4 = list(4B) then Alt2.Att4 = list(4B, 4C)",
  "if Alt1.Att1 = list(1C) AND Alt2.Att2 = list(1B) AND Alt1.Att4 = list(4C) then Alt2.Att4 = list(4C)"
)


mf_cs <- Modfed(
  cs[within_eli, ],
  n.set = 48, 
  n.alts = 2,
  alt.cte = c(0, 0),
  par.draws = priors,
  parallel = T,
  constraints = cnts
)


mf_cs_no_cross <- Modfed(
  cs[within_eli, ],
  n.set = 48, 
  n.alts = 2,
  alt.cte = c(0, 0),
  par.draws = priors,
  parallel = T
)


mf_cs
mf_cs$BestDesign$DB.error
mf_cs_no_cross
mf_cs_no_cross$BestDesign$DB.error


## Extract questions

map_attr_c <- setNames(
  paste0("C", map_attr),
  paste0(names(map_attr), "_C")
)


blks <- Blocks(mf_cs$BestDesign$design, n.alts = 2, n.blocks = 4)
questions <- lapply(blks$Blocks, \(blk) {
  left_join(
    Decode(blk, n.alts = 2, coding = rep("D", length(lvls)), lvl.names = lvls_names)$design %>% 
      as_tibble(rownames = "Row"), 
    Decode(blk, n.alts = 2, coding = rep("D", length(lvls)), lvl.names = lapply(code, as.character))$design %>% 
      as_tibble(rownames = "Row") %>% 
      rename_with(.fn = \(x) paste0("C", x), .cols = -Row)
  )
}) %>% 
  bind_rows() %>% 
  mutate(
    Block = rep(1:4, each = 24)
  ) %>% 
  rename(all_of(c(map_attr, map_attr_c))) %>% 
  extract(Row, c("Set", "Alt"), "(set\\d+).(alt\\d+)") %>% 
  relocate(Block, Set, Alt)


save(blks, file = here::here("Surveys", "Survey_CHD_Blocks_pilot.rdata"))
write_csv(questions, here::here("Surveys", "Survey_CHD_pilot.csv"))


blks <- Blocks(mf_cs_no_cross$BestDesign$design, n.alts = 2, n.blocks = 4)
questions_no_cross <- lapply(blks$Blocks, \(blk) {
  left_join(
    Decode(blk, n.alts = 2, coding = rep("D", length(lvls)), lvl.names = lvls_names)$design %>% 
      as_tibble(rownames = "Row"), 
    Decode(blk, n.alts = 2, coding = rep("D", length(lvls)), lvl.names = lapply(code, as.character))$design %>% 
      as_tibble(rownames = "Row") %>% 
      rename_with(.fn = \(x) paste0("C", x), .cols = -Row)
  )
}) %>% 
  bind_rows() %>% 
  mutate(
    Block = rep(1:4, each = 24)
  ) %>% 
  rename(all_of(c(map_attr, map_attr_c))) %>% 
  extract(Row, c("Set", "Alt"), "(set\\d+).(alt\\d+)") %>% 
  relocate(Block, Set, Alt)


save(blks, file = here::here("Surveys", "Survey_CHD_Blocks_prepilot_nocross.rdata"))
write_csv(questions_no_cross, here::here("Surveys", "Survey_CHD_pilot.csv_nocross.csv"))

