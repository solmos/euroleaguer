#' Get who assisted who from play-by-play data
#'
#' @param pbp Play-by-play data frame as produced by extract_pbp()
#' @param team An optional three letter string specifying the team code
#'
#' @return A data frame
#' @export
#'
#' @examples
getAssists <- function(pbp, team) {
    ignored_plays <- c("IN", "OUT", "TOUT", "TOUT_TV")

    pbp <- pbp %>%
        dplyr::filter(!(.data$play_type %in% ignored_plays))
    if (!missing(team)) {
        pbp <- pbp %>%
            dplyr::filter(.data$team_code == team)
    }
    # Assisted FGM are recorded in the row above the assist row
    assists_idx <- which(pbp$play_type == "AST")
    fg_idx <- assists_idx - 1
    assists_df <- data.frame(
        passer = pbp$player_name[assists_idx],
        shooter = pbp$player_name[fg_idx],
        play_type = as.character(pbp$play_type[fg_idx]),
        points = 0,
        team_code = pbp$team_code[fg_idx],
        seconds = pbp$seconds[fg_idx],
        game_code = pbp$game_code[fg_idx],
        season = pbp$season[fg_idx],
        play_number = pbp$play_number[assists_idx],
        time_remaining = pbp$time_remaining[fg_idx],
        quarter = pbp$quarter[fg_idx],
        stringsAsFactors = FALSE
    )

    # We need to find out how many assisted free throws were made
    # We get a df with the rows above and below the assisted FT
    ft_plays <- c("FTM", "RPF", "CPF")
    assisted_fts <- assists_df %>%
        dplyr::filter(.data$play_type %in% ft_plays) %>%
        dplyr::select(.data$play_type, .data$seconds,
                      .data$game_code, .data$season)

    pbp_by_game <- split(pbp, list(pbp$game_code, pbp$season))


    assisted_fts_by_game <- split(
        assisted_fts,
        f = list(assisted_fts$game_code, assisted_fts$season),
        drop = TRUE
        )
    # Select only games that have assisted FTs
    assisted_ft_pbp <- pbp_by_game[names(pbp_by_game) %in% names(assisted_fts_by_game)]

    # We could do the following step with the following purrr alternative
    # purrr::map2_df(
    #     assisted_ft_pbp,
    #     assisted_fts_by_game,
    #     function(pbp, ast_df) pbp[pbp$seconds %in% ast_df$seconds,]
    # )

    ft_list <- Map(function(pbp, a) pbp[pbp$seconds %in% a$seconds,],
                   pbp = assisted_ft_pbp, a = assisted_fts_by_game)
    ft_df <- do.call("rbind", ft_list) %>%
        # dplyr::mutate(seconds = factor(.data$seconds)) %>%
        dplyr::group_by(.data$season, .data$game_code, .data$seconds) %>%
        dplyr::summarise(fta = sum(.data$play_type == "FTM" |
                                       .data$play_type == "FTA"),
                         ftm = sum(.data$play_type == "FTM"),
                         and1 = .data$fta == 1,
                         fg2 = sum(.data$play_type == "2FGM"),
                         fg3 = sum(.data$play_type == "3FGM"),
                         foul = 1) %>%
        dplyr::mutate(shot_type = dplyr::case_when(
            fg2 == 1 ~ "2FG",
            fg3 == 1 ~ "3FG",
            fta == 2 ~ "2FG",
            fta == 3 ~ "3FG"
            )
        )
    assists_df$seconds <- as.integer(assists_df$seconds)
    ft_df$seconds <- as.integer(ft_df$seconds)
    assists_df <- dplyr::left_join(assists_df, ft_df,
                                   by = c("season", "game_code", "seconds"))

    # NOTE: Any non 2FG or 3FG will be recorded as NA
    assists_df$shot_type[assists_df$play_type == "2FGM"] <- "2FG"
    assists_df$shot_type[assists_df$play_type == "3FGM"] <- "3FG"

    assists_df$foul[is.na(assists_df$foul)] <- 0
    assists_df$ftm[is.na(assists_df$ftm)] <- 0
    assists_df$and1[is.na(assists_df$and1)] <- 0

    assists_df <- assists_df %>%
        dplyr::mutate(points = dplyr::case_when(
            .data$foul == 1 & .data$and1 == 0 ~ ftm,
            .data$and1 == 1 & .data$shot_type == "2FG" ~ 2 + ftm,
            .data$and1 == 1 & .data$shot_type == "3FG" ~ 3 + ftm,
            .data$play_type == "2FGM" ~ 2,
            .data$play_type == "3FGM" ~ 3
        ))

    assists <- assists_df %>%
        dplyr::mutate(
            foul = as.logical(.data$foul),
            and1 = as.logical(.data$and1)
            ) %>%
        dplyr::select(
            .data$season,
            .data$game_code,
            .data$team_code,
            .data$passer,
            .data$shooter,
            .data$shot_type,
            .data$points,
            .data$time_remaining,
            .data$quarter,
            .data$seconds,
            .data$foul,
            .data$and1,
            .data$ftm
        )

    tibble::as_tibble(assists)
}

