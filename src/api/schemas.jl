module Schemas

using Dates

struct Round
    number::Int
    open_time::DateTime
    close_time::DateTime
    resolve_time::DateTime
    is_active::Bool
end

struct ModelPerformance
    model_id::String
    model_name::String
    corr::Float64
    mmc::Float64
    fnc::Float64
    tc::Float64
    sharpe::Float64
    stake::Float64
end

struct Submission
    id::String
    model_id::String
    round_number::Int
    filename::String
    submitted_at::DateTime
end

struct DatasetInfo
    version::String
    train_url::String
    validation_url::String
    live_url::String
    features_url::String
end

struct UserInfo
    username::String
    public_id::String
    models::Vector{String}
    total_stake::Float64
end

end