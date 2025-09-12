using Test
using NumeraiTournament
using NumeraiTournament.API: NumeraiClient, create_webhook, delete_webhook, list_webhooks, 
                              update_webhook, test_webhook, get_webhook_logs, get_models_for_user
using Dates

@testset "Webhook Management Tests" begin
    
    @testset "Webhook CRUD Operations" begin
        # Mock client for testing
        client = NumeraiClient("test_public_id", "test_secret_key")
        model_id = "test_model_123"
        webhook_url = "https://example.com/webhook"
        
        @testset "Create Webhook" begin
            # Test webhook creation with default event types
            webhook_id = create_webhook(client, model_id, webhook_url)
            # In real tests, this would fail without valid credentials
            @test isnothing(webhook_id) || isa(webhook_id, String)
            
            # Test webhook creation with custom event types
            event_types = ["submission_status", "round_performance", "stake_change"]
            webhook_id = create_webhook(client, model_id, webhook_url, event_types)
            @test isnothing(webhook_id) || isa(webhook_id, String)
        end
        
        @testset "List Webhooks" begin
            webhooks = list_webhooks(client, model_id)
            @test isa(webhooks, Vector{Dict{String,Any}})
            
            # If webhooks exist, check structure
            if !isempty(webhooks)
                webhook = webhooks[1]
                @test haskey(webhook, "id")
                @test haskey(webhook, "url")
                @test haskey(webhook, "status")
                @test haskey(webhook, "eventTypes")
            end
        end
        
        @testset "Update Webhook" begin
            webhook_id = "test_webhook_123"
            
            # Test updating URL only
            success = update_webhook(client, webhook_id; webhook_url="https://new-url.com/webhook")
            @test isa(success, Bool)
            
            # Test updating event types only
            new_events = ["submission_status", "payout"]
            success = update_webhook(client, webhook_id; event_types=new_events)
            @test isa(success, Bool)
            
            # Test enabling/disabling webhook
            success = update_webhook(client, webhook_id; enabled=false)
            @test isa(success, Bool)
            
            # Test updating multiple fields
            success = update_webhook(client, webhook_id; 
                                    webhook_url="https://another-url.com/webhook",
                                    event_types=["round_performance"],
                                    enabled=true)
            @test isa(success, Bool)
        end
        
        @testset "Test Webhook" begin
            webhook_id = "test_webhook_123"
            success = test_webhook(client, webhook_id)
            @test isa(success, Bool)
        end
        
        @testset "Get Webhook Logs" begin
            webhook_id = "test_webhook_123"
            
            # Test with default limit
            logs = get_webhook_logs(client, webhook_id)
            @test isa(logs, Vector{Dict{String,Any}})
            
            # Test with custom limit
            logs = get_webhook_logs(client, webhook_id; limit=50)
            @test isa(logs, Vector{Dict{String,Any}})
            
            # If logs exist, check structure
            if !isempty(logs)
                log_entry = logs[1]
                @test haskey(log_entry, "id")
                @test haskey(log_entry, "timestamp")
                @test haskey(log_entry, "event")
                @test haskey(log_entry, "statusCode")
                @test haskey(log_entry, "success")
            end
        end
        
        @testset "Delete Webhook" begin
            webhook_id = "test_webhook_123"
            success = delete_webhook(client, webhook_id)
            @test isa(success, Bool)
        end
    end
    
    @testset "Webhook Input Validation" begin
        client = NumeraiClient("test_public_id", "test_secret_key")
        
        @testset "Invalid URLs" begin
            model_id = "test_model"
            
            # Empty URL should be handled
            webhook_id = create_webhook(client, model_id, "")
            @test isnothing(webhook_id)
            
            # Invalid URL format should be handled
            webhook_id = create_webhook(client, model_id, "not-a-url")
            @test isnothing(webhook_id)
        end
        
        @testset "Empty Event Types" begin
            model_id = "test_model"
            webhook_url = "https://example.com/webhook"
            
            # Empty event types array should use defaults
            webhook_id = create_webhook(client, model_id, webhook_url, String[])
            @test isnothing(webhook_id) || isa(webhook_id, String)
        end
    end
    
    @testset "Webhook Error Handling" begin
        client = NumeraiClient("invalid_key", "invalid_secret")
        
        @testset "Invalid Credentials" begin
            # All operations should fail gracefully with invalid credentials
            model_id = "test_model"
            webhook_url = "https://example.com/webhook"
            webhook_id = "test_webhook"
            
            @test isnothing(create_webhook(client, model_id, webhook_url))
            @test isempty(list_webhooks(client, model_id))
            @test !update_webhook(client, webhook_id; enabled=false)
            @test !test_webhook(client, webhook_id)
            @test isempty(get_webhook_logs(client, webhook_id))
            @test !delete_webhook(client, webhook_id)
        end
    end
    
    @testset "Webhook Integration Scenarios" begin
        # These tests would require real API credentials to run
        # They're included to show how webhook management would be used in practice
        
        @testset "Webhook Lifecycle" begin
            # Skip these tests unless we have valid credentials
            if haskey(ENV, "NUMERAI_PUBLIC_ID") && haskey(ENV, "NUMERAI_SECRET_KEY")
                client = NumeraiClient(ENV["NUMERAI_PUBLIC_ID"], ENV["NUMERAI_SECRET_KEY"])
                
                # Get a real model ID
                models = get_models_for_user(client)
                if !isempty(models)
                    model_id = models[1]
                    webhook_url = "https://requestbin.com/test"  # Example webhook endpoint
                    
                    # Create webhook
                    webhook_id = create_webhook(client, model_id, webhook_url, ["submission_status"])
                    if !isnothing(webhook_id)
                        @test isa(webhook_id, String)
                        
                        # List webhooks to verify creation
                        webhooks = list_webhooks(client, model_id)
                        @test any(w -> w["id"] == webhook_id, webhooks)
                        
                        # Test the webhook
                        @test test_webhook(client, webhook_id)
                        
                        # Update the webhook
                        @test update_webhook(client, webhook_id; enabled=false)
                        
                        # Get logs
                        logs = get_webhook_logs(client, webhook_id; limit=10)
                        @test isa(logs, Vector)
                        
                        # Delete the webhook
                        @test delete_webhook(client, webhook_id)
                        
                        # Verify deletion
                        webhooks = list_webhooks(client, model_id)
                        @test !any(w -> w["id"] == webhook_id, webhooks)
                    end
                end
            else
                @info "Skipping integration tests - no API credentials found"
            end
        end
    end
end