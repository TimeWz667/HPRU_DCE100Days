library(tidyverse)
library(idefix)
library(jsonlite)



attributes <- jsonlite::read_json(here::here("def", "attributes.json"))


lvls <- sapply(attributes, \(x) {x$levels %>% length})
code <- lapply(attributes, \(x) {x$levels %>% sapply(\(d) d$value)})


cs <- Profiles(lvls = lvls, coding = rep("C", length(lvls)), c.lvls = code)

