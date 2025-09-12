# Numerai Tournament Examples

This directory contains example scripts demonstrating various features of the Numerai Tournament Julia implementation.

## Prerequisites

Before running any examples:

1. Set up your API credentials in `.env`:
```bash
NUMERAI_PUBLIC_ID=your_public_id_here
NUMERAI_SECRET_KEY=your_secret_key_here
```

2. Ensure Julia dependencies are installed:
```bash
julia --project=.. -e "using Pkg; Pkg.instantiate()"
```

## Available Examples

### 1. Basic Training (`basic_training.jl`)

A simple example showing the complete workflow:
- Download tournament data
- Train an XGBoost model  
- Generate predictions
- Evaluate performance
- Save predictions for submission

**Run:**
```bash
julia --project=.. examples/basic_training.jl
```

**What you'll learn:**
- How to use the API client
- Basic ML pipeline setup
- Data loading and preprocessing
- Model training and evaluation

### 2. Ensemble Models (`ensemble_models.jl`)

Advanced example demonstrating model ensembling:
- Train multiple model types (XGBoost, LightGBM, EvoTrees, Ridge)
- Different neutralization strategies
- Ensemble weight optimization
- Performance comparison

**Run:**
```bash
julia --project=.. examples/ensemble_models.jl
```

**What you'll learn:**
- Training diverse models
- Combining predictions effectively
- Weight optimization techniques
- Performance analysis

### 3. Dashboard Demo (`dashboard_demo.jl`)

Interactive dashboard demonstration:
- Connect to Numerai API
- Display model performance
- Show system status
- Simulate real-time updates

**Run:**
```bash
julia --project=.. examples/dashboard_demo.jl
```

**What you'll learn:**
- Dashboard components
- Real-time monitoring
- API integration
- System performance tracking

To run the full interactive dashboard:
```bash
julia -t 16 ../numerai
```

### 4. Hyperparameter Optimization (`hyperopt_example.jl`)

Optimize model hyperparameters:
- Grid search
- Random search
- Bayesian optimization
- Performance comparison

**Run:**
```bash
julia --project=.. examples/hyperopt_example.jl
```

**What you'll learn:**
- Parameter search spaces
- Different optimization strategies
- Efficiency vs thoroughness tradeoffs
- Results analysis

## Tips for Running Examples

1. **Start Small**: Begin with `basic_training.jl` to understand the workflow

2. **Data Download**: First run will download ~2GB of data. Subsequent runs use cached data.

3. **Computation Time**: 
   - Basic training: 5-10 minutes
   - Ensemble: 15-30 minutes
   - Hyperopt: 20-40 minutes (depending on trials)

4. **Memory Usage**: Examples are optimized for 8GB+ RAM. Reduce `sample_pct` in config if needed.

5. **Multi-threading**: Use multiple threads for better performance:
   ```bash
   julia -t 8 --project=.. examples/ensemble_models.jl
   ```

## Customization

Each example can be customized by modifying:

- **Model Parameters**: Adjust hyperparameters in the model configs
- **Feature Sets**: Choose between "small", "medium", or "all" features
- **Neutralization**: Adjust neutralization proportion (0.0 to 1.0)
- **Data Sampling**: Change sample sizes for faster iteration

## Troubleshooting

### API Errors
- Verify credentials in `.env` file
- Check internet connection
- Ensure you have models created on numer.ai

### Memory Issues
- Reduce sample size in training
- Use "small" feature set
- Close other applications

### Performance
- Use multiple Julia threads: `julia -t auto`
- Enable GPU if available (Metal.jl for Mac)
- Reduce model complexity for testing

## Next Steps

After running the examples:

1. Customize model parameters based on your strategy
2. Implement your own feature engineering
3. Set up automated submissions with the scheduler
4. Monitor performance with the dashboard

## Additional Resources

- [Numerai Tournament Docs](https://docs.numer.ai)
- [Julia ML Tutorials](https://juliaml.github.io)
- Main README: `../README.md`
- Configuration: `../config.toml`