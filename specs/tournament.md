## Numerai Tournament Mechanics Summary

### **Tournament Structure**

**Numerai is a hedge fund tournament** where data scientists compete to predict stock market movements using obfuscated financial data. The fund manages **$500M+ in assets** with institutional backing from JPMorgan, using the crowd-sourced predictions to trade global equities.

### **Data Format**

- **Obfuscated features**: ~1500 anonymized financial indicators binned into quintiles (0, 0.25, 0.5, 0.75, 1.0)
- **No real company identities**: Each row represents an anonymous stock at a specific time
- **Era-based organization**: Data grouped into weekly time periods called "eras"
- **Target variable**: Represents 20-day forward returns (also normalized to quintiles)
- **Multiple targets available**: 20+ different target variations (cyrus, victor, teager, etc.)

### **Tournament Rounds**

- **5 rounds per week**: Tuesday through Saturday
- **Weekend rounds**: Most important (Saturday 18:00 UTC - Monday 14:30 UTC)
- **Submission window**: ~60 hours for weekend rounds, ~30 hours for daily rounds
- **Live data**: New obfuscated stock data released each round for prediction

### **Prediction Requirements**

- **Format**: Predictions must be between 0 and 1 (rank normalized)
- **Coverage**: Must predict for all stocks in the live dataset
- **No missing values**: Every stock requires a prediction
- **Single submission**: One prediction file per model per round

### **Scoring System**

**Primary Metrics:**
- **CORR (Correlation)**: Spearman correlation between predictions and actual returns
- **MMC (Meta Model Contribution)**: Unique value added beyond the stake-weighted ensemble
- **FNC (Feature Neutral Correlation)**: Correlation after neutralizing feature exposure
- **TC (True Contribution)**: Direct contribution to fund returns

**Scoring Timeline:**
- **4-day lag**: Initial scoring begins after market data settles
- **20-day evaluation**: Full scoring period matches target horizon
- **Daily updates**: Scores update as market data becomes available
- **Final resolution**: ~4 weeks after submission

### **Staking Mechanism**

- **NMR cryptocurrency**: Numeraire token used for staking
- **Risk/reward system**: Stake NMR on model performance
- **Positive correlation = earnings**: Good predictions increase stake
- **Negative correlation = burns**: Poor predictions decrease stake
- **Compounding available**: Earnings can be automatically restaked

### **Payout Structure**

**Current formula (2024)**: `Payout = Stake × (0.5×CORR + 2×MMC)`
- Emphasis on unique contributions over raw correlation
- Daily payout calculations during scoring period
- Both positive and negative payouts possible

### **Reputation System**

- **Consistency rewards**: Top 1000 staked models by reputation earn 50% bonus
- **20-round minimum**: Must maintain stake for 20+ rounds to build reputation
- **Leaderboard rankings**: Based on various metrics (CORR, MMC, returns)

### **Data Releases**

**V5 "Atlas" Dataset (Latest)**:
- 3x more features than previous versions
- 5x more training data
- 20x more target variations
- Historical data from 2003 onwards

### **Model Constraints**

- **No external data**: Only provided features can be used
- **No feature engineering from IDs**: Stock identities must remain anonymous
- **Time-aware validation**: Must respect era boundaries (no future leakage)
- **Computational limits**: Reasonable model complexity for weekly predictions

### **Risk Factors**

- **Regime changes**: Market conditions shift over time
- **Overfitting risk**: Training and live distributions differ
- **Feature exposure**: High correlation with raw features increases volatility
- **Drawdown potential**: Extended periods of negative performance possible
- **Stake burns**: Can lose significant NMR during poor performance

### **Competition Goals**

The tournament aims to:
- Build a "metamodel" from diverse predictions
- Generate uncorrelated returns for the hedge fund
- Reward models that provide unique market insights
- Maintain long-term stable performance over quick gains
- Create the world's first crowd-sourced quantitative hedge fund

### **Participation Requirements**

- **Numerai account**: Free registration required
- **API credentials**: Public and secret keys for submissions
- **Regular participation**: Models become inactive without submissions
- **No mandatory staking**: Can participate without risking NMR
- **Multiple models allowed**: Users can manage portfolio of models

The tournament essentially transforms the stock market prediction problem into a data science competition where participants never know which real companies they're predicting, focusing purely on pattern recognition in anonymized data.

## Essential Numerai Documentation URLs

### **Official Documentation**
- **Main Documentation Hub**: https://docs.numer.ai/
- **Tournament Overview**: https://docs.numer.ai/tournament/learn
- **Data Documentation**: https://docs.numer.ai/numerai-tournament/data
- **Models Guide**: https://docs.numer.ai/numerai-tournament/models
- **Submissions Guide**: https://docs.numer.ai/numerai-tournament/submissions
- **Staking Guide**: https://docs.numer.ai/numerai-tournament/staking

### **Scoring Metrics**
- **Meta Model Contribution (MMC)**: https://docs.numer.ai/numerai-tournament/scoring/meta-model-contribution-mmc
- **Feature Neutral Correlation (FNC)**: https://docs.numer.ai/numerai-tournament/scoring/feature-neutral-correlation
- **True Contribution (TC)**: https://docs.numer.ai/numerai-tournament/scoring/true-contribution

### **API Documentation**
- **API Overview**: https://docs.numer.ai/numerai-tournament/api
- **GraphQL API Endpoint**: https://api-tournament.numer.ai

### **Code Resources**
- **Official Example Scripts**: https://github.com/numerai/example-scripts
- **NumerAPI Python Client**: https://github.com/numerai/numerapi
- **Feature Neutralization Example**: https://github.com/numerai/example-scripts/blob/master/feature_neutralization.ipynb
- **Official Numerai GitHub**: https://github.com/numerai

### **Community Resources**
- **Numerai Forum**: https://forum.numer.ai/
- **Numerai Tournament Website**: https://numer.ai/
- **Numerai Hedge Fund Site**: https://numerai.fund/
- **Community Tools**: https://docs.numer.ai/community/community-built-products

### **Data Downloads**
- **Current Datasets**: https://numer.ai/data/
- **V5 Data Direct Links**:
  - Training: https://numerai-public-datasets.s3-us-west-2.amazonaws.com/v5.0/train.parquet
  - Validation: https://numerai-public-datasets.s3-us-west-2.amazonaws.com/v5.0/validation.parquet
  - Features Metadata: https://numerai-public-datasets.s3-us-west-2.amazonaws.com/v5.0/features.json

### **Important Forum Discussions**
- **V5 "Atlas" Data Release**: https://forum.numer.ai/t/v5-atlas-data-release/7576
- **MMC Staking Changes**: https://forum.numer.ai/t/mmc-staking-starts-jan-2-2024/6827
- **Era-wise Cross-Validation**: https://forum.numer.ai/t/era-wise-time-series-cross-validation/791
- **LGBM Hyperparameter Optimization**: https://forum.numer.ai/t/hyperparameters-optimization-for-small-lgbm-models/6693

### **Educational Resources**
- **Numerai YouTube Channel**: https://www.youtube.com/@Numerai
- **Office Hours Recordings**: https://docs.numer.ai/office-hours-with-arbitrage
- **Tournament Structure Guide**: https://docs.numer.ai/community/community-built-products/numerai-structure

### **Model Performance**
- **Live Leaderboard**: https://numer.ai/leaderboard
- **Model Performance API**: https://numer.ai/api/v2/model-performance

These URLs provide comprehensive coverage of tournament mechanics, implementation details, scoring systems, and community best practices necessary for building a competitive Numerai tournament system.
