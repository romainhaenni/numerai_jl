module GridLayout

using Term
using Term: Panel, hLine, vLine

"""
    GridLayout

A 6-column grid system for the TUI dashboard providing responsive information display
following the specification:
- Top row: Model Performance (2 cols), Staking Status (2 cols), System Status (2 cols)
- Middle row: Training Progress (3 cols), Predictions Chart (3 cols) 
- Bottom row: Events Log (full width - 6 cols)
"""

struct GridPosition
    row::Int
    col::Int
    colspan::Int
    rowspan::Int
end

struct GridItem
    panel::Panel
    position::GridPosition
end

struct Grid
    items::Vector{GridItem}
    columns::Int
    rows::Int
    width::Int
    height::Int
end

"""
    create_6_column_grid(width::Int, height::Int) -> Grid

Create a 6-column grid layout with specified terminal dimensions
"""
function create_6_column_grid(width::Int, height::Int)
    return Grid(Vector{GridItem}(), 6, 3, width, height)
end

"""
    add_panel!(grid::Grid, panel::Panel, row::Int, col::Int, colspan::Int=1, rowspan::Int=1)

Add a panel to the grid at the specified position with optional span
"""
function add_panel!(grid::Grid, panel::Panel, row::Int, col::Int, colspan::Int=1, rowspan::Int=1)
    position = GridPosition(row, col, colspan, rowspan)
    item = GridItem(panel, position)
    push!(grid.items, item)
end

"""
    calculate_panel_dimensions(grid::Grid, position::GridPosition) -> (width, height)

Calculate the actual pixel dimensions for a panel based on its grid position
"""
function calculate_panel_dimensions(grid::Grid, position::GridPosition)
    # Calculate available space after accounting for borders and spacing
    border_width = 2  # Left and right borders
    spacing_width = 1  # Space between panels
    total_spacing = (grid.columns - 1) * spacing_width
    usable_width = grid.width - total_spacing
    
    # Calculate column width
    col_width = div(usable_width, grid.columns)
    panel_width = col_width * position.colspan + (position.colspan - 1) * spacing_width
    
    # Calculate row height - distribute available height across rows
    border_height = 2  # Top and bottom borders
    row_spacing = 1   # Space between rows
    total_row_spacing = (grid.rows - 1) * row_spacing
    usable_height = grid.height - total_row_spacing - border_height
    
    # Allocate different heights for different rows based on content needs
    if position.row == 1  # Top row panels (status panels)
        row_height = div(usable_height, 4)  # Smaller status panels
    elseif position.row == 2  # Middle row (training and predictions)
        row_height = div(usable_height, 3)  # Medium height
    else  # Bottom row (events log)
        row_height = div(usable_height, 2)  # Larger for events log
    end
    
    panel_height = row_height * position.rowspan + (position.rowspan - 1) * row_spacing
    
    return (max(20, panel_width), max(8, panel_height))  # Minimum dimensions
end

"""
    render_grid(grid::Grid) -> String

Render the entire grid layout as a formatted string
"""
function render_grid(grid::Grid)
    if isempty(grid.items)
        return "Empty grid"
    end
    
    # Sort items by row, then by column for proper rendering order
    sorted_items = sort(grid.items, by=item -> (item.position.row, item.position.col))
    
    # Group items by row
    rows = Vector{Vector{GridItem}}()
    current_row = 1
    row_items = Vector{GridItem}()
    
    for item in sorted_items
        if item.position.row != current_row
            if !isempty(row_items)
                push!(rows, copy(row_items))
            end
            empty!(row_items)
            current_row = item.position.row
        end
        push!(row_items, item)
    end
    
    # Don't forget the last row
    if !isempty(row_items)
        push!(rows, row_items)
    end
    
    # Render each row
    row_strings = Vector{String}()
    
    for (row_idx, row_items) in enumerate(rows)
        # Just render panels as they are with some spacing
        rendered_panels = Vector{String}()
        
        for item in row_items
            # Convert panel to string directly - Term should handle dimensions
            panel_str = string(item.panel)
            push!(rendered_panels, panel_str)
        end
        
        # Combine panels horizontally for this row
        if length(rendered_panels) == 1
            # Single panel spans full width
            push!(row_strings, rendered_panels[1])
        else
            # Multiple panels - combine horizontally
            combined_row = combine_panels_horizontally(rendered_panels)
            push!(row_strings, combined_row)
        end
    end
    
    # Combine all rows vertically
    return join(row_strings, "\n\n")  # Add spacing between rows
end

