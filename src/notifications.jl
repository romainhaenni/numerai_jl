module Notifications

using Dates
using TimeZones

# Import UTC utility function
include("utils.jl")

function send_notification(title::String, message::String, type::Symbol=:info)
    sound = type == :error ? "Basso" : (type == :success ? "Glass" : "default")
    
    script = """
    display notification "$message" with title "$title" sound name "$sound"
    """
    
    try
        run(`osascript -e $script`)
    catch e
        @warn "Failed to send notification: $e"
    end
end

function send_training_complete(model_name::String, score::Float64)
    title = "Training Complete"
    message = "Model: $model_name\\nValidation Score: $(round(score, digits=4))"
    send_notification(title, message, :success)
end

function send_submission_success(model_name::String, round_number::Int)
    title = "Submission Successful"
    message = "Model: $model_name\\nRound: $round_number"
    send_notification(title, message, :success)
end

function send_error_notification(error_msg::String)
    title = "Numerai Error"
    send_notification(title, error_msg, :error)
end

function send_round_open(round_number::Int, close_time::DateTime)
    title = "New Round Open"
    time_remaining = close_time - utc_now_datetime()
    hours = Dates.hour(time_remaining)
    minutes = Dates.minute(time_remaining)
    message = "Round $round_number is open\\nCloses in $(hours)h $(minutes)m"
    send_notification(title, message, :info)
end

function send_staking_update(total_stake::Float64, payout::Float64)
    title = "Staking Update"
    message = "Total Stake: $(round(total_stake, digits=2)) NMR\\nExpected Payout: $(round(payout, digits=4)) NMR"
    send_notification(title, message, :info)
end

function send_download_complete(dataset_type::String, file_size_mb::Float64)
    title = "Download Complete"
    message = "Dataset: $dataset_type\\nSize: $(round(file_size_mb, digits=1)) MB"
    send_notification(title, message, :success)
end

function send_model_ranking(model_name::String, rank::Int, percentile::Float64)
    title = "Model Ranking Update"
    message = "Model: $model_name\\nRank: #$rank\\nTop $(round(percentile, digits=1))%"
    send_notification(title, message, :info)
end

export send_notification, send_training_complete, send_submission_success,
       send_error_notification, send_round_open, send_staking_update,
       send_download_complete, send_model_ranking

end