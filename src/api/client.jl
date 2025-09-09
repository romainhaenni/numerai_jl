module API

using HTTP
using JSON3
using Dates
using Downloads
using ProgressMeter
using ..Schemas

const GRAPHQL_ENDPOINT = "https://api-tournament.numer.ai"
const DATA_BASE_URL = "https://numerai-public-datasets.s3-us-west-2.amazonaws.com"

mutable struct NumeraiClient
    public_id::String
    secret_key::String
    headers::Dict{String,String}
end

function NumeraiClient(public_id::String, secret_key::String)
    headers = Dict(
        "Content-Type" => "application/json",
        "x-public-id" => public_id,
        "x-secret-key" => secret_key
    )
    NumeraiClient(public_id, secret_key, headers)
end

function graphql_query(client::NumeraiClient, query::String, variables::Dict=Dict())
    body = JSON3.write(Dict("query" => query, "variables" => variables))
    
    response = HTTP.post(
        GRAPHQL_ENDPOINT,
        client.headers,
        body
    )
    
    data = JSON3.read(response.body)
    
    if haskey(data, :errors)
        error("GraphQL Error: $(data.errors)")
    end
    
    return data.data
end

function get_current_round(client::NumeraiClient)::Schemas.Round
    query = """
    query {
        rounds(first: 1) {
            number
            openTime
            closeTime
            resolveTime
        }
    }
    """
    
    result = graphql_query(client, query)
    round_data = result.rounds[1]
    
    return Schemas.Round(
        round_data.number,
        DateTime(round_data.openTime),
        DateTime(round_data.closeTime),
        DateTime(round_data.resolveTime),
        true
    )
end

function get_model_performance(client::NumeraiClient, model_name::String)::Schemas.ModelPerformance
    query = """
    query(\$modelName: String!) {
        v3UserProfile(modelName: \$modelName) {
            latestRanks {
                corr
                mmc
                fnc
                tc
            }
            stake {
                value
            }
            sharpe
        }
    }
    """
    
    result = graphql_query(client, query, Dict("modelName" => model_name))
    profile = result.v3UserProfile
    
    return Schemas.ModelPerformance(
        model_name,
        model_name,
        get(profile.latestRanks, :corr, 0.0),
        get(profile.latestRanks, :mmc, 0.0),
        get(profile.latestRanks, :fnc, 0.0),
        get(profile.latestRanks, :tc, 0.0),
        get(profile, :sharpe, 0.0),
        get(profile.stake, :value, 0.0)
    )
end

function download_dataset(client::NumeraiClient, dataset_type::String, output_path::String; show_progress::Bool=true)
    urls = Dict(
        "train" => "$(DATA_BASE_URL)/v5.0/train.parquet",
        "validation" => "$(DATA_BASE_URL)/v5.0/validation.parquet",
        "live" => "$(DATA_BASE_URL)/v5.0/live.parquet",
        "features" => "$(DATA_BASE_URL)/v5.0/features.json"
    )
    
    url = get(urls, dataset_type, nothing)
    if url === nothing
        error("Unknown dataset type: $dataset_type")
    end
    
    mkpath(dirname(output_path))
    
    if show_progress
        println("Downloading $dataset_type dataset...")
        Downloads.download(url, output_path; progress=true)
    else
        Downloads.download(url, output_path)
    end
    
    return output_path
end

function get_submission_status(client::NumeraiClient, model_name::String, round_number::Int)
    query = """
    query(\$modelName: String!, \$roundNumber: Int!) {
        v3UserProfile(modelName: \$modelName) {
            roundModelPerformances(roundNumber: \$roundNumber) {
                submissionScores {
                    date
                    correlation
                    mmc
                    fnc
                    tc
                }
            }
        }
    }
    """
    
    result = graphql_query(client, query, Dict("modelName" => model_name, "roundNumber" => round_number))
    return result
end

function submit_predictions(client::NumeraiClient, model_name::String, predictions_path::String)
    query = """
    mutation(\$modelId: String!, \$filename: String!) {
        createSignalsSubmission(
            modelId: \$modelId,
            filename: \$filename
        ) {
            id
            filename
        }
    }
    """
    
    if !isfile(predictions_path)
        error("Predictions file not found: $predictions_path")
    end
    
    result = graphql_query(client, query, Dict(
        "modelId" => model_name,
        "filename" => basename(predictions_path)
    ))
    
    return result.createSignalsSubmission
end

function get_models_for_user(client::NumeraiClient)::Vector{String}
    query = """
    query {
        account {
            models {
                name
                id
            }
        }
    }
    """
    
    result = graphql_query(client, query)
    return [model.name for model in result.account.models]
end

function get_dataset_info(client::NumeraiClient)::Schemas.DatasetInfo
    return Schemas.DatasetInfo(
        "v5.0",
        "$(DATA_BASE_URL)/v5.0/train.parquet",
        "$(DATA_BASE_URL)/v5.0/validation.parquet",
        "$(DATA_BASE_URL)/v5.0/live.parquet",
        "$(DATA_BASE_URL)/v5.0/features.json"
    )
end

export NumeraiClient, get_current_round, get_model_performance, download_dataset,
       submit_predictions, get_models_for_user, get_dataset_info, get_submission_status

end