"""
    combine_panels_horizontally(panels::Vector{String}) -> String

Combine multiple panel strings horizontally
"""
function combine_panels_horizontally(panels::Vector{String})
    if isempty(panels)
        return ""
    end
    
    if length(panels) == 1
        return panels[1]
    end
    
    # Split each panel into lines
    panel_lines = [split(panel, '\n') for panel in panels]
    
    # Find the maximum number of lines
    max_lines = maximum(length(lines) for lines in panel_lines)
    
    # Pad all panels to have the same number of lines and find max width for each panel
    panel_widths = Vector{Int}()
    
    for (i, lines) in enumerate(panel_lines)
        # Find max width for this panel
        panel_width = length(lines) > 0 ? maximum(length(line) for line in lines) : 0
        push!(panel_widths, panel_width)
        
        # Pad lines to max_lines and normalize width
        while length(lines) < max_lines
            push!(lines, repeat(" ", panel_width))
        end
        
        # Ensure all lines have consistent width
        for j in 1:length(lines)
            if length(lines[j]) < panel_width
                lines[j] = lines[j] * repeat(" ", panel_width - length(lines[j]))
            end
        end
    end
    
    # Combine lines horizontally with spacing
    combined_lines = Vector{String}()
    spacing = "  "  # Two spaces between panels
    
    for line_idx in 1:max_lines
        line_parts = String[]
        for (panel_idx, lines) in enumerate(panel_lines)
            push!(line_parts, lines[line_idx])
        end
        combined_line = join(line_parts, spacing)
        push!(combined_lines, combined_line)
    end
    
    return join(combined_lines, '\n')
end

"""
    create_dashboard_grid(panels::NamedTuple, terminal_width::Int, terminal_height::Int) -> Grid

Create a dashboard grid with the specified panel layout:
- Top row: Model Performance (2 cols), Staking Status (2 cols), System Status (2 cols)
- Middle row: Training Progress (3 cols), Predictions Chart (3 cols) 
- Bottom row: Events Log (full width - 6 cols)
"""
function create_dashboard_grid(panels::NamedTuple, terminal_width::Int=80, terminal_height::Int=40)
    grid = create_6_column_grid(terminal_width, terminal_height)
    
    # Create panels with fixed dimensions appropriate for grid layout
    # Calculate appropriate panel dimensions based on terminal size
    col_width = max(35, div(terminal_width - 10, 3))  # 3 panels per row max, with margins
    
    # Top row panels - each taking 2 columns conceptually but fixed width
    if haskey(panels, :model_performance) && panels.model_performance !== nothing
        resized_panel = create_resized_panel(panels.model_performance, col_width, 12)
        add_panel!(grid, resized_panel, 1, 1, 2, 1)  # Row 1, Col 1-2
    end
    
    if haskey(panels, :staking) && panels.staking !== nothing
        resized_panel = create_resized_panel(panels.staking, col_width, 12)
        add_panel!(grid, resized_panel, 1, 3, 2, 1)  # Row 1, Col 3-4
    end
    
    if haskey(panels, :system) && panels.system !== nothing
        resized_panel = create_resized_panel(panels.system, col_width, 12)
        add_panel!(grid, resized_panel, 1, 5, 2, 1)  # Row 1, Col 5-6
    end
    
    # Middle row panels - each taking 3 columns conceptually
    larger_width = max(45, div(terminal_width - 8, 2))  # 2 panels per row with margins
    
    if haskey(panels, :training) && panels.training !== nothing
        resized_panel = create_resized_panel(panels.training, larger_width, 14)
        add_panel!(grid, resized_panel, 2, 1, 3, 1)  # Row 2, Col 1-3
    end
    
    if haskey(panels, :predictions) && panels.predictions !== nothing
        resized_panel = create_resized_panel(panels.predictions, larger_width, 14)
        add_panel!(grid, resized_panel, 2, 4, 3, 1)  # Row 2, Col 4-6
    end
    
    # Bottom row - events log spanning full width
    if haskey(panels, :events) && panels.events !== nothing
        events_width = max(80, terminal_width - 4)  # Full width minus margins
        resized_panel = create_resized_panel(panels.events, events_width, 18)
        add_panel!(grid, resized_panel, 3, 1, 6, 1)  # Row 3, Col 1-6 (full width)
    end
    
    return grid
end

"""
    create_resized_panel(original_panel::Panel, width::Int, height::Int) -> Panel

Create a new panel with specified dimensions, copying content and style from original
"""
function create_resized_panel(original_panel::Panel, width::Int, height::Int)
    # For now, let's just return the original panel since Term.jl handles sizing internally
    # This is a simplified approach - the panel system will handle the dimensions
    return original_panel
end

"""
    get_terminal_size() -> (width, height)

Get current terminal dimensions with fallback defaults
"""
function get_terminal_size()
    try
        # Try to get actual terminal size
        width = parse(Int, read(`tput cols`, String) |> strip)
        height = parse(Int, read(`tput lines`, String) |> strip)
        return (width, height)
    catch
        # Fallback to reasonable defaults
        return (120, 40)
    end
end

export Grid, GridPosition, GridItem, create_6_column_grid, add_panel!, render_grid,
       create_dashboard_grid, get_terminal_size, calculate_panel_dimensions, create_resized_panel

end