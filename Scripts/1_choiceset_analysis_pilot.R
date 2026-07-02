library(tidyverse)
library(mlogit)

qst <- read_csv(here::here("Surveys", "test_surveys_data.csv"))
res <- read_csv(here::here("Surveys", "uk_survey_choices_chd.csv"))






data("Fishing", package = "mlogit")
Fish <- dfidx(Fishing, varying = 2:9, shape = "wide", choice = "mode")

## a pure "conditional" model
summary(mlogit(mode ~ price + catch, data = Fish))



dat_chd <- res %>% 
  select(age:has_school_age_child, Block = assigned_block, starts_with("set")) %>% 
  pivot_longer(starts_with("set")) %>% 
  filter(!is.na(value)) %>% 
  extract(name, "Set", "(set\\d+)") %>% 
  left_join(
    qst %>% 
      select(Block, Set, Alt, Var, value) %>% 
      pivot_wider(names_from = Var) %>% 
      mutate(
        across(starts_with("Var"), as.factor)
      ) %>%
      pivot_wider(names_from = Alt, values_from = Var1:Var4)
  )


dx_chd <- dfidx(dat_chd %>% 
        relocate(starts_with("Var")), varying = 1:8, sep = "_", shape = "wide", choice = "value")




fit <- mlogit(value ~ Var1 + Var3 + Var4 | sex + age, data = dx_chd, correlation = TRUE)
summary(fit)
vcov(fit)
mlogit::cov.mlogit(fit)
