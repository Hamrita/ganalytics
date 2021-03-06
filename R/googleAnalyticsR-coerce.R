#' @importFrom methods setAs
#' @importClassesFrom googleAnalyticsR dim_fil_ga4 met_fil_ga4 orFiltersForSegment_ga4
#' @importClassesFrom googleAnalyticsR segmentDef_ga4 segmentFilterClause_ga4
#' @importClassesFrom googleAnalyticsR segmentFilter_ga4 segmentSequenceStep_ga4
#' @importClassesFrom googleAnalyticsR sequenceSegment_ga4 simpleSegment_ga4
#' @importClassesFrom googleAnalyticsR segment_ga4 dynamicSegment_ga4 .filter_clauses_ga4
#' @importClassesFrom googleAnalyticsR dim_ga4 met_ga4
NULL

get_expression_details <- function(from, var_operators) {
  varName <- as.character(Var(from))
  names(varName) <- sub("^ga:", "", varName)
  operator <- Comparator(from)
  negated <- operator %in% kGa4Ops$negated_operators
  if(negated) operator <- Not(operator)
  operator_lookup_index <- match(as.character(operator), var_operators)
  operator_name <- names(var_operators)[operator_lookup_index]
  operand <- as.character(Operand(from))
  expressions <- character(0)
  minComparisonValue <- character(0)
  maxComparisonValue <- character(0)
  if(operator == "<>") {
    minComparisonValue <- operand[1]
    maxComparisonValue <- operand[2]
  } else if(inherits(from, ".metExpr")) {
    minComparisonValue <- operand
  } else {
    expressions <- operand
  }
  list(
    varName = varName,
    operator = operator,
    operator_name = operator_name,
    negated = negated,
    expressions = expressions,
    minComparisonValue = minComparisonValue,
    maxComparisonValue = maxComparisonValue
  )
}

setAs("gaDimExpr", "dim_fil_ga4", def = function(from, to) {
  dim_operation <- get_expression_details(from, kGa4Ops$dimension_operators)
  x <- list(
    dimensionName = dim_operation$varName,
    not = dim_operation$negated,
    operator = dim_operation$operator_name,
    expressions = as.list(as.character(Operand(from))),
    caseSensitive = FALSE
  )
  class(x) <- to
  x
})

setAs("gaMetExpr", "met_fil_ga4", def = function(from, to) {
  met_operation <- get_expression_details(from, kGa4Ops$metric_operators)
  x <- list(
    metricName = met_operation$varName,
    not = met_operation$negated,
    operator = met_operation$operator_name,
    comparisonValue = as.character(Operand(from))
  )
  class(x) <- to
  x
})

setAs("gaFilter", ".filter_clauses_ga4", def = function(from, to) {
  exprs <- unlist(from)
  if(all_inherit(exprs, ".dimExpr")) {
    type <- "dim_fil_ga4"
  } else if(all_inherit(exprs, ".metExpr")) {
    type <- "met_fil_ga4"
  } else {
    stop("From gaFilter must contain either all .dimExpr or all .metExpr")
  }
  filter_clauses <- lapply(
    from,
    function(or_filters) {
      or_filters <- lapply(or_filters, as, type)
      googleAnalyticsR::filter_clause_ga4(or_filters, operator = "OR")
    }
  )
  class(filter_clauses) <- type
  filter_clauses
})

setAs(".compoundExpr", ".filter_clauses_ga4", def = function(from, to) {
  as(as(from, "gaFilter"), to)
})

setAs("gaDimExpr", "segmentFilterClause_ga4", def = function(from, to) {
  exp_details <- get_expression_details(from, kGa4Ops$dimension_operators)
  segmentDimensionFilter <- list(
    dimensionName = exp_details$varName,
    operator = exp_details$operator_name,
    caseSensitive = NULL,
    expressions = exp_details$expressions,
    minComparisonValue = exp_details$minComparisonValue,
    maxComparisonValue = exp_details$maxComparisonValue
  )
  class(segmentDimensionFilter) <- "segmentDimFilter_ga4"
  x <- list(
    not = exp_details$negated,
    dimensionFilter = segmentDimensionFilter,
    metricFilter = NULL
  )
  class(x) <- to
  x
})

