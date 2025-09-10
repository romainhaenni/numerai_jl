module Database

using SQLite
using DataFrames
using Dates
using JSON3
using ..Logger: @log_info, @log_warn, @log_error, @log_debug

export DatabaseConnection, init_database, close_database
export save_model_performance, get_model_performance, get_latest_performance
export save_submission, get_submissions, get_latest_submission
export save_round_data, get_round_data
export save_stake_history, get_stake_history
export save_training_run, get_training_runs
export cleanup_old_data, vacuum_database

mutable struct DatabaseConnection
    db::SQLite.DB
    path::String
end

function init_database(; db_path::String = "data/tournament.db")
    # Create directory if it doesn't exist
    db_dir = dirname(db_path)
    if !isdir(db_dir) && !isempty(db_dir)
        mkpath(db_dir)
    end
    
    db = SQLite.DB(db_path)
    conn = DatabaseConnection(db, db_path)
    
    # Create tables
    create_tables(conn)
    
    # Create indexes for performance
    create_indexes(conn)
    
    @log_info "Database initialized" path=db_path
    
    return conn
end

function create_tables(conn::DatabaseConnection)
    # Model performance history table
    SQLite.execute(conn.db, """
        CREATE TABLE IF NOT EXISTS model_performance (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            model_name TEXT NOT NULL,
            round_number INTEGER NOT NULL,
            correlation REAL,
            mmc REAL,
            tc REAL,
            fnc REAL,
            sharpe REAL,
            payout REAL,
            stake_value REAL,
            rank INTEGER,
            percentile REAL,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            UNIQUE(model_name, round_number)
        )
    """)
    
    # Submissions table
    SQLite.execute(conn.db, """
        CREATE TABLE IF NOT EXISTS submissions (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            model_name TEXT NOT NULL,
            round_number INTEGER NOT NULL,
            submission_id TEXT,
            filename TEXT,
            status TEXT,
            validation_correlation REAL,
            validation_sharpe REAL,
            submitted_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            UNIQUE(model_name, round_number)
        )
    """)
    
    # Round data table
    SQLite.execute(conn.db, """
        CREATE TABLE IF NOT EXISTS rounds (
            round_number INTEGER PRIMARY KEY,
            open_time TIMESTAMP,
            close_time TIMESTAMP,
            resolve_time TIMESTAMP,
            round_type TEXT,
            dataset_url TEXT,
            features_url TEXT,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )
    """)
    
    # Stake history table
    SQLite.execute(conn.db, """
        CREATE TABLE IF NOT EXISTS stake_history (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            model_name TEXT NOT NULL,
            round_number INTEGER NOT NULL,
            action TEXT NOT NULL, -- 'increase', 'decrease', 'compound'
            amount REAL NOT NULL,
            balance_before REAL,
            balance_after REAL,
            transaction_hash TEXT,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )
    """)
    
    # Training runs table
    SQLite.execute(conn.db, """
        CREATE TABLE IF NOT EXISTS training_runs (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            model_name TEXT NOT NULL,
            model_type TEXT NOT NULL,
            round_number INTEGER,
            training_time_seconds REAL,
            validation_score REAL,
            test_score REAL,
            feature_importance TEXT, -- JSON string
            hyperparameters TEXT, -- JSON string
            dataset_version TEXT,
            num_features INTEGER,
            num_samples INTEGER,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )
    """)
    
    # Predictions archive table
    SQLite.execute(conn.db, """
        CREATE TABLE IF NOT EXISTS predictions_archive (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            model_name TEXT NOT NULL,
            round_number INTEGER NOT NULL,
            era TEXT NOT NULL,
            prediction_value REAL NOT NULL,
            actual_target REAL,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )
    """)
    
    # Model configurations table
    SQLite.execute(conn.db, """
        CREATE TABLE IF NOT EXISTS model_configs (
            model_name TEXT PRIMARY KEY,
            config_json TEXT NOT NULL,
            active BOOLEAN DEFAULT 1,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )
    """)
    
    @log_debug "Database tables created successfully"
end

function create_indexes(conn::DatabaseConnection)
    # Performance indexes
    SQLite.execute(conn.db, """
        CREATE INDEX IF NOT EXISTS idx_perf_model_round 
        ON model_performance(model_name, round_number DESC)
    """)
    
    SQLite.execute(conn.db, """
        CREATE INDEX IF NOT EXISTS idx_perf_round 
        ON model_performance(round_number DESC)
    """)
    
    # Submissions indexes
    SQLite.execute(conn.db, """
        CREATE INDEX IF NOT EXISTS idx_sub_model_round 
        ON submissions(model_name, round_number DESC)
    """)
    
    # Stake history indexes
    SQLite.execute(conn.db, """
        CREATE INDEX IF NOT EXISTS idx_stake_model_created 
        ON stake_history(model_name, created_at DESC)
    """)
    
    # Training runs indexes
    SQLite.execute(conn.db, """
        CREATE INDEX IF NOT EXISTS idx_train_model_created 
        ON training_runs(model_name, created_at DESC)
    """)
    
    @log_debug "Database indexes created successfully"
