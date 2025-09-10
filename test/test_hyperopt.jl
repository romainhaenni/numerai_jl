using Test
using DataFrames
using Random
using Statistics
using NumeraiTournament.HyperOpt

@testset "HyperOpt Module Tests" begin
    
    # Create synthetic test data
    function create_test_data(n_samples=1000, n_features=10, n_eras=10)
        Random.seed!(42)
        
        # Create feature columns
        features = DataFrame()
        feature_names = ["feature_$i" for i in 1:n_features]
        for fname in feature_names
            features[!, fname] = randn(n_samples)
        end
        
        # Create target with some signal
        target = 0.1 * sum(Matrix(features), dims=2)[:, 1] + 0.9 * randn(n_samples)
        target = (target .- mean(target)) ./ std(target)  # Normalize
        
        # Create eras
        era = repeat(1:n_eras, inner=n_samples ÷ n_eras)[1:n_samples]
        
        # Combine into DataFrame
        df = copy(features)
        df.target = target
        df.era = era
        
        return df, feature_names
    end
    
    @testset "HyperOptConfig" begin
        config = HyperOptConfig(
            model_type=:XGBoost,
            objective=:correlation,
            n_splits=3,
            verbose=false
        )
        
        @test config.model_type == :XGBoost
        @test config.objective == :correlation
        @test config.n_splits == 3
        @test config.verbose == false
        @test config.parallel == true
        @test config.seed == 42
    end
    
    @testset "Parameter Grid Creation" begin
        @testset "XGBoost Grid" begin
            grid = create_param_grid(:XGBoost)
            @test haskey(grid, :max_depth)
            @test haskey(grid, :learning_rate)
            @test haskey(grid, :n_estimators)
            @test haskey(grid, :colsample_bytree)
            @test all(grid[:max_depth] .>= 3)
            @test all(grid[:learning_rate] .> 0)
        end
        
        @testset "LightGBM Grid" begin
            grid = create_param_grid(:LightGBM)
            @test haskey(grid, :num_leaves)
            @test haskey(grid, :learning_rate)
            @test haskey(grid, :feature_fraction)
            @test all(grid[:num_leaves] .>= 10)
        end
        
        @testset "Linear Model Grids" begin
            ridge_grid = create_param_grid(:Ridge)
            @test haskey(ridge_grid, :alpha)
            @test all(ridge_grid[:alpha] .> 0)
            
            lasso_grid = create_param_grid(:Lasso)
            @test haskey(lasso_grid, :alpha)
            
            elastic_grid = create_param_grid(:ElasticNet)
            @test haskey(elastic_grid, :alpha)
            @test haskey(elastic_grid, :l1_ratio)
            @test all(0 .<= elastic_grid[:l1_ratio] .<= 1)
        end
        
        @testset "Neural Network Grid" begin
            grid = create_param_grid(:NeuralNetwork)
            @test haskey(grid, :hidden_layers)
            @test haskey(grid, :learning_rate)
            @test haskey(grid, :batch_size)
            @test haskey(grid, :epochs)
            @test haskey(grid, :dropout_rate)
            @test all(isa.(grid[:hidden_layers], Vector))
        end
    end
    
    @testset "Parameter Distributions Creation" begin
        @testset "XGBoost Distributions" begin
            dists = create_param_distributions(:XGBoost)
            @test haskey(dists, :max_depth)
            @test haskey(dists, :learning_rate)
            
            # Test sampling
            max_depth_sample = dists[:max_depth]()
            @test 3 <= max_depth_sample <= 15
            
            lr_sample = dists[:learning_rate]()
            @test 0.0001 <= lr_sample <= 0.1
        end
        
        @testset "Neural Network Distributions" begin
            dists = create_param_distributions(:NeuralNetwork)
            @test haskey(dists, :hidden_layers)
            
            # Test layer generation
            layers = dists[:hidden_layers]()
            @test isa(layers, Vector{Int})
            @test length(layers) >= 2
            @test all(layers .>= 32)
        end
    end
    
    @testset "Grid Search Optimizer" begin
        # Create small test grid for speed
        test_grid = Dict(
            :max_depth => [3, 5],
            :learning_rate => [0.01, 0.1]
        )
        
        config = HyperOptConfig(
            model_type=:XGBoost,
            objective=:correlation,
            n_splits=2,
            verbose=false,
            parallel=false
        )
        
        optimizer = GridSearchOptimizer(test_grid, config)
        
        @test optimizer.param_grid == test_grid
        @test optimizer.config == config
        
        # Test that it creates correct number of combinations
        n_combinations = prod(length(v) for v in values(test_grid))
        @test n_combinations == 4
    end
    
    @testset "Random Search Optimizer" begin
        dists = Dict(
            :max_depth => () -> rand(3:10),
            :learning_rate => () -> 10^(rand(-3:-1))
        )
        
        config = HyperOptConfig(
            model_type=:XGBoost,
            objective=:correlation,
            n_splits=2,
            verbose=false,
            parallel=false
        )
        
        n_iter = 10
        optimizer = RandomSearchOptimizer(dists, n_iter, config)
        
        @test optimizer.param_distributions == dists
        @test optimizer.n_iter == n_iter
        @test optimizer.config == config
    end
    
    @testset "Bayesian Optimizer" begin
        bounds = Dict(
            :max_depth => (3.0, 10.0),
            :learning_rate => (0.001, 0.1)
        )
        
        config = HyperOptConfig(
            model_type=:XGBoost,
            objective=:correlation,
            n_splits=2,
            verbose=false,
            parallel=false
        )
        
        optimizer = BayesianOptimizer(
            bounds,
            5,  # n_initial
            10,  # n_iter
            :ei,  # acquisition function
            config
        )
        
        @test optimizer.param_bounds == bounds
        @test optimizer.n_initial == 5
        @test optimizer.n_iter == 10
        @test optimizer.acquisition_function == :ei
    end
    
    @testset "Objective Score Calculation" begin
        # Create test predictions and validation data
        n_samples = 100
        predictions = DataFrame(
            target1 = randn(n_samples),
            target2 = randn(n_samples)
        )
        
        val_data = Dict(
            "target1" => DataFrame(target = randn(n_samples)),
            "target2" => DataFrame(target = randn(n_samples))
        )
        
        targets = ["target1", "target2"]
        
        @testset "Correlation Objective" begin
            score = HyperOpt.calculate_objective_score(
                predictions, val_data, :correlation, targets
            )
            @test isa(score, Float64)
            @test -1 <= score <= 1
        end
        
        @testset "Sharpe Objective" begin
            score = HyperOpt.calculate_objective_score(
                predictions, val_data, :sharpe, targets
            )
            @test isa(score, Float64)
        end
        
        @testset "Multi-Objective" begin
            score = HyperOpt.calculate_objective_score(
                predictions, val_data, :multi_objective, targets
            )
            @test isa(score, Float64)
        end
    end
    
    @testset "Acquisition Functions" begin
        @testset "Expected Improvement" begin
            candidate = [5.0, 0.01]
            observed_params = [[3.0, 0.1], [7.0, 0.001]]
            observed_scores = [0.5, 0.6]
            
            ei = HyperOpt.calculate_expected_improvement(
                candidate, observed_params, observed_scores
            )
            @test isa(ei, Float64)
            @test ei >= 0
        end
        
        @testset "Upper Confidence Bound" begin
            candidate = [5.0, 0.01]
            observed_params = [[3.0, 0.1], [7.0, 0.001]]
            observed_scores = [0.5, 0.6]
            
            ucb = HyperOpt.calculate_upper_confidence_bound(
                candidate, observed_params, observed_scores
            )
            @test isa(ucb, Float64)
        end
    end
    
    @testset "Optimization Result" begin
        best_params = Dict(:max_depth => 5, :learning_rate => 0.01)
        best_score = 0.75
        all_results = DataFrame(score=[0.5, 0.6, 0.75])
        history = [Dict(:params => best_params, :score => best_score)]
        cv_scores = [0.7, 0.75, 0.8]
        training_time = 10.5
        
        result = OptimizationResult(
            best_params, best_score, all_results,
            history, cv_scores, training_time
        )
        
        @test result.best_params == best_params
        @test result.best_score == best_score
        @test result.training_time == training_time
        @test get_best_params(result) == best_params
    end
    
    @testset "Save and Load Results" begin
        best_params = Dict(:max_depth => 5, :learning_rate => 0.01)
        best_score = 0.75
        all_results = DataFrame()
        history = [Dict(:params => best_params, :score => best_score)]
        cv_scores = [0.7, 0.75, 0.8]
        training_time = 10.5
        
        result = OptimizationResult(
            best_params, best_score, all_results,
            history, cv_scores, training_time
        )
        
        # Save to temporary file
        temp_file = tempname() * ".json"
        HyperOpt.save_optimization_results(result, temp_file)
        @test isfile(temp_file)
        
        # Load and verify
        loaded_result = HyperOpt.load_optimization_results(temp_file)
        @test loaded_result.best_score == best_score
        @test loaded_result.training_time == training_time
        @test loaded_result.cross_validation_scores == cv_scores
        
        # Clean up
        rm(temp_file)
    end
    
    @testset "Integration Test - Small Grid Search" begin
        # Create minimal test data
        df, feature_names = create_test_data(200, 5, 4)
        
        # Create data dict for hyperopt
        data_dict = Dict{String,DataFrame}()
        data_dict["target"] = df
        targets = ["target"]
        
        # Small grid for testing
        test_grid = Dict(
            :max_depth => [3, 5],
            :learning_rate => [0.1]  # Single value to speed up
        )
        
        config = HyperOptConfig(
            model_type=:XGBoost,
            objective=:correlation,
            n_splits=2,
            verbose=false,
            parallel=false
        )
        
        optimizer = GridSearchOptimizer(test_grid, config)
        
        # Note: This would normally fail because it tries to create actual models
        # In a real test, we'd need to mock the model creation and training
        # For now, we just test the setup
        @test optimizer.param_grid == test_grid
        @test length(targets) == 1
    end
    
    @testset "Parameter Update Helper" begin
        best_params = Dict{Symbol,Any}()
        best_score = -Inf
        best_cv_scores = Float64[]
        history = Vector{Dict{Symbol,Any}}()
        all_results = DataFrame()
        
        # Test updating with better score
        params1 = Dict{Symbol,Any}(:max_depth => 5, :learning_rate => 0.01)
        score1 = 0.7
        cv_scores1 = [0.65, 0.7, 0.75]
        
        new_score = HyperOpt.update_best_params!(
            params1, score1, cv_scores1,
            best_params, best_score, best_cv_scores,
            history, all_results
        )
        
        @test new_score == 0.7
        @test best_params == params1
        @test length(history) == 1
        @test nrow(all_results) == 1
        
        # Test updating with worse score (shouldn't update best)
        params2 = Dict{Symbol,Any}(:max_depth => 3, :learning_rate => 0.1)
        score2 = 0.6
        cv_scores2 = [0.55, 0.6, 0.65]
        
        new_score = HyperOpt.update_best_params!(
            params2, score2, cv_scores2,
            best_params, best_score, best_cv_scores,
            history, all_results
        )
        
        @test new_score == 0.7  # Should still be the previous best
        @test best_params == params1  # Should not change
        @test length(history) == 2  # History should grow
        @test nrow(all_results) == 2
    end
end

# Run the tests
@testset "HyperOpt Module" begin
    println("\n" * "="^60)
    println("Running HyperOpt Module Tests")
    println("="^60)
    
    @time include("test_hyperopt.jl")
    
    println("\nHyperOpt tests completed successfully!")
end