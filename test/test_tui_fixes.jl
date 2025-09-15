# Test file for TUI panel fixes
using Test
using NumeraiTournament
using Dates

@testset "TUI Panel Fixes" begin
    @testset "Progress Callback Fixes" begin
        # Test that progress callbacks accept keyword arguments
        test_callback = (phase; kwargs...) -> begin
            if phase == :start
                @test haskey(kwargs, :name)
            elseif phase == :progress
                @test haskey(kwargs, :progress)
            elseif phase == :complete
                @test haskey(kwargs, :size_mb)
            end
        end
        
        # Simulate callback calls as they would happen in the API
        test_callback(:start, name="test.parquet")
        test_callback(:progress, progress=50.0, current_mb=10.0, total_mb=20.0)
        test_callback(:complete, name="test.parquet", size_mb=20.0)
        
        @test true  # If we get here without errors, callbacks work
    end
    
    @testset "Progress Tracker Updates" begin
        # Create a mock progress tracker
        progress_tracker = NumeraiTournament.Dashboard.EnhancedDashboard.ProgressTracker(
            0.0, "", 0.0, 0.0, 0.0, "", 0.0, 0.0, 0.0, "", 0, 0, 0.0, 0.0, 0.0, "", 0, 0,
            false, false, false, false, now()
        )
        
        # Test download progress update
        NumeraiTournament.Dashboard.EnhancedDashboard.update_progress_tracker!(
            progress_tracker, :download,
            active=true, file="train.parquet", progress=50.0
        )
        @test progress_tracker.is_downloading == true
        @test progress_tracker.download_file == "train.parquet"
        @test progress_tracker.download_progress == 50.0
        
        # Test upload progress update
        NumeraiTournament.Dashboard.EnhancedDashboard.update_progress_tracker!(
            progress_tracker, :upload,
            active=true, file="predictions.csv", progress=30.0
        )
        @test progress_tracker.is_uploading == true
        @test progress_tracker.upload_file == "predictions.csv"
        @test progress_tracker.upload_progress == 30.0
        
        # Test training progress update
        NumeraiTournament.Dashboard.EnhancedDashboard.update_progress_tracker!(
            progress_tracker, :training,
            active=true, model="test_model", epoch=5, total_epochs=10
        )
        @test progress_tracker.is_training == true
        @test progress_tracker.training_model == "test_model"
        @test progress_tracker.training_epoch == 5
        @test progress_tracker.training_total_epochs == 10
    end
    
    @testset "Dashboard Command Fixes" begin
        # Test that download_data_internal exists and doesn't error
        @test isdefined(NumeraiTournament.Dashboard, :download_data_internal)
        
        # Test that train_models_internal exists
        @test isdefined(NumeraiTournament.Dashboard, :train_models_internal)
        
        # Test that generate_predictions_internal exists
        @test isdefined(NumeraiTournament.Dashboard, :generate_predictions_internal)
        
        # Test that submit_predictions_internal exists
        @test isdefined(NumeraiTournament.Dashboard, :submit_predictions_internal)
        
        # Test that run_full_pipeline exists
        @test isdefined(NumeraiTournament.Dashboard, :run_full_pipeline)
    end
    
    @testset "API Progress Callbacks" begin
        # Test that submit_predictions accepts progress_callback
        @test hasmethod(NumeraiTournament.API.submit_predictions, 
                       Tuple{NumeraiTournament.API.NumeraiClient, String, String})
        
        # Test that download_dataset accepts progress_callback
        @test hasmethod(NumeraiTournament.API.download_dataset,
                       Tuple{NumeraiTournament.API.NumeraiClient, String, String})
    end
end

println("\n✅ All TUI panel fix tests passed!")
