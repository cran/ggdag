#' Covariate Adjustment Sets
#'
#' See [dagitty::adjustmentSets()] for details.
#'
#' @param .tdy_dag input graph, an object of class `tidy_dagitty` or
#'   `dagitty`
#' @param exposure a character vector, the exposure variable. Default is
#'   `NULL`, in which case it will be determined from the DAG.
#' @param outcome a character vector, the outcome variable. Default is
#'   `NULL`, in which case it will be determined from the DAG.
#' @param ... additional arguments to `adjustmentSets`
#' @param shadow logical. Show paths blocked by adjustment?
#' @param node_size size of DAG node
#' @param text_size size of DAG text
#' @param label_size size of label text
#' @param text_col color of DAG text
#' @param label_col color of label text
#' @param node logical. Should nodes be included in the DAG?
#' @param stylized logical. Should DAG nodes be stylized? If so, use
#'   `geom_dag_nodes` and if not use `geom_dag_point`
#' @param text logical. Should text be included in the DAG?
#' @param use_labels a string. Variable to use for `geom_dag_label_repel()`.
#'   Default is `NULL`.
#' @inheritParams expand_plot
#'
#' @return a `tidy_dagitty` with an `adjusted` column and `set`
#'   column, indicating adjustment status and DAG ID, respectively, for the
#'   adjustment sets or a `ggplot`
#' @export
#'
#' @examples
#' dag <- dagify(y ~ x + z2 + w2 + w1,
#'   x ~ z1 + w1,
#'   z1 ~ w1 + v,
#'   z2 ~ w2 + v,
#'   w1 ~ ~w2,
#'   exposure = "x",
#'   outcome = "y"
#' )
#'
#' tidy_dagitty(dag) %>% dag_adjustment_sets()
#'
#' ggdag_adjustment_set(dag)
#'
#' ggdag_adjustment_set(dagitty::randomDAG(10, .5),
#'   exposure = "x3",
#'   outcome = "x5"
#' )
#'
#' @rdname adjustment_sets
#' @name Covariate Adjustment Sets
dag_adjustment_sets <- function(.tdy_dag, exposure = NULL, outcome = NULL, ...) {
  .tdy_dag <- if_not_tidy_daggity(.tdy_dag)
  sets <- dagitty::adjustmentSets(pull_dag(.tdy_dag), exposure = exposure, outcome = outcome, ...)
  is_empty_set <- purrr::is_empty(sets)
  if (is_empty_set) {
    warning("Failed to close backdoor paths. Common reasons include:
            * graph is not acyclic
            * backdoor paths are not closeable with given set of variables
            * necessary variables are unmeasured (latent)")
    sets <- "(No Way to Block Backdoor Paths)"
  } else {
    sets <- extract_sets(sets)
  }

  update_dag_data(.tdy_dag) <-
    purrr::map_df(
      sets,
      ~ dplyr::mutate(pull_dag_data(.tdy_dag), adjusted = ifelse(name %in% .x, "adjusted", "unadjusted"), set = paste0("{", paste(.x, collapse = ", "), "}"))
    )

  .tdy_dag
}

extract_sets <- function(sets) {
  sets <- unname(as.list(sets))
  sets <- purrr::map_if(sets, purrr::is_empty, ~"(Backdoor Paths Unconditionally Closed)")
}


#' @rdname adjustment_sets
#' @export
ggdag_adjustment_set <- function(.tdy_dag, exposure = NULL, outcome = NULL, ..., shadow = FALSE,
                                 node_size = 16, text_size = 3.88, label_size = text_size,
                                 text_col = "white", label_col = text_col,
                                 node = TRUE, stylized = FALSE, text = TRUE, use_labels = NULL,
                                 expand_x = expansion(c(0.25, 0.25)),
                                 expand_y = expansion(c(0.2, 0.2))) {
  .tdy_dag <- if_not_tidy_daggity(.tdy_dag) %>%
    dag_adjustment_sets(exposure = exposure, outcome = outcome, ...)

  p <- ggplot2::ggplot(.tdy_dag, ggplot2::aes(
    x = x, y = y, xend = xend,
    yend = yend, shape = adjusted,
    col = adjusted
  )) +
    ggplot2::facet_wrap(~set) +
    scale_adjusted() +
    expand_plot(expand_x = expand_x, expand_y = expand_y)

  if (shadow) {
    p <- p + geom_dag_edges(ggplot2::aes(edge_alpha = adjusted),
      start_cap = ggraph::circle(10, "mm"),
      end_cap = ggraph::circle(10, "mm")
    )
  } else {
    vals <- c("unadjusted" = "black", "adjusted" = "#FFFFFF00")
    p <- p + geom_dag_edges(
      ggplot2::aes(edge_colour = adjusted),
      show.legend = FALSE
    ) +
      ggraph::scale_edge_colour_manual(
        drop = FALSE,
        values = vals,
        limits = names(vals)
      )
  }

  if (node) {
    if (stylized) {
      p <- p + geom_dag_node(size = node_size)
    } else {
      p <- p + geom_dag_point(size = node_size)
    }
  }

  if (text) p <- p + geom_dag_text(col = text_col, size = text_size)

  if (!is.null(use_labels)) {
    p <- p +
      geom_dag_label_repel(
        ggplot2::aes(
          label = !!rlang::sym(use_labels),
          fill = adjusted
        ),
        size = text_size,
        col = label_col, show.legend = FALSE
      )
  }
  p
}

#' Assess if a variable confounds a relationship
#'
#' @param .tdy_dag input graph, an object of class `tidy_dagitty` or
#'   `dagitty`
#' @param z a character vector, the potential confounder
#' @param x,y a character vector, the variables z may confound.
#' @param direct logical. Only consider direct confounding? Default is
#'   `FALSE`
#'
#' @return Logical. Is the variable a confounder?
#' @export
#'
#' @examples
#' dag <- dagify(y ~ z, x ~ z)
#'
#' is_confounder(dag, "z", "x", "y")
#' is_confounder(dag, "x", "z", "y")
#'
is_confounder <- function(.tdy_dag, z, x, y, direct = FALSE) {
  .tdy_dag <- if_not_tidy_daggity(.tdy_dag)
  dag <- pull_dag(.tdy_dag)

  if (direct) {
    z_descendants <- dagitty::children(dag, z)
  } else {
    z_descendants <- dagitty::descendants(dag, z)[-1]
  }
  all(c(x, y) %in% z_descendants)
}

#' Adjust for variables and activate any biasing paths that result
#'
#' @param .tdy_dag input graph, an object of class `tidy_dagitty` or
#'   `dagitty`
#' @param var a character vector, the variable(s) to adjust for.
#' @param ... additional arguments passed to `tidy_dagitty()`
#' @param node_size size of DAG node
#' @param text_size size of DAG text
#' @param label_size size of label text
#' @param text_col color of DAG text
#' @param label_col color of label text
#' @param node logical. Should nodes be included in the DAG?
#' @param stylized logical. Should DAG nodes be stylized? If so, use
#'   `geom_dag_nodes` and if not use `geom_dag_point`
#' @param text logical. Should text be included in the DAG?
#' @param use_labels a string. Variable to use for
#'   `geom_dag_label_repel()`. Default is `NULL`.
#' @param collider_lines logical. Should the plot show paths activated by
#'   adjusting for a collider?
#' @param as_factor logical. Should the `adjusted` column be a factor?
#' @param activate_colliders logical. Include colliders activated by adjustment?
#'
#' @return a `tidy_dagitty` with a `adjusted` column for adjusted
#'   variables, as well as any biasing paths that arise, or a `ggplot`
#' @export
#'
#' @examples
#' dag <- dagify(m ~ a + b, x ~ a, y ~ b)
#'
#' control_for(dag, var = "m")
#' ggdag_adjust(dag, var = "m")
#'
#' @rdname control_for
#' @name Adjust for variables
control_for <- function(.tdy_dag, var, as_factor = TRUE, activate_colliders = TRUE, ...) {
  .tdy_dag <- if_not_tidy_daggity(.tdy_dag, ...)
  updated_dag <- pull_dag(.tdy_dag)
  dagitty::adjustedNodes(updated_dag) <- var
  update_dag(.tdy_dag) <- updated_dag
  if (isTRUE(activate_colliders)) .tdy_dag <- activate_collider_paths(.tdy_dag, var)
  .tdy_dag <- dplyr::mutate(.tdy_dag, adjusted = ifelse(name %in% var, "adjusted", "unadjusted"))
  if (as_factor) .tdy_dag <- dplyr::mutate(.tdy_dag, adjusted = factor(adjusted, exclude = NA))
  .tdy_dag
}

#' @rdname control_for
#' @export
adjust_for <- control_for

#' @rdname control_for
#' @export
ggdag_adjust <- function(.tdy_dag, var = NULL, ...,
                         node_size = 16, text_size = 3.88, label_size = text_size,
                         text_col = "white", label_col = text_col,
                         node = TRUE, stylized = FALSE, text = TRUE, use_labels = NULL, collider_lines = TRUE) {
  .tdy_dag <- if_not_tidy_daggity(.tdy_dag, ...)
  if (!is.null(var)) {
    .tdy_dag <- .tdy_dag %>% control_for(var)
  } else {
    var <- dagitty::adjustedNodes(pull_dag(.tdy_dag))
    if (is.null(var)) stop("an adjusting variable needs to be set, either via `var` or `control_for()`")
    if (is.null(pull_dag_data(.tdy_dag)$adjusted)) .tdy_dag <- .tdy_dag %>% control_for(var)
  }

  p <- .tdy_dag %>%
    ggplot2::ggplot(ggplot2::aes(
      x = x, y = y, xend = xend, yend = yend,
      col = adjusted, shape = adjusted
    )) +
    geom_dag_edges(ggplot2::aes(edge_alpha = adjusted),
      start_cap = ggraph::circle(10, "mm"),
      end_cap = ggraph::circle(10, "mm")
    ) +
    scale_adjusted() +
    expand_plot(expand_y = expansion(c(0.2, 0.2)))

  if (collider_lines) p <- p + geom_dag_collider_edges()
  if (node) {
    if (stylized) {
      p <- p + geom_dag_node(size = node_size)
    } else {
      p <- p + geom_dag_point(size = node_size)
    }
  }

  if (text) p <- p + geom_dag_text(col = text_col, size = text_size)

  if (!is.null(use_labels)) {
    p <- p +
      geom_dag_label_repel(
        ggplot2::aes(
          label = !!rlang::sym(use_labels),
          fill = adjusted
        ),
        size = text_size,
        col = label_col, show.legend = FALSE
      )
  }
  p
}
