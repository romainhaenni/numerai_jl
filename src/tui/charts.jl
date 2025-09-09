module Charts

using UnicodePlots
using Statistics

function create_sparkline(values::Vector{Float64}; width::Int=40, height::Int=8)::String
    if isempty(values)
        return "No data"
    end
    
    if length(values) == 1
        return "Single value: $(round(values[1], digits=4))"
    end
    
    plt = lineplot(
        1:length(values), values,
        width=width, height=height,
        border=:none,
        labels=false,
        canvas=BrailleCanvas
    )
    
    return string(plt)
end

function create_bar_chart(labels::Vector{String}, values::Vector{Float64}; 
                         width::Int=40)::String
    if isempty(labels) || isempty(values)
        return "No data"
    end
    
    plt = barplot(
        labels, values,
        width=width,
        border=:solid
    )
    
    return string(plt)
end

function create_histogram(values::Vector{Float64}; bins::Int=20, width::Int=40)::String
    if isempty(values)
        return "No data"
    end
    
    plt = histogram(
        values,
        nbins=bins,
        width=width,
        border=:solid
    )
    
    return string(plt)
end

function create_performance_sparklines(performance_history::Dict{String, Vector{Float64}};
                                      width::Int=30, height::Int=4)::Dict{String, String}
    sparklines = Dict{String, String}()
    
    for (metric, values) in performance_history
        if !isempty(values)
            sparklines[metric] = create_sparkline(values, width=width, height=height)
        else
            sparklines[metric] = "No history"
        end
    end
    
    return sparklines
end

function format_correlation_bar(corr::Float64; width::Int=20)::String
    if isnan(corr)
        return "─" ^ width
    end
    
    normalized = (corr + 1.0) / 2.0
    filled = Int(round(normalized * width))
    
    bar = "█" ^ filled * "░" ^ (width - filled)
    
    color = if corr > 0.02
        "\e[32m"
    elseif corr < -0.02
        "\e[31m"
    else
        "\e[33m"
    end
    
    return "$(color)$(bar)\e[0m $(round(corr, digits=4))"
end

function create_mini_chart(values::Vector{Float64}; width::Int=10)::String
    if isempty(values)
        return " " ^ width
    end
    
    min_val, max_val = extrema(values)
    if min_val == max_val
        return "─" ^ width
    end
    
    chars = ['▁', '▂', '▃', '▄', '▅', '▆', '▇', '█']
    
    result = ""
    for val in values[max(1, end-width+1):end]
        normalized = (val - min_val) / (max_val - min_val)
        idx = Int(ceil(normalized * 8))
        idx = clamp(idx, 1, 8)
        result *= chars[idx]
    end
    
    return result
end

export create_sparkline, create_bar_chart, create_histogram,
       create_performance_sparklines, format_correlation_bar, create_mini_chart

end