end

function close_database(conn::DatabaseConnection)
    SQLite.close(conn.db)
    @log_info "Database connection closed" path=conn.path
end

# Model performance functions
function save_model_performance(conn::DatabaseConnection, data::Dict)
    query = """
        INSERT OR REPLACE INTO model_performance 
        (model_name, round_number, correlation, mmc, tc, fnc, sharpe, 
         payout, stake_value, rank, percentile)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    """
    
    SQLite.execute(conn.db, query, [
        data[:model_name],
        data[:round_number],
        get(data, :correlation, nothing),
        get(data, :mmc, nothing),
        get(data, :tc, nothing),
        get(data, :fnc, nothing),
        get(data, :sharpe, nothing),
        get(data, :payout, nothing),
        get(data, :stake_value, nothing),
        get(data, :rank, nothing),
        get(data, :percentile, nothing)
    ])
    
    @log_debug "Model performance saved" model=data[:model_name] round=data[:round_number]
end

function get_model_performance(conn::DatabaseConnection, model_name::String; 
                              limit::Int = 100)
    query = """
        SELECT * FROM model_performance 
        WHERE model_name = ?
        ORDER BY round_number DESC
        LIMIT ?
    """
    
    result = DBInterface.execute(conn.db, query, [model_name, limit]) |> DataFrame
    return result
end

function get_latest_performance(conn::DatabaseConnection, model_name::String)
    query = """
        SELECT * FROM model_performance 
        WHERE model_name = ?
        ORDER BY round_number DESC
        LIMIT 1
    """
    
    result = DBInterface.execute(conn.db, query, [model_name]) |> DataFrame
    return nrow(result) > 0 ? result[1, :] : nothing
end

# Submission functions
function save_submission(conn::DatabaseConnection, data::Dict)
    query = """
        INSERT OR REPLACE INTO submissions 
        (model_name, round_number, submission_id, filename, status, 
         validation_correlation, validation_sharpe)
        VALUES (?, ?, ?, ?, ?, ?, ?)
    """
    
    SQLite.execute(conn.db, query, [
        data[:model_name],
        data[:round_number],
        get(data, :submission_id, nothing),
        get(data, :filename, nothing),
        get(data, :status, "pending"),
        get(data, :validation_correlation, nothing),
        get(data, :validation_sharpe, nothing)
    ])
    
    @log_debug "Submission saved" model=data[:model_name] round=data[:round_number]
end

function get_submissions(conn::DatabaseConnection, model_name::String; 
                        limit::Int = 100)
    query = """
        SELECT * FROM submissions 
        WHERE model_name = ?
        ORDER BY round_number DESC
        LIMIT ?
    """
    
    result = DBInterface.execute(conn.db, query, [model_name, limit]) |> DataFrame
    return result
end

function get_latest_submission(conn::DatabaseConnection, model_name::String)
    query = """
        SELECT * FROM submissions 
        WHERE model_name = ?
        ORDER BY round_number DESC
        LIMIT 1
    """
    
    result = DBInterface.execute(conn.db, query, [model_name]) |> DataFrame
    return nrow(result) > 0 ? result[1, :] : nothing
end

# Round data functions
function save_round_data(conn::DatabaseConnection, data::Dict)
    query = """
        INSERT OR REPLACE INTO rounds 
        (round_number, open_time, close_time, resolve_time, round_type, 
         dataset_url, features_url)
        VALUES (?, ?, ?, ?, ?, ?, ?)
    """
    
    SQLite.execute(conn.db, query, [
        data[:round_number],
        get(data, :open_time, nothing),
        get(data, :close_time, nothing),
        get(data, :resolve_time, nothing),
        get(data, :round_type, nothing),
        get(data, :dataset_url, nothing),
        get(data, :features_url, nothing)
    ])
    
    @log_debug "Round data saved" round=data[:round_number]
end

function get_round_data(conn::DatabaseConnection, round_number::Int)
    query = """
        SELECT * FROM rounds 
        WHERE round_number = ?
    """
    
    result = DBInterface.execute(conn.db, query, [round_number]) |> DataFrame
    return nrow(result) > 0 ? result[1, :] : nothing
