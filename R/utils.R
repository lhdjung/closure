
# Avoid NOTEs in R-CMD saying "no visible binding for global variable".
utils::globalVariables(c(".", "value"))


# Add S3 class(es) to an object `x`
add_class <- function (x, new_class) {
  `class<-`(x, value = c(new_class, class(x)))
}

# Reading CLOSURE data from disk can lead to spurious differences in attributes;
# specifically, in pointers. However, what matters when comparing two data
# frames produced by different CLOSURE implementations is only the values, not
# any transitory details about the way R stores them in memory.

# Test whether two objects are identical except for their attributes. In other
# words, when the attributes are removed, is the rest identical between the two?
identical_except_attributes <- function(x, y) {
  identical(
    `attributes<-`(x, NULL),
    `attributes<-`(y, NULL)
  )
}


# Given two data frames, does each pair of columns contain the same values? This
# is tested by sorting the columns first, then comparing them. CLOSURE results
# are hard to predict, and different correct implementations can lead to
# differently sorted columns. The mark of correctness, then, is whether the
# columns are identical after being ordered equally. This assumes the same
# number and names of columns. With `message = TRUE`, it will print which column
# pair is the first unequal one if the result is `FALSE`.
identical_sorted_cols <- function(x, y, message = FALSE) {
  if (ncol(x) != ncol(y)) {
    cli::cli_abort("Different numbers of columns.")
  }
  if (!identical(colnames(x), colnames(y))) {
    cli::cli_abort("Different column names.")
  }
  for (n in seq_len(ncol(x))) {
    if (!identical(sort(x[[n]]), sort(y[[n]]))) {
      if (message) {
        message(paste("Different at", n))
      }
      return(FALSE)
    }
  }
  TRUE
}


# Error if the input was not produced by `closure_combine()`, or perhaps
# `closure_pivot_longer()`; this depends on the specifics of the caller
# function.
abort_not_closure_data <- function(allow_pivot = FALSE) {
  error <- "These data are not output of `closure_combine()`"
  if (allow_pivot) {
    error <- paste(error, "or `closure_pivot_longer()`")
  }
  error <- paste0(error, ".")
  cli::cli_abort(c(
    "Can only use CLOSURE data.",
    "x" = error
  ))
}


# Error if the output of certain functions has been altered, i.e., it has been
# manually tampered with so that downstream operations are no longer reliable.
abort_closure_data_altered <- function(type, fn_name) {
  cli::cli_abort(c(
    "Can only use {type} here if left unaltered.",
    "x" = paste(
      "These data seem to be output of `{fn_name}()`",
      "that was later manipulated."
    ),
    "i" = "Leave the data unchanged to avoid this error."
  ))
}


# Error if input is not a CLOSURE data frame.
check_closure_combine <- function(data) {

  if (!inherits(data, "closure_combine")) {
    abort_not_closure_data()
  }

  coltypes <- vapply(
    X = data,
    FUN = typeof,
    FUN.VALUE = character(1),
    USE.NAMES = FALSE
  )

  if (!all(coltypes == "integer")) {
    colnames_all <- colnames(data)
    offenders <- colnames_all[!coltypes == "integer"]
    offenders <- paste0("\"", offenders, "\"")
    this_these <- if (length(offenders) == 1) {
      "This column is"
    } else {
      "These columns are"
    }
    cli::cli_abort(c(
      "All columns of CLOSURE data must be integer.",
      "x" = "{this_these} not integer:",
      "x" = "{offenders}"
    ))
  }

  colnames_expected <- paste0("n", seq_len(ncol(data)))

  # Check correct column names:
  if (identical(colnames(data), colnames_expected)) {
    return(invisible(NULL))
  }


  # From now on, the function only checks which kind of column name error it
  # should throw.

  colnames_all <- colnames(data)

  # The parts of the error message that are common to all possible errors below:
  error_start <- "Column names of CLOSURE data must be valid."
  error_end <- c(
    "i" = "Tip: leave the data unchanged to avoid this error."
  )


  # Are any incorrect column names present?
  offenders <- colnames_all[!(colnames_all %in% colnames_expected)]

  # Circumspect way of checking whether (correct) columns were removed: if so,
  # `colnames_expected` will be too short, so that the last N column names from
  # the longer `colnames_all` vector are not present in it, where N is the
  # number of columns that were removed. Therefore, some "offenders" will
  # actually have the correct format, so this is checked here.
  if (any(grepl("^n\\d+$", offenders))) {
    cli::cli_abort(c(
      error_start,
      "x" = "Were any columns removed?",
      error_end
    ))
  }

  if (length(offenders) > 0) {
    this_these <- if (length(offenders) == 1) {
      "This column name is"
    } else {
      "These column names are"
    }

    offenders <- paste0("\"", offenders, "\"")

    cli::cli_abort(c(
      error_start,
      "x" = "{this_these} unexpected:",
      "x" = "{offenders}",
      error_end
    ))
  }


  # Are any correct column names absent?
  missing_cols <- colnames_expected[!(colnames_expected %in% colnames_all)]

  if (length(missing_cols) > 0) {
    missing_cols <- paste0("\"", missing_cols, "\"")
    col_cols = if (length(missing_cols) == 1) "column" else "columns"
    cli::cli_abort(c(
      error_start,
      "x" = "Missing {col_cols}:",
      "x" = "{missing_cols}",
      error_end
    ))
  }

  last_n <- paste0("n", ncol(data))

  # If the column names are complete and each of them is expected, but they
  # are still not pairwise identical to the expected column names, the only
  # possibility is that they are not ordered correctly:
  cli::cli_abort(c(
    error_start,
    "x" = "Columns are not properly ordered.",
    "x" = "They should run from \"n1\" to \"{last_n}\".",
    error_end
  ))

}