setAs("gaMetExpr", "segmentFilterClause_ga4", def = function(from, to) {
  from <- as(from, "gaSegMetExpr")
  as(from, to)
})

setAs("gaSegMetExpr", "segmentFilterClause_ga4", def = function(from, to) {
  exp_details <- get_expression_details(from, kGa4Ops$metric_operators)
  scope <- c(
    "perProduct" = "PRODUCT",
    "perHit" = "HIT",
    "perSession" = "SESSION",
    "perUser" = "USER"
  )[[ScopeLevel(from)]]
  segmentMetricFilter <- list(
    scope = scope,
    metricName = exp_details$varName,
    operator = exp_details$operator_name,
    comparisonValue = exp_details$minComparisonValue,
    maxComparisonValue = exp_details$maxComparisonValue
  )
  class(segmentMetricFilter) <- "segmentMetFilter_ga4"
  x <- list(
    not = exp_details$negated,
    dimensionFilter = NULL,
    metricFilter = segmentMetricFilter
  )
  class(x) <- to
  x
})

setAs("orExpr", "orFiltersForSegment_ga4", def = function(from, to) {
  x <- list(
    segmentFilterClauses = lapply(from, as, "segmentFilterClause_ga4")
  )
  class(x) <- to
  x
})

setAs("andExpr", "simpleSegment_ga4", def = function(from, to) {
  x <- list(
    orFiltersForSegment = lapply(from, as, "orFiltersForSegment_ga4")
  )
  class(x) <- to
  x
})

setAs("gaSegmentSequenceStep", "segmentSequenceStep_ga4", def = function(from, to) {
  matchType <- if(from@immediatelyPrecedes) "IMMEDIATELY_PRECEDES" else "PRECEDES"
  x <- c(
    as(as(from@.Data, "andExpr"), "simpleSegment_ga4"),
    list(matchType = matchType)
  )
  class(x) <- to
  x
})

setAs("gaSegmentSequenceFilter", "sequenceSegment_ga4", def = function(from, to) {
  segmentSequenceSteps <- lapply(from, as, "segmentSequenceStep_ga4")
  x <- list(
    segmentSequenceSteps = segmentSequenceSteps,
    firstStepShouldMatchFirstHit = from[[1]]@immediatelyPrecedes
  )
  class(x) <- to
  x
})

setAs("gaSegmentConditionFilter", "segmentFilter_ga4", def = function(from, to) {
  x <- list(
    not = IsNegated(from),
    simpleSegment = as(from, "simpleSegment_ga4"),
    sequenceSegment = NULL
  )
  class(x) <- to
  x
})

setAs(".compoundExpr", "segmentFilter_ga4", def = function(from, to) {
  as(as(from, "gaSegmentConditionFilter"), to)
})

setAs("gaSegmentSequenceFilter", "segmentFilter_ga4", def = function(from, to) {
  x <- list(
    not = IsNegated(from),
    simpleSegment = NULL,
    sequenceSegment = as(from, "sequenceSegment_ga4")
  )
  class(x) <- to
  x
})

setAs("gaDynSegment", "segmentDef_ga4", def = function(from, to) {
  x <- list(
    segmentFilters = lapply(from, as, "segmentFilter_ga4")
  )
  class(x) <- to
  x
})

setAs("gaSegmentConditionFilter", "segmentDef_ga4", def = function(from, to) {
  as(as(from, "gaDynSegment"), to)
})

setAs("gaSegmentSequenceFilter", "segmentDef_ga4", def = function(from, to) {
  as(as(from, "gaDynSegment"), to)
})