end

# Stake history functions
function save_stake_history(conn::DatabaseConnection, data::Dict)
    query = """
        INSERT INTO stake_history 
        (model_name, round_number, action, amount, balance_before, 
         balance_after, transaction_hash)
        VALUES (?, ?, ?, ?, ?, ?, ?)
    """
    
    SQLite.execute(conn.db, query, [
        data[:model_name],
        data[:round_number],
        data[:action],
        data[:amount],
        get(data, :balance_before, nothing),
        get(data, :balance_after, nothing),
        get(data, :transaction_hash, nothing)
    ])
    
    @log_info "Stake history saved" model=data[:model_name] action=data[:action] amount=data[:amount]
end

function get_stake_history(conn::DatabaseConnection, model_name::String; 
                          limit::Int = 100)
    query = """
        SELECT * FROM stake_history 
        WHERE model_name = ?
        ORDER BY created_at DESC
        LIMIT ?
    """
    
    result = DBInterface.execute(conn.db, query, [model_name, limit]) |> DataFrame
    return result
end

# Training run functions
function save_training_run(conn::DatabaseConnection, data::Dict)
    query = """
        INSERT INTO training_runs 
        (model_name, model_type, round_number, training_time_seconds, 
         validation_score, test_score, feature_importance, hyperparameters,
         dataset_version, num_features, num_samples)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    """
    
    SQLite.execute(conn.db, query, [
        data[:model_name],
        data[:model_type],
        get(data, :round_number, nothing),
        get(data, :training_time_seconds, nothing),
        get(data, :validation_score, nothing),
        get(data, :test_score, nothing),
        get(data, :feature_importance, nothing) !== nothing ? 
            JSON3.write(data[:feature_importance]) : nothing,
        get(data, :hyperparameters, nothing) !== nothing ? 
            JSON3.write(data[:hyperparameters]) : nothing,
        get(data, :dataset_version, nothing),
        get(data, :num_features, nothing),
        get(data, :num_samples, nothing)
    ])
    
    @log_info "Training run saved" model=data[:model_name] type=data[:model_type]
end

function get_training_runs(conn::DatabaseConnection, model_name::String; 
                          limit::Int = 100)
    query = """
        SELECT * FROM training_runs 
        WHERE model_name = ?
        ORDER BY created_at DESC
        LIMIT ?
    """
    
    result = DBInterface.execute(conn.db, query, [model_name, limit]) |> DataFrame
    
    # Note: JSON fields are stored as strings and can be parsed by the caller if needed
    # This avoids type conversion issues in DataFrames
    
    return result
end

# Cleanup functions
function cleanup_old_data(conn::DatabaseConnection; days_to_keep::Int = 365)
    cutoff_date = now() - Day(days_to_keep)
    
    # Clean old predictions archive
    SQLite.execute(conn.db, """
        DELETE FROM predictions_archive 
        WHERE created_at < ?
    """, [cutoff_date])
    
    # Clean old training runs
    SQLite.execute(conn.db, """
        DELETE FROM training_runs 
        WHERE created_at < ?
        AND id NOT IN (
            SELECT id FROM training_runs 
            WHERE model_name IN (SELECT DISTINCT model_name FROM training_runs)
            GROUP BY model_name
            ORDER BY created_at DESC
            LIMIT 10
        )
    """, [cutoff_date])
    
    @log_info "Old data cleaned up" days_kept=days_to_keep
end

function vacuum_database(conn::DatabaseConnection)
    SQLite.execute(conn.db, "VACUUM")
    @log_info "Database vacuumed" path=conn.path
end

# Analytics functions
function get_performance_summary(conn::DatabaseConnection, model_name::String)
    query = """
        SELECT 
            COUNT(*) as total_rounds,
            AVG(correlation) as avg_corr,
            AVG(mmc) as avg_mmc,
            AVG(tc) as avg_tc,
            AVG(sharpe) as avg_sharpe,
            SUM(payout) as total_payout,
            MAX(correlation) as max_corr,
            MIN(correlation) as min_corr
        FROM model_performance
        WHERE model_name = ?
    """
    
    result = DBInterface.execute(conn.db, query, [model_name]) |> DataFrame
    return nrow(result) > 0 ? result[1, :] : nothing
end

function get_all_models(conn::DatabaseConnection)
    query = """
        SELECT DISTINCT model_name 
        FROM model_performance
        ORDER BY model_name
    """
    
    result = DBInterface.execute(conn.db, query) |> DataFrame
    return result.model_name
end

export get_performance_summary, get_all_models, get_latest_submission

end # module