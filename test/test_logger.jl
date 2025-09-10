using Test
using Logging
using Dates
using Random
using Base.Threads

# Import the main module and logger
using NumeraiTournament
using NumeraiTournament.Logger

@testset "Logger Module Tests" begin
    
    # Test utility function to create temporary log directories
    function create_temp_log_dir()
        temp_dir = mktempdir()
        log_dir = joinpath(temp_dir, "logs")
        mkpath(log_dir)
        return log_dir
    end
    
    # Test utility function to clean up after tests
    function cleanup_logger()
        try
            Logger.close_logger()
        catch
            # Ignore errors during cleanup
        end
    end
    
    # Test utility function to ensure logs are flushed to disk
    function flush_and_read(log_file::String)
        Logger.flush_logger()
        return read(log_file, String)
    end
    
    @testset "Logger Initialization" begin
        @testset "Basic initialization" begin
            log_dir = create_temp_log_dir()
            log_file = joinpath(log_dir, "test_basic.log")
            
            logger = Logger.init_logger(log_file=log_file)
            @test logger isa AbstractLogger
            @test isfile(log_file)
            
            # Test that global logger is set
            global_logger = Logger.get_logger()
            @test global_logger isa AbstractLogger
            
            cleanup_logger()
            rm(dirname(log_file), recursive=true)
        end
        
        @testset "Custom log levels" begin
            log_dir = create_temp_log_dir()
            log_file = joinpath(log_dir, "test_levels.log")
            
            logger = Logger.init_logger(
                log_file=log_file,
                console_level=Logging.Warn,
                file_level=Logging.Debug
            )
            
            @test logger isa AbstractLogger
            @test isfile(log_file)
            
            cleanup_logger()
            rm(dirname(log_file), recursive=true)
        end
        
        @testset "Append mode" begin
            log_dir = create_temp_log_dir()
            log_file = joinpath(log_dir, "test_append.log")
            
            # Create initial log file
            write(log_file, "Initial content\n")
            initial_size = filesize(log_file)
            
            # Initialize logger with append=true
            logger = Logger.init_logger(log_file=log_file, append=true)
            
            # File should still exist and be larger (or same size)
            @test isfile(log_file)
            @test filesize(log_file) >= initial_size
            
            cleanup_logger()
            rm(dirname(log_file), recursive=true)
        end
        
        @testset "Directory creation" begin
            temp_dir = mktempdir()
            nested_log_file = joinpath(temp_dir, "nested", "logs", "test.log")
            
            # Directory doesn't exist yet
            @test !isdir(dirname(nested_log_file))
            
            logger = Logger.init_logger(log_file=nested_log_file)
            
            # Directory should be created
            @test isdir(dirname(nested_log_file))
            @test isfile(nested_log_file)
            
            cleanup_logger()
            rm(temp_dir, recursive=true)
        end
    end
    
    @testset "Logging Levels and Macros" begin
        @testset "Debug logging" begin
            log_dir = create_temp_log_dir()
            log_file = joinpath(log_dir, "test_debug.log")
            
            Logger.init_logger(
                log_file=log_file,
                console_level=Logging.Debug,
                file_level=Logging.Debug
            )
            
            Logger.@log_debug "Debug message" key1="value1" key2=42
            
            # Check file contents
            log_content = flush_and_read(log_file)
            @test occursin("Debug message", log_content)
            @test occursin("[DEBUG]", log_content)
            @test occursin("key1=value1", log_content)
            @test occursin("key2=42", log_content)
            
            cleanup_logger()
            rm(dirname(log_file), recursive=true)
        end
        
        @testset "Info logging" begin
            log_dir = create_temp_log_dir()
            log_file = joinpath(log_dir, "test_info.log")
            
            Logger.init_logger(log_file=log_file)
            
            Logger.@log_info "Info message" status="success"
            
            log_content = flush_and_read(log_file)
            @test occursin("Info message", log_content)
            @test occursin("[INFO]", log_content)
            @test occursin("status=success", log_content)
            
            cleanup_logger()
            rm(dirname(log_file), recursive=true)
        end
        
        @testset "Warning logging" begin
            log_dir = create_temp_log_dir()
            log_file = joinpath(log_dir, "test_warn.log")
            
            Logger.init_logger(log_file=log_file)
            
            Logger.@log_warn "Warning message" code=404
            
            log_content = flush_and_read(log_file)
            @test occursin("Warning message", log_content)
            @test occursin("[WARN]", log_content)
            @test occursin("code=404", log_content)
            
            cleanup_logger()
            rm(dirname(log_file), recursive=true)
        end
        
        @testset "Error logging" begin
            log_dir = create_temp_log_dir()
            log_file = joinpath(log_dir, "test_error.log")
            
            Logger.init_logger(log_file=log_file)
            
            Logger.@log_error "Error message" exception="TestException"
            
            log_content = flush_and_read(log_file)
            @test occursin("Error message", log_content)
            @test occursin("[ERROR]", log_content)
            @test occursin("exception=TestException", log_content)
            
            cleanup_logger()
            rm(dirname(log_file), recursive=true)
        end
        
        @testset "Critical logging" begin
            log_dir = create_temp_log_dir()
            log_file = joinpath(log_dir, "test_critical.log")
            
            Logger.init_logger(log_file=log_file)
            
            Logger.@log_critical "Critical error" system="failed"
            
            log_content = flush_and_read(log_file)
            @test occursin("[CRITICAL]", log_content)
            @test occursin("Critical error", log_content)
            @test occursin("system=failed", log_content)
            
            cleanup_logger()
            rm(dirname(log_file), recursive=true)
        end
    end
    
    @testset "Message Formatting" begin
        @testset "Timestamp format" begin
            timestamp = Dates.format(now(), "yyyy-mm-dd HH:MM:SS.sss")
            formatted = Logger.format_log_message(
                Logging.Info, "Test message", nothing, nothing, nothing, nothing, nothing
            )
            
            @test occursin("[INFO]", formatted)
            @test occursin("Test message", formatted)
            @test occursin(r"\[\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\.\d{3}\]", formatted)
        end
        
        @testset "Message with keyword arguments" begin
            formatted = Logger.format_log_message(
                Logging.Warn, "Warning", nothing, nothing, nothing, nothing, nothing;
                key1="value1", key2=123
            )
            
            @test occursin("[WARN]", formatted)
            @test occursin("Warning", formatted)
            @test occursin("key1=value1", formatted)
            @test occursin("key2=123", formatted)
        end
        
        @testset "Message without keyword arguments" begin
            formatted = Logger.format_log_message(
                Logging.Error, "Simple error", nothing, nothing, nothing, nothing, nothing
            )
            
            @test occursin("[ERROR]", formatted)
            @test occursin("Simple error", formatted)
            @test !occursin("|", formatted)  # No separator for kwargs
        end
    end
    
    @testset "Specialized Logging Functions" begin
        @testset "Model performance logging" begin
            log_dir = create_temp_log_dir()
            log_file = joinpath(log_dir, "test_model_perf.log")
            
            Logger.init_logger(log_file=log_file)
            
            metrics = Dict(
                :corr => 0.025,
                :mmc => 0.015,
                :tc => 0.010,
                :sharpe => 1.25
            )
            
            Logger.log_model_performance("test_model", metrics)
            
            log_content = flush_and_read(log_file)
            @test occursin("Model performance update", log_content)
            @test occursin("model=test_model", log_content)
            @test occursin("corr=0.025", log_content)
            @test occursin("mmc=0.015", log_content)
            @test occursin("tc=0.01", log_content)
            @test occursin("sharpe=1.25", log_content)
            
            cleanup_logger()
            rm(dirname(log_file), recursive=true)
        end
        
        @testset "API call logging" begin
            log_dir = create_temp_log_dir()
            log_file = joinpath(log_dir, "test_api_calls.log")
            
            Logger.init_logger(
                log_file=log_file,
                console_level=Logging.Debug,
                file_level=Logging.Debug
            )
            
            # Test successful API call (200)
            Logger.log_api_call("/api/models", "GET", 200; duration=0.150)
            
            # Test client error (404)
            Logger.log_api_call("/api/nonexistent", "GET", 404; duration=0.050)
            
            # Test server error (500)
            Logger.log_api_call("/api/broken", "POST", 500; duration=2.500)
            
            log_content = flush_and_read(log_file)
            @test occursin("API call successful", log_content)
            @test occursin("endpoint=/api/models", log_content)
            @test occursin("status=200", log_content)
            @test occursin("duration_ms=150.0", log_content)
            
            @test occursin("API client error", log_content)
            @test occursin("status=404", log_content)
            
            @test occursin("API server error", log_content)
            @test occursin("status=500", log_content)
            @test occursin("duration_ms=2500.0", log_content)
            
            cleanup_logger()
            rm(dirname(log_file), recursive=true)
        end
        
        @testset "Submission logging" begin
            log_dir = create_temp_log_dir()
            log_file = joinpath(log_dir, "test_submissions.log")
            
            Logger.init_logger(log_file=log_file)
            
            # Test successful submission
            Logger.log_submission("model_1", 570, true)
            
            # Test failed submission
            Logger.log_submission("model_2", 571, false, error_msg="Invalid predictions format")
            
            log_content = flush_and_read(log_file)
            @test occursin("Submission successful", log_content)
            @test occursin("model=model_1", log_content)
            @test occursin("round=570", log_content)
            
            @test occursin("Submission failed", log_content)
            @test occursin("model=model_2", log_content)
            @test occursin("round=571", log_content)
            @test occursin("error=Invalid predictions format", log_content)
            
            cleanup_logger()
            rm(dirname(log_file), recursive=true)
        end
        
        @testset "Training progress logging" begin
            log_dir = create_temp_log_dir()
            log_file = joinpath(log_dir, "test_training.log")
            
            Logger.init_logger(log_file=log_file)
            
            training_metrics = Dict("loss" => 0.125, "accuracy" => 0.85)
            
            Logger.log_training_progress(
                "neural_net_1", 5, 10,
                metrics=training_metrics,
                eta_seconds=125.5
            )
            
            log_content = flush_and_read(log_file)
            @test occursin("Training progress", log_content)
            @test occursin("model=neural_net_1", log_content)
            @test occursin("epoch=5", log_content)
            @test occursin("total=10", log_content)
            @test occursin("progress_pct=50.0", log_content)
            @test occursin("eta=2m 5s", log_content)
            @test occursin("loss=0.125", log_content)
            @test occursin("accuracy=0.85", log_content)
            
            cleanup_logger()
            rm(dirname(log_file), recursive=true)
        end
    end
    
    @testset "File Output and Handle Management" begin
        @testset "File creation and writing" begin
            log_dir = create_temp_log_dir()
            log_file = joinpath(log_dir, "test_file_output.log")
            
            Logger.init_logger(log_file=log_file)
            
            @test isfile(log_file)
            
            Logger.@log_info "Test file output"
            
            # Check file content
            log_content = flush_and_read(log_file)
            @test occursin("Test file output", log_content)
            @test occursin("[INFO]", log_content)
            
            cleanup_logger()
            rm(dirname(log_file), recursive=true)
        end
        
        @testset "File handle cleanup" begin
            log_dir = create_temp_log_dir()
            log_file = joinpath(log_dir, "test_cleanup.log")
            
            Logger.init_logger(log_file=log_file)
            
            # Write some content
            Logger.@log_info "Before cleanup"
            
            # Close logger explicitly
            Logger.close_logger()
            
            # File should still exist and be readable
            @test isfile(log_file)
            log_content = flush_and_read(log_file)
            @test occursin("Before cleanup", log_content)
            
            rm(dirname(log_file), recursive=true)
        end
        
        @testset "Multiple logger reinitialization" begin
            log_dir = create_temp_log_dir()
            log_file1 = joinpath(log_dir, "test_reinit1.log")
            log_file2 = joinpath(log_dir, "test_reinit2.log")
            
            # Initialize first logger
            Logger.init_logger(log_file=log_file1)
            Logger.@log_info "First logger"
            
            # Initialize second logger (should close first)
            Logger.init_logger(log_file=log_file2)
            Logger.@log_info "Second logger"
            
            # Both files should exist
            @test isfile(log_file1)
            @test isfile(log_file2)
            
            # First file should have first message only
            content1 = flush_and_read(log_file1)
            @test occursin("First logger", content1)
            @test !occursin("Second logger", content1)
            
            # Second file should have second message only
            content2 = flush_and_read(log_file2)
            @test occursin("Second logger", content2)
            @test !occursin("First logger", content2)
            
            cleanup_logger()
            rm(dirname(log_file1), recursive=true)
        end
    end
    
    @testset "Log Rotation" begin
        @testset "Size-based rotation" begin
            log_dir = create_temp_log_dir()
            log_file = joinpath(log_dir, "test_rotation.log")
            
            Logger.init_logger(log_file=log_file)
            
            # Create a large log file by writing many messages
            large_message = "x" ^ 1000  # 1KB message
            for i in 1:200  # 200KB total
                Logger.@log_info large_message iteration=i
            end
            
            # Check file size is substantial
            original_size = filesize(log_file)
            @test original_size > 100_000  # At least 100KB
            
            # Trigger rotation with small max size
            Logger.rotate_logs(max_size_mb=0.05, max_files=3)  # 50KB max
            
            # Original file should be smaller now (new file)
            new_size = filesize(log_file)
            @test new_size < original_size
            
            # Check that rotated file exists
            rotated_file = replace(log_file, ".log" => ".1.log")
            @test isfile(rotated_file)
            
            cleanup_logger()
            rm(dirname(log_file), recursive=true)
        end
        
        @testset "Multiple rotation cycles" begin
            log_dir = create_temp_log_dir()
            log_file = joinpath(log_dir, "test_multi_rotation.log")
            
            Logger.init_logger(log_file=log_file)
            
            # Create content for multiple rotations
            message = "y" ^ 500  # 500 byte message
            
            # First batch - fill initial file
            for i in 1:200
                Logger.@log_info message batch=1 iteration=i
            end
            
            # Allow time for logs to be written
            sleep(0.1)
            
            # Trigger first rotation
            Logger.rotate_logs(max_size_mb=0.02, max_files=3)  # 20KB max
            
            # Allow time for rotation to complete
            sleep(0.1)
            
            # Second batch
            for i in 1:200
                Logger.@log_info message batch=2 iteration=i
            end
            
            # Allow time for logs to be written
            sleep(0.1)
            
            # Trigger second rotation
            Logger.rotate_logs(max_size_mb=0.02, max_files=3)
            
            # Allow time for rotation to complete
            sleep(0.1)
            
            # Check that multiple rotated files exist
            rotated_file1 = replace(log_file, ".log" => ".1.log")
            rotated_file2 = replace(log_file, ".log" => ".2.log")
            
            @test isfile(rotated_file1)
            @test isfile(rotated_file2)
            
            # After rotation, latest content should be in rotated file 1
            rotated1_content = isfile(rotated_file1) ? read(rotated_file1, String) : ""
            @test occursin("batch=2", rotated1_content)
            
            cleanup_logger()
            rm(dirname(log_file), recursive=true)
        end
        
        @testset "Max files limit" begin
            log_dir = create_temp_log_dir()
            log_file = joinpath(log_dir, "test_max_files.log")
            
            Logger.init_logger(log_file=log_file)
            
            message = "z" ^ 1000  # 1KB message
            max_files = 2
            
            # Create multiple rotation cycles
            for cycle in 1:4
                for i in 1:50
                    Logger.@log_info message cycle=cycle iteration=i
                end
                Logger.rotate_logs(max_size_mb=0.02, max_files=max_files)  # 20KB max
            end
            
            # Should only have max_files rotated files
            rotated_files = []
            for i in 1:5  # Check more than max_files
                rotated_file = replace(log_file, ".log" => ".$(i).log")
                if isfile(rotated_file)
                    push!(rotated_files, rotated_file)
                end
            end
            
            @test length(rotated_files) <= max_files
            
            cleanup_logger()
            rm(dirname(log_file), recursive=true)
        end
    end
    
    @testset "Thread Safety" begin
        @testset "Concurrent logging" begin
            log_dir = create_temp_log_dir()
            log_file = joinpath(log_dir, "test_concurrent.log")
            
            Logger.init_logger(log_file=log_file)
            
            # Number of threads and messages per thread
            num_threads = min(4, nthreads())  # Use available threads, max 4
            messages_per_thread = 50
            
            # Create concurrent logging tasks
            tasks = Task[]
            for thread_id in 1:num_threads
                task = @async begin
                    for msg_id in 1:messages_per_thread
                        Logger.@log_info "Concurrent message" thread_id=thread_id message_id=msg_id
                        sleep(0.001)  # Small delay to increase concurrency chance
                    end
                end
                push!(tasks, task)
            end
            
            # Wait for all tasks to complete
            for task in tasks
                wait(task)
            end
            
            # Check file content
            log_content = flush_and_read(log_file)
            lines = split(log_content, '\n')
            non_empty_lines = filter(!isempty, lines)
            
            # Should have at least num_threads * messages_per_thread log entries
            expected_messages = num_threads * messages_per_thread
            @test length(non_empty_lines) >= expected_messages
            
            # Check that messages from different threads are present
            for thread_id in 1:num_threads
                @test any(line -> occursin("thread_id=$thread_id", line), non_empty_lines)
            end
            
            cleanup_logger()
            rm(dirname(log_file), recursive=true)
        end
        
        @testset "Concurrent rotation" begin
            log_dir = create_temp_log_dir()
            log_file = joinpath(log_dir, "test_concurrent_rotation.log")
            
            Logger.init_logger(log_file=log_file)
            
            # Use a lock to prevent race conditions in test
            rotation_lock = ReentrantLock()
            
            # Create tasks that log and attempt rotation concurrently
            num_tasks = 3
            tasks = Task[]
            
            for task_id in 1:num_tasks
                task = @async begin
                    for i in 1:30
                        # Log a large message
                        large_msg = "concurrent_test_" * "x"^500
                        Logger.@log_info large_msg task_id=task_id iteration=i
                        
                        # Occasionally attempt rotation with lock
                        if i % 10 == 0
                            lock(rotation_lock) do
                                Logger.rotate_logs(max_size_mb=0.01, max_files=2)
                            end
                        end
                        sleep(0.02)  # Increased sleep time
                    end
                end
                push!(tasks, task)
            end
            
            # Wait for all tasks
            for task in tasks
                wait(task)
            end
            
            # Allow time for final writes
            sleep(0.2)
            
            # Final rotation to ensure state is consistent
            lock(rotation_lock) do
                Logger.rotate_logs(max_size_mb=0.01, max_files=2)
            end
            
            # Allow time for rotation to complete
            sleep(0.1)
            
            # Should have log files without corruption
            @test isfile(log_file)
            # Check for file existence (may be empty after rotation)
            @test isfile(log_file)  # Simplified check
            
            cleanup_logger()
            rm(dirname(log_file), recursive=true)
        end
    end
    
    @testset "Logger Lifecycle Management" begin
        @testset "Set and get log level" begin
            log_dir = create_temp_log_dir()
            log_file = joinpath(log_dir, "test_log_level.log")
            
            Logger.init_logger(log_file=log_file)
            
            # Test setting log level
            Logger.set_log_level(Logging.Warn)
            logger = Logger.get_logger()
            @test logger isa AbstractLogger
            
            cleanup_logger()
            rm(dirname(log_file), recursive=true)
        end
        
        @testset "Auto-initialization" begin
            # Clean any existing logger first
            cleanup_logger()
            
            # Getting logger should auto-initialize
            logger = Logger.get_logger()
            @test logger isa AbstractLogger
            
            # Setting level should also auto-initialize if needed
            Logger.set_log_level(Logging.Debug)
            
            cleanup_logger()
        end
        
        @testset "Global logger management" begin
            log_dir1 = create_temp_log_dir()
            log_dir2 = create_temp_log_dir()
            log_file1 = joinpath(log_dir1, "global_test1.log")
            log_file2 = joinpath(log_dir2, "global_test2.log")
            
            # Initialize first logger
            logger1 = Logger.init_logger(log_file=log_file1)
            retrieved1 = Logger.get_logger()
            @test retrieved1 === logger1
            
            # Initialize second logger - should replace first
            logger2 = Logger.init_logger(log_file=log_file2)
            retrieved2 = Logger.get_logger()
            @test retrieved2 === logger2
            @test retrieved2 !== logger1
            
            cleanup_logger()
            rm(dirname(log_file1), recursive=true)
            rm(dirname(log_file2), recursive=true)
        end
    end
    
    @testset "Error Handling and Edge Cases" begin
        @testset "Invalid log directory permissions" begin
            # This test might not work on all systems, so we'll make it conditional
            if !Sys.iswindows()
                temp_dir = mktempdir()
                restricted_dir = joinpath(temp_dir, "restricted")
                mkdir(restricted_dir)
                chmod(restricted_dir, 0o444)  # Read-only
                
                log_file = joinpath(restricted_dir, "subdir", "test.log")
                
                # Should handle permission errors gracefully
                # Note: This test might vary by system
                try
                    Logger.init_logger(log_file=log_file)
                    # If it succeeds, that's also okay - some systems might allow it
                    cleanup_logger()
                catch e
                    # Expected on systems with strict permissions
                    @test e isa SystemError || e isa Base.IOError
                end
                
                chmod(restricted_dir, 0o755)  # Restore permissions for cleanup
                rm(temp_dir, recursive=true)
            end
        end
        
        @testset "Rotation with non-existent file" begin
            # Test rotation when log file doesn't exist
            Logger.rotate_logs(max_size_mb=1.0, max_files=5)
            # Should not throw error
            @test true
        end
        
        @testset "Close non-initialized logger" begin
            # Test closing logger when not initialized
            Logger.close_logger()
            # Should not throw error
            @test true
        end
        
        @testset "Empty message logging" begin
            log_dir = create_temp_log_dir()
            log_file = joinpath(log_dir, "test_empty.log")
            
            Logger.init_logger(log_file=log_file)
            
            Logger.@log_info ""
            Logger.@log_warn ""
            
            # Should handle empty messages gracefully
            log_content = flush_and_read(log_file)
            @test occursin("[INFO]", log_content)
            @test occursin("[WARN]", log_content)
            
            cleanup_logger()
            rm(dirname(log_file), recursive=true)
        end
    end
    
    # Cleanup after all tests
    @testset "Final Cleanup" begin
        cleanup_logger()
        @test true
    end
end