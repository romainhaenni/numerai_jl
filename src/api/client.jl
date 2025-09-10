module API

using HTTP
using JSON3
using Dates
using TimeZones
using Downloads
using ProgressMeter
using ..Schemas
using ..Logger: @log_debug, @log_info, @log_warn, @log_error, log_api_call, log_submission

# Import retry functionality
include("retry.jl")
using .Retry: with_retry, with_graphql_retry, with_download_retry, RetryConfig, CircuitBreaker, with_circuit_breaker

# Import UTC utility function
include("../utils.jl")

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
    return with_graphql_retry(context="GraphQL query") do
        start_time = time()
        body = JSON3.write(Dict("query" => query, "variables" => variables))
        
        response = HTTP.post(
            GRAPHQL_ENDPOINT,
            client.headers,
            body;
            readtimeout=30,
            connect_timeout=30
        )
        
        duration = time() - start_time
        log_api_call(GRAPHQL_ENDPOINT, "POST", response.status; duration=duration)
        
        data = JSON3.read(response.body)
        
        if haskey(data, :errors)
            @log_error "GraphQL Error" errors=data.errors query=first(query, 100)
            error("GraphQL Error: $(data.errors)")
        end
        
        return data.data
    end
end

function parse_datetime_safe(dt_str)
    if dt_str === nothing || dt_str == ""
        return utc_now_datetime()
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
            return utc_now_datetime()
        end
    end
end

function get_current_round(client::NumeraiClient)::Schemas.Round
    query = """
    query {
        rounds(tournament: 8, take: 5) {
            number
            openTime
            closeTime
            resolveTime
        }
    }
    """
    
    result = graphql_query(client, query)
    
    # Check if we have rounds
    if !haskey(result, "rounds") || isempty(result["rounds"])
        error("No rounds found in API response")
    end
    
    # Find the current active round (first one that hasn't resolved yet)
    current_time = utc_now_datetime()
    for round_data in result["rounds"]
        close_time = parse_datetime_safe(get(round_data, "closeTime", nothing))
        if close_time > current_time
            # This round is still active
            return Schemas.Round(
                round_data["number"],
                parse_datetime_safe(get(round_data, "openTime", nothing)),
                close_time,
                parse_datetime_safe(get(round_data, "resolveTime", nothing)),
                true  # is_active
            )
        end
    end
    
    # If no active round, return the most recent one as inactive
    # Double-check we have rounds (this should already be validated above, but safety first)
    if isempty(result["rounds"])
        error("No rounds available to return as inactive round")
    end
    
    round_data = result["rounds"][1]
    return Schemas.Round(
        round_data["number"],
        parse_datetime_safe(get(round_data, "openTime", nothing)),
        parse_datetime_safe(get(round_data, "closeTime", nothing)),
        parse_datetime_safe(get(round_data, "resolveTime", nothing)),
        false  # not active
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
        @log_info "Downloading dataset" type=dataset_type
        
        # Download with progress callback
        download_with_progress(url, output_path, dataset_type)
        
        @log_info "Downloaded dataset" type=dataset_type
    else
        Downloads.download(url, output_path; timeout=300)
    end
    
    return output_path
end

function download_with_progress(url::String, output_path::String, name::String)
    # Use simple download with status indication
    temp_file = tempname()
    
    try
        @log_info "Starting download" file=name
        
        # Download with retry logic
        with_download_retry(context="download $name") do
            Downloads.download(url, temp_file; timeout=300)
        end
        
        # Get file size after download
        file_size = filesize(temp_file)
        size_mb = round(file_size / 1024 / 1024, digits=1)
        
        # Move to final location
        mv(temp_file, output_path, force=true)
        
        @log_debug "Download complete" size_mb=size_mb
    catch e
        # Cleanup on error
        isfile(temp_file) && rm(temp_file)
        @log_error "Download failed" file=name error=string(e)
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

function submit_predictions(client::NumeraiClient, model_name::String, predictions_path::String; validate_window::Bool=true)
    if !isfile(predictions_path)
        error("Predictions file not found: $predictions_path")
    end
    
    # Validate submission window if requested
    if validate_window
        current_round = get_current_round(client)
        window_info = get_submission_window_info(current_round.open_time)
        
        if !window_info.is_open
            time_closed = abs(window_info.time_remaining)
            error("Submission window is closed for round $(current_round.number). Window closed $(round(time_closed, digits=1)) hours ago (at $(window_info.window_end) UTC)")
        end
        
        @log_info "Submission window is open" round_type=window_info.round_type round=current_round.number
        if window_info.time_remaining > 0
            @log_info "Time remaining for submission" hours_remaining=round(window_info.time_remaining, digits=1) closes_at=window_info.window_end
        end
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
        file_content;
        readtimeout=300,
        connect_timeout=30
    )
    
    if upload_response.status != 200
        error("Failed to upload predictions: $(upload_response.status)")
    end
    
    @log_info "Successfully uploaded predictions" model=model_name
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
    
    # Check if we have rounds and they contain datasetId
    if !haskey(result, :rounds) || isempty(result.rounds)
        error("No rounds found in API response")
    end
    
    first_round = result.rounds[1]
    if !haskey(first_round, :datasetId)
        error("No datasetId found in round data")
    end
    
    return first_round.datasetId