# Specifically check that data already known to inherit the
# "closure_pivot_longer" class were not manipulated.
check_closure_pivot_longer_unaltered <- function(data) {

  data_are_correct <-
    identical(colnames(data$results), c("n", "value")) &&
    identical(
      vapply(data$results, typeof, character(1), USE.NAMES = FALSE),
      c("integer", "integer")
    )

  if (!data_are_correct) {
    abort_closure_data_altered(
      type = "long-format CLOSURE data",
      fn_name = "closure_pivot_longer"
    )
  }

}


# Borrowed from scrutiny's internals and used in the helper below this one.
is_seq_linear_basic <- function(x) {
  if (length(x) < 3L) {
    return(TRUE)
  }
  diff_first <- x[2L] - x[1L]
  for (i in 3L:length(x)) {
    if (x[i] - x[i - 1L] != diff_first) {
      return(FALSE)
    }
  }
  TRUE
}


# Specifically check that data already known to inherit the "closure_summarize"
# class were not manipulated.
check_closure_summarize_unaltered <- function(data) {

  data_are_correct <-
    identical(colnames(data), c("value", "f_absolute", "f_relative")) &&
    identical(
      vapply(data, typeof, character(1), USE.NAMES = FALSE),
      c("integer", "integer", "double")
    ) &&
    !anyNA(data$value) &&
    !anyNA(data$f_absolute) &&
    !anyNA(data$f_relative) &&
    identical(
      data$value,
      seq(
        from = data$value[1],
        to   = data$value[length(data$value)]
      )
    ) &&
    is_seq_linear_basic(data$value) &&
    sum(data$f_relative) == 1

  if (!data_are_correct) {
    abort_closure_data_altered(
      type = "summaries of CLOSURE data",
      fn_name = "closure_summarize"
    )
  }

}


# Functions like `closure_combine()` that take `scale_min` and `scale_max`
# arguments need to make sure that min <= max. Functions that take the mean into
# account also need to check that it is within these bounds. Such functions
# include `closure_combine()` but not `closure_count_initial()`.
check_scale <- function(scale_min, scale_max, mean = NULL) {
  if (scale_min > scale_max) {
    cli::cli_abort(c(
      "Scale minimum can't be greater than scale maximum.",
      "x" = "`scale_min` is {scale_min}.",
      "x" = "`scale_max` is {scale_max}."
    ))
  }
  if (!is.null(mean)) {
    if (mean < scale_min) {
      cli::cli_abort(c(
        "Mean can't be less than scale minimum.",
        "x" = "`mean` is {mean}.",
        "x" = "`scale_min` is {scale_min}."
      ))
    }
    if (mean > scale_max) {
      cli::cli_abort(c(
        "Mean can't be greater than scale maximum.",
        "x" = "`mean` is {mean}.",
        "x" = "`scale_max` is {scale_max}."
      ))
    }
  }
}


# Make sure a value has the right type (or one of multiple allowed types), has
# length 1, and is not `NA`. Multiple allowed types are often `c("double",
# "integer")` which allows any numeric value, but no values of any other types.
check_value <- function(x, type) {
  if (!any(type == typeof(x))) {
    name <- deparse(substitute(x))
    cli::cli_abort(c(
      "`{name}` must be {type}.",
      "x" = "It is a {typeof(x)}."
    ))
  }
  if (length(x) != 1L) {
    name <- deparse(substitute(x))
    cli::cli_abort(c(
      "`{name}` must have length 1.",
      "x" = "It has length {length(x)}."
    ))
  }
  if (is.na(x)) {
    name <- deparse(substitute(x))
    cli::cli_abort("`{name}` can't be `NA`.")
  }
}

