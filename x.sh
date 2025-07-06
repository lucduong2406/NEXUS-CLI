#!/bin/bash

# Check if tmux session 'nexus' exists, if not create it
if ! tmux has-session -t nexus 2>/dev/null; then
    echo "Creating new tmux session 'nexus'"
    tmux new-session -d -s nexus
else
    echo "Session 'nexus' already exists, reusing it"
fi

# Array of node IDs
nodes=(
    13146933
    13202706
    13117577
    13060927
    13086743
    12976850
    13117578
    13175764
    13202708
    13009330
    12924775
    13086745
)

# Get list of current windows
existing_windows=$(tmux list-windows -t nexus -F "#{window_index}" 2>/dev/null | sort -n)

# If there are existing windows, kill them to start fresh
if [ -n "$existing_windows" ]; then
    echo "Clearing existing windows in session 'nexus'"
    for win in $existing_windows; do
        tmux kill-window -t nexus:$win
    done
fi

# Create a new window for each node
for i in "${!nodes[@]}"; do
    node_id=${nodes[$i]}
    
    # For the first node, use the initial window
    if [ $i -eq 0 ]; then
        echo "Starting node $node_id in initial window"
        tmux send-keys -t nexus:0 C-c C-m "clear" C-m
        tmux send-keys -t nexus:0 "nexus-network start --node-id $node_id" C-m
    else
        # Create a new window without specifying an index
        echo "Creating new window for node $node_id"
        tmux new-window -t nexus
        # Get the index of the newly created window
        new_window_index=$(tmux list-windows -t nexus -F "#{window_index}" | tail -n 1)
        tmux send-keys -t nexus:$new_window_index "nexus-network start --node-id $node_id" C-m
    fi
    
    # Rename the window to the node ID (using the current window index)
    current_window_index=$(tmux list-windows -t nexus -F "#{window_index}" | tail -n 1)
    tmux rename-window -t nexus:$current_window_index "node-$node_id"
done

# Attach to the tmux session
echo "Attaching to tmux session 'nexus'"
tmux attach-session -t nexus