setAs("gaDynSegment", "dynamicSegment_ga4", def = function(from, to) {
  dyn_segment <- list(
    name = from@name,
    userSegment = as(select_segment_filters_with_scope(from, scope = "users"), "segmentDef_ga4"),
    sessionSegment = as(select_segment_filters_with_scope(from, scope = "sessions"), "segmentDef_ga4")
  )
  class(dyn_segment) <- "dynamicSegment_ga4"
  dyn_segment
})

setAs("gaSegmentList", "segment_ga4", def = function(from, to) {
  segment_list <- lapply(seq_along(from), function(segment_i) {
    segment_name <- names(from)[segment_i]
    if(is.null(segment_name)) segment_name <- character(0)
    segment <- from[[segment_i]]
    switch (class(segment),
      gaDynSegment = {
        segment@name = segment_name
        list(dynamicSegment = as(segment, "dynamicSegment_ga4"))
      },
      gaSegmentId = list(segmentId = as(segment, "character"))
    )
  })
  class(segment_list) <- to
  segment_list
})

setAs(".compoundExpr", "segmentDef_ga4", def = function(from, to) {
  as(as(from, "gaDynSegment"), to)
})

setAs("gaDimensions", "dim_ga4", def = function(from, to) {
  dim_ga4 <- lapply(from, function(dim_var) {
    list(
      name = as.character(dim_var),
      histogramBuckets = dim_var@histogramBuckets
    )
  })
  class(dim_ga4) <- to
  dim_ga4
})

setAs("gaMetrics", "met_ga4", def = function(from, to) {
  met_ga4 <- lapply(from, function(met_var) {
    list(
      expression = as.character(met_var),
      alias = met_var@alias,
      formattingType = met_var@formattingType
    )
  })
  class(met_ga4) <- to
  met_ga4
})

setAs("gaSortBy", "order_bys_ga4", def = function(from, to) {
  sort_order <- c("ASCENDING", "DESCENDING")[as.integer(from@desc) + 1L]
  order_bys_ga4 <- lapply(seq_along(from), function(field_i) {
    order_type_ga4 <- list(
      fieldName = from[field_i],
      orderType = from@orderType,
      sortOrder = sort_order[field_i]
    )
    class(order_type_ga4) <- "order_type_ga4"
    order_type_ga4
  })
  class(order_bys_ga4) <- to
  order_bys_ga4
})

setAs("gaQuery", "ga4_req", def = function(from, to) {
  assert_that(
    length(from@dateRange) <= 2L
  )
  if (all_inherit(unlist(from@tableFilter), "gaDimExpr")) {
    dim_filters <- from@tableFilter
    met_filters <- NULL
  } else if (all_inherit(unlist(from@tableFilter), "gaMetExpr")) {
    dim_filters <- NULL
    met_filters <- from@tableFilter
  } else {
    stop("Unrecognised type of table filter.")
  }
  request <- list(
    viewId = from@viewId,
    dateRanges = list(
      list(startDate = StartDate(from)[1L], endDate = EndDate(from)[1L]),
      list(startDate = StartDate(from)[2L], endDate = EndDate(from)[2L])
    ),
    samplingLevel = names(from@samplingLevel == samplingLevel_levels),
    dimensions = as(from@dimensions, "dim_ga4"),
    metrics = as(from@metrics, "met_ga4"),
    dimensionFilterClauses = as(dim_filters, ".filter_clauses_ga4"),
    metricFilterClauses = as(met_filters, ".filter_clauses_ga4"),
    orderBys = as(from@sortBy, "order_bys_ga4"),
    segments = as(from@segments, "segment_ga4"),
    pivots = from@pivots,
    cohortGroup = from@cohorts #,
    # pageToken = as.character(pageToken),
    # pageSize = pageSize,
    # includeEmptyRows = TRUE
  )
  class(request) <- to
})