end

function upload_predictions_multipart(client::NumeraiClient, model_id::String, predictions_path::String, round_number::Int; validate_window::Bool=true)
    if !isfile(predictions_path)
        error("Predictions file not found: $predictions_path")
    end
    
    # Validate submission window if requested
    if validate_window
        current_round = get_current_round(client)
        window_info = get_submission_window_info(current_round.open_time)
        
        if !window_info.is_open
            time_closed = abs(window_info.time_remaining)
            error("Submission window is closed for round $(current_round.number). Window closed $(round(time_closed, digits=1)) hours ago (at $(window_info.window_end) UTC)")
        end
        
        @log_info "Submission window is open" round_type=window_info.round_type round=current_round.number
        if window_info.time_remaining > 0
            @log_info "Time remaining for submission" hours_remaining=round(window_info.time_remaining, digits=1) closes_at=window_info.window_end
        end
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
    response = HTTP.put(upload_url, [], file_content; readtimeout=300, connect_timeout=30)
    
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
        
        if haskey(response, "v3UserProfile")
            user_profile = response["v3UserProfile"]
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
    # Note: The v5 dataset endpoints are standard, not from GraphQL
    query = """
    query {
        rounds(tournament: 8, take: 1) {
            number
            openTime
            closeTime
            resolveTime
        }
    }
    """
    
    try
        response = graphql_query(client, query)
        # Dataset v5 uses standard URLs, not GraphQL endpoints
        # We just verify connection is working
        if haskey(response, "rounds") && !isempty(response["rounds"])
            # Connection verified, return v5 dataset info
            return Schemas.DatasetInfo(
                "v5.0",
                "v5.0/train.parquet",
                "v5.0/validation.parquet", 
                "v5.0/live.parquet",
                "v5.0/features.json"
            )
        end
    catch e
        @warn "Failed to verify API connection: $e. Using default v5.0 dataset."
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

