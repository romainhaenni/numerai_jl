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

function parse_datetime_safe(dt_str)
    if dt_str === nothing || dt_str == ""
        return now()
    end
    try
        # Try ISO format first
        return DateTime(dt_str)
    catch
        try
            # Try Unix timestamp
            return unix2datetime(parse(Float64, dt_str))
        catch
            # Default to now if all else fails
            return now()
        end
    end
end

function get_current_round(client::NumeraiClient)::Schemas.Round
    query = """
    query {
        rounds {
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
        parse_datetime_safe(get(round_data, :openTime, nothing)),
        parse_datetime_safe(get(round_data, :closeTime, nothing)),
        parse_datetime_safe(get(round_data, :resolveTime, nothing)),
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
            nmrStaked
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
        0.0,  # Sharpe not directly available
        get(profile, :nmrStaked, 0.0)
    )
end

function download_dataset(client::NumeraiClient, dataset_type::String, output_path::String; show_progress::Bool=true)
    # Map dataset types to v5.0 filenames
    dataset_files = Dict(
        "train" => "v5.0/train.parquet",
        "validation" => "v5.0/validation.parquet",
        "live" => "v5.0/live.parquet",
        "features" => "v5.0/features.json"
    )
    
    filename = get(dataset_files, dataset_type, nothing)
    if filename === nothing
        error("Unknown dataset type: $dataset_type")
    end
    
    # Get signed URL from Numerai API
    query = """
    query(\$filename: String!) {
        dataset(filename: \$filename)
    }
    """
    
    result = graphql_query(client, query, Dict("filename" => filename))
    url = result.dataset
    
    mkpath(dirname(output_path))
    
    if show_progress
        println("📥 Downloading $dataset_type dataset...")
        
        # Download with progress callback
        download_with_progress(url, output_path, dataset_type)
        
        println("✅ Downloaded $dataset_type dataset")
    else
        Downloads.download(url, output_path)
    end
    
    return output_path
end

function download_with_progress(url::String, output_path::String, name::String)
    # Use simple download with status indication
    temp_file = tempname()
    
    try
        print("  Downloading $name... ")
        
        # Download the file
        Downloads.download(url, temp_file)
        
        # Get file size after download
        file_size = filesize(temp_file)
        size_mb = round(file_size / 1024 / 1024, digits=1)
        
        # Move to final location
        mv(temp_file, output_path, force=true)
        
        println("✓ ($(size_mb) MB)")
    catch e
        # Cleanup on error
        isfile(temp_file) && rm(temp_file)
        rethrow(e)
    end
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
    if !isfile(predictions_path)
        error("Predictions file not found: $predictions_path")
    end
    
    # First, get the upload URL
    query = """
    mutation(\$filename: String!, \$modelId: String!) {
        createSignalsSubmission(
            filename: \$filename,
            modelId: \$modelId
        ) {
            id
            filename
            uploadUrl
        }
    }
    """
    
    result = graphql_query(client, query, Dict(
        "filename" => basename(predictions_path),
        "modelId" => model_name
    ))
    
    submission_id = result.createSignalsSubmission.id
    upload_url = result.createSignalsSubmission.uploadUrl
    
    # Upload the file to S3
    file_content = read(predictions_path)
    upload_response = HTTP.put(
        upload_url,
        Dict("Content-Type" => "text/csv"),
        file_content
    )
    
    if upload_response.status != 200
        error("Failed to upload predictions: $(upload_response.status)")
    end
    
    println("Successfully uploaded predictions for model: $model_name")
    return submission_id
end

function get_live_dataset_id(client::NumeraiClient)
    query = """
    query {
        rounds {
            datasetId
        }
    }
    """
    
    result = graphql_query(client, query)
    return result.rounds[1].datasetId
end

function upload_predictions_multipart(client::NumeraiClient, model_id::String, predictions_path::String, round_number::Int)
    if !isfile(predictions_path)
        error("Predictions file not found: $predictions_path")
    end
    
    # Get AWS S3 presigned URL for upload
    query = """
    mutation(\$filename: String!, \$modelId: String!) {
        v3SubmissionUpload(
            filename: \$filename,
            modelId: \$modelId
        ) {
            filename
            url
        }
    }
    """
    
    result = graphql_query(client, query, Dict(
        "filename" => basename(predictions_path),
        "modelId" => model_id
    ))
    
    upload_url = result.v3SubmissionUpload.url
    
    # Upload the file
    file_content = read(predictions_path)
    response = HTTP.put(upload_url, [], file_content)
    
    if response.status != 200
        error("Failed to upload predictions: $(response.status)")
    end
    
    # Confirm submission
    confirm_query = """
    mutation(\$filename: String!, \$modelId: String!, \$version: Int!) {
        v3SubmitPredictions(
            filename: \$filename,
            modelId: \$modelId,
            version: \$version
        ) {
            id
            filename
        }
    }
    """
    
    confirm_result = graphql_query(client, confirm_query, Dict(
        "filename" => basename(predictions_path),
        "modelId" => model_id,
        "version" => 3
    ))
    
    return confirm_result.v3SubmitPredictions.id
end

function get_models_for_user(client::NumeraiClient)::Vector{String}
    query = """
    query {
        v3UserProfile {
            username
            models {
                name
                id
            }
        }
    }
    """
    
    try
        response = graphql_query(client, query)
        
        if haskey(response, "data") && haskey(response["data"], "v3UserProfile")
            user_profile = response["data"]["v3UserProfile"]
            if haskey(user_profile, "models") && !isnothing(user_profile["models"])
                model_names = String[]
                for model in user_profile["models"]
                    if haskey(model, "name") && !isnothing(model["name"])
                        push!(model_names, model["name"])
                    end
                end
                if !isempty(model_names)
                    return model_names
                else
                    @warn "No models found for user. Please create a model on numer.ai first."
                    return String[]
                end
            end
        end
    catch e
        @error "Failed to fetch user models: $e"
        @warn "Please check your API credentials and internet connection."
    end
    
    # Return empty array if API call fails - user needs to fix credentials
    return String[]
end

function get_dataset_info(client::NumeraiClient)::Schemas.DatasetInfo
    # Query actual dataset information from API
    query = """
    query {
        dataset {
            version
            trainDataUrl
            validationDataUrl
            liveDataUrl
            featuresUrl
        }
    }
    """
    
    try
        response = make_request(client, query)
        if haskey(response, "data") && haskey(response["data"], "dataset")
            data = response["data"]["dataset"]
            return Schemas.DatasetInfo(
                get(data, "version", "v5.0"),
                get(data, "trainDataUrl", "v5.0/train.parquet"),
                get(data, "validationDataUrl", "v5.0/validation.parquet"),
                get(data, "liveDataUrl", "v5.0/live.parquet"),
                get(data, "featuresUrl", "v5.0/features.json")
            )
        end
    catch e
        @warn "Failed to fetch dataset info from API: $e. Using default v5.0 dataset."
    end
    
    # Fallback to v5.0 defaults if API call fails
    return Schemas.DatasetInfo(
        "v5.0",
        "v5.0/train.parquet",
        "v5.0/validation.parquet",
        "v5.0/live.parquet",
        "v5.0/features.json"
    )
end

export NumeraiClient, get_current_round, get_model_performance, download_dataset,
       submit_predictions, get_models_for_user, get_dataset_info, get_submission_status,
       get_live_dataset_id, upload_predictions_multipart

end