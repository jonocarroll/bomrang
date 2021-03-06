
#' Get BOM Daily Précis Forecast for Select Towns
#'
#' Fetch the BOM daily précis forecast and return a tidy data frame of the seven
#' day town forecast for a specified state or territory.
#'
#' @param state Australian state or territory as full name or postal code.
#' Fuzzy string matching via \code{\link[base]{agrep}} is done.  Defaults to
#' "AUS" returning all state bulletins, see details for further information.
#'
#' @details Allowed state and territory postal codes, only one state per request
#' or all using \code{AUS}.
#'  \describe{
#'    \item{ACT}{Australian Capital Territory (will return NSW)}
#'    \item{NSW}{New South Wales}
#'    \item{NT}{Northern Territory}
#'    \item{QLD}{Queensland}
#'    \item{SA}{South Australia}
#'    \item{TAS}{Tasmania}
#'    \item{VIC}{Victoria}
#'    \item{WA}{Western Australia}
#'    \item{AUS}{Australia, returns forecast for all states, NT and ACT}
#'  }
#'
#' @return
#' Tidy data frame of a Australia BOM précis seven day forecasts for select
#' towns.  For full details of fields and units returned see Appendix 2 in the
#' \emph{bomrang} vignette, use \code{vignette("bomrang", package = "bomrang")}
#' to view.
#'
#' @examples
#' \dontrun{
#' BOM_forecast <- get_precis_forecast(state = "QLD")
#'}
#' @references
#' Forecast data come from Australian Bureau of Meteorology (BOM) Weather Data
#' Services \url{http://www.bom.gov.au/catalogue/data-feeds.shtml}
#'
#' Location data and other metadata for towns come from
#' the BOM anonymous FTP server with spatial data
#' \url{ftp://ftp.bom.gov.au/anon/home/adfd/spatial/}, specifically the DBF
#' file portion of a shapefile,
#' \url{ftp://ftp.bom.gov.au/anon/home/adfd/spatial/IDM00013.dbf}
#'
#' @author Adam H Sparks, \email{adamhsparks@gmail.com} and Keith Pembleton,
#' \email{keith.pembleton@usq.edu.au}
#' @importFrom magrittr %>%
#' @export
get_precis_forecast <- function(state = "AUS") {

the_state <- .check_states(state) # see internal_functions.R

  # ftp server
  ftp_base <- "ftp://ftp.bom.gov.au/anon/gen/fwo/"

  # create vector of XML files
  AUS_XML <- c(
    "IDN11060.xml", # NSW
    "IDD10207.xml", # NT
    "IDQ11295.xml", # QLD
    "IDS10044.xml", # SA
    "IDT16710.xml", # TAS
    "IDV10753.xml", # VIC
    "IDW14199.xml"  # WA
  )

  if (the_state != "AUS") {
    xmlforecast_url <-
      dplyr::case_when(
        the_state == "ACT" |
          the_state == "CANBERRA" ~ paste0(ftp_base, AUS_XML[1]),
        the_state == "NSW" |
          the_state == "NEW SOUTH WALES" ~ paste0(ftp_base, AUS_XML[1]),
        the_state == "NT" |
          the_state == "NORTHERN TERRITORY" ~ paste0(ftp_base, AUS_XML[2]),
        the_state == "QLD" |
          the_state == "QUEENSLAND" ~ paste0(ftp_base, AUS_XML[3]),
        the_state == "SA" |
          the_state == "SOUTH AUSTRALIA" ~ paste0(ftp_base, AUS_XML[4]),
        the_state == "TAS" |
          the_state == "TASMANIA" ~ paste0(ftp_base, AUS_XML[5]),
        the_state == "VIC" |
          the_state == "VICTORIA" ~ paste0(ftp_base, AUS_XML[6]),
        the_state == "WA" |
          the_state == "WESTERN AUSTRALIA" ~ paste0(ftp_base, AUS_XML[7])
      )
    out <- .parse_forecast(xmlforecast_url)
  } else {
    file_list <- paste0(ftp_base, AUS_XML)
    out <- lapply(X = file_list, FUN = .parse_forecast)
    out <- as.data.frame(data.table::rbindlist(out))
  }
  return(out)
}