function get_model_stakes(client::NumeraiClient, model_name::String)
    """
    Get staking information for a specific model including total stake,
    burn rate, and multipliers for scoring calculations.
    """
    query = """
    query(\$modelName: String!) {
        v3UserProfile(modelName: \$modelName) {
            nmrStaked
            stake {
                value
                confidence
                burnRate
            }
            roundModelPerformances(last: 1) {
                corrMultiplier
                mmcMultiplier
                roundNumber
            }
        }
    }
    """
    
    try
        result = graphql_query(client, query, Dict("modelName" => model_name))
        profile = result.v3UserProfile
        
        # Extract stake information
        total_stake = get(profile, :nmrStaked, 0.0)
        
        # Extract burn rate and multipliers with defaults
        stake_info = get(profile, :stake, Dict())
        burn_rate = get(stake_info, :burnRate, 0.25)  # Default 25% burn rate
        
        # Get multipliers from recent performance
        round_perfs = get(profile, :roundModelPerformances, [])
        if !isempty(round_perfs)
            latest_perf = round_perfs[end]
            corr_multiplier = get(latest_perf, :corrMultiplier, 0.5)
            mmc_multiplier = get(latest_perf, :mmcMultiplier, 2.0)
        else
            corr_multiplier = 0.5  # Default correlation multiplier
            mmc_multiplier = 2.0   # Default MMC multiplier
        end
        
        return Dict(
            :total_stake => total_stake,
            :burn_rate => burn_rate,
            :corr_multiplier => corr_multiplier,
            :mmc_multiplier => mmc_multiplier
        )
    catch e
        @warn "Failed to fetch stake information for model $model_name: $e"
        # Return defaults if API call fails
        return Dict(
            :total_stake => 0.0,
            :burn_rate => 0.25,
            :corr_multiplier => 0.5,
            :mmc_multiplier => 2.0
        )
    end
end

# Staking Write Operations

function stake_change(client::NumeraiClient, model_name::String, nmr_amount::Float64, action::String)
    """
    Change stake for a specific model.
    
    Parameters:
    - client: NumeraiClient instance
    - model_name: Name of the model to stake on
    - nmr_amount: Amount of NMR to stake/unstake
    - action: Either "increase" or "decrease"
    
    Returns:
    - Dict with stake change details or nothing on failure
    """
    
    # Validate action
    if !(action in ["increase", "decrease"])
        @error "Invalid action: $action. Must be 'increase' or 'decrease'"
        return nothing
    end
    
    # Get model ID first
    model_id = get_model_id(client, model_name)
    if isnothing(model_id)
        @error "Could not find model ID for model: $model_name"
        return nothing
    end
    
    # Get current tournament number
    tournament_number = get_current_tournament_number(client)
    if isnothing(tournament_number)
        @error "Could not determine current tournament number"
        return nothing
    end
    
    mutation = """
    mutation(\$value: String!
             \$type: String!
             \$tournamentNumber: Int!
             \$modelId: String) {
        v2ChangeStake(value: \$value
                      type: \$type
                      modelId: \$modelId
                      tournamentNumber: \$tournamentNumber) {
            dueDate
            requestedAmount
            status
            type
        }
    }
    """
    
    variables = Dict(
        "value" => string(nmr_amount),
        "type" => action,
        "tournamentNumber" => tournament_number,
        "modelId" => model_id
    )
    
    try
        result = graphql_query(client, mutation, variables)
        stake_result = get(result, :v2ChangeStake, nothing)
        
        if !isnothing(stake_result)
            @info "Stake change successful for model $model_name" action=action amount=nmr_amount
            return Dict(
                :due_date => get(stake_result, :dueDate, nothing),
                :requested_amount => get(stake_result, :requestedAmount, 0.0),
                :status => get(stake_result, :status, "unknown"),
                :type => get(stake_result, :type, action)
            )
        else
            @error "Stake change failed - no result returned"
            return nothing
        end
    catch e
        @error "Failed to change stake for model $model_name: $e"
        return nothing
    end
end

function stake_increase(client::NumeraiClient, model_name::String, nmr_amount::Float64)
    """
    Increase stake for a specific model.
    
    Parameters:
    - client: NumeraiClient instance
    - model_name: Name of the model to stake on
    - nmr_amount: Amount of NMR to add to stake
    
    Returns:
    - Dict with stake change details or nothing on failure
    """
    return stake_change(client, model_name, nmr_amount, "increase")
end

function stake_decrease(client::NumeraiClient, model_name::String, nmr_amount::Float64)
    """
    Decrease stake for a specific model.
    Note: Stake decreases have a ~4 week waiting period before NMR is returned.
    
    Parameters:
    - client: NumeraiClient instance
    - model_name: Name of the model to unstake from
    - nmr_amount: Amount of NMR to remove from stake
    
    Returns:
    - Dict with stake change details or nothing on failure
    """
    return stake_change(client, model_name, nmr_amount, "decrease")
end

