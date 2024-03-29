set.seed(1234)

expect_names <- function(object, expectation) {
  obj_names <- names(object)
  expect_true(all(expectation %in% obj_names))
}

test_that("dags ............", {
  # non-reversible dag
  p1 <- ggdag_equivalent_dags(test_dag)
  p2 <- ggdag_equivalent_class(test_dag)
  expect_doppelganger("ggdag_equivalent_dags() plots no equivalent dags", p1)
  expect_doppelganger("ggdag_equivalent_class() plots no reversible edges", p2)

  # reversible dag
  g_ex <- dagify(y ~ x + z, x ~ z)
  p3 <- ggdag_equivalent_dags(g_ex)
  p4 <- ggdag_equivalent_class(g_ex)
  expect_doppelganger("ggdag_equivalent_dags() plots 6 equivalent dags", p3)
  expect_doppelganger("ggdag_equivalent_class() plots all reversible edges", p4)

  # equivalent dags work with labels and maintain other columns from original dag
  labelled_dag <- dagify(
    y ~ x,
    y ~ z,
    x ~ z,
    labels = c(
      "y" = "Outcome",
      "x" = "Exposure",
      "z" = "Confounder"
    ),
    exposure = "x",
    outcome = "y"
  ) %>%
    tidy_dagitty()

  labelled_dag2 <- labelled_dag %>%
    # also add node status
    node_status() %>%
    node_equivalent_dags()

  expect_names(pull_dag_data(labelled_dag2), c("label", "status"))

  p5 <- ggdag_equivalent_dags(labelled_dag, use_labels = "label")
  expect_doppelganger("ggdag_equivalent_class() plots labels", p5)
})