.parse_forecast <- function(xmlforecast_url) {
  # CRAN note avoidance
  AAC_codes <- attrs <- end_time_local <- precipitation_range <-
    start_time_local <- values <- NULL

  # download the XML forecast --------------------------------------------------
  tryCatch({
    xmlforecast <- xml2::read_xml(xmlforecast_url)
  },
  error = function(x)
    stop(
      "\nThe server with the forecast is not responding.",
      "Please retry again later.\n"
    ))

  areas <-
    xml2::xml_find_all(xmlforecast, ".//*[@type='location']")
  xml2::xml_find_all(areas, ".//*[@type='forecast_icon_code']") %>%
    xml2::xml_remove()

  out <- lapply(X = areas, FUN = .parse_areas)
  out <- as.data.frame(do.call("rbind", out))

  # This is the actual returned value for the main function. The functions
  # below chunk the xml into locations and then days, this assembles into
  # the final data frame

  out <- tidyr::spread(out, key = attrs, value = values)

  names(out) <- c(
    "aac",
    "index",
    "start_time_local",
    "end_time_local",
    "start_time_utc",
    "end_time_utc",
    "maximum_temperature",
    "minimum_temperature",
    "precipitation_range",
    "precis",
    "probability_of_precipitation"
  )

  out <-
    out %>%
    tidyr::separate(
      end_time_local,
      into = c("end_time_local", "UTC_offset"),
      sep = "\\+"
    ) %>%
    tidyr::separate(
      start_time_local,
      into = c("start_time_local", "UTC_offset_drop"),
      sep = "\\+"
    )

  # drop the "UTC_offset_drop" column
  out <- out[!names(out) %in% "UTC_offset_drop"]

  out$probability_of_precipitation <-
    gsub("%", "", paste(out$probability_of_precipitation))

  # remove the "T" from the date/time columns
  out[, c("start_time_local",
          "end_time_local",
          "start_time_utc",
          "end_time_utc")] <-
    apply(out[, c("start_time_local",
                  "end_time_local",
                  "start_time_utc",
                  "end_time_utc")], 2, function(x)
                    chartr("T", " ", x))

  # remove the "Z" from start_time_utc
  out[, c("start_time_utc",
          "end_time_utc")] <-
    apply(out[, c("start_time_utc",
                  "end_time_utc")], 2, function(x)
                    chartr("Z", " ", x))

  out[, "precipitation_range"] <- as.character(out[, "precipitation_range"])
  # format any values that are only zero to make next step easier
  out$precipitation_range[which(out$precipitation_range == "0 mm")] <-
    "0 mm to 0 mm"

  # separate the precipitation column into two, upper/lower limit ------------
  out <-
    out %>%
    tidyr::separate(
      precipitation_range,
      into = c("lower_precipitation_limit", "upper_precipitation_limit"),
      sep = "to",
      fill = "left"
    )

  # remove unnecessary text (mm in prcp cols) ----------------------------------
  out <- as.data.frame(lapply(out, function(x) {
    gsub(" mm", "", x)
  }))

  # convert factors to character for left merge, otherwise funny stuff happens
  out[, c(1, 3:4, 6:13)] <- lapply(out[, c(1, 3, 4, 6:13)], as.character)

  # convert dates to POSIXct format
  out[, c(3:4, 6:7)] <- lapply(out[, c(3:4, 6:7)],
                               function(x)
                                 as.POSIXct(x, origin = "1970-1-1",
                                            format = "%Y-%m-%d %H:%M:%OS"))

  # convert numeric values to numeric
  out[, c(8:11, 13)] <- lapply(out[, 8:11, 13], as.numeric)

  # Load AAC code/town name list to join with final output
  load(system.file("extdata", "AAC_codes.rda", package = "bomrang"))

  # return final forecast object -----------------------------------------------
  # merge with aac codes for location information
  tidy_df <-
    dplyr::left_join(out,
                     AAC_codes, by = c("aac" = "AAC"))

  # set names to match précis forecast
  names(tidy_df)[15:17] <- c("lon", "lat", "elev")

  # add state field
  tidy_df$state <- gsub("_.*", "", tidy_df$aac)

  # add product ID field
  tidy_df$product_id <- substr(basename(xmlforecast_url),
                               1,
                               nchar(basename(xmlforecast_url)) - 4)

  names(tidy_df)[names(tidy_df) == "PT_NAME"] <- "town"

  # reorder columns
  refcols <- c(
    "index",
    "product_id",
    "state",
    "town",
    "aac",
    "lat",
    "lon",
    "elev",
    "start_time_local",
    "end_time_local",
    "UTC_offset",
    "start_time_utc",
    "end_time_utc",
    "minimum_temperature",
    "maximum_temperature",
    "lower_precipitation_limit",
    "upper_precipitation_limit",
    "precis",
    "probability_of_precipitation"
  )
  tidy_df <- tidy_df[c(refcols, setdiff(names(tidy_df), refcols))]

  return(tidy_df)
}

# get the data from areas --------------------------------------------------
.parse_areas <- function(x) {
  aac <- as.character(xml2::xml_attr(x, "aac"))

  # get xml children for the forecast (there are seven of these for each area)
  forecast_periods <- xml2::xml_children(x)

  sub_out <-
    lapply(X = forecast_periods, FUN = .extract_values)
  sub_out <- do.call(rbind, sub_out)
  sub_out <- cbind(aac, sub_out)
  return(sub_out)
}

# extract the values of the forecast items
.extract_values <- function(y) {
  values <- xml2::xml_children(y)
  attrs <- unlist(as.character(xml2::xml_attrs(values)))
  values <- unlist(as.character(xml2::xml_contents(values)))

  time_period <- unlist(t(as.data.frame(xml2::xml_attrs(y))))
  time_period <-
    time_period[rep(seq_len(nrow(time_period)), each = length(attrs)), ]

  sub_out <- cbind(time_period, attrs, values)
  row.names(sub_out) <- NULL
  return(sub_out)
}