function stake_drain(client::NumeraiClient, model_name::String)
    """
    Remove entire stake from a model.
    Note: This will remove ALL staked NMR with a ~4 week waiting period.
    
    Parameters:
    - client: NumeraiClient instance
    - model_name: Name of the model to drain stake from
    
    Returns:
    - Dict with stake change details or nothing on failure
    """
    # Get current stake amount
    stake_info = get_model_stakes(client, model_name)
    total_stake = get(stake_info, :total_stake, 0.0)
    
    if total_stake <= 0
        @warn "No stake to drain for model $model_name"
        return nothing
    end
    
    return stake_decrease(client, model_name, total_stake)
end

function withdraw_nmr(client::NumeraiClient, address::String, amount::Float64)
    """
    Withdraw NMR from Numerai wallet to an Ethereum address.
    Note: Account must be 30+ days old or withdrawing >0.1 NMR.
    
    Parameters:
    - client: NumeraiClient instance
    - address: Ethereum wallet address for withdrawal
    - amount: Amount of NMR to withdraw
    
    Returns:
    - Dict with withdrawal details or nothing on failure
    """
    mutation = """
    mutation(\$address: String!
             \$amount: String!
             \$currency: String!) {
        payout(address: \$address
               amount: \$amount
               currency: \$currency) {
            txHash
            status
            amount
        }
    }
    """
    
    variables = Dict(
        "address" => address,
        "amount" => string(amount),
        "currency" => "NMR"
    )
    
    try
        result = graphql_query(client, mutation, variables)
        payout_result = get(result, :payout, nothing)
        
        if !isnothing(payout_result)
            @info "Withdrawal initiated" amount=amount address=address
            return Dict(
                :tx_hash => get(payout_result, :txHash, nothing),
                :status => get(payout_result, :status, "unknown"),
                :amount => get(payout_result, :amount, 0.0)
            )
        else
            @error "Withdrawal failed - no result returned"
            return nothing
        end
    catch e
        @error "Failed to withdraw NMR: $e"
        return nothing
    end
end

function set_withdrawal_address(client::NumeraiClient, address::String)
    """
    Set the default withdrawal address for the account.
    
    Parameters:
    - client: NumeraiClient instance
    - address: Ethereum wallet address for withdrawals
    
    Returns:
    - Bool indicating success
    """
    mutation = """
    mutation(\$address: String!) {
        setWithdrawAddress(address: \$address) {
            success
        }
    }
    """
    
    variables = Dict("address" => address)
    
    try
        result = graphql_query(client, mutation, variables)
        success_result = get(result, :setWithdrawAddress, Dict())
        return get(success_result, :success, false)
    catch e
        @error "Failed to set withdrawal address: $e"
        return false
    end
end

# Helper function to get model ID
function get_model_id(client::NumeraiClient, model_name::String)
    """
    Get the model ID (UUID) for a given model name.
    
    Parameters:
    - client: NumeraiClient instance
    - model_name: Name of the model
    
    Returns:
    - Model ID string or nothing if not found
    """
    query = """
    query {
        v3UserProfile {
            models {
                name
                id
            }
        }
    }
    """
    
    try
        result = graphql_query(client, query)
        profile = result.v3UserProfile
        models = get(profile, :models, [])
        
        for model in models
            if get(model, :name, "") == model_name
                return get(model, :id, nothing)
            end
        end
        
        return nothing
    catch e
        @error "Failed to get model ID: $e"
        return nothing
    end
end

# Helper function to get current tournament number
function get_current_tournament_number(client::NumeraiClient)
    """
    Get the current tournament round number.
    
    Returns:
    - Tournament number or nothing if not found
    """
    query = """
    query {
        rounds(tournament: 8) {
            number
            openTime
            closeTime
        }
    }
    """
    
    try
        result = graphql_query(client, query)
        rounds = get(result, :rounds, [])
        
        # Check if we have any rounds
        if isempty(rounds)
            @warn "No rounds found in tournament data"
            return nothing
        end
        
        # Find the current active round
        current_time = now(UTC)
        for round in rounds
            open_time_str = get(round, :openTime, nothing)
            close_time_str = get(round, :closeTime, nothing)
            
            if !isnothing(open_time_str) && !isnothing(close_time_str)
                # Use parse_datetime_safe instead of undefined safe_parse_datetime
                open_time = parse_datetime_safe(open_time_str)
                close_time = parse_datetime_safe(close_time_str)
                
                if !isnothing(open_time) && !isnothing(close_time)
                    if current_time >= open_time && current_time <= close_time
                        return get(round, :number, nothing)
                    end
                end
            end
        end
        
        # If no active round, get the most recent one (bounds already checked above)
        return get(rounds[1], :number, nothing)
    catch e
        @error "Failed to get tournament number: $e"
        return nothing
    end
end

function get_wallet_balance(client::NumeraiClient)
    """
    Get the current wallet balance.
    
    Returns:
    - Dict with wallet information including NMR balance
    """
    query = """
    query {
        account {
            nmrBalance
            usdBalance
            status
        }
    }
    """
    
    try
        result = graphql_query(client, query)
        account = get(result, :account, Dict())
        
        return Dict(
            :nmr_balance => parse(Float64, get(account, :nmrBalance, "0")),
            :usd_balance => parse(Float64, get(account, :usdBalance, "0")),
            :status => get(account, :status, "unknown")
        )
    catch e
        @error "Failed to get wallet balance: $e"
        return Dict(
            :nmr_balance => 0.0,
            :usd_balance => 0.0,
            :status => "error"
        )
    end
end

function get_latest_submission(client::NumeraiClient)
    """
    Get the latest submission across all models for the user.
    Returns submission details including round number and timestamp.
    """
    query = """
    query {
        v3UserProfile {
            models {
                name
                latestSubmission {
                    id
                    filename
                    roundNumber
                    selectedStakeValue
                }
            }
        }
    }
    """
    
    try
        result = graphql_query(client, query)
        profile = result.v3UserProfile
        models = get(profile, :models, [])
        
        # Find the most recent submission across all models
        latest_round = 0
        latest_submission = nothing
        
        for model in models
            submission = get(model, :latestSubmission, nothing)
            if submission !== nothing
                round_num = get(submission, :roundNumber, 0)
                if round_num > latest_round
                    latest_round = round_num
                    latest_submission = submission
                    # Add model name to submission info
                    latest_submission = merge(
                        Dict(pairs(submission)),
                        Dict(:model_name => get(model, :name, "unknown"))
                    )
                end
            end
        end
        
        if latest_submission !== nothing
            # Return a named tuple with round and other info
            return (
                round = get(latest_submission, :roundNumber, 0),
                id = get(latest_submission, :id, ""),
                filename = get(latest_submission, :filename, ""),
                model_name = get(latest_submission, :model_name, "unknown")
            )
        else
            # No submissions found
            return (round = 0, id = "", filename = "", model_name = "")
        end
    catch e
        @warn "Failed to fetch latest submission: $e"
        # Return empty submission if API call fails
        return (round = 0, id = "", filename = "", model_name = "")
    end
end

function validate_submission_window(client::NumeraiClient)
    """
    Validates if submissions are currently allowed for the active round.
    Returns a detailed status about the submission window.
    """
    current_round = get_current_round(client)
    window_info = get_submission_window_info(current_round.open_time)
    
    return (
        round_number = current_round.number,
        round_type = window_info.round_type,
        is_open = window_info.is_open,
        window_end = window_info.window_end,
        time_remaining = window_info.time_remaining,
        open_time = current_round.open_time
    )
end

export NumeraiClient, get_current_round, get_model_performance, download_dataset,
       submit_predictions, get_models_for_user, get_dataset_info, get_submission_status,
       get_live_dataset_id, upload_predictions_multipart, get_model_stakes, get_latest_submission,
       validate_submission_window, stake_change, stake_increase, stake_decrease, stake_drain,
       withdraw_nmr, set_withdrawal_address, get_model_id, get_current_tournament_number,
       get_wallet_balance

end